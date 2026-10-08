extends Node
## v1.4.1 自检：资源收支悬浮窗 + 「占领地块」按钮文案改为行政点数。
## 用法：godot --headless --path <项目> res://tests/diag_v141.tscn

var failed := 0


func _ready() -> void:
	await get_tree().process_frame

	print("== 1. resource_breakdown（收支明细） ==")
	GameState.new_game(20280101)
	var cap := str(GameState.state["capital"])
	GameState.state["res"]["production"] = 100.0
	GameState.build(cap, "classic_workshop")
	GameState.assign_worker(cap, "classic_workshop", 1)
	var bd: Dictionary = GameState.resource_breakdown("production")
	var inc: Array = bd["income"]
	var upk: Array = bd["upkeep"]
	print("  生产力：收入行 %d，支出行 %d（都应 > 0）" % [inc.size(), upk.size()])
	if inc.is_empty() or upk.is_empty():
		failed += 1
	for e in inc:
		print("    ＋ %s %.1f" % [e["label"], e["amount"]])
	for e in upk:
		print("    － %s %.1f" % [e["label"], e["amount"]])
	var food_bd: Dictionary = GameState.resource_breakdown("food")
	var has_pop := false
	for e in food_bd["upkeep"]:
		if str(e["label"]).contains("人口"):
			has_pop = true
	print("  食物支出含「人口维护」：%s" % has_pop)
	if not has_pop:
		failed += 1

	print("\n== 2. 悬浮窗弹出 / 关闭 ==")
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(holder)
	var gs: Control = load("res://scripts/ui/game_screen.gd").new()
	gs.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(gs)
	gs.size = Vector2(1280, 720)
	for i in 6:
		await get_tree().process_frame
	gs.call("_show_res_info", "production", Rect2(100, 40, 60, 24))
	for i in 3:
		await get_tree().process_frame
	var pop: Variant = gs.get("_res_popup")
	print("  点击后悬浮窗存在：%s" % (pop != null))
	if pop == null:
		failed += 1
	else:
		var t := _collect_text(pop as Node)
		print("  悬浮窗文字：%s" % t)
		if not t.contains("每周期收支") or not t.contains("建筑"):
			failed += 1
	gs.call("_close_res_popup")
	for i in 2:
		await get_tree().process_frame
	print("  关闭后：%s（期望 null）" % str(gs.get("_res_popup")))
	if gs.get("_res_popup") != null:
		failed += 1

	print("\n== 3. 世界页「占领地块」按钮文案 ==")
	var world: Control = load("res://scripts/ui/views/view_world_page.gd").new()
	world.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(world)
	world.size = Vector2(1280, 600)
	for i in 4:
		await get_tree().process_frame
	var cks := WorldGen.claimable_keys(GameState.state)
	var txt := ""
	if not cks.is_empty():
		world.call("_on_tile_selected", cks[0])
		for i in 3:
			await get_tree().process_frame
		if world.get("info_box") is Node:
			txt = _collect_text(world.get("info_box") as Node)
	print("  按钮文案含「行政点数」：%s（且不含「生产力」）" % txt.contains("行政点数"))
	if not txt.contains("行政点数") or txt.contains("生产力"):
		failed += 1

	print("\n== v1.4.1 自检结束，失败 %d 项 ==" % failed)
	get_tree().quit(0 if failed == 0 else 1)


func _collect_text(n: Node) -> String:
	var s := ""
	if n is Label:
		s += (n as Label).text + " | "
	if n is Button:
		s += "[" + (n as Button).text + "] "
	for c in n.get_children():
		s += _collect_text(c)
	return s
