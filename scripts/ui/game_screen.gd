extends Control
## 游戏主页外壳：上方资源栏 + 中间功能场景 + 下方一级按钮 + 结束周期按钮。
## 对应设计文档「游戏主页」章节。
##
## 一级按钮：管理 / 至宝 / 世界泡 / 日志 / 世界
## v1.2：删除了「休眠」页（功能与其他页面重复），退出改为顶部栏按钮。

signal exit_to_menu

## v1.8.8：现在只有 world 是"页面"（常驻底层），其余都是二级浮窗。
## 浮窗尺寸**待试玩后定**（先用 1120×620）。
const VIEWS := [
	{"id": "treasure", "name": "至宝", "script": "res://scripts/ui/views/treasure_view.gd", "w": 1120.0, "h": 620.0},
	{"id": "gacha", "name": "世界泡", "script": "res://scripts/ui/views/gacha_view.gd", "w": 1120.0, "h": 620.0},
	{"id": "world", "name": "世界", "script": "res://scripts/ui/views/view_world_page.gd", "w": 0.0, "h": 0.0},
]
const DEFAULT_VIEW := "world"



var current_view := DEFAULT_VIEW
var views: Dictionary = {}
var resource_bar: HBoxContainer
var abstract_box: VBoxContainer
var concrete_box: VBoxContainer
## 资源收支悬浮窗（v1.4.1）
var _res_popup: Control = null
var content_host: MarginContainer
## v1.7.1:视窗ID <-> 按钮 配对，刷新高亮用
var nav_buttons: Dictionary = {} 
var cycle_label: Label
var detail_label: Label
var cheat_button: Button

## v1.8.6：角落浮动按钮与浮窗（左上科技树 / 右上日志）
const CORNER_MARGIN := 16.0
const CORNER_TOP := 112.0
var corner_tech_btn: Button
var corner_log_btn: Button
var end_btn: Button
## v1.8.11：统计面板（资源栏中间的「统计」按钮打开；默认看资源）
var stats_btn: Button
var stats_panel: StatsPanel = null
## v1.8.8：二级浮窗注册表 id -> PagePanel（内部页面同时挂到 views[id]，保持旧调用点可用）
var panels: Dictionary = {}
## 压暗层（浮窗打开时出现；mouse_filter = IGNORE，所以**地图仍然能拖能点**）
var dim: ColorRect
var tech_panel: TechPanel = null
var log_panel: LogPanel = null

var _dialog: DialogLayer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	GameState.state_changed.connect(_refresh)
	GameState.toast.connect(_on_toast)
	# 作弊开关是全局设置，改了要立刻反映到顶部按钮上
	AppSettings.changed.connect(_refresh)
	# v1.8.8：大世界是底层（root），先把它立起来；浮窗只是叠在它上面的窗。
	_setup_world()
	_refresh_nav()


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
	root.add_theme_constant_override("separation", UI.fs(0))
	add_child(root)

	# --- 顶部资源栏 ---
	var top := PanelContainer.new()
	UIKit.apply_panel(top, Color(0.08, 0.08, 0.12), UIKit.LINE_SOFT, 0)
	top.custom_minimum_size = Vector2(UI.px(0), UI.px(98))
	root.add_child(top)

	var top_v := VBoxContainer.new()
	top_v.add_theme_constant_override("separation", UI.fs(2))
	top.add_child(top_v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UI.fs(14))
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
	cheat_button.visible = AppSettings.cheat_enabled()
	head.add_child(cheat_button)

	var btn_save := UIKit.small("快速保存")
	btn_save.pressed.connect(func() -> void:
		var slot := int(GameState.state.get("current_slot", -1))
		if slot < 0:
			slot = 1
		GameState.save_to_slot(slot))
	head.add_child(btn_save)

	resource_bar = HBoxContainer.new()
	resource_bar.add_theme_constant_override("separation", UI.fs(12))
	top_v.add_child(resource_bar)

	# v1.4：抽象资源（左，两行）｜具体资源（右，两行）
	abstract_box = VBoxContainer.new()
	abstract_box.add_theme_constant_override("separation", UI.fs(3))
	resource_bar.add_child(abstract_box)

	# v1.8.11：资源栏**中间**是「统计」入口 —— 点开在它下面展开统计面板。
	# 中间那块本来就是空的（左抽象 / 右具体），正好用来放"能统计但没家"的东西。
	var res_mid := HBoxContainer.new()
	res_mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	res_mid.alignment = BoxContainer.ALIGNMENT_CENTER
	resource_bar.add_child(res_mid)
	stats_btn = UIKit.small("统计", 12)
	stats_btn.custom_minimum_size = Vector2(UI.px(68), UI.px(26))
	stats_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stats_btn.tooltip_text = "统计：资源 / 单位 / 地块 / 领地"
	stats_btn.pressed.connect(_toggle_stats_panel)
	res_mid.add_child(stats_btn)

	concrete_box = VBoxContainer.new()
	concrete_box.add_theme_constant_override("separation", UI.fs(3))
	resource_bar.add_child(concrete_box)

	# --- 中间内容区 ---
	content_host = MarginContainer.new()
	content_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_host.add_theme_constant_override("margin_left", UI.px(10))
	content_host.add_theme_constant_override("margin_right", UI.px(10))
	content_host.add_theme_constant_override("margin_top", UI.px(8))
	content_host.add_theme_constant_override("margin_bottom", UI.px(4))
	root.add_child(content_host)
	content_host.set_script(preload("res://scripts/ui/view_host.gd"))

	# v1.8.7：底部栏整个取消 —— 按钮改为直接悬浮在大世界上（见 _build_floating_ui）。

	# v1.8.8：压暗层。加在按钮**之前** → 它在按钮和浮窗下面；IGNORE 让它不吃输入。
	dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.visible = false
	add_child(dim)

	# v1.8.7：按钮全部改为悬浮（左上科技树 / 右上日志 / 左下至宝·世界泡 / 右下结束周期）
	_build_floating_ui()

	_refresh()


