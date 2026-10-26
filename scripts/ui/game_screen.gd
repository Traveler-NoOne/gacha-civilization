extends Control
## 游戏主页外壳：上方资源栏 + 中间功能场景 + 下方一级按钮 + 结束周期按钮。
## 对应设计文档「游戏主页」章节。
##
## 一级按钮：管理 / 至宝 / 世界泡 / 日志 / 世界
## v1.2：删除了「休眠」页（功能与其他页面重复），退出改为顶部栏按钮。

signal exit_to_menu

## 2026-10-26：世界页直接合并进本文件（它是最底层），所以 VIEWS 里**只剩二级浮窗页**。
## DEFAULT_VIEW 仍表示"没有浮窗打开"的状态 ✓
## 浮窗尺寸**待试玩后定**（先用 1120×620）。
const VIEWS := [
	{"id": "treasure", "name": "至宝", "script": "res://scripts/ui/views/treasure_view.gd", "w": 1120.0, "h": 620.0},
	{"id": "gacha", "name": "世界泡", "script": "res://scripts/ui/views/gacha_view.gd", "w": 1120.0, "h": 620.0},
]
const DEFAULT_VIEW := "world"



var current_view := DEFAULT_VIEW
var views: Dictionary = {}
## 顶部资源栏（自成一体的控件，见 scripts/ui/parts/top_bar.gd）✓
var top_bar: TopBar
## 资源收支小窗（scripts/ui/parts/res_info_popup.gd）✓
var res_info: ResInfoPopup
## 悬浮按钮层（scripts/ui/parts/floating_bar.gd）✓
var floating: FloatingBar

## v1.8.11：统计面板（资源栏中间的「统计」按钮打开；默认看资源）
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
	_refresh_nav()


# ---------------------------------------------------------------------------
# 构建
# ---------------------------------------------------------------------------
func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Palette.BG_DARK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# --- 世界层：铺满全屏，它是最底层（2026-10-26：世界页合并进来）---
	_build_world()

	# --- 顶部资源栏：叠在世界之上（锚顶部，高 98）---
	top_bar = TopBar.new()
	add_child(top_bar)
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_bottom = UI.px(98)
	top_bar.menu_pressed.connect(_confirm_exit)
	top_bar.save_pressed.connect(_quick_save)
	top_bar.cheat_pressed.connect(_open_cheat_menu)
	top_bar.stats_pressed.connect(_toggle_stats_panel)
	top_bar.chip_clicked.connect(_show_res_info)

	# v1.8.8：压暗层（在按钮之前 → 在按钮和浮窗下面；IGNORE 让它不吃输入）
	dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.visible = false
	add_child(dim)

	# 悬浮按钮（左上科技树 / 右上日志 / 左下至宝·世界泡 / 右下结束周期）
	_build_floating_ui()
	# 工具条：世界层的四个动作（合并后这些方法就在本类里 → 传 self）✓
	floating.add_tools(self)
	_place_floating_ui()

	# 资源收支小窗：排在最后 → 盖在所有东西之上 ✓
	res_info = ResInfoPopup.new()
	add_child(res_info)

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
func _build_floating_ui() -> void:
	floating = FloatingBar.new()
	add_child(floating)
	var nav_items: Array = []
	for v in VIEWS:
		if str(v["id"]) != DEFAULT_VIEW:
			nav_items.append({"id": str(v["id"]), "name": str(v["name"])})
	floating.setup(nav_items)
	floating.tech_pressed.connect(_toggle_tech_panel)
	floating.log_pressed.connect(_toggle_log_panel)
	floating.nav_pressed.connect(_toggle_page)
	floating.end_pressed.connect(_end_cycle)

	resized.connect(_place_floating_ui)
	# 状态变了就顺带刷新开着的科技浮窗（科研点与解锁状态会变）
	GameState.state_changed.connect(func() -> void:
		if tech_panel != null and is_instance_valid(tech_panel) and tech_panel.visible:
			tech_panel.refresh())
	_place_floating_ui()


## ⚠️ 悬浮层一律用 **TOP_LEFT 锚点 + 按屏幕尺寸算绝对位置**，并在 resized 时重摆。
##（"锚右上 + 负偏移"那套很容易摆错：锚点若在 add_child 之前设，还没有父节点可参照。）
func _place_floating_ui() -> void:
	if is_instance_valid(floating):
		floating.layout(size)

	if stats_panel != null and is_instance_valid(stats_panel):
		# 展开在「统计」按钮的正下方（和"点资源弹收支窗"一个位置逻辑）
		var gp := Vector2.ZERO
		if is_instance_valid(top_bar.stats_button):
			gp = top_bar.stats_button.global_position - global_position
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
	if is_instance_valid(floating):
		floating.set_nav_active(current_view)


