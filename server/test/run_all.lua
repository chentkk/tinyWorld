-- server/test/run_all.lua
-- 单元测试总入口。

package.path = "./?.lua;./?/init.lua;" .. package.path

local tests = {
    "test_proto", "test_schema", "test_record", "test_space", "test_loadbalancer",
    "test_direction",
    "test_batch_sync",
    "test_ghost_sync", "test_ghost_promote", "test_migration",
    "test_migration_data",
    "test_custom_data",
    "test_container_order",
    "test_migrate_rpc",
    "test_migrate_factory",
    "test_projectile",
    "test_combat_entity",
    "test_server_object",
    "test_gameplay_tags",
    "test_timer_wheel",
    "test_spatial_index",
    "test_projectile_cross_cell",
    "test_ghost_settlement",
}

for _, name in ipairs(tests) do
    io.write("run " .. name .. " ...\n")
    dofile("test/" .. name .. ".lua")
end

print("ALL TESTS PASS")
