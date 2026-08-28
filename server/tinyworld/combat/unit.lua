-- tinyworld/combat/unit.lua
-- 战斗单位扩展: 管理 modifier 与 ability, 驱动每帧 update。
-- modifier/ability 的增删与状态变化会像普通容器一样直接写入对应视图,
-- 由 buildOutbox 统一 flush, 战斗核心不碰网络。

local M = {}

-- 能力工厂: 项目启动时由 game.scripts.vscripts.abilities 注册。
-- 能力创建由 unit/entity 层统一处理, 业务组件无需知道 npc / vscripts 路径。
M.abilityFactory = nil

function M.setAbilityFactory(factory)
    M.abilityFactory = factory
end

function M.createAbility(caster, abilityName)
    if not M.abilityFactory then return nil, "ability factory not set" end
    return M.abilityFactory(caster, abilityName)
end

function M.modifiersSnapshot(unit)
    local out = {}
    for _, mod in ipairs(unit.modifiers or {}) do
        out[#out + 1] = {
            name = mod:GetModifierName(),
            duration = mod.duration,
            stack = mod.stack,
        }
    end
    return out
end

M.snapshot = M.modifiersSnapshot

local function combatView(unit, viewName)
    if not unit.getContainer then return nil end
    local cont = unit:getContainer(viewName)
    if cont and cont:isViewOpened() then
        return cont
    end
end

local function syncObjectToView(unit, viewName, object)
    if not object then return end
    local cont = combatView(unit, viewName)
    if not cont then return end

    local data = object:viewData()
    local id = data.id
    if not cont:has(id) then
        cont:add(data)
        return
    end

    local child = cont:get(id)
    for name, value in pairs(data) do
        child[name] = value
    end
end

function M.apply(unit)
    if unit.combatApplied then return unit end
    unit.combatApplied = true

    unit.modifiers = unit.modifiers or {}
    unit.abilities = unit.abilities or {}

    function unit:addModifier(mod, ability, params)
        if not mod then return nil end

        -- example 风格: 直接传 modifier 名字, 由全局 vscripts 类实例化
        if type(mod) == "string" then
            local cls = _G[mod]
            if not cls then return nil end
            mod = cls.new(self, ability, params)
        end

        if not mod.owner then mod.owner = self end

        local name = mod:GetModifierName()
        for _, old in ipairs(self.modifiers) do
            if old:GetModifierName() == name then
                old:refresh({})
                self:emit("combat_modifier_refresh", name, old.stack)
                return old
            end
        end

        self.modifiers[#self.modifiers + 1] = mod
        mod:OnCreated(mod._params or {})
        syncObjectToView(self, "modifiers_view", mod)
        self:emit("combat_modifier_add", name, mod.duration, mod.stack)
        return mod
    end

    function unit:removeModifier(mod)
        for i, old in ipairs(self.modifiers) do
            if old == mod then
                table.remove(self.modifiers, i)
                local cont = combatView(self, "modifiers_view")
                if cont then cont:remove(mod.uid) end
                self:emit("combat_modifier_remove", mod:GetModifierName())
                return mod
            end
        end
        return nil
    end

    function unit:hasModifier(name)
        for _, mod in ipairs(self.modifiers) do
            if mod:GetModifierName() == name then return mod end
        end
        return nil
    end

    function unit:updateCombat(dt)
        for i, mod in ipairs(self.modifiers) do
            if mod then
                mod:update(dt)
                syncObjectToView(self, "modifiers_view", mod)
            end
        end
        for i, ab in ipairs(self.abilities) do
            if ab then
                ab:update(dt)
                syncObjectToView(self, "abilities_view", ab)
            end
        end
    end

    function unit:loadAbilities(names)
        self.abilities = {}
        for _, abilityName in ipairs(names or {}) do
            local ability = M.createAbility(self, abilityName)
            if ability then
                self.abilities[#self.abilities + 1] = ability
                syncObjectToView(self, "abilities_view", ability)
            end
        end
        return self.abilities
    end

    function unit:castAbility(index, target)
        local ab = self.abilities[index]
        if not ab then return false end
        return ab:cast(target)
    end

    return unit
end

return M
