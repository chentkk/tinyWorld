/*
 * lualib-src/timerwheel.c
 * 单线程时间轮(翻译自 skynet_timer.c 的核心结构):
 *   - 单位由调用方决定(请统一用毫秒整数)
 *   - 一次性定时器: add(wheel, id, delay) -> 到期时 update 返回 due id 列表
 *   - 重复/无限次由 Lua 层在 due 后重新 add
 * Lua API:
 *   tw = timerwheel.new()
 *   timerwheel.add(tw, id, delay_ms)
 *   timerwheel.remove(tw, id)  -> boolean
 *   ids = timerwheel.update(tw, delta_ms)  -- 返回本次到期的 id 数组
 */

#include <lua.h>
#include <lauxlib.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#define TIME_NEAR_SHIFT 8
#define TIME_NEAR (1 << TIME_NEAR_SHIFT)
#define TIME_LEVEL_SHIFT 6
#define TIME_LEVEL (1 << TIME_LEVEL_SHIFT)
#define TIME_NEAR_MASK (TIME_NEAR - 1)
#define TIME_LEVEL_MASK (TIME_LEVEL - 1)

typedef struct timer_node {
    struct timer_node *next;
    uint32_t expire;
    int64_t id;
} timer_node;

typedef struct link_list {
    timer_node head;
    timer_node *tail;
} link_list;

typedef struct timer_wheel {
    link_list near[TIME_NEAR];
    link_list t[4][TIME_LEVEL];
    uint32_t time;
    uint32_t count;
} timer_wheel;

#define TIMERWHEEL_META "timerwheel"

static inline timer_node *link_clear(link_list *list) {
    timer_node *ret = list->head.next;
    list->head.next = NULL;
    list->tail = &list->head;
    return ret;
}

static inline void link_tail(link_list *list, timer_node *node) {
    list->tail->next = node;
    list->tail = node;
    node->next = NULL;
}

static void add_node(timer_wheel *T, timer_node *node) {
    uint32_t time = node->expire;
    uint32_t current_time = T->time;

    if ((time | TIME_NEAR_MASK) == (current_time | TIME_NEAR_MASK)) {
        link_tail(&T->near[time & TIME_NEAR_MASK], node);
    } else {
        int i;
        uint32_t mask = TIME_NEAR << TIME_LEVEL_SHIFT;
        for (i = 0; i < 3; i++) {
            if ((time | (mask - 1)) == (current_time | (mask - 1))) {
                break;
            }
            mask <<= TIME_LEVEL_SHIFT;
        }
        link_tail(&T->t[i][(time >> (TIME_NEAR_SHIFT + i * TIME_LEVEL_SHIFT)) & TIME_LEVEL_MASK], node);
    }
}

static void move_list(timer_wheel *T, int level, int idx) {
    timer_node *current = link_clear(&T->t[level][idx]);
    while (current) {
        timer_node *temp = current->next;
        add_node(T, current);
        current = temp;
    }
}

static void timer_shift(timer_wheel *T) {
    int mask = TIME_NEAR;
    uint32_t ct = ++T->time;
    if (ct == 0) {
        move_list(T, 3, 0);
    } else {
        uint32_t time = ct >> TIME_NEAR_SHIFT;
        int i = 0;
        while ((ct & (mask - 1)) == 0) {
            int idx = time & TIME_LEVEL_MASK;
            if (idx != 0) {
                move_list(T, i, idx);
                break;
            }
            mask <<= TIME_LEVEL_SHIFT;
            time >>= TIME_LEVEL_SHIFT;
            ++i;
        }
    }
}

static int collect_due_into(timer_wheel *T, lua_State *L, int table_idx) {
    int idx = T->time & TIME_NEAR_MASK;
    timer_node *current = T->near[idx].head.next;
    if (!current) return 0;

    current = link_clear(&T->near[idx]);
    int n = (int)luaL_len(L, table_idx);
    while (current) {
        timer_node *tmp = current;
        lua_pushinteger(L, (lua_Integer)tmp->id);
        lua_rawseti(L, table_idx, ++n);
        current = tmp->next;
        free(tmp);
        T->count--;
    }
    return n;
}

