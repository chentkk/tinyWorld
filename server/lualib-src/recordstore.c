/*
 * lualib-src/recordstore.c
 * C Record 存储(第一版, 支持 int/string 字段):
 *   - 固定 schema, 行按 key 动态插入 / 删除
 *   - 行内字段走连续数组, dirty 合并成 add/remove/set ops
 *
 * Lua API:
 *   rec = recordstore.new(def)
 *   key = recordstore.keyOf(rec, rowDataTable)
 *   row = recordstore.add(rec, rowDataTable)
 *   row = recordstore.get(rec, key)
 *   recordstore.remove(rec, key)
 *   recordstore.set(rec, key, field, value)
 *   ops = recordstore.flush(rec)
 *   data = recordstore.dump(rec)
 */

#define _GNU_SOURCE
#include <lua.h>
#include <lauxlib.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <math.h>
#include <pthread.h>

#define RECSTORE_META      "recordstore"
#define RECSTORE_ROW_META  "recordstore.row"

#define STR_INLINE_SIZE 32

enum {
    PROP_BOOL = 1,
    PROP_INT = 2,
    PROP_INT64 = 3,
    PROP_FLOAT = 4,
    PROP_DOUBLE = 5,
    PROP_STRING = 6,
};

typedef struct {
    char *name;
    int type;        /* PROP_* */
    int key;         /* 是否主键字段 */
    int sync_none;   /* f.sync == "none": flush 时不下发该字段 */
    bool def_bool;
    int32_t def_int;
    int64_t def_int64;
    float def_float;
    double def_double;
    char *def_s;   /* NULL */
} rfield;

/* 值单元: 按字段类型使用对应成员 */
typedef struct {
    int type;
    union {
        bool b;
        int32_t i;
        int64_t i64;
        float f;
        double d;
    } num;
    struct {
        char in[STR_INLINE_SIZE];
        char *heap;
    } str;
} rvalue;

typedef struct {
    int used;      /* 0 empty, 1 occupied, 2 tombstone */
    char *key;
    int idx;
} rslot;

#define OP_ADD 1
#define OP_REMOVE 2
#define OP_SET 3

typedef struct {
    int type;
    char *key;
    int row;
    uint8_t *dirty;  /* OP_SET: 每个字段变更标记 */
} rec_op;

typedef struct {
    rfield *fields;
    int nfield;
    int sync_none;   /* def.sync == "none" */
    int *name_idx;   /* 字段名哈希表 */
    char *name;      /* record def name(类名) */
} rec_desc;

typedef struct {
    rec_desc *desc;
    rvalue *rows;  /* cap * nfield */
    uint8_t *set;  /* cap * nfield: 字段是否显式赋值 */
    char **keys;   /* cap */
    int nrows;
    int cap;
    rslot *slots;
    int slot_cap;
    int slot_used;
    int *free_rows;  /* 已删除行索引 */
    int free_n;
    int *order_rows;  /* 插入顺序(row index) */
    int order_n;
    int order_cap;

    rec_op *ops;
    int op_cap;
    int op_n;
    rslot *op_slots;    /* key -> ops 数组下标哈希表 */
    int op_slot_cap;
    int op_slot_used;
    int host_ref;    /* LUA_REGISTRYINDEX 引用, -1 无 */
    int facade_ref;  /* facade(Record 实例)引用, -1 无 */
} record_store;

typedef struct {
    record_store *rec;
    int row_idx;
} record_row;

static int field_type_of(const char *t) {
    if (t == NULL) return PROP_INT;
    if (strcmp(t, "bool") == 0) return PROP_BOOL;
    if (strcmp(t, "int") == 0) return PROP_INT;
    if (strcmp(t, "int64") == 0) return PROP_INT64;
    if (strcmp(t, "float") == 0) return PROP_FLOAT;
    if (strcmp(t, "double") == 0 || strcmp(t, "number") == 0) return PROP_DOUBLE;
    if (strcmp(t, "string") == 0) return PROP_STRING;
    return PROP_INT;
}

static unsigned int strhash(const char *s) {
    unsigned int h = 5381;
    while (*s) {
        h = (h * 33) ^ (unsigned char)(*s);
        s++;
    }
    return h;
}

static int find_field_idx(rec_desc *d, const char *field) {
    unsigned int h = strhash(field);
    int slot = h & 255;
    while (d->name_idx[slot]) {
        int idx = d->name_idx[slot] - 1;
        if (strcmp(d->fields[idx].name, field) == 0) return idx;
        slot = (slot + 1) & 255;
    }
    return -1;
}

static record_store *check_rec(lua_State *L, int idx) {
    record_store *r = (record_store *)lua_touserdata(L, idx);
    if (r == NULL) luaL_error(L, "expected recordstore userdata");
    return r;
}

static void value_free(rvalue *v) {
    if (v->str.heap) free(v->str.heap);
    memset(v, 0, sizeof(*v));
    v->type = PROP_INT;
}

static void value_from_lua(lua_State *L, int idx, rfield *f, rvalue *v) {
    value_free(v);
    v->type = f->type;
    switch (f->type) {
        case PROP_BOOL: v->num.b = lua_toboolean(L, idx); break;
        case PROP_INT: v->num.i = (int32_t)lua_tointegerx(L, idx, NULL); break;
        case PROP_INT64: v->num.i64 = (int64_t)lua_tointegerx(L, idx, NULL); break;
        case PROP_FLOAT: v->num.f = (float)lua_tonumberx(L, idx, NULL); break;
        case PROP_DOUBLE: v->num.d = lua_tonumberx(L, idx, NULL); break;
        case PROP_STRING: {
            size_t len = 0;
            const char *str = lua_tolstring(L, idx, &len);
            if (str) {
                if (len < STR_INLINE_SIZE) {
                    memcpy(v->str.in, str, len);
                    v->str.in[len] = '\0';
                } else {
                    v->str.heap = strndup(str, len);
                }
            }
            break;
        }
        default: break;
    }
}

