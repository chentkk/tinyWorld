# ability_panel.gd — 技能列表(view: abilities_view, selfOnly)。
# 显示序号 -> 技能名 -> 状态, 序号即施法时 onCastAbility 的 index 参数。
# 顺序由 WorldState.abilities() 统一提供, 与施法输入保持一致。
extends PanelBase
class_name AbilityPanel


func _build_text(world: WorldState, entity_id: int) -> String:
	var abilities := world.abilities(entity_id)

	var parts: Array = []
	var index := 1
	for ab in abilities:
		var state := str(ab.get("state", ""))
		var suffix := " [%s]" % state if state != "ready" else ""
		parts.append("%d:%s%s" % [index, str(ab.get("id", "?")), suffix])
		index += 1

	return "技能(%d): %s" % [abilities.size(), ", ".join(parts)]
