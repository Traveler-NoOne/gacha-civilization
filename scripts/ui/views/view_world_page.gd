extends Control
## 【世界】页：2D 六边形格子地图（类似文明 6），迷雾、资源点、据点、敌人、终极威胁。
## 对应设计文档「6世界」章节。

var map: HexMapView
var info_box: VBoxContainer
var legend_box: VBoxContainer
var stats_box: VBoxContainer
var tip_label: Label
var selected := ""

## v1.3.1：右侧「规划面板」的两个页签
const PLAN_TABS := [
	{"id": "info", "name": "信息页"},
	{"id": "plan", "name": "地块规划页"},
]
var plan_bar: HBoxContainer
var plan_pages: Dictionary = {}
var plan_tab := "info"
var build_box: VBoxContainer

# ---------------------------------------------------------------------------
# v1.5：单位操作（点击轮换 / 招募选地 / 移动 / 攻击）
# ---------------------------------------------------------------------------
## v1.8.2：简约地块信息小窗（点在非我方地块时，在鼠标位置弹出）
var tile_info_popup: PanelContainer = null
var tile_info_box: VBoxContainer = null

## v1.8.4：据点管理窗口（点我方领地块时在右侧打开）
var stronghold_panel: StrongholdPanel = null
var sel_uid := ""
var pick_mode := ""      # "" / "recruit" / "move" / "attack"
var pick_unit := ""
var pending_tile := ""   # 招募选地：已选中的目标地块
var unit_strip: PanelContainer
var unit_strip_row: HBoxContainer
var unit_panel: PanelContainer
var unit_panel_box: VBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	visibility_changed.connect(_on_visibility_changed)
	refresh()


