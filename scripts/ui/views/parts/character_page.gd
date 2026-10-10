extends Control
## 角色 / 单位页（v1.1 重构版）
##
## 左边是单位列表（可按类型筛选），中间是立绘 + 名字/性别/特质，
## 右边是三级按钮：主要 / 技能 / 职业 / 位阶 / 编队。
## 新增内容：职业与克制关系、位阶与经验倍率、地块派驻（每格最多 4 个单位）、队伍编成（每队最多 4 个单位）。

const SUB_TABS := [
	{"id": "main", "name": "主要"},
	{"id": "skill", "name": "技能"},
	{"id": "profession", "name": "职业"},
	{"id": "rank", "name": "位阶"},
	# v1.8.10：**「编队」入口暂时隐藏**（用户决定"暂时放弃编队功能"）。
	# 只藏入口，不动代码：`team` 子页的构造与 `GameState.assign_team/remove_from_team/team_units`
	# 全都留着，等以后"大世界单位操作"优化完，把上面这行取消注释接回来即可。
	# {"id": "team", "name": "编队"},
]

const TYPE_FILTERS := [
	{"id": "all", "name": "全部"},
	{"id": "character", "name": "角色"},
	{"id": "trained", "name": "训练军"},
	{"id": "recruit", "name": "募集军"},
]

## v1.5：二类筛选（客人 / 公民）
const STATUS_FILTERS := [
	{"id": "all", "name": "全部"},
	{"id": "guest", "name": "客人"},
	{"id": "citizen", "name": "公民"},
]

var list_box: VBoxContainer
var portrait_host: CenterContainer
var name_label: Label
var meta_label: Label
var badge_row: HBoxContainer
var sub_bar: HBoxContainer
var type_bar: HBoxContainer
var status_bar: HBoxContainer
var status_actions: HBoxContainer
var detail_host: VBoxContainer
var selected_id: String = ""
var sub_tab := "main"
var type_filter := "all"
var status_filter := "all"


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	refresh()


func _build() -> void:
	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", UI.fs(6))
	add_child(root)

	# ---- 最左：单位列表 ----
	var left := UIKit.panel()
	left.custom_minimum_size = Vector2(UI.px(250), UI.px(0))
	root.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", UI.fs(4))
	left.add_child(lv)
	lv.add_child(UIKit.title("单位列表", 15))

	type_bar = HBoxContainer.new()
	type_bar.add_theme_constant_override("separation", UI.fs(3))
	lv.add_child(type_bar)
	for f in TYPE_FILTERS:
		var fid: String = f["id"]
		var b := UIKit.tiny(str(f["name"]), 11)
		b.custom_minimum_size = Vector2(UI.px(0), UI.px(24))
		b.pressed.connect(func() -> void:
			type_filter = fid
			refresh())
		type_bar.add_child(b)

	# v1.5：二类筛选（客人 / 公民）
	status_bar = HBoxContainer.new()
	status_bar.add_theme_constant_override("separation", UI.fs(3))
	lv.add_child(status_bar)
	for f in STATUS_FILTERS:
		var sfid: String = f["id"]
		var sb := UIKit.tiny(str(f["name"]), 11)
		sb.custom_minimum_size = Vector2(UI.px(0), UI.px(24))
		sb.pressed.connect(func() -> void:
			status_filter = sfid
			refresh())
		status_bar.add_child(sb)

	lv.add_child(UIKit.dim("按位阶、稀有度排序"))
	list_box = VBoxContainer.new()
	list_box.add_theme_constant_override("separation", UI.fs(3))
	lv.add_child(UIKit.scroll(list_box))

	# ---- 左中：立绘 + 基础信息 ----
	var mid := UIKit.panel()
	mid.custom_minimum_size = Vector2(UI.px(250), UI.px(0))
	root.add_child(mid)
	var mv := VBoxContainer.new()
	mv.alignment = BoxContainer.ALIGNMENT_CENTER
	mv.add_theme_constant_override("separation", UI.fs(6))
	mid.add_child(mv)

	var pic_frame := PanelContainer.new()
	UIKit.apply_panel(pic_frame, UIKit.BG_SLOT, UIKit.LINE, 8)
	pic_frame.custom_minimum_size = Vector2(UI.px(210), UI.px(190))
	mv.add_child(pic_frame)
	# v1.7：立绘槽 —— 有美术就放立绘，没有就回落到几何占位（每帧重建，随选中单位切换）
	portrait_host = CenterContainer.new()
	portrait_host.custom_minimum_size = Vector2(UI.px(190), UI.px(170))
	pic_frame.add_child(portrait_host)

	name_label = UIKit.text_label("未选择单位", 19, UIKit.GOLD)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mv.add_child(name_label)

	badge_row = HBoxContainer.new()
	badge_row.alignment = BoxContainer.ALIGNMENT_CENTER
	badge_row.add_theme_constant_override("separation", UI.fs(4))
	mv.add_child(badge_row)

	meta_label = UIKit.text_label("", 12, UIKit.TEXT_DIM)
	meta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	meta_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mv.add_child(meta_label)

	# v1.5：状态窗口底部 —— 客人可「招募 / 遣返」，公民没有按钮
	status_actions = HBoxContainer.new()
	status_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	status_actions.add_theme_constant_override("separation", UI.fs(6))
	mv.add_child(status_actions)

	# ---- 右：三级按钮 + 内容 ----
	var right := UIKit.panel()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", UI.fs(6))
	right.add_child(rv)

	sub_bar = HBoxContainer.new()
	sub_bar.add_theme_constant_override("separation", UI.fs(6))
	rv.add_child(sub_bar)
	for t in SUB_TABS:
		var tid: String = t["id"]
		var b := UIKit.small(str(t["name"]), 13)
		b.custom_minimum_size = Vector2(UI.px(76), UI.px(30))
		b.pressed.connect(func() -> void:
			sub_tab = tid
			refresh())
		sub_bar.add_child(b)

	detail_host = VBoxContainer.new()
	detail_host.add_theme_constant_override("separation", UI.fs(6))
	rv.add_child(UIKit.scroll(detail_host))


