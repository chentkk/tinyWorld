-- server/test/run_all.lua
-- 单元测试总入口。

package.path = "./?.lua;./?/init.lua;" .. package.path

local tests = {
    "test_proto", "test_schema", "test_space", "test_loadbalancer", "test_combat",
}

for _, name in ipairs(tests) do
    io.write("run " .. name .. " ...\n")
    dofile("test/" .. name .. ".lua")
end

print("ALL TESTS PASS")
