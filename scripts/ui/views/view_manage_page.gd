extends Control
## 【管理】页：据点详情（人力管理 + 规划队列）＋ 中控区（只剩军队；v1.8.6 起科技树搬到左上角浮窗）。
## 对应设计文档「1管理」章节。
##
## v1.2 减负：删掉「持有资源总览」与「部落概况」，领地列表合并进详情区。
## v1.3：右侧「指挥」区改名「中控区」，改为左中右页签切换。
## v1.4：删除「指挥」页签（扩张/清剿改到世界页做，理由见更新指导）；
##       据点详情补回「人力管理」（放在规划队列左边，只列已建建筑）。

## 中控区的页签（v1.4：删除了「指挥」）
const CTRL_TABS := [
	{"id": "army", "name": "军队"},
]

var yield_label: Label
var stronghold_title: Button
var tile_info: VBoxContainer
var queue_list: VBoxContainer
var labor_list: VBoxContainer
var selected_stronghold: String = "sh_capital"
## 中控区当前的页签
var ctrl_tab := "army"
var ctrl_bar: HBoxContainer
var ctrl_pages: Dictionary = {}
## 中控区各页签里需要动态刷新的容器（直接持有引用，
## 因为 find_child 遍历不到被隐藏的页签，会拿不到节点）
var unit_box: VBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)
	
	# 新增：左列，把「顶部 stats 行」和「地块详情」装在一起
	var left_col := VBoxContainer.new()
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_col.add_theme_constant_override("separation", 6)
	root.add_child(left_col)

	# ---------- 顶部：每周期收支 + 制度提示 ----------
	# v1.2 减负：删掉了「持有资源总览」（顶部资源栏已经显示）
	#            也删掉了「部落概况」里的幸福值 / 文化率 / 稳定度（顶部同样已显示）
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 6)
	left_col.add_child(stats)

	var flow := _panel("每周期收支（估算）", 460.0)
	yield_label = _kv(flow, "产出")
	stats.add_child(flow["panel"])

	var rules := _panel("制度与提示", 0.0)
	var rules_text := RichTextLabel.new()
	rules_text.bbcode_enabled = true
	rules_text.fit_content = true
	rules_text.scroll_active = false
	rules_text.custom_minimum_size = Vector2(300, 0)
	rules_text.text = "[color=#c9cbd6]幸福值 = 基础 50 + 建筑加成 − 民怨。文化率由教育/文化建筑提升，作为凝聚力结算的倍率。\n稳定度低于 [color=#eb6166]10%[/color] 或 无主地块少于 [color=#eb6166]10[/color] 个时无法进行世界泡操作。\n幸福程度给予凝聚力的数值，文化率给予倍率。\n幸福值 / 文化率 / 稳定度的实时数值请看顶部资源栏。[/color]"
	rules_text.add_theme_font_size_override("normal_font_size", 12)
	rules["body"].add_child(rules_text)
	rules["panel"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats.add_child(rules["panel"])

	# 中：据点详情 + 规划队列
	# v1.3.1：「地块详情」改名为「据点详情」，建筑功能迁到「世界 → 规划面板 → 地块规划页」，
	#         此处取而代之的是「规划队列」。
	var mid := UIKit.panel()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_col.add_child(mid)
	var mv := VBoxContainer.new()
	mid.add_child(mv)

	# 据点标题：下拉切换要管理的据点（本作仅首都，为多据点预留）
	stronghold_title = Button.new()
	stronghold_title.custom_minimum_size = Vector2(0, 34)
	stronghold_title.focus_mode = Control.FOCUS_NONE
	stronghold_title.alignment = HORIZONTAL_ALIGNMENT_LEFT
	stronghold_title.add_theme_font_size_override("font_size", 15)
	UIKit.style_button(stronghold_title, true)
	stronghold_title.pressed.connect(_open_stronghold_picker)
	mv.add_child(stronghold_title)
	mv.add_child(UIKit.dim("据点详情：名称 / 地块 / 可用土地一览。修建与升级请到「世界 → 规划面板 → 地块规划页」。"))

	# 用 Label 逐行显示（RichTextLabel 在固定高度下会出现行重叠）
	var tile_scroll := ScrollContainer.new()
	tile_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tile_scroll.custom_minimum_size = Vector2(0, 150)
	tile_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mv.add_child(tile_scroll)
	tile_info = VBoxContainer.new()
	tile_info.add_theme_constant_override("separation", 1)
	tile_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile_scroll.add_child(tile_info)

	mv.add_child(UIKit.spacer(4))
	var bottom_row := HBoxContainer.new()
	bottom_row.add_theme_constant_override("separation", 6)
	bottom_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mv.add_child(bottom_row)

	# 左：人力管理（v1.4，只列已建建筑）
	var labor_col := VBoxContainer.new()
	labor_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	labor_col.add_theme_constant_override("separation", 3)
	bottom_row.add_child(labor_col)
	labor_col.add_child(UIKit.title("人力管理", 14))
	labor_col.add_child(UIKit.dim("只列出已修建的建筑；点 −/＋ 投入人力。"))
	labor_list = VBoxContainer.new()
	labor_list.add_theme_constant_override("separation", 3)
	var labor_scroll := UIKit.scroll(labor_list)
	labor_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	labor_col.add_child(labor_scroll)

	# 右：规划队列
	var queue_col := VBoxContainer.new()
	queue_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	queue_col.add_theme_constant_override("separation", 3)
	bottom_row.add_child(queue_col)
	queue_col.add_child(UIKit.title("规划队列", 14))
	queue_col.add_child(UIKit.dim("生产力不足的建造会排在这里。"))
	queue_list = VBoxContainer.new()
	queue_list.add_theme_constant_override("separation", 4)
	var queue_scroll := UIKit.scroll(queue_list)
	queue_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	queue_col.add_child(queue_scroll)

	# 右：扩张 / 军事 / 科技
	var right := UIKit.panel()
	right.custom_minimum_size = Vector2(330, 0)
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 5)
	right.add_child(rv)

	# v1.3：原来的「指挥」区改名为「中控区」，
	# 指挥已删除（v1.4）；科技树已搬到左上角浮窗（v1.8.6），这里只剩军队。
	# 保留「按钮切换」的结构，以后加页签直接往 CTRL_TABS 里加即可。
	rv.add_child(UIKit.title("中控区", 16))

	ctrl_bar = HBoxContainer.new()
	ctrl_bar.add_theme_constant_override("separation", 5)
	rv.add_child(ctrl_bar)
	for t in CTRL_TABS:
		var tid: String = t["id"]
		var b := UIKit.small(str(t["name"]), 13)
		b.custom_minimum_size = Vector2(0, 32)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void: switch_ctrl_tab(tid))
		ctrl_bar.add_child(b)

	var ctrl_rule := ColorRect.new()
	ctrl_rule.color = UIKit.LINE_SOFT
	ctrl_rule.custom_minimum_size = Vector2(0, 1)
	rv.add_child(ctrl_rule)

	# 中控区内容宿主：一次只显示一个页签
	var ctrl_host := MarginContainer.new()
	ctrl_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rv.add_child(ctrl_host)

	# ---------- 页签 1：军队 ----------
	ctrl_pages["army"] = VBoxContainer.new()
	(ctrl_pages["army"] as VBoxContainer).add_theme_constant_override("separation", 5)
	ctrl_host.add_child(ctrl_pages["army"])
	var av := ctrl_pages["army"] as VBoxContainer

	var unit_info := VBoxContainer.new()
	unit_info.name = "UnitInfo"
	unit_info.add_theme_constant_override("separation", 2)
	av.add_child(unit_info)
	unit_box = unit_info

	var recruit_btn := UIKit.small("招募募集兵（选择职业）", 12)
	recruit_btn.pressed.connect(_open_recruit)
	av.add_child(recruit_btn)

	var team_btn := UIKit.small("查看队伍编成", 12)
	team_btn.pressed.connect(_open_teams)
	av.add_child(team_btn)

	var army_tip := UIKit.dim("提示：单位的派驻与撤回在「世界」页点击地块，或「至宝 → 角色 → 编队」里操作。")
	army_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	av.add_child(army_tip)


	switch_ctrl_tab("army")
	refresh()