# ---------------------------------------------------------------------------
# 刷新
# ---------------------------------------------------------------------------
func refresh() -> void:
	if not is_instance_valid(list_box):
		return
	_refresh_bars()
	_refresh_list()
	_refresh_portrait()
	_refresh_detail()


func _refresh_bars() -> void:
	var i := 0
	for c in sub_bar.get_children():
		if c is Button:
			var active: bool = SUB_TABS[i]["id"] == sub_tab
			UIKit.style_button(c as Button, active)
			(c as Button).add_theme_color_override("font_color", UIKit.GOLD if active else UIKit.TEXT)
			i += 1
	i = 0
	for c2 in type_bar.get_children():
		if c2 is Button:
			var active2: bool = TYPE_FILTERS[i]["id"] == type_filter
			UIKit.style_button(c2 as Button, active2)
			(c2 as Button).add_theme_color_override("font_color", UIKit.GOLD if active2 else UIKit.TEXT)
			i += 1
	i = 0
	for c3 in status_bar.get_children():
		if c3 is Button:
			var active3: bool = STATUS_FILTERS[i]["id"] == status_filter
			UIKit.style_button(c3 as Button, active3)
			(c3 as Button).add_theme_color_override("font_color", UIKit.GOLD if active3 else UIKit.TEXT)
			i += 1


func _filtered_units() -> Array:
	var out := []
	for u in GameState.state["units"]:
		if type_filter != "all" and str(u.get("unit_type", "character")) != type_filter:
			continue
		if status_filter != "all" and str(u.get("status", UnitDB.STATUS_CITIZEN)) != status_filter:
			continue
		out.append(u)
	# 位阶优先，其次稀有度
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ra := UnitDB.RANK_ORDER.find(str(a.get("rank", "")))
		var rb := UnitDB.RANK_ORDER.find(str(b.get("rank", "")))
		if ra != rb:
			return ra > rb
		if int(a.get("rarity", 1)) != int(b.get("rarity", 1)):
			return int(a["rarity"]) > int(b["rarity"])
		return str(a["name"]) < str(b["name"]))
	return out


func _refresh_list() -> void:
	for c in list_box.get_children():
		c.queue_free()
	var units := _filtered_units()
	if units.is_empty():
		list_box.add_child(UIKit.dim("这里还没有单位。\n去「世界泡 → 召唤系统」召唤角色，\n或在「管理」里招募募集兵。"))
		return
	for u in units:
		list_box.add_child(_unit_row(u))
	if selected_id == "" or GameState.unit_by_uid(selected_id).is_empty():
		if not units.is_empty():
			selected_id = str(units[0]["uid"])
		else:
			selected_id = ""


func _unit_row(u: Dictionary) -> Control:
	var is_sel := str(u["uid"]) == selected_id
	var rank_col := UnitDB.rank_color(str(u.get("rank", "")))

	# 整行就是一个 Button：不再依赖「全屏透明按钮 + move_child」的做法
	# （那种做法会把命中层压在后面的兄弟节点之下，导致多抽几个角色后就点不中）
	var row := Button.new()
	row.custom_minimum_size = Vector2(UI.px(0), UI.px(40))
	row.focus_mode = Control.FOCUS_NONE
	row.clip_text = false
	UIKit.style_button(row, is_sel)
	row.pressed.connect(func() -> void:
		selected_id = str(u["uid"])
		refresh())

	var h := HBoxContainer.new()
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 6
	h.offset_top = 3
	h.offset_right = -4
	h.offset_bottom = -3
	h.add_theme_constant_override("separation", UI.fs(6))
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(h)

	var ic := GeoIcon.new()
	ic.custom_minimum_size = Vector2(UI.px(28), UI.px(28))
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.setup(UnitDB.profession_icon(str(u.get("profession", ""))),
		UnitDB.profession_color(str(u.get("profession", ""))))
	h.add_child(ic)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", UI.fs(0))
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	v.add_child(UIKit.text_label(str(u["name"]), 12, Consts.rarity_color(int(u.get("rarity", 1)))))
	var sub := "%s·%s" % [UnitDB.rank_name(str(u.get("rank", ""))),
		UnitDB.profession_name(str(u.get("profession", "")))]
	# 派驻 / 编队标记
	var marks: Array[String] = []
	if str(u.get("tile", "")) != "":
		marks.append("驻%s" % str(u["tile"]))
	if int(u.get("team", -1)) >= 0:
		marks.append("队%d" % (int(u["team"]) + 1))
	var line2 := sub + ("　" + " ".join(marks) if not marks.is_empty() else "")
	v.add_child(UIKit.dim(line2, 10))

	# 位阶颜色条（必须限制宽度，否则会被 HBoxContainer 拉满整行）
	var strip := ColorRect.new()
	strip.color = rank_col
	strip.custom_minimum_size = Vector2(UI.px(3), UI.px(0))
	strip.size_flags_horizontal = Control.SIZE_SHRINK_END
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(strip)
	return row


