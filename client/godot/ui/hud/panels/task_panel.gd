# task_panel.gd — 当前任务(record: current_tasks)内容。
extends PanelBase
class_name TaskPanel


func _build_text(world: WorldState, entity_id: int) -> String:
	var rows := world.records.get_rows(entity_id, Protocol.RECORD_CURRENT_TASKS)

	var parts: Array = []
	for key in rows.keys():
		var row: Dictionary = rows[key]
		parts.append("task%s(state%s,p%s)" % [
			str(row.get("taskid", "?")), str(row.get("state", 0)), str(row.get("progress", 0))])

	return "任务 current_tasks(%d): %s" % [rows.size(), ", ".join(parts)]