func _end_cycle() -> void:
	var rep: Dictionary = Cycle.end_cycle(GameState.state, GameState.rng())
	# 广播给当前视图
	if current_view == DEFAULT_VIEW:
		on_cycle_finished(rep)
	else:
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
	if not is_instance_valid(top_bar):
		return
	# 资源栏重建前先收起收支悬浮窗（避免内容过期）
	_close_res_popup()
	top_bar.refresh()

	if current_view == DEFAULT_VIEW:
		refresh()   # 世界层就是自己 ✓
	else:
		var v2: Variant = views.get(current_view, null)
		if v2 != null and v2.has_method("refresh"):
			v2.refresh()


## 资源收支小窗（实现在 scripts/ui/parts/res_info_popup.gd）✓
func _show_res_info(key: String, rect: Rect2) -> void:
	if is_instance_valid(res_info):
		res_info.show_for(key, rect)


func _close_res_popup() -> void:
	if is_instance_valid(res_info):
		res_info.hide_popup()


## 快速保存到当前槽位（没槽位就存 1 号）✓
func _quick_save() -> void:
	var slot := int(GameState.state.get("current_slot", -1))
	if slot < 0:
		slot = 1
	Save.write(slot, GameState.state)


func _confirm_exit() -> void:
	# 休眠页删除后，这里承接「退出到主菜单 / 退出到桌面」；内容在 scripts/ui/exit_dialog.gd ✓
	open_dialog(ExitDialog.build(close_dialog, func() -> void: exit_to_menu.emit()))


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
	# 2026-10-24：按键改走 Input Map（项目设置 → 输入映射）✓
	# 好处：改键 / 手柄 / 多设备都不用改这里；is_action_pressed 默认忽略长按重复 ✓
	# 世界层的"选点模式"优先吃掉 Esc（原来是 view_world_page 自己的 _unhandled_input）✓
	if pick_mode != "" and event.is_action_pressed("close_ui"):
		if pick_mode == "recruit":
			_cancel_recruit()
		else:
			_end_pick()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("view_treasure"):
		_switch_view("treasure")
	elif event.is_action_pressed("view_gacha"):
		_switch_view("gacha")
	elif event.is_action_pressed("view_world"):
		_switch_view("world")
	elif event.is_action_pressed("end_cycle"):
		_end_cycle()
	elif event.is_action_pressed("close_ui"):
		# 浮窗能关了，所以 Esc 先关浮窗
		if stats_panel != null and is_instance_valid(stats_panel) and stats_panel.visible:
			stats_panel.visible = false
		if _any_page_panel_open():
			_close_all_panels()
			_refresh_nav()
		_close_res_popup()
		close_dialog()


func goto_view(id: String) -> void:
	_switch_view(id)


# ===========================================================================
# 世界层（2026-10-26 从 scripts/ui/views/view_world_page.gd 合并进来）
# 它是游戏主页的**底层**：地图 + 地块交互 + 据点窗口 + 修建浮窗 + 单位条
# 以后要把"非世界"的东西（顶栏 / 悬浮条 / 面板管理 / 周期输入）拆出去，这里就是地基 ✓
# ===========================================================================

var map: HexMapView
var selected := ""


# ---------------------------------------------------------------------------
# v1.5：单位操作（点击轮换 / 招募选地 / 移动 / 攻击）
# ---------------------------------------------------------------------------
## v1.8.2：简约地块信息小窗（点在非我方地块时，在鼠标位置弹出）
var tile_info_popup: PanelContainer = null


var tile_info_box: VBoxContainer = null

## v1.8.4：据点管理窗口（点我方领地块时在右侧打开）
var stronghold_panel: StrongholdPanel = null

## v1.8.5：右键菜单（球形图标按钮）。**数据驱动**：以后加"拆除 / 驻军 / 巡查"只要加一行。
const TILE_ACTIONS := [
	{"id": "build", "icon": "hammer-ball", "tip": "修建建筑"},
	{"id": "harvest", "icon": "axe-ball", "tip": "破坏性采集（清掉树林，+30 木材）"},
]
var action_menu: PanelContainer = null
var build_panel: BuildPanel = null
var sel_uid := ""
## 悬停 1 秒后要显示的那一格；每次悬停变化就自增序号，用来作废过期的那次
var _hover_seq := 0