func _selected() -> Dictionary:
	return GameState.unit_by_uid(selected_id)


func _refresh_portrait() -> void:
	for c in badge_row.get_children():
		c.queue_free()
	for c in portrait_host.get_children():
		c.queue_free()
	var u := _selected()
	if u.is_empty():
		var ph := GeoIcon.new()
		ph.custom_minimum_size = Vector2(UI.px(190), UI.px(170))
		ph.setup("circle", UIKit.TEXT_FAINT)
		portrait_host.add_child(ph)
		name_label.text = "未选择单位"
		name_label.add_theme_color_override("font_color", UIKit.GOLD)
		meta_label.text = ""
		_refresh_status_actions({})
		return
	var rcol := Consts.rarity_color(int(u.get("rarity", 1)))
	portrait_host.add_child(UIKit.unit_art(u, "portrait", Vector2(190, 170)))
	name_label.text = str(u["name"])
	name_label.add_theme_color_override("font_color", rcol)
	badge_row.add_child(_badge(UnitDB.rank_name(str(u.get("rank", ""))),
		UnitDB.rank_color(str(u.get("rank", "")))))
	badge_row.add_child(_badge(UnitDB.profession_name(str(u.get("profession", ""))),
		UnitDB.profession_color(str(u.get("profession", "")))))
	# v1.5：客人 / 公民 徽记
	var st := str(u.get("status", UnitDB.STATUS_CITIZEN))
	badge_row.add_child(_badge(UnitDB.status_name(st),
		UIKit.WARN if st == UnitDB.STATUS_GUEST else UIKit.OK))
	meta_label.text = "性别：%s　特质：%s　%s" % [
		_gender_of(u), _trait_of(u), UnitDB.unit_type_name(str(u.get("unit_type", "character")))]
	_refresh_status_actions(u)


## v1.5：状态窗口底部按钮 —— 客人可「招募 / 遣返」，公民没有按钮
func _refresh_status_actions(u: Dictionary) -> void:
	if not is_instance_valid(status_actions):
		return
	for c in status_actions.get_children():
		c.queue_free()
	if u.is_empty():
		return
	if str(u.get("status", UnitDB.STATUS_CITIZEN)) != UnitDB.STATUS_GUEST:
		status_actions.add_child(UIKit.dim("公民 — 已在大世界中", 11))
		return
	var uid := str(u.get("uid", ""))
	var b_recruit := UIKit.primary("招募", 13)
	b_recruit.tooltip_text = "接受招募后成为公民，需要在世界系统里选一块领地进行部署"
	b_recruit.pressed.connect(func() -> void:
		var r := GameState.begin_recruit(uid)
		if not bool(r["ok"]):
			GameState.toast.emit(str(r["why"]))
			return
		GameState.toast.emit("请在世界系统中点选要部署的领地，再点「确认招募」")
		_go_world())
	status_actions.add_child(b_recruit)

	var b_dismiss := UIKit.normal("遣返", 13)
	b_dismiss.tooltip_text = "把他送回自己的世界（从库存中移除）"
	b_dismiss.pressed.connect(func() -> void:
		var r := GameState.dismiss_guest(uid)
		if not bool(r["ok"]):
			GameState.toast.emit(str(r["why"]))
			return
		selected_id = ""
		refresh())
	status_actions.add_child(b_dismiss)


## 跳到世界系统（招募时选地）
func _go_world() -> void:
	var gs := UIKit.game_screen_of(self)
	if gs != null and gs.has_method("goto_view"):
		gs.call("goto_view", "world")


func _badge(text: String, col: Color) -> Control:
	var p := PanelContainer.new()
	UIKit.apply_panel(p, Color(col.r * 0.25, col.g * 0.25, col.b * 0.25, 1.0), col, 4)
	var l := UIKit.text_label(text, 11, col)
	p.add_child(l)
	return p


static func _gender_of(u: Dictionary) -> String:
	var kinds := ["triangle", "square", "star", "circle", "hexagon", "diamond", "line"]
	var idx := kinds.find(str(u.get("kind", "circle")))
	return ["女", "男", "女", "机械", "未知", "男", "未知"][maxi(0, idx)]


