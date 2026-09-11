# panel_base.gd — 所有数据面板的基类。
# 每个面板是一个单行 Label, 由 refresh() 从 WorldState 拉取自己关心的数据。
# 这样新增面板只需继承 + 实现 _build_text(), HUD 不必知道具体面板类型。
extends Label
class_name PanelBase

const FONT_SIZE := 11


func _init() -> void:
	add_theme_font_size_override("font_size", FONT_SIZE)
	add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))


# 子类覆写: 返回本面板要显示的一行文本。
func _build_text(_world: WorldState, _entity_id: int) -> String:
	return ""


func refresh(world: WorldState, entity_id: int) -> void:
	text = _build_text(world, entity_id)