static void value_to_lua(lua_State *L, rfield *f, rvalue *v) {
    switch (f->type) {
        case PROP_BOOL: lua_pushboolean(L, v->num.b); break;
        case PROP_INT: lua_pushinteger(L, (lua_Integer)v->num.i); break;
        case PROP_INT64: lua_pushinteger(L, (lua_Integer)v->num.i64); break;
        case PROP_FLOAT: lua_pushnumber(L, (lua_Number)v->num.f); break;
        case PROP_DOUBLE: {
            double dv = v->num.d;
            if (isfinite(dv) && dv >= (double)LUA_MININTEGER && dv <= (double)LUA_MAXINTEGER) {
                lua_Integer iv = (lua_Integer)dv;
                if ((double)iv == dv) {
                    lua_pushinteger(L, iv);
                    break;
                }
            }
            lua_pushnumber(L, (lua_Number)dv);
            break;
        }
        case PROP_STRING:
            if (v->str.heap) lua_pushstring(L, v->str.heap);
            else lua_pushstring(L, v->str.in[0] ? v->str.in : "");
            break;
        default: lua_pushnil(L); break;
    }
}

static rvalue *cell_at(record_store *r, int row, int field) {
    return &r->rows[row * r->desc->nfield + field];
}

static int cell_set(record_store *r, int row, int field) {
    return r->set[row * r->desc->nfield + field];
}

static void cell_mark(record_store *r, int row, int field) {
    r->set[row * r->desc->nfield + field] = 1;
}

/* 未显式赋值的字段读出 nil, 显式赋值的字段按类型输出 */
static void push_field_value(lua_State *L, record_store *r, int row, int idx) {
    if (!cell_set(r, row, idx)) {
        lua_pushnil(L);
        return;
    }
    value_to_lua(L, &r->desc->fields[idx], cell_at(r, row, idx));
}

static void init_default(rfield *f, rvalue *v) {
    memset(v, 0, sizeof(*v));
    v->type = f->type;
    switch (f->type) {
        case PROP_BOOL: v->num.b = f->def_bool; break;
        case PROP_INT: v->num.i = f->def_int; break;
        case PROP_INT64: v->num.i64 = f->def_int64; break;
        case PROP_FLOAT: v->num.f = f->def_float; break;
        case PROP_DOUBLE: v->num.d = f->def_double; break;
        case PROP_STRING:
            if (f->def_s) {
                size_t len = strlen(f->def_s);
                if (len < STR_INLINE_SIZE) {
                    memcpy(v->str.in, f->def_s, len);
                    v->str.in[len] = '\0';
                } else {
                    v->str.heap = strdup(f->def_s);
                }
            }
            break;
        default: break;
    }
}

static void null_row_cells(record_store *r, int row) {
    for (int i = 0; i < r->desc->nfield; i++) {
        init_default(&r->desc->fields[i], cell_at(r, row, i));
        r->set[row * r->desc->nfield + i] = 0;
    }
}

static void ensure_cap(record_store *r) {
    if (r->nrows < r->cap) return;
    int newcap = r->cap * 2;
    r->rows = (rvalue *)realloc(r->rows, (size_t)r->desc->nfield * newcap * sizeof(rvalue));
    r->set = (uint8_t *)realloc(r->set, (size_t)r->desc->nfield * newcap * sizeof(uint8_t));
    r->keys = (char **)realloc(r->keys, (size_t)newcap * sizeof(char *));
    for (int i = r->cap; i < newcap; i++) r->keys[i] = NULL;
    memset(r->rows + (size_t)r->cap * r->desc->nfield, 0,
           (size_t)(newcap - r->cap) * r->desc->nfield * sizeof(rvalue));
    memset(r->set + (size_t)r->cap * r->desc->nfield, 0,
           (size_t)(newcap - r->cap) * r->desc->nfield * sizeof(uint8_t));
    r->cap = newcap;
}

static void rehash_slots(record_store *r, int newcap) {
    rslot *old = r->slots;
    int oldcap = r->slot_cap;
    rslot *new = (rslot *)calloc((size_t)newcap, sizeof(rslot));

    for (int i = 0; i < oldcap; i++) {
        if (old[i].used == 1) {
            const char *key = old[i].key;
            unsigned int h = strhash(key);
            int j = h & (newcap - 1);
            while (new[j].used == 1) j = (j + 1) & (newcap - 1);
            new[j].used = 1;
            new[j].key = (char *)key;    /* 复用字符串所有权 */
            new[j].idx = old[i].idx;
        }
    }
    free(old);
    r->slots = new;
    r->slot_cap = newcap;
}

static void ensure_slots(record_store *r) {
    if (r->slot_cap < 64) {
        r->slot_cap = 64;
        r->slots = (rslot *)realloc(r->slots, (size_t)r->slot_cap * sizeof(rslot));
        memset(r->slots, 0, (size_t)r->slot_cap * sizeof(rslot));
    }
    if ((r->slot_used + 1) * 4 >= r->slot_cap) {
        rehash_slots(r, r->slot_cap * 2);
    }
}

static int find_key_slot(record_store *r, const char *key) {
    unsigned int h = strhash(key);
    int i = h & (r->slot_cap - 1);
    while (r->slots[i].used) {
        if (r->slots[i].used == 1 && strcmp(r->slots[i].key, key) == 0) return i;
        i = (i + 1) & (r->slot_cap - 1);
    }
    return -1;
}

static int store_add_row(record_store *r, const char *key, int *out_row) {
    ensure_cap(r);
    int row;
    if (r->free_n > 0) {
        row = r->free_rows[--r->free_n];
    } else {
        row = r->nrows;
        r->nrows++;
    }
    r->keys[row] = strdup(key);
    null_row_cells(r, row);

    ensure_slots(r);
    unsigned int h = strhash(key);
    int i = h & (r->slot_cap - 1);
    while (r->slots[i].used == 1) i = (i + 1) & (r->slot_cap - 1);
    r->slots[i].used = 1;
    r->slots[i].key = strdup(key);
    r->slots[i].idx = row;
    r->slot_used++;

    if (r->order_n >= r->order_cap) {
        r->order_cap *= 2;
        r->order_rows = (int *)realloc(r->order_rows, (size_t)r->order_cap * sizeof(int));
    }
    r->order_rows[r->order_n++] = row;

    *out_row = row;
    return row;
}