static func _trait_of(u: Dictionary) -> String:
	var traits := ["坚韧", "迅捷", "锐利", "精密", "神秘", "沉稳", "中庸"]
	var kinds := ["square", "triangle", "line", "circle", "hexagon", "diamond", "star"]
	var idx := kinds.find(str(u.get("kind", "circle")))
	return traits[maxi(0, idx)] + "系"


# ---------------------------------------------------------------------------
# 详情各页
# ---------------------------------------------------------------------------
func _refresh_detail() -> void:
	for c in detail_host.get_children():
		c.queue_free()
	var u := _selected()
	if u.is_empty():
		detail_host.add_child(UIKit.dim("从左边的列表里选一个单位。"))
		return
	match sub_tab:
		"main": _build_main(u)
		"skill": _build_skill(u)
		"profession": _build_profession(u)
		"rank": _build_rank(u)
		"team": _build_team(u)
		_: _build_main(u)


func _build_main(u: Dictionary) -> void:
	var attr_panel := UIKit.panel(UIKit.BG_PANEL_2, UIKit.LINE_SOFT, 6)
	detail_host.add_child(attr_panel)
	var av := VBoxContainer.new()
	av.add_theme_constant_override("separation", UI.fs(4))
	attr_panel.add_child(av)
	av.add_child(UIKit.title("属性信息", 15))

	# 基础属性 vs 位阶修正后的实际战斗属性
	var base: Dictionary = u.get("attr", {})
	var eff: Dictionary = GameState.unit_combat_attr(u)
	var mul := UnitDB.rank_multiplier(str(u.get("rank", "")), UnitDB.progress_of(u))
	var names := {
		"atk": "攻击力", "def": "防御力", "hp": "生命值",
		"spd": "移动速度", "agi": "灵敏值",
	}
	var g := UIKit.grid(4, 14, 4)
	av.add_child(g)
	g.add_child(UIKit.dim("属性", 11))
	g.add_child(UIKit.dim("基础", 11))
	g.add_child(UIKit.dim("实战（含位阶）", 11))
	g.add_child(UIKit.dim("倍率", 11))
	for k in ["atk", "def", "hp", "spd", "agi"]:
		if not base.has(k):
			continue
		g.add_child(UIKit.text_label(str(names.get(k, k)), 12, UIKit.TEXT_DIM))
		g.add_child(UIKit.text_label(str(base[k]), 12, UIKit.TEXT))
		g.add_child(UIKit.text_label("%.1f" % float(eff.get(k, 0.0)), 12,
			UIKit.OK if mul >= 1.0 else UIKit.WARN))
		g.add_child(UIKit.dim("×%.2f" % mul, 11))
	av.add_child(UIKit.dim("位阶倍率 ×%.2f = 在 [%.2f, %.2f] 区间内按经验进度插值" % [
		mul, float(UnitDB.RANKS[str(u.get("rank", "recruit"))]["mul_min"]),
		float(UnitDB.RANKS[str(u.get("rank", "recruit"))]["mul_max"])], 11))

	var lv_row := HBoxContainer.new()
	lv_row.add_theme_constant_override("separation", UI.fs(6))
	av.add_child(lv_row)
	lv_row.add_child(UIKit.dim("等级 %d / 上限（星级 %d → %d 级）" % [
		int(u.get("level", 1)), int(u.get("star", 1)), int(u.get("star", 1)) * 20], 12))
	var up := UIKit.small("提升等级（消耗货币）", 12)
	up.pressed.connect(func() -> void:
		var cost := 120.0 * float(u.get("level", 1))
		if GameState.res("currency") < cost:
			GameState.toast.emit("货币不足（需要 %d）" % int(cost))
			return
		GameState.add_res("currency", -cost)
		u["level"] = int(u["level"]) + 1
		GameState.add_log("%s 提升到 Lv.%d。" % [u["name"], int(u["level"])], "unit")
		GameState.state_changed.emit()
		refresh())
	lv_row.add_child(up)

	# 携带信息
	var carry := UIKit.panel(UIKit.BG_PANEL_2, UIKit.LINE_SOFT, 6)
	detail_host.add_child(carry)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", UI.fs(3))
	carry.add_child(cv)
	var ch := HBoxContainer.new()
	ch.add_theme_constant_override("separation", UI.fs(8))
	cv.add_child(ch)
	ch.add_child(UIKit.title("携带信息", 15))
	var auto_eq := UIKit.small("随机分配一件装备", 11)
	auto_eq.pressed.connect(func() -> void:
		_auto_equip(u))
	ch.add_child(auto_eq)
	var eq: Dictionary = u.get("equipped", {"weapon": "", "relic": ""})
	for slot in ["weapon", "relic"]:
		var slot_name := "武装" if slot == "weapon" else "战备"
		var item_id := str(eq.get(slot, ""))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", UI.fs(6))
		cv.add_child(row)
		row.add_child(UIKit.dim(slot_name, 12))
		if item_id == "":
			row.add_child(UIKit.text_label("（空）", 12, UIKit.TEXT_FAINT))
		else:
			var it := _find_equipment(item_id)
			row.add_child(UIKit.text_label(str(it.get("name", item_id)), 12,
				Consts.rarity_color(int(it.get("rarity", 1)))))

	var hint := UIKit.dim("说明：角色可以装备「召唤」获得的武装与战备；训练军 / 募集军不能装备召唤产物。", 11)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_host.add_child(hint)


