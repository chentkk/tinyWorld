-- tinyworld/core/class.lua
-- 轻量 class 系统: 支持继承与 super 调用, 函数命名统一使用 camelCase。
-- 支持继承 __index / __newindex 元方法, 使子对象类能路由属性 schema 读写。

local M = {}

local function makeClass(name, super)
    local cls = {}
    cls._name = name

    if super then
        cls._super = super
        setmetatable(cls, { __index = super })
    end

    -- 属性 schema 读写元方法需要沿继承链传递
    if super and type(super.__index) == "function" then
        cls.__index = function(self, key)
            local own = rawget(cls, key)
            if own ~= nil then return own end
            return super.__index(self, key)
        end
    else
        cls.__index = cls
    end

    if super and type(super.__newindex) == "function" then
        cls.__newindex = super.__newindex
    end

    function cls.new(...)
        local self = setmetatable({}, cls)
        if self.ctor then
            self:ctor(...)
        end
        return self
    end

    function cls.extend(childName)
        return makeClass(childName, cls)
    end

    return cls
end

M.makeClass = makeClass
M.Object = makeClass("Object")

return M
