extends Control
## 游戏主页外壳：上方资源栏 + 中间功能场景 + 下方一级按钮 + 结束周期按钮。
## 对应设计文档「游戏主页」章节。
##
## 一级按钮：管理 / 至宝 / 世界泡 / 日志 / 世界
## v1.2：删除了「休眠」页（功能与其他页面重复），退出改为顶部栏按钮。

signal exit_to_menu

const VIEWS := [
	{"id": "manage", "name": "管理", "script": "res://scripts/ui/views/view_manage_page.gd"},
	{"id": "treasure", "name": "至宝", "script": "res://scripts/ui/views/treasure_view.gd"},
	{"id": "gacha", "name": "世界泡", "script": "res://scripts/ui/views/gacha_view.gd"},
	{"id": "log", "name": "日志", "script": "res://scripts/ui/views/log_view.gd"},
	{"id": "world", "name": "世界", "script": "res://scripts/ui/views/view_world_page.gd"},
]
const DEFAULT_VIEW := "world"

var current_view := "DEFAULT_VIEW"
var views: Dictionary = {}
var resource_bar: HBoxContainer
var abstract_box: VBoxContainer
var concrete_box: VBoxContainer
## 资源收支悬浮窗（v1.4.1）
var _res_popup: Control = null
var content_host: MarginContainer
var nav_bar: HBoxContainer
## v1.7.1:视窗ID <-> 按钮 配对，刷新高亮用
var nav_buttons: Dictionary = {} 
var cycle_label: Label
var detail_label: Label
var cheat_button: Button

var _dialog: DialogLayer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	GameState.state_changed.connect(_refresh)
	GameState.toast.connect(_on_toast)
	# 作弊开关是全局设置，改了要立刻反映到顶部按钮上
	AppSettings.changed.connect(_refresh)
	_switch_view("DEFAULT_VIEW")


