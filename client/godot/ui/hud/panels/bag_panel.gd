# bag_panel.gd — 背包(view: bag)内容。
extends PanelBase
class_name BagPanel


func _build_text(world: WorldState, entity_id: int) -> String:
	var view := world.views.get_view(entity_id, Protocol.VIEW_BAG)
	var props: Dictionary = view["props"]
	var capacity := int(props.get("capacity", 0))
	var children: Dictionary = view["children"]

	var parts: Array = []
	for id in children.keys():
		var item: Dictionary = children[id]
		parts.append("slot%d:item%d x%d" % [
			int(item.get("slot", 0)), int(item.get("itemId", 0)), int(item.get("count", 0))])

	return "背包 bag(%d/%s): %s" % [
		children.size(), str(capacity) if capacity > 0 else "?", ", ".join(parts)]