# ---------------------------------------------------------------------------
# v1.3 中控区页签
# ---------------------------------------------------------------------------
func switch_ctrl_tab(id: String) -> void:
	ctrl_tab = id
	for k in ctrl_pages.keys():
		var page: Variant = ctrl_pages[k]
		if page is Control:
			(page as Control).visible = str(k) == id
	_refresh_ctrl_bar()
	# 切到某个页签时刷新它自己的内容
	match id:
		"army": _refresh_units()
		_: pass


func _refresh_ctrl_bar() -> void:
	if not is_instance_valid(ctrl_bar):
		return
	var i := 0
	for child in ctrl_bar.get_children():
		if child is Button:
			var active: bool = str(CTRL_TABS[i]["id"]) == ctrl_tab
			UIKit.style_button(child as Button, active)
			(child as Button).add_theme_color_override("font_color",
				UIKit.GOLD if active else UIKit.TEXT)
			i += 1


# ---------------------------------------------------------------------------
# 小工具
# ---------------------------------------------------------------------------
func _panel(title: String, min_w: float) -> Dictionary:
	var p := UIKit.panel()
	if min_w > 0.0:
		p.custom_minimum_size = Vector2(min_w, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	p.add_child(v)
	v.add_child(UIKit.title(title, 14))
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 2)
	v.add_child(body)
	return {"panel": p, "body": body}


