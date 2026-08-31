-- game/config/abilities.lua
-- 技能数据配置: vscript 与 npc 数据根目录。
-- 具体技能逻辑只存在于 game/scripts/vscripts/<hero>/<skill>.lua,
-- 技能数据只存在于 game/scripts/npc/<hero>/<skill>.txt。

return {
    vscriptRoot = "game/scripts/vscripts",
    npcRoot = "game/scripts/npc",
}