func _build() -> void:
	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	# ---- 地图 ----
	var map_panel := UIKit.panel(UIKit.BG_SLOT, UIKit.LINE, 6)
	map_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(map_panel)
	var mv := VBoxContainer.new()
	map_panel.add_child(mv)

	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 6)
	mv.add_child(toolbar)
	toolbar.add_child(UIKit.title("大世界", 16))
	var b_center := UIKit.small("回到首都", 12)
	b_center.pressed.connect(func() -> void:
		map.center_on_axial(WorldGen.coord_of(str(GameState.state["capital"]))))
	toolbar.add_child(b_center)
	var b_fit := UIKit.small("重置缩放", 12)
	b_fit.pressed.connect(func() -> void: map.reset_view())
	toolbar.add_child(b_fit)
	var b_axis := UIKit.small("显示坐标", 12)
	b_axis.toggle_mode = true
	b_axis.toggled.connect(func(on: bool) -> void:
		map.show_axis = on
		map.queue_redraw())
	toolbar.add_child(b_axis)
	var b_expand := UIKit.small("扩建地图（发展系统功能）", 12)
	b_expand.pressed.connect(func() -> void:
		var added := WorldGen.expand_map(GameState.state, _rng(), 1)
		if added > 0:
			GameState.add_log("营地扩建：地图上限扩大，新增 %d 格。" % added, "world")
			GameState.toast.emit("地图已扩大，新增 %d 格" % added)
			GameState.state_changed.emit()
		else:
			GameState.toast.emit("已达地图大小上限"))
	toolbar.add_child(b_expand)

	tip_label = UIKit.dim("左键拖动平移　·　滚轮缩放　·　左键点击地块查看详情　·　中键回到首都", 11)
	mv.add_child(tip_label)

	map = HexMapView.new()
	# Control 默认 custom_minimum_size 是 (200,200)：必须显式压低，否则会把父容器撑爆
	map.custom_minimum_size = Vector2(120, 120)
	map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map.tile_clicked.connect(_on_tile_clicked)
	mv.add_child(map)

	# ---- 右侧：规划面板（信息页 / 地块规划页） ----
	var side := UIKit.panel()
	side.custom_minimum_size = Vector2(330, 0)
	root.add_child(side)
	var sv := VBoxContainer.new()
	side.add_child(sv)

	sv.add_child(UIKit.title("规划面板", 16))

	plan_bar = HBoxContainer.new()
	plan_bar.add_theme_constant_override("separation", 5)
	sv.add_child(plan_bar)
	for t in PLAN_TABS:
		var tid: String = t["id"]
		var b := UIKit.small(str(t["name"]), 13)
		b.custom_minimum_size = Vector2(0, 30)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void: switch_plan_tab(tid))
		plan_bar.add_child(b)

	var rule := ColorRect.new()
	rule.color = UIKit.LINE_SOFT
	rule.custom_minimum_size = Vector2(0, 1)
	sv.add_child(rule)

	var host := MarginContainer.new()
	host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sv.add_child(host)

	# 信息页：整个大世界的信息 + 图例
	plan_pages["info"] = VBoxContainer.new()
	host.add_child(plan_pages["info"])
	var info_page := plan_pages["info"] as VBoxContainer
	stats_box = VBoxContainer.new()
	stats_box.add_theme_constant_override("separation", 2)
	info_page.add_child(stats_box)
	info_page.add_child(UIKit.spacer(4))
	info_page.add_child(UIKit.title("图例", 14))
	legend_box = VBoxContainer.new()
	legend_box.add_theme_constant_override("separation", 2)
	info_page.add_child(legend_box)
	_build_legend()

	# 地块规划页：选中地块的信息 + 建筑选择与修建
	plan_pages["plan"] = VBoxContainer.new()
	host.add_child(plan_pages["plan"])
	var plan_page := plan_pages["plan"] as VBoxContainer
	info_box = VBoxContainer.new()
	info_box.add_theme_constant_override("separation", 3)
	build_box = VBoxContainer.new()
	build_box.add_theme_constant_override("separation", 4)
	var plan_inner := VBoxContainer.new()
	plan_inner.add_theme_constant_override("separation", 6)
	plan_inner.add_child(info_box)
	plan_inner.add_child(UIKit.title("修建建筑", 14))
	plan_inner.add_child(build_box)
	plan_page.add_child(UIKit.scroll(plan_inner))

	# ---- v1.5：底部单位立绘条（该格 ≥2 个公民单位时出现） ----
	unit_strip = PanelContainer.new()
	unit_strip.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	unit_strip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	unit_strip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	unit_strip.position = Vector2(0, -10)
	unit_strip.visible = false
	UIKit.apply_panel(unit_strip, Color(0.08, 0.08, 0.12, 0.94), UIKit.LINE, 6)
	add_child(unit_strip)
	unit_strip_row = HBoxContainer.new()
	unit_strip_row.add_theme_constant_override("separation", 6)
	unit_strip.add_child(unit_strip_row)

	# ---- v1.5：左下角单位操作窗（浮层，不放进 map —— map 有 clip_contents） ----
	unit_panel = PanelContainer.new()
	unit_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	unit_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	unit_panel.position = Vector2(14, -14)
	unit_panel.custom_minimum_size = Vector2(260, 0)
	unit_panel.visible = false
	UIKit.apply_panel(unit_panel, Color(0.07, 0.07, 0.11, 0.96), UIKit.GOLD, 6)
	add_child(unit_panel)
	unit_panel_box = VBoxContainer.new()
	unit_panel_box.add_theme_constant_override("separation", 4)
	unit_panel.add_child(unit_panel_box)

	switch_plan_tab("info")
	call_deferred("_init_map")


func _rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.randomize()
	return r


func _init_map() -> void:
	if is_instance_valid(map):
		map.center_on_axial(WorldGen.coord_of(str(GameState.state["capital"])))
		# 布局稳定后再居中一次，保证地图恰好落在可见区域中央
		await get_tree().process_frame
		await get_tree().process_frame
		map.center_on_axial(WorldGen.coord_of(str(GameState.state["capital"])))


