extends Control
## 主页面：开始游戏（继续 / 新游戏 / 读取游戏）、游戏设置、退出游戏、反馈。
## 对应设计文档「主页面」章节。

signal start_game_requested(mode: String)

var _expand_box: VBoxContainer
var _btn_continue: Button
var _btn_load: Button
var _dialog: DialogLayer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# 背景装饰：几何图形（代替美术资源）
	var deco := GeoIcon.Decor.new()
	deco.set_anchors_preset(Control.PRESET_FULL_RECT)
	deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(deco)

	var center := VBoxContainer.new()
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center.grow_vertical = Control.GROW_DIRECTION_BOTH
	center.custom_minimum_size = Vector2(360, 0)
	center.add_theme_constant_override("separation", 10)
	add_child(center)

	var title := Label.new()
	title.text = "抽 卡 文 明"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 54)
	title.add_theme_color_override("font_color", Color(0.96, 0.86, 0.55))
	center.add_child(title)

	var sub := Label.new()
	sub.text = "Turn-based Roguelite Gacha Civilization · 可玩 Demo"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", Color(0.55, 0.58, 0.68))
	center.add_child(sub)

	center.add_child(_spacer(18))

	var btn_start := UIKit.primary("开始游戏")
	btn_start.pressed.connect(_toggle_expand)
	center.add_child(btn_start)

	_expand_box = VBoxContainer.new()
	_expand_box.add_theme_constant_override("separation", 6)
	_expand_box.visible = false
	center.add_child(_expand_box)

	_btn_continue = UIKit.normal("继续游戏")
	_btn_continue.tooltip_text = "读取最后一次退出时的进度"
	_btn_continue.pressed.connect(func() -> void: start_game_requested.emit("continue"))
	_expand_box.add_child(_btn_continue)

	var btn_new := UIKit.normal("新游戏")
	btn_new.pressed.connect(func() -> void: start_game_requested.emit("new"))
	_expand_box.add_child(btn_new)

	_btn_load = UIKit.normal("读取游戏")
	_btn_load.pressed.connect(_open_load_dialog)
	_expand_box.add_child(_btn_load)

	center.add_child(_spacer(8))

	var btn_settings := UIKit.normal("游戏设置")
	btn_settings.pressed.connect(_open_settings)
	center.add_child(btn_settings)

	var btn_quit := UIKit.normal("退出游戏")
	btn_quit.pressed.connect(func() -> void: get_tree().quit())
	center.add_child(btn_quit)

	# 右下角反馈按钮
	var feedback := UIKit.small("反馈")
	feedback.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	feedback.position = Vector2(-110, -56)
	feedback.custom_minimum_size = Vector2(92, 34)
	feedback.pressed.connect(_open_feedback)
	add_child(feedback)

	# v1.5：左下角免责声明
	var disclaimer := Label.new()
	disclaimer.text = Consts.DISCLAIMER_TEXT
	disclaimer.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	disclaimer.position = Vector2(16, -34)
	disclaimer.grow_vertical = Control.GROW_DIRECTION_BEGIN
	disclaimer.add_theme_font_size_override("font_size", 11)
	disclaimer.add_theme_color_override("font_color", UIKit.TEXT_FAINT)
	add_child(disclaimer)

	_refresh_buttons()


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _refresh_buttons() -> void:
	var can_continue := GameState.has_continue()
	_btn_continue.disabled = not can_continue
	_btn_continue.modulate = Color(1, 1, 1, 1) if can_continue else Color(0.5, 0.5, 0.55, 0.75)
	if not can_continue:
		_btn_continue.tooltip_text = "没有上次退出的自动存档"
	var has_any := GameState.any_save()
	_btn_load.disabled = not has_any
	_btn_load.modulate = Color(1, 1, 1, 1) if has_any else Color(0.5, 0.5, 0.55, 0.75)
	if not has_any:
		_btn_load.tooltip_text = "还没有任何存档"


func _toggle_expand() -> void:
	_expand_box.visible = not _expand_box.visible
	_refresh_buttons()


# ---------------------------------------------------------------------------
# 读取游戏
# ---------------------------------------------------------------------------
func _open_load_dialog() -> void:
	_close_dialog()
	var d := UIKit.dialog("读取游戏")
	_dialog = d
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	d.set_content(list)
	var found := false
	for i in Consts.SAVE_SLOTS:
		var summ := GameState.slot_summary(i)
		if summ.is_empty():
			continue
		found = true
		var slot := i
		var b := UIKit.normal("槽位 %d　周期 %d　地块 %d　角色 %d" % [
			i + 1, summ["cycle"], summ["tiles"], summ["chars"]])
		b.pressed.connect(func() -> void:
			if GameState.load_from_slot(slot):
				close_dialog()
				start_game_requested.emit("load"))
		list.add_child(b)
	if not found:
		var l := Label.new()
		l.text = "没有任何存档。"
		l.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
		list.add_child(l)
	add_child(d)


