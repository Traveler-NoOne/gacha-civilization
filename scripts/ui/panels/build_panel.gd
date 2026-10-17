class_name BuildPanel
extends PanelContainer
## v1.8.5：修建建筑浮窗（中型）
##
## 进入方式：右键地块 → 球形图标菜单 🔨 → 打开本浮窗。
## 中间：可修建建筑列表；**点条目 = 选中它**（同时展开它的完整效果）。
## 左下角：[取消]（随时可按）　[修建]（**选中条目后才亮起**）。
##
## 行为对齐旧版右侧面板（v1.8.5 会把它删掉），不能缩水：
##   · 只有我方领地能修
##   · **未满足科技条件的建筑自动隐藏**（不是置灰）—— v1.6 的规矩
##   · 生产力不够时提示"将进入队列"
##   · `GameState.can_build` 不通过时给出原因（并禁用按钮）

var tile_key := ""
var selected_id := ""
var title: Label
var land_label: Label
var list_box: VBoxContainer
var build_btn: Button


func _init() -> void:
	custom_minimum_size = Vector2(UI.px(560), UI.px(420))
	UIKit.apply_panel(self, Color(0.07, 0.07, 0.11, 1.0), UIKit.GOLD, 6)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UI.fs(6))
	add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UI.fs(8))
	col.add_child(head)
	title = UIKit.title("修建建筑", 15)
	head.add_child(title)
	land_label = UIKit.dim("", 11)
	head.add_child(land_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var close := UIKit.tiny("✕", 13, true)
	close.pressed.connect(func() -> void: visible = false)
	head.add_child(close)

	list_box = VBoxContainer.new()
	list_box.add_theme_constant_override("separation", UI.fs(4))
	col.add_child(UIKit.scroll(list_box))

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", UI.fs(8))
	col.add_child(bottom)
	var cancel_btn := UIKit.normal("取消", 13)
	cancel_btn.pressed.connect(func() -> void: visible = false)
	bottom.add_child(cancel_btn)
	build_btn = UIKit.primary("修建", 13)
	build_btn.disabled = true
	build_btn.tooltip_text = "先在列表里选一项"
	build_btn.pressed.connect(_on_build)
	bottom.add_child(build_btn)


func setup(key: String) -> void:
	tile_key = key
	selected_id = ""
	refresh()


func refresh() -> void:
	if not is_instance_valid(list_box):
		return
	for c in list_box.get_children():
		c.queue_free()
	var t := GameState.tile_at(tile_key)
	title.text = "修建建筑　[%s]" % tile_key
	if t.is_empty():
		list_box.add_child(UIKit.dim("（没有这块地）"))
		_update_build_btn(t)
		return
	if t.get("owner", Consts.Owner.NONE) != Consts.Owner.PLAYER:
		list_box.add_child(UIKit.dim("只有我方领地才能修建。", 12))
		land_label.text = ""
		_update_build_btn(t)
		return
	land_label.text = "已用土地 %.1f / %.1f" % [GameState.land_used(t), GameState.land_cap(t)]
	var shown := 0
	for def in GameState.building_defs:
		# v1.6 的规矩：未满足科技条件的建筑**自动隐藏**
		if def.required_tech != "" and not GameState.tech_unlocked(def.required_tech):
			continue
		list_box.add_child(_row(def, t))
		shown += 1
	if shown == 0:
		list_box.add_child(UIKit.dim("当前没有可修建的建筑（可能都被科技锁着）。"))
	_update_build_btn(t)


## 一行 = 一个 PanelContainer（**容器会按内容撑高**；Button 不会，所以这里不用 Button）
func _row(def: BuildingDef, t: Dictionary) -> Control:
	var sel := str(def.id) == selected_id
	var row := PanelContainer.new()
	UIKit.apply_panel(row, UIKit.BG_PANEL_2, UIKit.GOLD if sel else UIKit.LINE_SOFT, 5)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed \
				and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			select_row(str(def.id)))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", UI.fs(2))
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UI.fs(8))
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(head)
	head.add_child(UIKit.text_label(str(def.display_name), 13, UIKit.GOLD if sel else UIKit.TEXT))
	head.add_child(UIKit.dim("占地 %.1f" % float(def.land), 10))
	var count := GameState.tile_buildings_of(t, def.id).size()
	if count > 0:
		head.add_child(UIKit.text_label("已有 ×%d" % count, 10, UIKit.OK))

	var cost := def.upgrade_cost(1)
	var can_now := GameState.res("production") >= float(cost.get("production", 0.0))
	v.add_child(UIKit.dim("消耗 %s%s" % [GameState.cost_to_text(cost),
		"" if can_now else "（生产力不足，将进入队列）"], 10))

	if sel:
		# 选中时才展开完整效果 —— 这就是"点条目查看建筑效果"
		var info := UIKit.dim(str(def.summary()), 10)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(info)
		var chk := GameState.can_build(t, def)
		if not bool(chk["ok"]):
			v.add_child(UIKit.text_label("不能修建：%s" % str(chk["why"]), 10, UIKit.BAD))
	return row


func select_row(id: String) -> void:
	selected_id = id
	refresh()


func _update_build_btn(t: Dictionary) -> void:
	if selected_id == "" or t.is_empty():
		build_btn.disabled = true
		build_btn.text = "修建"
		build_btn.tooltip_text = "先在列表里选一项"
		return
	var def := GameState.find_building(selected_id)
	if def == null:
		build_btn.disabled = true
		return
	var chk := GameState.can_build(t, def)
	build_btn.disabled = not bool(chk["ok"])
	build_btn.tooltip_text = "" if bool(chk["ok"]) else str(chk["why"])
	# 生产力够就叫「修建」，不够就叫「加入队列」（沿用旧面板的说法）
	var can_now := GameState.res("production") >= float(def.upgrade_cost(1).get("production", 0.0))
	build_btn.text = "修建" if can_now else "加入队列"


func _on_build() -> void:
	if selected_id == "":
		return
	var r: Dictionary = GameState.request_build(tile_key, selected_id)
	if not bool(r["ok"]):
		GameState.toast.emit(str(r["why"]))
	else:
		GameState.toast.emit("已加入规划队列" if bool(r.get("queued", false)) else "建造完成")
	GameState.state_changed.emit()
	selected_id = ""
	refresh()
