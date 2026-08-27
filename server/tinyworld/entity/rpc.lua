-- tinyworld/entity/rpc.lua
-- RPC 注册表。仅保存 { 对象, 函数名 }, 调用时按名字直接索取,
-- 不需要再遍历对象上的所有组件。


local RpcRegistry = {}
RpcRegistry.__index = RpcRegistry

function RpcRegistry.new()
    return setmetatable({ entries = {} }, RpcRegistry)
end

function RpcRegistry:register(target, methodName, option)
    assert(type(methodName) == "string", "rpc name must be string")
    assert(type(target[methodName]) == "function", "rpc method missing: " .. methodName)

    local list = self.entries[methodName]
    if not list then
        list = {}
        self.entries[methodName] = list
    end

    -- 同名 rpc 覆盖注册提示, 防止误注册
    if #list > 0 then
        error("duplicate rpc register: " .. methodName)
    end

    list[#list + 1] = { target = target, method = methodName, option = option }
end

function RpcRegistry:dispatch(name, data)
    local list = self.entries[name]
    if not list then
        return nil, "rpc not found: " .. tostring(name)
    end

    local results
    for i = 1, #list do
        local entry = list[i]
        results = { entry.target[entry.method](entry.target, data) }
    end
    return table.unpack(results or {})
end

function RpcRegistry:has(name)
    return self.entries[name] ~= nil
end

return RpcRegistry
