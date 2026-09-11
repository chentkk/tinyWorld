# modifier_panel.gd — Buff/Debuff 列表(view: modifiers_view)。
extends PanelBase
class_name ModifierPanel


func _build_text(world: WorldState, entity_id: int) -> String:
	var view := world.views.get_view(entity_id, Protocol.VIEW_MODIFIERS)
	var children: Dictionary = view["children"]

	var parts: Array = []
	for id in children.keys():
		var mod: Dictionary = children[id]
		parts.append("%s x%s(%.1fs)" % [
			str(mod.get("name", "?")), str(mod.get("stack", 1)),
			float(mod.get("remaining", 0.0))])

	return "Buff(%d): %s" % [children.size(), ", ".join(parts)]
