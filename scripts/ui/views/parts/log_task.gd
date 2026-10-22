extends Control
## 任务页：当前 / 档案 切换；左侧三个图标按钮（新建任务组、新建任务、删除任务组、删除任务、完成任务）。

var tab_bar: HBoxContainer
var icon_bar: VBoxContainer
var list_box: VBoxContainer
var mode := "current"
var selected := ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	refresh()


func _build() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", UI.fs(6))
	add_child(root)

	tab_bar = HBoxContainer.new()
	tab_bar.add_theme_constant_override("separation", UI.fs(6))
	root.add_child(tab_bar)
	for pair in [["current", "当前"], ["archive", "档案"]]:
		var mid: String = pair[0]
		var b := UIKit.small(str(pair[1]), 14)
		b.custom_minimum_size = Vector2(UI.px(110), UI.px(32))
		b.pressed.connect(func() -> void:
			mode = mid
			selected = ""
			refresh())
		tab_bar.add_child(b)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", UI.fs(6))
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	# 左侧文字按钮（v1.1：取消原来的多边形图标设计，改为文字按钮）
	# v1.2：六个按钮的宽度减去三分之一（124 -> 83，按钮 112 -> 75）
	# v1.3：是tip不换行导致的宽度过宽，增加自动换行功能后正常，83反而太小，修改回120。
	var icon_panel := UIKit.panel()
	icon_panel.custom_minimum_size = Vector2(UI.px(120), UI.px(0))
	icon_panel.size_flags_horizontal = Control.SIZE_FILL
	body.add_child(icon_panel)
	icon_bar = VBoxContainer.new()
	icon_bar.custom_minimum_size = Vector2(UI.px(110), UI.px(0))
	icon_bar.add_theme_constant_override("separation", UI.fs(4))
	icon_panel.add_child(icon_bar)
	_add_text_button("新建任务组", _new_group)
	_add_text_button("新建任务", _new_task)
	_add_text_button("删除任务组", _delete_group)
	_add_text_button("删除任务", _delete_task)
	_add_text_button("完成任务", _complete_task)
	_add_text_button("归档选中任务", _archive_task)
	var tip := UIKit.dim("选中：点任务行里的「选中」按钮。", 10)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size = Vector2(UI.px(110), UI.px(0)) 
	icon_bar.add_child(tip)
	icon_bar.add_child(UIKit.spacer(4))
	
	var tip2 := UIKit.dim("已完成的任务会在「选中」左边多出一个「归档」按钮，点击后完成并转入档案页。", 10)
	tip2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # ← 新增
	tip2.custom_minimum_size = Vector2(UI.px(110), UI.px(0))             # ← 新增：窄宽度强制折行
	icon_bar.add_child(tip2)

	var list_panel := UIKit.panel()
	list_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(list_panel)
	var lv := VBoxContainer.new()
	list_panel.add_child(lv)
	lv.add_child(UIKit.title("任务列表", 15))
	var hint := UIKit.dim("系统自动创建的任务组与任务不可删除；只能删除自己创建的。点任务可选中。", 11)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lv.add_child(hint)
	list_box = VBoxContainer.new()
	list_box.add_theme_constant_override("separation", UI.fs(4))
	lv.add_child(UIKit.scroll(list_box))

	refresh()


func _add_text_button(text: String, cb: Callable) -> void:
	var b := UIKit.normal(text, 12)
	b.custom_minimum_size = Vector2(UI.px(110), UI.px(30))
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.tooltip_text = text
	b.pressed.connect(cb)
	icon_bar.add_child(b)


