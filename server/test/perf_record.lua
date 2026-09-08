-- server/test/perf_record.lua
-- Record C vs legacy Lua 性能对比压力测试。
-- 场景: NOBJ 个对象, 每个对象 NREC 个 Record; Record 定义 8 个字段, 覆盖全部数据类型。
-- 每 tick 每个 Record: 新增 5 行、删除 5 行、更新 5 行, 并 flushSync 清空待同步 op。
--
-- 用法: lua test/perf_record.lua [NOBJ] [NREC] [TICKS] [PRELOAD]
-- C 路径:   LUA_CPATH='/path/to/recordstore.so;;' lua test/perf_record.lua
-- legacy 路径: LUA_CPATH='' lua test/perf_record.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local Record = require "tinyworld.schema.record"
local RecordDef = require "tinyworld.schema.record_def"

local NOBJ   = tonumber(arg and arg[1]) or 1000
local NREC   = tonumber(arg and arg[2]) or 40
local TICKS  = tonumber(arg and arg[3]) or 3
local PRE    = tonumber(arg and arg[4]) or 20

-- 8 个字段, 覆盖 bool/int/int64/float/double/string/number 全部类型
local def = RecordDef.new({
    name = "bench",
    keyFields = { "id" },
    sync = "all",
    fields = {
        { name = "id", type = "int" },
        { name = "i", type = "int" },
        { name = "i64", type = "int64" },
        { name = "f", type = "float" },
        { name = "d", type = "double" },
        { name = "b", type = "bool" },
        { name = "s", type = "string" },
        { name = "n", type = "number" },
    },
})

local function mkData(id)
    return {
        id = id,
        i = id,
        i64 = id,
        f = id + 0.5,
        d = id + 0.25,
        b = (id % 2 == 0),
        s = "s" .. id,
        n = id + 0.75,
    }
end

local function mkPatch(id)
    return {
        i = id * 2,
        i64 = id * 2,
        f = id + 1.5,
        d = id + 2.25,
        b = (id % 2 == 1),
        s = "u" .. id,
        n = id + 3.75,
    }
end

-- 每个 Record 预置 PRE 行(随时 flush 清掉预置的 add op, 不进入压测计时)
local objs = {}
local recTotal = 0
for o = 1, NOBJ do
    local recs = {}
    for r = 1, NREC do
        Record.define(def)
        local rec = Record.new(def)
        local live = {}
        local nid = 0
        for p = 1, PRE do
            nid = nid + 1
            live[#live + 1] = nid
            rec:add(mkData(nid))
        end
        rec:flushSync()
        recs[r] = { rec = rec, live = live, head = 1, nid = nid }
        recTotal = recTotal + 1
    end
    objs[o] = recs
end

local adds, rems, ups = 0, 0, 0
local t0 = os.clock()

for t = 1, TICKS do
    for o = 1, NOBJ do
        for r = 1, NREC do
            local s = objs[o][r]
            local rec = s.rec
            local live = s.live

            -- 新增 5 行
            for a = 1, 5 do
                s.nid = s.nid + 1
                local id = s.nid
                rec:add(mkData(id))
                live[#live + 1] = id
                adds = adds + 1
            end

            -- 更新 5 行(不碰本轮新增/本轮删除的行)
            for u = 0, 4 do
                local id = live[s.head + 5 + u]
                rec:update(tostring(id), mkPatch(id))
                ups = ups + 1
            end

            -- 删除 5 行(从头部取, 保持每 record 行数稳定)
            for d = 1, 5 do
                local id = live[s.head]
                local key = tostring(id)
                assert(rec:remove(key), "remove fail " .. key)
                live[s.head] = nil
                s.head = s.head + 1
                rems = rems + 1
            end

            local fs = rec:flushSync()
            if fs then assert(fs.name == "bench") end
        end
    end
end

local sec = os.clock() - t0

-- 校验行数 / op 是否清空(置于计时之后)
for o = 1, NOBJ do
    for r = 1, NREC do
        local s = objs[o][r]
        assert(s.rec:count() == PRE, "record count mismatch")
        assert(s.rec:flushSync() == nil, "pending ops after ticks")
    end
end

local totalOps = adds + rems + ups
print(("[perf_record] objects=%d records=%d total_records=%d ticks=%d add=%d remove=%d update=%d total_ops=%d time=%.3fs ops/s=%.0f"):format(
    NOBJ, NREC, recTotal, TICKS, adds, rems, ups, totalOps, sec, totalOps / sec))
