class_name SettingsMenu
extends VBoxContainer
## 游戏设置弹窗的**内容**：画面 / 辅助 / 音效 / 键位 四个页签 ✓
##
## 2026-10-25 从 menu_screen 解耦出来 —— 那边只剩三行：
##     var d := UIKit.dialog("游戏设置", 640.0)
##     d.set_content(SettingsMenu.new(self))   # self 只用来挂"需要重启"确认框
##     add_child(d)
##
## 里面所有改动都是**立即生效**的（AppSettings / Engine / AudioServer），
## 只有分辨率例外：它涉及 UI 重建，所以"确认"时保存 + 问要不要现在重启 ✓

const TABS := [
	{"id": "video", "name": "画面设置"},
	{"id": "assist", "name": "辅助设置"},
	{"id": "audio", "name": "音效设置"},
	{"id": "keys", "name": "键位设置"},
]

## 挂"需要重启"确认框用的宿主（一般是打开设置的那个界面）
var _host: Node

## 分辨率档位（确认按钮要读用户最终选择）
var _res_keys: Array = []

## 页签容器 / 页面词典（切换页用）
var _tabs_box: VBoxContainer
var _pages: Dictionary = {}

## 改键捕获状态
var _rebind_action := ""
var _rebind_btn: Button = null


func _init(host: Node) -> void:
	_host = host
	add_theme_constant_override("separation", UI.fs(10))
	_build()


# ---------------------------------------------------------------------------
# 构建
# ---------------------------------------------------------------------------
func _build() -> void:
	var mid := HBoxContainer.new()
	mid.add_theme_constant_override("separation", UI.fs(14))
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(mid)

	_tabs_box = VBoxContainer.new()
	_tabs_box.add_theme_constant_override("separation", UI.fs(6))
	_tabs_box.custom_minimum_size = Vector2(UI.px(100), UI.px(0))
	mid.add_child(_tabs_box)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", UI.fs(8))
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_child(body)

	var page_video := VBoxContainer.new()
	var page_assist := VBoxContainer.new()
	var page_audio := VBoxContainer.new()
	var page_keys := VBoxContainer.new()
	_pages = {"video": page_video, "assist": page_assist, "audio": page_audio, "keys": page_keys}
	for t in TABS:
		var pg: VBoxContainer = _pages[str(t["id"])]
		pg.add_theme_constant_override("separation", UI.fs(8))
		pg.visible = false
		body.add_child(pg)
		var b := UIKit.normal(str(t["name"]), 13)
		b.set_meta("setting_id", str(t["id"]))
		b.custom_minimum_size = Vector2(UI.px(100), UI.px(34))
		b.pressed.connect(_switch_page.bind(str(t["id"])))
		_tabs_box.add_child(b)

	_build_video_page(page_video)
	_build_assist_page(page_assist)
	_build_audio_page(page_audio)
	_build_keys_page(page_keys)

	# 确认区
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation", UI.fs(8))
	add_child(footer)

	var btn_cancel := UIKit.normal("取消", 14)
	btn_cancel.custom_minimum_size = Vector2(UI.px(96), UI.px(34))
	btn_cancel.pressed.connect(_close_self)
	footer.add_child(btn_cancel)

	var btn_ok := UIKit.primary("确认", 14)
	btn_ok.custom_minimum_size = Vector2(UI.px(96), UI.px(34))
	btn_ok.pressed.connect(func() -> void:
		# 其余设置（帧率 / 音量 / 自动存档）都是"改一下立即生效"，
		# 这里只剩分辨率要做决定 —— 它涉及 UI 重建，不能即时改：保存 + 问要不要现在重启。
		AppSettings.set_resolution(str(_res_keys[_res_opt.selected]))
		_close_self()
		_ask_restart())
	footer.add_child(btn_ok)

	_switch_page("video")


var _res_opt: OptionButton


func _build_video_page(page: VBoxContainer) -> void:
	# 分辨率：选项来自 UI 尺寸词典（唯一来源），改完保存、下次启动生效
	_res_opt = OptionButton.new()
	_res_keys = UI.resolutions()
	for res_key in _res_keys:
		_res_opt.add_item(UI.label_of(str(res_key)))
	var ri := _res_keys.find(AppSettings.resolution())
	_res_opt.selected = ri if ri >= 0 else _res_keys.find(UI.BASE_KEY)
	page.add_child(_row("分辨率", _res_opt))
	page.add_child(_hint("改完保存，重启后才生效。"))

	var quality := OptionButton.new()
	quality.add_item("兼容（GL Compatibility）")
	quality.selected = 0
	quality.disabled = true
	page.add_child(_row("画质档位", quality))

	var fps := OptionButton.new()
	fps.add_item("不限")
	fps.add_item("60")
	fps.add_item("30")
	var fps_opts := [0, 60, 30]
	var fi := fps_opts.find(Engine.max_fps)
	fps.selected = fi if fi >= 0 else 0
	fps.item_selected.connect(func(idx: int) -> void:
		Engine.max_fps = fps_opts[idx])
	page.add_child(_row("帧率限制", fps))

	var fs_box := UIKit.toggle_checkbox("全屏", AppSettings.fullscreen())
	fs_box.toggled.connect(func(on: bool) -> void:
		AppSettings.set_fullscreen(on)
		if on:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(UI.current_size())
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_RESIZE_DISABLED, true))
	page.add_child(fs_box)


