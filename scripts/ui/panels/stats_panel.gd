class_name StatsPanel
extends PanelContainer
## v1.8.11：统计面板。
##
## 定位：**"能统计、但一时不知道该放哪"的东西的收容所。**
## 由来：v1.8.7 删掉「管理」入口时，中控区「军队」页的单位清单（= 部队统计）没有归宿。
## 它属于**整个世界**的口径（有多少单位、多少编队），不隶属任何据点，
## 所以不能塞进据点管理窗口（那个窗口将来要按据点各开一份）。
##
## 打开方式：资源栏中间的「统计」按钮 → 在它下面展开。
## 左侧一列切换统计类型，右侧是内容。
##
## ⚠️ 数字口径**必须复用已有来源**（GameState 的现成函数 / 资源表），
## 不许在这里另写一套循环 —— 这是本项目反复咬过的坑（两处口径迟早会对不上）。

signal closed

## 统计类型。想加"能数但没家"的东西，往这里加一条 + 写一个 _fill_xxx。
const TYPES := [
	{"id": "res", "name": "资源"},
	{"id": "unit", "name": "单位"},
	{"id": "tile", "name": "地块"},
	{"id": "land", "name": "领地"},
]

## 当前类型。**默认看经济**（用户定的：统计最基础的就是看资源）。
var tab := "res"

var type_bar: VBoxContainer
var content_box: VBoxContainer


func _init() -> void:
	custom_minimum_size = Vector2(UI.px(360), UI.px(0))
	UIKit.apply_panel(self, Color(0.08, 0.08, 0.12, 0.98), UIKit.GOLD, 6)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UI.fs(6))
	add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UI.fs(8))
	col.add_child(head)
	head.add_child(UIKit.title("统计", 14))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var close := UIKit.tiny("✕", 12, true)
	close.tooltip_text = "关闭（Esc）"
	close.pressed.connect(func() -> void: _close())
	head.add_child(close)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", UI.fs(8))
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)

	# 左：类型切换（竖排一列）
	type_bar = VBoxContainer.new()
	type_bar.add_theme_constant_override("separation", UI.fs(4))
	body.add_child(type_bar)
	for t in TYPES:
		var tid := str(t["id"])
		var b := UIKit.small(str(t["name"]), 12)
		b.custom_minimum_size = Vector2(UI.px(64), UI.px(28))
		b.pressed.connect(func() -> void:
			tab = tid
			refresh())
		type_bar.add_child(b)

	# 右：内容
	content_box = VBoxContainer.new()
	content_box.add_theme_constant_override("separation", UI.fs(3))
	content_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sc := UIKit.scroll(content_box)
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(sc)
	refresh()


func _close() -> void:
	visible = false
	closed.emit()


func refresh() -> void:
	if not is_instance_valid(content_box):
		return
	for c in content_box.get_children():
		c.queue_free()
	# 类型按钮的高亮
	var i := 0
	for t in TYPES:
		var b: Button = type_bar.get_child(i)
		UIKit.style_button(b, str(t["id"]) == tab)
		i += 1
	match tab:
		"unit":
			_fill_units()
		"tile":
			_fill_tiles()
		"land":
			_fill_land()
		_:
			_fill_resources()


## 一行「名称 …… 值」
func _row(label_text: String, value_text: String, col := UIKit.TEXT) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", UI.fs(8))
	var l := UIKit.text_label(label_text, 11, UIKit.TEXT_DIM)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	h.add_child(UIKit.text_label(value_text, 12, col))
	return h


func _section(title_text: String) -> void:
	content_box.add_child(UIKit.spacer(2))
	content_box.add_child(UIKit.title(title_text, 12))


# ---------------------------------------------------------------------------
# 资源（默认）
# ---------------------------------------------------------------------------
func _fill_resources() -> void:
	content_box.add_child(UIKit.dim("当前拥有 / 上限，以及每周期净收支（口径与资源栏点击后的收支窗一致）", 10))
	for group in [
		["抽象资源", Consts.RES_ABSTRACT],
		["具体资源", Consts.RES_CONCRETE],
	]:
		_section(str(group[0]))
		for item in (group[1] as Array):
			var key := str(item[0])
			var label_text := str(item[1])
			if key == "pop":
				# 人力不是产出资源：受住房上限约束（和资源栏的写法保持一致）
				content_box.add_child(_row(label_text, "%d / %d" % [
					int(GameState.state["pop_total"]), int(Derived.housing_capacity(GameState.state))]))
				content_box.add_child(_row("　已指派 / 空闲", "%d / %d" % [
					int(Derived.assigned_pop(GameState.state)), int(Derived.free_pop(GameState.state))]))
				continue
			var cap := Res.storage_cap(GameState.state, key)
			var net := 0.0
			for e in (Admin.resource_breakdown(GameState.state, key)["income"] as Array):
				net += float(e["amount"])
			for e2 in (Admin.resource_breakdown(GameState.state, key)["upkeep"] as Array):
				net += float(e2["amount"])
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", UI.fs(6))
			var l := UIKit.text_label(label_text, 11, UIKit.TEXT_DIM)
			l.custom_minimum_size = Vector2(UI.px(74), UI.px(0))
			h.add_child(l)
			h.add_child(UIKit.text_label(("%s / %s" % [UIKit.fmt_num(Res.amount(GameState.state, key)), UIKit.fmt_num(cap)]) if cap >= 0.0 else UIKit.fmt_num(Res.amount(GameState.state, key)), 12, UIKit.TEXT))
			var sp := Control.new()
			sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(sp)
			h.add_child(UIKit.text_label("%+.1f/周期" % net, 11, UIKit.OK if net >= 0.0 else UIKit.BAD))
			content_box.add_child(h)