# ---------------------------------------------------------------------------
# 构建
# ---------------------------------------------------------------------------
func _build() -> void:
	var bg := ColorRect.new()
	bg.color = UIKit.BG_DARK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	# --- 顶部资源栏 ---
	var top := PanelContainer.new()
	UIKit.apply_panel(top, Color(0.08, 0.08, 0.12), UIKit.LINE_SOFT, 0)
	top.custom_minimum_size = Vector2(0, 98)
	root.add_child(top)

	var top_v := VBoxContainer.new()
	top_v.add_theme_constant_override("separation", 2)
	top.add_child(top_v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	top_v.add_child(head)

	cycle_label = UIKit.text_label("周期 1", 16, UIKit.GOLD)
	head.add_child(cycle_label)

	detail_label = UIKit.text_label("", 12, UIKit.TEXT_DIM)
	detail_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(detail_label)

	var btn_menu := UIKit.small("主菜单")
	btn_menu.pressed.connect(_confirm_exit)
	head.add_child(btn_menu)

	# v1.2：作弊菜单按钮，紧挨着主菜单按钮；只有在反馈窗口勾选了「作弊功能」后才显示
	cheat_button = UIKit.small("作弊", 12)
	UIKit.style_button(cheat_button, false, true)
	cheat_button.tooltip_text = "作弊功能已开启（在主页面的「反馈」窗口里关闭）"
	cheat_button.pressed.connect(_open_cheat_menu)
	cheat_button.visible = GameState.cheat_enabled()
	head.add_child(cheat_button)

	var btn_save := UIKit.small("快速保存")
	btn_save.pressed.connect(func() -> void:
		var slot := int(GameState.state.get("current_slot", -1))
		if slot < 0:
			slot = 1
		GameState.save_to_slot(slot))
	head.add_child(btn_save)

	resource_bar = HBoxContainer.new()
	resource_bar.add_theme_constant_override("separation", 12)
	top_v.add_child(resource_bar)

	# v1.4：抽象资源（左，两行）｜具体资源（右，两行）
	abstract_box = VBoxContainer.new()
	abstract_box.add_theme_constant_override("separation", 3)
	resource_bar.add_child(abstract_box)

	var res_spacer := Control.new()
	res_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resource_bar.add_child(res_spacer)

	concrete_box = VBoxContainer.new()
	concrete_box.add_theme_constant_override("separation", 3)
	resource_bar.add_child(concrete_box)

	# --- 中间内容区 ---
	content_host = MarginContainer.new()
	content_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_host.add_theme_constant_override("margin_left", 10)
	content_host.add_theme_constant_override("margin_right", 10)
	content_host.add_theme_constant_override("margin_top", 8)
	content_host.add_theme_constant_override("margin_bottom", 4)
	root.add_child(content_host)
	content_host.set_script(preload("res://scripts/ui/view_host.gd"))

	# --- 底部导航 ---
	var bottom := PanelContainer.new()
	UIKit.apply_panel(bottom, Color(0.08, 0.08, 0.12), UIKit.LINE_SOFT, 0)
	bottom.custom_minimum_size = Vector2(0, 56)
	root.add_child(bottom)

	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 0)
	bottom.add_child(bh)

	# 左右两区都 EXPAND_FILL -> 宽度相等 -> 中间那格必然在正中
	
	# 左区：包含结束周期;end_btn
	var left_wrap := HBoxContainer.new()
	left_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bh.add_child(left_wrap)
	
	# 结束周期按钮
	var end_btn := UIKit.primary("结束周期", 15)
	end_btn.custom_minimum_size = Vector2(100, 40)
	end_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	end_btn.pressed.connect(_end_cycle)
	left_wrap.add_child(end_btn)
	
	# 中区： 包含世界按钮;world_btn
	var mid_wrap := HBoxContainer.new()
	mid_wrap.custom_minimum_size = Vector2(64, 44)
	bh.add_child(mid_wrap)
	
	# 世界按钮
	var world_btn := UIKit.image_button("world-ball-s", "世界", 64, 64)
	world_btn.set_anchors_preset(Control.PRESET_CENTER)
	world_btn.pressed.connect(func() -> void: _switch_view("world"))
	mid_wrap.add_child(world_btn)
	nav_buttons["world"] = world_btn
	
	# 右区：包含管理，至宝，世界泡，日志
	var right_wrap := HBoxContainer.new()
	right_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_wrap.alignment = BoxContainer.ALIGNMENT_END
	bh.add_child(right_wrap)
	
	# 系统按钮排布
	nav_bar = HBoxContainer.new()
	nav_bar.add_theme_constant_override("separation", 6)
	nav_bar.alignment = BoxContainer.ALIGNMENT_END
	right_wrap.add_child(nav_bar)

	for v in VIEWS:
		var vid: String = v["id"]
		if vid == "world":
			continue
		var b := UIKit.normal(str(v["name"]), 15)
		b.custom_minimum_size = Vector2(96, 40)
		b.pressed.connect(func() -> void: _switch_view(vid))
		nav_bar.add_child(b)
		nav_buttons[vid] = b

	_refresh()


# ---------------------------------------------------------------------------
# 视图切换
# ---------------------------------------------------------------------------
func _switch_view(id: String) -> void:
	current_view = id
	if views.has(id):
		content_host.show_view(views[id])
		# v1.6 修复：切回**已缓存**的视图时必须重新刷新一次，否则显示的是上次刷新时的旧内容。
		# 典型症状：修建建筑后进管理页，人力管理与规划队列仍是空的，
		# 必须手动点一次「据点」弹窗才触发刷新、内容才出来。
		var cached: Variant = views[id]
		if cached != null and is_instance_valid(cached) and (cached as Node).has_method("refresh"):
			(cached as Node).call("refresh")
		_refresh_nav()
		return
	var def: Dictionary = {}
	for v in VIEWS:
		if v["id"] == id:
			def = v
			break
	if def.is_empty():
		return
	var scr: Control = load(str(def["script"])).new()
	views[id] = scr
	content_host.add_view(scr, id)
	content_host.show_view(scr)
	_refresh_nav()

##刷新系统按钮排布
func _refresh_nav() -> void:
	# v1.7.1：改成按「配对」刷新。以前是靠按钮在栏里的顺序去 VIEWS 对号入座，
	# 世界球搬到栏外（顺序变了）就会整体错位；存配对就不会。
	for vid in nav_buttons:
		var b: Button = nav_buttons[vid]
		if not is_instance_valid(b):
			continue
		var active: bool = vid == current_view
		if vid == "world":
			UIKit.apply_icon_active(b, active)
		else:
			UIKit.style_button(b, active)
			b.add_theme_color_override("font_color",UIKit.GOLD if active else  UIKit.TEXT)