func _build_skill(u: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UI.fs(6))
	detail_host.add_child(row)

	var tal := UIKit.panel(UIKit.BG_PANEL_2, UIKit.LINE_SOFT, 6)
	tal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(tal)
	var tv := VBoxContainer.new()
	tal.add_child(tv)
	tv.add_child(UIKit.title("天赋", 15))
	tv.add_child(UIKit.dim("伴随等级提升而解锁", 11))
	var unlock_levels := [1, 10, 20, 40]
	var tnames := ["%s·共鸣" % u["name"], "%s·强化" % u["name"],
		"%s·领域" % u["name"], "%s·终焉" % u["name"]]
	for i in unlock_levels.size():
		var need := int(unlock_levels[i])
		var unlocked := int(u.get("level", 1)) >= need
		tv.add_child(UIKit.text_label("%s %s" % ["✔" if unlocked else "✖", tnames[i]], 12,
			UIKit.OK if unlocked else UIKit.TEXT_FAINT))
		tv.add_child(UIKit.dim("　　Lv.%d 解锁" % need, 10))

	var sk := UIKit.panel(UIKit.BG_PANEL_2, UIKit.LINE_SOFT, 6)
	sk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sk)
	var sv := VBoxContainer.new()
	sk.add_child(sv)
	sv.add_child(UIKit.title("技能", 15))
	sv.add_child(UIKit.dim("需要通过使用、训练、强化来提升", 11))
	var skills: Array = u.get("skills", [])
	if skills.is_empty():
		sv.add_child(UIKit.dim("（尚未觉醒技能）"))
	for s in skills:
		sv.add_child(UIKit.text_label("· %s Lv.%d" % [str(s.get("name", "?")), int(s.get("level", 1))], 12))
	var add := UIKit.small("训练一次（消耗货币 200）", 12)
	add.pressed.connect(func() -> void:
		if GameState.res("currency") < 200.0:
			GameState.toast.emit("货币不足")
			return
		GameState.add_res("currency", -200.0)
		var arr: Array = u.get("skills", [])
		var nm := "%s·奥义" % u["name"]
		var found := false
		for s in arr:
			if str(s.get("name", "")) == nm:
				s["level"] = int(s["level"]) + 1
				found = true
		if not found:
			arr.append({"name": nm, "level": 1})
		u["skills"] = arr
		GameState.add_log("%s 的技能获得提升。" % u["name"], "unit")
		GameState.state_changed.emit()
		refresh())
	sv.add_child(add)

	# v1.1：独特机制接口（为抽卡角色预留）
	var uniq := UIKit.panel(UIKit.BG_PANEL_2, UIKit.LINE_SOFT, 6)
	detail_host.add_child(uniq)
	var uv := VBoxContainer.new()
	uniq.add_child(uv)
	uv.add_child(UIKit.title("独特机制（预留接口）", 15))
	var uniques: Array = u.get("unique", [])
	if uniques.is_empty():
		uv.add_child(UIKit.dim("该单位暂时没有独特机制。召唤角色可以挂载以下接口：", 11))
	else:
		for key in uniques:
			uv.add_child(UIKit.text_label("· " + str(UnitDB.UNIQUE_HOOKS.get(str(key), key)), 12, UIKit.GOLD))
	var gh := HBoxContainer.new()
	gh.add_theme_constant_override("separation", UI.fs(4))
	uv.add_child(gh)
	for key2 in UnitDB.UNIQUE_HOOKS.keys():
		if uniques.has(key2):
			continue
		var kb := UIKit.tiny(str(UnitDB.UNIQUE_HOOKS[key2]).split("：")[0], 11)
		kb.tooltip_text = str(UnitDB.UNIQUE_HOOKS[key2])
		kb.pressed.connect(func() -> void:
			(u["unique"] as Array).append(key2)
			GameState.toast.emit("已为该单位挂载机制：%s" % str(UnitDB.UNIQUE_HOOKS[key2]))
			refresh())
		gh.add_child(kb)