# ---------------------------------------------------------------------------
# 视图切换
# ---------------------------------------------------------------------------
func _view_def(id: String) -> Dictionary:
	for v in VIEWS:
		if str(v["id"]) == id:
			return v
	return {}


## v1.8.8：世界常驻底层；切到别的 id = 打开它对应的二级浮窗；切回 world = 关掉所有浮窗。
func _switch_view(id: String) -> void:
	if id == "" or id == DEFAULT_VIEW:
		_close_all_panels()
		current_view = DEFAULT_VIEW
		_refresh_nav()
		return
	_open_panel(id)


## 打开（或唤起）一个二级浮窗。同一时刻只留一个页级浮窗，避免叠罗汉。
func _open_panel(id: String) -> void:
	var def := _view_def(id)
	if def.is_empty():
		return
	for other in panels.keys():
		if str(other) != id and (panels[other] as Control).visible:
			(panels[other] as PagePanel).close_panel()
	if not panels.has(id):
		var p := PagePanel.new(str(def["name"]), str(def["script"]),
			float(def.get("w", 1120.0)), float(def.get("h", 620.0)))
		p.set_anchors_preset(Control.PRESET_TOP_LEFT)
		p.visible = false
		p.closed.connect(_on_panel_closed)
		add_child(p)
		panels[id] = p
		# 兼容：旧代码/测试用 views[id] 拿"页面"，现在指向浮窗内部那一页
		views[id] = p.page
	var panel: PagePanel = panels[id]
	# ⚠️ v1.6 的保证不能丢：**每次打开都刷新**，否则会重现"修建后进来看空列表"那类旧缓存 bug。
	if panel.page != null and is_instance_valid(panel.page) and panel.page.has_method("refresh"):
		panel.page.call("refresh")
	panel.visible = true
	current_view = id
	_place_floating_ui()
	_update_dim()
	_refresh_nav()


func _close_all_panels() -> void:
	for id in panels.keys():
		if (panels[id] as Control).visible:
			(panels[id] as Control).visible = false
	_update_dim()


func _on_panel_closed() -> void:
	_update_dim()
	if not _any_page_panel_open():
		current_view = DEFAULT_VIEW
	_refresh_nav()


func _any_page_panel_open() -> bool:
	for id in panels.keys():
		if (panels[id] as Control).visible:
			return true
	return false


## 有页级浮窗打开时压暗底下（但不拦输入 —— 地图仍可拖动，保持"我在世界之上操作"的手感）
func _update_dim() -> void:
	if is_instance_valid(dim):
		dim.visible = _any_page_panel_open()


## v1.8.8：把大世界立成常驻底层
func _setup_world() -> void:
	var def := _view_def(DEFAULT_VIEW)
	if def.is_empty():
		return
	var scr: Control = load(str(def["script"])).new()
	views[DEFAULT_VIEW] = scr
	content_host.add_view(scr, DEFAULT_VIEW)
	content_host.show_view(scr)
	current_view = DEFAULT_VIEW

