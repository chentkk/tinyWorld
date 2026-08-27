-- server/test/test_schema.lua
-- PropertySchema / Record / Container(View) / Entity 打包 的单元测试。

package.path = "./?.lua;./?/init.lua;" .. package.path

local Entity = require "tinyworld.entity.entity"
local compileDef = require "tinyworld.entity.entity_def"
local bin = require "tinyworld.core.bin"
local json = require "tinyworld.core.json"

local def = compileDef({
    name = "Player",
    props = {
        { name = "level", type = "number", sync = "all", persist = true, default = 1 },
        { name = "vip", type = "number", sync = "self", persist = true, default = 0 },
        { name = "tmp", type = "number", sync = "none", persist = false, default = 7 },
    },
    records = {
        { name = "tasks", keyFields = { "taskid" }, sync = "all", fields = {
            { name = "taskid", type = "number", sync = "all" },
            { name = "progress", type = "number", sync = "all", default = 0 } } },
    },
    containers = {
        { name = "bag", persist = true,
          viewProps = { { name = "capacity", type = "number", sync = "all", default = 8 } },
          childProps = { { name = "id", type = "number" }, { name = "itemId", type = "number", sync = "all" },
                         { name = "count", type = "number", sync = "all", default = 1 } } },
    },
})

local e = Entity.new(def, 1000001, "Player")
e:onCreate()

-- property: dot 赋值自动同步 + 持久化标记
e.level = 10
assert(e:get("level") == 10)
assert(e.props:collectSync().level == 10)
assert(e.props:collectSync().level == nil)
local persist = e.props:collectPersist()
assert(persist.level == 10)
e.vip = 3
assert(e.props:collectPersist().vip == 3)

-- record add/update/query
local tasks = e:getRecord("tasks")
tasks:add({ taskid = 102, progress = 1 })
tasks:add({ taskid = 101, progress = 3 })
assert(tasks:count() == 2)
assert(tasks:get("101").progress == 3)
tasks:update("101", { progress = 5 })
assert(tasks:findOne("taskid", 101).progress == 5)
local ops = tasks:collectSync()
assert(ops[1].type == "add" and ops[3] and ops[3].type == "set")

-- container: 视图 op 类型覆盖 add/remove/set/view
local bag = e:getContainer("bag")
bag:openView("1")
bag:add({ id = 1, itemId = 1001, count = 3 })
bag:setChildProp(1, "count", 2)
bag:setViewProp("capacity", 16)
bag:add({ id = 2, itemId = 2002 })
bag:remove(2)
local vops = bag:collectSync()
assert(vops[1].type == "add" and vops[1].data.count == 3)
assert(vops[2].type == "set" and vops[3].type == "view" and vops[4].type == "add")
assert(vops[5].type == "remove" and vops[5].id == 2)

-- 二进制打包往返 (player_bin 结构)
local packed = bin.packEntity(e:dump())
local back = bin.unpackEntity(packed)
assert(back.props.level == 10)
assert(back.records.tasks["101"].progress == 5)
assert(#back.containers.bag.children == 1)

-- json 编解码
local jt = { a = 1, b = { c = "x" }, arr = { 1, 2, 3 } }
local js = json.encode(jt)
assert(json.decode(js).b.c == "x")
assert(json.decode(js).arr[3] == 3)

print("PASS test_schema")
