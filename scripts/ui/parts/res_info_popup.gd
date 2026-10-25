class_name ResInfoPopup
extends Control
## 点资源 chip 后的「每周期收支」小窗（2026-10-25 从 game_screen 拆出）✓
##
## 结构：全屏点击层（点任意处关闭）+ 贴着被点 chip 的面板
## 用法：`show_for(key, chip_global_rect)` / `hide_popup()`

var _panel: PanelContainer
var _title: Label
var _rows: VBoxContainer
var _net: Label


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 点任意处关闭
	var bg := Button.new()
	bg.focus_mode = Control.FOCUS_NONE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.pressed.connect(hide_popup)
	add_child(bg)

	_panel = UIKit.panel(Palette.BG_PANEL_2, Palette.LINE, 6)
	_panel.custom_minimum_size = Vector2(UI.px(250), UI.px(0))
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", UI.fs(2))
	_panel.add_child(v)
	_title = UIKit.title("", 14)
	v.add_child(_title)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", UI.fs(2))
	v.add_child(_rows)
	_net = UIKit.text_label("", 12, Palette.TEXT)
	v.add_child(_net)


## 在某个 chip 下方弹出（rect 是 chip 的**全局**矩形）✓
func show_for(key: String, rect: Rect2) -> void:
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	_title.text = "%s · 每周期收支" % Consts.res_name(key)

	if key == "pop":
		# 人力不是产出资源：受住房上限约束（和资源栏口径一致）
		_rows.add_child(UIKit.dim("人力不是产出资源，受住房上限约束。"))
		_rows.add_child(_break_row("住房上限", float(Derived.housing_capacity(GameState.state))))
		_rows.add_child(_break_row("已指派", float(Derived.assigned_pop(GameState.state))))
		_rows.add_child(_break_row("空闲", float(Derived.free_pop(GameState.state))))
		_net.visible = false
	else:
		var bd: Dictionary = Admin.resource_breakdown(GameState.state, key)
		var inc: Array = bd["income"]
		var upk: Array = bd["upkeep"]
		var net := 0.0
		for e in inc:
			net += float(e["amount"])
			_rows.add_child(_break_row(str(e["label"]), float(e["amount"])))
		if not inc.is_empty() and not upk.is_empty():
			var sep := ColorRect.new()
			sep.color = Palette.LINE_SOFT
			sep.custom_minimum_size = Vector2(UI.px(0), UI.px(1))
			_rows.add_child(sep)
		for e in upk:
			net += float(e["amount"])
			_rows.add_child(_break_row(str(e["label"]), float(e["amount"])))
		if inc.is_empty() and upk.is_empty():
			_rows.add_child(UIKit.dim("该资源本期没有收支。"))
		_net.visible = true
		_net.text = "净收支 %+.1f / 周期" % net
		_net.add_theme_color_override("font_color", Palette.OK if net >= 0.0 else Palette.BAD)

	# 贴着 chip 下方，并夹在视口内
	var vs := get_viewport_rect().size
	var pos := Vector2(rect.position.x, rect.end.y + 4.0)
	pos.x = clampf(pos.x, 8.0, maxf(8.0, vs.x - 258.0))
	pos.y = clampf(pos.y, 8.0, maxf(8.0, vs.y - 220.0))
	_panel.position = pos
	visible = true


func hide_popup() -> void:
	visible = false


## 一行「名称 …… 数值」
func _break_row(label_text: String, amount: float) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", UI.fs(8))
	var l := UIKit.text_label(label_text, 11, Palette.TEXT_DIM)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	h.add_child(UIKit.text_label("%+.1f" % amount, 12,
		Palette.OK if amount >= 0.0 else Palette.BAD))
	return h
