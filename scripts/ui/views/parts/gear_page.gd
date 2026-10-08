extends Control
## 装备页：武装 / 战备 两类。
## 对应设计文档「装备页」：一般只分为武装、战备两种类型。

var type_tabs: HBoxContainer
var list_box: VBoxContainer
var detail_box: VBoxContainer
var filter := "all"
var selected := ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	refresh()


func _build() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	var head := UIKit.hbox(8)
	root.add_child(head)
	head.add_child(UIKit.title("装备", 18))
	head.add_child(UIKit.dim("武装：武器 / 光锥 / 音擎　·　战备：圣遗物 / 遗器 / 驱动盘"))

	type_tabs = UIKit.hbox(6)
	root.add_child(type_tabs)
	for pair in [["all", "全部"], ["weapon", "武装"], ["relic", "战备"]]:
		var fid: String = pair[0]
		var b := UIKit.small(str(pair[1]), 13)
		b.custom_minimum_size = Vector2(96, 30)
		b.pressed.connect(func() -> void:
			filter = fid
			refresh())
		type_tabs.add_child(b)

	var body := UIKit.hbox(6)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	var left := UIKit.panel()
	left.custom_minimum_size = Vector2(260, 0)
	body.add_child(left)
	var lv := VBoxContainer.new()
	left.add_child(lv)
	lv.add_child(UIKit.title("持有列表", 14))
	list_box = VBoxContainer.new()
	list_box.add_theme_constant_override("separation", 3)
	lv.add_child(UIKit.scroll(list_box))

	var right := UIKit.panel()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	detail_box = VBoxContainer.new()
	detail_box.add_theme_constant_override("separation", 6)
	right.add_child(UIKit.scroll(detail_box))


func refresh() -> void:
	if not is_instance_valid(list_box):
		return
	_refresh_tabs()
	_refresh_list()
	_refresh_detail()


func _refresh_tabs() -> void:
	var ids := ["all", "weapon", "relic"]
	var i := 0
	for c in type_tabs.get_children():
		if c is Button:
			var active: bool = ids[i] == filter
			UIKit.style_button(c as Button, active)
			(c as Button).add_theme_color_override("font_color", UIKit.GOLD if active else UIKit.TEXT)
			i += 1


func _filtered() -> Array:
	var out := []
	for e in GameState.state["equipment"]:
		if filter == "all" or str(e.get("slot", "")) == filter:
			out.append(e)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["rarity"]) != int(b["rarity"]):
			return int(a["rarity"]) > int(b["rarity"])
		return str(a["name"]) < str(b["name"]))
	return out


func _refresh_list() -> void:
	for c in list_box.get_children():
		c.queue_free()
	var items := _filtered()
	if items.is_empty():
		list_box.add_child(UIKit.dim("还没有装备。\n去「世界泡 → 召唤系统」召唤武装与战备。"))
		return
	for e in items:
		var col: Color = Consts.rarity_color(int(e["rarity"]))
		var row := PanelContainer.new()
		UIKit.apply_panel(row, UIKit.BG_PANEL_2, col if str(e["id"]) == selected else UIKit.LINE_SOFT, 5)
		list_box.add_child(row)
		var h := UIKit.hbox(6)
		row.add_child(h)
		var ic := GeoIcon.new()
		ic.setup(str(e["kind"]), col)
		ic.custom_minimum_size = Vector2(28, 28)
		h.add_child(ic)
		var v := VBoxContainer.new()
		h.add_child(v)
		v.add_child(UIKit.text_label(str(e["name"]), 12, col))
		v.add_child(UIKit.dim("%d★　%s" % [int(e["rarity"]), "武装" if str(e["slot"]) == "weapon" else "战备"], 10))
		var hit := Button.new()
		hit.flat = true
		hit.set_anchors_preset(Control.PRESET_FULL_RECT)
		hit.pressed.connect(func() -> void:
			selected = str(e["id"])
			refresh())
		row.add_child(hit)
		row.move_child(hit, 0)
	if selected == "" and not items.is_empty():
		selected = str(items[0]["id"])


func _refresh_detail() -> void:
	for c in detail_box.get_children():
		c.queue_free()
	var found: Dictionary = {}
	var total := 0
	for e in GameState.state["equipment"]:
		if str(e["id"]) == selected:
			found = e
		if filter == "all" or str(e.get("slot", "")) == filter:
			total += 1
	detail_box.add_child(UIKit.title("装备详情", 16))
	if found.is_empty():
		detail_box.add_child(UIKit.dim("从左边选一件装备。"))
		return
	var col: Color = Consts.rarity_color(int(found["rarity"]))
	var head := UIKit.hbox(10)
	detail_box.add_child(head)
	var ic := GeoIcon.new()
	ic.setup(str(found["kind"]), col)
	ic.custom_minimum_size = Vector2(72, 72)
	head.add_child(ic)
	var v := VBoxContainer.new()
	head.add_child(v)
	v.add_child(UIKit.text_label(str(found["name"]), 18, col))
	v.add_child(UIKit.dim("%d★ %s　·　%s　·　%s" % [
		int(found["rarity"]), Consts.rarity_name(int(found["rarity"])),
		"武装" if str(found["slot"]) == "weapon" else "战备", str(found["group"])], 12))

	var attr: Dictionary = found.get("attr", {})
	if not attr.is_empty():
		var g := UIKit.grid(2, 16, 3)
		detail_box.add_child(g)
		for k in attr.keys():
			var nm := "攻击力" if k == "atk" else ("防御力" if k == "def" else str(k))
			g.add_child(UIKit.dim(nm, 12))
			g.add_child(UIKit.text_label(str(attr[k]), 12, UIKit.TEXT))

	detail_box.add_child(UIKit.spacer(6))
	detail_box.add_child(UIKit.dim("当前筛选下共 %d 件装备。" % total, 12))
	detail_box.add_child(UIKit.dim("说明：装备只对「角色」生效；训练军与募集军不能装备召唤获得的武器或战备。", 11))


func on_cycle_finished(_rep: Dictionary) -> void:
	refresh()