func _build_legend() -> void:
	var rows := [
		["六边形描边：浅蓝 = 我方，红色 = 敌方", UIKit.TEXT_DIM],
		["★ 金色星形 = 首都", UIKit.GOLD],
		["地形底色：深绿=树林，褐=丘陵，深蓝=水域，灰绿=平原，灰褐=荒地", UIKit.TEXT_DIM],
		["资源点图标：木材 / 煤 / 铜 / 铁 / 原油 / 水晶（与顶部资源栏同款图标）", UIKit.TEXT_DIM],
		["小方块 = 建筑（黄=工业，红=军事，蓝=民用），上面的黄点表示已指派人力", UIKit.TEXT_DIM],
		["暗色六边形 = 未点亮的迷雾", UIKit.TEXT_DIM],
	]
	for r in rows:
		var l := UIKit.text_label(str(r[0]), 11, r[1])
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		legend_box.add_child(l)


# ---------------------------------------------------------------------------
# v1.3.1 规划面板页签 + 地块规划（修建）
# ---------------------------------------------------------------------------
func switch_plan_tab(id: String) -> void:
	plan_tab = id
	for k in plan_pages.keys():
		var p: Variant = plan_pages[k]
		if p is Control:
			(p as Control).visible = str(k) == id
	_refresh_plan_bar()
	refresh()


func _refresh_plan_bar() -> void:
	if not is_instance_valid(plan_bar):
		return
	var i := 0
	for child in plan_bar.get_children():
		if child is Button:
			var active: bool = str(PLAN_TABS[i]["id"]) == plan_tab
			UIKit.style_button(child as Button, active)
			(child as Button).add_theme_color_override("font_color",
				UIKit.GOLD if active else UIKit.TEXT)
			i += 1


## 地块规划页：选中地块的建筑修建列表
func _refresh_build_list() -> void:
	if not is_instance_valid(build_box):
		return
	for c in build_box.get_children():
		c.queue_free()
	if selected == "" or not GameState.state["tiles"].has(selected):
		build_box.add_child(UIKit.dim("先在地图上点选一块地块。", 11))
		return
	var t := GameState.tile_at(selected)
	if t.get("owner", "") != "player":
		build_box.add_child(UIKit.dim("只有我方领地才能修建。", 11))
		return
	build_box.add_child(UIKit.dim("已用土地 %.1f / %.1f" % [
		GameState.land_used(t), GameState.land_cap(t)], 11))
	for def in GameState.building_defs:
		# v1.6：未满足科技条件的建筑自动隐藏
		if def.required_tech != "" and not GameState.tech_unlocked(def.required_tech):
			continue
		_build_row(def, t)


func _build_row(def: BuildingDef, t: Dictionary) -> void:
	var count := GameState.tile_buildings_of(t, def.id).size()
	var row := PanelContainer.new()
	UIKit.apply_panel(row, UIKit.BG_PANEL_2, UIKit.LINE_SOFT, 5)
	build_box.add_child(row)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	row.add_child(h)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 1)
	h.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	v.add_child(head)
	head.add_child(UIKit.text_label(def.display_name, 13, UIKit.GOLD))
	head.add_child(UIKit.dim("占地 %.1f" % def.land, 10))
	# v1.6：点条目（或「详情」按钮）查看该建筑的完整效果，不打断修建 / 入队
	var info := Label.new()
	info.text = def.summary()
	info.visible = false
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_size_override("font_size", 10)
	info.add_theme_color_override("font_color", UIKit.TEXT_DIM)
	var b_info := UIKit.tiny("详情", 10)
	b_info.toggle_mode = true
	b_info.tooltip_text = "查看这个建筑的详细效果"
	b_info.toggled.connect(func(on: bool) -> void: info.visible = on)
	head.add_child(b_info)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed \
				and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			info.visible = not info.visible
			b_info.set_pressed_no_signal(info.visible))
	v.add_child(info)
	if count > 0:
		head.add_child(UIKit.text_label("已有 ×%d" % count, 11, UIKit.OK))
	if def.required_tech != "" and not GameState.tech_unlocked(def.required_tech):
		head.add_child(UIKit.text_label("需科技：%s" % GameState.tech_name(def.required_tech), 10, UIKit.BAD))
	var cost := def.upgrade_cost(1)
	var can_now := GameState.res("production") >= float(cost.get("production", 0.0))
	v.add_child(UIKit.dim("消耗 %s%s" % [GameState.cost_to_text(cost),
		"" if can_now else "（生产力不足，将进入队列）"], 10))
	var chk := GameState.can_build(t, def)
	var b := UIKit.small("修建" if can_now else "加入队列", 11)
	if not chk["ok"]:
		b.disabled = true
		b.tooltip_text = str(chk["why"])
	else:
		b.pressed.connect(func() -> void:
			var r: Dictionary = GameState.request_build(selected, def.id)
			if not r["ok"]:
				GameState.toast.emit(str(r["why"]))
			else:
				GameState.toast.emit("已加入规划队列" if bool(r.get("queued", false)) else "建造完成")
			GameState.state_changed.emit()
			refresh())
	h.add_child(b)


