extends Control
## 【世界泡】页：召唤 / 打捞 / 发展 三个子系统。
## v1.5：对应设计文档「召唤系统与客人公民」章节，含稳定度与无主地块限制、保底、以及三种世界威胁生成。

## v1.5：把「抽卡」重做成有世界观的「世界泡系统」，三个子系统各有自己的名字与动作词。
## 母题：召唤 / 打捞 / 创造 都是这个文明对自身行为的美化，本质都是「世界泡」。
const POOLS := [
	{"id": "rotation", "name": "召唤", "enum": 0,
		"title": "召唤系统", "verb": "召唤", "result": "召唤结果"},
	{"id": "resource", "name": "打捞", "enum": 1,
		"title": "打捞系统", "verb": "打捞", "result": "打捞结果"},
	{"id": "development", "name": "发展", "enum": 2,
		"title": "发展系统", "verb": "创造", "result": "创造结果"},
]

var pool_bar: HBoxContainer
var title_label: Label
var result_title: Label
var draw_row: HBoxContainer
var pool := 0
var cost_label: Label
var pity_label: Label
var rule_box: RichTextLabel
var limit_label: Label
var group_label: Label
var result_box: HBoxContainer
var stats_box: VBoxContainer
var _rng := RandomNumberGenerator.new()
var last_cards: Array = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_rng.randomize()
	_build()
	refresh()


func _build() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", UI.fs(6))
	add_child(root)

	var head := UIKit.hbox(10)
	root.add_child(head)
	title_label = UIKit.title("召唤系统", 20)
	head.add_child(title_label)
	group_label = UIKit.dim("")
	head.add_child(group_label)
	var rotate := UIKit.small("手动轮换卡组（免费 1 次 / 周期）", 12)
	rotate.pressed.connect(_rotate_group)
	head.add_child(rotate)

	# 二级按钮
	pool_bar = HBoxContainer.new()
	pool_bar.add_theme_constant_override("separation", UI.fs(6))
	root.add_child(pool_bar)
	for p in POOLS:
		var pe: int = int(p["enum"])
		var b := UIKit.normal(str(p["name"]), 15)
		b.custom_minimum_size = Vector2(UI.px(140), UI.px(36))
		b.pressed.connect(func() -> void:
			pool = pe
			refresh())
		pool_bar.add_child(b)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", UI.fs(6))
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	# ---- 左：卡池说明 ----
	var left := UIKit.panel()
	left.custom_minimum_size = Vector2(UI.px(430), UI.px(0))
	body.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", UI.fs(6))
	left.add_child(lv)
	lv.add_child(UIKit.title("卡池规则", 16))
	var rule_scroll := ScrollContainer.new()
	rule_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rule_scroll.custom_minimum_size = Vector2(UI.px(400), UI.px(240))
	rule_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lv.add_child(rule_scroll)
	rule_box = RichTextLabel.new()
	rule_box.bbcode_enabled = true
	rule_box.fit_content = true
	rule_box.scroll_active = false
	rule_box.custom_minimum_size = Vector2(UI.px(0), UI.px(0))
	rule_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule_box.add_theme_font_size_override("normal_font_size", UI.fs(12))
	rule_scroll.add_child(rule_box)

	cost_label = UIKit.text_label("消耗：--", 14, UIKit.GOLD)
	lv.add_child(cost_label)
	pity_label = UIKit.text_label("保底：--", 12, UIKit.TEXT_DIM)
	lv.add_child(pity_label)
	limit_label = UIKit.text_label("", 12, UIKit.WARN)
	limit_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lv.add_child(limit_label)

	lv.add_child(UIKit.spacer(8))
	draw_row = UIKit.hbox(8)
	lv.add_child(draw_row)

	lv.add_child(UIKit.spacer(6))
	lv.add_child(UIKit.title("货币来源", 14))
	var src := UIKit.dim(
		"秩序结晶：根据玩家等级每周期结算给予。\n" +
		"稳定度：由世界占领情况计算，部分子系统的操作会消耗它（本 Demo 简化为不直接消耗）。\n" +
		"凝聚力：根据民众幸福程度（数值）与文化率（倍率）结算。", 11)
	src.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lv.add_child(src)

	# ---- 右：结果 + 统计 ----
	var right := UIKit.panel()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", UI.fs(6))
	right.add_child(rv)
	result_title = UIKit.title("本次召唤结果", 16)
	rv.add_child(result_title)
	result_box = HBoxContainer.new()
	result_box.add_theme_constant_override("separation", UI.fs(6))
	result_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	rv.add_child(result_box)

	rv.add_child(UIKit.spacer(8))
	rv.add_child(UIKit.title("统计", 16))
	stats_box = VBoxContainer.new()
	stats_box.add_theme_constant_override("separation", UI.fs(3))
	var stats_scroll := UIKit.scroll(stats_box)
	stats_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rv.add_child(stats_scroll)

	refresh()


