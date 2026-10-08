extends Control
## 记录页：保存 / 读取 / 删除 + 10 个存档槽。保存到已有存档与删除都需要二次确认。

var slot_box: VBoxContainer
var info_label: Label
var slot_count := Consts.SAVE_SLOTS


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	refresh()


func _build() -> void:
	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	# 左：操作按钮
	var left := UIKit.panel()
	left.custom_minimum_size = Vector2(300, 0)
	root.add_child(left)
	var lv := VBoxContainer.new()
	left.add_child(lv)
	lv.add_child(UIKit.title("存档操作", 18))
	info_label = UIKit.dim("")
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lv.add_child(info_label)
	lv.add_child(UIKit.spacer(8))

	var cur := int(GameState.state.get("current_slot", -1))
	var b_save := UIKit.normal("保存到选中槽位", 14)
	b_save.pressed.connect(_save)
	lv.add_child(b_save)

	var b_load := UIKit.normal("从选中槽位读取", 14)
	b_load.pressed.connect(_load)
	lv.add_child(b_load)

	var b_del := UIKit.normal("删除选中槽位的存档", 14)
	UIKit.style_button(b_del, false, true)
	b_del.pressed.connect(_delete)
	lv.add_child(b_del)

	lv.add_child(UIKit.spacer(10))
	lv.add_child(UIKit.title("说明", 14))
	var note := UIKit.dim("· 存档槽数量上限：%d 个。\n" % Consts.SAVE_SLOTS +
		"· 每个周期结束会自动存档到槽位 1。\n" +
		"· 覆盖已有存档与删除存档都需要二次确认，防止误操作。\n" +
		"· 当前槽位：%s" % ("槽位 %d" % (cur + 1) if cur >= 0 else "未保存"))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lv.add_child(note)

	# 右：存档槽
	var right := UIKit.panel()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(right)
	var rv := VBoxContainer.new()
	right.add_child(rv)
	rv.add_child(UIKit.title("存档槽", 18))
	slot_box = VBoxContainer.new()
	slot_box.add_theme_constant_override("separation", 4)
	rv.add_child(UIKit.scroll(slot_box))

	refresh()


func _selected_slot() -> int:
	var cur := int(GameState.state.get("current_slot", -1))
	return cur


func refresh() -> void:
	if not is_instance_valid(slot_box):
		return
	for c in slot_box.get_children():
		c.queue_free()
	var cur := _selected_slot()
	for i in slot_count:
		var slot := i
		var summ := GameState.slot_summary(i)
		var row := PanelContainer.new()
		var is_cur := i == cur
		UIKit.apply_panel(row, UIKit.BG_PANEL_2, UIKit.GOLD if is_cur else UIKit.LINE_SOFT, 5)
		slot_box.add_child(row)
		var h := UIKit.hbox(8)
		row.add_child(h)

		var tag := "自动" if i == Consts.AUTOSAVE_SLOT else "手动"
		var title := "槽位 %d（%s）" % [i + 1, tag]
		var v := UIKit.vbox(1)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(v)
		v.add_child(UIKit.text_label(title, 13, UIKit.GOLD if is_cur else UIKit.TEXT))
		if summ.is_empty():
			v.add_child(UIKit.dim("（空槽位）", 11))
		else:
			v.add_child(UIKit.dim("周期 %d　地块 %d　角色 %d　%s" % [
				int(summ["cycle"]), int(summ["tiles"]), int(summ["chars"]), str(summ["time"])], 11))

		var sv := UIKit.small("保存到此", 11)
		sv.pressed.connect(func() -> void: _save_to(slot))
		h.add_child(sv)
		var ld := UIKit.small("读取", 11)
		ld.disabled = summ.is_empty()
		ld.pressed.connect(func() -> void: _load_from(slot))
		h.add_child(ld)
		var dl := UIKit.small("删除", 11)
		dl.disabled = summ.is_empty()
		UIKit.style_button(dl, false, true)
		dl.pressed.connect(func() -> void: _delete_at(slot))
		h.add_child(dl)

	var cur2 := _selected_slot()
	info_label.text = "当前进度位于：%s\n周期 %d　地块 %d　角色 %d" % [
		("槽位 %d" % (cur2 + 1)) if cur2 >= 0 else "（尚未保存）",
		int(GameState.state["cycle"]), GameState.owned_tiles().size(),
		(GameState.state["units"] as Array).size()]


func _save() -> void:
	var slot := _selected_slot()
	if slot < 0:
		GameState.toast.emit("请先在右侧选择一个槽位保存")
		return
	_save_to(slot)


func _save_to(slot: int) -> void:
	if GameState.slot_exists(slot):
		var gs := UIKit.game_screen_of(self)
		if gs != null:
			gs.open_dialog(UIKit.confirm("覆盖存档",
				"槽位 %d 已有存档，确定覆盖？" % (slot + 1),
				func() -> void:
					GameState.save_to_slot(slot)
					refresh()))
			return
	GameState.save_to_slot(slot)
	refresh()


func _load() -> void:
	var slot := _selected_slot()
	if slot < 0:
		GameState.toast.emit("请先在右侧选择一个槽位")
		return
	_load_from(slot)


func _load_from(slot: int) -> void:
	GameState.load_from_slot(slot)
	refresh()


func _delete() -> void:
	var slot := _selected_slot()
	if slot < 0:
		GameState.toast.emit("请先在右侧选择一个槽位")
		return
	_delete_at(slot)


func _delete_at(slot: int) -> void:
	var gs := UIKit.game_screen_of(self)
	if gs == null:
		GameState.delete_slot(slot)
		refresh()
		return
	gs.open_dialog(UIKit.confirm("删除存档", "确定删除槽位 %d 的存档？此操作不可撤销。" % (slot + 1),
		func() -> void:
			GameState.delete_slot(slot)
			refresh()))


func on_cycle_finished(_rep: Dictionary) -> void:
	refresh()