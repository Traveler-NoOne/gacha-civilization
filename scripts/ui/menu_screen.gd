extends Control
## 主页面：开始游戏（继续 / 新游戏 / 读取游戏）、游戏设置、退出游戏、反馈。
## 对应设计文档「主页面」章节。

## v1.8.9：mode = "continue" / "load" / "new"。
## 2026-10-15：新增 opts（新游戏设置面板的选项）。
## ⚠️ 信号参数**不许写默认值** ✗（Godot 会报 "Signal parameters cannot have a default value" ✓）
##    —— 所以三处 emit **都必须显式传第二个参数** ✓（不传的那个会报参数不匹配 ✗）
signal start_game_requested(mode: String, opts: Dictionary)

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
	center.custom_minimum_size = Vector2(UI.px(360), UI.px(0))
	center.add_theme_constant_override("separation", UI.fs(10))
	add_child(center)

	var title := Label.new()
	title.text = "抽 卡 文 明"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", UI.fs(54))
	title.add_theme_color_override("font_color", Color(0.96, 0.86, 0.55))
	center.add_child(title)

	var sub := Label.new()
	sub.text = "Turn-based Roguelite Gacha Civilization · 可玩 Demo"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", UI.fs(13))
	sub.add_theme_color_override("font_color", Color(0.55, 0.58, 0.68))
	center.add_child(sub)

	center.add_child(_spacer(18))

	var btn_start := UIKit.primary("开始游戏")
	btn_start.pressed.connect(_toggle_expand)
	center.add_child(btn_start)

	_expand_box = VBoxContainer.new()
	_expand_box.add_theme_constant_override("separation", UI.fs(6))
	_expand_box.visible = false
	center.add_child(_expand_box)

	_btn_continue = UIKit.normal("继续游戏")
	_btn_continue.tooltip_text = "读取最后一次退出时的进度"
	_btn_continue.pressed.connect(func() -> void: start_game_requested.emit("continue", {}))
	_expand_box.add_child(_btn_continue)

	var btn_new := UIKit.normal("新游戏")
	btn_new.pressed.connect(_open_new_game_dialog)
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
	feedback.custom_minimum_size = Vector2(UI.px(92), UI.px(34))
	feedback.pressed.connect(_open_feedback)
	add_child(feedback)

	# v1.5：左下角免责声明
	var disclaimer := Label.new()
	disclaimer.text = Consts.DISCLAIMER_TEXT
	disclaimer.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	disclaimer.position = Vector2(16, -34)
	disclaimer.grow_vertical = Control.GROW_DIRECTION_BEGIN
	disclaimer.add_theme_font_size_override("font_size", UI.fs(11))
	disclaimer.add_theme_color_override("font_color", UIKit.TEXT_FAINT)
	add_child(disclaimer)

	_refresh_buttons()


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(UI.px(0), UI.px(h))
	return c


func _refresh_buttons() -> void:
	var can_continue := Save.has_continue()
	_btn_continue.disabled = not can_continue
	_btn_continue.modulate = Color(1, 1, 1, 1) if can_continue else Color(0.5, 0.5, 0.55, 0.75)
	if not can_continue:
		_btn_continue.tooltip_text = "没有上次退出的自动存档"
	var has_any := Save.any()
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
	list.add_theme_constant_override("separation", UI.fs(4))
	d.set_content(list)
	var found := false
	for i in Consts.SAVE_SLOTS:
		var summ := Save.summary(i)
		if summ.is_empty():
			continue
		found = true
		var slot := i
		var b := UIKit.normal("槽位 %d　周期 %d　地块 %d　角色 %d" % [
			i + 1, summ["cycle"], summ["tiles"], summ["chars"]])
		b.pressed.connect(func() -> void:
			if GameState.load_from_slot(slot):
				close_dialog()
				start_game_requested.emit("load", {}))
		list.add_child(b)
	if not found:
		var l := Label.new()
		l.text = "没有任何存档。"
		l.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
		list.add_child(l)
	add_child(d)


