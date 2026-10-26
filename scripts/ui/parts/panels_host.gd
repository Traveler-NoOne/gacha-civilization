class_name PanelsHost
extends Control
## 面板管理（2026-10-26 从 game_screen 拆出）✓
##
## 管三样：
##   1. 二级浮窗页（至宝 / 世界泡）—— PagePanel，**同一时刻只留一个**
##   2. 统计 / 科技树 / 日志 三个浮窗
##   3. 它们的开关、布局，以及"有浮窗开着 → 压暗底下"的通知
##
## 对外：switch_view / toggle_page / toggle_stats / toggle_tech / toggle_log
##       close_all / any_page_open / layout(area, stats_anchor)
## 信号：view_changed(id)（导航高亮用）/ dim_changed(on)（压暗层用）

signal view_changed(id: String)
## 有页级浮窗打开时压暗底下（调用方只负责切 dim.visible，不管别的）
signal dim_changed(on: bool)

const VIEWS := [
	{"id": "treasure", "name": "至宝", "script": "res://scripts/ui/views/treasure_view.gd", "w": 1120.0, "h": 620.0},
	{"id": "gacha", "name": "世界泡", "script": "res://scripts/ui/views/gacha_view.gd", "w": 1120.0, "h": 620.0},
]
## 世界是常驻底层，不是"页面" → 这个 id 只表示"没有浮窗打开"✓
const DEFAULT_VIEW := "world"

var current_view := DEFAULT_VIEW
var views: Dictionary = {}
var panels: Dictionary = {}
var stats_panel: StatsPanel = null
var tech_panel: TechPanel = null
var log_panel: LogPanel = null

## 最近一次 layout() 给的尺寸与「统计」按钮位置（重摆浮窗时用）
var _area := Vector2.ZERO
var _stats_anchor := Vector2.ZERO


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# 自己不吃鼠标：浮窗各自吃自己的
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 状态变了就刷新开着的科技浮窗（科研点与解锁状态会变）
	GameState.state_changed.connect(func() -> void:
		if tech_panel != null and is_instance_valid(tech_panel) and tech_panel.visible:
			tech_panel.refresh())


# ---------------------------------------------------------------------------
# 对外开关
# ---------------------------------------------------------------------------
## 世界常驻底层；切到别的 id = 打开它对应的二级浮窗；切回 world = 关掉所有浮窗。
func switch_view(id: String) -> void:
	if id == "" or id == DEFAULT_VIEW:
		close_all()
		current_view = DEFAULT_VIEW
		view_changed.emit(current_view)
		return
	open_panel(id)


## 打开（或唤起）一个二级浮窗。同一时刻只留一个页级浮窗，避免叠罗汉。
func open_panel(id: String) -> void:
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
		# 兼容：旧代码用 views[id] 拿"页面"，现在指向浮窗内部那一页
		views[id] = p.page
	var panel: PagePanel = panels[id]
	# ⚠️ 保证不能丢：**每次打开都刷新**，否则会重现"修建后进来看空列表"那类旧缓存 bug。
	if panel.page != null and is_instance_valid(panel.page) and panel.page.has_method("refresh"):
		panel.page.call("refresh")
	panel.visible = true
	current_view = id
	_layout_panels()
	_update_dim()
	view_changed.emit(current_view)


func close_all() -> void:
	for id in panels.keys():
		if (panels[id] as Control).visible:
			(panels[id] as Control).visible = false
	_update_dim()


func any_page_open() -> bool:
	for id in panels.keys():
		if (panels[id] as Control).visible:
			return true
	return false


## 至宝 / 世界泡：点开 → 再点收回世界
func toggle_page(id: String) -> void:
	if current_view == id:
		switch_view(DEFAULT_VIEW)
	else:
		switch_view(id)


func toggle_stats() -> void:
	if stats_panel == null:
		stats_panel = StatsPanel.new()
		stats_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
		stats_panel.visible = false
		stats_panel.closed.connect(_update_dim)
		add_child(stats_panel)
	stats_panel.visible = not stats_panel.visible
	if stats_panel.visible:
		_layout_panels()
		stats_panel.refresh()


func toggle_tech() -> void:
	if tech_panel == null:
		tech_panel = TechPanel.new()
		tech_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
		add_child(tech_panel)
		tech_panel.visible = false
	tech_panel.visible = not tech_panel.visible
	if tech_panel.visible:
		_layout_panels()
		tech_panel.refresh()


func toggle_log() -> void:
	if log_panel == null:
		log_panel = LogPanel.new()
		log_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
		add_child(log_panel)
		log_panel.visible = false
	log_panel.visible = not log_panel.visible
	if log_panel.visible:
		_layout_panels()


# ---------------------------------------------------------------------------
# 布局
# ---------------------------------------------------------------------------
## `stats_anchor`：「统计」按钮在本控件坐标系里的位置（统计面板贴在它下面）
func layout(area: Vector2, stats_anchor: Vector2) -> void:
	_area = area
	_stats_anchor = stats_anchor
	_layout_panels()


## ⚠️ 浮层一律按屏幕尺寸算绝对位置，窗口变了由外部再调 layout() ✓
func _layout_panels() -> void:
	if _area == Vector2.ZERO:
		return
	if stats_panel != null and is_instance_valid(stats_panel):
		# 展开在「统计」按钮的正下方（和"点资源弹收支窗"一个位置逻辑）
		var gp := _stats_anchor
		var w := 360.0
		var hh := minf(430.0, _area.y - gp.y - 80.0)
		stats_panel.size = Vector2(w, maxf(200.0, hh))
		stats_panel.position = Vector2(
			clampf(gp.x - 40.0, 8.0, maxf(8.0, _area.x - w - 8.0)),
			gp.y + 30.0)
	if tech_panel != null and is_instance_valid(tech_panel):
		var sz := Vector2(560, 480)
		tech_panel.size = sz
		tech_panel.position = Vector2(maxf(0.0, (_area.x - sz.x) * 0.5), maxf(0.0, (_area.y - sz.y) * 0.5))
	if log_panel != null and is_instance_valid(log_panel):
		# 四周留边 —— 这就是"露出底下的世界"的那点边距
		log_panel.position = Vector2(72.0, 64.0)
		log_panel.size = Vector2(maxf(200.0, _area.x - 144.0), maxf(160.0, _area.y - 144.0))
	# 页级浮窗居中；夹在屏幕内（窗口比屏幕大时贴左上）
	for id in panels.keys():
		var p: Control = panels[id]
		if not is_instance_valid(p):
			continue
		var sz := p.custom_minimum_size
		p.size = sz
		p.position = Vector2(maxf(8.0, (_area.x - sz.x) * 0.5), maxf(8.0, (_area.y - sz.y) * 0.5))


# ---------------------------------------------------------------------------
# 内部
# ---------------------------------------------------------------------------
func _view_def(id: String) -> Dictionary:
	for v in VIEWS:
		if str(v["id"]) == id:
			return v
	return {}


func _on_panel_closed() -> void:
	_update_dim()
	if not any_page_open():
		current_view = DEFAULT_VIEW
	view_changed.emit(current_view)


## 有页级浮窗打开时压暗底下（但不拦输入 —— 地图仍可拖动，保持"我在世界之上操作"的手感）
func _update_dim() -> void:
	dim_changed.emit(any_page_open())
