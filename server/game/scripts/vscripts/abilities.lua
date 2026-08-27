-- game/scripts/vscripts/abilities.lua
-- 技能注册表: 从 npc/ 读取 dota 风格数据, 按 ScriptFile 加载同名 vscripts 类。
-- 具体技能逻辑只存在于 scripts 目录; 战斗核心框架位于 tinyworld/combat。

local kv = require "game.scripts.vscripts.kv"
local registry = {}

-- 技能名(与 npc 内 key 一致) -> npc 文件路径
local npcPath = {
    ability_aphotic_shield = "game/scripts/npc/heroes/abaddon/aphotic_shield.txt",
    ability_borrowed_time = "game/scripts/npc/heroes/abaddon/borrowed_time.txt",
    ability_mist_coil = "game/scripts/npc/heroes/abaddon/mist_coil.txt",
    ability_curse_of_avernus = "game/scripts/npc/heroes/abaddon/curse_of_avernus.txt",
}

function registry.create(caster, abilityName)
    local path = npcPath[abilityName]
    if not path then return nil, "unknown ability " .. tostring(abilityName) end

    local data = kv.load(path, abilityName)
    if not data then return nil, "no npc data " .. abilityName end

    local scriptModule = "game.scripts.vscripts." .. data.ScriptFile:gsub("/", ".")
    local mod = require(scriptModule)
    local cls = mod[abilityName]
    if not cls then return nil, "no vscript " .. abilityName end

    local ability = cls.new(caster, data)
    if ability.onCreateAbility then
        ability:onCreateAbility()
    end
    return ability
end

return registry