## 2026-10-15：**新游戏设置面板** —— 新建存档之前先定几件事。
## 现在两项：① 世界生成器（新生成器还没接进来 → 先灰着 ✓）② 世界种子（留空 = 随机 ✓）
## 注意：**「继续 / 读取」不弹这个面板** ✓（那是读既有的档，生成器早已定了 ✓）
func _open_new_game_dialog() -> void:
	_close_dialog()
	var d := UIKit.dialog("新游戏设置", 560.0)
	_dialog = d

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", UI.fs(10))
	d.set_content(v)

	v.add_child(UIKit.title("世界生成", 15))

	# 世界种子：填数字就能复现同一张地图（new_game 里 0 = 取时钟随机 ✓）
	var seed_edit := LineEdit.new()
	seed_edit.placeholder_text = "留空 = 随机"
	seed_edit.custom_minimum_size = Vector2(UI.px(160), UI.px(0))
	v.add_child(_row("世界种子", seed_edit))
	v.add_child(UIKit.dim("填一个数字就能复现同一张地图 ✓ 留空或 0 = 每次随机 ✓", 11))

	# 只出图、不进游戏 ✓（迭代生成器时最常用的入口 ✓）
	var shot := UIKit.small("只出图看看（不开始游戏）", 11)
	shot.tooltip_text = "生成一次世界并存成 PNG，存到项目目录的 preview/ 里（控制台会打印绝对路径）"
	shot.pressed.connect(func() -> void:
		var txt2 := seed_edit.text.strip_edges()
		var s2 := int(txt2) if txt2 != "" else 0
		var r := await WorldPreview.save_preview(self, s2)
		if not bool(r["ok"]):
			GameState.toast.emit("出图失败 ✗ 详情看控制台")
		else:
			print("预览图已保存：", str(r["path"]))
			GameState.toast.emit("已出图（种子 %d）→ %s" % [int(r["seed"]), str(r["path"])]))
	v.add_child(shot)

	v.add_child(_spacer(8))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UI.fs(10))
	row.alignment = BoxContainer.ALIGNMENT_END
	var cancel := UIKit.normal("取消", 13)
	cancel.pressed.connect(_close_dialog)
	row.add_child(cancel)
	var ok := UIKit.primary("开始游戏", 13)
	ok.pressed.connect(func() -> void:
		var txt := seed_edit.text.strip_edges()
		var s := int(txt) if txt != "" else 0
		_close_dialog()
		start_game_requested.emit("new", {"seed": s}))
	row.add_child(ok)
	v.add_child(row)

	# ⚠️ 必须挂进场景树 ✗ —— 只 new 不 add_child = 界面什么都不出现 ✓
	#（2026-10-15 踩到：抄 _open_settings 时只看了它的开头，漏了它结尾的 add_child(d) ✓）
	add_child(d)


func _open_settings() -> void:
	_close_dialog()
	var d := UIKit.dialog("游戏设置", 640.0)
	_dialog = d
	
	# 创建设置菜单一级容器竖式
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", UI.fs(10))
	d.set_content(outer)
	
	# 创建设置菜单二级容器横式
	var mid := HBoxContainer.new()
	mid.add_theme_constant_override("separation", UI.fs(14))
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(mid)
	
	# 创建设置菜单按钮列表
	var tabs := VBoxContainer.new()
	tabs.add_theme_constant_override("separation", UI.fs(6))
	tabs.custom_minimum_size = Vector2(UI.px(100), UI.px(0))
	mid.add_child(tabs)
	
	# 创建设置菜单的内容页父容器
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", UI.fs(8))
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
		pg.add_theme_constant_override("separation", UI.fs(8))
		pg.visible = false
		body.add_child(pg)
		
		# 初始化按钮
		var b := UIKit.normal(str(t["name"]), 13)
		b.set_meta("setting_id", str(t["id"]))
		b.custom_minimum_size = Vector2(UI.px(100), UI.px(34))
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
	res_hint.text = "改完保存，重启后才生效。"
	res_hint.add_theme_font_size_override("font_size", UI.fs(11))
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
	var _fps_opts := [0, 60, 30]
	var _fi := _fps_opts.find(Engine.max_fps)
	fps.selected = _fi if _fi >= 0 else 0
	# v1.8.20：帧率不涉及 UI 重建 → 改一下立即生效
	fps.item_selected.connect(func(idx: int) -> void:
		Engine.max_fps = _fps_opts[idx])
	page_video.add_child(_row("帧率限制", fps))
	# 初始化全屏设置
	var fs_box := UIKit.toggle_checkbox("全屏", AppSettings.fullscreen())
	fs_box.toggled.connect(func(on: bool) -> void:
		AppSettings.set_fullscreen(on)
		if on:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(UI.current_size())
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_RESIZE_DISABLED, true))
	page_video.add_child(fs_box)
	
	
	# v1.2：自动存档周期数
	var auto_spin := SpinBox.new()
	auto_spin.min_value = Consts.AUTOSAVE_INTERVAL_MIN
	auto_spin.max_value = Consts.AUTOSAVE_INTERVAL_MAX
	auto_spin.step = 1
	auto_spin.value = AppSettings.autosave_interval()
	auto_spin.tooltip_text = "默认每 1 个周期自动存档一次；可以改成每 N 个周期存档一次"
	# v1.8.20：不涉及 UI 重建 → 改一下立即生效
	auto_spin.value_changed.connect(func(v: float) -> void:
		AppSettings.set_autosave_interval(int(v))
		GameState.toast.emit("自动存档已设为每 %d 个周期一次" % AppSettings.autosave_interval())
		GameState.state_changed.emit())
	page_assist.add_child(_row("自动存档周期数", auto_spin))
	var auto_hint := Label.new()
	auto_hint.text = "默认情况下为每周期自动存档；这里可以设置自定义数量的周期进行一次自动存档（%d ~ %d）。" % [
		Consts.AUTOSAVE_INTERVAL_MIN, Consts.AUTOSAVE_INTERVAL_MAX]
	auto_hint.add_theme_font_size_override("font_size", UI.fs(11))
	auto_hint.add_theme_color_override("font_color", Color(0.62, 0.64, 0.72))
	auto_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page_assist.add_child(auto_hint)
	
	# 初始化音效设置
	page_audio.add_child(_volume_row("总音量", "Master"))
	page_audio.add_child(_volume_row("背景音乐", "Music"))
	page_audio.add_child(_volume_row("战斗音效", "SFX"))

	# 初始化键位设置
	var hint := Label.new()
	hint.text = "世界地图：鼠标左键拖动平移、滚轮缩放、点击地块查看详情。\n快捷键：「1/2/3」切换功能页，空格 = 结束周期，Esc = 关闭弹窗。"
	hint.add_theme_font_size_override("font_size", UI.fs(12))
	hint.add_theme_color_override("font_color", Color(0.72, 0.74, 0.8))
	page_keys.add_child(hint)
	
	# 弹窗确定区
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation", UI.fs(8))
	outer.add_child(footer)
	
	var btn_cancel := UIKit.normal("取消", 14)
	btn_cancel.custom_minimum_size = Vector2(UI.px(96), UI.px(34))
	btn_cancel.pressed.connect(func() -> void:
		close_dialog())
	footer.add_child(btn_cancel)
	
	var btn_ok := UIKit.primary("确认", 14)
	btn_ok.custom_minimum_size = Vector2(UI.px(96), UI.px(34))
	btn_ok.pressed.connect(func() -> void:
		# v1.8.20：其余设置（帧率 / 音量 / 自动存档）都是"改一下立即生效"，
		# 这里只剩分辨率要做决定 —— 它涉及 UI 重建，不能即时改：保存 + 问要不要现在重启。
		AppSettings.set_resolution(str(_res_keys[res_opt.selected]))


		close_dialog()
		_ask_restart())
	footer.add_child(btn_ok)
	
	_switch_setting_page(pages, tabs, "video")
	add_child(d)


