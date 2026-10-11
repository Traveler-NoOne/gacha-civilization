extends Node
const U := preload("res://tests/test_util.gd")
## v1.8.10 走查自检：**主要入口一个都不能是死的**。
##
## 为什么单独有这一项：v1.8 重构期间我们踩过三次同类坑 ——
## 「入口没了 / 方法名漏改 / 页面不可达」但没有任何测试发现，最后是用户点出来才发现的。
## 这一项就是把这些入口挨个点一遍：主菜单 → 加载 → 世界 → 四个浮窗 → 右键菜单 → 修建浮窗。

var suite := U.reporter("v1.8.10 死入口走查")
func _ready() -> void:
	await get_tree().process_frame
	print("\n== v1.8.10 死入口走查 ==")

	# ① 主菜单 → 新游戏：必须先经过加载界面
	var main: Control = load("res://scripts/ui/main.gd").new()
	add_child(main)
	await suite.frames(3)
	main.call("_on_start_game", "new")
	await suite.frames(3)
	var cur: Variant = main.get("_current")
	suite.ok(cur != null and (cur as Node).name == "LoadingScreen", "新游戏先经过加载界面")

	# ② 等加载界面自己走完 → 进游戏主页
	var t0 := Time.get_ticks_msec()
	var gs: Variant = null
	while Time.get_ticks_msec() - t0 < 8000:
		await get_tree().process_frame
		var c2: Variant = main.get("_current")
		if c2 != null and (c2 as Node).name == "GameScreen":
			gs = c2
			break
	suite.ok(gs != null, "加载界面结束后进入游戏主页")
	if gs == null:
		suite.finish(get_tree(), "v1.8.10 走查结束（中途断了）")
		return

	# ③ 大世界常驻底层
	suite.ok((gs as Node).get("views").has("world"), "大世界常驻在底层")

	# ④ 五个角落按钮：四个浮窗开→关
	for pair in [["treasure", "至宝"], ["gacha", "世界泡"]]:
		var pid := str(pair[0])
		gs.call("goto_view", pid)
		await suite.frames(4)
		var panels: Dictionary = (gs as Node).get("panels")
		var opened: bool = panels.has(pid) and (panels[pid] as Control).visible
		suite.ok(opened, "「%s」浮窗能打开" % str(pair[1]))
		if opened:
			(panels[pid] as PagePanel).close_panel()
			await suite.frames(3)
			suite.ok(not (panels[pid] as Control).visible, "「%s」浮窗能关闭（✕）" % str(pair[1]))
	suite.ok(not bool(gs.call("_any_page_panel_open")), "全部关掉后回到纯地图")

	gs.call("_toggle_tech_panel")
	await suite.frames(4)
	suite.ok(((gs as Node).get("tech_panel") as Control).visible, "左上角「科技树」能打开")
	gs.call("_toggle_tech_panel")
	await suite.frames(2)
	gs.call("_toggle_log_panel")
	await suite.frames(4)
	suite.ok(((gs as Node).get("log_panel") as Control).visible, "右上角「日志」能打开")
	gs.call("_toggle_log_panel")
	await suite.frames(2)

	# ⑤ 世界页：右键 → 球形菜单 → 修建浮窗
	var wp: Variant = (gs as Node).get("views")["world"]
	var cap := str(GameState.state["capital"])
	wp.call("_on_tile_right_clicked", cap, Vector2(500, 300))
	await suite.frames(4)
	var am: Variant = wp.get("action_menu")
	suite.ok(am != null and (am as Control).visible, "右键地块能弹出球形菜单")
	wp.call("_run_tile_action", "build", cap)
	await suite.frames(5)
	var bp: Variant = wp.get("build_panel")
	suite.ok(bp != null and (bp as Control).visible, "🔨 能打开修建浮窗")

	# ⑥ 点击语义：点首都星 → 据点管理窗口（v1.8.20.4：改成命中首都星才开）

	var v110_map: Node = wp.get("map")
	var v110_star: Vector2 = v110_map.get_global_transform() * (v110_map.call("tile_center", cap) as Vector2)
	wp.call("_on_tile_clicked", cap, "", v110_star)

	await suite.frames(4)
	var sp: Variant = wp.get("stronghold_panel")
	suite.ok(sp != null and (sp as Control).visible, "点首都星能打开据点管理窗口")


	# ⑦ 资源栏中间的「统计」入口 —— 四种统计类型都要能出内容（不能有死页）
	gs.call("_toggle_stats_panel")
	await suite.frames(5)
	var stp: Variant = (gs as Node).get("stats_panel")
	suite.ok(stp != null and (stp as Control).visible, "资源栏中间的「统计」能打开")
	if stp == null:
		suite.ok(false, "统计面板没建出来，后面跳过")
	else:
		suite.ok(str((stp as Node).get("tab")) == "res", "统计面板**默认看「资源」**（用户定的）")
		for tid in ["res", "unit", "tile", "land"]:
			(stp as Node).set("tab", str(tid))
			(stp as Node).call("refresh")
			await suite.frames(3)
			var rows := ((stp as Node).get("content_box") as Node).get_child_count()
			suite.ok(rows > 2, "统计页「%s」有内容（%d 行）" % [str(tid), rows])
		(stp as Control).visible = false
		await suite.frames(2)

	# ⑧ 先把科技全解锁（顺序很重要：科技会开放建筑，建筑又决定征兵能不能排）
	GameState.add_res("research", 9999.0)
	var first_id := str((Consts.TECHS[0] as Dictionary)["id"])
	var tr: Dictionary = GameState.research(first_id)
	suite.ok(bool(tr["ok"]) and GameState.tech_unlocked(first_id), "科技能解锁（%s）" % first_id)
	for t in Consts.TECHS:
		GameState.research(str(t["id"]))

	# ⑧ 把首都上能修的都修了（征兵需要一座训练场地）
	GameState.add_res("production", 2000.0)
	var built_n := 0
	for def in GameState.building_defs:
		if GameState.can_build(GameState.tile_at(cap), def)["ok"]:
			if bool(GameState.build(cap, def.id)["ok"]):
				built_n += 1
	print("     （顺手修了 %d 座建筑，给征兵腾出前提）" % built_n)
	suite.ok(built_n > 0, "首都上能修建建筑")

	# ⑨ 政事：征兵入口可用 —— 能排入，或者给出**明确原因**（"训练场地不够"是正常游戏行为，不是死入口）
	var dr: Dictionary = GameState.enqueue_decree(DecreeDB.RECRUIT)
	var why := str(dr.get("why", ""))
	suite.ok(bool(dr["ok"]) or why != "", "「征兵」政事入口可用（%s）" % ("已排入队列" if bool(dr["ok"]) else why))

	# ⑨ 结束周期能推进
	var c0 := int(GameState.state["cycle"])
	GameState.end_cycle()
	suite.ok(int(GameState.state["cycle"]) > c0, "结束周期能推进天数")

	suite.finish(get_tree(), "v1.8.10 走查结束")