static int l_new(lua_State *L) {
    timer_wheel *T = (timer_wheel *)lua_newuserdata(L, sizeof(timer_wheel));
    memset(T, 0, sizeof(*T));
    int i, j;
    for (i = 0; i < TIME_NEAR; i++) {
        T->near[i].head.next = NULL;
        T->near[i].tail = &T->near[i].head;
    }
    for (i = 0; i < 4; i++) {
        for (j = 0; j < TIME_LEVEL; j++) {
            T->t[i][j].head.next = NULL;
            T->t[i][j].tail = &T->t[i][j].head;
        }
    }
    luaL_getmetatable(L, TIMERWHEEL_META);
    lua_setmetatable(L, -2);
    return 1;
}

static timer_wheel *check_wheel(lua_State *L, int idx) {
    return (timer_wheel *)luaL_checkudata(L, idx, TIMERWHEEL_META);
}

static int l_add(lua_State *L) {
    timer_wheel *T = check_wheel(L, 1);
    int64_t id = (int64_t)luaL_checkinteger(L, 2);
    uint32_t delay = (uint32_t)luaL_checkinteger(L, 3);
    luaL_argcheck(L, delay > 0, 3, "delay must be > 0");

    timer_node *node = (timer_node *)malloc(sizeof(*node));
    node->id = id;
    node->expire = T->time + delay;
    add_node(T, node);
    T->count++;
    return 0;
}

static int l_remove(lua_State *L) {
    timer_wheel *T = check_wheel(L, 1);
    int64_t id = (int64_t)luaL_checkinteger(L, 2);

    /* 按 near 槽线性删; 定时器数量通常小, 可接受 */
    uint32_t idx = T->time & TIME_NEAR_MASK;
    timer_node *prev = &T->near[idx].head;
    timer_node *cur = T->near[idx].head.next;
    while (cur) {
        if (cur->id == id) {
            prev->next = cur->next;
            if (T->near[idx].tail == cur) T->near[idx].tail = prev;
            free(cur);
            T->count--;
            lua_pushboolean(L, 1);
            return 1;
        }
        prev = cur;
        cur = cur->next;
    }

    /* 非 near 槽未做按 id 删除; 返回 false, Lua 层直接标记逻辑删除 */
    lua_pushboolean(L, 0);
    return 1;
}

static int l_update(lua_State *L) {
    timer_wheel *T = check_wheel(L, 1);
    uint32_t delta = (uint32_t)luaL_checkinteger(L, 2);
    uint32_t i;
    lua_newtable(L);
    int table_idx = lua_gettop(L);
    int n = 0;

    for (i = 0; i < delta; i++) {
        n += collect_due_into(T, L, table_idx); /* 本 tick 到期 */
        timer_shift(T);
        n += collect_due_into(T, L, table_idx); /* shift 后 near 槽 */
    }

    /* 用 n 保证数组长度; collect_* 用 rawseti 顺序递增 */
    (void)n;
    return 1;
}

static int l_count(lua_State *L) {
    timer_wheel *T = check_wheel(L, 1);
    lua_pushinteger(L, (lua_Integer)T->count);
    return 1;
}

static int l_time(lua_State *L) {
    timer_wheel *T = check_wheel(L, 1);
    lua_pushinteger(L, (lua_Integer)T->time);
    return 1;
}

static const luaL_Reg funcs[] = {
    { "new", l_new },
    { NULL, NULL },
};

static const luaL_Reg methods[] = {
    { "add", l_add },
    { "remove", l_remove },
    { "update", l_update },
    { "count", l_count },
    { "time", l_time },
    { NULL, NULL },
};

int luaopen_timerwheel(lua_State *L) {
    if (luaL_newmetatable(L, TIMERWHEEL_META) == 0) {
        /* metatable already exists */
    }
    luaL_setfuncs(L, methods, 0);
    lua_pushvalue(L, -1);
    lua_setfield(L, -2, "__index");

    luaL_newlib(L, funcs);
    return 1;
}
