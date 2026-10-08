extends Control
## 图鉴页（v1.1 重构版）
##
## v1.1 更新指导：
##   · 新增二级分类「文明组」：提瓦特 / 绝区零 / 崩坏本征
##   · 原来的「二级分类」更名为「稀有度」
##   · 文明组与稀有度两个二级分类可以同时共存
##   · 「名词」分类已移出图鉴，迁到新的「手册」子系统

## 每个一级分类下的分组化二级按钮
const CATEGORIES := [
	{
		"id": "character", "name": "角色",
		"groups": [
			{"key": "civ", "title": "文明组", "options": [["all", "全部"], ["提瓦特", "提瓦特"], ["绝区零", "绝区零"], ["崩坏本征", "崩坏本征"]]},
			{"key": "rarity", "title": "稀有度", "options": [["all", "全部"], ["5", "5★"], ["4", "4★"], ["3", "3★"], ["2", "2★"], ["1", "1★"]]},
		],
	},
	{
		"id": "weapon", "name": "武装",
		"groups": [
			{"key": "civ", "title": "文明组", "options": [["all", "全部"], ["提瓦特", "提瓦特"], ["绝区零", "绝区零"], ["崩坏本征", "崩坏本征"]]},
			{"key": "rarity", "title": "稀有度", "options": [["all", "全部"], ["5", "5★"], ["4", "4★"], ["3", "3★"], ["2", "2★"], ["1", "1★"]]},
		],
	},
	{
		"id": "relic", "name": "战备",
		"groups": [
			{"key": "civ", "title": "文明组", "options": [["all", "全部"], ["提瓦特", "提瓦特"], ["绝区零", "绝区零"], ["崩坏本征", "崩坏本征"]]},
			{"key": "rarity", "title": "稀有度", "options": [["all", "全部"], ["5", "5★"], ["4", "4★"], ["3", "3★"], ["2", "2★"], ["1", "1★"]]},
		],
	},
	{
		"id": "material", "name": "材料",
		"groups": [
			{"key": "civ", "title": "文明组", "options": [["all", "全部"], ["提瓦特", "提瓦特"], ["绝区零", "绝区零"], ["崩坏本征", "崩坏本征"]]},
			{"key": "rarity", "title": "稀有度", "options": [["all", "全部"], ["5", "5★"], ["4", "4★"], ["3", "3★"], ["2", "2★"], ["1", "1★"]]},
			{"key": "tier", "title": "材料档位", "options": [["all", "全部"], ["basic", "基础"], ["advanced", "高级"]]},
		],
	},
	{
		"id": "item", "name": "道具",
		"groups": [
			{"key": "rarity", "title": "稀有度", "options": [["all", "全部"], ["5", "5★"], ["4", "4★"], ["3", "3★"], ["2", "2★"], ["1", "1★"]]},
		],
	},
	{
		"id": "function", "name": "功能",
		"groups": [
			{"key": "rarity", "title": "稀有度", "options": [["all", "全部"], ["5", "5★"], ["4", "4★"], ["3", "3★"]]},
		],
	},
	{
		"id": "profession", "name": "职业",
		"groups": [
			{"key": "prof", "title": "职业类型", "options": [["all", "全部"], ["melee", "近身战士"], ["ranged", "远身战士"], ["projectile", "投射者"], ["defender", "防御者"], ["support", "支援者"]]},
		],
	},
]

var cat_bar: VBoxContainer
var sub_area: VBoxContainer
var content_box: VBoxContainer
var content_title: Label
var cat := "character"
## 每个分组当前的选中值：{ "civ": "all", "rarity": "all" }
var picks: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	refresh()


func _build() -> void:
	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	# 左：一级分类 + 分组化二级分类
	var left := UIKit.panel()
	left.custom_minimum_size = Vector2(210, 0)
	root.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 4)
	left.add_child(lv)
	lv.add_child(UIKit.title("一级分类", 14))
	cat_bar = VBoxContainer.new()
	cat_bar.add_theme_constant_override("separation", 3)
	lv.add_child(cat_bar)
	lv.add_child(UIKit.spacer(6))

	sub_area = VBoxContainer.new()
	sub_area.add_theme_constant_override("separation", 4)
	lv.add_child(UIKit.scroll(sub_area))

	# 右：内容
	var right := UIKit.panel()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 6)
	right.add_child(rv)
	content_title = UIKit.title("图鉴内容", 16)
	rv.add_child(content_title)
	content_box = VBoxContainer.new()
	content_box.add_theme_constant_override("separation", 6)
	rv.add_child(UIKit.scroll(content_box))

	_build_cats()
	refresh()