func _kv(d: Dictionary, label_text: String) -> Label:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var l := UIKit.text_label(label_text, 13, UIKit.TEXT_DIM)
	l.custom_minimum_size = Vector2(96, 0)
	h.add_child(l)
	var v := UIKit.text_label("--", 14, UIKit.TEXT)
	h.add_child(v)
	(d["body"] as VBoxContainer).add_child(h)
	return v


# ---------------------------------------------------------------------------
# 刷新
# ---------------------------------------------------------------------------
func refresh() -> void:
	if not is_instance_valid(stronghold_title):
		return
	# v1.2：幸福值 / 文化率 / 稳定度 与 持有资源 都只在顶部资源栏显示，这里不再重复
	# v1.7：与顶部资源栏悬浮窗同源（此前这里自算一套，与真实结算 / 悬浮窗都对不上）
	var inc := GameState.income_estimate()
	var parts: Array[String] = []
	for k in inc.keys():
		parts.append("%s %+.1f" % [Consts.res_name(k), float(inc[k])])
	yield_label.text = "  ".join(parts) if not parts.is_empty() else "暂无产出（先建建筑并指派人力）"
	yield_label.add_theme_color_override("font_color", UIKit.TEXT_DIM)
	yield_label.add_theme_font_size_override("font_size", 12)

	_ensure_stronghold()
	_refresh_stronghold_title()
	_refresh_stronghold_detail()
	_refresh_labor()
	_refresh_queue()
	# v1.3：中控区只刷新当前页签，避免无谓的重建（三个页签的内容互不影响）
	_refresh_ctrl_bar()
	match ctrl_tab:
		"army": _refresh_units()
		_: pass


## 保证 selected_stronghold 指向一个存在的据点
func _ensure_stronghold() -> void:
	var all := GameState.strongholds()
	if all.is_empty():
		selected_stronghold = ""
		return
	for s in all:
		if str(s.get("id", "")) == selected_stronghold:
			return
	selected_stronghold = str((all[0] as Dictionary).get("id", ""))


func _refresh_stronghold_title() -> void:
	if selected_stronghold == "":
		stronghold_title.text = "据点详情（还没有据点）  ▾"
		return
	var sh := GameState.stronghold_by_id(selected_stronghold)
	var nm := str(sh.get("name", selected_stronghold))
	var n := GameState.stronghold_tiles(selected_stronghold).size()
	stronghold_title.text = "%s　（地块 %d）　▾" % [nm, n]


