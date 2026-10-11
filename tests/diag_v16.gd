extends Node
const U := preload("res://tests/test_util.gd")
## v1.6 自检：开局格蕾修 / 量子之海文案 / 管理页刷新（人力管理·规划队列）/ 建筑详情与科技隐藏 /
## 招募全流程（攒 1600 凝聚力 → 十连 → 至宝招募 → 部署 → 移动两格）。
## 用法：godot --headless --path <项目> res://tests/diag_v16.tscn

var suite := U.reporter("v1.6 自检")
func _ready() -> void:
	await get_tree().process_frame

	print("== 1. 开局赠送：格蕾修 ==")
	GameState.new_game(20260101)
	var cap := str(GameState.state["capital"])
	var g := {}
	for u in GameState.state["units"]:
		if str(u.get("id", "")) == "char_grieso":
			g = u
	print("  单位数 %d｜格蕾修在场：%s｜状态 %s｜职业 %s｜地块 %s" % [
		(GameState.state["units"] as Array).size(), str(not g.is_empty()),
		str(g.get("status", "")), str(g.get("profession", "")), str(g.get("tile", ""))])
	if g.is_empty():
		suite.fail("开局没有赠送格蕾修")
	else:
		if str(g.get("status", "")) != UnitDB.STATUS_CITIZEN:
			suite.fail("格蕾修不是公民")
		if str(g.get("profession", "")) != UnitDB.PROJECTILE:
			suite.fail("格蕾修不是投射者")
		if str(g.get("tile", "")) != cap:
			suite.fail("格蕾修没有落在首都")
		if int(g.get("move_left", 0)) <= 0:
			suite.fail("格蕾修没有初始移动力")

	print("\n== 2. 文案：量子之海 / 世界泡 / 通用敌人称呼 ==")
	var scr_v: Script = load("res://scripts/ui/views/gacha_view.gd")
	var cv: Dictionary = scr_v.get_script_constant_map()
	var titles: Array[String] = []
	for p in (cv["POOLS"] as Array):
		titles.append(str(p["title"]))
	print("  三个子系统：%s" % " / ".join(titles))
	if titles[0] != "召唤系统" or titles[1] != "打捞系统" or titles[2] != "发展系统":
		suite.fail("子系统命名不对")
	var scr_gs: Script = load("res://scripts/ui/game_screen.gd")
	var gsc: Dictionary = scr_gs.get_script_constant_map()
	var names: Array[String] = []
	for v in (gsc["VIEWS"] as Array):
		names.append(str(v["name"]))
	print("  一级按钮：%s" % " / ".join(names))
	if not names.has("世界泡") or names.has("攫取"):
		suite.fail("一级按钮没有改成「世界泡」")
	var enemy_label := ""
	var t_test := {"owner": "enemy", "danger": true}
	enemy_label = GameState.enemy_label(t_test)
	print("  据点型敌人称呼：%s（期望 高危据点）" % enemy_label)
	if enemy_label != "高危据点":
		suite.fail("据点称呼不是通用称呼")

	print("\n== 3. 切回据点管理窗口必须刷新（用户报过的 bug；v1.8.7 管理页不可达，改打窗口） ==")
	var holder := U.host(self)
	var world: Control = load("res://scripts/ui/views/view_world_page.gd").new()
	world.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(world)
	world.size = Vector2(1280, 720)
	for i in 4:
		await get_tree().process_frame
	var cap_k := str(GameState.state["capital"])
	# 打开据点管理窗口（v1.8.20.4：改点首都星命中）
	var v16_map: Node = world.get("map")
	var v16_star: Vector2 = v16_map.get_global_transform() * (v16_map.call("tile_center", cap_k) as Vector2)
	world.call("_on_tile_clicked", cap_k, "", v16_star)

	for i in 4:
		await get_tree().process_frame
	var sp: Variant = world.get("stronghold_panel")
	if sp == null:
		suite.fail("据点管理窗口没有打开")
	else:
		sp.set("tab", "labor")
		sp.call("refresh")
		for i in 3:
			await get_tree().process_frame
		var n_first := ((sp.get("content_box") as Node).get_child_count()) if (sp.get("content_box") is Node) else 0
		# 修建一个建筑 + 排队一个建筑
		GameState.add_res("production", 400.0)
		var built_id := ""
		for def in GameState.building_defs:
			if GameState.can_build(GameState.tile_at(cap_k), def)["ok"]:
				var r := GameState.build(cap_k, def.id)
				print("  修建 %s：%s" % [def.id, str(r["ok"])])
				if bool(r["ok"]):
					built_id = def.id
					break
		GameState.state["res"]["production"] = 0.0
		var q_id := ""
		for def2 in GameState.building_defs:
			if str(def2.id) == built_id:
				continue
			if GameState.can_build(GameState.tile_at(cap_k), def2)["ok"]:
				q_id = str(def2.id)
				break
		if q_id != "":
			var qr := GameState.request_build(cap_k, q_id)
			print("  入队 %s：%s（queued=%s）" % [q_id, str(qr["ok"]), str(qr.get("queued", false))])
		# 重新打开窗口（走**缓存**路径）—— 修复前这里两块都是空的
		(sp as Control).visible = false
		world.call("_on_tile_clicked", cap_k, "", v16_star)

		for i in 3:
			await get_tree().process_frame
		sp.set("tab", "labor")
		sp.call("refresh")
		for i in 3:
			await get_tree().process_frame
		var n_labor := ((sp.get("content_box") as Node).get_child_count()) if (sp.get("content_box") is Node) else 0
		var n_queue := ((sp.get("build_box") as Node).get_child_count()) if (sp.get("build_box") is Node) else 0
		print("  首次打开人力子项 %d → 修建/入队后 %d｜规划队列 %d" % [n_first, n_labor, n_queue])
		if built_id == "":
			suite.fail("没有可建造的建筑，测试无效")
		if n_labor <= 0:
			suite.fail("据点管理窗口的人力页仍为空（没有刷新）")
		if n_queue <= 0:
			suite.fail("据点管理窗口的规划队列仍为空（没有刷新）")
	world.queue_free()
	holder.queue_free()

	print("\n== 4. 建筑详情与科技隐藏 ==")
	var scr_w: Script = load("res://scripts/ui/views/view_world_page.gd")
	print("  view_world_page 可加载：%s" % str(scr_w != null))
	var hidden := 0
	for def in GameState.building_defs:
		if def.required_tech != "" and not GameState.tech_unlocked(def.required_tech):
			hidden += 1
	print("  因科技未解锁而隐藏的建筑：%d 个" % hidden)
	if hidden <= 0:
		print("  （提示：当前没有需要科技的建筑，隐藏规则无法体现——不算失败）")

	print("\n== 5. 招募全流程：攒 1600 凝聚力 → 十连 → 招募 → 部署 → 移动两格 ==")
	GameState.add_res("cohesion", 4000.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260101
	var guests_before := GameState.guest_units().size()
	for attempt in 3:
		var d := Gacha.draw_ten(GameState.state, Gacha.Pool.ROTATION, rng)
		print("  第 %d 次十连：%s" % [attempt + 1, str(d["ok"])])
		if GameState.guest_units().size() > guests_before:
			break
	var guests := GameState.guest_units()
	print("  十连后客人数：%d" % guests.size())
	if guests.is_empty():
		suite.fail("十连没有召来任何客人")
	else:
		var guest: Dictionary = guests[0]
		var uid := str(guest["uid"])
		var br := GameState.begin_recruit(uid)
		print("  begin_recruit：%s（可部署 %d 块）" % [str(br["ok"]), int(br.get("tiles", []).size())])
		if not bool(br["ok"]):
			suite.fail("无法开始招募：" + str(br.get("why", "")))
		else:
			var ck := GameState.confirm_recruit(uid, cap)
			print("  确认招募：%s %s" % [str(ck["ok"]), str(ck.get("why", ""))])
			if not bool(ck["ok"]):
				suite.fail("确认招募失败")
			elif str(guest["status"]) != UnitDB.STATUS_CITIZEN:
				suite.fail("招募后不是公民")
			else:
				# 移动两格（一次距离 2 的跳跃，耗 2 移动力）
				GameState.reset_unit_moves()
				var from := str(guest["tile"])
				var a := WorldGen.coord_of(from)
				var dest := ""
				for d1 in Hex.DIRECTIONS:
					for d2 in Hex.DIRECTIONS:
						var k := WorldGen.key_of(a + d1 + d2)
						if k == from or not GameState.state["tiles"].has(k):
							continue
						if Hex.distance(a, WorldGen.coord_of(k)) != 2:
							continue
						if not GameState.tile_passable(k):
							continue
						if GameState.units_on_tile(k).size() >= UnitDB.UNITS_PER_TILE:
							continue
						dest = k
						break
					if dest != "":
						break
				if dest == "":
					suite.fail("找不到距离 2 的可移动地块")
				else:
					var mv_before := int(guest["move_left"])
					var mr := GameState.move_unit(uid, dest)
					print("  移动两格 %s → %s：%s（移动力 %d → %d，期望 -%d）" % [
						from, dest, str(mr["ok"]), mv_before, int(guest["move_left"]),
						Consts.MOVE_COST_FAR])
					if not bool(mr["ok"]):
						suite.fail("距离 2 移动失败：" + str(mr.get("why", "")))
					elif int(guest["move_left"]) != mv_before - Consts.MOVE_COST_FAR:
						suite.fail("距离 2 应消耗 2 移动力")
					elif str(guest["tile"]) != dest:
						suite.fail("移动后没有落在目标地块")

	print("\n== 6. 驻军：维护费打折 / 禁止行动 ==")
	var gu := GameState.units_on_tile(cap)
	if gu.is_empty():
		suite.fail("首都没有单位，无法测驻军")
	else:
		var gu0: Dictionary = gu[0]
		gu0["garrisoned"] = false
		var free_up := GameState.unit_upkeep_of(gu0)
		var tg := GameState.toggle_garrison(str(gu0["uid"]))
		var g_up := GameState.unit_upkeep_of(gu0)
		print("  行军维护 %.2f → 驻军维护 %.2f（领地内应 ×%.1f）" % [
			float(free_up["food"]), float(g_up["food"]), Consts.UPKEEP_MUL_IN_TERRITORY])
		if not bool(tg["ok"]):
			suite.fail("toggle_garrison 失败")
		if float(g_up["food"]) >= float(free_up["food"]) - 0.0001:
			suite.fail("驻军后维护费没有打折")
		GameState.reset_unit_moves()
		var a2 := WorldGen.coord_of(str(gu0["tile"]))
		var dest2 := ""
		for d in Hex.DIRECTIONS:
			var k := WorldGen.key_of(a2 + d)
			if GameState.state["tiles"].has(k) and GameState.tile_passable(k):
				dest2 = k
				break
		if dest2 != "":
			var mv2 := GameState.move_unit(str(gu0["uid"]), dest2)
			print("  驻军时移动：%s（期望失败）" % str(mv2["ok"]))
			if bool(mv2["ok"]):
				suite.fail("驻军中仍可移动")
		var tg2 := GameState.toggle_garrison(str(gu0["uid"]))
		print("  解除驻军：%s（garrisoned=%s）" % [str(tg2["ok"]), str(gu0.get("garrisoned", false))])
		if bool(gu0.get("garrisoned", false)):
			suite.fail("解除驻军失败")

	suite.finish(get_tree())