var pick_mode := ""      # "" / "recruit" / "move" / "attack"
var pick_unit := ""
var pending_tile := ""   # 招募选地：已选中的目标地块
var unit_strip: PanelContainer
var unit_strip_row: HBoxContainer
var unit_panel: PanelContainer
var unit_panel_box: VBoxContainer


func _build_world() -> void:
	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", UI.fs(6))
	add_child(root)

	# ---- 地图 ----
	var map_panel := UIKit.panel(Palette.BG_SLOT, Palette.LINE, 6)
	map_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(map_panel)
	var mv := VBoxContainer.new()
	map_panel.add_child(mv)

	map = HexMapView.new()
	# Control 默认 custom_minimum_size 是 (200,200)：必须显式压低，否则会把父容器撑爆
	map.custom_minimum_size = Vector2(UI.px(120), UI.px(120))
	map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map.tile_left_clicked.connect(_on_tile_clicked)

	map.tile_right_clicked.connect(_on_tile_right_clicked)
	map.hover_changed.connect(_on_hover_changed)

	mv.add_child(map)

	# ---- v1.8.20.5：底部单位立绘条 + 左下角单位操作窗（按 v1.7 原样补回来） ----
	# 起因：这两块原本建在 v1.7 的这个页面里，v1.8 重写世界页时**只把"刷新"搬了过来、"创建"丢了** ——
	# 于是 _refresh_unit_strip / _refresh_unit_panel 开头的 is_instance_valid 判断永远成立、直接 return，
	# 底部单位条与单位操作窗再没出现过（攻击 / 移动 / 驻军三个按钮都在那个窗里，v1.6.1 的核心交互）。
	# 摆放全靠锚点（和 v1.7 一致），尺寸/间距走 UI.px / UI.fs；不放进 map —— map 开了 clip_contents。
	unit_strip = PanelContainer.new()
	unit_strip.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	unit_strip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	unit_strip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	unit_strip.position = Vector2(0, UI.px(-10))
	unit_strip.visible = false
	UIKit.apply_panel(unit_strip, Color(0.08, 0.08, 0.12, 0.94), Palette.LINE, 6)
	add_child(unit_strip)
	unit_strip_row = HBoxContainer.new()
	unit_strip_row.add_theme_constant_override("separation", UI.fs(6))
	unit_strip.add_child(unit_strip_row)

	unit_panel = PanelContainer.new()
	unit_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	unit_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	# 左下角那一排「至宝 / 世界泡」悬浮按钮是 v1.8.7 才加的，v1.7 时这里没有东西 →
	# 照原样摆会被按钮压住（实测过），所以抬高到按钮之上：16(边距) + 40(按钮高) + 14(原间隙)。
	unit_panel.position = Vector2(UI.px(14), UI.px(-70))

	unit_panel.custom_minimum_size = Vector2(UI.px(260), 0)
	unit_panel.visible = false
	UIKit.apply_panel(unit_panel, Color(0.07, 0.07, 0.11, 0.96), Palette.GOLD, 6)
	add_child(unit_panel)
	unit_panel_box = VBoxContainer.new()
	unit_panel_box.add_theme_constant_override("separation", UI.fs(4))
	unit_panel.add_child(unit_panel_box)

	call_deferred("_init_map")




func _init_map() -> void:
	if is_instance_valid(map):
		map.center_on_axial(TileManager.coord_of(str(GameState.state["capital"])))
		# 布局稳定后再居中一次，保证地图恰好落在可见区域中央
		await get_tree().process_frame
		await get_tree().process_frame
		map.center_on_axial(TileManager.coord_of(str(GameState.state["capital"])))


func _on_tile_clicked(key: String, uid: String, gpos: Vector2) -> void:
	# ① 选地 / 选目标模式优先（保持原行为）
	if pick_mode != "":
		_pick_tile(key)
		return
	# 左键点任何地方都先收起右键菜单
	_hide_action_menu()
	# v1.8.20.4：小窗改由「悬停」负责，点击一律先把它收起来
	_hide_tile_info()
	# ② 点中了棋子图标 → 直接选中它（图标优先于首都星）
	if uid != "":
		selected = key
		sel_uid = uid
		_refresh_after_select()
		return
	# ③ 点中了首都星 → 打开「这一格」对应的据点面板（认格子）
	if map != null and map.capital_star_hit(key, gpos):

		selected = key
		sel_uid = ""
		_refresh_after_select()
		_open_stronghold_panel(key)
		return
	# ④ 我方其它格子 → 只更新选中，不弹面板、不弹信息
	if TileManager.tile_at(GameState.state, key).get("owner", Consts.Owner.NONE) == Consts.Owner.PLAYER:
		selected = key
		sel_uid = ""
		_refresh_after_select()
		return
	# ⑤ 空白 / 敌方格 → 取消选择，什么都不打开
	selected = ""
	sel_uid = ""
	_refresh_after_select()