static void free_slot_row(record_store *r, int slot) {
    int row = r->slots[slot].idx;
    for (int f = 0; f < r->desc->nfield; f++) {
        value_free(cell_at(r, row, f));
        r->set[row * r->desc->nfield + f] = 0;
    }
    free(r->keys[row]);
    r->keys[row] = NULL;
    free(r->slots[slot].key);
    r->slots[slot].key = NULL;
    r->slots[slot].used = 2; /* tombstone */
    r->free_rows = (int *)realloc(r->free_rows, (size_t)(r->free_n + 1) * sizeof(int));
    r->free_rows[r->free_n++] = row;

    /* 从插入顺序中移除(前移, 与旧 Lua table.remove 一致) */
    for (int i = 0; i < r->order_n; i++) {
        if (r->order_rows[i] == row) {
            memmove(&r->order_rows[i], &r->order_rows[i + 1],
                    (size_t)(r->order_n - i - 1) * sizeof(int));
            r->order_n--;
            break;
        }
    }
}

/* ---------- pending ops ---------- */

static void op_map_ensure(record_store *r) {
    if (r->op_slot_cap >= 16) return;
    r->op_slot_cap = 64;
    r->op_slots = (rslot *)calloc((size_t)r->op_slot_cap, sizeof(rslot));
}

static void op_map_rehash(record_store *r, int newcap) {
    rslot *old = r->op_slots;
    int oldcap = r->op_slot_cap;
    rslot *new = (rslot *)calloc((size_t)newcap, sizeof(rslot));

    int live = 0;
    for (int i = 0; i < oldcap; i++) {
        if (old[i].used == 1) {
            unsigned int h = strhash(old[i].key);
            int j = h & (newcap - 1);
            while (new[j].used == 1) j = (j + 1) & (newcap - 1);
            new[j] = old[i];       /* 转移 key 所有权 */
            live++;
        }
    }
    free(old);
    r->op_slots = new;
    r->op_slot_cap = newcap;
    r->op_slot_used = live;
}

static int op_map_slot(record_store *r, const char *key) {
    unsigned int h = strhash(key);
    int i = h & (r->op_slot_cap - 1);
    while (r->op_slots[i].used) {
        if (r->op_slots[i].used == 1 && strcmp(r->op_slots[i].key, key) == 0) return i;
        i = (i + 1) & (r->op_slot_cap - 1);
    }
    return -1;
}

static void op_map_insert(record_store *r, const char *key, int op_idx) {
    op_map_ensure(r);
    if ((r->op_slot_used + 1) * 4 >= r->op_slot_cap) {
        op_map_rehash(r, r->op_slot_cap * 2);
    }
    unsigned int h = strhash(key);
    int i = h & (r->op_slot_cap - 1);
    while (r->op_slots[i].used == 1) {
        if (strcmp(r->op_slots[i].key, key) == 0) {
            r->op_slots[i].idx = op_idx;
            return;
        }
        i = (i + 1) & (r->op_slot_cap - 1);
    }
    r->op_slots[i].used = 1;
    r->op_slots[i].key = strdup(key);
    r->op_slots[i].idx = op_idx;
    r->op_slot_used++;
}

static void op_map_remove(record_store *r, const char *key) {
    if (r->op_slot_cap == 0) return;
    int slot = op_map_slot(r, key);
    if (slot < 0) return;
    free(r->op_slots[slot].key);
    r->op_slots[slot].key = NULL;
    r->op_slots[slot].used = 2; /* tombstone */
}

static void op_map_clear(record_store *r) {
    if (r->op_slot_cap == 0) return;
    for (int i = 0; i < r->op_slot_cap; i++) {
        if (r->op_slots[i].used == 1) free(r->op_slots[i].key);
    }
    memset(r->op_slots, 0, (size_t)r->op_slot_cap * sizeof(rslot));
    r->op_slot_used = 0;
}

static rec_op *op_append(record_store *r, int type, const char *key, int row, int field) {
    if (r->op_n >= r->op_cap) {
        r->op_cap *= 2;
        r->ops = (rec_op *)realloc(r->ops, (size_t)r->op_cap * sizeof(rec_op));
    }
    rec_op *op = &r->ops[r->op_n];
    op->type = type;
    op->key = strdup(key);
    op->row = row;
    op->dirty = (uint8_t *)calloc((size_t)r->desc->nfield, 1);
    if (field >= 0) op->dirty[field] = 1;
    op_map_insert(r, key, r->op_n);
    r->op_n++;
    return op;
}

static int op_find_by_key(record_store *r, const char *key) {
    if (r->op_slot_cap == 0) return -1;
    int slot = op_map_slot(r, key);
    return slot < 0 ? -1 : r->op_slots[slot].idx;
}

static void op_free(rec_op *op) {
    free(op->key); op->key = NULL;
    free(op->dirty); op->dirty = NULL;
}

static void op_remove_at(record_store *r, int idx) {
    op_map_remove(r, r->ops[idx].key);
    op_free(&r->ops[idx]);
    int last = r->op_n - 1;
    if (idx != last) {
        r->ops[idx] = r->ops[last];
        op_map_insert(r, r->ops[idx].key, idx);
    }
    r->op_n--;
}

/* ---------- Lua binding: record ---------- */


/* ---------------- record def 共享(按类名索引) ---------------- */

/* desc 缓存: C 进程级开放寻址哈希表, 多个 Lua VM 共享, O(1) 查找 */
typedef struct {
    char *name;
    rec_desc *desc;
} rec_desc_slot;

static rec_desc_slot *g_desc_slots = NULL;
static int g_desc_slot_cap = 0;
static int g_desc_used = 0;