func _build_cats() -> void:
	for c in cat_bar.get_children():
		c.queue_free()
	for c in CATEGORIES:
		var cid: String = c["id"]
		var b := UIKit.small(str(c["name"]), 13)
		b.pressed.connect(func() -> void:
			cat = cid
			picks = {}
			refresh())
		cat_bar.add_child(b)


func _current_cat() -> Dictionary:
	for c in CATEGORIES:
		if c["id"] == cat:
			return c
	return {}


func _pick(key: String) -> String:
	return str(picks.get(key, "all"))


# ---------------------------------------------------------------------------
# 刷新
# ---------------------------------------------------------------------------
func refresh() -> void:
	if not is_instance_valid(content_box):
		return
	# 一级分类高亮
	var i := 0
	for c in cat_bar.get_children():
		if c is Button:
			var active: bool = CATEGORIES[i]["id"] == cat
			UIKit.style_button(c as Button, active)
			(c as Button).add_theme_color_override("font_color", UIKit.GOLD if active else UIKit.TEXT)
			i += 1

	# 二级分类：每个分组各占一块，互不冲突，可以同时生效
	for c2 in sub_area.get_children():
		c2.queue_free()
	for g in _current_cat().get("groups", []):
		var gkey: String = g["key"]
		var gl := UIKit.text_label(str(g["title"]), 12, UIKit.GOLD)
		sub_area.add_child(gl)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 3)
		sub_area.add_child(row)
		for opt in g["options"]:
			var oval: String = opt[0]
			var b := UIKit.tiny(str(opt[1]), 11)
			b.custom_minimum_size = Vector2(0, 24)
			UIKit.style_button(b, oval == _pick(gkey))
			b.pressed.connect(func() -> void:
				picks[gkey] = oval
				refresh())
			row.add_child(b)

	for c3 in content_box.get_children():
		c3.queue_free()

	if cat == "profession":
		_profession_content()
		return

	var cards := _cards_for_cat()
	var owned := _owned_counts()
	content_title.text = "图鉴内容 · %s" % _filter_desc()
	var g := UIKit.grid(6, 6, 6)
	content_box.add_child(g)
	var unlocked := 0
	for card in cards:
		var cnt := int(owned.get(str(card["id"]), 0))
		var is_unlocked := cnt > 0
		if is_unlocked:
			unlocked += 1
		var holder := UIKit.card_button(card, 104, 138)
		if not is_unlocked:
			holder.modulate = Color(0.34, 0.34, 0.38, 0.9)
			var v := UIKit.vbox(0)
			var tag := UIKit.text_label("未解锁", 10, UIKit.TEXT_FAINT)
			tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			v.add_child(tag)
			holder.add_child(v)
		else:
			var v2 := UIKit.vbox(0)
			var tag2 := UIKit.text_label("持有 %d" % cnt, 10, UIKit.OK)
			tag2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			v2.add_child(tag2)
			holder.add_child(v2)
		# 文明组标记
		var civ := CardDB.civ_group_of(card)
		if civ != "":
			var cv := UIKit.vbox(0)
			var cl := UIKit.text_label(civ, 9, _civ_color(civ))
			cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cv.add_child(cl)
			holder.add_child(cv)
		g.add_child(holder)

	content_box.add_child(UIKit.spacer(4))
	content_box.add_child(UIKit.dim("该筛选结果共 %d 项，已解锁 %d 项。" % [cards.size(), unlocked], 12))
	var hint := UIKit.dim("提示：文明组与稀有度是两个独立的二级分类，可以同时生效（例如「提瓦特 + 4★」）。", 11)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content_box.add_child(hint)


func _filter_desc() -> String:
	var parts: Array[String] = []
	for g in _current_cat().get("groups", []):
		var v := _pick(str(g["key"]))
		if v == "all":
			continue
		var label := v
		for opt in g["options"]:
			if str(opt[0]) == v:
				label = str(opt[1])
		parts.append("%s=%s" % [str(g["title"]), label])
	if parts.is_empty():
		return "全部"
	return "　".join(parts)


static func _civ_color(civ: String) -> Color:
	match civ:
		"提瓦特": return Color(0.55, 0.85, 0.75)
		"绝区零": return Color(0.95, 0.78, 0.35)
		"崩坏本征": return Color(0.85, 0.55, 0.95)
		_: return UIKit.TEXT_DIM


