-- game/scripts/vscripts/heroes/abaddon/ability_abaddon_aphotic_shield_lua.lua
-- 无光之盾: 施法时间结束后给目标套盾 modifier。

local combatAbility = require "game.scripts.vscripts.combat.ability"
local M = {}

M.ability_abaddon_aphotic_shield_lua = combatAbility.Ability.extend("ability_abaddon_aphotic_shield_lua")

function M.ability_abaddon_aphotic_shield_lua:OnSpellStart()
    local target = self.target or self.caster
    local modifierName = "modifier_abaddon_aphotic_shield_lua"
    if target.addModifier then
        target:addModifier(require("game.scripts.vscripts.heroes.abaddon." .. modifierName)
            [modifierName].new(self.caster, self, tonumber(self.data.duration) or 6))
    end
end

return M
