-- game/scripts/vscripts/heroes/abaddon/modifier_abaddon_aphotic_shield_lua.lua
-- 无光之盾 modifier: 吸收伤害, 到期或持有者受伤时由逻辑脚本驱动。

local combatModifier = require "game.scripts.vscripts.combat.modifier"
local M = {}

M.modifier_abaddon_aphotic_shield_lua = combatModifier.Modifier.extend("modifier_abaddon_aphotic_shield_lua")

function M.modifier_abaddon_aphotic_shield_lua:OnCreated(params)
    self.absorb = tonumber(self.ability.data.damageAbsorb) or 0
end

function M.modifier_abaddon_aphotic_shield_lua:OnRefresh(params)
    self.absorb = tonumber(self.ability.data.damageAbsorb) or self.absorb
end

return M
