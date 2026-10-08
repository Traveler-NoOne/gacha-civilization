extends Node
## v1.5 自检：客人/公民、招募流程（选地 / 满员重选 / 取消 / 遣返）、单位维护费、
## 移动力、移动与攻击、点击轮换、三个子系统命名、免责声明。
## 用法：godot --headless --path <项目> res://tests/diag_v15.tscn

var failed := 0


func _fail(msg: String) -> void:
	print("  [FAIL] " + msg)
	failed += 1


func _host() -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.custom_minimum_size = Vector2(1280, 720)
	add_child(c)
	return c


func _hero(name_text: String) -> Dictionary:
	return UnitDB.from_card({
		"id": "t_" + name_text, "name": name_text, "rarity": 5, "group": "通用",
		"kind": "circle", "profession": UnitDB.MELEE, "rank": UnitDB.HERO,
	})


func _add(u: Dictionary) -> void:
	u["acquired_cycle"] = int(GameState.state["cycle"])
	GameState.state["units"].append(u)


func _ready() -> void:
	await get_tree().process_frame

	print("== 1. 状态默认值：召唤=客人 / 征兵=公民 ==")
	GameState.new_game(20250101)
	var cap := str(GameState.state["capital"])
	var guest := _hero("测试客人")
	_add(guest)
	print("  召唤角色 status=%s（期望 guest）" % str(guest["status"]))
	if str(guest["status"]) != UnitDB.STATUS_GUEST:
		_fail("召唤来的角色默认不是客人")
	if int(guest.get("hp", 0)) <= 0:
		_fail("单位没有初始化血量")
	if GameState.guest_units().size() != 1:
		_fail("guest_units() 计数不对")
	GameState.add_res("food", 200.0)
	GameState.add_res("currency", 900.0)
	var rb := GameState.build(cap, "classic_training_ground")
	var rr := GameState.recruit_soldier(UnitDB.MELEE)
	print("  训练场 %s / 征兵 %s %s" % [str(rb["ok"]), str(rr["ok"]), str(rr.get("why", ""))])
	if bool(rb["ok"]) and bool(rr["ok"]):
		var sol: Dictionary = rr["unit"]
		if str(sol["status"]) != UnitDB.STATUS_CITIZEN:
			_fail("征兵单位不是公民")
		if str(sol["tile"]) == "":
			_fail("公民没有自动派驻大世界（公民必须在大世界）")

	print("\n== 2. 客人 / 公民 维护费 ==")
	var g_up := GameState.unit_upkeep_of(guest)
	print("  客人：食物 %.2f 货币 %.2f（期望 %.2f / 0）" % [
		float(g_up["food"]), float(g_up["currency"]), Consts.GUEST_FOOD_PER_CYCLE])
	if absf(float(g_up["food"]) - Consts.GUEST_FOOD_PER_CYCLE) > 0.001:
		_fail("客人食物开销不对")
	if absf(float(g_up["currency"])) > 0.001:
		_fail("客人不该消耗货币")
	var cits := GameState.citizen_units()
	if not cits.is_empty():
		var c0: Dictionary = cits[0]
		# v1.6.1：维护费折扣只对「驻军」状态生效；行军时全额
		c0["garrisoned"] = false
		var free_up := GameState.unit_upkeep_of(c0)
		print("  公民（行军，全额）：食物 %.2f（期望 %.2f）" % [
			float(free_up["food"]), Consts.UNIT_UPKEEP_FOOD])
		if absf(float(free_up["food"]) - Consts.UNIT_UPKEEP_FOOD) > 0.001:
			_fail("行军状态不该享受维护费折扣")
		c0["garrisoned"] = true
		var inside := GameState.unit_upkeep_of(c0)
		var want_in := Consts.UNIT_UPKEEP_FOOD * Consts.UPKEEP_MUL_IN_TERRITORY
		print("  公民（驻军·领地内）：食物 %.2f（期望 %.2f）" % [float(inside["food"]), want_in])
		if absf(float(inside["food"]) - want_in) > 0.001:
			_fail("领地内驻军维护费没有 −60%")
		var saved := str(c0["tile"])
		var free_keys := WorldGen.claimable_keys(GameState.state)
		if not free_keys.is_empty():
			c0["tile"] = str(free_keys[0])
			var outside := GameState.unit_upkeep_of(c0)
			var want_out := Consts.UNIT_UPKEEP_FOOD * Consts.UPKEEP_MUL_OUTSIDE
			print("  公民（驻军·领地外）：食物 %.2f（期望 %.2f）" % [float(outside["food"]), want_out])
			if absf(float(outside["food"]) - want_out) > 0.001:
				_fail("领地外驻军维护费没有 −10%")
		c0["tile"] = saved
		c0["garrisoned"] = false

	print("\n== 3. 移动力（2 移动速度 = 1 移动力） ==")
	for spd in [2, 3, 4]:
		var u := UnitDB.make_soldier("recruit", UnitDB.MELEE, UnitDB.RECRUIT, "t%d" % spd, 1)
		(u["attr"] as Dictionary)["spd"] = spd
		var mv := GameState.max_move(u)
		var want := maxi(1, int(floor(float(spd) / 2.0)))
		print("  spd=%d → %d 移动力（期望 %d）" % [spd, mv, want])
		if mv != want:
			_fail("移动力换算不对")

	print("\n== 4. 招募流程：确认 / 满员重选 / 取消 / 遣返 ==")
	var dk := GameState.deployable_keys()
	print("  可部署地块 %d 个" % dk.size())
	if dk.is_empty():
		_fail("没有可部署地块")
	var br := GameState.begin_recruit(str(guest["uid"]))
	print("  begin_recruit %s（待招募=%s）" % [str(br["ok"]), GameState.pending_recruit_uid()])
	if not bool(br["ok"]) or GameState.pending_recruit_uid() != str(guest["uid"]):
		_fail("无法开始招募")
	if not dk.is_empty():
		var ok1 := GameState.confirm_recruit(str(guest["uid"]), dk[0])
		print("  正常确认：%s %s" % [str(ok1["ok"]), str(ok1.get("why", ""))])
		if not bool(ok1["ok"]):
			_fail("合法地块无法招募")
		if str(guest["status"]) != UnitDB.STATUS_CITIZEN or str(guest["tile"]) != str(dk[0]):
			_fail("招募后没有转公民并落地")
	# 把首都塞满（4 人），再试一次招募 → 必须失败且保持客人
	while GameState.units_on_tile(cap).size() < UnitDB.UNITS_PER_TILE:
		var filler := UnitDB.make_soldier("recruit", UnitDB.DEFENDER, UnitDB.RECRUIT, "填位", 1)
		filler["tile"] = cap
		_add(filler)
	var guest2 := _hero("二号客人")
	_add(guest2)
	GameState.begin_recruit(str(guest2["uid"]))
	var full := GameState.confirm_recruit(str(guest2["uid"]), cap)
	print("  满员地块确认：%s %s（期望失败）" % [str(full["ok"]), str(full.get("why", ""))])
	if bool(full["ok"]):
		_fail("满员地块竟然可以部署")
	if str(guest2["status"]) != UnitDB.STATUS_GUEST:
		_fail("失败时客人应保持客人")
	GameState.cancel_recruit()
	print("  取消后：待招募=%s 状态=%s（期望空 / guest）" % [
		GameState.pending_recruit_uid(), str(guest2["status"])])
	if GameState.pending_recruit_uid() != "" or str(guest2["status"]) != UnitDB.STATUS_GUEST:
		_fail("取消后没有清空待招募或改变了状态")
	var n_before := (GameState.state["units"] as Array).size()
	var dr := GameState.dismiss_guest(str(guest2["uid"]))
	print("  遣返：%s（单位数 %d → %d）" % [str(dr["ok"]), n_before, (GameState.state["units"] as Array).size()])
	if not bool(dr["ok"]) or (GameState.state["units"] as Array).size() != n_before - 1:
		_fail("遣返没有真的移除单位")
	var dr2 := GameState.dismiss_guest(str(guest["uid"]))
	print("  遣返公民：%s（期望失败）" % str(dr2["ok"]))
	if bool(dr2["ok"]):
		_fail("公民不应该能被遣返")

	print("\n== 5. 移动与攻击 ==")
	GameState.reset_unit_moves()
	var mv_u: Dictionary = GameState.units_on_tile(cap)[0]
	var a := WorldGen.coord_of(cap)
	var dest := ""
	for d in Hex.DIRECTIONS:
		var k := WorldGen.key_of(a + d)
		if GameState.state["tiles"].has(k) and GameState.tile_passable(k) \
				and GameState.units_on_tile(k).size() < UnitDB.UNITS_PER_TILE:
			dest = k
			break
	if dest == "":
		_fail("找不到可移动的相邻格")
	else:
		var before := int(mv_u["move_left"])
		var mr := GameState.move_unit(str(mv_u["uid"]), dest)
		print("  相邻移动：%s 移动力 %d → %d（期望 -%d）" % [
			str(mr["ok"]), before, int(mv_u["move_left"]), Consts.MOVE_COST_NEAR])
		if not bool(mr["ok"]):
			_fail("合法移动失败：" + str(mr.get("why", "")))
		elif int(mv_u["move_left"]) != before - Consts.MOVE_COST_NEAR:
			_fail("相邻移动应消耗 1 移动力")
		var far := WorldGen.key_of(a + Hex.DIRECTIONS[0] * 3)
		var bad := GameState.move_unit(str(mv_u["uid"]), far)
		print("  3 格外移动：%s（期望失败）" % str(bad["ok"]))
		if bool(bad["ok"]):
			_fail("超过 2 格也能移动")
		# 造一个相邻敌人来攻击
		var ua := WorldGen.coord_of(str(mv_u["tile"]))
		var ekey := ""
		for d2 in Hex.DIRECTIONS:
			var k2 := WorldGen.key_of(ua + d2)
			var t2 := GameState.tile_at(k2)
			if not t2.is_empty() and t2.get("owner", "") == "":
				ekey = k2
				break
		if ekey == "":
			_fail("找不到可放敌人的相邻空格")
		else:
			var et := GameState.tile_at(ekey)
			et["owner"] = "enemy"
			et["force"] = 8.0
			et["discovered"] = true
			et["name"] = "敌意个体"
			mv_u["move_left"] = 3
			var ar := GameState.unit_attack(str(mv_u["uid"]), ekey)
			print("  攻击：%s 伤害 %.1f 剩余兵力 %.1f 行动 %d→%d" % [
				str(ar["ok"]), float(ar.get("damage", 0.0)), float(et["force"]),
				3, int(mv_u["move_left"])])
			if not bool(ar["ok"]):
				_fail("攻击失败：" + str(ar.get("why", "")))
			elif float(et["force"]) >= 8.0:
				_fail("攻击没有削减敌人兵力")
			elif int(mv_u["move_left"]) != 0:
				_fail("攻击后应耗尽本周期行动")

	print("\n== 6. 点击轮换（市中心 → 单位 → 地块） ==")
	var holder := _host()
	var w: Control = load("res://scripts/ui/views/view_world_page.gd").new()
	w.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(w)
	w.size = Vector2(1280, 720)
	for i in 4:
		await get_tree().process_frame
	w.call("_on_tile_selected", cap)
	var s1 := int(w.get("click_step"))
	var u1 := str(w.get("sel_uid"))
	w.call("_on_tile_selected", cap)
	var s2 := int(w.get("click_step"))
	w.call("_on_tile_selected", cap)
	var s3 := int(w.get("click_step"))
	print("  同格连点 step：%d → %d → %d；首档 sel=%s" % [s1, s2, s3, u1])
	if s1 != 0 or s2 != 1 or s3 != 2:
		_fail("同格重复点击没有按档轮换")
	if bool(GameState.tile_at(cap).get("is_capital", false)) and u1 != "":
		_fail("首档应选市中心，却选了单位")
	var other := ""
	for k in GameState.state["tiles"].keys():
		if str(k) != cap:
			other = str(k)
			break
	w.call("_on_tile_selected", other)
	print("  换到另一格后 step=%d（期望 0）" % int(w.get("click_step")))
	if int(w.get("click_step")) != 0:
		_fail("换格后没有从头开始")
	w.queue_free()
	holder.queue_free()

	print("\n== 7. 三个子系统的命名 + 一级按钮 + 免责声明 ==")
	var h2 := _host()
	var gv: Control = load("res://scripts/ui/views/gacha_view.gd").new()
	h2.add_child(gv)
	gv.size = Vector2(1280, 720)
	for i in 4:
		await get_tree().process_frame
	var titles: Array[String] = []
	for i in 3:
		gv.set("pool", i)
		gv.call("refresh")
		for f in 2:
			await get_tree().process_frame
		titles.append(str((gv.get("title_label") as Label).text))
	print("  池标题：%s" % " / ".join(titles))
	if titles[0] != "召唤系统" or titles[1] != "打捞系统" or titles[2] != "发展系统":
		_fail("三个子系统的命名不对")
	gv.set("pool", 2)
	gv.call("refresh")
	for f in 2:
		await get_tree().process_frame
	var n_btn := 0
	var first_label := ""
	for c in (gv.get("draw_row") as Node).get_children():
		if c is Button:
			n_btn += 1
			if first_label == "":
				first_label = str((c as Button).text)
	print("  发展系统动作按钮：%d 个，首个「%s」（期望 1 个「创造」）" % [n_btn, first_label])
	if n_btn != 1 or first_label != "创造":
		_fail("发展系统的动作按钮不对")
	h2.queue_free()

	var scr := load("res://scripts/ui/game_screen.gd") as Script
	var consts: Dictionary = scr.get_script_constant_map()
	var names: Array[String] = []
	for v in (consts["VIEWS"] as Array):
		names.append(str(v["name"]))
	print("  一级按钮：%s" % " / ".join(names))
	if not names.has("世界泡") or names.has("抽卡"):
		_fail("一级按钮没有改成「世界泡」（v1.6 起由「攫取」再改名）")
	print("  免责声明：%s" % Consts.DISCLAIMER_TEXT)
	if not Consts.DISCLAIMER_TEXT.contains("非官方同人"):
		_fail("免责声明文案不对")

	print("\n== 8. 客人离去判定（第 15 周期起） ==")
	var g3 := _hero("三号客人")
	g3["status"] = UnitDB.STATUS_GUEST
	g3["acquired_cycle"] = 1
	GameState.state["units"].append(g3)
	GameState.state["cycle"] = 14
	GameState.guest_leave_tick({"events": []})
	print("  第 14 周期：leave_chance=%.4f（期望 0）" % float(g3["leave_chance"]))
	if float(g3["leave_chance"]) > 0.0:
		_fail("未满 15 周期就积累离去概率")
	GameState.state["cycle"] = 20
	GameState.guest_leave_tick({"events": []})
	print("  第 20 周期：leave_chance=%.4f（期望 > 0）" % float(g3["leave_chance"]))
	if float(g3["leave_chance"]) <= 0.0:
		_fail("超过 15 周期后离去概率没有累积")

	print("\n== v1.5 自检结束，失败 %d 项 ==" % failed)
	get_tree().quit(0 if failed == 0 else 1)
