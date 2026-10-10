extends Control
## 主页面：开始游戏（继续 / 新游戏 / 读取游戏）、游戏设置、退出游戏、反馈。
## 对应设计文档「主页面」章节。

signal start_game_requested(mode: String)

var _expand_box: VBoxContainer
var _btn_continue: Button
var _btn_load: Button
var _dialog: DialogLayer

## v1.8.12：设置菜单的类别。
## 目前分类为：画面设置、辅助设置、音效设置、键位设置
const SETTING_TABS := [
	{"id": "video", "name": "画面设置"},
	{"id": "assist", "name": "辅助设置"},
	{"id": "audio", "name": "音效设置"},
	{"id": "keys", "name": "键位设置"},
]


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
	var d := UIKit.dialog("游戏设置", 640.0)
	_dialog = d
	
	# 创建设置菜单一级容器竖式
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	d.set_content(outer)
	
	# 创建设置菜单二级容器横式
	var mid := HBoxContainer.new()
	mid.add_theme_constant_override("separation", 14)
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(mid)
	
	# 创建设置菜单按钮列表
	var tabs := VBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	tabs.custom_minimum_size = Vector2(100, 0)
	mid.add_child(tabs)
	
	# 创建设置菜单的内容页父容器
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_child(body)
	
	# 创建主要的四个设置菜单的变量
	# 画面设置菜单
	var page_video := VBoxContainer.new()
	# 辅助设置菜单
	var page_assist := VBoxContainer.new()
	# 音效设置菜单
	var page_audio := VBoxContainer.new()
	# 键位设置菜单
	var page_keys := VBoxContainer.new()
	# 创建一个存储四个菜单的页面词典
	var pages := {"video": page_video, "assist": page_assist, "audio": page_audio, "keys": page_keys}
	# 通过循环初始化每页
	for t in SETTING_TABS:
		# 初始化页面
		var pg: VBoxContainer = pages[str(t["id"])]
		pg.add_theme_constant_override("separation", 8)
		pg.visible = false
		body.add_child(pg)
		
		# 初始化按钮
		var b := UIKit.normal(str(t["name"]), 13)
		b.set_meta("setting_id", str(t["id"]))
		b.custom_minimum_size = Vector2(100, 34)
		b.pressed.connect(_switch_setting_page.bind(pages, tabs, str(t["id"])))
		tabs.add_child(b)
		
	# 初始化画面设置
	# v1.8.20：分辨率选项来自 UI 尺寸词典（唯一来源），改完**保存**、下次启动生效
	var res_opt := OptionButton.new()
	var _res_keys: Array = UI.resolutions()
	for res_key in _res_keys:
		res_opt.add_item(UI.label_of(str(res_key)))
	var _ri := _res_keys.find(AppSettings.resolution())
	res_opt.selected = _ri if _ri >= 0 else _res_keys.find(UI.BASE_KEY)
	page_video.add_child(_row("分辨率", res_opt))
	var res_hint := Label.new()
	res_hint.text = "改完保存，下次启动生效。"
	res_hint.add_theme_font_size_override("font_size", 11)
	res_hint.add_theme_color_override("font_color", Color(0.62, 0.64, 0.72))
	page_video.add_child(res_hint)
	
	# 初始化画质设置
	var quality := OptionButton.new()
	quality.add_item("兼容（GL Compatibility）")
	quality.selected = 0
	quality.disabled = true
	page_video.add_child(_row("画质档位", quality))

	# 初始化帧率设置
	var fps := OptionButton.new()
	fps.add_item("不限")
	fps.add_item("60")
	fps.add_item("30")
	var _fps_opts := [0,60,30]
	var _fi := _fps_opts.find(Engine.max_fps)
	fps.selected = _fi if _fi >= 0 else 0
	page_video.add_child(_row("帧率限制", fps))

	# v1.2：自动存档周期数
	var auto_spin := SpinBox.new()
	auto_spin.min_value = Consts.AUTOSAVE_INTERVAL_MIN
	auto_spin.max_value = Consts.AUTOSAVE_INTERVAL_MAX
	auto_spin.step = 1
	auto_spin.value = GameState.autosave_interval()
	auto_spin.tooltip_text = "默认每 1 个周期自动存档一次；可以改成每 N 个周期存档一次"
	page_assist.add_child(_row("自动存档周期数", auto_spin))
	var auto_hint := Label.new()
	auto_hint.text = "默认情况下为每周期自动存档；这里可以设置自定义数量的周期进行一次自动存档（%d ~ %d）。" % [
		Consts.AUTOSAVE_INTERVAL_MIN, Consts.AUTOSAVE_INTERVAL_MAX]
	auto_hint.add_theme_font_size_override("font_size", 11)
	auto_hint.add_theme_color_override("font_color", Color(0.62, 0.64, 0.72))
	auto_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page_assist.add_child(auto_hint)
	
	# 初始化音效设置
	var vol_pending := {}
	page_audio.add_child(_volume_row("总音量", "Master", vol_pending))
	page_audio.add_child(_volume_row("背景音乐", "Music", vol_pending))
	page_audio.add_child(_volume_row("战斗音效", "SFX", vol_pending))

	# 初始化键位设置
	var hint := Label.new()
	hint.text = "世界地图：鼠标左键拖动平移、滚轮缩放、点击地块查看详情。\n快捷键：「1/2/3」切换功能页，空格 = 结束周期，Esc = 关闭弹窗。"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.72, 0.74, 0.8))
	page_keys.add_child(hint)
	
	# 弹窗确定区
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation", 8)
	outer.add_child(footer)
	
	var btn_cancel := UIKit.normal("取消", 14)
	btn_cancel.custom_minimum_size = Vector2(96, 34)
	btn_cancel.pressed.connect(func() -> void:
		close_dialog())
	footer.add_child(btn_cancel)
	
	var btn_ok := UIKit.primary("确认", 14)
	btn_ok.custom_minimum_size = Vector2(96, 34)
	btn_ok.pressed.connect(func() -> void:
		# v1.8.20：分辨率只保存，下次启动由 main.gd 应用（不能即时改：整个 UI 要按新档重排）
		AppSettings.set_resolution(str(_res_keys[res_opt.selected]))
		GameState.toast.emit("分辨率已保存，下次启动生效")
		Engine.max_fps = _fps_opts[fps.selected]
		GameState.set_autosave_interval(int(auto_spin.value))
		for b in vol_pending.keys():
			var bi := AudioServer.get_bus_index(str(b))
			if bi >= 0:
				AudioServer.set_bus_volume_db(bi, linear_to_db(maxf(0.0001, float(vol_pending[b]) / 100.0)))
		close_dialog())
	footer.add_child(btn_ok)
	
	_switch_setting_page(pages, tabs, "video")
	add_child(d)


func _switch_setting_page(pages: Dictionary, tabs: VBoxContainer, tid: String) -> void:
	# 遍历所有页面，仅显示与 tid 匹配的页面
	for id in pages.keys():
		(pages[id] as Control).visible = str(id) == tid

	# 遍历所有切换按钮
	for child in tabs.get_children():
		var btn := child as Button
		# 跳过非按钮节点
		if btn == null:
			continue
		# 获取按钮绑定的设置页 id
		var btn_id := str(btn.get_meta("setting_id", ""))
		# 根据 id 是否匹配来设置按钮高亮
		UIKit.style_button(btn, btn_id == tid)


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


func _volume_row(label_text: String, bus: String, pending: Dictionary) -> HBoxContainer:
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.custom_minimum_size = Vector2(180, 0)
	
	var bus_idx := AudioServer.get_bus_index(bus)
	var cur := 100.0
	if bus_idx >= 0:
		cur = clampf(db_to_linear(AudioServer.get_bus_volume_db(bus_idx)) * 100.0, 0.0, 100.0)
	slider.value = cur
	pending[bus] = cur
	
	slider.value_changed.connect(func(v: float) -> void:
		pending[bus] = v)
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