func refresh() -> void:
	if not is_instance_valid(list_box):
		return
	var i := 0
	for c in tab_bar.get_children():
		if c is Button:
			var want := "current" if i == 0 else "archive"
			UIKit.style_button(c as Button, mode == want)
			(c as Button).add_theme_color_override("font_color", Palette.GOLD if mode == want else Palette.TEXT)
			i += 1

	for c in list_box.get_children():
		c.queue_free()

	if mode == "archive":
		var done: Array = GameState.state.get("tasks_done", [])
		list_box.add_child(UIKit.title("档案（已完成且不再重置的任务）", 14))
		if done.is_empty():
			list_box.add_child(UIKit.dim("还没有已完成的任务。"))
		for t in done:
			list_box.add_child(_done_row(t))
		return

	var groups: Array = GameState.state["task_groups"]
	var tasks: Array = GameState.state["tasks"]
	if groups.is_empty() and tasks.is_empty():
		list_box.add_child(UIKit.dim("还没有任务。用左边的图标按钮创建任务组和任务。"))

	for g in groups:
		var gid := str(g["id"])
		var head := PanelContainer.new()
		UIKit.apply_panel(head, Color(0.13, 0.13, 0.19), Palette.LINE, 5)
		list_box.add_child(head)
		var h := UIKit.hbox(6)
		head.add_child(h)
		var open := bool(GameState.state["_group_open"].get(gid, true))
		var caret := UIKit.tiny("▾" if open else "▸", 12)
		caret.pressed.connect(func() -> void:
			GameState.state["_group_open"][gid] = not open
			refresh())
		h.add_child(caret)
		h.add_child(UIKit.text_label("%s　（%d 个任务）" % [str(g["name"]), _count_in(gid)], 13,
			Palette.GOLD))
		if bool(g.get("system", false)):
			h.add_child(UIKit.dim("系统", 10))
		var hit := UIKit.small("选中", 11)
		hit.pressed.connect(func() -> void:
			selected = "group:" + gid
			refresh())
		h.add_child(hit)
		if selected == "group:" + gid:
			h.add_child(UIKit.text_label("◀ 已选中", 11, Palette.OK))

		if open:
			for t in tasks:
				if str(t.get("group", "")) == gid:
					list_box.add_child(_task_row(t, true))

	# 未分组任务
	var loose := 0
	for t in tasks:
		if str(t.get("group", "")) == "":
			if loose == 0:
				list_box.add_child(UIKit.dim("未分组任务", 12))
			loose += 1
			list_box.add_child(_task_row(t, true))


func _count_in(gid: String) -> int:
	var n := 0
	for t in GameState.state["tasks"]:
		if str(t.get("group", "")) == gid:
			n += 1
	return n


func _task_row(t: Dictionary, indented: bool) -> Control:
	var row := PanelContainer.new()
	var col := Palette.LINE_SOFT
	if selected == "task:" + str(t["id"]):
		col = Palette.GOLD
	UIKit.apply_panel(row, Palette.BG_PANEL_2, col, 5)
	if indented:
		var mc := MarginContainer.new()
		mc.add_theme_constant_override("margin_left", UI.px(18))
		mc.add_child(row)
		_fill_task_row(row, t)
		return mc
	_fill_task_row(row, t)
	return row


func _fill_task_row(row: PanelContainer, t: Dictionary) -> void:
	var h := UIKit.hbox(8)
	row.add_child(h)
	var v := UIKit.vbox(1)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var head := UIKit.hbox(6)
	v.add_child(head)
	head.add_child(UIKit.text_label(str(t["name"]), 13, Palette.TEXT))
	if bool(t.get("system", false)):
		head.add_child(UIKit.dim("系统", 10))
	var desc := UIKit.dim(str(t.get("desc", "")), 11)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(desc)

	# 目标进度
	var goals: Array = t.get("goals", [])
	if not goals.is_empty():
		var gp: Array[String] = []
		for g in goals:
			var cur := _goal_progress(g)
			gp.append("%s %d/%d%s" % [str(g["text"]), cur, int(g["need"]),
				"　✔" if cur >= int(g["need"]) else ""])
		v.add_child(UIKit.dim("目标：" + "；".join(gp), 11))
	# 重置周期
	if int(t.get("reset_cycles", 0)) > 0:
		v.add_child(UIKit.dim("每 %d 个周期重置一次" % int(t["reset_cycles"]), 10))

	# v1.1：已完成的任务，在「选中」按钮的左边增加一个「归档」按钮
	var done := _is_complete(t)
	if done:
		var done_tag := UIKit.text_label("已完成", 11, Palette.OK)
		v.add_child(done_tag)
		var arc := UIKit.small("归档", 11)
		UIKit.style_button(arc, true)
		arc.tooltip_text = "完成任务并转移到档案页"
		arc.pressed.connect(func() -> void: _archive_one(t))
		h.add_child(arc)

	var pick := UIKit.small("选中", 11)
	pick.pressed.connect(func() -> void:
		selected = "task:" + str(t["id"])
		refresh())
	h.add_child(pick)