## v1.8.20.4：悬停 1 秒后才显示简约地块信息（不依赖点击）。
## at 传了位置就用它（测试用）；不传就用鼠标当前位置。
func _on_hover_changed(key: String, at: Vector2 = Vector2(-1.0, -1.0)) -> void:
	_hover_seq += 1
	var my_seq := _hover_seq
	# v1.8.20.11：鼠标一离开那个地块就**销毁**旧弹窗（不是等新弹窗来了再清）。
	# 于是"新的在量尺寸"时旧的已经真的不在了 —— 不必等帧、也不必给它固定高度。
	_destroy_tile_info()
	if key == "":
		return

	var pos := at
	if pos.x < 0.0:
		pos = get_viewport().get_mouse_position()
	await get_tree().create_timer(1.0).timeout
	# 这 1 秒里又换了格子（或进入了选地模式）→ 这次作废
	if my_seq != _hover_seq or pick_mode != "" or not is_visible_in_tree():
		return
	_show_tile_info(key, pos)



## 选中状态变化后要刷新的一串地方（原来在点击处理里抄了两遍，收成一处）
func _refresh_after_select() -> void:
	_refresh_unit_strip()
	_refresh_unit_panel()
	_refresh_marks()


# ---------------------------------------------------------------------------
# 刷新
# ---------------------------------------------------------------------------
func refresh() -> void:
	if not is_instance_valid(map):
		return
	# v1.5：从至宝点「招募」跳过来时，自动进入选地模式
	var pr := Units.pending_recruit_uid(GameState.state)
	if pr != "" and pick_mode == "":
		pick_mode = "recruit"
		pick_unit = pr
		pending_tile = ""
	_refresh_marks()
	_refresh_unit_strip()
	_refresh_unit_panel()
	# v1.8.4：据点管理窗口开着的话，内容跟着状态走（否则会显示旧数据）
	if stronghold_panel != null and is_instance_valid(stronghold_panel) and stronghold_panel.visible:
		stronghold_panel.refresh()
	map.queue_redraw()


func _refresh_marks() -> void:
	map.marks.clear()
	if pick_mode == "recruit":
		for k in Units.deployable_keys(GameState.state):
			map.marks[k] = Color(0.55, 0.95, 0.65)
		if pending_tile != "":
			map.marks[pending_tile] = Palette.GOLD
	elif pick_mode == "move":
		for k in _move_targets(pick_unit):
			map.marks[k] = Color(0.55, 0.95, 0.65)
	elif pick_mode == "attack":
		for k in _attack_targets(pick_unit):
			map.marks[k] = Color(0.95, 0.45, 0.40)
	else:
		for k in TileManager.claimable_keys(GameState.state):
			map.marks[k] = Color(0.55, 0.95, 0.65)
	map.queue_redraw()


## v1.8.4：打开据点管理窗口。
## 关闭方式：窗口右上角的 ✕（**故意不"点别处就自动关"** —— 管理窗口不该因为你点了一下地图就消失）。
## v1.8.20.4：认格子 —— 打开被点那一格对应的据点面板
func _open_stronghold_panel(key: String) -> void:
	_ensure_stronghold_panel()
	stronghold_panel.key = key
	stronghold_panel.visible = true
	_place_stronghold_panel()
	stronghold_panel.refresh()



## 贴着世界页右侧摆（上下留边距）。窗口尺寸固定，所以只要按页宽算一次。
func _place_stronghold_panel() -> void:
	if stronghold_panel == null or not is_instance_valid(stronghold_panel):
		return
	stronghold_panel.position = Vector2(maxf(0.0, size.x - UI.px(356.0	)), 56.0)
	


## 懒创建（第一次用到才建）；固定尺寸 + 锚在右侧。
## 注意：挂在本页上，**不放进 map**（map 开了 clip_contents，会把浮层剪掉）。
func _ensure_stronghold_panel() -> void:
	if stronghold_panel != null:
		return
	stronghold_panel = StrongholdPanel.new()
	# ⚠️ 锚点用 TOP_LEFT + 绝对定位。
	# 别用「锚右上 + 负偏移」那一套：锚点若在 add_child **之前**设，那时还没有父节点可参照，
	# 负偏移会被当成绝对坐标，窗口直接跑到屏幕外（实测 global_position = -356，白忙一场）。
	stronghold_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	stronghold_panel.size = Vector2(UI.px(340), UI.px(520))
	add_child(stronghold_panel)
	stronghold_panel.visible = false


