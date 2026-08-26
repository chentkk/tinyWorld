-- game/scripts/vscripts/heroes/abaddon/ability_abaddon_borrowed_time_lua.lua
-- 回光返照: 立即进入持续施法, 期间把受到的伤害转化为治疗。
-- 伤害结算统一走 combdamage, 不做任何网络同步。

local combatAbility = require "game.scripts.vscripts.combat.ability"
local M = {}

M.ability_abaddon_borrowed_time_lua = combatAbility.Ability.extend("ability_abaddon_borrowed_time_lua")

function M.ability_abaddon_borrowed_time_lua:OnChannelStart()
    self.caster.borrowedTime = true
end

function M.ability_abaddon_borrowed_time_lua:OnChannelFinish()
    self.caster.borrowedTime = false
end

return M