func _build_profession(u: Dictionary) -> void:
	var my := str(u.get("profession", UnitDB.MELEE))
	var head := UIKit.panel(UIKit.BG_PANEL_2, UnitDB.profession_color(my), 6)
	detail_host.add_child(head)
	var hv := HBoxContainer.new()
	hv.add_theme_constant_override("separation", UI.fs(8))
	head.add_child(hv)
	var ic := GeoIcon.new()
	ic.custom_minimum_size = Vector2(UI.px(52), UI.px(52))
	ic.setup(UnitDB.profession_icon(my), UnitDB.profession_color(my))
	hv.add_child(ic)
	var ht := VBoxContainer.new()
	ht.add_theme_constant_override("separation", UI.fs(2))
	hv.add_child(ht)
	ht.add_child(UIKit.text_label("当前职业：%s" % UnitDB.profession_name(my), 16, UnitDB.profession_color(my)))
	var d := UIKit.dim(UnitDB.profession_desc(my), 11)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ht.add_child(d)
	var rng := int((UnitDB.PROFESSIONS[my] as Dictionary).get("range", 1))
	if rng >= 2:
		ht.add_child(UIKit.text_label("攻击距离：%d 格（可以隔一格攻击）" % rng, 11, UIKit.OK))

	detail_host.add_child(UIKit.title("克制关系总览", 15))
	var g := UIKit.grid(6, 8, 4)
	detail_host.add_child(g)
	g.add_child(UIKit.dim("攻方＼守方", 11))
	for p in UnitDB.PROFESSION_ORDER:
		g.add_child(UIKit.text_label(UnitDB.profession_name(p), 11, UnitDB.profession_color(p)))
	for a in UnitDB.PROFESSION_ORDER:
		g.add_child(UIKit.text_label(UnitDB.profession_name(a), 11, UnitDB.profession_color(a)))
		for b in UnitDB.PROFESSION_ORDER:
			var adv := UnitDB.advantage(a, b)
			var txt := "—"
			var col := UIKit.TEXT_FAINT
			if adv > 0:
				txt = "克制 +30%"
				col = UIKit.OK
			elif adv < 0:
				txt = "被克制 −20%"
				col = UIKit.BAD
			var cell := UIKit.text_label(txt, 10, col)
			g.add_child(cell)

	detail_host.add_child(UIKit.spacer(4))
	detail_host.add_child(UIKit.title("该单位的克制结果", 15))
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", UI.fs(2))
	detail_host.add_child(rows)
	for enemy in UnitDB.PROFESSION_ORDER:
		var a2 := UnitDB.advantage(my, enemy)
		var e2 := UnitDB.advantage(enemy, my)
		var text := "对 %s：均势" % UnitDB.profession_name(enemy)
		var col2 := UIKit.TEXT_DIM
		if a2 > 0 and e2 < 0:
			text = "对 %s：单方面克制（+30%% 伤害）" % UnitDB.profession_name(enemy)
			col2 = UIKit.OK
		elif a2 > 0:
			text = "对 %s：互相克制（+30%% / −20%%）" % UnitDB.profession_name(enemy)
			col2 = UIKit.WARN
		elif a2 < 0 and e2 > 0:
			text = "对 %s：被单方面克制（−20%% 伤害）" % UnitDB.profession_name(enemy)
			col2 = UIKit.BAD
		rows.add_child(UIKit.text_label(text, 11, col2))

	# 防御者/支援者的特殊说明
	detail_host.add_child(UIKit.spacer(4))
	var note := UIKit.panel(UIKit.BG_PANEL_2, UIKit.LINE_SOFT, 5)
	detail_host.add_child(note)
	var nv := VBoxContainer.new()
	note.add_child(nv)
	nv.add_child(UIKit.title("职业机制说明", 14))
	var notes := [
		"防御者：小幅度减免所在格子及队伍中单位所受伤害（−20%），对投射者的伤害大幅度减免（−60%）。",
		"支援者：不直接造成伤害，而是根据条件增幅特定单位的伤害或提供减免。",
		"投射者：射程为 2 格，能够攻击间隔一个格子的目标。",
		"战斗规则：除非有专门设计，伤害都是个体对个体结算；目标格子存在多个单位时需要专门选择，敌人 AI 面对多单位格子随机选择，只有高危及以上的敌人才会考虑克制关系。",
	]
	for n in notes:
		var l := UIKit.dim(n, 11)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nv.add_child(l)