func _build_assist_page(page: VBoxContainer) -> void:
	var auto_spin := SpinBox.new()
	auto_spin.min_value = Consts.AUTOSAVE_INTERVAL_MIN
	auto_spin.max_value = Consts.AUTOSAVE_INTERVAL_MAX
	auto_spin.step = 1
	auto_spin.value = AppSettings.autosave_interval()
	auto_spin.tooltip_text = "默认每 1 个周期自动存档一次；可以改成每 N 个周期存档一次"
	auto_spin.value_changed.connect(func(v: float) -> void:
		AppSettings.set_autosave_interval(int(v))
		GameState.toast.emit("自动存档已设为每 %d 个周期一次" % AppSettings.autosave_interval())
		GameState.state_changed.emit())
	page.add_child(_row("自动存档周期数", auto_spin))
	var auto_hint := _hint("默认情况下为每周期自动存档；这里可以设置自定义数量的周期进行一次自动存档（%d ~ %d）。" % [
		Consts.AUTOSAVE_INTERVAL_MIN, Consts.AUTOSAVE_INTERVAL_MAX])
	auto_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(auto_hint)


func _build_audio_page(page: VBoxContainer) -> void:
	page.add_child(_volume_row("总音量", "Master"))
	page.add_child(_volume_row("背景音乐", "Music"))
	page.add_child(_volume_row("战斗音效", "SFX"))


## 键位页：每行「名称 + 当前键（点它改键）」+ 恢复默认 ✓
func _build_keys_page(page: VBoxContainer) -> void:
	page.add_child(_hint("点「改键」后按下新按键即可（按 Esc 取消）。改动立即生效，并会记住。"))
	for a in KeyBinds.ACTIONS:
		var id := str(a["id"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", UI.fs(8))
		page.add_child(row)
		var nm := UIKit.text_label(str(a["name"]), 13, Palette.TEXT)
		nm.custom_minimum_size = Vector2(UI.px(170), UI.px(0))
		row.add_child(nm)
		var key_btn := UIKit.small(KeyBinds.key_text(id), 12)
		key_btn.custom_minimum_size = Vector2(UI.px(120), UI.px(30))
		key_btn.tooltip_text = "点击后按下新按键（Esc 取消）"
		key_btn.pressed.connect(_start_rebind.bind(id, key_btn))
		row.add_child(key_btn)
	var reset_btn := UIKit.small("恢复默认键位", 11)
	reset_btn.pressed.connect(_reset_keys)
	page.add_child(reset_btn)


# ---------------------------------------------------------------------------
# 页签切换
# ---------------------------------------------------------------------------
func _switch_page(tid: String) -> void:
	for id in _pages.keys():
		(_pages[id] as Control).visible = str(id) == tid
	for child in _tabs_box.get_children():
		var btn := child as Button
		if btn == null:
			continue
		UIKit.style_button(btn, str(btn.get_meta("setting_id", "")) == tid)


# ---------------------------------------------------------------------------
# 改键
# ---------------------------------------------------------------------------
func _start_rebind(action: String, btn: Button) -> void:
	_rebind_action = action
	_rebind_btn = btn
	btn.text = "按下新键…"


## `_input` 比 `_unhandled_input` 早，所以捕获期间按 Esc 是"取消改键"而不是关弹窗 ✓
func _input(event: InputEvent) -> void:
	if _rebind_action == "":
		return
	if not (event is InputEventKey) or not (event as InputEventKey).pressed:
		return
	get_viewport().set_input_as_handled()
	var k := event as InputEventKey
	if k.keycode == KEY_ESCAPE:
		_finish_rebind()
		return
	KeyBinds.rebind(_rebind_action, k)
	_rebind_btn.text = KeyBinds.key_text(_rebind_action)
	_finish_rebind()


func _finish_rebind() -> void:
	_rebind_action = ""
	_rebind_btn = null


## 恢复默认后**就地重建**键位页（不关窗重开，省得闪一下）✓
func _reset_keys() -> void:
	KeyBinds.reset_defaults()
	var page: VBoxContainer = _pages["keys"]
	for c in page.get_children():
		page.remove_child(c)
		c.queue_free()
	_build_keys_page(page)
	_switch_page("keys")


# ---------------------------------------------------------------------------
# 收尾
# ---------------------------------------------------------------------------
## 关掉自己所在的弹窗（往上找 DialogLayer，不用把宿主接口带进来）✓
func _close_self() -> void:
	var n: Node = self
	while n != null and not (n is DialogLayer):
		n = n.get_parent()
	if n != null:
		(n as DialogLayer).close()


## v1.8.20：分辨率涉及 UI 重建，不能即时改 —— 保存好后问用户要不要现在重启。
func _ask_restart() -> void:
	var d := UIKit.confirm("需要重启", "分辨率改动要重启游戏才生效。\n现在就重启吗？\n（点「取消」＝这次仍用当前分辨率，下次启动自动生效）", _restart_game)
	if is_instance_valid(_host):
		_host.add_child(d)


## 重启游戏：导出版直接拉起新进程；编辑器里只能手动重开（免得又把编辑器拉一个起来）
func _restart_game() -> void:
	if OS.has_feature("editor"):
		GameState.toast.emit("在编辑器里请手动重新运行")
		return
	OS.create_process(OS.get_executable_path(), PackedStringArray())
	get_tree().quit()


# ---------------------------------------------------------------------------
# 小零件
# ---------------------------------------------------------------------------
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


func _hint(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", UI.fs(11))
	l.add_theme_color_override("font_color", Palette.TEXT_DIM)
	return l


func _volume_row(label_text: String, bus: String) -> HBoxContainer:
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.custom_minimum_size = Vector2(UI.px(180), UI.px(0))

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
