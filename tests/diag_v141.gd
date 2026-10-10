extends Node
const U := preload("res://tests/test_util.gd")
## v1.4.1 自检：资源收支悬浮窗 + 「占领地块」按钮文案改为行政点数。
## 用法：godot --headless --path <项目> res://tests/diag_v141.tscn

var suite := U.reporter("v1.4.1 自检")
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
		suite.failed += 1
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
		suite.failed += 1

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
		suite.failed += 1
	else:
		var t := U.collect_text(pop as Node)
		print("  悬浮窗文字：%s" % t)
		if not t.contains("每周期收支") or not t.contains("建筑"):
			suite.failed += 1
	gs.call("_close_res_popup")
	for i in 2:
		await get_tree().process_frame
	print("  关闭后：%s（期望 null）" % str(gs.get("_res_popup")))
	if gs.get("_res_popup") != null:
		suite.failed += 1

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
		world.call("_on_tile_clicked", cks[0], "", Vector2.ZERO)
		for i in 3:
			await get_tree().process_frame
		# v1.8.5：旧右侧规划面板已删除，「占领」按钮搬进了「简约地块信息小窗」
		if world.get("tile_info_popup") is Node:
			txt = U.collect_text(world.get("tile_info_popup") as Node)
	print("  按钮文案含「行政点数」：%s（且不含「生产力」）" % txt.contains("行政点数"))
	if not txt.contains("行政点数") or txt.contains("生产力"):
		suite.failed += 1

	suite.finish(get_tree())