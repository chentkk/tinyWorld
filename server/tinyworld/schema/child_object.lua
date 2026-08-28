-- tinyworld/schema/child_object.lua
-- ChildObject: 容器子对象 / Record 行包装对象。
-- 通过 __index / __newindex 支持 obj.field = value。
-- 属性写入会通知 owner, owner 再生成同步 op。

local ChildObject = {}
ChildObject.__index = ChildObject

function ChildObject.new(schema, owner, id, data)
    local self = setmetatable({}, ChildObject)

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

function ChildObject:__index(name)
    local raw = rawget(self, name)
    if raw ~= nil then
        return raw
    end

    if ChildObject[name] ~= nil then
        return ChildObject[name]
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

function ChildObject:__newindex(name, value)
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

function ChildObject:rawSet(name, value)
    rawset(self, name, value)
end

function ChildObject:id()
    return rawget(self, "_id")
end

function ChildObject:data()
    return rawget(self, "_data")
end

return ChildObject