## 任务的全部目标是否都已达成
static func _is_complete(t: Dictionary) -> bool:
	var goals: Array = t.get("goals", [])
	if goals.is_empty():
		return false
	for g in goals:
		if _goal_progress(g) < int(g["need"]):
			return false
	return true


## 把任务归档：标记完成 -> 移入档案页
func _archive_one(t: Dictionary) -> void:
	var tid := str(t["id"])
	var tasks: Array = GameState.state["tasks"]
	var idx := -1
	for i in tasks.size():
		if str((tasks[i] as Dictionary)["id"]) == tid:
			idx = i
			break
	if idx < 0:
		return
	var item: Dictionary = tasks[idx]
	item["done_cycle"] = int(GameState.state["cycle"])
	item["archived"] = true
	(GameState.state["tasks_done"] as Array).append(item)
	tasks.remove_at(idx)
	if selected == "task:" + tid:
		selected = ""
	Journal.add(GameState.state, "任务归档：%s" % str(item["name"]), "task")
	GameState.toast.emit("已归档「%s」，可在档案页查看" % str(item["name"]))
	GameState.state_changed.emit()
	refresh()


## 顶部「归档选中任务」按钮
func _archive_task() -> void:
	if not selected.begins_with("task:"):
		GameState.toast.emit("请先在列表中选中一个任务")
		return
	var tid := selected.substr(5)
	for t in GameState.state["tasks"]:
		if str(t["id"]) == tid:
			_archive_one(t)
			return
	GameState.toast.emit("未找到该任务")


static func _goal_progress(g: Dictionary) -> int:
	match str(g.get("type", "item")):
		"item":
			var items: Dictionary = GameState.state["items"]
			return int(items.get(str(g.get("key", "")), 0))
		"resource":
			return int(Res.amount(GameState.state, str(g.get("key", ""))))
		"kill":
			return int(GameState.state.get("enemy_killed", 0))
		"tile":
			return TileManager.owned_tiles(GameState.state).size()
		"cycle":
			return int(GameState.state["cycle"])
		_:
			return 0


func _done_row(t: Dictionary) -> Control:
	var row := UIKit.panel(Palette.BG_PANEL_2, Palette.LINE_SOFT, 5)
	var v := UIKit.vbox(1)
	row.add_child(v)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", UI.fs(6))
	v.add_child(h)
	h.add_child(UIKit.text_label(str(t["name"]), 13, Palette.OK))
	if bool(t.get("archived", false)):
		h.add_child(UIKit.text_label("已归档", 10, Palette.GOLD))
	else:
		h.add_child(UIKit.text_label("已完成", 10, Palette.TEXT_DIM))
	v.add_child(UIKit.dim("%s于第 %d 周期　%s" % [
		"归档" if bool(t.get("archived", false)) else "完成",
		int(t.get("done_cycle", 0)), str(t.get("desc", ""))], 11))
	return row