## v1.8.20：分辨率涉及 UI 重建，不能即时改 —— 保存好后问用户要不要现在重启。
## 重启 → 立刻用新分辨率；不重启 → 本次仍用当前分辨率，下次启动自动生效。
func _ask_restart() -> void:
	var d := UIKit.confirm("需要重启", "分辨率改动要重启游戏才生效。\n现在就重启吗？\n（点「取消」＝这次仍用当前分辨率，下次启动自动生效）", _restart_game)
	add_child(d)


## 重启游戏：导出版直接拉起新进程；编辑器里只能手动重开（免得又把编辑器拉一个起来）
func _restart_game() -> void:
	if OS.has_feature("editor"):
		GameState.toast.emit("在编辑器里请手动重新运行")
		return
	OS.create_process(OS.get_executable_path(), PackedStringArray())
	get_tree().quit()


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
	h.add_theme_constant_override("separation", UI.fs(10))
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(UI.px(90), UI.px(0))
	h.add_child(l)
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(node)
	return h


func _volume_row(label_text: String, bus: String) -> HBoxContainer:
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.custom_minimum_size = Vector2(UI.px(180), UI.px(0))

	# v1.8.12：显示当前真实音量（不是写死的 80）
	var bus_idx := AudioServer.get_bus_index(bus)
	var cur := 100.0
	if bus_idx >= 0:
		cur = clampf(db_to_linear(AudioServer.get_bus_volume_db(bus_idx)) * 100.0, 0.0, 100.0)
	slider.value = cur
	
	slider.value_changed.connect(func(v: float) -> void:
		var i := AudioServer.get_bus_index(bus)
		if i >= 0:
			AudioServer.set_bus_volume_db(i, linear_to_db(maxf(0.0001, v / 100.0))))
	return _row(label_text, slider)


func _open_feedback() -> void:
	_close_dialog()
	var d := UIKit.dialog("反馈")
	_dialog = d
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", UI.fs(6))

	# v1.2：显示当前 demo 版本
	var ver := Label.new()
	ver.text = "当前版本：%s" % Consts.DEMO_VERSION_FULL
	ver.add_theme_font_size_override("font_size", UI.fs(13))
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
		l.add_theme_font_size_override("font_size", UI.fs(13))
		v.add_child(l)

	# v1.2：作弊功能勾选框
	v.add_child(UIKit.spacer(6.0))
	var rule := ColorRect.new()
	rule.color = UIKit.LINE_SOFT
	rule.custom_minimum_size = Vector2(UI.px(0), UI.px(1))
	v.add_child(rule)
	v.add_child(UIKit.spacer(4.0))

	var cheat_box := UIKit.toggle_checkbox("作弊功能", AppSettings.cheat_enabled())
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
					Cheat.set_enabled(true)
					GameState.toast.emit("作弊功能已开启")
					cheat_box.set_pressed_no_signal(true))
			add_child(confirm)
		else:
			Cheat.set_enabled(false)
			GameState.toast.emit("作弊功能已关闭"))

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
