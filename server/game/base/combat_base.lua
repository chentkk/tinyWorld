-- game/base/combat_base.lua
-- baseapp 侧战斗组件: 负责把 base 侧运行时数据打包给 cellapp 构建 cellentity。
-- 当前只打包 abilities; 后续装备等玩法数据在此扩展。

local component = require "tinyworld.entity.component"

local CombatBase = component.extend("CombatBase")

function CombatBase:ctor(entity, name)
    component.ctor(self, entity, name)
end

-- 把本组件需要传输给 cellapp 的数据整理成 table
function CombatBase:buildCellData()
    local entity = self.entity
    local data = {}

    local abilities = entity:getRecord("abilities")
    if abilities then
        local names = {}
        for _, row in ipairs(abilities:rowsList()) do
            names[#names + 1] = row.name
        end
        data.abilities = names
    end

    return data
end

return CombatBase