## v1.8.2：左键点击 = 三档分派（"更具体的目标优先"）
##   ① 选地/选目标模式 → 指目标
##   ② 点中棋子图标（最具体）→ 选中该单位
##   ③ 我方领地（没点到图标）→ 据点管理窗口（v1.8.4 接入；本段先只提示）
##   ④ 其它地块（没点到图标）→ 简约地块信息小窗（鼠标位置）
## 注：原来的"重复点同一格轮换内容"已取消 —— 地块不再可选中。
func _on_tile_clicked(key: String, uid: String, gpos: Vector2) -> void:
	# ① 选地 / 选目标模式优先（保持原行为）
	if pick_mode != "":
		_pick_tile(key)
		return
	# ② 点中了棋子图标 → 直接选中它
	if uid != "":
		selected = key
		sel_uid = uid
		_hide_tile_info()
		_refresh_after_select()
		return
	# 没点到棋子：先把"选中单位"清掉，再按地块归属分派
	selected = key
	sel_uid = ""
	# ③ 我方领地 → 打开右侧「据点管理窗口」
	if str(GameState.tile_at(key).get("owner", "")) == "player":
		_hide_tile_info()
		_refresh_after_select()
		_open_stronghold_panel()
		return
	# ④ 其它地块 → 简约地块信息小窗
	_refresh_after_select()
	_show_tile_info(key, gpos)


## 选中状态变化后要刷新的一串地方（原来在点击处理里抄了两遍，收成一处）
func _refresh_after_select() -> void:
	_refresh_info()
	_refresh_unit_strip()
	_refresh_unit_panel()
	_refresh_marks()
	_refresh_build_list()


# ---------------------------------------------------------------------------
# 刷新
# ---------------------------------------------------------------------------
func refresh() -> void:
	if not is_instance_valid(map):
		return
	# v1.5：从至宝点「招募」跳过来时，自动进入选地模式
	var pr := GameState.pending_recruit_uid()
	if pr != "" and pick_mode == "":
		pick_mode = "recruit"
		pick_unit = pr
		pending_tile = ""
	_refresh_stats()
	_refresh_marks()
	_refresh_info()
	_refresh_build_list()
	_refresh_unit_strip()
	_refresh_unit_panel()
	# v1.8.4：据点管理窗口开着的话，内容跟着状态走（否则会显示旧数据）
	if stronghold_panel != null and is_instance_valid(stronghold_panel) and stronghold_panel.visible:
		stronghold_panel.refresh()
	map.queue_redraw()


func _refresh_stats() -> void:
	var box := stats_box
	if box == null:
		return
	for c in box.get_children():
		c.queue_free()
	var owned := GameState.owned_tiles().size()
	var enemy := GameState.enemy_tiles().size()
	var free_n := GameState.free_tiles().size()
	var total: int = int((GameState.state["tiles"] as Dictionary).size())
	var radius := WorldGen.map_radius(GameState.state)
	box.add_child(UIKit.text_label("地图：半径 %d（直径 %d 格）／上限半径 %d" % [
		radius, radius * 2 + 1, Consts.MAP_MAX_RADIUS], 12, UIKit.TEXT))
	box.add_child(UIKit.text_label("我方 %d｜敌方 %d｜无主 %d｜总格 %d" % [
		owned, enemy, free_n, total], 12, UIKit.TEXT))
	box.add_child(UIKit.text_label("玩家战斗力 %.0f｜敌人战斗力 %.0f" % [
		GameState.player_force(), GameState.enemy_force()], 12, UIKit.TEXT))
	var st := GameState.stability()
	var stl := UIKit.text_label("稳定度 %.1f%%（世界泡下限 10%%）" % (st * 100.0), 12,
		UIKit.BAD if st < Consts.STABILITY_MIN_BLOCK else UIKit.OK)
	box.add_child(stl)
	box.add_child(UIKit.dim("扩张消耗 %d 生产力" % int(WorldGen.claim_cost(GameState.state)), 11))


