extends Control
## 游戏主页外壳：上方资源栏 + 中间功能场景 + 下方一级按钮 + 结束周期按钮。
## 对应设计文档「游戏主页」章节。
##
## 一级按钮：管理 / 至宝 / 世界泡 / 日志 / 世界
## v1.2：删除了「休眠」页（功能与其他页面重复），退出改为顶部栏按钮。

signal exit_to_menu

var top_bar: TopBar
## 资源收支小窗（scripts/ui/parts/res_info_popup.gd）✓
var res_info: ResInfoPopup
## 悬浮按钮层（scripts/ui/parts/floating_bar.gd）✓
var floating: FloatingBar
## 面板管理（至宝/世界泡浮窗 + 统计/科技/日志）✓
var panels_host: PanelsHost
## 周期 / 弹窗 / 存档 ✓
var flow: GameFlow

## v1.8.11：统计面板（资源栏中间的「统计」按钮打开；默认看资源）
## v1.8.8：二级浮窗注册表 id -> PagePanel（内部页面同时挂到 views[id]，保持旧调用点可用）
## 压暗层（浮窗打开时出现；mouse_filter = IGNORE，所以**地图仍然能拖能点**）
var dim: ColorRect



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

	# --- 面板管理（至宝/世界泡浮窗 + 统计/科技/日志）---
	panels_host = PanelsHost.new()
	add_child(panels_host)
	panels_host.view_changed.connect(func(id: String) -> void:
		floating.set_nav_active(id))
	panels_host.dim_changed.connect(func(on: bool) -> void:
		if is_instance_valid(dim):
			dim.visible = on)
	floating.tech_pressed.connect(_toggle_tech_panel)
	floating.log_pressed.connect(_toggle_log_panel)
	floating.nav_pressed.connect(_toggle_page)

	# --- 周期 / 弹窗 / 存档 ---
	flow = GameFlow.new()
	add_child(flow)
	flow.setup(self, manager, panels_host)
	flow.exit_to_menu.connect(func() -> void: exit_to_menu.emit())
	flow.cycle_finished.connect(_refresh)

	_place_floating_ui()

	# 资源收支小窗：排在最后 → 盖在所有东西之上 ✓
	res_info = ResInfoPopup.new()
	add_child(res_info)

	_refresh()


# ---------------------------------------------------------------------------
# 视图切换
# ---------------------------------------------------------------------------
func _on_toast(text: String) -> void:
	pass


func _refresh() -> void:
	if not is_instance_valid(top_bar):
		return
	# 资源栏重建前先收起收支悬浮窗（避免内容过期）
	_close_res_popup()
	top_bar.refresh()

	manager.refresh()   # 世界层 ✓
	# 开着的浮窗页也刷一下（它的数据同样变过）
	if panels_host != null and panels_host.current_view != PanelsHost.DEFAULT_VIEW:
		var v2: Variant = panels_host.views.get(panels_host.current_view, null)
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
func _unhandled_input(event: InputEvent) -> void:
	# 2026-10-24：按键改走 Input Map（项目设置 → 输入映射）✓
	# 好处：改键 / 手柄 / 多设备都不用改这里；is_action_pressed 默认忽略长按重复 ✓
	# 世界层的"选点模式"优先吃掉 Esc（原来是 view_world_page 自己的 _unhandled_input）✓
	if event.is_action_pressed("close_ui") and manager.cancel_pick():
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
		if panels_host != null and is_instance_valid(panels_host.stats_panel) \
				and panels_host.stats_panel.visible:
			panels_host.stats_panel.visible = false
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
## 中控（scripts/ui/manager_center.gd）：管理类功能的挂载与协调 ✓
var manager: ManagerCenter
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
	mv.add_child(map)

	# --- 中控：管理类功能（右键菜单 / 修建 / 据点 / 地块信息 / 单位操作）---
	manager = ManagerCenter.new()
	add_child(manager)
	manager.setup(map)
	map.tile_left_clicked.connect(manager.on_tile_clicked)
	map.tile_right_clicked.connect(manager.on_tile_right_clicked)
	map.hover_changed.connect(manager.on_hover_changed)

	call_deferred("_init_map")




func _init_map() -> void:
	if is_instance_valid(map):
		map.center_on_axial(TileManager.coord_of(str(GameState.state["capital"])))
		# 布局稳定后再居中一次，保证地图恰好落在可见区域中央
		await get_tree().process_frame
		await get_tree().process_frame
		map.center_on_axial(TileManager.coord_of(str(GameState.state["capital"])))


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


# ---------------------------------------------------------------------------
# 悬浮层：建按钮（面板管理在 _build 里接，见 panels_host）
# ---------------------------------------------------------------------------
func _build_floating_ui() -> void:
	floating = FloatingBar.new()
	add_child(floating)
	var nav_items: Array = []
	for v in PanelsHost.VIEWS:
		nav_items.append({"id": str(v["id"]), "name": str(v["name"])})
	floating.setup(nav_items)
	floating.end_pressed.connect(_end_cycle)
	resized.connect(_place_floating_ui)
	_place_floating_ui()


## ⚠️ 悬浮层一律用 TOP_LEFT 锚点 + 按屏幕尺寸算绝对位置，并在 resized 时重摆。
func _place_floating_ui() -> void:
	if is_instance_valid(floating):
		floating.layout(size)
	if is_instance_valid(panels_host):
		var anchor := Vector2.ZERO
		if is_instance_valid(top_bar.stats_button):
			anchor = top_bar.stats_button.global_position - global_position
		panels_host.layout(size, anchor)


# ---------------------------------------------------------------------------
# 转调（真正的实现在 panels_host / game_flow）
# ---------------------------------------------------------------------------
func _switch_view(id: String) -> void:
	panels_host.switch_view(id)


func _close_all_panels() -> void:
	panels_host.close_all()


func _any_page_panel_open() -> bool:
	return panels_host.any_page_open()


func _toggle_page(id: String) -> void:
	panels_host.toggle_page(id)


func _toggle_stats_panel() -> void:
	panels_host.toggle_stats()


func _toggle_tech_panel() -> void:
	panels_host.toggle_tech()


func _toggle_log_panel() -> void:
	panels_host.toggle_log()


func _refresh_nav() -> void:
	pass   # 导航高亮由 panels_host.view_changed 驱动


func _end_cycle() -> void:
	flow.end_cycle()


func _quick_save() -> void:
	flow.quick_save()


func _confirm_exit() -> void:
	flow.confirm_exit()


func _open_cheat_menu() -> void:
	flow.open_cheat()


func open_dialog(d: DialogLayer) -> void:
	flow.open_dialog(d)


func close_dialog() -> void:
	flow.close_dialog()