# ---------------------------------------------------------------------------
# v1.8.5：右键菜单 + 修建浮窗
# ---------------------------------------------------------------------------
func _on_tile_right_clicked(key: String, gpos: Vector2) -> void:
	# 选地 / 选目标模式下不给右键菜单（免得和"点格子选目标"混在一起）
	if pick_mode != "":
		return
	_hide_tile_info()
	_show_tile_actions(key, gpos)


func _show_tile_actions(key: String, gpos: Vector2) -> void:
	_ensure_action_menu()
	for c in action_menu.get_children():
		c.queue_free()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UI.fs(6))
	action_menu.add_child(row)
	row.add_child(UIKit.dim(key, 10))
	for a in TILE_ACTIONS:
		var aid := str(a["id"])
		if not _action_available(aid, key):
			continue   # 这块地不支持这个动作 → 整条不显示（不是灰掉）✓
		var b := UIKit.image_button(str(a["icon"]), str(a["tip"]), 40, 40)
		b.pressed.connect(func() -> void:
			_hide_action_menu()
			_run_tile_action(aid, key))
		row.add_child(b)
	action_menu.visible = true
	# 贴点弹窗统一走 UIKit.place_popup_at（全局坐标 + 尺寸算准后重摆 + 下方放不下翻上方 + 夹进视口）
	UIKit.place_popup_at(action_menu, gpos, Vector2(6.0, 6.0))



func _hide_action_menu() -> void:
	if action_menu != null:
		action_menu.visible = false


func _ensure_action_menu() -> void:
	if action_menu != null:
		return
	action_menu = PanelContainer.new()
	action_menu.set_anchors_preset(Control.PRESET_TOP_LEFT)
	action_menu.visible = false
	UIKit.apply_panel(action_menu, Color(0.07, 0.07, 0.11, 1.0), Palette.GOLD, 6)
	add_child(action_menu)


## 菜单里每个动作的落点（加动作就在这里加一个分支）
func _run_tile_action(id: String, key: String) -> void:
	match id:
		"build":
			_open_build_panel(key)
		"harvest":
			var r: Dictionary = Buildings.request_harvest(GameState.state, key)
			if bool(r["ok"]):
				GameState.toast.emit("破坏性采集已加入规划队列（%.0f 生产力）" % Buildings.HARVEST_PROD)
			else:
				GameState.toast.emit(str(r["why"]))
		_:
			GameState.toast.emit("这个动作还没做：%s" % id)


## 某个右键动作在这块地上能不能用（不能用就整条不显示）✓
func _action_available(id: String, key: String) -> bool:
	if id == "harvest":
		return bool(Buildings.can_harvest(GameState.state, key)["ok"])
	return true


func _open_build_panel(key: String) -> void:
	_ensure_build_panel()
	build_panel.visible = true
	build_panel.setup(key)
	_place_center(build_panel)


func _ensure_build_panel() -> void:
	if build_panel != null:
		return
	build_panel = BuildPanel.new()
	build_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	build_panel.size = Vector2(UI.px(560), UI.px(420))
	add_child(build_panel)
	build_panel.visible = false


## 把尺寸固定的浮窗摆到页面中间
func _place_center(p: Control) -> void:
	p.position = Vector2(
		maxf(0.0, (size.x - p.size.x) * 0.5),
		maxf(0.0, (size.y - p.size.y) * 0.5))


## 简约地块信息小窗：**懒创建**（第一次要用时才建），挂在本页上。
## 不放进 map —— map 开了 clip_contents，会把浮出格子的东西剪掉。
func _ensure_tile_info_popup() -> void:
	if tile_info_popup != null:
		return
	tile_info_popup = PanelContainer.new()
	tile_info_popup.set_anchors_preset(Control.PRESET_TOP_LEFT)
	tile_info_popup.custom_minimum_size = Vector2(UI.px(210), UI.px(0))
	tile_info_popup.visible = false
	# 小窗里有按钮（占领），所以必须能接收点击；点窗外仍然照常落到地图上
	tile_info_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	UIKit.apply_panel(tile_info_popup, Color(0.07, 0.07, 0.11, 1.0), Palette.LINE, 6)
	add_child(tile_info_popup)
	tile_info_box = VBoxContainer.new()
	tile_info_box.add_theme_constant_override("separation", UI.fs(3))
	tile_info_popup.add_child(tile_info_box)



