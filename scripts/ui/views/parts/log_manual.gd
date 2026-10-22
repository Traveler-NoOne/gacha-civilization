extends Control
## 手册子系统（v1.1 新增，日志的第四个子页面）
##
## v1.1 更新指导：日志系统中增加一个手册子系统，是「任务、记录、图鉴」之后的第四个页面。
## 同时「名词」分类移动到手册子系统中，手册专门作为对专有名词和世界观设定进行解释的设定集。

var group_bar: VBoxContainer
var term_list: VBoxContainer
var detail_box: VBoxContainer
var search_edit: LineEdit
var count_label: Label
var current_group := "全部"
var selected_term := ""
var keyword := ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	refresh()


func _build() -> void:
	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", UI.fs(6))
	add_child(root)

	# ---- 左：分组 + 条目列表 ----
	var left := UIKit.panel()
	left.custom_minimum_size = Vector2(UI.px(280), UI.px(0))
	root.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", UI.fs(4))
	left.add_child(lv)
	lv.add_child(UIKit.title("手册 · 目录", 16))

	search_edit = LineEdit.new()
	search_edit.placeholder_text = "搜索名词…"
	search_edit.text_changed.connect(func(t: String) -> void:
		keyword = t.strip_edges()
		refresh())
	lv.add_child(search_edit)

	group_bar = VBoxContainer.new()
	group_bar.add_theme_constant_override("separation", UI.fs(3))
	lv.add_child(group_bar)

	count_label = UIKit.dim("")
	lv.add_child(count_label)

	term_list = VBoxContainer.new()
	term_list.add_theme_constant_override("separation", UI.fs(2))
	lv.add_child(UIKit.scroll(term_list))

	# ---- 右：条目正文 ----
	var right := UIKit.panel()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(right)
	detail_box = VBoxContainer.new()
	detail_box.add_theme_constant_override("separation", UI.fs(6))
	right.add_child(UIKit.scroll(detail_box))


func _all_terms() -> Array:
	var out: Array = TermDB.all()
	if keyword == "":
		return out
	var kw := keyword.to_lower()
	var filtered: Array = []
	for t in out:
		if str(t["name"]).to_lower().contains(kw) or str(t["text"]).to_lower().contains(kw) \
				or str(t["group"]).to_lower().contains(kw):
			filtered.append(t)
	return filtered


func _refresh_groups() -> void:
	for c in group_bar.get_children():
		c.queue_free()
	var groups: Array[String] = ["全部"]
	groups.append_array(TermDB.groups())
	for g in groups:
		var b := UIKit.small(g, 12)
		var active: bool = g == current_group
		UIKit.style_button(b, active)
		b.add_theme_color_override("font_color", Palette.GOLD if active else Palette.TEXT)
		b.pressed.connect(func() -> void:
			current_group = g
			selected_term = ""
			refresh())
		group_bar.add_child(b)


func refresh() -> void:
	if not is_instance_valid(term_list):
		return
	_refresh_groups()

	# 列表
	for c in term_list.get_children():
		c.queue_free()
	var terms := _all_terms()
	var shown := 0
	for t in terms:
		if current_group != "全部" and str(t["group"]) != current_group:
			continue
		shown += 1
		var b := UIKit.small(str(t["name"]), 12)
		if str(t["name"]) == selected_term:
			UIKit.style_button(b, true)
			b.add_theme_color_override("font_color", Palette.GOLD)
		b.pressed.connect(func() -> void:
			selected_term = str(t["name"])
			refresh())
		term_list.add_child(b)
	count_label.text = "共 %d 条名词%s" % [shown, "（已按关键词筛选）" if keyword != "" else ""]

	# 正文
	for c2 in detail_box.get_children():
		c2.queue_free()
	if selected_term != "":
		_render_term(selected_term)
	elif keyword != "":
		detail_box.add_child(UIKit.title("搜索结果", 16))
		detail_box.add_child(UIKit.dim("关键词「%s」命中 %d 条，点击左侧条目查看详情。" % [keyword, shown]))
		for t2 in terms:
			if current_group != "全部" and str(t2["group"]) != current_group:
				continue
			detail_box.add_child(_preview(t2))
	else:
		detail_box.add_child(UIKit.title("手册", 18))
		var intro := UIKit.dim(
			"这里是对专有名词和世界观设定的解释设定集。\n" +
			"名词分类原本属于图鉴，v1.1 更新后移动到了这里。\n\n" +
			"从左侧选择分组，或直接搜索关键词。", 12)
		intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail_box.add_child(intro)
		detail_box.add_child(UIKit.spacer(4))
		for t3 in terms:
			if current_group != "全部" and str(t3["group"]) != current_group:
				continue
			detail_box.add_child(_preview(t3))