##刷新系统按钮排布
# ---------------------------------------------------------------------------
# v1.8.7：悬浮按钮与浮窗（底栏取消，按钮直接悬在大世界上）
# ---------------------------------------------------------------------------
func _build_floating_ui() -> void:
	# 左上角：科技树
	corner_tech_btn = UIKit.normal("科技树", 13)
	corner_tech_btn.custom_minimum_size = Vector2(UI.px(84), UI.px(34))
	corner_tech_btn.tooltip_text = "科技树"
	corner_tech_btn.pressed.connect(_toggle_tech_panel)
	add_child(corner_tech_btn)

	# 右上角：日志（书本图标）
	corner_log_btn = UIKit.image_button("book-ball", "日志", 40, 40)
	corner_log_btn.pressed.connect(_toggle_log_panel)
	add_child(corner_log_btn)

	# 左下角：至宝 / 世界泡（原来在底栏右侧）
	# 它们现在是"盖在世界上的页面"，所以再点一次收回世界 —— 否则关不掉（世界按钮已随底栏删除）。
	for v in VIEWS:
		var vid := str(v["id"])
		if vid == "world":
			continue
		var b := UIKit.normal(str(v["name"]), 14)
		b.custom_minimum_size = Vector2(UI.px(96), UI.px(40))
		b.pressed.connect(func() -> void: _toggle_page(vid))
		add_child(b)
		nav_buttons[vid] = b

	# 右下角：结束周期（原来在底栏左侧）
	end_btn = UIKit.primary("结束周期", 15)
	end_btn.custom_minimum_size = Vector2(UI.px(100), UI.px(40))
	end_btn.pressed.connect(_end_cycle)
	add_child(end_btn)

	resized.connect(_place_floating_ui)
	# 状态变了就顺带刷新开着的科技浮窗（科研点与解锁状态会变）
	GameState.state_changed.connect(func() -> void:
		if tech_panel != null and is_instance_valid(tech_panel) and tech_panel.visible:
			tech_panel.refresh())
	_place_floating_ui()


## ⚠️ 悬浮层一律用 **TOP_LEFT 锚点 + 按屏幕尺寸算绝对位置**，并在 resized 时重摆。
##（"锚右上 + 负偏移"那套很容易摆错：锚点若在 add_child 之前设，还没有父节点可参照。）
func _place_floating_ui() -> void:
	var bh := UI.px(40)
	var margin := UI.px(CORNER_MARGIN)
	if is_instance_valid(corner_tech_btn):
		corner_tech_btn.position = Vector2(CORNER_MARGIN, CORNER_TOP)
	if is_instance_valid(corner_log_btn):
		corner_log_btn.position = Vector2(size.x - CORNER_MARGIN - bh, CORNER_TOP - 6.0)
	# 左下角一排（至宝、世界泡），按 VIEWS 顺序相邻排开
	var x := margin
	var y := size.y - CORNER_MARGIN - bh
	for vid in nav_buttons:
		var b: Button = nav_buttons[vid]
		if not is_instance_valid(b):
			continue
		b.position = Vector2(x, y)
		x += b.custom_minimum_size.x + 8.0
	if is_instance_valid(end_btn):
		end_btn.position = Vector2(size.x - margin - UI.px(100), y)
	if stats_panel != null and is_instance_valid(stats_panel):
		# 展开在「统计」按钮的正下方（和"点资源弹收支窗"一个位置逻辑）
		var gp := Vector2.ZERO
		if is_instance_valid(stats_btn):
			gp = stats_btn.global_position - global_position
		var w := 360.0
		var hh := minf(430.0, size.y - gp.y - 80.0)
		stats_panel.size = Vector2(w, maxf(200.0, hh))
		stats_panel.position = Vector2(
			clampf(gp.x - 40.0, 8.0, maxf(8.0, size.x - w - 8.0)),
			gp.y + 30.0)
	if tech_panel != null and is_instance_valid(tech_panel):
		var sz := Vector2(560, 480)
		tech_panel.size = sz
		tech_panel.position = Vector2(maxf(0.0, (size.x - sz.x) * 0.5), maxf(0.0, (size.y - sz.y) * 0.5))
	if log_panel != null and is_instance_valid(log_panel):
		# 四周留边 —— 这就是"露出底下的世界"的那点边距
		log_panel.position = Vector2(72.0, 64.0)
		log_panel.size = Vector2(maxf(200.0, size.x - 144.0), maxf(160.0, size.y - 144.0))
	# v1.8.8：页级浮窗居中；夹在屏幕内（窗口比屏幕大时贴左上）
	for id in panels.keys():
		var p: Control = panels[id]
		if not is_instance_valid(p):
			continue
		var sz := p.custom_minimum_size
		p.size = sz
		p.position = Vector2(maxf(8.0, (size.x - sz.x) * 0.5), maxf(8.0, (size.y - sz.y) * 0.5))