# ---------------------------------------------------------------------------
# 刷新
# ---------------------------------------------------------------------------
func refresh() -> void:
	if not is_instance_valid(pool_bar):
		return
	_refresh_bar()
	var pe: int = pool
	title_label.text = str(POOLS[pe]["title"])
	result_title.text = "本次%s结果" % str(POOLS[pe]["verb"])
	group_label.text = "当前卡组：%s（影响打捞系统能捞到的高级材料）" % str(GameState.state.get("active_group", ""))
	_refresh_draw_buttons()

	match pe:
		0:
			cost_label.text = "消耗：%s × %.0f" % [Consts.res_name("cohesion"), Consts.DRAW_COST_COHESION]
			rule_box.text = "[b][color=#edc96b]召唤系统[/color][/b]\n" + \
				"· 我们所在的世界泡漂浮在量子之海中，当前卡组就是 [b]相对最近的世界泡[/b]。\n" + \
				"· 消耗 [color=#f59abf]凝聚力[/color] 召唤，唤来 [b]角色[/b] 与 [b]装备[/b]——有时是个体过来，有时是被遗弃的装备过来。\n" + \
				"· 附近的世界泡大多已濒临末日，[b]所以受召唤者往往愿意留下[/b]——留下，比回去强。\n" + \
				"· 善意与敌意一同到来：敌意者并非召唤的目标，只能寻找机会和漏洞挤进来，因此是 [b]概率性[/b] 降临。\n" + \
				"· 每次召唤都有概率在大世界生成 [color=#eb6166]游荡敌人[/color]，次数越多概率越高，生成后重置；累计 %d 次后必出一次 [color=#eb6166]高危游荡敌人[/color]。\n" % Consts.WANDER_PITY + \
				"· 在特定卡组之间轮换（%s）。" % " / ".join(CardDB.CIV_GROUPS)
		1:
			cost_label.text = "消耗：%s × %.0f" % [Consts.res_name("order_crystal"), Consts.DRAW_COST_CRYSTAL]
			rule_box.text = "[b][color=#edc96b]打捞系统[/color][/b]\n" + \
				"· 从量子之海中汲取混沌的物质。我们不可能事先知晓混沌的构成（否则那就不叫混沌了），只有取出并凝结之后，才知道捞到了什么。\n" + \
				"· 消耗 [color=#b79aee]秩序结晶[/color] 打捞，捞上来 [b]材料[/b]、[b]资源[/b] 与 [b]道具[/b]；有时甚至是珍贵的成品道具。\n" + \
				"· 但直接从量子之海汲取、而不是从邻近世界泡召唤，就意味着更容易被盯上——[b]一旦被入侵，就是据点形式[/b]。\n" + \
				"· 每次打捞都有较大概率生成 [color=#eb6166]高危据点[/color]；累计 %d 次后必出一次 [color=#eb6166]极度高危据点[/color]。\n" % Consts.HAZARD_PITY + \
				"· 某个组内角色的高级材料，只有轮换到该组期间才能捞到；打捞所得不会在大世界生成可再生资源点。"
		_:
			cost_label.text = "消耗：无（但必定生成终极威胁）"
			rule_box.text = "[b][color=#edc96b]发展系统[/color][/b]\n" + \
				"· 直接把一整片世界泡包裹进来。于是世界上就会多出一处大型矿脉，或一处产出很高的原油层。\n" + \
				"· 此处不消耗货币，但风险极高：[b]几乎必然会把敌人也一并包进来[/b]——每次都会生成 [color=#eb6166]终极威胁[/color]。\n" + \
				"· 不对它做任何限制 —— 或者说，终极威胁本身就是限制。（这个文明把这种冒进称作「创造」。）\n" + \
				"· 可以抽到很多功能，例如「资源地脉」：让原本只能靠打捞获取的材料，在世界发展中自然、可再生的获取。\n" + \
				"· 也可以抽到「创世结晶」，作为原神科技树「七神时代」的前置。"

	var limit := Gacha.check(GameState.state, pe)
	if limit["ok"]:
		limit_label.text = "✔ 当前可以进行世界泡操作（稳定度 %.0f%%，无主地块 %d）" % [
			GameState.stability() * 100.0, TileManager.free_tiles(GameState.state).size()]
		limit_label.add_theme_color_override("font_color", UIKit.OK)
	else:
		limit_label.text = "✖ " + str(limit["why"])
		limit_label.add_theme_color_override("font_color", UIKit.BAD)

	pity_label.text = "保底：" + Gacha.pity_text(GameState.state, pe)

	_refresh_result()
	_refresh_stats()


