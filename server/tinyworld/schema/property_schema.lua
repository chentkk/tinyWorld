-- tinyworld/schema/property_schema.lua
-- PropertySchema: 属性定义编译为平铺字段, 支持 include, 提供 get / coerce。

local function flattenFields(defs, result, seen, stack)
    result = result or {}
    seen = seen or {}
    stack = stack or {}

    for _, item in ipairs(defs or {}) do
        if item.include then
            if stack[item.include] then error("circular property include: " .. item.include) end
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

local PropertySchema = { flattenFields = flattenFields }
PropertySchema.__index = PropertySchema

function PropertySchema.new(defs)
    local self = setmetatable({}, PropertySchema)
    self.fields = flattenFields(defs)
    self.byName = {}
    for _, f in ipairs(self.fields) do self.byName[f.name] = f end
    return self
end

function PropertySchema:get(name)
    return self.byName[name]
end

function PropertySchema:coerce(name, value)
    local f = self.byName[name]
    if not f then error("unknown property: " .. tostring(name)) end
    if value == nil then return f.default end
    if f.type == "number" then return tonumber(value) or 0
    elseif f.type == "string" then return tostring(value)
    elseif f.type == "boolean" then
        if value == "false" then return false end
        return not not value
    end
    return value
end

function PropertySchema:loadDefinition(requirePath)
    local def = require(requirePath)
    return PropertySchema.new(def.props or def)
end

return PropertySchema
