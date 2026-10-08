extends Node
## v1.1 单位系统自检：征兵 -> 派驻 -> 战斗 -> 经验 -> 晋升 的完整链路。

func _ready() -> void:
	GameState.new_game(20240607)
	var cap: String = str(GameState.state["capital"])

	print("== 准备：造训练场地 + 抽几个角色 ==")
	GameState.add_res("production", 500.0)
	GameState.add_res("food", 500.0)
	GameState.add_res("currency", 5000.0)
	var rb: Dictionary = GameState.build(cap, "classic_training_ground")
	print("  建造经典训练场地 -> %s %s" % [rb["ok"], rb["why"]])
	GameState.add_res("cohesion", 30000.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	Gacha.draw_ten(GameState.state, Gacha.Pool.ROTATION, rng)
	print("  单位总数 %d（角色 %d）" % [
		GameState.state["units"].size(), GameState.state["units"].size()])

	print("\n== 职业与位阶数据 ==")
	for p in UnitDB.PROFESSION_ORDER:
		var c: Array = (UnitDB.PROFESSIONS[p] as Dictionary)["counters"]
		var cnames: Array[String] = []
		for x in c:
			cnames.append(UnitDB.profession_name(str(x)))
		print("  %s（射程 %d）克制：%s" % [UnitDB.profession_name(p),
			int((UnitDB.PROFESSIONS[p] as Dictionary)["range"]),
			"、".join(cnames) if not cnames.is_empty() else "无"])
	print("  位阶倍率：募集军满经验=%.2f，正规军满经验=%.2f，角色满经验=%.2f" % [
		UnitDB.rank_multiplier(UnitDB.RECRUIT, 1.0),
		UnitDB.rank_multiplier(UnitDB.REGULAR, 1.0),
		UnitDB.rank_multiplier(UnitDB.HERO, 1.0)])
	print("  经验上限：%d / %d / %d" % [
		UnitDB.exp_cap(UnitDB.RECRUIT), UnitDB.exp_cap(UnitDB.REGULAR), UnitDB.exp_cap(UnitDB.HERO)])

	print("\n== 征兵（募集军） ==")
	for p in [UnitDB.MELEE, UnitDB.PROJECTILE, UnitDB.DEFENDER, UnitDB.SUPPORT, UnitDB.RANGED]:
		var r: Dictionary = GameState.recruit_soldier(p)
		if r["ok"]:
			var u: Dictionary = r["unit"]
			var mul := UnitDB.rank_multiplier(str(u["rank"]), UnitDB.progress_of(u))
			print("  招募 %s -> %s（%s，倍率 ×%.2f）" % [
				UnitDB.profession_name(p), str(u["name"]), UnitDB.rank_name(str(u["rank"])), mul])
		else:
			print("  招募 %s 失败：%s" % [UnitDB.profession_name(p), str(r["why"])])
	print("  单位总数 %d" % GameState.state["units"].size())

	print("\n== 地块容量限制（每格最多 %d） ==" % UnitDB.UNITS_PER_TILE)
	var idle := GameState.idle_units()
	var placed := 0
	for u in idle:
		var r2: Dictionary = GameState.deploy_unit(str(u["uid"]), cap)
		if r2["ok"]:
			placed += 1
		else:
			print("  第 %d 个派驻失败：%s" % [placed + 1, str(r2["why"])])
	print("  首都共派驻 %d 个（上限 %d）" % [GameState.units_on_tile(cap).size(), UnitDB.UNITS_PER_TILE])

	print("\n== 编队（每队最多 %d） ==" % UnitDB.UNITS_PER_TEAM)
	var all_units: Array = GameState.state["units"]
	for i in all_units.size():
		var r3: Dictionary = GameState.assign_team(str(all_units[i]["uid"]), 0)
		if not r3["ok"]:
			print("  第 %d 个编队失败：%s" % [i + 1, str(r3["why"])])
	var team0_names: Array[String] = []
	for m in GameState.team_units(0):
		team0_names.append(str(m["name"]))
	print("  第一队 %d/%d：%s" % [GameState.team_units(0).size(), UnitDB.UNITS_PER_TEAM,
		"、".join(team0_names)])
	# 换队
	if all_units.size() > 0:
		GameState.assign_team(str(all_units[0]["uid"]), 1)
		print("  把 %s 换到第二队 -> 第一队 %d 人，第二队 %d 人" % [
			str(all_units[0]["name"]), GameState.team_units(0).size(), GameState.team_units(1).size()])

	print("\n== 伤害与克制结算 ==")
	var melee := GameState.unit_by_uid(str(all_units[0]["uid"]))
	var dummy_def := {"name": "假想防御者", "profession": UnitDB.DEFENDER, "attr": {"atk": 10, "def": 20, "hp": 200}}
	var dummy_proj := {"name": "假想投射者", "profession": UnitDB.PROJECTILE, "attr": {"atk": 30, "def": 10, "hp": 120}}
	for pair in [[UnitDB.MELEE, UnitDB.DEFENDER], [UnitDB.MELEE, UnitDB.PROJECTILE],
			[UnitDB.PROJECTILE, UnitDB.MELEE], [UnitDB.DEFENDER, UnitDB.PROJECTILE]]:
		var atk := {"profession": pair[0], "attr": {"atk": 30, "def": 10, "hp": 150}}
		var dfn := {"profession": pair[1], "attr": {"atk": 10, "def": 15, "hp": 150}}
		var rr := UnitDB.resolve_damage(atk, dfn)
		var tag := "均势"
		if int(rr["advantage"]) > 0:
			tag = "克制 +30%"
		elif int(rr["advantage"]) < 0:
			tag = "被克制 −20%"
		print("  %s 打 %s：%.1f 伤害（%s，职业减免 %.0f%%）" % [
			UnitDB.profession_name(pair[0]), UnitDB.profession_name(pair[1]),
			float(rr["damage"]), tag, float(rr["mitigated"]) * 100.0])

	print("\n== 经验与晋升 ==")
	var target: Dictionary = GameState.unit_by_uid(str(all_units[0]["uid"]))
	if str(target.get("rank", "")) == UnitDB.HERO:
		# 找一个募集军来测试晋升
		for u2 in GameState.state["units"]:
			if str(u2.get("rank", "")) == UnitDB.RECRUIT:
				target = u2
				break
	print("  测试单位：%s（%s，经验 %d/%d）" % [str(target["name"]),
		UnitDB.rank_name(str(target["rank"])), int(target.get("exp", 0)),
		UnitDB.exp_cap(str(target["rank"]))])
	var base_power := UnitDB.power_of(target)
	# 用周期循环经验刷满
	for i in 60:
		GameState.gain_exp(str(target["uid"]), UnitDB.EXP_PER_CYCLE, "cycle")
	print("  周期经验刷满后：经验 %d（周期来源 %d，上限 %d）｜战力 %.1f -> %.1f｜倍率 ×%.2f" % [
		int(target["exp"]), int(target.get("exp_from_cycles", 0)), UnitDB.EXP_FROM_CYCLES_CAP,
		base_power, UnitDB.power_of(target),
		UnitDB.rank_multiplier(str(target["rank"]), UnitDB.progress_of(target))])
	var more := GameState.gain_exp(str(target["uid"]), 50, "cycle")
	print("  再刷周期经验：%s %s" % [more["ok"], str(more.get("why", ""))])
	var pr: Dictionary = GameState.promote_unit(str(target["uid"]))
	print("  晋升 -> %s %s（现在 %s，倍率 ×%.2f）" % [pr["ok"], str(pr.get("why", "")),
		UnitDB.rank_name(str(target.get("rank", ""))),
		UnitDB.rank_multiplier(str(target.get("rank", "")), UnitDB.progress_of(target))])

	print("\n== 战斗（对敌方地块） ==")
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 555
	# 主动造一个危险据点，保证战斗可测：反复尝试直到触发
	for i in 200:
		var hz: Dictionary = WorldGen.maybe_spawn_hazard(GameState.state, rng2)
		if hz["spawned"]:
			break
	var enemy_key := ""
	for t in GameState.enemy_tiles():
		enemy_key = WorldGen.key_of(Vector2i(int(t["c"][0]), int(t["c"][1])))
	if enemy_key == "":
		print("  没能生成敌方地块，跳过战斗测试")
	else:
		# 把驻军挪到敌人旁边，保证有参战单位
		# 先点亮敌人周围一圈，再直接找一块相邻的无主地块占下来
		WorldGen.discover_radius(GameState.state, WorldGen.coord_of(enemy_key), 2)
		var cap_c := WorldGen.coord_of(str(GameState.state["capital"]))
		var best_adj := ""
		var best_d := 9999
		for n in Hex.neighbors(WorldGen.coord_of(enemy_key)):
			var nk := WorldGen.key_of(n)
			var nt := GameState.tile_at(nk)
			if nt.is_empty():
				continue
			if nt.get("owner", "") == "player":
				best_adj = nk
				break
			if nt.get("owner", "") != "" or str(nt.get("terrain", "")) == "water":
				continue
			var d := Hex.distance(WorldGen.coord_of(nk), cap_c)
			if d < best_d:
				best_d = d
				best_adj = nk
		if best_adj != "":
			GameState.add_res("production", 800.0)
			var tk := GameState.tile_at(best_adj)
			if tk.get("owner", "") != "player":
				# 直接标记为我方地块（绕过迷雾/相邻判定，测试用）
				tk["owner"] = "player"
				tk["discovered"] = true
				WorldGen.discover_radius(GameState.state, WorldGen.coord_of(best_adj), 1)
				print("  测试用：直接把 %s 设为我方地块" % best_adj)
			for u3 in GameState.idle_units():
				var dr: Dictionary = GameState.deploy_unit(str(u3["uid"]), best_adj)
				if not dr["ok"]:
					break
			print("  派驻地 %s 现有驻军 %d 个" % [best_adj, GameState.units_on_tile(best_adj).size()])
		else:
			print("  找不到敌人旁边的可用地块")
		print("  敌方地块 %s（%s，战力 %.0f，职业 %s）" % [enemy_key,
			str(GameState.tile_at(enemy_key).get("name", "敌人")),
			float(GameState.tile_at(enemy_key).get("force", 0.0)),
			UnitDB.profession_name(GameState._enemy_profession(GameState.tile_at(enemy_key)))])
		print("  相邻我方驻军：%d 个" % GameState.units_on_tile_neighbors(enemy_key).size())
		var br: Dictionary = GameState.simulate_battle(enemy_key)
		if br["ok"]:
			for line in br["lines"]:
				print("    %s" % str(line))
			print("  结果：%s（参战 %d 个，总伤害 %.1f，克制命中 %d 次）" % [
				"胜利" if br["won"] else "未决", int(br["attackers"]),
				float(br["damage"]), int(br["advantage_hits"])])
		else:
			print("  战斗无法进行：%s" % str(br["why"]))

	print("\n== 存档兼容（旧版 characters 迁移到 units） ==")
	var slot := 5
	# 构造一个旧格式存档
	var legacy := {
		"magic": GameState.SAVE_MAGIC, "version": 1,
		"saved_at": "legacy", "state": {
			"cycle": 7, "capital": "0,0", "tiles": GameState.state["tiles"],
			"characters": [{"id": "char_geo", "name": "岩构骑士", "rarity": 4,
				"group": "原神组", "kind": "square", "level": 12, "star": 4,
				"attr": {"atk": 42, "def": 30, "hp": 260, "spd": 3, "agi": 12},
				"equipped": {"weapon": "", "relic": ""}, "skills": []}],
			"equipment": [], "items": {}, "res": {}, "techs": [], "log": [],
		},
	}
	var f := FileAccess.open(GameState.slot_path(slot), FileAccess.WRITE)
	f.store_string(JSON.stringify(legacy, "  "))
	f.close()
	var ok := GameState.load_from_slot(slot)
	print("  读取旧存档 -> %s｜周期 %d｜单位 %d 个" % [ok, int(GameState.state["cycle"]),
		GameState.state["units"].size()])
	if not (GameState.state["units"] as Array).is_empty():
		var mu: Dictionary = GameState.state["units"][0]
		print("  迁移结果：%s（%s·%s，Lv.%d，经验 %d，文明组 %s）" % [
			str(mu["name"]), UnitDB.rank_name(str(mu["rank"])),
			UnitDB.profession_name(str(mu["profession"])), int(mu["level"]),
			int(mu["exp"]), CardDB.civ_group_of(mu)])
	GameState.delete_slot(slot)

	print("\n== 图鉴文明组分类 ==")
	for civ in CardDB.CIV_GROUPS:
		var n := 0
		for c in GameState.cards:
			if CardDB.civ_group_of(c) == civ:
				n += 1
		print("  %s：%d 项" % [civ, n])
	var general := 0
	for c2 in GameState.cards:
		if CardDB.civ_group_of(c2) == "":
			general += 1
	print("  通用（无文明组）：%d 项" % general)

	print("\n== 手册条目 ==")
	print("  共 %d 条，分组：%s" % [TermDB.all().size(), "、".join(TermDB.groups())])

	get_tree().quit(0)
