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
	title.add_theme_color_override("font_color", Palette.GOLD)
	center.add_child(title)

	var sub := Label.new()
	sub.text = "Turn-based Roguelite Gacha Civilization · 可玩 Demo"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", UI.fs(13))
	sub.add_theme_color_override("font_color", Palette.TEXT_DIM)
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
	disclaimer.add_theme_color_override("font_color", Palette.TEXT_FAINT)
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
		l.add_theme_color_override("font_color", Palette.TEXT_DIM)
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
	# 设置内容在独立脚本里（scripts/ui/settings_menu.gd）；传 self 只是为了挂"需要重启"确认框 ✓
	d.set_content(SettingsMenu.new(self))
	add_child(d)


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
	ver.add_theme_color_override("font_color", Palette.GOLD)
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
	rule.color = Palette.LINE_SOFT
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
	if event.is_action_pressed("close_ui"):
		_close_dialog()