static void rec_desc_rehash(int newcap) {
    rec_desc_slot *old = g_desc_slots;
    int oldcap = g_desc_slot_cap;
    rec_desc_slot *nw = (rec_desc_slot *)calloc((size_t)newcap, sizeof(rec_desc_slot));

    for (int i = 0; i < oldcap; i++) {
        if (old[i].name) {
            unsigned int h = strhash(old[i].name);
            int j = h & (newcap - 1);
            while (nw[j].name) j = (j + 1) & (newcap - 1);
            nw[j] = old[i];   /* 转移 name 所有权 */
        }
    }
    free(old);
    g_desc_slots = nw;
    g_desc_slot_cap = newcap;
}

static rec_desc *rec_desc_find(const char *name) {
    if (g_desc_slot_cap == 0) return NULL;
    unsigned int h = strhash(name);
    int i = h & (g_desc_slot_cap - 1);
    while (g_desc_slots[i].name) {
        if (strcmp(g_desc_slots[i].name, name) == 0) return g_desc_slots[i].desc;
        i = (i + 1) & (g_desc_slot_cap - 1);
    }
    return NULL;
}

static void rec_desc_insert(const char *name, rec_desc *d) {
    if (g_desc_slot_cap == 0) {
        g_desc_slot_cap = 64;
        g_desc_slots = (rec_desc_slot *)calloc(64, sizeof(rec_desc_slot));
    }
    if ((g_desc_used + 1) * 4 >= g_desc_slot_cap) {
        rec_desc_rehash(g_desc_slot_cap * 2);
    }

    unsigned int h = strhash(name);
    int i = h & (g_desc_slot_cap - 1);
    while (g_desc_slots[i].name) i = (i + 1) & (g_desc_slot_cap - 1);
    g_desc_slots[i].name = strdup(name);
    g_desc_slots[i].desc = d;
    g_desc_used++;
}

static pthread_mutex_t g_desc_lock = PTHREAD_MUTEX_INITIALIZER;

/* 只在显式 define 阶段构建 desc; 不惰性注册 */
static rec_desc *rec_desc_build(lua_State *L, int def_idx) {
    lua_getfield(L, def_idx, "name");
    const char *name = luaL_optstring(L, -1, "record");

    lua_getfield(L, def_idx, "fields");
    luaL_checktype(L, -1, LUA_TTABLE);
    int nfield = (int)luaL_len(L, -1);
    int fields_idx = lua_gettop(L);

    rec_desc *d = (rec_desc *)calloc(1, sizeof(rec_desc));
    d->nfield = nfield;
    d->name = strdup(name);
    d->fields = (rfield *)calloc((size_t)(nfield > 0 ? nfield : 1), sizeof(rfield));
    d->name_idx = (int *)calloc(256, sizeof(int));

    for (int i = 0; i < nfield; i++) {
        lua_rawgeti(L, fields_idx, i + 1);
        lua_getfield(L, -1, "name");
        const char *fname = luaL_checkstring(L, -1);
        lua_getfield(L, -2, "type");
        const char *type = lua_tostring(L, -1);
        d->fields[i].name = strdup(fname);
        d->fields[i].type = field_type_of(type);
        lua_pop(L, 2);

        lua_getfield(L, -1, "sync");
        d->fields[i].sync_none = lua_isstring(L, -1) && strcmp(lua_tostring(L, -1), "none") == 0;
        lua_pop(L, 1);

        lua_getfield(L, -1, "default");
        if (!lua_isnil(L, -1)) {
            switch (d->fields[i].type) {
                case PROP_BOOL: d->fields[i].def_bool = lua_toboolean(L, -1); break;
                case PROP_INT: d->fields[i].def_int = (int32_t)lua_tointegerx(L, -1, NULL); break;
                case PROP_INT64: d->fields[i].def_int64 = (int64_t)lua_tointegerx(L, -1, NULL); break;
                case PROP_FLOAT: d->fields[i].def_float = (float)lua_tonumberx(L, -1, NULL); break;
                case PROP_DOUBLE: d->fields[i].def_double = lua_tonumberx(L, -1, NULL); break;
                case PROP_STRING: {
                    size_t len = 0;
                    const char *ds = lua_tolstring(L, -1, &len);
                    if (ds) d->fields[i].def_s = strndup(ds, len);
                    break;
                }
                default: break;
            }
        }
        lua_pop(L, 1);

        unsigned int h = strhash(fname);
        int slot = h & 255;
        while (d->name_idx[slot]) slot = (slot + 1) & 255;
        d->name_idx[slot] = i + 1;
        lua_pop(L, 1);
    }

    lua_pop(L, 1); /* fields */

    lua_getfield(L, def_idx, "sync");
    d->sync_none = lua_isstring(L, -1) && strcmp(lua_tostring(L, -1), "none") == 0;
    lua_pop(L, 1);

    lua_getfield(L, def_idx, "keyFields");
    if (lua_istable(L, -1)) {
        int nk = (int)luaL_len(L, -1);
        for (int k = 1; k <= nk; k++) {
            lua_rawgeti(L, -1, k);
            const char *keyname = lua_tostring(L, -1);
            if (keyname) {
                for (int i = 0; i < nfield; i++) {
                    if (strcmp(d->fields[i].name, keyname) == 0) {
                        d->fields[i].key = 1;
                        break;
                    }
                }
            }
            lua_pop(L, 1);
        }
    }
    lua_pop(L, 1);

    lua_pop(L, 1); /* name */
    return d;
}

/* 线程安全注册; 重复 define 返回同一 desc。
 * define 只应在服务启动阶段由 def 注册流程调用; new 阶段只查不建。*/
