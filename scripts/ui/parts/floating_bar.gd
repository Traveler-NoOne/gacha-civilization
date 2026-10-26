class_name FloatingBar
extends Control
## 悬浮按钮层（2026-10-25 从 game_screen 拆出）✓
##
## 科技树（左上）/ 日志（右上）/ 至宝·世界泡（左下）/ 结束周期（右下）
## 位置按**窗口尺寸**算，窗口变了调一次 `layout(size)` ✓
## 只发信号，不碰游戏规则 ✓

signal tech_pressed
signal log_pressed
signal nav_pressed(id: String)
signal end_pressed

const CORNER_MARGIN := 16.0
## 工具条（资源栏下方那条）的 y：资源栏 98 + 间隙 6
const TOOLS_TOP := 104.0
## 工具条按钮高度
const TOOLS_H := 26.0
## 左上角科技树按钮的 y：让开工具条
const CORNER_TOP := TOOLS_TOP + TOOLS_H + 16.0

var nav_buttons: Dictionary = {}
var _tech: Button
var _log: Button
var _end: Button
var _tools: HBoxContainer


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## nav_items：[{"id": "treasure", "name": "至宝"}, …]（**不含 world**）✓
func setup(nav_items: Array) -> void:
	_tech = UIKit.normal("科技树", 13)
	_tech.custom_minimum_size = Vector2(UI.px(84), UI.px(34))
	_tech.tooltip_text = "科技树"
	_tech.pressed.connect(func() -> void: tech_pressed.emit())
	add_child(_tech)

	_log = UIKit.image_button("book-ball", "日志", 40, 40)
	_log.pressed.connect(func() -> void: log_pressed.emit())
	add_child(_log)

	for v in nav_items:
		var vid := str(v["id"])
		var b := UIKit.normal(str(v["name"]), 14)
		b.custom_minimum_size = Vector2(UI.px(96), UI.px(40))
		b.pressed.connect(func() -> void: nav_pressed.emit(vid))
		add_child(b)
		nav_buttons[vid] = b

	_end = UIKit.primary("结束周期", 15)
	_end.custom_minimum_size = Vector2(UI.px(100), UI.px(40))
	_end.pressed.connect(func() -> void: end_pressed.emit())
	add_child(_end)


## 世界页的四个动作（地图铺满后，它原来那条工具栏没地方放了）✓
func add_tools(world: Control) -> void:
	_tools = HBoxContainer.new()
	_tools.add_theme_constant_override("separation", UI.fs(6))
	add_child(_tools)
	_add_tool("回到首都", func() -> void: world.call("center_on_capital"))
	_add_tool("重置缩放", func() -> void: world.call("reset_map_view"))
	var axis := _add_tool("显示坐标", Callable())
	axis.toggle_mode = true
	axis.toggled.connect(func(on: bool) -> void:
		world.call("set_axis", on))
	_add_tool("扩建地图（发展系统功能）", func() -> void: world.call("expand_map"))


func _add_tool(text: String, cb: Callable) -> Button:
	var b := UIKit.small(text, 12)
	b.custom_minimum_size = Vector2(0, UI.px(TOOLS_H))
	if cb.is_valid():
		b.pressed.connect(cb)
	_tools.add_child(b)
	return b


## ⚠️ 一律**按屏幕尺寸算绝对坐标**，父节点 resized 时重调 ✓
func layout(area: Vector2) -> void:
	var bh := UI.px(40)
	var margin := UI.px(CORNER_MARGIN)
	if is_instance_valid(_tools):
		_tools.position = Vector2(margin, UI.px(TOOLS_TOP))
	if is_instance_valid(_tech):
		_tech.position = Vector2(margin, UI.px(CORNER_TOP))
	if is_instance_valid(_log):
		_log.position = Vector2(area.x - margin - bh, UI.px(CORNER_TOP))

	# 左下角一排（至宝 / 世界泡），按 nav_items 顺序相邻排开
	var x := margin
	var y := area.y - margin - bh
	for vid in nav_buttons:
		var b: Button = nav_buttons[vid]
		if not is_instance_valid(b):
			continue
		b.position = Vector2(x, y)
		x += b.custom_minimum_size.x + 8.0
	if is_instance_valid(_end):
		_end.position = Vector2(area.x - margin - UI.px(100), y)


## 当前所在视图的按钮高亮（世界泡 / 至宝；在世界时两个都灭）✓
func set_nav_active(id: String) -> void:
	for vid in nav_buttons:
		var b: Button = nav_buttons[vid]
		if not is_instance_valid(b):
			continue
		var active := str(vid) == id
		UIKit.style_button(b, active)
		b.add_theme_color_override("font_color", Palette.GOLD if active else Palette.TEXT)
