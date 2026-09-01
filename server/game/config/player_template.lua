-- game/config/player_template.lua
-- 新角色 / 无存档读档时的默认数据模板。
-- 只描述默认数据, 不包含读取/存储逻辑(存储由框架 player_store 负责)。

return {
    props = {
        level = 1,
        hp = 100,
        maxHp = 100,
        mp = 100,
        maxMp = 100,
        gold = 0,
        scene = "main",
        x = 10,
        y = 10,
    },
    records = {
        abilities = {
            { name = "ability_aphotic_shield" },
            { name = "ability_borrowed_time" },
            { name = "ability_mist_coil" },
            { name = "ability_blood_harvest" },
            { name = "ability_projectile_track" },
            { name = "ability_projectile_line" },
        },
    },
    containers = {},
}