# ---------------------------------------------------------------------------
# 操作
# ---------------------------------------------------------------------------
func _new_group() -> void:
	var gs := UIKit.game_screen_of(self)
	if gs == null:
		return
	var v := UIKit.vbox(6)
	v.add_child(UIKit.text_label("新建任务组（类似文件夹，可收纳任务）", 13))
	var edit := LineEdit.new()
	edit.placeholder_text = "任务组名称"
	v.add_child(edit)
	var ok := UIKit.primary("创建", 14)
	ok.pressed.connect(func() -> void:
		var nm := edit.text.strip_edges()
		if nm == "":
			nm = "任务组 %d" % ((GameState.state["task_groups"] as Array).size() + 1)
		(GameState.state["task_groups"] as Array).append({
			"id": "g%d" % Time.get_ticks_usec(), "name": nm, "system": false,
		})
		gs.close_dialog()
		refresh())
	v.add_child(ok)
	var d := UIKit.dialog("新建任务组", 380.0)
	d.set_content(v)
	gs.open_dialog(d)


func _new_task() -> void:
	var gs := UIKit.game_screen_of(self)
	if gs == null:
		return
	var v := UIKit.vbox(6)
	v.add_child(UIKit.text_label("新建任务（实时追踪目标）", 13))
	var edit := LineEdit.new()
	edit.placeholder_text = "任务名称"
	v.add_child(edit)
	var edit2 := LineEdit.new()
	edit2.placeholder_text = "任务描述"
	v.add_child(edit2)

	var group_opt := OptionButton.new()
	group_opt.add_item("（不归属任何任务组）")
	group_opt.set_item_metadata(0, "")
	for g in GameState.state["task_groups"]:
		group_opt.add_item(str(g["name"]))
		group_opt.set_item_metadata(group_opt.item_count - 1, str(g["id"]))
	v.add_child(UIKit.text_label("归属任务组", 12, Palette.TEXT_DIM))
	v.add_child(group_opt)

	var type_opt := OptionButton.new()
	var types := [["item", "收集图鉴中的物品"], ["resource", "累计资源"], ["kill", "击杀敌对目标"],
		["tile", "占领地块数"], ["cycle", "存活周期数"]]
	for pair in types:
		type_opt.add_item(str(pair[1]))
		type_opt.set_item_metadata(type_opt.item_count - 1, str(pair[0]))
	v.add_child(UIKit.text_label("追踪目标类型（目标必须是图鉴中已解锁的内容）", 12, Palette.TEXT_DIM))
	v.add_child(type_opt)

	var key_edit := LineEdit.new()
	key_edit.placeholder_text = "目标标识（如 mat_wood）"
	v.add_child(key_edit)

	var need_spin := SpinBox.new()
	need_spin.min_value = 1
	need_spin.max_value = 9999
	need_spin.value = 10
	v.add_child(UIKit.text_label("需要数量", 12, Palette.TEXT_DIM))
	v.add_child(need_spin)

	var reset_spin := SpinBox.new()
	reset_spin.min_value = 0
	reset_spin.max_value = 999
	reset_spin.value = 0
	v.add_child(UIKit.text_label("多少周期后重置（0 = 不重置）", 12, Palette.TEXT_DIM))
	v.add_child(reset_spin)

	var ok := UIKit.primary("创建", 14)
	ok.pressed.connect(func() -> void:
		var nm := edit.text.strip_edges()
		if nm == "": 
			nm = "新任务 %d" % ((GameState.state["tasks"] as Array).size() + 1)
		var gtype := str(type_opt.get_item_metadata(type_opt.selected))
		var gkey := key_edit.text.strip_edges()
		var goal := {"type": gtype, "key": gkey, "need": int(need_spin.value), "text": _goal_text(gtype, gkey)}
		(GameState.state["tasks"] as Array).append({
			"id": "t%d" % Time.get_ticks_usec(),
			"name": nm,
			"desc": edit2.text.strip_edges(),
			"group": str(group_opt.get_item_metadata(group_opt.selected)),
			"goals": [goal],
			"reset_cycles": int(reset_spin.value),
			"system": false,
			"created_cycle": int(GameState.state["cycle"]),
		})
		Journal.add(GameState.state, "新建任务：%s" % nm, "task")
		gs.close_dialog()
		refresh())
	v.add_child(ok)

	var sc := UIKit.scroll(v)
	sc.custom_minimum_size = Vector2(UI.px(0), UI.px(420))
	var d := UIKit.dialog("新建任务", 460.0)
	d.set_content(sc)
	gs.open_dialog(d)