func _build_rank(u: Dictionary) -> void:
	var rank := str(u.get("rank", UnitDB.RECRUIT))
	var exp := int(u.get("exp", 0))
	var cap := UnitDB.exp_cap(rank)
	var prog := UnitDB.progress_of(u)
	var mul := UnitDB.rank_multiplier(rank, prog)

	var head := UIKit.panel(UIKit.BG_PANEL_2, UnitDB.rank_color(rank), 6)
	detail_host.add_child(head)
	var hv := HBoxContainer.new()
	hv.add_theme_constant_override("separation", UI.fs(8))
	head.add_child(hv)
	var ic := GeoIcon.new()
	ic.custom_minimum_size = Vector2(UI.px(52), UI.px(52))
	ic.setup(UnitDB.rank_icon(rank), UnitDB.rank_color(rank))
	hv.add_child(ic)
	var ht := VBoxContainer.new()
	ht.add_theme_constant_override("separation", UI.fs(3))
	ht.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.add_child(ht)
	ht.add_child(UIKit.text_label("当前位阶：%s" % UnitDB.rank_name(rank), 16, UnitDB.rank_color(rank)))
	var d := UIKit.dim(UnitDB.rank_desc(rank), 11)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ht.add_child(d)
	ht.add_child(UIKit.text_label("当前属性倍率：×%.2f" % mul, 13,
		UIKit.OK if mul >= 1.0 else UIKit.WARN))
	ht.add_child(UIKit.progress_bar_row(exp, cap, prog, UnitDB.rank_color(rank)))

	detail_host.add_child(UIKit.title("经验来源", 15))
	var eg := UIKit.grid(2, 16, 3)
	detail_host.add_child(eg)
	eg.add_child(UIKit.dim("经验值上限", 12))
	eg.add_child(UIKit.text_label("%d" % cap, 12, UIKit.TEXT))
	eg.add_child(UIKit.dim("周期循环获得", 12))
	eg.add_child(UIKit.text_label("%d / %d（上限 %d）" % [
		int(u.get("exp_from_cycles", 0)), UnitDB.EXP_FROM_CYCLES_CAP, UnitDB.EXP_FROM_CYCLES_CAP], 12, UIKit.TEXT))
	eg.add_child(UIKit.dim("战斗获得", 12))
	eg.add_child(UIKit.text_label("%d" % int(u.get("exp_from_combat", 0)), 12, UIKit.TEXT))

	detail_host.add_child(UIKit.spacer(4))
	detail_host.add_child(UIKit.title("位阶一览", 15))
	var tbl := UIKit.grid(5, 10, 4)
	detail_host.add_child(tbl)
	tbl.add_child(UIKit.dim("位阶", 11))
	tbl.add_child(UIKit.dim("倍率区间", 11))
	tbl.add_child(UIKit.dim("经验上限", 11))
	tbl.add_child(UIKit.dim("周期经验", 11))
	tbl.add_child(UIKit.dim("说明", 11))
	for r in UnitDB.RANK_ORDER:
		var rd: Dictionary = UnitDB.RANKS[r]
		var is_cur := r == rank
		tbl.add_child(UIKit.text_label(UnitDB.rank_name(r), 11,
			UnitDB.rank_color(r) if is_cur else UIKit.TEXT_DIM))
		tbl.add_child(UIKit.text_label("%.1f ~ %.1f" % [float(rd["mul_min"]), float(rd["mul_max"])], 11, UIKit.TEXT))
		tbl.add_child(UIKit.text_label("%d" % int(rd["exp_cap"]), 11, UIKit.TEXT))
		tbl.add_child(UIKit.text_label("≤ %d" % UnitDB.EXP_FROM_CYCLES_CAP, 11, UIKit.TEXT))
		var sd := UIKit.dim(str(rd["desc"]).split("。")[0], 10)
		sd.custom_minimum_size = Vector2(UI.px(240), UI.px(0))
		sd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tbl.add_child(sd)

	detail_host.add_child(UIKit.spacer(6))
	var ops := HBoxContainer.new()
	ops.add_theme_constant_override("separation", UI.fs(6))
	detail_host.add_child(ops)
	var gain := UIKit.small("模拟训练（+15 战斗经验，消耗货币 80）", 12)
	gain.pressed.connect(func() -> void:
		if GameState.res("currency") < 80.0:
			GameState.toast.emit("货币不足")
			return
		GameState.add_res("currency", -80.0)
		var r := GameState.gain_exp(str(u["uid"]), 15, "combat")
		GameState.toast.emit("获得经验 %d（%d/%d）" % [int(r.get("gain", 0)),
			int(r.get("exp", 0)), int(r.get("cap", 0))] if r["ok"] else str(r["why"]))
		refresh())
	ops.add_child(gain)

	var prom := UIKit.small("晋升位阶", 12)
	UIKit.style_button(prom, true)
	if not UnitDB.can_promote(u):
		prom.disabled = true
		if UnitDB.next_rank(rank) == "":
			prom.tooltip_text = "已是最高位阶"
		else:
			prom.tooltip_text = "经验未满（%d/%d）" % [exp, cap]
	prom.pressed.connect(func() -> void:
		var r := GameState.promote_unit(str(u["uid"]))
		if not r["ok"]:
			GameState.toast.emit(str(r["why"]))
		else:
			GameState.toast.emit("%s 晋升为 %s" % [u["name"], UnitDB.rank_name(str(r["rank"]))])
		refresh())
	ops.add_child(prom)


