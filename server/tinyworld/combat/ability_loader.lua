-- tinyworld/combat/ability_loader.lua
-- 框架侧能力加载器/工厂: 自动扫描 vscript 目录,
-- 提供 setAbilityFactory / createAbility / loadAbilities / castAbility。
-- 只负责加载与工厂注册, 不包含具体技能逻辑。

local kv = require "tinyworld.combat.kv"

local M = {}
M.abilityFactory = nil

local function scanLuaFiles(root)
    local out = {}
    local p = io.popen("find " .. root .. " -type f -name '*.lua' 2>/dev/null")
    if not p then return out end

    for line in p:lines() do
        if line and line ~= "" then
            out[#out + 1] = line:sub(#root + 2)
        end
    end
    p:close()
    return out
end

local function modulePath(rel)
    return "game.scripts.vscripts." .. rel:gsub("%.lua$", ""):gsub("/", ".")
end

function M.setAbilityFactory(factory)
    M.abilityFactory = factory
end

function M.createAbility(caster, abilityName)
    if not M.abilityFactory then return nil, "ability factory not set" end

    local schema = nil
    if caster.getContainer then
        local view = caster:getContainer("abilities_view")
        schema = view and view.def.childSchema
    end
    return M.abilityFactory(caster, abilityName, schema)
end

-- 装配技能: 与迁移还原走同一条容器构建流程(view:addFromData -> Ability.fromData),
-- 这里只提供技能名, 其余交给 abilities_view 的子对象类。
function M.loadAbilities(unit, names)
    local view = unit:getContainer("abilities_view")
    if view then
        for _, abilityName in ipairs(names or {}) do
            view:addFromData({ id = abilityName })
        end
    end
    return view and view:childrenList() or {}
end

function M.castAbility(unit, index, target)
    local view = unit:getContainer("abilities_view")
    local ab = view and view:childrenList()[index]
    if not ab then return false end
    return ab:cast(target)
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

        local data = kv.load(npcRoot .. "/" .. rel .. ".txt", abilityName)
        if not data then return nil, "no npc data " .. abilityName end

        local cls = _G[abilityName]
        if not cls then return nil, "no vscript " .. abilityName end

        local ability = cls.new(caster, data, schema)
        ability:initModifier()
        return ability
    end

    M.setAbilityFactory(factory.create)
    return factory
end

return M
