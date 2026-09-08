-- server/test/test_record.lua
-- Record 完整 API 测试: add/get/set/update/rowsList/query/findOne/
-- collectSync/flushSync/dump/rec[key] 行访问/多主键/sync none/默认值。

package.path = "./?.lua;./?/init.lua;" .. package.path

local Record = require "tinyworld.schema.record"
local RecordDef = require "tinyworld.schema.record_def"

-- 基本增删查改 + 行字段写回合并
local def = RecordDef.new({
    name = "tasks",
    keyFields = { "taskid" },
    sync = "all",
    fields = {
        { name = "taskid", type = "number", sync = "all" },
        { name = "progress", type = "number", sync = "all", default = 0 },
    },
})
Record.define(def)
local rec = Record.new(def)
rec:add({ taskid = 102, progress = 1 })
rec:add({ taskid = 101, progress = 3 })
assert(rec:count() == 2)
assert(rec:get("101").progress == 3)
assert(rec["101"].progress == 3)

-- row.field = value 自动记录 set(与已有 add op 合并)
rec["101"].progress = 5
assert(rec:findOne("taskid", 101).progress == 5)

local ops = rec:collectSync()
assert(#ops == 2)
assert(ops[1].type == "add" and ops[2].type == "add")
assert(ops[2].key == "101" and ops[2].data.progress == 5)

-- update/set 返回行
local row = rec:update("101", { progress = 7 })
assert(row and row.progress == 7)
rec:set("102", "progress", 9)
assert(rec:get("102").progress == 9)

local fs = rec:flushSync()
assert(fs and fs.name == "tasks")
assert(#fs.ops == 2 and fs.ops[1].type == "set" and fs.ops[2].type == "set")
assert(rec:flushSync() == nil)

-- rowsList/query 保持插入顺序
local rows = rec:rowsList()
assert(#rows == 2 and rows[1].taskid == 102 and rows[2].taskid == 101)
local q = rec:query(function(r, key)
    return r.progress >= 8 and key == "102"
end)
assert(#q == 1 and q[1].taskid == 102)

-- remove + 插入顺序
rec:remove("102")
rec:add({ taskid = 103, progress = 1 })
rows = rec:rowsList()
assert(#rows == 2 and rows[1].taskid == 101 and rows[2].taskid == 103)

local fs2 = rec:flushSync()
assert(fs2.ops[1].type == "remove" and fs2.ops[1].key == "102")
assert(fs2.ops[2].type == "add" and fs2.ops[2].key == "103")

local dump = rec:dump()
assert(dump["101"].progress == 7 and dump["103"].progress == 1)

-- 多主键拼接
local mdef = RecordDef.new({
    name = "bag_slots",
    keyFields = { "owner", "slot" },
    sync = "all",
    fields = {
        { name = "owner", type = "number", sync = "all" },
        { name = "slot", type = "number", sync = "all" },
        { name = "itemId", type = "number", sync = "all", default = 0 },
    },
})
Record.define(mdef)
local mrec = Record.new(mdef)
mrec:add({ owner = 1, slot = 3, itemId = 9 })
mrec:add({ owner = 1, slot = 4, itemId = 10 })
assert(mrec:get("1:3").itemId == 9)
assert(mrec["1:4"].itemId == 10)

-- sync none: 不产生 sync op, 但数据可用
local ndef = RecordDef.new({
    name = "none_sync",
    keyFields = { "k" },
    sync = "none",
    fields = {
        { name = "k", type = "number" },
        { name = "v", type = "number", default = 3 },
    },
})
Record.define(ndef)
local nrec = Record.new(ndef)
nrec:add({ k = 1 })
assert(nrec:get("1").v == nil)  -- 未显式赋值的字段与旧实现一致: 读出 nil
assert(next(nrec:collectSync()) == nil)

-- string/bool 默认值
local sdef = RecordDef.new({
    name = "mixed",
    keyFields = { "k" },
    sync = "all",
    fields = {
        { name = "k", type = "int" },
        { name = "name", type = "string", default = "" },
        { name = "flag", type = "bool", default = false },
    },
})
Record.define(sdef)
local srec = Record.new(sdef)
srec:add({ k = 1, name = "hello", flag = true })
assert(srec:get("1").name == "hello")
assert(srec:get("1").flag == true)

print("PASS test_record")