## v1.3.1：点击据点名称弹出下拉，选择要管理的据点（本作仅首都，为多据点预留）
func _open_stronghold_picker() -> void:
	var gs := UIKit.game_screen_of(self)
	if gs == null:
		return
	var v := UIKit.vbox(4)
	v.add_child(UIKit.text_label("选择要管理的据点", 15, UIKit.GOLD))
	v.add_child(UIKit.dim("本作暂只有首都一个据点；多据点功能已预留此入口。"))
	var all := GameState.strongholds()
	if all.is_empty():
		v.add_child(UIKit.dim("你还没有任何据点。"))
	else:
		for s in all:
			var sid := str(s.get("id", ""))
			var nm := str(s.get("name", sid))
			var n := GameState.stronghold_tiles(sid).size()
			var label := "%s　地块 %d　掌控力 %.0f%%%s" % [
				nm, n, GameState.control_of(s) * 100.0,
				"　◀ 当前" if sid == selected_stronghold else ""]
			var b := UIKit.small(label, 12)
			if sid == selected_stronghold:
				UIKit.style_button(b, true)
			b.pressed.connect(func() -> void:
				selected_stronghold = sid
				gs.close_dialog()
				refresh())
			v.add_child(b)
	var sc := UIKit.scroll(v)
	sc.custom_minimum_size = Vector2(0, 300)
	var d := UIKit.dialog("选择据点", 520.0)
	d.set_content(sc)
	gs.open_dialog(d)


func _refresh_stronghold_detail() -> void:
	if not is_instance_valid(tile_info):
		return
	for c in tile_info.get_children():
		c.queue_free()
	var sh := GameState.stronghold_by_id(selected_stronghold)
	if sh.is_empty():
		tile_info.add_child(UIKit.dim("没有可管理的据点，请先建立营地。"))
		return
	var tiles := GameState.stronghold_tiles(selected_stronghold)
	var land_cap := 0.0
	var land_used := 0.0
	for t in tiles:
		land_cap += GameState.land_cap(t)
		land_used += GameState.land_used(t)
	tile_info.add_child(_detail_row("据点", str(sh.get("name", "")), UIKit.GOLD))
	tile_info.add_child(_detail_row("掌控力", "%.0f%%" % (GameState.control_of(sh) * 100.0), UIKit.TEXT))
	tile_info.add_child(_detail_row("地块", "%d 块" % tiles.size(), UIKit.TEXT))
	tile_info.add_child(_detail_row("已用土地", "%.1f / %.1f" % [land_used, land_cap], UIKit.TEXT_DIM))
	tile_info.add_child(UIKit.spacer(2))
	tile_info.add_child(UIKit.dim("地块明细："))
	if tiles.is_empty():
		tile_info.add_child(UIKit.dim("（暂无领地）"))
	for t in tiles:
		var key := GameState.tile_key(t)
		var nm := str(t.get("name", ""))
		if nm == "":
			nm = key
		var bcount := (t.get("buildings", []) as Array).size()
		var line := "· %s [%s]　地形 %s　土地 %.1f/%.1f　建筑 %d" % [
			nm, key, Consts.terrain_name(str(t.get("terrain", ""))),
			GameState.land_used(t), GameState.land_cap(t), bcount]
		var l := UIKit.dim(line, 11)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tile_info.add_child(l)


func _detail_row(key: String, value: String, col: Color) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var k := UIKit.text_label(key, 12, UIKit.TEXT_DIM)
	k.custom_minimum_size = Vector2(72, 0)
	h.add_child(k)
	var v := UIKit.text_label(value, 12, col)
	v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	return h


func _refresh_labor() -> void:
	if not is_instance_valid(labor_list):
		return
	for c in labor_list.get_children():
		c.queue_free()
	var sh := GameState.stronghold_by_id(selected_stronghold)
	if sh.is_empty():
		return
	var any := false
	for t in GameState.stronghold_tiles(selected_stronghold):
		var key := GameState.tile_key(t)
		for b in t.get("buildings", []):
			var def := GameState.find_building(str(b.get("id", "")))
			if def == null:
				continue
			var level := int(b.get("level", 1))
			var maxw := def.max_workers(level)
			if maxw <= 0:
				continue	
			any = true
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 4)
			labor_list.add_child(row)
			var l := UIKit.text_label("%s Lv.%d（%s）" % [def.display_name, level, key], 11, UIKit.TEXT)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			row.add_child(l)
			var bid := str(b.get("bid", ""))
			var minus := UIKit.tiny("−", 12)
			minus.pressed.connect(func() -> void:
				GameState.assign_worker_by_bid(key, bid, -1)
				refresh())
			var num := UIKit.text_label("%d/%d" % [int(b.get("workers", 0)), maxw], 11, UIKit.TEXT)
			var plus := UIKit.tiny("＋", 12)
			plus.pressed.connect(func() -> void:
				var r2: Dictionary = GameState.assign_worker_by_bid(key, bid, 1)
				if not r2["ok"]:
					GameState.toast.emit(str(r2["why"]))
				refresh())
			row.add_child(minus)
			row.add_child(num)
			row.add_child(plus)
	if not any:
		labor_list.add_child(UIKit.dim("该据点还没有建筑。到「世界 → 规划面板 → 地块规划页」修建。"))