## 在鼠标位置显示某一格的简约信息（取代"选中地块"）
func _show_tile_info(key: String, gpos: Vector2) -> void:
	_ensure_tile_info_popup()
	# 第二道保险：即使哪天有人不经过"离开地块"就重弹，这里也把旧内容**立即**清掉
	# （queue_free 要等帧末，会把旧内容算进这一次的尺寸测量）。
	# 这里不在任何子控件的回调里，free 是安全的；_hide_tile_info 那边保留 queue_free。
	for c in tile_info_box.get_children():
		c.free()

	var t := TileManager.tile_at(GameState.state, key)
	tile_info_box.add_child(UIKit.title("地块 %s" % key, 13))
	var discovered := bool(t.get("discovered", false))
	if not discovered:
		tile_info_box.add_child(UIKit.dim("（未点亮：迷雾）", 11))
		tile_info_popup.visible = true
		UIKit.place_popup_at(tile_info_popup, gpos, Vector2(14.0, 10.0))
		return


	var owner_txt := "无主"
	var owner_col := Palette.TEXT_DIM
	match t.get("owner", Consts.Owner.NONE):
		Consts.Owner.PLAYER:
			owner_txt = "我方领地"
			owner_col = Color(0.55, 0.85, 1.0)
		Consts.Owner.ENEMY:
			owner_txt = "敌方"
			owner_col = Color(0.95, 0.45, 0.45)
	tile_info_box.add_child(UIKit.text_label("势力：%s" % owner_txt, 11, owner_col))
	# 地块明细（单格版）—— 与据点详情里那行同格式，避免两处口径不同
	var nm := str(t.get("name", ""))
	if nm != "":
		tile_info_box.add_child(UIKit.text_label("名称：%s" % nm, 11, Palette.TEXT))
	var bcount := (t.get("buildings", []) as Array).size()
	var line := "地形 %s　土地 %.1f/%.1f　建筑 %d" % [
		Consts.terrain_name(str(t.get("terrain", ""))),
		Strongholds.land_used(t), Strongholds.land_cap(t), bcount]
	var l := UIKit.dim(line, 11)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tile_info_box.add_child(l)
	# v1.8.21：地物（覆盖物）单独一行 —— 裸地不显示（空串），免得每格都多一行废话
	var cover_txt := str(t.get("cover", ""))
	if cover_txt != "":
		tile_info_box.add_child(UIKit.text_label("地物：%s" % Consts.cover_name(cover_txt), 11, Palette.OK))

	var res := str(t.get("resource", ""))
	if res != "":
		tile_info_box.add_child(UIKit.text_label("资源点：%s" % Consts.res_name(res), 11, Palette.OK))
	# v1.8.5：可占领的地块 → 在这里直接给「占领」按钮。
	# 旧右侧规划面板删掉后，**这里就是占领的唯一入口**（不能丢功能）。
	if TileManager.claimable_keys(GameState.state).has(key):
		tile_info_box.add_child(UIKit.spacer(2))
		var cost := int(TileManager.claim_cost(GameState.state))
		var cb := UIKit.normal("占领此地块（%d 行政点数）" % cost, 11)
		cb.pressed.connect(func() -> void:
			var r: Dictionary = TileManager.claim(GameState.state, key)
			if not bool(r["ok"]):
				GameState.toast.emit(str(r["why"]))
			_hide_tile_info()
			GameState.state_changed.emit()
			refresh())
		tile_info_box.add_child(cb)
	tile_info_popup.visible = true
	UIKit.place_popup_at(tile_info_popup, gpos, Vector2(14.0, 10.0))





## v1.8.20.11：销毁弹窗（连内容一起，下次用时会自动重建）。
## 用 queue_free 而不是 free：这条路径也可能被「占领」按钮的回调走到，立即释放等于把它自己删掉；
## 而下次弹窗至少要等悬停 1 秒，帧末释放绰绰有余。
func _destroy_tile_info() -> void:
	if tile_info_popup == null:
		return
	tile_info_popup.queue_free()
	tile_info_popup = null
	tile_info_box = null


func _hide_tile_info() -> void:


	if tile_info_popup != null:
		tile_info_popup.visible = false


func on_cycle_finished(_rep: Dictionary) -> void:
	refresh()


