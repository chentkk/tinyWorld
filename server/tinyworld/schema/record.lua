-- tinyworld/schema/record.lua
-- Record 入口: C recordstore 直接承载全部表格逻辑, 仅保留一个薄 facade 用于:
--   - 把 RecordDef(schema) 转成 C 需要的平铺字段表
--   - 提供 rec[key] 行查找与 rec.rows 快照(与旧 Lua 实现同接口)
-- C module 不可用(例如系统 Lua 5.4)时回退纯 Lua 实现。

local okC, recordstore = pcall(require, "recordstore")
if not okC or type(recordstore.new) ~= "function" then
    return require "tinyworld.schema.record_legacy"
end

local class = require "tinyworld.core.class"

local Record = class.makeClass("Record")

local function fieldDefs(def)
    local out = {}
    for _, f in ipairs(def.schema.fields) do
        out[#out + 1] = {
            name = f.name,
            type = f.type,
            sync = f.sync,
            persist = f.persist,
            default = f.default,
        }
    end
    return out
end

-- 启动阶段集中注册: 按 record def 在 C 内按类名建立共享 desc
function Record.define(def)
    recordstore.define(def.name, {
        name = def.name,
        keyFields = def.keyFields or { "key" },
        sync = def.sync or "none",
        fields = fieldDefs(def),
    })
end

-- 实例 __index: 行查找优先(旧实现语义), 其次方法表
function Record:__index(key)
    if key == "rows" then
        local store = rawget(self, "_store")
        if store then
            local out = {}
            for _, row in ipairs(store:rowsList()) do
                out[row:id()] = row
            end
            return out
        end
        return nil
    end

    local store = rawget(self, "_store")
    if store and type(key) == "string" then
        local row = store:get(key)
        if row then
            return row
        end
    end
    return Record[key]
end

function Record:ctor(def, host)
    rawset(self, "def", def)
    rawset(self, "host", host)
    rawset(self, "_store", recordstore.new(def.name, self))
end

function Record:add(data)
    return rawget(self, "_store"):add(data)
end

function Record:remove(key)
    return rawget(self, "_store"):remove(key)
end

function Record:get(key)
    return rawget(self, "_store"):get(key)
end

function Record:count()
    return rawget(self, "_store"):count()
end

function Record:update(key, patch)
    return rawget(self, "_store"):update(key, patch)
end

function Record:set(key, name, value)
    return self:update(key, { [name] = value })
end

function Record:rowsList()
    return rawget(self, "_store"):rowsList()
end

function Record:query(pred)
    return rawget(self, "_store"):query(pred)
end

function Record:findOne(field, value)
    return rawget(self, "_store"):findOne(field, value)
end

function Record:onChildPropChange(child, name, value)
    -- C 行 __newindex 已在 C 内合并 set op 并通知 host; 该方法仅作接口兼容。
    return rawget(self, "_store"):set(child:id(), name, value)
end

function Record:syncData(row)
    local out = {}
    local schema = self.def.schema
    for _, f in ipairs(schema.fields) do
        if f.sync ~= "none" then
            out[f.name] = row[f.name]
        end
    end
    return out
end

function Record:collectSync()
    return rawget(self, "_store"):flush()
end

function Record:flushSync()
    return rawget(self, "_store"):flushSync()
end

function Record:dump()
    return rawget(self, "_store"):dump()
end

return Record
