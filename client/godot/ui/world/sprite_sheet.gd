# sprite_sheet.gd — 序列帧表(sprite sheet)加载器。
#
# 目的: 美术只需要交一张 PNG + 一份 JSON 描述, 不用在 Godot 编辑器里手工拖帧。
# 描述文件格式(见 assets/sprites/hero.json):
#   {
#     "name": "hero",
#     "sheet": "res://assets/sprites/hero.png",
#     "frame_size": { "w": 64, "h": 64 },
#     "directions": ["down", "up", "side"],        // 行顺序(自上而下)
#     "actions": {
#       "idle": { "row_start": 0, "columns": 4, "fps": 6,  "loop": true },
#       "walk": { "row_start": 3, "columns": 6, "fps": 10, "loop": true }
#     }
#   }
# 生成的动画名 = "<action>_<row>", 如 "idle_down" / "walk_side"。
#
# directions 支持两种布局(见 game/world/facing.gd 的 render_for):
#   4 行 ["down","up","left","right"] —— 每向独立绘制, 不翻转
#   3 行 ["down","up","side"]         —— side 画"朝右", 朝左由 flip_h 镜像
extends RefCounted
class_name SpriteSheet

const DEFAULT_FRAME_SIZE := Vector2i(64, 64)
const DEFAULT_FPS := 8.0


# 从 JSON 描述文件构建 SpriteFrames。
# 文件缺失/解析失败/贴图缺失时返回 null, 由调用方回退到占位绘制。
static func load_frames(desc_path: String) -> SpriteFrames:
	if not FileAccess.file_exists(desc_path):
		return null

	var text := FileAccess.get_file_as_string(desc_path)
	var desc: Variant = JSON.parse_string(text)
	if typeof(desc) != TYPE_DICTIONARY:
		push_warning("[SpriteSheet] 描述文件解析失败: %s" % desc_path)
		return null

	var sheet_path := str(desc.get("sheet", ""))
	if sheet_path.is_empty() or not ResourceLoader.exists(sheet_path):
		push_warning("[SpriteSheet] 贴图不存在: %s" % sheet_path)
		return null

	var texture: Texture2D = load(sheet_path)
	if texture == null:
		return null

	var frame_size := _parse_frame_size(desc.get("frame_size", null))
	var directions: Array = desc.get("directions", ["down", "up", "side"])
	var actions: Dictionary = desc.get("actions", {})
	if actions.is_empty():
		push_warning("[SpriteSheet] 描述文件无 actions: %s" % desc_path)
		return null

	var frames := SpriteFrames.new()
	# 移除默认的 "default" 动画, 避免残留一个空动画。
	if frames.has_animation("default"):
		frames.remove_animation("default")

	for action_name in actions.keys():
		var action: Dictionary = actions[action_name]
		var row_start := int(action.get("row_start", 0))
		var columns := int(action.get("columns", 1))
		var fps := float(action.get("fps", DEFAULT_FPS))
		var loop := bool(action.get("loop", true))

		for i in directions.size():
			var dir_name := str(directions[i])
			var anim := "%s_%s" % [action_name, dir_name]
			if not frames.has_animation(anim):
				frames.add_animation(anim)
			frames.set_animation_speed(anim, fps)
			frames.set_animation_loop(anim, loop)

			var row := row_start + i
			for col in columns:
				var region := Rect2(
					col * frame_size.x, row * frame_size.y,
					frame_size.x, frame_size.y)
				var atlas := AtlasTexture.new()
				atlas.atlas = texture
				atlas.region = region
				frames.add_frame(anim, atlas)

	return frames


static func _parse_frame_size(raw: Variant) -> Vector2i:
	if typeof(raw) == TYPE_DICTIONARY:
		return Vector2i(int(raw.get("w", 64)), int(raw.get("h", 64)))
	if typeof(raw) == TYPE_ARRAY and raw.size() >= 2:
		return Vector2i(int(raw[0]), int(raw[1]))
	return DEFAULT_FRAME_SIZE