func _refresh_queue() -> void:
	if not is_instance_valid(queue_list):
		return
	for c in queue_list.get_children():
		c.queue_free()
	var sh := GameState.stronghold_by_id(selected_stronghold)
	if sh.is_empty():
		return
	var q: Array = sh.get("queue", [])
	if q.is_empty():
		queue_list.add_child(UIKit.dim("队列为空。到「世界 → 规划面板 → 地块规划页」选择建筑修建。"))
		return
	for i in q.size():
		_queue_row(q[i], i, q.size())


func _queue_row(item: Dictionary, index: int, total: int) -> void:
	var def := GameState.find_building(str(item.get("id", "")))
	var nm: String = def.display_name if def != null else str(item.get("id", ""))
	var kind := "升级" if str(item.get("kind", "")) == "upgrade" else "修建"
	var row := PanelContainer.new()
	UIKit.apply_panel(row, UIKit.BG_PANEL_2, UIKit.LINE_SOFT, 5)
	queue_list.add_child(row)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	row.add_child(h)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 1)
	h.add_child(v)
	v.add_child(UIKit.text_label("%d. %s%s　[%s]" % [
		index + 1, kind, nm, str(item.get("tile", ""))], 12, UIKit.TEXT))
	var need := float(item.get("need_prod", 0.0))
	var paid := float(item.get("paid_prod", 0.0))
	v.add_child(UIKit.bar(paid, maxf(0.0001, need), UIKit.GOLD, 150.0, 10.0))
	v.add_child(UIKit.dim("生产力 %.1f / %.1f" % [paid, need], 10))
	var ops := VBoxContainer.new()
	ops.add_theme_constant_override("separation", 2)
	h.add_child(ops)
	var up := UIKit.tiny("↑", 11)
	up.disabled = index <= 0
	up.pressed.connect(func() -> void:
		GameState.queue_move(selected_stronghold, index, -1)
		refresh())
	ops.add_child(up)
	var dn := UIKit.tiny("↓", 11)
	dn.disabled = index >= total - 1
	dn.pressed.connect(func() -> void:
		GameState.queue_move(selected_stronghold, index, 1)
		refresh())
	ops.add_child(dn)
	var rm := UIKit.tiny("移除", 10, true)
	rm.pressed.connect(func() -> void:
		GameState.queue_remove(selected_stronghold, index)
		refresh())
	ops.add_child(rm)


func on_cycle_finished(_rep: Dictionary) -> void:
	refresh()


# ---------------------------------------------------------------------------
# v1.1 军队：征兵 / 编队总览
# ---------------------------------------------------------------------------
func _refresh_units() -> void:
	var box := unit_box
	if box == null:
		return
	for c in box.get_children():
		c.queue_free()
	var units: Array = GameState.state["units"]
	var by_prof := {}
	var deployed := 0
	for u in units:
		var p := str(u.get("profession", ""))
		by_prof[p] = int(by_prof.get(p, 0)) + 1
		if str(u.get("tile", "")) != "":
			deployed += 1
	box.add_child(UIKit.text_label("单位 %d 个（派驻 %d）｜空闲人力 %d" % [
		units.size(), deployed, GameState.free_pop()], 12,
		UIKit.TEXT if not units.is_empty() else UIKit.TEXT_DIM))
	var parts: Array[String] = []
	for p in UnitDB.PROFESSION_ORDER:
		var n := int(by_prof.get(p, 0))
		if n > 0:
			parts.append("%s×%d" % [UnitDB.profession_name(p), n])
	if not parts.is_empty():
		var l := UIKit.dim("　".join(parts), 11)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(l)
	var teams: Array = GameState.state["teams"]
	var tparts: Array[String] = []
	for i in teams.size():
		tparts.append("%s %d/%d" % [str((teams[i] as Dictionary)["name"]),
			GameState.team_units(i).size(), UnitDB.UNITS_PER_TEAM])
	var tl := UIKit.dim("队伍：" + "　".join(tparts), 11)
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(tl)