func _cards_for_cat() -> Array:
	var out: Array = []
	for c in GameState.cards:
		var pool: String = str(c["pool"])
		var match_cat := false
		if cat == "character" and pool == "character":
			match_cat = true
		elif cat == "weapon" and pool == "weapon":
			match_cat = true
		elif cat == "relic" and pool == "relic":
			match_cat = true
		elif cat == "material" and pool in ["material", "advanced"]:
			match_cat = true
		elif cat == "item" and pool == "item":
			match_cat = true
		elif cat == "function" and pool == "function":
			match_cat = true
		if not match_cat:
			continue

		# 多个二级分类同时生效
		var ok := true
		for g in _current_cat().get("groups", []):
			var gkey: String = g["key"]
			var pick := _pick(gkey)
			if pick == "all":
				continue
			match gkey:
				"civ":
					if CardDB.civ_group_of(c) != pick:
						ok = false
				"rarity":
					if str(int(c["rarity"])) != pick:
						ok = false
				"tier":
					if pick == "basic" and pool != "material":
						ok = false
					if pick == "advanced" and pool != "advanced":
						ok = false
				_:
					pass
			if not ok:
				break
		if ok:
			out.append(c)
	return out


func _owned_counts() -> Dictionary:
	var out := {}
	for u in GameState.state["units"]:
		var id := str(u["id"])
		out[id] = int(out.get(id, 0)) + 1
	for e in GameState.state["equipment"]:
		var id2 := str(e["id"])
		out[id2] = int(out.get(id2, 0)) + 1
	var items: Dictionary = GameState.state["items"]
	for k in items.keys():
		out[k] = int(out.get(k, 0)) + int(items[k])
	return out


# ---------------------------------------------------------------------------
# 职业图鉴（v1.1）
# ---------------------------------------------------------------------------
func _profession_content() -> void:
	content_title.text = "图鉴内容 · 职业"
	var pick := _pick("prof")
	var v := UIKit.vbox(6)
	content_box.add_child(v)
	for p in UnitDB.PROFESSION_ORDER:
		if pick != "all" and pick != p:
			continue
		v.add_child(_profession_card(p))
	v.add_child(UIKit.spacer(4))
	v.add_child(UIKit.title("位阶一览", 15))
	var tbl := UIKit.grid(4, 12, 4)
	content_box.add_child(tbl)
	tbl.add_child(UIKit.dim("位阶", 11))
	tbl.add_child(UIKit.dim("属性倍率", 11))
	tbl.add_child(UIKit.dim("经验上限", 11))
	tbl.add_child(UIKit.dim("说明", 11))
	for r in UnitDB.RANK_ORDER:
		var rd: Dictionary = UnitDB.RANKS[r]
		tbl.add_child(UIKit.text_label(UnitDB.rank_name(r), 12, UnitDB.rank_color(r)))
		tbl.add_child(UIKit.text_label("%.1f ~ %.1f" % [float(rd["mul_min"]), float(rd["mul_max"])], 12, UIKit.TEXT))
		tbl.add_child(UIKit.text_label("%d" % int(rd["exp_cap"]), 12, UIKit.TEXT))
		var sd := UIKit.dim(str(rd["desc"]), 10)
		sd.custom_minimum_size = Vector2(300, 0)
		sd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tbl.add_child(sd)


func _profession_card(p: String) -> Control:
	var col := UnitDB.profession_color(p)
	var row := UIKit.panel(UIKit.BG_PANEL_2, col, 6)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	row.add_child(h)
	var ic := GeoIcon.new()
	ic.custom_minimum_size = Vector2(62, 62)
	ic.setup(UnitDB.profession_icon(p), col)
	h.add_child(ic)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	v.add_child(UIKit.text_label(UnitDB.profession_name(p), 16, col))
	var d := UIKit.dim((UnitDB.PROFESSIONS[p] as Dictionary)["desc"], 11)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(d)

	# 克制与被克制
	var counters: Array = (UnitDB.PROFESSIONS[p] as Dictionary).get("counters", [])
	var cnames: Array[String] = []
	for c in counters:
		cnames.append(UnitDB.profession_name(str(c)))
	var countered_by: Array[String] = []
	for q in UnitDB.PROFESSION_ORDER:
		if UnitDB.counters(q, p) and q != p:
			countered_by.append(UnitDB.profession_name(q))
	var rng := int((UnitDB.PROFESSIONS[p] as Dictionary).get("range", 1))
	if not cnames.is_empty():
		v.add_child(UIKit.text_label("克制：%s（伤害 +30%%）" % "、".join(cnames), 11, UIKit.OK))
	if not countered_by.is_empty():
		v.add_child(UIKit.text_label("被克制：%s（伤害 −20%%）" % "、".join(countered_by), 11, UIKit.BAD))
	v.add_child(UIKit.dim("攻击距离：%d 格%s" % [rng, "（可以隔一格攻击）" if rng >= 2 else ""], 11))

	# 该职业的单位数量
	var n := 0
	for u in GameState.state["units"]:
		if str(u.get("profession", "")) == p:
			n += 1
	v.add_child(UIKit.text_label("我方持有该职业单位：%d 个" % n, 11,
		UIKit.OK if n > 0 else UIKit.TEXT_FAINT))
	return row


func on_cycle_finished(_rep: Dictionary) -> void:
	refresh()