static func _goal_text(gtype: String, key: String) -> String:
	match gtype:
		"item": return "收集 %s" % (Consts.res_name(key) if key != "" else "物品")
		"resource": return "累计 %s" % Consts.res_name(key)
		"kill": return "击杀敌人"
		"tile": return "占领地块"
		"cycle": return "存活周期"
		_: return gtype


func _delete_group() -> void:
	if not selected.begins_with("group:"):
		GameState.toast.emit("请先在列表中选中一个任务组")
		return
	var gid := selected.substr(6)
	var target: Dictionary = {}
	for g in GameState.state["task_groups"]:
		if str(g["id"]) == gid:
			target = g
	if target.is_empty():
		GameState.toast.emit("未找到该任务组")
		return
	if bool(target.get("system", false)):
		GameState.toast.emit("系统任务组不可删除")
		return
	var gs := UIKit.game_screen_of(self)
	if gs == null:
		return
	gs.open_dialog(UIKit.confirm("删除任务组", "确定删除任务组「%s」？组内任务会一并删除。" % str(target["name"]),
		func() -> void:
			var keep_g: Array = []
			for g in GameState.state["task_groups"]:
				if str(g["id"]) != gid:
					keep_g.append(g)
			GameState.state["task_groups"] = keep_g
			var keep_t: Array = []
			for t in GameState.state["tasks"]:
				if str(t.get("group", "")) != gid:
					keep_t.append(t)
			GameState.state["tasks"] = keep_t
			selected = ""
			refresh()))


func _delete_task() -> void:
	if not selected.begins_with("task:"):
		GameState.toast.emit("请先在列表中选中一个任务")
		return
	var tid := selected.substr(5)
	var target: Dictionary = {}
	for t in GameState.state["tasks"]:
		if str(t["id"]) == tid:
			target = t
	if target.is_empty():
		GameState.toast.emit("未找到该任务")
		return
	if bool(target.get("system", false)):
		GameState.toast.emit("系统任务不可删除")
		return
	var gs := UIKit.game_screen_of(self)
	if gs == null:
		return
	gs.open_dialog(UIKit.confirm("删除任务", "确定删除任务「%s」？" % str(target["name"]),
		func() -> void:
			var keep: Array = []
			for t in GameState.state["tasks"]:
				if str(t["id"]) != tid:
					keep.append(t)
			GameState.state["tasks"] = keep
			selected = ""
			refresh()))


func _complete_task() -> void:
	if not selected.begins_with("task:"):
		GameState.toast.emit("请先在列表中选中一个任务")
		return
	var tid := selected.substr(5)
	var idx := -1
	var tasks: Array = GameState.state["tasks"]
	for i in tasks.size():
		if str((tasks[i] as Dictionary)["id"]) == tid:
			idx = i
	if idx < 0:
		GameState.toast.emit("未找到该任务")
		return
	var t: Dictionary = tasks[idx]
	var can := true
	for g in t.get("goals", []):
		if _goal_progress(g) < int(g["need"]):
			can = false
	if not can and not (t.get("goals", []) as Array).is_empty():
		GameState.toast.emit("目标尚未完成，无法手动完成")
		return
	t["done_cycle"] = int(GameState.state["cycle"])
	t["archived"] = true
	(GameState.state["tasks_done"] as Array).append(t)
	tasks.remove_at(idx)
	selected = ""
	Journal.add(GameState.state, "任务归档：%s" % str(t["name"]), "task")
	GameState.toast.emit("已完成并归档「%s」" % str(t["name"]))
	GameState.state_changed.emit()
	refresh()


func on_cycle_finished(_rep: Dictionary) -> void:
	refresh()