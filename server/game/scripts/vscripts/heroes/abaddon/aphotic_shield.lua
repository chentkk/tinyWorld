-- game/scripts/vscripts/heroes/abaddon/aphotic_shield.lua
-- 无光之盾: 施法给目标。具体 modifier 待设计完整后重新实现。

local Ability = require "tinyworld.combat.ability"

ability_aphotic_shield = Ability.extend("ability_aphotic_shield")

function ability_aphotic_shield:OnSpellStart()
    local target = self:GetCursorTarget() or self:GetCaster()
    -- TODO: 在 modifier 系统重新设计后再实现伤害吸收效果
end

return ability_aphotic_shield
