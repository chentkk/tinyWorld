# equipment_panel.gd — 装备栏(view: equipment)内容。
extends PanelBase
class_name EquipmentPanel


func _build_text(world: WorldState, entity_id: int) -> String:
	var view := world.views.get_view(entity_id, Protocol.VIEW_EQUIPMENT)
	var children: Dictionary = view["children"]

	var parts: Array = []
	for id in children.keys():
		var item: Dictionary = children[id]
		parts.append("位%d:item%d" % [int(item.get("slotName", 0)), int(item.get("itemId", 0))])

	return "装备 equipment(%d): %s" % [children.size(), ", ".join(parts)]