static int l_record_define(lua_State *L) {
    const char *name = luaL_checkstring(L, 1);
    luaL_checktype(L, 2, LUA_TTABLE);

    rec_desc *d = rec_desc_build(L, 2);
    /* d->name 由 build 从 def.name 提取; 传入的 className 必须一致 */
    if (strcmp(d->name, name) != 0) {
        /* 释放误构建对象, 直接报错 */
        /* 简化: 直接使用 className 作为 key, 修正 name */
        free(d->name);
        d->name = strdup(name);
    }

    pthread_mutex_lock(&g_desc_lock);
    rec_desc *existing = rec_desc_find(name);
    if (existing) {
        pthread_mutex_unlock(&g_desc_lock);
        /* 丢弃重复构建的 desc */
        for (int i = 0; i < d->nfield; i++) {
            free(d->fields[i].name);
            free(d->fields[i].def_s);
        }
        free(d->fields);
        free(d->name_idx);
        free(d->name);
        free(d);
        return 0;
    }
    rec_desc_insert(name, d);
    pthread_mutex_unlock(&g_desc_lock);
    return 0;
}

static int l_new_rec(lua_State *L) {
    const char *name = luaL_checkstring(L, 1);

    pthread_mutex_lock(&g_desc_lock);
    rec_desc *d = rec_desc_find(name);
    pthread_mutex_unlock(&g_desc_lock);

    if (!d) {
        return luaL_error(L, "recordstore: record def not registered: %s", name);
    }
    int nfield = d->nfield;

    record_store *r = (record_store *)lua_newuserdata(L, sizeof(record_store));
    memset(r, 0, sizeof(*r));
    r->desc = d;
    r->host_ref = LUA_NOREF;
    r->facade_ref = LUA_NOREF;
    r->op_cap = 16;
    r->cap = 16;
    r->slot_cap = 64;

    r->rows = (rvalue *)calloc((size_t)nfield * r->cap, sizeof(rvalue));
    r->set = (uint8_t *)calloc((size_t)nfield * r->cap, sizeof(uint8_t));
    r->keys = (char **)calloc((size_t)r->cap, sizeof(char *));
    r->slots = (rslot *)calloc((size_t)r->slot_cap, sizeof(rslot));
    r->ops = (rec_op *)calloc((size_t)r->op_cap, sizeof(rec_op));
    r->order_cap = 16;
    r->order_rows = (int *)calloc((size_t)r->order_cap, sizeof(int));

    /* facade(第二个参数, Record 实例)与 host */
    if (lua_gettop(L) >= 2 && !lua_isnil(L, 2)) {
        lua_pushvalue(L, 2);
        r->facade_ref = luaL_ref(L, LUA_REGISTRYINDEX);
        lua_getfield(L, 2, "host");
        if (!lua_isnil(L, -1)) {
            lua_pushvalue(L, -1);
            r->host_ref = luaL_ref(L, LUA_REGISTRYINDEX);
        }
        lua_pop(L, 1);
    }

    luaL_getmetatable(L, RECSTORE_META);
    lua_setmetatable(L, -2);
    return 1;
}

/* 调 host.onRecordChange(facade, { type=, key= }) */
static void record_notify(lua_State *L, record_store *r, const char *type, const char *key) {
    if (r->host_ref == LUA_NOREF) return;
    lua_rawgeti(L, LUA_REGISTRYINDEX, r->host_ref);     /* host */
    lua_getfield(L, -1, "onRecordChange");
    if (lua_isfunction(L, -1)) {
        lua_pushvalue(L, -2);                            /* host 作为方法 self */
        if (r->facade_ref != LUA_NOREF) {
            lua_rawgeti(L, LUA_REGISTRYINDEX, r->facade_ref);
        } else {
            lua_pushnil(L);
        }
        lua_newtable(L);
        lua_pushliteral(L, "type"); lua_pushstring(L, type); lua_settable(L, -3);
        lua_pushliteral(L, "key");  lua_pushstring(L, key);  lua_settable(L, -3);
        lua_call(L, 3, 0);
        lua_pop(L, 1);                                   /* host */
    } else {
        lua_pop(L, 2);                                   /* fn, host */
    }
}

/* 从行数据表中取出主键字符串: keyFields 多字段用 ":" 拼接(tostring 语义) */
static void push_key_from_table(lua_State *L, record_store *r, int tbl_idx) {
    luaL_checkstack(L, 6, "record key");
    luaL_Buffer b;
    luaL_buffinit(L, &b);
    int first = 1;
    for (int i = 0; i < r->desc->nfield; i++) {
        if (!r->desc->fields[i].key) continue;
        if (!first) luaL_addchar(&b, ':');
        first = 0;
        lua_getfield(L, tbl_idx, r->desc->fields[i].name);
        size_t len = 0;
        const char *s = luaL_tolstring(L, -1, &len);  /* 压入转换后的字符串 */
        luaL_addlstring(&b, s, len);
        lua_pop(L, 2);                                /* 字符串 + 原值 */
    }
    luaL_pushresult(&b);
}

static int l_key_of(lua_State *L) {
    record_store *r = check_rec(L, 1);
    luaL_checktype(L, 2, LUA_TTABLE);
    push_key_from_table(L, r, 2);
    return 1;
}

static int l_add(lua_State *L) {
    record_store *r = check_rec(L, 1);
    luaL_checktype(L, 2, LUA_TTABLE);

    push_key_from_table(L, r, 2);
    char *key = strdup(luaL_checkstring(L, -1));
    lua_pop(L, 1);

    int row;
    int existing = find_key_slot(r, key);
    if (existing >= 0) {
        free(key);
        lua_pushnil(L);
        return 1;
    }
    store_add_row(r, key, &row);

    /* add/remove 合并: 先检查是否已有 pending remove */
    if (!r->desc->sync_none) {
        int existing_op = op_find_by_key(r, key);
        if (existing_op >= 0 && r->ops[existing_op].type == OP_REMOVE) {
            op_remove_at(r, existing_op);
        } else if (existing_op < 0) {
            op_append(r, OP_ADD, key, row, -1);
        }
    }
    free(key);

    for (int i = 0; i < r->desc->nfield; i++) {
        lua_getfield(L, 2, r->desc->fields[i].name);
        if (!lua_isnil(L, -1)) {
            value_from_lua(L, -1, &r->desc->fields[i], cell_at(r, row, i));
            cell_mark(r, row, i);
        }
        lua_pop(L, 1);
    }

    record_notify(L, r, "add", r->keys[row]);

    record_row *rr = (record_row *)lua_newuserdata(L, sizeof(record_row));
    rr->rec = r;
    rr->row_idx = row;
    luaL_getmetatable(L, RECSTORE_ROW_META);
    lua_setmetatable(L, -2);
    return 1;
}

