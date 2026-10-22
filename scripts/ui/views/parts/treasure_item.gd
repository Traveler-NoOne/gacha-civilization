extends Control
## 道具页：货币、强化道具之类杂项，以及抽卡获得的材料。

var grid: GridContainer
var summary: Label
var detail: VBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	refresh()


func _build() -> void:
	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", UI.fs(6))
	add_child(root)

	var left := UIKit.panel()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(left)
	var lv := VBoxContainer.new()
	left.add_child(lv)
	lv.add_child(UIKit.title("道具 / 材料", 18))
	summary = UIKit.dim("")
	lv.add_child(summary)
	grid = UIKit.grid(6, 8, 8)
	lv.add_child(UIKit.scroll(grid))

	var right := UIKit.panel()
	right.custom_minimum_size = Vector2(UI.px(300), UI.px(0))
	root.add_child(right)
	detail = VBoxContainer.new()
	detail.add_theme_constant_override("separation", UI.fs(5))
	right.add_child(UIKit.scroll(detail))


func refresh() -> void:
	if not is_instance_valid(grid):
		return
	for c in grid.get_children():
		c.queue_free()
	var items: Dictionary = GameState.state["items"]
	if items.is_empty():
		grid.add_child(UIKit.dim("还没有道具。去「世界泡 → 打捞系统」打捞材料与道具。"))
	else:
		var ids := items.keys()
		ids.sort()
		for id in ids:
			grid.add_child(_card_for(str(id), int(items[id])))

	# 右侧：资源明细
	for c in detail.get_children():
		c.queue_free()
	detail.add_child(UIKit.title("资源明细", 15))
	summary.text = "道具 %d 种" % items.size()
	var g := UIKit.grid(2, 14, 3)
	detail.add_child(g)
	for k in Consts.RES_KEYS:
		g.add_child(UIKit.dim(Consts.res_name(k), 12))
		g.add_child(UIKit.text_label(UIKit.fmt_num(Res.amount(GameState.state, k)), 12, Palette.TEXT))
	detail.add_child(UIKit.spacer(6))
	var note := UIKit.dim("说明：材料用于发展营地与养成角色。\n某一组内角色的高级材料，只有在「轮换」处于该卡组期间，才能在资源页抽出。", 11)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(note)


func _card_for(id: String, count: int) -> Control:
	var def := _find(id)
	var col := Palette.TEXT_DIM
	var kind := "circle"
	var nm := id
	var rarity := 1
	if not def.is_empty():
		kind = str(def.get("kind", "circle"))
		rarity = int(def.get("rarity", 1))
		col = Consts.rarity_color(rarity)
		nm = str(def.get("name", id))
	var p := PanelContainer.new()
	UIKit.apply_panel(p, Palette.BG_SLOT, col, 6)
	p.custom_minimum_size = Vector2(UI.px(96), UI.px(108))
	var v := UIKit.vbox(2)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(v)
	var ic := GeoIcon.new()
	ic.setup(kind, col)
	ic.custom_minimum_size = Vector2(UI.px(72), UI.px(56))
	v.add_child(ic)
	var l := UIKit.text_label(nm, 11, col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(l)
	var c := UIKit.text_label("x%d" % count, 12, Palette.TEXT)
	c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(c)
	return p


func _find(id: String) -> Dictionary:
	for c in CardDB.all():
		if str(c["id"]) == id:
			return c
	return {}


func on_cycle_finished(_rep: Dictionary) -> void:
	refresh()