# ===========================================================================
# v1.5：招募选地 / 移动 / 攻击 / 单位操作窗
# ===========================================================================
## v1.7：直接复用 GameState 的同一份规则（此前这里自己判一遍、且漏了中继格检查）
func _move_targets(uid: String) -> Array[String]:
	return Combat.move_candidates(GameState.state, uid)

func _attack_targets(uid: String) -> Array[String]:
	var out: Array[String] = []
	var u := Units.unit_by_uid(GameState.state, uid)
	if u.is_empty() or int(u.get("move_left", 0)) <= 0:
		return out
	var from := str(u.get("tile", ""))
	if from == "":
		return out
	var a := TileManager.coord_of(from)
	for d in Hex.DIRECTIONS:
		var k := TileManager.key_of(a + d)
		var t := TileManager.tile_at(GameState.state, k)
		if not t.is_empty() and t.get("owner", Consts.Owner.NONE) == Consts.Owner.ENEMY:
			out.append(k)
	return out


func _pick_tile(key: String) -> void:
	if pick_mode == "recruit":
		if not Units.deployable_keys(GameState.state).has(key):
			GameState.toast.emit("该地块不可部署（已驻满或掌控力不足），请另选")
			return
		pending_tile = key
		_refresh_marks()
		_refresh_unit_panel()
		return
	if pick_mode == "move":
		var r := Combat.move_unit(GameState.state, pick_unit, key)
		GameState.toast.emit("移动完成" if bool(r["ok"]) else str(r["why"]))
		_end_pick()
		return
	if pick_mode == "attack":
		var r2 := Combat.unit_attack(GameState.state, pick_unit, key)
		if bool(r2["ok"]):
			GameState.toast.emit("清剿成功" if bool(r2["won"]) else "战斗未决")
		else:
			GameState.toast.emit(str(r2["why"]))
		_end_pick()


func _end_pick() -> void:
	pick_mode = ""
	pick_unit = ""
	pending_tile = ""
	_refresh_marks()
	_refresh_unit_panel()
	_refresh_unit_strip()
	refresh()


## 招募取消：客人保持客人（不做任何转换）
func _cancel_recruit() -> void:
	Units.cancel_recruit(GameState.state)
	_end_pick()


## 招募确认：唯一的状态转换点
func _confirm_recruit() -> void:
	var uid := Units.pending_recruit_uid(GameState.state)
	if uid == "":
		GameState.toast.emit("没有待招募的客人")
		return
	if pending_tile == "":
		GameState.toast.emit("请先点选一块高亮的领地进行部署")
		return
	var r := Units.confirm_recruit(GameState.state, uid, pending_tile)
	if not bool(r["ok"]):
		GameState.toast.emit(str(r["why"]))
		return
	GameState.toast.emit("招募完成：已成为公民并进驻该领地")
	_end_pick()


func _refresh_unit_strip() -> void:
	if not is_instance_valid(unit_strip_row):
		return
	for c in unit_strip_row.get_children():
		c.queue_free()
	var units: Array = []
	if selected != "":
		for u in Units.units_on_tile(GameState.state, selected):
			if UnitDB.is_citizen(u):
				units.append(u)
	unit_strip.visible = units.size() >= 2
	if not unit_strip.visible:
		return
	unit_strip_row.add_child(UIKit.dim("该地块 %d 个单位：" % units.size(), 11))
	for u in units:
		# v1.6.1：立绘窗口 —— 每个单位一个「立绘 + 名字」
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", UI.fs(3))
		cell.add_child(UIKit.unit_art(u, "chip", Vector2(28, 28)))
		var b := UIKit.small(str(u["name"]), 11)
		b.pressed.connect(func() -> void:
			sel_uid = str(u["uid"])
			_refresh_unit_panel())
		cell.add_child(b)
		unit_strip_row.add_child(cell)


