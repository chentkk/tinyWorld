-- tinyworld/combat/ability_loader.lua
-- 框架侧能力加载器: 自动扫描 vscript 目录并注册 abilityFactory。
-- 只负责加载, 不包含具体能力/修饰符逻辑。

local combatUnit = require "tinyworld.combat.unit"
local kv = require "tinyworld.combat.kv"

local M = {}

-- 递归扫描目录下所有 .lua 文件, 返回相对路径列表
local function scanLuaFiles(root)
    local out = {}
    local p = io.popen("find " .. root .. " -type f -name '*.lua' 2>/dev/null")
    if not p then return out end

    for line in p:lines() do
        if line and line ~= "" then
            local rel = line:sub(#root + 2)
            out[#out + 1] = rel
        end
    end
    p:close()
    return out
end

local function modulePath(rel)
    return "game.scripts.vscripts." .. rel:gsub("%.lua$", ""):gsub("/", ".")
end

function M.setup(cfg)
    cfg = cfg or {}
    local vscriptRoot = cfg.vscriptRoot or "game/scripts/vscripts"
    local npcRoot = cfg.npcRoot or "game/scripts/npc"

    local abilityRel = {}
    for _, rel in ipairs(scanLuaFiles(vscriptRoot)) do
        local file = io.open(vscriptRoot .. "/" .. rel, "r")
        if file then
            local text = file:read("*a")
            file:close()
            for name in text:gmatch("([%w_]+)%s*=") do
                if name:match("^ability_") then
                    abilityRel[name] = rel:gsub("%.lua$", "")
                end
            end
        end

        require(modulePath(rel))
    end

    local factory = {}
    function factory.create(caster, abilityName, schema)
        local rel = abilityRel[abilityName]
        if not rel then return nil, "unknown ability " .. tostring(abilityName) end

        local npcPath = npcRoot .. "/" .. rel .. ".txt"
        local data = kv.load(npcPath, abilityName)
        if not data then return nil, "no npc data " .. abilityName end

        local cls = _G[abilityName]
        if not cls then return nil, "no vscript " .. abilityName end

        local ability = cls.new(caster, data, schema)
        ability:initModifier()
        return ability
    end

    combatUnit.setAbilityFactory(factory.create)
    return factory
end

return M