## v1.8.7：至宝 / 世界泡 变成"盖在世界上的页面"，再点一次收回世界。
##（v1.8.8 会把它们正式变成浮窗，交互方向一致。）
func _toggle_page(id: String) -> void:
	if current_view == id:
		_switch_view(DEFAULT_VIEW)
	else:
		_switch_view(id)


## v1.8.11：统计面板（资源栏中间）
func _toggle_stats_panel() -> void:
	if stats_panel == null:
		stats_panel = StatsPanel.new()
		stats_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
		stats_panel.visible = false
		stats_panel.closed.connect(_update_dim)
		add_child(stats_panel)
	stats_panel.visible = not stats_panel.visible
	if stats_panel.visible:
		_place_floating_ui()
		stats_panel.refresh()


func _toggle_tech_panel() -> void:
	if tech_panel == null:
		tech_panel = TechPanel.new()
		tech_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
		add_child(tech_panel)
		tech_panel.visible = false
	tech_panel.visible = not tech_panel.visible
	if tech_panel.visible:
		_place_floating_ui()
		tech_panel.refresh()


func _toggle_log_panel() -> void:
	if log_panel == null:
		log_panel = LogPanel.new()
		log_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
		add_child(log_panel)
		log_panel.visible = false
	log_panel.visible = not log_panel.visible
	if log_panel.visible:
		_place_floating_ui()


func _refresh_nav() -> void:
	# v1.7.1：改成按「配对」刷新。以前是靠按钮在栏里的顺序去 VIEWS 对号入座，
	# 世界球搬到栏外（顺序变了）就会整体错位；存配对就不会。
	for vid in nav_buttons:
		var b: Button = nav_buttons[vid]
		if not is_instance_valid(b):
			continue
		var active: bool = vid == current_view
		UIKit.style_button(b, active)
		b.add_theme_color_override("font_color", UIKit.GOLD if active else UIKit.TEXT)


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
	for c in abstract_box.get_children():
		c.queue_free()
	for c in concrete_box.get_children():
		c.queue_free()

	# 抽象资源（左，两行）：生产力 / 科研点 / 行政点数 ｜ 秩序结晶 / 凝聚力 / 人力
	_fill_group(abstract_box, Consts.RES_ABSTRACT, 3, false)
	# 具体资源（右，两行）：食物 / 货币 / 木材 / 煤 / 铜 ｜ 铁 / 原油 / 水晶碎屑
	_fill_group(concrete_box, Consts.RES_CONCRETE, 5, true)

	cycle_label.text = "周期 %d" % int(GameState.state["cycle"])
	var st := GameState.stability()
	var hp := GameState.happiness()
	var iv := GameState.autosave_interval()
	detail_label.text = "幸福度 %.0f　文化率 %.2f　稳定度 %.0f%%　地块 %d(我) / %d(敌) / %d(无主)　卡组 %s　自动存档 每%d周期" % [
		hp, GameState.culture_rate(), st * 100.0,
		TileManager.owned_tiles(GameState.state).size(), TileManager.enemy_tiles(GameState.state).size(),
		TileManager.free_tiles(GameState.state).size(), str(GameState.state.get("active_group", "")),
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
			row.add_theme_constant_override("separation", UI.fs(10))
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
	panel.custom_minimum_size = Vector2(UI.px(250), UI.px(0))
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
			sep.custom_minimum_size = Vector2(UI.px(0), UI.px(1))
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
	h.add_theme_constant_override("separation", UI.fs(8))
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

# v1.2 作弊菜单
func _open_cheat_menu() -> void:
	open_dialog(CheatMenu.build())

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
	# v1.8.7：管理页与日志页都不再是一级入口，编号重排
	match k.keycode:
		KEY_1: _switch_view("treasure")
		KEY_2: _switch_view("gacha")
		KEY_3: _switch_view("world")
		KEY_SPACE: _end_cycle()
		KEY_ESCAPE:
			# v1.8.8：浮窗能关了，所以 Esc 先关浮窗
			if stats_panel != null and is_instance_valid(stats_panel) and stats_panel.visible:
				stats_panel.visible = false
			if _any_page_panel_open():
				_close_all_panels()
				_refresh_nav()
			_close_res_popup()
			close_dialog()


func goto_view(id: String) -> void:
	_switch_view(id)