func _refresh_marks() -> void:
	map.marks.clear()
	if pick_mode == "recruit":
		for k in GameState.deployable_keys():
			map.marks[k] = Color(0.55, 0.95, 0.65)
		if pending_tile != "":
			map.marks[pending_tile] = UIKit.GOLD
	elif pick_mode == "move":
		for k in _move_targets(pick_unit):
			map.marks[k] = Color(0.55, 0.95, 0.65)
	elif pick_mode == "attack":
		for k in _attack_targets(pick_unit):
			map.marks[k] = Color(0.95, 0.45, 0.40)
	else:
		for k in WorldGen.claimable_keys(GameState.state):
			map.marks[k] = Color(0.55, 0.95, 0.65)
	map.queue_redraw()


## v1.8.4：打开据点管理窗口。
## 关闭方式：窗口右上角的 ✕（**故意不"点别处就自动关"** —— 管理窗口不该因为你点了一下地图就消失）。
func _open_stronghold_panel() -> void:
	_ensure_stronghold_panel()
	stronghold_panel.visible = true
	_place_stronghold_panel()
	stronghold_panel.refresh()


## 贴着世界页右侧摆（上下留边距）。窗口尺寸固定，所以只要按页宽算一次。
func _place_stronghold_panel() -> void:
	if stronghold_panel == null or not is_instance_valid(stronghold_panel):
		return
	stronghold_panel.position = Vector2(maxf(0.0, size.x - 356.0), 56.0)


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
	stronghold_panel.size = Vector2(340, 520)
	add_child(stronghold_panel)
	stronghold_panel.visible = false


## 简约地块信息小窗：**懒创建**（第一次要用时才建），挂在本页上。
## 不放进 map —— map 开了 clip_contents，会把浮出格子的东西剪掉。
func _ensure_tile_info_popup() -> void:
	if tile_info_popup != null:
		return
	tile_info_popup = PanelContainer.new()
	tile_info_popup.set_anchors_preset(Control.PRESET_TOP_LEFT)
	tile_info_popup.custom_minimum_size = Vector2(210, 0)
	tile_info_popup.visible = false
	tile_info_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIKit.apply_panel(tile_info_popup, Color(0.07, 0.07, 0.11, 1.0), UIKit.LINE, 6)
	add_child(tile_info_popup)
	tile_info_box = VBoxContainer.new()
	tile_info_box.add_theme_constant_override("separation", 3)
	tile_info_popup.add_child(tile_info_box)
	# 容器的"最小尺寸"要到下一帧才会按新内容重算 —— 所以光在当前帧设一次不够，
	# 会留下一个过时的尺寸（实测 354px，而内容只需要 66px）。等它算好时自动校一次。
	tile_info_popup.minimum_size_changed.connect(_fit_tile_info_size)


