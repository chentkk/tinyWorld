/*
 * lualib-src/skiplist.c
 * 跳表(skiplist), 参考 redis z_set 的 zslInsert / zslDelete / zslFirstInRange 实现,
 * 供 tinyworld cellapp 作 X/Y 十字链表索引。
 *
 * 暴露给 Lua 的接口:
 *   s = skip.new()
 *   s:insert(score, id)
 *   s:remove(score, id)
 *   s:count()        -> number
 *   ids = s:range(lo, hi)  -> 区间内 id 数组(仅序遍历, 不排序保证? 有序)
 */

#include <lua.h>
#include <lauxlib.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#define ZSKIPLIST_MAXLEVEL 32
#define ZSKIPLIST_P 0.25

typedef struct zskiplistNode {
    double score;
    long long id;
    struct zskiplistNode *backward;
    struct zskiplistLevel {
        struct zskiplistNode *forward;
    } level[];
} zskiplistNode;

typedef struct zskiplist {
    zskiplistNode *header;
    zskiplistNode *tail;
    unsigned long length;
    int level;
} zskiplist;

/* 比较 (score, id): 先比 score, 再比 id */
static int zslCompare(double s1, long long id1, double s2, long long id2) {
    if (s1 < s2) return -1;
    if (s1 > s2) return 1;
    if (id1 < id2) return -1;
    if (id1 > id2) return 1;
    return 0;
}

static int zslRandomLevel(void) {
    int level = 1;
    while ((random() & 0xFFFF) < (ZSKIPLIST_P * 0xFFFF))
        level += 1;
    return (level < ZSKIPLIST_MAXLEVEL) ? level : ZSKIPLIST_MAXLEVEL;
}

static zskiplistNode *zslCreateNode(int level, double score, long long id) {
    zskiplistNode *zn = (zskiplistNode *)malloc(sizeof(zskiplistNode) + level * sizeof(struct zskiplistLevel));
    zn->score = score;
    zn->id = id;
    return zn;
}

static zskiplist *zslCreate(void) {
    int j;
    zskiplist *zsl = (zskiplist *)malloc(sizeof(zskiplist));
    zsl->level = 1;
    zsl->length = 0;
    zsl->header = zslCreateNode(ZSKIPLIST_MAXLEVEL, 0, 0);
    for (j = 0; j < ZSKIPLIST_MAXLEVEL; j++) {
        zsl->header->level[j].forward = NULL;
    }
    zsl->header->backward = NULL;
    zsl->tail = NULL;
    return zsl;
}

static void zslFree(zskiplist *zsl) {
    zskiplistNode *node = zsl->header->level[0].forward, *next;
    free(zsl->header);
    while (node) {
        next = node->level[0].forward;
        free(node);
        node = next;
    }
    free(zsl);
}

static zskiplistNode *zslInsert(zskiplist *zsl, double score, long long id) {
    zskiplistNode *update[ZSKIPLIST_MAXLEVEL];
    zskiplistNode *x;
    int i, level;

    x = zsl->header;
    for (i = zsl->level - 1; i >= 0; i--) {
        while (x->level[i].forward &&
               zslCompare(x->level[i].forward->score, x->level[i].forward->id, score, id) < 0) {
            x = x->level[i].forward;
        }
        update[i] = x;
    }

    level = zslRandomLevel();
    if (level > zsl->level) {
        for (i = zsl->level; i < level; i++) update[i] = zsl->header;
        zsl->level = level;
    }

    x = zslCreateNode(level, score, id);
    for (i = 0; i < level; i++) {
        x->level[i].forward = update[i]->level[i].forward;
        update[i]->level[i].forward = x;
    }
    x->backward = (update[0] == zsl->header) ? NULL : update[0];
    if (x->level[0].forward) {
        x->level[0].forward->backward = x;
    } else {
        zsl->tail = x;
    }
    zsl->length++;
    return x;
}

static int zslDelete(zskiplist *zsl, double score, long long id) {
    zskiplistNode *update[ZSKIPLIST_MAXLEVEL], *x;
    int i;

    x = zsl->header;
    for (i = zsl->level - 1; i >= 0; i--) {
        while (x->level[i].forward &&
               zslCompare(x->level[i].forward->score, x->level[i].forward->id, score, id) < 0) {
            x = x->level[i].forward;
        }
        update[i] = x;
    }

    x = update[0]->level[0].forward;
    if (x && zslCompare(x->score, x->id, score, id) == 0) {
        for (i = 0; i < zsl->level; i++) {
            if (update[i]->level[i].forward == x) {
                update[i]->level[i].forward = x->level[i].forward;
            } else {
                break;
            }
        }
        if (x->level[0].forward) {
            x->level[0].forward->backward = x->backward;
        } else {
            zsl->tail = x->backward;
        }
        while (zsl->level > 1 && zsl->header->level[zsl->level - 1].forward == NULL)
            zsl->level--;
        zsl->length--;
        free(x);
        return 1;
    }
    return 0;
}

