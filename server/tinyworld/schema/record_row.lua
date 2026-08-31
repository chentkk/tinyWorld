-- tinyworld/schema/record_row.lua
-- RecordRow: Record 的一行。
-- 通过 __index / __newindex 支持 row.field = value。
-- 字段写回会通知 owner(Record), 由 Record 合并生成同步 op。

local RecordRow = {}
RecordRow.__index = RecordRow

function RecordRow.new(schema, owner, id, data)
    local self = setmetatable({}, RecordRow)

    rawset(self, "_schema", schema)
    rawset(self, "_owner", owner)
    rawset(self, "_id", id)
    local storage = {}
    rawset(self, "_data", storage)

    for name, value in pairs(data or {}) do
        storage[name] = schema:coerce(name, value)
    end

    return self
end

function RecordRow:__index(name)
    local raw = rawget(self, name)
    if raw ~= nil then
        return raw
    end

    if RecordRow[name] ~= nil then
        return RecordRow[name]
    end

    local schema = rawget(self, "_schema")
    local data = rawget(self, "_data")
    if schema then
        if schema:get(name) then
            return data[name]
        end
    end
    return nil
end

function RecordRow:__newindex(name, value)
    local schema = rawget(self, "_schema")
    local data = rawget(self, "_data")
    if not schema:get(name) then
        rawset(self, name, value)
        return
    end

    value = schema:coerce(name, value)
    if data[name] == value then
        return
    end

    data[name] = value
    local owner = rawget(self, "_owner")
    if owner and owner.onChildPropChange then
        owner:onChildPropChange(self, name, value)
    end
end

function RecordRow:rawSet(name, value)
    rawset(self, name, value)
end

function RecordRow:id()
    return rawget(self, "_id")
end

function RecordRow:data()
    return rawget(self, "_data")
end

return RecordRow
