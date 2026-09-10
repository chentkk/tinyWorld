-- game/scripts/vscripts/heroes/abaddon/borrowed_time.lua
-- 回光返照: 被动效果在 modifier 系统重新设计后再实现。

local Ability = require "tinyworld.combat.ability"

ability_borrowed_time = Ability.extend("ability_borrowed_time")

function ability_borrowed_time:startCooldown()
    Ability.startCooldown(self)
end

return ability_borrowed_time
