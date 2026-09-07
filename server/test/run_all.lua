-- server/test/run_all.lua
-- 单元测试总入口。

package.path = "./?.lua;./?/init.lua;" .. package.path

local tests = {
    "test_proto", "test_schema", "test_space", "test_loadbalancer", "test_combat",
    "test_ghost_sync", "test_blood_harvest", "test_ghost_promote", "test_migration",
    "test_projectile",
    "test_combat_entity",
    "test_server_object",
    "test_gameplay_tags",
    "test_spatial_index",
    "test_projectile_cross_cell",
    "test_ghost_settlement",
}

for _, name in ipairs(tests) do
    io.write("run " .. name .. " ...\n")
    dofile("test/" .. name .. ".lua")
end

print("ALL TESTS PASS")