func _build_team(u: Dictionary) -> void:
	var uid := str(u["uid"])
	var cur_team := int(u.get("team", -1))
	var cur_tile := str(u.get("tile", ""))

	# ---- 编队 ----
	detail_host.add_child(UIKit.title("队伍编成（每队最多 %d 个单位）" % UnitDB.UNITS_PER_TEAM, 15))
	var teams: Array = GameState.state["teams"]
	var tg := HBoxContainer.new()
	tg.add_theme_constant_override("separation", UI.fs(6))
	detail_host.add_child(tg)
	for i in teams.size():
		var idx := i
		var team: Dictionary = teams[i]
		var members := GameState.team_units(idx)
		var pane := UIKit.panel(UIKit.BG_PANEL_2,
			UIKit.GOLD if idx == cur_team else UIKit.LINE_SOFT, 6)
		pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tg.add_child(pane)
		var pv := VBoxContainer.new()
		pv.add_theme_constant_override("separation", UI.fs(3))
		pane.add_child(pv)
		pv.add_child(UIKit.text_label("%s（%d/%d）" % [str(team["name"]),
			members.size(), UnitDB.UNITS_PER_TEAM], 13,
			UIKit.GOLD if idx == cur_team else UIKit.TEXT))
		if members.is_empty():
			pv.add_child(UIKit.dim("（空）", 11))
		for m in members:
			var mr := HBoxContainer.new()
			mr.add_theme_constant_override("separation", UI.fs(4))
			pv.add_child(mr)
			var mi := GeoIcon.new()
			mi.custom_minimum_size = Vector2(UI.px(20), UI.px(20))
			mi.setup(UnitDB.profession_icon(str(m.get("profession", ""))),
				UnitDB.profession_color(str(m.get("profession", ""))))
			mr.add_child(mi)
			var ml := UIKit.text_label(str(m["name"]), 11,
				Consts.rarity_color(int(m.get("rarity", 1))))
			ml.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			mr.add_child(ml)
			var x := UIKit.tiny("✕", 10, true)
			x.pressed.connect(func() -> void:
				GameState.remove_from_team(str(m["uid"]))
				refresh())
			mr.add_child(x)
		var join := UIKit.small("加入此队" if idx != cur_team else "退出队伍", 11)
		join.pressed.connect(func() -> void:
			if idx == cur_team:
				GameState.remove_from_team(uid)
			else:
				var r := GameState.assign_team(uid, idx)
				if not r["ok"]:
					GameState.toast.emit(str(r["why"]))
			refresh())
		pv.add_child(join)

	# ---- 派驻 ----
	detail_host.add_child(UIKit.spacer(4))
	detail_host.add_child(UIKit.title("地块派驻（每格最多 %d 个单位）" % UnitDB.UNITS_PER_TILE, 15))
	detail_host.add_child(UIKit.text_label("当前状态：%s" % (
		"驻守 %s" % cur_tile if cur_tile != "" else "未派驻（在营地待命）"), 12,
		UIKit.OK if cur_tile != "" else UIKit.TEXT_DIM))

	var own := GameState.owned_tiles()
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", UI.fs(3))
	detail_host.add_child(list)
	var shown := 0
	for t in own:
		var key := GameState.tile_key(t)
		var on_tile := GameState.units_on_tile(key)
		var is_here := key == cur_tile
		var row := PanelContainer.new()
		UIKit.apply_panel(row, UIKit.BG_PANEL_2, UIKit.GOLD if is_here else UIKit.LINE_SOFT, 5)
		list.add_child(row)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", UI.fs(6))
		row.add_child(h)
		var label := "%s　[%s]　驻军 %d/%d" % [
			str(t.get("name", key)) if str(t.get("name", "")) != "" else key,
			key, on_tile.size(), UnitDB.UNITS_PER_TILE]
		var ll := UIKit.text_label(label, 12, UIKit.TEXT)
		ll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(ll)
		if is_here:
			var wb := UIKit.small("撤回", 11)
			wb.pressed.connect(func() -> void:
				GameState.withdraw_unit(uid)
				refresh())
			h.add_child(wb)
		else:
			var db := UIKit.small("派驻", 11)
			db.disabled = on_tile.size() >= UnitDB.UNITS_PER_TILE
			if db.disabled:
				db.tooltip_text = "该地块已驻满"
			db.pressed.connect(func() -> void:
				var r := GameState.deploy_unit(uid, key)
				if not r["ok"]:
					GameState.toast.emit(str(r["why"]))
				refresh())
			h.add_child(db)
		var names: Array[String] = []
		for m in on_tile:
			names.append(str(m["name"]))
		if not names.is_empty():
			var nl := UIKit.dim("　".join(names), 10)
			nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(nl)
		shown += 1
	if shown == 0:
		list.add_child(UIKit.dim("你还没有任何领地。"))


# ---------------------------------------------------------------------------
# 辅助
# ---------------------------------------------------------------------------
func _find_equipment(id: String) -> Dictionary:
	for e in GameState.state["equipment"]:
		if str(e["id"]) == id:
			return e
	return {}


func _auto_equip(u: Dictionary) -> void:
	var pool: Array = GameState.state["equipment"]
	if pool.is_empty():
		GameState.toast.emit("还没有任何装备，去召唤吧")
		return
	var pick: Dictionary = pool[randi() % pool.size()]
	var eq: Dictionary = u.get("equipped", {"weapon": "", "relic": ""})
	eq[str(pick.get("slot", "weapon"))] = str(pick["id"])
	u["equipped"] = eq
	GameState.toast.emit("%s 装备了 %s" % [u["name"], pick["name"]])
	refresh()


func on_cycle_finished(_rep: Dictionary) -> void:
	refresh()