func _end_cycle() -> void:
	var rep: Dictionary = GameState.end_cycle()
	# 广播给当前视图
	var v: Variant = views.get(current_view, null)
	if v != null and v.has_method("on_cycle_finished"):
		v.on_cycle_finished(rep)
	# v1.2：按设置的周期数触发自动存档时给出提示
	if bool(rep.get("autosaved", false)):
		GameState.toast.emit("已自动存档（每 %d 个周期一次）" % int(rep.get("autosave_interval", 1)))
	_refresh()


# ---------------------------------------------------------------------------
# 刷新
# ---------------------------------------------------------------------------
func _on_toast(text: String) -> void:
	pass


func _refresh() -> void:
	if not is_instance_valid(resource_bar):
		return
	# 资源栏重建前先收起收支悬浮窗（避免内容过期）
	_close_res_popup()
	# 作弊按钮的显隐跟随全局设置里的「作弊功能」勾选状态
	if is_instance_valid(cheat_button):
		cheat_button.visible = AppSettings.cheat_enabled()
	for c in abstract_box.get_children():
		c.queue_free()
	for c in concrete_box.get_children():
		c.queue_free()

	# 抽象资源（左，两行）：生产力 / 科研点 / 行政点数 ｜ 秩序结晶 / 凝聚力 / 人力
	_fill_group(abstract_box, [
		["production", "生产力", Color(0.90, 0.72, 0.35)],
		["research", "科研点", Color(0.55, 0.75, 0.98)],
		["admin", "行政点数", Color(0.80, 0.85, 0.55)],
		["order_crystal", "秩序结晶", Color(0.75, 0.60, 0.98)],
		["cohesion", "凝聚力", Color(0.98, 0.60, 0.75)],
		["pop", "人力", Color(0.85, 0.90, 1.0)],
	], 3, false)

	# 具体资源（右，两行）：食物 / 货币 / 木材 / 煤 / 铜 ｜ 铁 / 原油 / 水晶碎屑
	_fill_group(concrete_box, [
		["food", "食物", Color(0.55, 0.85, 0.45)],
		["currency", "货币", Color(0.95, 0.85, 0.45)],
		["wood", "木材", Color(0.7, 0.72, 0.78)],
		["coal", "煤", Color(0.7, 0.72, 0.78)],
		["copper", "铜矿", Color(0.7, 0.72, 0.78)],
		["iron", "铁矿", Color(0.7, 0.72, 0.78)],
		["oil", "原油", Color(0.7, 0.72, 0.78)],
		["crystal_shard", "水晶碎屑", Color(0.7, 0.72, 0.78)],
	], 5, true)

	cycle_label.text = "周期 %d" % int(GameState.state["cycle"])
	var st := GameState.stability()
	var hp := GameState.happiness()
	var iv := GameState.autosave_interval()
	detail_label.text = "幸福度 %.0f　文化率 %.2f　稳定度 %.0f%%　地块 %d(我) / %d(敌) / %d(无主)　卡组 %s　自动存档 每%d周期" % [
		hp, GameState.culture_rate(), st * 100.0,
		GameState.owned_tiles().size(), GameState.enemy_tiles().size(),
		GameState.free_tiles().size(), str(GameState.state.get("active_group", "")),
		iv,
	]
	detail_label.add_theme_color_override("font_color",
		UIKit.BAD if st < Consts.STABILITY_MIN_BLOCK else UIKit.TEXT_DIM)

	var v2: Variant = views.get(current_view, null)
	if v2 != null and v2.has_method("refresh"):
		v2.refresh()


## 把一组资源分到若干行（每行 per_row 个）填进 box
func _fill_group(box: VBoxContainer, items: Array, per_row: int, right_align: bool) -> void:
	var row: HBoxContainer = null
	for i in items.size():
		if i % per_row == 0:
			row = HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			if right_align:
				row.alignment = BoxContainer.ALIGNMENT_END
			box.add_child(row)
		_add_chip(row, str(items[i][0]), str(items[i][1]), items[i][2])


