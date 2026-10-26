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
## 顶部资源栏（自成一体的控件，见 scripts/ui/parts/top_bar.gd）✓
var top_bar: TopBar
## 资源收支小窗（scripts/ui/parts/res_info_popup.gd）✓
var res_info: ResInfoPopup
var content_host: MarginContainer
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
	_setup_world()
	_refresh_nav()


# ---------------------------------------------------------------------------
# 构建
# ---------------------------------------------------------------------------
func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Palette.BG_DARK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# --- 世界层：铺满全屏，它是最底层 ---
	content_host = MarginContainer.new()
	content_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(content_host)
	content_host.set_script(preload("res://scripts/ui/view_host.gd"))

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
func _setup_world() -> void:
	var def := _view_def(DEFAULT_VIEW)
	if def.is_empty():
		return
	var scr: Control = load(str(def["script"])).new()
	views[DEFAULT_VIEW] = scr
	content_host.add_view(scr, DEFAULT_VIEW)
	content_host.show_view(scr)
	current_view = DEFAULT_VIEW
	# 世界铺满后，它自己那条工具栏没地方放 → 交给悬浮层（资源栏下方）✓
	if is_instance_valid(floating):
		floating.add_tools(scr)
		_place_floating_ui()

##刷新系统按钮排布
# ---------------------------------------------------------------------------
# v1.8.7：悬浮按钮与浮窗（底栏取消，按钮直接悬在大世界上）
# ---------------------------------------------------------------------------
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