func _open_settings() -> void:
	_close_dialog()
	var d := UIKit.dialog("游戏设置")
	_dialog = d
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	d.set_content(list)

	list.add_child(_section("画面设置"))
	var res_opt := OptionButton.new()
	res_opt.add_item("1280 x 720")
	res_opt.add_item("1600 x 900")
	res_opt.add_item("1920 x 1080")
	res_opt.selected = 0
	res_opt.item_selected.connect(func(idx: int) -> void:
		var sizes := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
		DisplayServer.window_set_size(sizes[idx]))
	list.add_child(_row("分辨率", res_opt))

	var quality := OptionButton.new()
	quality.add_item("兼容（GL Compatibility）")
	quality.selected = 0
	quality.disabled = true
	list.add_child(_row("画质档位", quality))

	var fps := OptionButton.new()
	fps.add_item("不限")
	fps.add_item("60")
	fps.add_item("30")
	fps.selected = 0
	fps.item_selected.connect(func(idx: int) -> void:
		Engine.max_fps = [0, 60, 30][idx])
	list.add_child(_row("帧率限制", fps))

	# v1.2：自动存档周期数
	list.add_child(_section("存档设置"))
	var auto_spin := SpinBox.new()
	auto_spin.min_value = Consts.AUTOSAVE_INTERVAL_MIN
	auto_spin.max_value = Consts.AUTOSAVE_INTERVAL_MAX
	auto_spin.step = 1
	auto_spin.value = GameState.autosave_interval()
	auto_spin.tooltip_text = "默认每 1 个周期自动存档一次；可以改成每 N 个周期存档一次"
	auto_spin.value_changed.connect(func(v: float) -> void:
		GameState.set_autosave_interval(int(v)))
	list.add_child(_row("自动存档周期数", auto_spin))
	var auto_hint := Label.new()
	auto_hint.text = "默认情况下为每周期自动存档；这里可以设置自定义数量的周期进行一次自动存档（%d ~ %d）。" % [
		Consts.AUTOSAVE_INTERVAL_MIN, Consts.AUTOSAVE_INTERVAL_MAX]
	auto_hint.add_theme_font_size_override("font_size", 11)
	auto_hint.add_theme_color_override("font_color", Color(0.62, 0.64, 0.72))
	auto_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(auto_hint)

	list.add_child(_section("音效设置"))
	list.add_child(_volume_row("总音量", "Master"))
	list.add_child(_volume_row("背景音乐", "Music"))
	list.add_child(_volume_row("战斗音效", "SFX"))

	list.add_child(_section("操控设置"))
	var hint := Label.new()
	hint.text = "世界地图：鼠标左键拖动平移、滚轮缩放、点击地块查看详情。\n快捷键：1-5 切换功能页，空格 = 结束周期，Esc = 关闭弹窗。"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.72, 0.74, 0.8))
	list.add_child(hint)

	add_child(d)


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = "— %s —" % text
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(0.9, 0.8, 0.5))
	return l


func _row(label_text: String, node: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(90, 0)
	h.add_child(l)
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(node)
	return h


func _volume_row(label_text: String, bus: String) -> HBoxContainer:
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.value = 80
	slider.custom_minimum_size = Vector2(180, 0)
	slider.value_changed.connect(func(v: float) -> void:
		var idx := AudioServer.get_bus_index(bus)
		if idx >= 0:
			AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(0.0001, v / 100.0))))
	return _row(label_text, slider)


func _open_feedback() -> void:
	_close_dialog()
	var d := UIKit.dialog("反馈")
	_dialog = d
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)

	# v1.2：显示当前 demo 版本
	var ver := Label.new()
	ver.text = "当前版本：%s" % Consts.DEMO_VERSION_FULL
	ver.add_theme_font_size_override("font_size", 13)
	ver.add_theme_color_override("font_color", UIKit.GOLD)
	v.add_child(ver)
	v.add_child(UIKit.spacer(2.0))

	var lines := [
		"感谢试玩《抽卡文明》Demo！",
		"",
		"QQ 群：%s" % Consts.FEEDBACK_QQ_GROUP,
		"邮箱：%s" % Consts.FEEDBACK_EMAIL,
		"",
		"本 Demo 所有美术均为几何图形占位，正式版会替换为完整美术资源。",
		Consts.DISCLAIMER_TEXT,
	]
	for t in lines:
		var l := Label.new()
		l.text = t
		l.add_theme_font_size_override("font_size", 13)
		v.add_child(l)

	# v1.2：作弊功能勾选框
	v.add_child(UIKit.spacer(6.0))
	var rule := ColorRect.new()
	rule.color = UIKit.LINE_SOFT
	rule.custom_minimum_size = Vector2(0, 1)
	v.add_child(rule)
	v.add_child(UIKit.spacer(4.0))

	var cheat_box := UIKit.toggle_checkbox("作弊功能", GameState.cheat_enabled())
	cheat_box.tooltip_text = "点击切换作弊功能（开启前会二次确认）"
	v.add_child(cheat_box)
	var cl := UIKit.dim("勾选后顶部资源栏会出现「作弊」按钮。", 11)
	cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(cl)

	cheat_box.toggled.connect(func(on: bool) -> void:
		if on:
			# 先弹二次确认；确认前把勾选框还原成未勾选
			cheat_box.set_pressed_no_signal(false)
			var confirm := UIKit.confirm("开启作弊功能",
				"你确定开启作弊功能吗？这也许会摧毁你的游戏体验。",
				func() -> void:
					GameState.set_cheat_enabled(true)
					cheat_box.set_pressed_no_signal(true))
			add_child(confirm)
		else:
			GameState.set_cheat_enabled(false))

	d.set_content(v)
	add_child(d)


func _close_dialog() -> void:
	if is_instance_valid(_dialog):
		_dialog.queue_free()
	_dialog = null


func close_dialog() -> void:
	_close_dialog()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed:
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			_close_dialog()