## 一个资源 chip；有存储上限的显示「当前 / 上限」
func _add_chip(row: HBoxContainer, key: String, label_text: String, color: Color) -> void:
	var value: float
	var cap := -1.0
	if key == "pop":
		value = float(GameState.state["pop_total"])
	else:
		value = GameState.res(key)
		cap = GameState.storage_cap(key)
	var chip := PanelContainer.new()
	UIKit.apply_panel(chip, Color(0.12, 0.12, 0.17), Color(color.r, color.g, color.b, 0.45), 4)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	chip.add_child(h)
	# v1.4.2：资源图标（art/icons/<key>.png）；缺图时自动只显示文字
	var icon_key := "population" if key == "pop" else key
	var icon := UIKit.get_icon(icon_key, UIKit.Art.ICON)
	if icon != null:
		var tr := TextureRect.new()
		tr.texture = icon
		tr.custom_minimum_size = Vector2(15, 15)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		h.add_child(tr)
	h.add_child(UIKit.text_label(label_text, 11, color))
	var val_text := UIKit.fmt_num(value)
	var val_color := UIKit.TEXT
	if cap >= 0.0:
		val_text = "%s / %s" % [UIKit.fmt_num(value), UIKit.fmt_num(cap)]
		if value >= cap - 0.001:
			val_color = UIKit.WARN
	h.add_child(UIKit.text_label(val_text, 12, val_color))
	# v1.4.1：点击资源 → 在该位置弹出收支明细悬浮窗
	chip.mouse_filter = Control.MOUSE_FILTER_STOP
	chip.tooltip_text = "点击查看每周期收支"
	chip.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton:
			var mb := e as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				chip.accept_event()
				_show_res_info(key, chip.get_global_rect()))
	row.add_child(chip)


