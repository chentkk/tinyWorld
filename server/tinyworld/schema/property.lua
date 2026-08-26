-- tinyworld/schema/property.lua
-- 通用属性结构 PropertySchema。
-- 属性: 名称、类型、同步方式、是否持久化、注释、默认值。
-- 支持 include 插入已定义的属性定义文件。
-- 运行时由 Properties 承载, set("level", 10) 或 player.level = 10 自动触发同步与存盘。

local M = {}

-- 编译定义(可带 include) 为平铺的核心字段表
local function flattenFields(defs, result, seen, stack)
    result = result or {}
    seen = seen or {}
    stack = stack or {}

    for _, item in ipairs(defs or {}) do
        if item.include then
            if stack[item.include] then
                error("circular property include: " .. item.include)
            end
            if not seen[item.include] then
                local sub = require(item.include)
                local subDefs = sub.props or sub.fields or sub
                stack[item.include] = true
                flattenFields(subDefs, result, seen, stack)
                stack[item.include] = nil
                seen[item.include] = true
            end
        else
            if not item.name then error("property field missing name") end
            result[#result + 1] = {
                name = item.name,
                type = item.type or "number",
                sync = item.sync or "all",
                persist = item.persist and true or false,
                comment = item.comment or "",
                default = item.default,
            }
        end
    end
    return result
end

local PropertySchema = {}
PropertySchema.__index = PropertySchema

function PropertySchema.new(defs)
    local self = setmetatable({}, PropertySchema)
    self.fields = flattenFields(defs)
    self.byName = {}
    for _, f in ipairs(self.fields) do
        self.byName[f.name] = f
    end
    return self
end

function PropertySchema:get(name)
    return self.byName[name]
end

-- 批量校验 / 修正值类型
function PropertySchema:coerce(name, value)
    local f = self.byName[name]
    if not f then error("unknown property: " .. tostring(name)) end
    if value == nil then return f.default end
    if f.type == "number" then
        return tonumber(value) or 0
    elseif f.type == "string" then
        return tostring(value)
    elseif f.type == "boolean" then
        if value == "false" then return false end
        return not not value
    end
    return value
end

M.PropertySchema = PropertySchema
M.flattenFields = flattenFields

-- 运行时属性集
local Properties = {}
Properties.__index = Properties

function Properties.new(schema, host)
    local self = setmetatable({}, Properties)
    self.schema = schema
    self.host = host -- 需实现 onPropChange / onPropPersist
    self.values = {}
    self.dirtySync = {} -- name -> true
    self.dirtyPersist = {} -- name -> true

    for _, f in ipairs(schema.fields) do
        if f.default ~= nil then
            self.values[f.name] = f.default
        end
    end
    return self
end

function Properties:get(name)
    return self.values[name]
end

function Properties:set(name, value, source)
    value = self.schema:coerce(name, value)
    if self.values[name] == value then return end

    self.values[name] = value
    local f = self.schema:get(name)

    if f.sync ~= "none" then
        self.dirtySync[name] = true
        if self.host.onPropChange then
            self.host:onPropChange(name, value, f.sync, source)
        end
    end

    if f.persist then
        self.dirtyPersist[name] = true
    end
end

function Properties:setBatch(t, source)
    for k, v in pairs(t) do
        self:set(k, v, source)
    end
end

function Properties:syncMode(name)
    local f = self.schema:get(name)
    return f and f.sync or "none"
end

-- 收集同步脏数据并按范围过滤(供 AOI 广播)
function Properties:collectSync(scope)
    local out = {}
    for name in pairs(self.dirtySync) do
        local f = self.schema:get(name)
        if f and (scope == "all" or (scope == "self") or f.sync == "all") then
            out[name] = self.values[name]
        end
    end
    self.dirtySync = {}
    return out
end

function Properties:clearSync()
    self.dirtySync = {}
end

-- 收集需要存盘的字段
function Properties:collectPersist()
    local out = {}
    for name in pairs(self.dirtyPersist) do
        out[name] = self.values[name]
    end
    return out
end

function Properties:clearPersist()
    self.dirtyPersist = {}
end

function Properties:dump()
    local out = {}
    for _, f in ipairs(self.schema.fields) do
        if self.values[f.name] ~= nil then
            out[f.name] = self.values[f.name]
        end
    end
    return out
end

function Properties:load(t)
    self:setBatch(t, "load")
end

M.Properties = Properties

-- 便捷: 从定义文件生成 schema
function M.loadDefinition(requirePath)
    local def = require(requirePath)
    return PropertySchema.new(def.props or def)
end

return M
