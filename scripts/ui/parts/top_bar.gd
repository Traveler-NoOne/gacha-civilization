class_name TopBar
extends PanelContainer
## 顶部资源栏（2026-10-25 从 game_screen 拆出）✓
##
## 内容：周期 / 详情行 / 主菜单·作弊·快速保存 / 抽象资源·「统计」·具体资源
## 对外只发信号 + 一个 refresh()，不碰任何游戏规则 ✓

signal menu_pressed
signal save_pressed
signal cheat_pressed
signal stats_pressed
## 点某个资源 chip：把 key 和它的**屏幕矩形**一起发出去（收支小窗要贴着它弹）✓
signal chip_clicked(key: String, rect: Rect2)

var cycle_label: Label
var detail_label: Label
var cheat_button: Button
var stats_button: Button
var abstract_box: VBoxContainer
var concrete_box: VBoxContainer


func _init() -> void:
	UIKit.apply_panel(self, Palette.BG_SLOT, Palette.LINE_SOFT, 0)
	custom_minimum_size = Vector2(UI.px(0), UI.px(98))

	var top_v := VBoxContainer.new()
	top_v.add_theme_constant_override("separation", UI.fs(2))
	add_child(top_v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UI.fs(14))
	top_v.add_child(head)

	cycle_label = UIKit.text_label("周期 1", 16, Palette.GOLD)
	head.add_child(cycle_label)

	detail_label = UIKit.text_label("", 12, Palette.TEXT_DIM)
	detail_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(detail_label)

	var btn_menu := UIKit.small("主菜单")
	btn_menu.pressed.connect(func() -> void: menu_pressed.emit())
	head.add_child(btn_menu)

	# v1.2：作弊菜单按钮；只有反馈窗口勾选了「作弊功能」后才显示
	cheat_button = UIKit.small("作弊", 12)
	UIKit.style_button(cheat_button, false, true)
	cheat_button.tooltip_text = "作弊功能已开启（在主页面的「反馈」窗口里关闭）"
	cheat_button.pressed.connect(func() -> void: cheat_pressed.emit())
	cheat_button.visible = AppSettings.cheat_enabled()
	head.add_child(cheat_button)

	var btn_save := UIKit.small("快速保存")
	btn_save.pressed.connect(func() -> void: save_pressed.emit())
	head.add_child(btn_save)

	# v1.4：抽象资源（左，两行）｜「统计」（中）｜具体资源（右，两行）
	var bars := HBoxContainer.new()
	bars.add_theme_constant_override("separation", UI.fs(12))
	top_v.add_child(bars)

	abstract_box = VBoxContainer.new()
	abstract_box.add_theme_constant_override("separation", UI.fs(3))
	bars.add_child(abstract_box)

	var mid := HBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	bars.add_child(mid)
	stats_button = UIKit.small("统计", 12)
	stats_button.custom_minimum_size = Vector2(UI.px(68), UI.px(26))
	stats_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stats_button.tooltip_text = "统计：资源 / 单位 / 地块 / 领地"
	stats_button.pressed.connect(func() -> void: stats_pressed.emit())
	mid.add_child(stats_button)

	concrete_box = VBoxContainer.new()
	concrete_box.add_theme_constant_override("separation", UI.fs(3))
	bars.add_child(concrete_box)


## 重建资源 chip + 周期 / 详情行（状态变化、周期结算后调）✓
func refresh() -> void:
	for c in abstract_box.get_children():
		c.queue_free()
	for c in concrete_box.get_children():
		c.queue_free()

	# 抽象资源（左，两行）：生产力 / 科研点 / 行政点数 ｜ 秩序结晶 / 凝聚力 / 人力
	_fill_group(abstract_box, Consts.RES_ABSTRACT, 3, false)
	# 具体资源（右，两行）：食物 / 货币 / 木材 / 煤 / 铜 ｜ 铁 / 原油 / 水晶碎屑
	_fill_group(concrete_box, Consts.RES_CONCRETE, 5, true)

	cycle_label.text = "周期 %d" % int(GameState.state["cycle"])
	var st := Derived.stability(GameState.state)
	var hp := Derived.happiness(GameState.state)
	var iv := AppSettings.autosave_interval()
	detail_label.text = "幸福度 %.0f　文化率 %.2f　稳定度 %.0f%%　地块 %d(我) / %d(敌) / %d(无主)　卡组 %s　自动存档 每%d周期" % [
		hp, Derived.culture_rate(GameState.state), st * 100.0,
		TileManager.owned_tiles(GameState.state).size(), TileManager.enemy_tiles(GameState.state).size(),
		TileManager.free_tiles(GameState.state).size(), str(GameState.state.get("active_group", "")),
		iv,
	]
	detail_label.add_theme_color_override("font_color",
		Palette.BAD if st < Consts.STABILITY_MIN_BLOCK else Palette.TEXT_DIM)


## 把一组资源分到若干行（每行 per_row 个）填进 box
func _fill_group(box: VBoxContainer, items: Array, per_row: int, right_align: bool) -> void:
	var row: HBoxContainer = null
	for i in items.size():
		if i % per_row == 0:
			row = HBoxContainer.new()
			row.add_theme_constant_override("separation", UI.fs(10))
			if right_align:
				row.alignment = BoxContainer.ALIGNMENT_END
			box.add_child(row)
		_add_chip(row, str(items[i][0]), str(items[i][1]), items[i][2])


## 一个资源 chip；有存储上限的显示「当前 / 上限」；点击 → 发 chip_clicked ✓
func _add_chip(row: HBoxContainer, key: String, label_text: String, color: Color) -> void:
	var value: float
	var cap := -1.0
	if key == "pop":
		value = float(GameState.state["pop_total"])
	else:
		value = Res.amount(GameState.state, key)
		cap = Res.storage_cap(GameState.state, key)
	var chip := PanelContainer.new()
	UIKit.apply_panel(chip, Palette.BG_PANEL_2, Color(color.r, color.g, color.b, 0.45), 4)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", UI.fs(4))
	chip.add_child(h)
	# v1.4.2：资源图标（art/icons/<key>.png）；缺图时自动只显示文字
	var icon_key := "population" if key == "pop" else key
	var icon := UIKit.get_icon(icon_key, UIKit.Art.ICON)
	if icon != null:
		var tr := TextureRect.new()
		tr.texture = icon
		tr.custom_minimum_size = Vector2(UI.px(15), UI.px(15))
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		h.add_child(tr)
	h.add_child(UIKit.text_label(label_text, 11, color))
	var val_text := UIKit.fmt_num(value)
	var val_color := Palette.TEXT
	if cap >= 0.0:
		val_text = "%s / %s" % [UIKit.fmt_num(value), UIKit.fmt_num(cap)]
		if value >= cap - 0.001:
			val_color = Palette.WARN
	h.add_child(UIKit.text_label(val_text, 12, val_color))
	# v1.4.1：点击资源 → 在该位置弹出收支明细悬浮窗（由外部接 chip_clicked）
	chip.mouse_filter = Control.MOUSE_FILTER_STOP
	chip.tooltip_text = "点击查看每周期收支"
	chip.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton:
			var mb := e as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				chip.accept_event()
				chip_clicked.emit(key, chip.get_global_rect()))
	row.add_child(chip)