static int l_get_row_by_key(lua_State *L) {
    record_store *r = check_rec(L, 1);
    const char *key = luaL_checkstring(L, 2);
    int slot = find_key_slot(r, key);
    if (slot < 0) {
        lua_pushnil(L);
        return 1;
    }
    record_row *rr = (record_row *)lua_newuserdata(L, sizeof(record_row));
    rr->rec = r;
    rr->row_idx = r->slots[slot].idx;
    luaL_getmetatable(L, RECSTORE_ROW_META);
    lua_setmetatable(L, -2);
    return 1;
}

static int l_remove(lua_State *L) {
    record_store *r = check_rec(L, 1);
    const char *key = luaL_checkstring(L, 2);
    int slot = find_key_slot(r, key);
    if (slot < 0) {
        lua_pushboolean(L, 0);
        return 1;
    }

    char *row_key = strdup(r->slots[slot].key);
    free_slot_row(r, slot);

    int op_idx = op_find_by_key(r, key);
    if (op_idx >= 0 && r->ops[op_idx].type == OP_ADD) {
        op_remove_at(r, op_idx);
    } else if (op_idx >= 0 && r->ops[op_idx].type == OP_SET) {
        op_remove_at(r, op_idx);
        op_append(r, OP_REMOVE, key, -1, -1);
    } else {
        op_append(r, OP_REMOVE, key, -1, -1);
    }
    lua_pushboolean(L, 1);
    record_notify(L, r, "remove", row_key);
    free(row_key);
    return 1;
}

static void store_set_field(lua_State *L, record_store *r, int row,
                                const char *key, const char *field, int value_idx) {
    int idx = find_field_idx(r->desc, field);
    if (idx < 0) luaL_error(L, "unknown field %s", field);
    value_free(cell_at(r, row, idx));
    value_from_lua(L, value_idx, &r->desc->fields[idx], cell_at(r, row, idx));
    cell_mark(r, row, idx);

    if (!r->desc->sync_none) {
        int op_idx = op_find_by_key(r, key);
        if (op_idx >= 0 && r->ops[op_idx].type == OP_SET) {
            r->ops[op_idx].dirty[idx] = 1;
        } else if (op_idx < 0) {
            rec_op *op = op_append(r, OP_SET, key, row, idx);
            op->dirty[idx] = 1;
        }
        /* 已有 OP_ADD 时, 全行快照已覆盖该修改 */
    }
    record_notify(L, r, "set", key);
}

static int l_set(lua_State *L) {
    record_store *r = check_rec(L, 1);
    const char *key = luaL_checkstring(L, 2);
    const char *field = luaL_checkstring(L, 3);

    int slot = find_key_slot(r, key);
    if (slot < 0) {
        luaL_error(L, "record key not found: %s", key);
    }
    store_set_field(L, r, r->slots[slot].idx, key, field, 4);
    return 0;
}

static int l_flush(lua_State *L) {
    record_store *r = check_rec(L, 1);
    lua_newtable(L); /* ops 数组 */

    int out = 0;
    for (int i = 0; i < r->op_n; i++) {
        rec_op *op = &r->ops[i];
        lua_newtable(L);
        if (op->type == OP_ADD) {
            lua_pushliteral(L, "type"); lua_pushliteral(L, "add"); lua_settable(L, -3);
            lua_pushliteral(L, "key"); lua_pushstring(L, op->key); lua_settable(L, -3);
            lua_pushliteral(L, "data");
            lua_newtable(L);
            for (int f = 0; f < r->desc->nfield; f++) {
                if (r->desc->fields[f].sync_none || !cell_set(r, op->row, f)) continue;
                lua_pushstring(L, r->desc->fields[f].name);
                push_field_value(L, r, op->row, f);
                lua_settable(L, -3);
            }
            lua_settable(L, -3);
        } else if (op->type == OP_REMOVE) {
            lua_pushliteral(L, "type"); lua_pushliteral(L, "remove"); lua_settable(L, -3);
            lua_pushliteral(L, "key"); lua_pushstring(L, op->key); lua_settable(L, -3);
        } else if (op->type == OP_SET) {
            lua_pushliteral(L, "type"); lua_pushliteral(L, "set"); lua_settable(L, -3);
            lua_pushliteral(L, "key"); lua_pushstring(L, op->key); lua_settable(L, -3);
            lua_pushliteral(L, "data");
            lua_newtable(L);
            for (int f = 0; f < r->desc->nfield; f++) {
                if (op->dirty[f] && !r->desc->fields[f].sync_none && cell_set(r, op->row, f)) {
                    lua_pushstring(L, r->desc->fields[f].name);
                    push_field_value(L, r, op->row, f);
                    lua_settable(L, -3);
                }
            }
            lua_settable(L, -3);
        }
        lua_rawseti(L, -2, ++out);
    }

    /* 清空 ops */
    for (int i = 0; i < r->op_n; i++) op_free(&r->ops[i]);
    r->op_n = 0;
    op_map_clear(r);
    return 1;
}

static int l_dump(lua_State *L) {
    record_store *r = check_rec(L, 1);
    lua_newtable(L);
    for (int i = 0; i < r->order_n; i++) {
        int row = r->order_rows[i];
        lua_newtable(L);
        for (int f = 0; f < r->desc->nfield; f++) {
            if (!cell_set(r, row, f)) continue;
            lua_pushstring(L, r->desc->fields[f].name);
            push_field_value(L, r, row, f);
            lua_settable(L, -3);
        }
        lua_setfield(L, -2, r->keys[row]);
    }
    return 1;
}