# ---------------------------------------------------------------------------
# 单位（含编队）
# ---------------------------------------------------------------------------
func _fill_units() -> void:
	var units: Array = GameState.state["units"]
	_section("单位")
	content_box.add_child(_row("总数", str(units.size())))
	# 按状态分
	var n_guest := 0
	var n_citizen := 0
	for u in units:
		if bool((u as Dictionary).get("guest", false)):
			n_guest += 1
		else:
			n_citizen += 1
	content_box.add_child(_row("客人 / 公民", "%d / %d" % [n_guest, n_citizen]))
	content_box.add_child(_row("空闲 / 已指派人力", "%d / %d" % [int(Derived.free_pop(GameState.state)), int(Derived.assigned_pop(GameState.state))]))
	# 按职业
	_section("按职业")
	var by_prof := {}
	for u2 in units:
		var p := str((u2 as Dictionary).get("profession", ""))
		by_prof[p] = int(by_prof.get(p, 0)) + 1
	for p2 in UnitDB.PROFESSION_ORDER:
		content_box.add_child(_row(UnitDB.profession_name(str(p2)), str(int(by_prof.get(str(p2), 0)))))
	# 按据点所在（本作只有首都，但按"地块是否有我方据点"数）
	_section("编队")
	var teams: Array = GameState.state.get("teams", [])
	content_box.add_child(_row("编队数", str(teams.size())))
	var i := 0
	for t2 in teams:
		var members: Array = (t2 as Dictionary).get("members", [])
		content_box.add_child(_row("%s" % str((t2 as Dictionary).get("name", "队伍 %d" % (i + 1))),
			"%d / %d 人" % [members.size(), UnitDB.UNITS_PER_TEAM],
			UIKit.OK if not members.is_empty() else UIKit.TEXT_DIM))
		i += 1


# ---------------------------------------------------------------------------
# 地块
# ---------------------------------------------------------------------------
func _fill_tiles() -> void:
	var tiles: Dictionary = GameState.state["tiles"]
	_section("总数")
	content_box.add_child(_row("地图格数", str(tiles.size())))
	_section("按地形")
	var by_terrain := {}
	for k in tiles.keys():
		var tr := str(TileManager.tile_at(GameState.state, str(k)).get("terrain", "?"))
		by_terrain[tr] = int(by_terrain.get(tr, 0)) + 1
	for tr2 in by_terrain.keys():
		content_box.add_child(_row(str(tr2), str(int(by_terrain[tr2]))))
	_section("资源点")
	var by_res := {}
	for k2 in tiles.keys():
		var r := str(TileManager.tile_at(GameState.state, str(k2)).get("resource", ""))
		if r != "":
			by_res[r] = int(by_res.get(r, 0)) + 1
	if by_res.is_empty():
		content_box.add_child(UIKit.dim("（暂无）"))
	for r2 in by_res.keys():
		content_box.add_child(_row(Consts.res_name(str(r2)), str(int(by_res[r2]))))


# ---------------------------------------------------------------------------
# 领地
# ---------------------------------------------------------------------------
func _fill_land() -> void:
	_section("领地口径")
	content_box.add_child(_row("我方领地", str(TileManager.owned_tiles(GameState.state).size()), UIKit.OK))
	content_box.add_child(_row("敌方据点", str(TileManager.enemy_tiles(GameState.state).size()), UIKit.BAD))
	content_box.add_child(_row("无主地块", str(TileManager.free_tiles(GameState.state).size())))
	content_box.add_child(_row("扩张消耗", "%d 行政点数" % int(TileManager.claim_cost(GameState.state))))
	_section("可扩张的格数")
	content_box.add_child(_row("与领地相邻的无主格", str(TileManager.claimable_keys(GameState.state).size())))
	_section("据点")
	content_box.add_child(_row("据点数量", str((GameState.state.get("strongholds", []) as Array).size())))
	content_box.add_child(_row("首都", str(GameState.state.get("capital", ""))))