## 资源收支悬浮窗（v1.4.1）：基于点击位置弹出
func _show_res_info(key: String, rect: Rect2) -> void:
	_close_res_popup()
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)
	_res_popup = layer

	# 点击任意处关闭
	var bg := Button.new()
	bg.focus_mode = Control.FOCUS_NONE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.pressed.connect(_close_res_popup)
	layer.add_child(bg)

	var panel := UIKit.panel(UIKit.BG_PANEL_2, UIKit.LINE, 6)
	panel.custom_minimum_size = Vector2(250, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(panel)
	var v := UIKit.vbox(2)
	panel.add_child(v)
	v.add_child(UIKit.title("%s · 每周期收支" % Consts.res_name(key), 14))
	if key == "pop":
		v.add_child(UIKit.dim("人力不是产出资源，受住房上限约束。"))
		var cap := GameState.housing_capacity()
		v.add_child(_break_row("住房上限", float(cap)))
		v.add_child(_break_row("已指派", float(GameState.assigned_pop())))
		v.add_child(_break_row("空闲", float(GameState.free_pop())))
	else:
		var bd: Dictionary = GameState.resource_breakdown(key)
		var inc: Array = bd["income"]
		var upk: Array = bd["upkeep"]
		var net := 0.0
		for e in inc:
			net += float(e["amount"])
			v.add_child(_break_row(str(e["label"]), float(e["amount"])))
		if not inc.is_empty() and not upk.is_empty():
			var sep := ColorRect.new()
			sep.color = UIKit.LINE_SOFT
			sep.custom_minimum_size = Vector2(0, 1)
			v.add_child(sep)
		for e in upk:
			net += float(e["amount"])
			v.add_child(_break_row(str(e["label"]), float(e["amount"])))
		if inc.is_empty() and upk.is_empty():
			v.add_child(UIKit.dim("该资源本期没有收支。"))
		v.add_child(UIKit.text_label("净收支 %+.1f / 周期" % net, 12,
			UIKit.OK if net >= 0.0 else UIKit.BAD))

	# 定位到点击位置下方，夹在视口内
	var vs := get_viewport_rect().size
	var pos := Vector2(rect.position.x, rect.end.y + 4.0)
	pos.x = clampf(pos.x, 8.0, maxf(8.0, vs.x - 258.0))
	pos.y = clampf(pos.y, 8.0, maxf(8.0, vs.y - 220.0))
	panel.position = pos


func _break_row(label_text: String, amount: float) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var l := UIKit.text_label(label_text, 11, UIKit.TEXT_DIM)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	h.add_child(UIKit.text_label("%+.1f" % amount, 12,
		UIKit.OK if amount >= 0.0 else UIKit.BAD))
	return h


func _close_res_popup() -> void:
	if is_instance_valid(_res_popup):
		_res_popup.queue_free()
	_res_popup = null


func _confirm_exit() -> void:
	# v1.2：休眠页删除后，这里承接「退出到主菜单 / 退出到桌面」
	open_dialog(_build_exit_dialog())


func _build_exit_dialog() -> DialogLayer:
	var d := UIKit.dialog("休眠 / 退出", 420.0)
	var v := UIKit.vbox(8)
	v.add_child(UIKit.text_label("请选择退出方式", 15, UIKit.GOLD))
	var cur := int(GameState.state.get("current_slot", -1))
	if cur < 0:
		v.add_child(UIKit.dim("当前进度还没有保存过，退出前建议先保存（会存到槽位 2）。"))
	else:
		v.add_child(UIKit.dim("当前存档槽位：%d（周期 %d）。" % [cur + 1, int(GameState.state["cycle"])]))

	var to_menu := UIKit.normal("退出到主菜单（先保存）", 14)
	to_menu.pressed.connect(func() -> void:
		close_dialog()
		var slot := int(GameState.state.get("current_slot", -1))
		if slot < 0:
			slot = 1
		GameState.save_to_slot(slot)
		exit_to_menu.emit())
	v.add_child(to_menu)

	var to_desktop := UIKit.normal("退出到桌面（先保存）", 14)
	UIKit.style_button(to_desktop, false, true)
	to_desktop.pressed.connect(func() -> void:
		close_dialog()
		var slot := int(GameState.state.get("current_slot", -1))
		if slot < 0:
			slot = 1
		GameState.save_to_slot(slot)
		GameState.save_to_slot(Consts.AUTOSAVE_SLOT)
		get_tree().quit())
	v.add_child(to_desktop)

	var cancel := UIKit.small("取消", 13)
	cancel.pressed.connect(func() -> void: close_dialog())
	v.add_child(cancel)
	d.set_content(v)
	return d


# ---------------------------------------------------------------------------
# v1.2 作弊菜单
# ---------------------------------------------------------------------------
const CHEAT_RESOURCES := [
	["food", "食物"],
	["production", "生产力"],
	["currency", "货币"],
	["research", "科研点"],
	["order_crystal", "秩序结晶"],
	["cohesion", "凝聚力"],
	["admin", "行政点数"],
	["wood", "木材"],
	["pop_total", "人力"],
]


func _open_cheat_menu() -> void:
	if not GameState.cheat_enabled():
		GameState.toast.emit("作弊功能未开启：请在主页面的「反馈」窗口里勾选")
		return
	var d := UIKit.dialog("作弊菜单", 560.0)
	var v := UIKit.vbox(8)
	v.add_child(UIKit.text_label("注意：作弊会直接修改存档数据，仅用于调试。", 12, UIKit.WARN))

	# ---- 添加资源 ----
	v.add_child(UIKit.title("添加资源", 15))
	v.add_child(UIKit.dim("填写每个资源想增加的数量（可填空或 0），然后点最下面的「一次性添加」。"))
	var grid := UIKit.grid(4, 10, 6)
	v.add_child(grid)
	var spins: Dictionary = {}
	for pair in CHEAT_RESOURCES:
		var key: String = pair[0]
		var nm: String = pair[1]
		grid.add_child(UIKit.text_label(nm, 12, UIKit.TEXT_DIM))
		var sb := SpinBox.new()
		sb.min_value = -999999
		sb.max_value = 999999
		sb.step = 1
		sb.value = 0
		sb.custom_minimum_size = Vector2(110, 0)
		grid.add_child(sb)
		spins[key] = sb

	var quick := UIKit.hbox(6)
	var b1 := UIKit.small("快捷：全部 +100", 11)
	b1.pressed.connect(func() -> void:
		for k in spins.keys():
			(spins[k] as SpinBox).value = 100)
	quick.add_child(b1)
	var b2 := UIKit.small("快捷：全部 +1000", 11)
	b2.pressed.connect(func() -> void:
		for k in spins.keys():
			(spins[k] as SpinBox).value = 1000)
	quick.add_child(b2)
	var b0 := UIKit.small("清零", 11)
	b0.pressed.connect(func() -> void:
		for k in spins.keys():
			(spins[k] as SpinBox).value = 0)
	quick.add_child(b0)
	v.add_child(quick)

	var apply := UIKit.primary("一次性添加", 15)
	apply.pressed.connect(func() -> void:
		var amounts := {}
		for k in spins.keys():
			var v2 := int((spins[k] as SpinBox).value)
			if v2 != 0:
				amounts[k] = v2
		GameState.cheat_add_resources(amounts)
		close_dialog())
	v.add_child(apply)

	# ---- 摧毁敌对单位 ----
	v.add_child(UIKit.spacer(6.0))
	v.add_child(UIKit.title("摧毁敌对单位", 15))
	v.add_child(UIKit.dim("可以选中大世界中的任何敌对单位直接摧毁。"))
	var enemies := GameState.enemy_tiles()
	v.add_child(UIKit.dim("当前大世界敌对单位：%d 个" % enemies.size()))
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 3)
	for t in enemies:
		var key := GameState.tile_key(t)
		var label := GameState.enemy_label(t)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		list.add_child(row)
		var l := UIKit.text_label("%s　[%s]　战力 %.0f" % [label, key, float(t.get("force", 0.0))],
			12, UIKit.BAD)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var rb := UIKit.tiny("摧毁", 11, true)
		rb.pressed.connect(func() -> void:
			var r := GameState.cheat_destroy_tile(key)
			if not r["ok"]:
				GameState.toast.emit(str(r["why"]))
			else:
				GameState.toast.emit("已摧毁 %s 的%s" % [key, str(r["label"])])
			close_dialog())
		row.add_child(rb)
	if enemies.is_empty():
		list.add_child(UIKit.dim("（当前没有敌对单位）"))
	# 敌人列表：(0,0) 最小尺寸 —— 由 ScrollContainer 自己裁剪，不参与弹窗高度撑开
	var lsc := UIKit.scroll(list)
	lsc.custom_minimum_size = Vector2(0, 0)
	lsc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(lsc)

	var all_btn := UIKit.normal("摧毁全部敌对单位", 13)
	UIKit.style_button(all_btn, false, true)
	all_btn.pressed.connect(func() -> void:
		GameState.cheat_destroy_all_enemies()
		close_dialog())
	v.add_child(all_btn)

	v.add_child(UIKit.dim("关闭作弊：回到主页面 → 反馈 → 取消勾选「作弊功能」。", 11))

	# 外层滚动容器：(0,0) 最小尺寸 + 撑满剩余高度。
	# 关键点：一定不能给它写死的最小高度（或累加出超过视口的高度），
	# 否则 VBoxContainer 的最小高度会把弹窗顶出屏幕，底部按钮就点不到了。
	var sc := UIKit.scroll(v)
	sc.custom_minimum_size = Vector2(0, 0)
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	d.set_content(sc)
	open_dialog(d)


func open_dialog(d: DialogLayer) -> void:
	close_dialog()
	_dialog = d
	add_child(d)


func close_dialog() -> void:
	if is_instance_valid(_dialog):
		_dialog.queue_free()
	_dialog = null


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not (event as InputEventKey).pressed:
		return
	var k := event as InputEventKey
	if k.echo:
		return
	match k.keycode:
		KEY_1: _switch_view("manage")
		KEY_2: _switch_view("treasure")
		KEY_3: _switch_view("gacha")
		KEY_4: _switch_view("log")
		KEY_5: _switch_view("world")
		KEY_SPACE: _end_cycle()
		KEY_ESCAPE:
			_close_res_popup()
			close_dialog()


func goto_view(id: String) -> void:
	_switch_view(id)