## 在鼠标位置显示某一格的简约信息（取代"选中地块"）
func _show_tile_info(key: String, gpos: Vector2) -> void:
	_ensure_tile_info_popup()
	for c in tile_info_box.get_children():
		c.queue_free()
	var t := GameState.tile_at(key)
	tile_info_box.add_child(UIKit.title("地块 %s" % key, 13))
	var discovered := bool(t.get("discovered", false))
	if not discovered:
		tile_info_box.add_child(UIKit.dim("（未点亮：迷雾）", 11))
		tile_info_popup.visible = true
		_place_tile_info(gpos)
		return
	var owner_txt := "无主"
	var owner_col := UIKit.TEXT_DIM
	match str(t.get("owner", "")):
		"player":
			owner_txt = "我方领地"
			owner_col = Color(0.55, 0.85, 1.0)
		"enemy":
			owner_txt = "敌方"
			owner_col = Color(0.95, 0.45, 0.45)
	tile_info_box.add_child(UIKit.text_label("势力：%s" % owner_txt, 11, owner_col))
	# 地块明细（单格版）—— 与据点详情里那行同格式，避免两处口径不同
	var nm := str(t.get("name", ""))
	if nm != "":
		tile_info_box.add_child(UIKit.text_label("名称：%s" % nm, 11, UIKit.TEXT))
	var bcount := (t.get("buildings", []) as Array).size()
	var line := "地形 %s　土地 %.1f/%.1f　建筑 %d" % [
		Consts.terrain_name(str(t.get("terrain", ""))),
		GameState.land_used(t), GameState.land_cap(t), bcount]
	var l := UIKit.dim(line, 11)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tile_info_box.add_child(l)
	var res := str(t.get("resource", ""))
	if res != "":
		tile_info_box.add_child(UIKit.text_label("资源点：%s" % Consts.res_name(res), 11, UIKit.OK))
	tile_info_popup.visible = true
	_place_tile_info(gpos)


## 把窗口放到鼠标旁边；贴边时往回收，避免跑出屏幕
func _place_tile_info(gpos: Vector2) -> void:
	_fit_tile_info_size()
	var sz := tile_info_popup.size
	var vp := get_viewport_rect().size
	tile_info_popup.global_position = Vector2(
		clampf(gpos.x + 14.0, 0.0, maxf(0.0, vp.x - sz.x)),
		clampf(gpos.y + 10.0, 0.0, maxf(0.0, vp.y - sz.y)))


## 让面板收缩到刚好包住内容。
## { 面板是自由摆放的（没进容器），尺寸不会自动跟着内容缩；而"最小尺寸"又要到下一帧才重算 }
## → 所以既要在这里主动设一次，也要靠 minimum_size_changed 在算好后补一次。
func _fit_tile_info_size() -> void:
	if tile_info_popup == null:
		return
	tile_info_popup.size = tile_info_popup.get_combined_minimum_size()


func _hide_tile_info() -> void:
	if tile_info_popup != null:
		tile_info_popup.visible = false


