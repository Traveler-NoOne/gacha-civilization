extends Node
## 平衡性自检：用一个「自动玩家」跑 60 个周期，检查经济与压力曲线是否合理。
## 用法：godot --headless --path <项目> res://tests/autoplay.tscn

const CYCLES := 60

var rng := RandomNumberGenerator.new()
var pulls := 0
var claims := 0
var builds := 0


func _ready() -> void:
	rng.seed = 987654321
	GameState.new_game(424242)
	print("== 自动试玩：%d 个周期 ==" % CYCLES)
	print("%-6s %-8s %-8s %-8s %-6s %-6s %-6s %-6s %-8s %-6s" % [
		"周期", "食物", "生产力", "科研", "人力", "幸福", "稳定", "地块", "敌人", "威胁"])

	for i in CYCLES:
		_play_turn()
		var rep: Dictionary = GameState.end_cycle()
		if (i + 1) % 5 == 0 or i < 3:
			_print_row(int(rep["cycle"]))

	print("\n== 汇总 ==")
	print("建造 %d 次｜扩张 %d 次｜抽卡 %d 次" % [builds, claims, pulls])
	print("单位 %d 个｜装备 %d 件｜道具 %d 种" % [
		(GameState.state["units"] as Array).size(),
		(GameState.state["equipment"] as Array).size(),
		(GameState.state["items"] as Dictionary).size()])
	# v1.1：职业与位阶分布
	var prof_count := {}
	var rank_count := {}
	for u in GameState.state["units"]:
		var pn := UnitDB.profession_name(str(u.get("profession", "")))
		prof_count[pn] = int(prof_count.get(pn, 0)) + 1
		var rn := UnitDB.rank_name(str(u.get("rank", "")))
		rank_count[rn] = int(rank_count.get(rn, 0)) + 1
	print("职业分布：%s" % str(prof_count))
	print("位阶分布：%s" % str(rank_count))
	var team_parts: Array[String] = []
	var teams: Array = GameState.state["teams"]
	for i in teams.size():
		team_parts.append("%s %d/%d" % [str((teams[i] as Dictionary)["name"]),
			GameState.team_units(i).size(), UnitDB.UNITS_PER_TEAM])
	print("派驻单位 %d 个｜队伍编成：%s" % [
		GameState.state["units"].size() - GameState.idle_units().size(),
		"、".join(team_parts)])
	print("稳定度 %.1f%%｜幸福度 %.0f｜文化率 %.2f｜人力 %d/%d｜科技 %s" % [
		GameState.stability() * 100.0, GameState.happiness(), GameState.culture_rate(),
		int(GameState.state["pop_total"]), GameState.housing_capacity(),
		str(GameState.state["techs"])])
	print("生产力 %.0f｜食物 %.0f｜货币 %.0f｜科研 %.0f｜秩序结晶 %.0f｜凝聚力 %.0f" % [
		GameState.res("production"), GameState.res("food"), GameState.res("currency"),
		GameState.res("research"), GameState.res("order_crystal"), GameState.res("cohesion")])
	print("终极威胁 %d 个｜敌方地块 %d 个（上限 %d）" % [
		(GameState.state["threats"] as Array).size(), GameState.enemy_tiles().size(),
		WorldGen.enemy_cap(GameState.state)])
	var blocked := Gacha.check(GameState.state, Gacha.Pool.ROTATION)
	print("轮换抽卡可用：%s %s" % [blocked["ok"], blocked["why"]])
	print("最近日志：")
	var log: Array = GameState.state["log"]
	for e in log.slice(maxi(0, log.size() - 12)):
		print("  [%d] %s" % [int(e["cycle"]), str(e["text"])])
	get_tree().quit(0)


func _print_row(c: int) -> void:
	print("%-6d %-8.1f %-8.1f %-8.1f %-6d %-6.0f %-6.0f %-6d %-8d %-6d" % [
		c, GameState.res("food"), GameState.res("production"), GameState.res("research"),
		int(GameState.state["pop_total"]), GameState.happiness(), GameState.stability() * 100.0,
		GameState.owned_tiles().size(), GameState.enemy_tiles().size(),
		(GameState.state["threats"] as Array).size()])


# ---------------------------------------------------------------------------
# 一个简单但合理的自动玩家
# ---------------------------------------------------------------------------
func _play_turn() -> void:
	_assign_all_workers()
	_try_claim()
	_try_build()
	_try_recruit()
	_try_deploy()
	_try_form_team()
	_try_clear()
	_try_gacha()
	_try_research()


## v1.1：征兵（需要经典训练场地）
func _try_recruit() -> void:
	if GameState.state["units"].size() >= 12:
		return
	if GameState.free_pop() <= 0:
		return
	if GameState.res("food") < 60.0 or GameState.res("currency") < 200.0:
		return
	# 缺哪个职业就补哪个，尽量凑齐五种职业
	var have := {}
	for u in GameState.state["units"]:
		var p := str(u.get("profession", ""))
		have[p] = int(have.get(p, 0)) + 1
	var want := UnitDB.PROFESSION_ORDER[GameState.state["units"].size() % UnitDB.PROFESSION_ORDER.size()]
	for p2 in UnitDB.PROFESSION_ORDER:
		if int(have.get(p2, 0)) == 0:
			want = p2
			break
	GameState.recruit_soldier(want)