func _open_recruit() -> void:
	var gs := UIKit.game_screen_of(self)
	if gs == null:
		return
	var v := UIKit.vbox(6)
	v.add_child(UIKit.text_label("招募募集兵", 15, UIKit.GOLD))
	v.add_child(UIKit.dim("募集军是刚招募的军队单位，对战斗并不熟练，属性倍率只有 0.6~0.8，经验上限 100 点。\n需要一座「经典训练场地」。执行时消耗：食物 20、货币 60。\n\nv1.8.3：征兵已改成**政事** —— 排入队列后每周期积累行政点数，攒够 %.0f 点才真正征到兵。" % DecreeDB.cost_of(DecreeDB.RECRUIT)))
	for p in UnitDB.PROFESSION_ORDER:
		var row := PanelContainer.new()
		UIKit.apply_panel(row, UIKit.BG_PANEL_2, UnitDB.profession_color(p), 5)
		v.add_child(row)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		row.add_child(h)
		var ic := GeoIcon.new()
		ic.custom_minimum_size = Vector2(30, 30)
		ic.setup(UnitDB.profession_icon(p), UnitDB.profession_color(p))
		h.add_child(ic)
		var tv := VBoxContainer.new()
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(tv)
		tv.add_child(UIKit.text_label(UnitDB.profession_name(p), 13, UnitDB.profession_color(p)))
		var dd := UIKit.dim(UnitDB.profession_desc(p), 10)
		dd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tv.add_child(dd)
		# v1.8.3：征兵改成"排进政事队列"（攒够行政点数才真的征到兵）。
		# v1.8.4 会把这条政事搬到据点管理窗口的「政事」页；这里先留过渡入口。
		var b := UIKit.small("排入政事", 12)
		b.pressed.connect(func() -> void:
			var r := GameState.enqueue_decree(DecreeDB.RECRUIT, p)
			if not r["ok"]:
				GameState.toast.emit(str(r["why"]))
			else:
				GameState.toast.emit("已排入政事队列：征兵（%s）" % UnitDB.profession_name(p))
			gs.close_dialog()
			refresh())
		h.add_child(b)
	var sc := UIKit.scroll(v)
	sc.custom_minimum_size = Vector2(0, 380)
	var d := UIKit.dialog("招募募集兵", 560.0)
	d.set_content(sc)
	gs.open_dialog(d)


func _open_teams() -> void:
	var gs := UIKit.game_screen_of(self)
	if gs == null:
		return
	var v := UIKit.vbox(6)
	v.add_child(UIKit.text_label("队伍编成（每队最多 %d 个单位）" % UnitDB.UNITS_PER_TEAM, 15, UIKit.GOLD))
	v.add_child(UIKit.dim("在「至宝 → 角色 → 编队」页可以为每个单位选择队伍与驻守地块。"))
	var teams: Array = GameState.state["teams"]
	for i in teams.size():
		var members := GameState.team_units(i)
		var pane := UIKit.panel(UIKit.BG_PANEL_2, UIKit.LINE_SOFT, 5)
		v.add_child(pane)
		var pv := VBoxContainer.new()
		pane.add_child(pv)
		pv.add_child(UIKit.text_label("%s（%d/%d）" % [str(teams[i]["name"]),
			members.size(), UnitDB.UNITS_PER_TEAM], 13, UIKit.GOLD))
		if members.is_empty():
			pv.add_child(UIKit.dim("（空队伍）", 11))
		for m in members:
			pv.add_child(UIKit.dim("　· %s　%s·%s　驻 %s" % [
				str(m["name"]), UnitDB.rank_name(str(m.get("rank", ""))),
				UnitDB.profession_name(str(m.get("profession", ""))),
				str(m.get("tile", "")) if str(m.get("tile", "")) != "" else "营地"], 11))
	var sc := UIKit.scroll(v)
	sc.custom_minimum_size = Vector2(0, 320)
	var d := UIKit.dialog("队伍编成", 520.0)
	d.set_content(sc)
	gs.open_dialog(d)