/* ---------- row methods ---------- */

static record_row *check_row(lua_State *L, int idx) {
    record_row *r = (record_row *)lua_touserdata(L, idx);
    if (r == NULL) luaL_error(L, "expected recordstore row userdata");
    return r;
}

static int l_row_id(lua_State *L) {
    record_row *rr = check_row(L, 1);
    lua_pushstring(L, rr->rec->keys[rr->row_idx]);
    return 1;
}

static int l_row_get(lua_State *L) {
    record_row *rr = check_row(L, 1);
    const char *field = luaL_checkstring(L, 2);
    int idx = find_field_idx(rr->rec->desc, field);
    if (idx >= 0) {
        push_field_value(L, rr->rec, rr->row_idx, idx);
        return 1;
    }
    lua_pushnil(L);
    return 1;
}

static int l_row_set(lua_State *L) {
    record_row *rr = check_row(L, 1);
    const char *field = luaL_checkstring(L, 2);
    store_set_field(L, rr->rec, rr->row_idx, rr->rec->keys[rr->row_idx], field, 3);
    return 0;
}

static int l_row_raw_set(lua_State *L) {
    record_row *rr = check_row(L, 1);
    const char *field = luaL_checkstring(L, 2);
    int idx = find_field_idx(rr->rec->desc, field);
    if (idx < 0) luaL_error(L, "unknown field %s", field);
    value_free(cell_at(rr->rec, rr->row_idx, idx));
    value_from_lua(L, 3, &rr->rec->desc->fields[idx], cell_at(rr->rec, rr->row_idx, idx));
    cell_mark(rr->rec, rr->row_idx, idx);
    return 0;
}

static int l_row_data(lua_State *L) {
    record_row *rr = check_row(L, 1);
    lua_newtable(L);
    for (int i = 0; i < rr->rec->desc->nfield; i++) {
        if (!cell_set(rr->rec, rr->row_idx, i)) continue;
        lua_pushstring(L, rr->rec->desc->fields[i].name);
        push_field_value(L, rr->rec, rr->row_idx, i);
        lua_settable(L, -3);
    }
    return 1;
}

/* row.field 读取: 先方法, 再字段 */
static int l_row_index(lua_State *L) {
    record_row *rr = check_row(L, 1);
    const char *field = lua_tostring(L, 2);

    luaL_getmetatable(L, RECSTORE_ROW_META);
    lua_pushvalue(L, 2);
    lua_rawget(L, -2);
    if (!lua_isnil(L, -1)) return 1;
    lua_pop(L, 2);

    if (field) {
        int idx = find_field_idx(rr->rec->desc, field);
        if (idx >= 0) {
            push_field_value(L, rr->rec, rr->row_idx, idx);
            return 1;
        }
    }
    lua_pushnil(L);
    return 1;
}

/* row.field = value: 记录 set op 并通知 */
static int l_row_newindex(lua_State *L) {
    record_row *rr = check_row(L, 1);
    const char *field = luaL_checkstring(L, 2);
    store_set_field(L, rr->rec, rr->row_idx, rr->rec->keys[rr->row_idx], field, 3);
    return 0;
}

/* create row userdata for rec row idx */
static void push_row(lua_State *L, record_store *r, int row) {
    record_row *rr = (record_row *)lua_newuserdata(L, sizeof(record_row));
    rr->rec = r;
    rr->row_idx = row;
    luaL_getmetatable(L, RECSTORE_ROW_META);
    lua_setmetatable(L, -2);
}

static int l_update(lua_State *L) {
    record_store *r = check_rec(L, 1);
    const char *key = luaL_checkstring(L, 2);
    luaL_checktype(L, 3, LUA_TTABLE);
    int slot = find_key_slot(r, key);
    if (slot < 0) { lua_pushnil(L); return 1; }
    int row = r->slots[slot].idx;

    lua_pushnil(L); /* keep ordering */
    while (lua_next(L, 3) != 0) {
        /* key at -2, value at -1 */
        const char *field = lua_tostring(L, -2);
        if (!field) luaL_error(L, "record update key must be string");
        store_set_field(L, r, row, key, field, -1);
        lua_pop(L, 1); /* value */
    }
    push_row(L, r, row);
    return 1;
}

static int l_rows_list(lua_State *L) {
    record_store *r = check_rec(L, 1);
    lua_newtable(L);
    int n = 0;
    for (int i = 0; i < r->order_n; i++) {
        int row = r->order_rows[i];
        push_row(L, r, row);
        lua_rawseti(L, -2, ++n);
    }
    return 1;
}

static int l_query(lua_State *L) {
    record_store *r = check_rec(L, 1);
    int hasPred = lua_isfunction(L, 2);
    lua_newtable(L);                 /* result */
    int n = 0;
    for (int i = 0; i < r->order_n; i++) {
        int row = r->order_rows[i];
        push_row(L, r, row);         /* result, row */
        if (hasPred) {
            lua_pushvalue(L, 2);        /* pred */
            lua_pushvalue(L, -2);       /* row */
            lua_pushstring(L, r->keys[row]);
            lua_call(L, 2, 1);
            int keep = lua_toboolean(L, -1);
            lua_pop(L, 1);
            if (!keep) {
                lua_pop(L, 1);          /* drop row */
                continue;
            }
        }
        lua_rawseti(L, -2, ++n);     /* result,row removed */
    }
    return 1;
}

static int l_find_one(lua_State *L) {
    record_store *r = check_rec(L, 1);
    const char *field = luaL_checkstring(L, 2);
    int idx = find_field_idx(r->desc, field);
    if (idx < 0) {
        lua_pushnil(L);
        return 1;
    }

    for (int i = 0; i < r->order_n; i++) {
        int row = r->order_rows[i];
        push_field_value(L, r, row, idx);
        lua_pushvalue(L, 3);
        int eq = lua_compare(L, -2, -1, LUA_OPEQ);
        lua_pop(L, 2);
        if (eq) {
            push_row(L, r, row);
            return 1;
        }
    }
    lua_pushnil(L);
    return 1;
}