func _refresh_unit_panel() -> void:
	if not is_instance_valid(unit_panel_box):
		return
	for c in unit_panel_box.get_children():
		c.queue_free()
	if pick_mode == "recruit":
		unit_panel.visible = true
		var gu := Units.unit_by_uid(GameState.state, pick_unit)
		unit_panel_box.add_child(UIKit.title("招募 · 部署", 13))
		var info := UIKit.dim("客人：%s\n点选绿色高亮的领地，然后确认。" % str(gu.get("name", "?")), 11)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		unit_panel_box.add_child(info)
		unit_panel_box.add_child(UIKit.text_label(
			"目标：%s" % ("（未选）" if pending_tile == "" else pending_tile), 11, Palette.GOLD))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", UI.fs(6))
		var okb := UIKit.primary("确认招募", 12)
		okb.pressed.connect(_confirm_recruit)
		row.add_child(okb)
		var cb := UIKit.normal("取消", 12)
		cb.pressed.connect(_cancel_recruit)
		row.add_child(cb)
		unit_panel_box.add_child(row)
		return
	if pick_mode != "":
		unit_panel.visible = true
		unit_panel_box.add_child(UIKit.title("选择目标", 13))
		unit_panel_box.add_child(UIKit.dim("绿色 = 可移动，红色 = 可攻击", 11))
		var cb2 := UIKit.normal("取消", 12)
		cb2.pressed.connect(func() -> void: _end_pick())
		unit_panel_box.add_child(cb2)
		return
	var u := Units.unit_by_uid(GameState.state, sel_uid)
	if sel_uid == "" or u.is_empty():
		unit_panel.visible = false
		return
	unit_panel.visible = true
	var eff := UnitDB.effective_attr(u)
	var prof := str(u.get("profession", UnitDB.MELEE))
	var garrisoned := bool(u.get("garrisoned", false))
	# v1.6.1：左边必须有单位立绘（现在还是几何占位，但也要显示）
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UI.fs(6))
	unit_panel_box.add_child(head)
	var pic := UIKit.unit_art(u, "icon", Vector2(60, 60))
	head.add_child(pic)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UI.fs(3))
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(col)
	col.add_child(UIKit.title(str(u["name"]), 13))
	col.add_child(UIKit.dim("%s·%s%s" % [
		UnitDB.rank_name(str(u.get("rank", ""))), UnitDB.profession_name(prof),
		"　［驻军中］" if garrisoned else ""], 10))
	col.add_child(UIKit.text_label("攻击 %.0f　血量 %d / %d　移动力 %d / %d" % [
		float(eff.get("atk", 0.0)), int(u.get("hp", 0)), UnitDB.max_hp(u),
		int(u.get("move_left", 0)), Units.max_move(GameState.state, u)], 11, Palette.TEXT))
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", UI.fs(6))
	var no_act := int(u.get("move_left", 0)) <= 0 or garrisoned
	var ba := UIKit.primary("攻击", 12)
	ba.disabled = no_act
	ba.tooltip_text = "攻击相邻地块的敌人（消耗本周期剩余行动）"
	ba.pressed.connect(func() -> void:
		pick_mode = "attack"
		pick_unit = sel_uid
		_refresh_marks()
		_refresh_unit_panel())
	row2.add_child(ba)
	var bm := UIKit.normal("移动", 12)
	bm.disabled = no_act
	bm.tooltip_text = "相邻格耗 1 移动力，间隔一格耗 2"
	bm.pressed.connect(func() -> void:
		pick_mode = "move"
		pick_unit = sel_uid
		_refresh_marks()
		_refresh_unit_panel())
	row2.add_child(bm)
	# v1.6.1：第三个按钮 —— 驻军（原「地块规划页」的驻军功能，搬到单位自己的操作窗里）
	var bg := UIKit.normal("解除驻军" if garrisoned else "驻军", 12)
	bg.tooltip_text = ("解除驻军后才能移动 / 攻击" if garrisoned
		else "驻军：维护费打折（领地内 −60% / 领地外 −10%），但不能移动或攻击")
	bg.pressed.connect(func() -> void:
		var r := Units.toggle_garrison(GameState.state, sel_uid)
		if not bool(r["ok"]):
			GameState.toast.emit(str(r["why"]))
		_refresh_marks()
		_refresh_unit_panel())
	row2.add_child(bg)
	col.add_child(row2)

## 离开世界页 = 放弃招募（客人保持客人，不做任何转换）
func _on_visibility_changed() -> void:
	if not visible and pick_mode == "recruit":
		Units.cancel_recruit(GameState.state)
		_end_pick()

func center_on_capital() -> void:
	map.center_on_axial(TileManager.coord_of(str(GameState.state["capital"])))

func reset_map_view() -> void:
	map.reset_view()

func set_axis(on: bool) -> void:
	map.show_axis = on
	map.queue_redraw()

func expand_map() -> void:
	var added := WorldgenBuilder.expand_map(GameState.state, 1)
	if added > 0:
		Journal.add(GameState.state, "营地扩建：地图上限扩大，新增 %d 格。" % added, "world")
		GameState.toast.emit("地图已扩大，新增 %d 格" % added)
		GameState.state_changed.emit()
	else:
		GameState.toast.emit("已达地图大小上限")