func _preview(t: Dictionary) -> Control:
	var p := UIKit.panel(Palette.BG_PANEL_2, Palette.LINE_SOFT, 5)
	var v := UIKit.vbox(2)
	p.add_child(v)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", UI.fs(6))
	v.add_child(h)
	h.add_child(UIKit.text_label(str(t["name"]), 13, Palette.GOLD))
	h.add_child(UIKit.dim(str(t["group"]), 10))
	var d := UIKit.dim(str(t["text"]), 11)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(d)
	return p


func _render_term(name: String) -> void:
	var term: Dictionary = {}
	for t in TermDB.all():
		if str(t["name"]) == name:
			term = t
			break
	if term.is_empty():
		detail_box.add_child(UIKit.dim("找不到该条目。"))
		return
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UI.fs(8))
	detail_box.add_child(head)
	head.add_child(UIKit.title(str(term["name"]), 20))
	head.add_child(UIKit.dim("分类：%s" % str(term["group"]), 12))
	var body := UIKit.panel(Palette.BG_PANEL_2, Palette.GOLD, 6)
	detail_box.add_child(body)
	var bv := VBoxContainer.new()
	body.add_child(bv)
	var txt := UIKit.text_label(str(term["text"]), 13)
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bv.add_child(txt)

	# 同分类的其他条目
	var siblings: Array[String] = []
	for t2 in TermDB.all():
		if str(t2["group"]) == str(term["group"]) and str(t2["name"]) != name:
			siblings.append(str(t2["name"]))
	if not siblings.is_empty():
		detail_box.add_child(UIKit.spacer(4))
		detail_box.add_child(UIKit.title("同分类条目", 14))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", UI.fs(4))
		detail_box.add_child(row)
		for s in siblings:
			var b := UIKit.tiny(s, 11)
			b.pressed.connect(func() -> void:
				selected_term = s
				refresh())
			row.add_child(b)

	# 相关的一级功能入口提示
	detail_box.add_child(UIKit.spacer(4))
	var note := UIKit.dim(_related_hint(str(term["group"])), 11)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_box.add_child(note)


static func _related_hint(group: String) -> String:
	match group:
		"文明组": return "相关位置：图鉴页的「文明组」二级分类；世界泡页的卡组轮换。"
		# 1.8.21.2：这四条原来都指向「管理页」—— 那个入口 v1.8.7 已删除、功能全部搬走，
		# 照它走是死路。改指今天真实存在的位置（手册是给玩家看的，每句都要走得到）。
		"单位与战斗": return "相关位置：至宝 → 角色（主要/技能/职业/位阶）；部队统计在顶部资源栏中间的「统计」面板 → 单位。"
		"世界名词": return "相关位置：大世界地图；悬停 1 秒弹出的简约地块信息小窗；据点与稳定度在据点管理窗口、「统计」面板。"
		"世界泡与经济": return "相关位置：世界泡页的三个子系统；顶部资源栏。"
		"建筑与运营": return "相关位置：右键地块 → 🔨 修建浮窗；人力与规划队列在据点管理窗口。"
		"科技": return "相关位置：左上角的科技树浮窗。"
		"等级体系": return "相关位置：图鉴页的「稀有度」二级分类。"
		_: return ""


func on_cycle_finished(_rep: Dictionary) -> void:
	pass