## v1.5：动作按钮按池变化 —— 召唤 / 打捞 有「1 次」与「10 次」；发展只有一个「创造」
func _refresh_draw_buttons() -> void:
	if not is_instance_valid(draw_row):
		return
	for c in draw_row.get_children():
		c.queue_free()
	var verb := str(POOLS[pool]["verb"])
	if str(POOLS[pool]["id"]) == "development":
		var only := UIKit.primary(verb, 16)
		only.custom_minimum_size = Vector2(UI.px(150), UI.px(40))
		only.tooltip_text = "把一整片世界泡包裹进来（必定引来终极威胁）"
		only.pressed.connect(func() -> void: _do_draw(1))
		draw_row.add_child(only)
		return
	var b1 := UIKit.primary("%s 1 次" % verb, 16)
	b1.custom_minimum_size = Vector2(UI.px(150), UI.px(40))
	b1.pressed.connect(func() -> void: _do_draw(1))
	draw_row.add_child(b1)
	var b10 := UIKit.primary("%s 10 次" % verb, 16)
	b10.custom_minimum_size = Vector2(UI.px(150), UI.px(40))
	b10.pressed.connect(func() -> void: _do_draw(10))
	draw_row.add_child(b10)


func _refresh_bar() -> void:
	var i := 0
	for c in pool_bar.get_children():
		if c is Button:
			var active: bool = int(POOLS[i]["enum"]) == pool
			UIKit.style_button(c as Button, active)
			(c as Button).add_theme_color_override("font_color", UIKit.GOLD if active else UIKit.TEXT)
			i += 1


func _refresh_result() -> void:
	for c in result_box.get_children():
		c.queue_free()
	if last_cards.is_empty():
		result_box.add_child(UIKit.dim("还没有世界泡记录，点左边的按钮试试。"))
		return
	for card in last_cards:
		result_box.add_child(UIKit.card_button(card, 96, 124))