static int l_count(lua_State *L) {
    record_store *r = check_rec(L, 1);
    lua_pushinteger(L, r->nrows - r->free_n);
    return 1;
}

static int l_flush_sync(lua_State *L) {
    record_store *r = check_rec(L, 1);
    if (r->op_n == 0) {
        lua_pushnil(L);
        return 1;
    }

    /* 构造 ops 数组 */
    lua_newtable(L); int ops_tbl = lua_gettop(L);
    int n = 0;
    for (int i = 0; i < r->op_n; i++) {
        rec_op *op = &r->ops[i];
        lua_newtable(L);
        lua_pushliteral(L, "type");
        if (op->type == OP_ADD) lua_pushliteral(L, "add");
        else if (op->type == OP_REMOVE) lua_pushliteral(L, "remove");
        else lua_pushliteral(L, "set");
        lua_settable(L, -3);

        lua_pushliteral(L, "key"); lua_pushstring(L, op->key); lua_settable(L, -3);

        if (op->type == OP_ADD) {
            lua_pushliteral(L, "data"); lua_newtable(L);
            for (int f = 0; f < r->desc->nfield; f++) {
                if (r->desc->fields[f].sync_none || !cell_set(r, op->row, f)) continue;
                lua_pushstring(L, r->desc->fields[f].name);
                push_field_value(L, r, op->row, f);
                lua_settable(L, -3);
            }
            lua_settable(L, -3);
        } else if (op->type == OP_SET) {
            lua_pushliteral(L, "data"); lua_newtable(L);
            for (int f = 0; f < r->desc->nfield; f++) {
                if (op->dirty[f] && !r->desc->fields[f].sync_none && cell_set(r, op->row, f)) {
                    lua_pushstring(L, r->desc->fields[f].name);
                    push_field_value(L, r, op->row, f);
                    lua_settable(L, -3);
                }
            }
            lua_settable(L, -3);
        }
        lua_rawseti(L, ops_tbl, ++n);
    }

    /* 清空 */
    for (int i = 0; i < r->op_n; i++) op_free(&r->ops[i]);
    r->op_n = 0;
    op_map_clear(r);

    lua_newtable(L);
    lua_pushliteral(L, "name"); lua_pushstring(L, r->desc->name); lua_settable(L, -3);
    lua_pushliteral(L, "ops");  lua_pushvalue(L, ops_tbl);  lua_settable(L, -3);
    lua_remove(L, ops_tbl);
    return 1;
}

/* rec[key] / rec.method 查找: 方法优先, 其次按 key 返回行 */
static int l_rec_index(lua_State *L) {
    record_store *r = check_rec(L, 1);

    luaL_getmetatable(L, RECSTORE_META);
    lua_pushvalue(L, 2);
    lua_rawget(L, -2);
    if (!lua_isnil(L, -1)) return 1;
    lua_pop(L, 2);

    if (lua_type(L, 2) == LUA_TSTRING) {
        const char *key = lua_tostring(L, 2);
        int slot = find_key_slot(r, key);
        if (slot >= 0) {
            push_row(L, r, r->slots[slot].idx);
            return 1;
        }
    }
    lua_pushnil(L);
    return 1;
}

/* ---------- module open ---------- */

static const luaL_Reg rec_methods[] = {
    { "keyOf", l_key_of },
    { "add", l_add },
    { "get", l_get_row_by_key },
    { "remove", l_remove },
    { "set", l_set },
    { "update", l_update },
    { "rowsList", l_rows_list },
    { "count", l_count },
    { "query", l_query },
    { "findOne", l_find_one },
    { "flush", l_flush },
    { "flushSync", l_flush_sync },
    { "dump", l_dump },
    { NULL, NULL },
};

static const luaL_Reg rec_funcs[] = {
    { "define", l_record_define },
    { "new", l_new_rec },
    { NULL, NULL },
};

static const luaL_Reg row_methods[] = {
    { "id", l_row_id },
    { "get", l_row_get },
    { "set", l_row_set },
    { "rawSet", l_row_raw_set },
    { "data", l_row_data },
    { NULL, NULL },
};

static int l_store_gc(lua_State *L) {
    record_store *r = check_rec(L, 1);
    if (r) {
        /* 定义(desc)由进程级缓存共享, 这里只释放实例数据 */
        for (int row = 0; row < r->nrows; row++) {
            for (int f = 0; f < r->desc->nfield; f++) value_free(cell_at(r, row, f));
            free(r->keys[row]);
        }
        free(r->rows); free(r->set); free(r->keys); free(r->slots);
        for (int i = 0; i < r->op_n; i++) op_free(&r->ops[i]);
        op_map_clear(r);
        free(r->op_slots);
        free(r->ops); free(r->free_rows); free(r->order_rows);
        if (r->host_ref != LUA_NOREF) luaL_unref(L, LUA_REGISTRYINDEX, r->host_ref);
        if (r->facade_ref != LUA_NOREF) luaL_unref(L, LUA_REGISTRYINDEX, r->facade_ref);
    }
    return 0;
}

int luaopen_recordstore(lua_State *L) {

    luaL_newmetatable(L, RECSTORE_META);
    luaL_setfuncs(L, rec_methods, 0);
    lua_pushcfunction(L, l_rec_index);
    lua_setfield(L, -2, "__index");
    lua_pushcfunction(L, l_store_gc);
    lua_setfield(L, -2, "__gc");
    lua_pop(L, 1);

    luaL_newmetatable(L, RECSTORE_ROW_META);
    luaL_setfuncs(L, row_methods, 0);
    lua_pushcfunction(L, l_row_index);
    lua_setfield(L, -2, "__index");
    lua_pushcfunction(L, l_row_newindex);
    lua_setfield(L, -2, "__newindex");
    lua_pop(L, 1);

    luaL_newlib(L, rec_funcs);
    return 1;
}