func _refresh_info() -> void:
	for c in info_box.get_children():
		c.queue_free()
	if selected == "" or not GameState.state["tiles"].has(selected):
		info_box.add_child(UIKit.dim("点击地图上的地块查看详情。\n绿色高亮 = 可以占领的地块。"))
		return
	var t := GameState.tile_at(selected)
	var c := WorldGen.coord_of(selected)
	var v := UIKit.vbox(3)
	info_box.add_child(v)

	v.add_child(UIKit.text_label("坐标 %s（轴向 q=%d, r=%d）" % [selected, c.x, c.y], 13, UIKit.GOLD))
	v.add_child(UIKit.dim("地形：%s" % Consts.terrain_name(str(t.get("terrain", ""))), 12))
	var owner_text := "无主"
	var owner_col := UIKit.TEXT_DIM
	match str(t.get("owner", "")):
		"player":
			owner_text = "我方领地"
			owner_col = Color(0.55, 0.85, 1.0)
		"enemy":
			owner_text = "敌方（%s）" % str(t.get("name", "敌人"))
			owner_col = UIKit.BAD
	v.add_child(UIKit.text_label("势力：%s" % owner_text, 12, owner_col))
	v.add_child(UIKit.dim("迷雾：%s" % ("已点亮" if t.get("discovered", false) else "未点亮"), 12))

	if str(t.get("resource", "")) != "":
		v.add_child(UIKit.text_label("资源点：%s　%.1f%s" % [
			Consts.res_name(str(t["resource"])), float(t.get("amount", 0.0)),
			"（可再生）" if t.has("node_tier") else ""], 12, Color(0.6, 0.9, 0.6)))

	if str(t.get("owner", "")) == "enemy":
		v.add_child(UIKit.text_label("敌方战力：%.0f" % float(t.get("force", 0.0)), 12, UIKit.BAD))
		v.add_child(UIKit.dim("清剿需要战力：%.0f（当前 %.0f）" % [
			WorldGen.clear_requirement(t), GameState.player_force()], 11))
		if t.get("danger", false):
			v.add_child(UIKit.dim("危险据点：每个周期都会生成游荡敌人。", 11))
		if t.get("threat", false):
			var timer := int(t.get("threat_timer", 0))
			v.add_child(UIKit.text_label("终极威胁：%s" % (
				"%d 个周期后直扑首都" % timer if timer > 0 else "已抵达，正在攻击首都"), 11, UIKit.BAD))
		var chk := WorldGen.can_clear(GameState.state, selected)
		var cb := UIKit.normal("派兵清剿此地块", 13)
		UIKit.style_button(cb, true)
		if not chk["ok"]:
			cb.disabled = true
			cb.tooltip_text = str(chk["why"])
		cb.pressed.connect(func() -> void:
			var r: Dictionary = WorldGen.clear_tile(GameState.state, selected, _rng())
			if not r["ok"]:
				GameState.toast.emit(str(r["why"]))
			else:
				GameState.toast.emit("清剿成功（%s）" % str(r["kind"]))
			GameState.state_changed.emit()
			refresh())
		v.add_child(cb)

	v.add_child(UIKit.text_label("已用土地 %.1f / %.1f" % [
		GameState.land_used(t), GameState.land_cap(t)], 12, UIKit.TEXT))
	var bs: Array = t.get("buildings", [])
	if bs.is_empty():
		v.add_child(UIKit.dim("暂无建筑。在下方「修建建筑」里选择。", 11))
	else:
		v.add_child(UIKit.title("已建建筑", 13))
		for b in bs:
			var def := GameState.find_building(str(b.get("id", "")))
			var nm: String = def.display_name if def != null else str(b.get("id", ""))
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 4)
			v.add_child(row)
			var l := UIKit.dim("%s Lv.%d（占地 %.1f｜人力 %d）" % [nm, int(b.get("level", 1)),
				(def.land if def != null else 0.0), int(b.get("workers", 0))], 11)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			row.add_child(l)
			if def != null and int(b.get("level", 1)) < def.level_cap():
				var ub := UIKit.tiny("升级", 10)
				ub.tooltip_text = "消耗 " + def.cost_text(int(b.get("level", 1)) + 1)
				ub.pressed.connect(func() -> void:
					var r2: Dictionary = GameState.request_upgrade_by_bid(selected, str(b.get("bid", "")))
					if not r2["ok"]:
						GameState.toast.emit(str(r2["why"]))
					else:
						GameState.toast.emit("已加入规划队列" if bool(r2.get("queued", false)) else "升级完成")
					GameState.state_changed.emit()
					refresh())
				row.add_child(ub)

	# v1.6.1：驻军功能已搬到「世界 → 单位操作窗」里，作为「攻击 / 移动」之后的第三个按钮

	var cks := WorldGen.claimable_keys(GameState.state)
	if cks.has(selected):
		v.add_child(UIKit.spacer(4))
		var btn := UIKit.normal("占领此地块（%d 行政点数）" % int(WorldGen.claim_cost(GameState.state)), 13)
		btn.pressed.connect(func() -> void:
			var r: Dictionary = WorldGen.claim(GameState.state, selected)
			if not r["ok"]:
				GameState.toast.emit(str(r["why"]))
			GameState.state_changed.emit()
			refresh())
		v.add_child(btn)


func on_cycle_finished(_rep: Dictionary) -> void:
	refresh()


# ===========================================================================
# v1.5：招募选地 / 移动 / 攻击 / 单位操作窗
# ===========================================================================
## v1.7：直接复用 GameState 的同一份规则（此前这里自己判一遍、且漏了中继格检查）
func _move_targets(uid: String) -> Array[String]:
	return GameState.move_candidates(uid)

func _attack_targets(uid: String) -> Array[String]:
	var out: Array[String] = []
	var u := GameState.unit_by_uid(uid)
	if u.is_empty() or int(u.get("move_left", 0)) <= 0:
		return out
	var from := str(u.get("tile", ""))
	if from == "":
		return out
	var a := WorldGen.coord_of(from)
	for d in Hex.DIRECTIONS:
		var k := WorldGen.key_of(a + d)
		var t := GameState.tile_at(k)
		if not t.is_empty() and t.get("owner", "") == "enemy":
			out.append(k)
	return out