func _refresh_stats() -> void:
	for c in stats_box.get_children():
		c.queue_free()
	var s := GameState.state
	stats_box.add_child(UIKit.dim("角色 %d 名｜装备 %d 件｜道具 %d 种｜终极威胁 %d 个" % [
		(s["units"] as Array).size(), (s["equipment"] as Array).size(),
		(s["items"] as Dictionary).size(), (s["threats"] as Array).size()], 12))
	var aff: Dictionary = s["affinity"]
	var parts: Array[String] = []
	for g in aff.keys():
		parts.append("%s %d" % [g, int(aff[g])])
	stats_box.add_child(UIKit.dim("卡组抽取次数：" + "　".join(parts), 12))
	# 按稀有度统计
	var by_r := {}
	for c in s["units"]:
		var r := int(c["rarity"])
		by_r[r] = int(by_r.get(r, 0)) + 1
	var rparts: Array[String] = []
	var keys := by_r.keys()
	keys.sort()
	keys.reverse()
	for k in keys:
		rparts.append("%d★×%d" % [k, int(by_r[k])])
	stats_box.add_child(UIKit.dim("单位稀有度分布：" + ("　".join(rparts) if not rparts.is_empty() else "无"), 12))
	# v1.1：职业分布
	var by_prof := {}
	for c2 in s["units"]:
		var pn := UnitDB.profession_name(str(c2.get("profession", "")))
		by_prof[pn] = int(by_prof.get(pn, 0)) + 1
	var pparts: Array[String] = []
	for p in UnitDB.PROFESSION_ORDER:
		pparts.append("%s×%d" % [UnitDB.profession_name(p), int(by_prof.get(UnitDB.profession_name(p), 0))])
	stats_box.add_child(UIKit.dim("职业分布：" + "　".join(pparts), 12))

	var hz: Dictionary = s["hazard"]
	var wd: Dictionary = s["wander"]
	stats_box.add_child(UIKit.dim("危险据点累计 %d 次（距极度危险还差 %d）｜游荡敌人累计 %d 次（距高危还差 %d）" % [
		int(hz.get("count", 0)), Consts.HAZARD_PITY - int(hz.get("pity", 0)),
		int(wd.get("count", 0)), Consts.WANDER_PITY - int(wd.get("pity", 0))], 11))


# ---------------------------------------------------------------------------
# 抽卡动作
# ---------------------------------------------------------------------------
func _do_draw(times: int) -> void:
	var r: Dictionary
	if times == 1:
		r = Gacha.draw(GameState.state, pool, _rng)
	else:
		r = Gacha.draw_ten(GameState.state, pool, _rng)
	if not r["ok"]:
		GameState.toast.emit(str(r["why"]))
		refresh()
		return
	last_cards = r["cards"]
	_refresh_result()
	GameState.state_changed.emit()
	_show_result_dialog(r)


func _show_result_dialog(r: Dictionary) -> void:
	var gs := UIKit.game_screen_of(self)
	if gs == null:
		return
	var v := UIKit.vbox(8)

	var cards: Array = r["cards"]
	if not cards.is_empty():
		var g := UIKit.grid(5, 6, 6)
		for c in cards:
			g.add_child(UIKit.card_button(c, 92, 118))
		v.add_child(g)

	var events: Array = r["events"]
	if not events.is_empty():
		v.add_child(UIKit.text_label("世界事件", 14, UIKit.WARN))
		for e in events:
			var l := UIKit.text_label("· " + str(e), 12, UIKit.WARN)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v.add_child(l)

	var stats := _rarity_summary(cards)
	v.add_child(UIKit.dim(stats, 12))

	var close := UIKit.primary("确定", 15)
	close.pressed.connect(func() -> void: gs.close_dialog())
	v.add_child(close)

	var d := UIKit.dialog(str(POOLS[pool]["result"]), 700.0)
	d.set_content(v)
	gs.open_dialog(d)


func _rarity_summary(cards: Array) -> String:
	var by_r := {}
	for c in cards:
		var rr := int(c["rarity"])
		by_r[rr] = int(by_r.get(rr, 0)) + 1
	var parts: Array[String] = []
	var keys := by_r.keys()
	keys.sort()
	keys.reverse()
	for k in keys:
		parts.append("%d★ × %d" % [k, int(by_r[k])])
	var best := 0
	for c in cards:
		best = maxi(best, int(c["rarity"]))
	return "共 %d 张：%s%s" % [cards.size(), "　".join(parts),
		"　★ 最高稀有度 %d★" % best if best >= 5 else ""]


func _rotate_group() -> void:
	var nxt := Gacha.rotate_group(GameState.state, _rng)
	GameState.toast.emit("卡组已轮换为：%s" % nxt)
	GameState.state_changed.emit()
	refresh()


func on_cycle_finished(_rep: Dictionary) -> void:
	refresh()