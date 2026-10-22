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
		# 1.8.21.2：原来写「在「管理」里招募募集兵」—— 管理入口 v1.8.7 已删、
		# 征兵 v1.8.3 就搬进「政事」了，照它走是死路。
		list_box.add_child(UIKit.dim("这里还没有单位。\n去「世界泡 → 召唤系统」召唤角色，\n或在据点管理窗口的「政事」里征兵。"))
		return
	for u in units:
		list_box.add_child(_unit_row(u))
	if selected_id == "" or Units.unit_by_uid(GameState.state, selected_id).is_empty():
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
	return Units.unit_by_uid(GameState.state, selected_id)


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
		var r := Units.begin_recruit(GameState.state, uid)
		if not bool(r["ok"]):
			GameState.toast.emit(str(r["why"]))
			return
		GameState.toast.emit("请在世界系统中点选要部署的领地，再点「确认招募」")
		_go_world())
	status_actions.add_child(b_recruit)

	var b_dismiss := UIKit.normal("遣返", 13)
	b_dismiss.tooltip_text = "把他送回自己的世界（从库存中移除）"
	b_dismiss.pressed.connect(func() -> void:
		var r := Units.dismiss_guest(GameState.state, uid)
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
		"skill":
			load("res://scripts/ui/views/parts/treasure_character/skill.gd").build(detail_host, u, refresh)
		"profession":
			load("res://scripts/ui/views/parts/treasure_character/profession.gd").build(detail_host, u, refresh)
		"rank":
			load("res://scripts/ui/views/parts/treasure_character/rank.gd").build(detail_host, u, refresh)
		"team":
			load("res://scripts/ui/views/parts/treasure_character/team.gd").build(detail_host, u, refresh)
		_: CharacterMain.build(detail_host, u, refresh)

# ---------------------------------------------------------------------------
# 辅助
# ---------------------------------------------------------------------------

func on_cycle_finished(_rep: Dictionary) -> void:
	refresh()
