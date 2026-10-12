extends Node
const U := preload("res://tests/test_util.gd")
## v1.4 自检：存储上限、经典仓储、中控区精简、人力管理、资源栏分类、土地口径。
## 用法：godot --headless --path <项目> res://tests/diag_v14.tscn

var suite := U.reporter("v1.4 自检")
func _ready() -> void:
	await get_tree().process_frame

	print("== 1. 存储上限（add_res 夹取） ==")
	GameState.new_game(20270101)
	var checks := [
		["food", 500.0, 100.0], ["wood", 999.0, 100.0], ["currency", 500.0, -1.0],
		["research", 999.0, 200.0], ["production", 999.0, 20.0],
	]
	for c in checks:
		var key := str(c[0])
		var before := GameState.res(key)
		GameState.add_res(key, float(c[1]))
		var cap := float(c[2])
		var expect := before + float(c[1])
		if cap >= 0.0:
			expect = minf(expect, cap)
		var got := GameState.res(key)
		var ok := absf(got - expect) < 0.5
		print("  %s：%.0f +%d -> %.0f（期望 %.0f）%s" % [
			Consts.res_name(key), before, int(c[1]), got, expect, "✔" if ok else "✘"])
		if not ok:
			suite.failed += 1

	print("\n== 2. 经典仓储提升上限 ==")
	var cap := str(GameState.state["capital"])
	print("  建前 storage_cap(wood)：%.0f（期望 100）" % GameState.storage_cap("wood"))
	if not is_equal_approx(GameState.storage_cap("wood"), 100.0):
		suite.failed += 1
	GameState.state["res"]["production"] = 100.0
	var rb: Dictionary = GameState.build(cap, "classic_warehouse")
	print("  建造经典仓储：%s %s" % [rb["ok"], str(rb.get("why", ""))])
	if not rb["ok"]:
		suite.failed += 1
	print("  建后 storage_cap(wood)：%.0f（期望 150）" % GameState.storage_cap("wood"))
	if not is_equal_approx(GameState.storage_cap("wood"), 150.0):
		suite.failed += 1
	var wh := GameState.tile_building(GameState.tile_at(cap), "classic_warehouse")
	GameState.state["res"]["production"] = 100.0
	var ru: Dictionary = GameState.request_upgrade_by_bid(cap, str(wh.get("bid", "")))
	print("  升级仓储到 Lv.2：ok=%s" % ru["ok"])
	print("  升级后 storage_cap(wood)：%.0f（期望 200）" % GameState.storage_cap("wood"))
	if not is_equal_approx(GameState.storage_cap("wood"), 200.0):
		suite.failed += 1

	# v1.8.20.6：原来这里测"管理页的中控区"，管理页已删除；这个 holder 后面几节还要用
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(holder)


	print("\n== 4. 人力管理（只列已建建筑）—— 改测据点窗口共用的那个 static ==")
	GameState.new_game(20270102)
	cap = str(GameState.state["capital"])
	GameState.state["res"]["production"] = 100.0
	GameState.build(cap, "classic_field")
	# v1.8.20.6：原管理页已删除；"人力行"的构造现在是 StrongholdPanel.build_labor_rows
	#（static，被据点管理窗口共用 —— 覆盖保留在这里，不丢）
	var labor_box := VBoxContainer.new()
	holder.add_child(labor_box)
	StrongholdPanel.build_labor_rows(labor_box, func() -> void: pass)
	var rows := labor_box.get_child_count()

	print("  人力管理行数：%d（应 > 0）" % rows)
	if rows <= 0:
		suite.failed += 1
	var fld := GameState.tile_building(GameState.tile_at(cap), "classic_field")
	var w0 := int(fld.get("workers", 0))
	var wr: Dictionary = GameState.assign_worker_by_bid(cap, str(fld.get("bid", "")), 1)
	print("  按 bid 投入人力：ok=%s，人力 %d -> %d" % [wr["ok"], w0, int(fld.get("workers", 0))])
	if not wr["ok"] or int(fld.get("workers", 0)) != w0 + 1:
		suite.failed += 1

	print("\n== 5. 资源栏分类 + 具体资源全显 ==")
	var gs: Control = load("res://scripts/ui/game_screen.gd").new()
	gs.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(gs)
	gs.size = Vector2(1280, 720)
	for i in 6:
		await get_tree().process_frame
	var bar: Variant = gs.get("resource_bar")
	var groups := 0
	if bar is Node:
		groups = (bar as Node).get_child_count()
	print("  资源栏子容器数：%d（期望 3：抽象盒 / 间隔 / 具体盒）" % groups)
	if groups != 3:
		suite.failed += 1
	var text := U.collect_text(bar as Node)
	for nm in ["生产力", "科研点", "行政点数", "秩序结晶", "凝聚力", "人力",
			"食物", "货币", "木材", "煤", "铜矿", "铁矿", "原油", "水晶碎屑"]:
		if not text.contains(nm):
			print("  [FAIL] 资源栏缺少：%s" % nm)
			suite.failed += 1

	print("\n== 6. 土地口径（已用/上限） ==")
	# v1.8.20.6：原管理页已删除；这段文案现在在据点管理窗口的「信息」页里
	var shp_land := StrongholdPanel.new()
	shp_land.key = GameState.state["capital"]
	holder.add_child(shp_land)
	shp_land.refresh()
	for i in 3:
		await get_tree().process_frame
	var ok_land := false
	if shp_land.get("content_box") is Node:
		var lt := U.collect_text(shp_land.get("content_box") as Node)
		ok_land = lt.contains("已用土地") and not lt.contains("可用土地")
	print("  据点窗口「信息」页土地文案：%s（应含「已用土地」、不含「可用土地」）" % ok_land)

	if not ok_land:
		suite.failed += 1

	suite.finish(get_tree())