## v1.1：把待命单位派驻到「与敌人相邻」的地块
func _try_deploy() -> void:
	var idle := GameState.idle_units()
	if idle.is_empty():
		return
	# 找出与敌人相邻、且还有空位的地块
	var spots: Array[String] = []
	for enemy in GameState.enemy_tiles():
		for n in Hex.neighbors(WorldGen.coord_of(
				WorldGen.key_of(Vector2i(int(enemy["c"][0]), int(enemy["c"][1]))))):
			var nk := WorldGen.key_of(n)
			var nt := GameState.tile_at(nk)
			if nt.is_empty() or nt.get("owner", "") != "player":
				continue
			if GameState.units_on_tile(nk).size() >= UnitDB.UNITS_PER_TILE:
				continue
			if not spots.has(nk):
				spots.append(nk)
	# 没有前线就把单位留在首都
	if spots.is_empty():
		var cap_key: String = str(GameState.state["capital"])
		if GameState.units_on_tile(cap_key).size() < UnitDB.UNITS_PER_TILE:
			spots.append(cap_key)
	if spots.is_empty():
		return
	var u: Dictionary = idle[0]
	GameState.deploy_unit(str(u["uid"]), spots[0])


## v1.1：把最强的几个单位编进第一队（每队最多 4 个）
func _try_form_team() -> void:
	if GameState.team_units(0).size() >= UnitDB.UNITS_PER_TEAM:
		return
	var units: Array = GameState.state["units"].duplicate()
	units.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return UnitDB.power_of(a) > UnitDB.power_of(b))
	for u in units:
		if int(u.get("team", -1)) < 0:
			GameState.assign_team(str(u["uid"]), 0)
			return


func _assign_all_workers() -> void:
	# 把空闲人力优先分配给食物、其次生产、再教育：每个建筑都尽量填满
	var priority := ["classic_field", "classic_mill", "classic_workshop", "classic_mine", "classic_academy"]
	for bid in priority:
		for t in GameState.owned_tiles():
			if GameState.free_pop() <= 0:
				return
			var b := GameState.tile_building(t, bid)
			if b.is_empty():
				continue
			var key := WorldGen.key_of(Vector2i(int(t["c"][0]), int(t["c"][1])))
			var def := GameState.find_building(bid)
			if def == null:
				continue
			while GameState.free_pop() > 0 and int(b.get("workers", 0)) < def.max_workers(int(b["level"])):
				var r: Dictionary = GameState.assign_worker(key, bid, 1)
				if not r["ok"]:
					break


func _try_build() -> void:
	var tiles := GameState.owned_tiles()
	if tiles.is_empty():
		return
	var sh := GameState.current_stronghold()
	if not sh.is_empty() and (sh.get("queue", []) as Array).size() >= 4:
		return   # 队列太长就先不再排
	var order := ["classic_field", "classic_workshop", "classic_mine", "classic_house",
		"classic_academy", "classic_bakery", "classic_training_ground"]
	for bid in order:
		var def := GameState.find_building(bid)
		if def == null:
			continue
		for t in tiles:
			var key := WorldGen.key_of(Vector2i(int(t["c"][0]), int(t["c"][1])))
			if not GameState.can_build(t, def)["ok"]:
				continue
			var r: Dictionary = GameState.build(key, bid)   # 够则立即，否则入队
			if r["ok"]:
				builds += 1
			return
	# 有建筑就尝试升级
	for t in tiles:
		var key2 := WorldGen.key_of(Vector2i(int(t["c"][0]), int(t["c"][1])))
		for b in t.get("buildings", []):
			var def2 := GameState.find_building(str(b.get("id", "")))
			if def2 == null or int(b.get("level", 1)) >= def2.level_cap():
				continue
			var r2: Dictionary = GameState.request_upgrade_by_bid(key2, str(b.get("bid", "")))
			if r2["ok"]:
				builds += 1
			return


func _try_claim() -> void:
	var cks := WorldGen.claimable_keys(GameState.state)
	if cks.is_empty():
		return
	# v1.3.1：扩张消耗行政点数
	if GameState.res("admin") < WorldGen.claim_cost(GameState.state):
		return
	var r: Dictionary = WorldGen.claim(GameState.state, cks[0])
	if r["ok"]:
		claims += 1


func _try_clear() -> void:
	if GameState.enemy_tiles().is_empty():
		return
	for t in GameState.enemy_tiles():
		var key := WorldGen.key_of(Vector2i(int(t["c"][0]), int(t["c"][1])))
		var chk := WorldGen.can_clear(GameState.state, key)
		if chk["ok"]:
			var r: Dictionary = WorldGen.clear_tile(GameState.state, key, rng)
			if r["ok"]:
				return


func _try_gacha() -> void:
	if GameState.state["cycle"] < 3:
		return
	# 优先发展抽卡（免费），但不要堆太多终极威胁
	var threats: Array = GameState.state["threats"]
	if GameState.res("cohesion") >= Consts.DRAW_COST_COHESION * 3.0 and threats.size() < 2:
		var r: Dictionary = Gacha.draw(GameState.state, Gacha.Pool.ROTATION, rng)
		if r["ok"]:
			pulls += 1
			return
	if GameState.res("order_crystal") >= 5.0 and GameState.state["cycle"] % 5 == 0:
		var r2: Dictionary = Gacha.draw(GameState.state, Gacha.Pool.RESOURCE, rng)
		if r2["ok"]:
			pulls += 1
			return
	if threats.size() < 2 and GameState.state["cycle"] % 10 == 0 and GameState.player_force() > 90.0:
		var r3: Dictionary = Gacha.draw(GameState.state, Gacha.Pool.DEVELOPMENT, rng)
		if r3["ok"]:
			pulls += 1


func _try_research() -> void:
	for t in Consts.TECHS:
		var chk := GameState.can_research(str(t["id"]))
		if chk["ok"]:
			GameState.research(str(t["id"]))
			return