static zskiplistNode *zslFirstInRange(zskiplist *zsl, double lo) {
    zskiplistNode *x;
    int i;

    x = zsl->header;
    for (i = zsl->level - 1; i >= 0; i--) {
        while (x->level[i].forward && x->level[i].forward->score < lo)
            x = x->level[i].forward;
    }
    return x->level[0].forward;
}

/* ============ Lua binding ============ */

typedef struct {
    zskiplist *zsl;
} luaSkiplist;

#define SKIPLIST_META "cslib.skiplist"

static luaSkiplist *checkSkiplist(lua_State *L, int idx) {
    return (luaSkiplist *)luaL_checkudata(L, idx, SKIPLIST_META);
}

static int l_new(lua_State *L) {
    luaSkiplist *s = (luaSkiplist *)lua_newuserdata(L, sizeof(luaSkiplist));
    s->zsl = zslCreate();
    luaL_getmetatable(L, SKIPLIST_META);
    lua_setmetatable(L, -2);
    return 1;
}

static int l_gc(lua_State *L) {
    luaSkiplist *s = checkSkiplist(L, 1);
    if (s->zsl) {
        zslFree(s->zsl);
        s->zsl = NULL;
    }
    return 0;
}

static int l_insert(lua_State *L) {
    luaSkiplist *s = checkSkiplist(L, 1);
    double score = luaL_checknumber(L, 2);
    long long id = (long long)luaL_checkinteger(L, 3);
    zslInsert(s->zsl, score, id);
    return 0;
}

static int l_remove(lua_State *L) {
    luaSkiplist *s = checkSkiplist(L, 1);
    double score = luaL_checknumber(L, 2);
    long long id = (long long)luaL_checkinteger(L, 3);
    lua_pushboolean(L, zslDelete(s->zsl, score, id));
    return 1;
}

static int l_count(lua_State *L) {
    luaSkiplist *s = checkSkiplist(L, 1);
    lua_pushinteger(L, (lua_Integer)s->zsl->length);
    return 1;
}

static int l_range(lua_State *L) {
    luaSkiplist *s = checkSkiplist(L, 1);
    double lo = luaL_checknumber(L, 2);
    double hi = luaL_checknumber(L, 3);
    zskiplistNode *x = zslFirstInRange(s->zsl, lo);
    int n = 0;
    lua_newtable(L);
    while (x && x->score <= hi) {
        lua_pushinteger(L, (lua_Integer)x->id);
        lua_rawseti(L, -2, ++n);
        x = x->level[0].forward;
    }
    return 1;
}

static int l_verify(lua_State *L) {
    luaSkiplist *s = checkSkiplist(L, 1);
    zskiplistNode *x = s->zsl->header->level[0].forward, *prev = NULL;
    unsigned long n = 0;
    while (x) {
        if (prev && zslCompare(prev->score, prev->id, x->score, x->id) >= 0) {
            lua_pushboolean(L, 0); lua_pushstring(L, "ordering broken"); return 2;
        }
        if (x->backward != prev) {
            lua_pushboolean(L, 0); lua_pushstring(L, "backward broken"); return 2;
        }
        prev = x; n++; x = x->level[0].forward;
    }
    if (n != s->zsl->length) {
        lua_pushboolean(L, 0); lua_pushstring(L, "count mismatch"); return 2;
    }
    lua_pushboolean(L, 1); lua_pushnil(L); return 2;
}

static const luaL_Reg funcs[] = {
    { "new", l_new },
    { NULL, NULL },
};

static const luaL_Reg methods[] = {
    { "insert", l_insert },
    { "remove", l_remove },
    { "count", l_count },
    { "range", l_range },
    { "verify", l_verify },
    { "__gc", l_gc },
    { NULL, NULL },
};

int luaopen_skiplist(lua_State *L) {
    if (luaL_newmetatable(L, SKIPLIST_META) == 0) {
        /* metatable already exists */
    }
    luaL_setfuncs(L, methods, 0);
    lua_pushvalue(L, -1);
    lua_setfield(L, -2, "__index");
    luaL_newlib(L, funcs);
    return 1;
}