func _pick_tile(key: String) -> void:
	if pick_mode == "recruit":
		if not GameState.deployable_keys().has(key):
			GameState.toast.emit("该地块不可部署（已驻满或掌控力不足），请另选")
			return
		pending_tile = key
		_refresh_marks()
		_refresh_unit_panel()
		return
	if pick_mode == "move":
		var r := GameState.move_unit(pick_unit, key)
		GameState.toast.emit("移动完成" if bool(r["ok"]) else str(r["why"]))
		_end_pick()
		return
	if pick_mode == "attack":
		var r2 := GameState.unit_attack(pick_unit, key)
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
	GameState.cancel_recruit()
	_end_pick()


## 招募确认：唯一的状态转换点
func _confirm_recruit() -> void:
	var uid := GameState.pending_recruit_uid()
	if uid == "":
		GameState.toast.emit("没有待招募的客人")
		return
	if pending_tile == "":
		GameState.toast.emit("请先点选一块高亮的领地进行部署")
		return
	var r := GameState.confirm_recruit(uid, pending_tile)
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
		for u in GameState.units_on_tile(selected):
			if GameState.is_citizen(u):
				units.append(u)
	unit_strip.visible = units.size() >= 2
	if not unit_strip.visible:
		return
	unit_strip_row.add_child(UIKit.dim("该地块 %d 个单位：" % units.size(), 11))
	for u in units:
		# v1.6.1：立绘窗口 —— 每个单位一个「立绘 + 名字」
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 3)
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
		var gu := GameState.unit_by_uid(pick_unit)
		unit_panel_box.add_child(UIKit.title("招募 · 部署", 13))
		var info := UIKit.dim("客人：%s\n点选绿色高亮的领地，然后确认。" % str(gu.get("name", "?")), 11)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		unit_panel_box.add_child(info)
		unit_panel_box.add_child(UIKit.text_label(
			"目标：%s" % ("（未选）" if pending_tile == "" else pending_tile), 11, UIKit.GOLD))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
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
	var u := GameState.unit_by_uid(sel_uid)
	if sel_uid == "" or u.is_empty():
		unit_panel.visible = false
		return
	unit_panel.visible = true
	var eff := UnitDB.effective_attr(u)
	var prof := str(u.get("profession", UnitDB.MELEE))
	var garrisoned := bool(u.get("garrisoned", false))
	# v1.6.1：左边必须有单位立绘（现在还是几何占位，但也要显示）
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	unit_panel_box.add_child(head)
	var pic := UIKit.unit_art(u, "icon", Vector2(60, 60))
	head.add_child(pic)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(col)
	col.add_child(UIKit.title(str(u["name"]), 13))
	col.add_child(UIKit.dim("%s·%s%s" % [
		UnitDB.rank_name(str(u.get("rank", ""))), UnitDB.profession_name(prof),
		"　［驻军中］" if garrisoned else ""], 10))
	col.add_child(UIKit.text_label("攻击 %.0f　血量 %d / %d　移动力 %d / %d" % [
		float(eff.get("atk", 0.0)), int(u.get("hp", 0)), UnitDB.max_hp(u),
		int(u.get("move_left", 0)), GameState.max_move(u)], 11, UIKit.TEXT))
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 6)
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
		var r := GameState.toggle_garrison(sel_uid)
		if not bool(r["ok"]):
			GameState.toast.emit(str(r["why"]))
		_refresh_marks()
		_refresh_unit_panel())
	row2.add_child(bg)
	col.add_child(row2)


## 离开世界页 = 放弃招募（客人保持客人，不做任何转换）
func _on_visibility_changed() -> void:
	if not visible and pick_mode == "recruit":
		GameState.cancel_recruit()
		_end_pick()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or pick_mode == "":
		return
	if event is InputEventKey and (event as InputEventKey).pressed \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		if pick_mode == "recruit":
			_cancel_recruit()
		else:
			_end_pick()
		get_viewport().set_input_as_handled()