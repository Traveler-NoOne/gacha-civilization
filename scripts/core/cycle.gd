class_name Cycle
extends RefCounted
## 周期结算：一次「结束周期」里发生的全部事情 ✓
##
## 顺序（就是文档里的核心循环，别随便调换）：
##   建筑产出 → 领地基础产出 → 维护 → 生产力入队 → 人口 → 世界演化 →
##   世界泡货币 → 行政点数 → 单位经验 → 自动存档 ✓
## ⚠️ 需要状态时一律传 `state`；需要随机数时传 `rng` ✓
##
static func end_cycle(state: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var report := {
		"cycle": int(state["cycle"]),
		"income": {},
		"upkeep": {},
		"pop_change": 0,
		"events": [],
		"happiness": Derived.happiness(state),
		"stability": Derived.stability(state),
	}

	# 1. 建筑产出
	var income := {}
	for t in TileManager.owned_tiles(state):
		var y := Buildings.tile_yield(t)
		for k in y.keys():
			income[k] = float(income.get(k, 0.0)) + float(y[k])
	# 民居金币
	for t in TileManager.owned_tiles(state):
		for b in t.get("buildings", []):
			if b.get("id", "") == "classic_house":
				income["currency"] = float(income.get("currency", 0.0)) + Derived.housing_gold(state, int(b.get("level", 1)))

	# 2. 领地基础产出与建筑维护
	var owned_list := TileManager.owned_tiles(state)
	if not owned_list.is_empty():
		income["production"] = float(income.get("production", 0.0)) \
			+ Consts.PRODUCTION_PER_TILE * float(owned_list.size())
	var upkeep := {}
	for t in owned_list:
		for b in t.get("buildings", []):
			upkeep["production"] = float(upkeep.get("production", 0.0)) \
				+ Consts.BUILDING_UPKEEP_PRODUCTION * float(b.get("level", 1))

	# 3. 人口食物维护
	var pop := int(state["pop_total"])
	upkeep["food"] = float(upkeep.get("food", 0.0)) + Consts.FOOD_UPKEEP_PER_POP * float(pop)

	# 3.5 v1.5：单位维护费（公民）+ 客人食物开销
	Units._units_upkeep_into(state, income, upkeep)

	# 4. 结算
	#   生产力单独处理（v1.3.1）：先补维护（不够用货币抵），再填建造队列，
	#   最后把剩余存起来（上限 PRODUCTION_STORE_CAP，超出作废）
	var prod_in := float(income.get("production", 0.0))
	var prod_upk := float(upkeep.get("production", 0.0))
	for k in income.keys():
		if str(k) != "production":
			Res.add(GameState.state, k, float(income[k]))
	for k in upkeep.keys():
		if str(k) != "production":
			Res.add(GameState.state, k, -float(upkeep[k]))
	var prod_avail := prod_in - prod_upk
	if prod_avail < 0.0:
		var short := -prod_avail
		Res.add(GameState.state, "currency", -short * 2.0)
		report["events"].append("生产力不足，用货币抵付维护 %.0f" % short)
		prod_avail = 0.0
	var leftover := Buildings.process_queue(state, prod_avail)
	var room := maxf(0.0, Consts.PRODUCTION_STORE_CAP - Res.amount(GameState.state, "production"))
	var added := minf(leftover, room)
	if added > 0.0:
		Res.add(GameState.state, "production", added)
	# 夹取（含被外部直接赋值超过上限的情况）
	if Res.amount(GameState.state, "production") > Consts.PRODUCTION_STORE_CAP:
		Res.add(GameState.state, "production", -(Res.amount(GameState.state, "production") - Consts.PRODUCTION_STORE_CAP))
	if leftover - added > 0.001:
		report["events"].append("生产力盈余超出存储上限（%d），%.1f 点作废。" % [
			int(Consts.PRODUCTION_STORE_CAP), leftover - added])

	# 4.5 v2026-10-25：建筑成熟（造林场 4 个周期后长成树林 → 转成林场）
	#     放在结算之后：本周期仍按"未成熟"算，从下个周期开始按林场产出 ✓
	_tick_growth(state, report)

	report["income"] = income
	report["upkeep"] = upkeep

	# 5. 人口增长（受幸福度与住房上限影响）
	var happy := Derived.happiness(state)
	var cap := Derived.housing_capacity(state)
	var growth := 0
	if pop < cap:
		var chance := 0.0
		if Res.amount(GameState.state, "food") > 10.0:
			chance = 0.35 + (happy - 50.0) * 0.004
		if rng.randf() < clampf(chance, 0.0, 0.95):
			growth = 1
	if Res.amount(GameState.state, "food") <= 0.0 and pop > 1 and rng.randf() < 0.5:
		growth = -1
		report["events"].append("食物耗尽，有人离开了部落。")
	state["pop_total"] = clampi(pop + growth, 1, Consts.POP_HARD_CAP)
	report["pop_change"] = growth

	# 6. 敌人与世界演化
	Threats.evolve(state, rng, report)

	# 7. 周期推进
	state["cycle"] = int(state["cycle"]) + 1
	state["playtime"] = float(state.get("playtime", 0.0)) + 1.0

	# 8. 稳定度过低会流失人力（保留保底人口与最低稳定度，避免死亡螺旋）
	var st := Derived.stability(state)
	if st < 0.30 and int(state["pop_total"]) > Consts.POP_FLOOR and rng.randf() < 0.5:
		state["pop_total"] = maxi(Consts.POP_FLOOR, int(state["pop_total"]) - 1)
		report["events"].append("稳定度 %.0f%%，人力流失。" % (st * 100.0))

	# 9. 抽卡货币的周期结算（秩序结晶按等级，凝聚力按幸福度 × 文化率）
	settle_gacha_currency(state, report)

	# 9.5 行政点数的周期结算（基底 + 限时 buff/debuff + 当期收支项；见 v1.3.1）
	Admin.settle(state, report)

	# 9.6 v1.8.3：政事队列推进。
	# 必须排在 9.5 之后 —— 它吃的是"本期刚入账的行政点数"
	#（与规划队列吃当期生产力同一套手感）。
	Decrees.process_queue(state, float((report.get("income", {}) as Dictionary).get("admin", 0.0)))

	# 10. 单位经验：通过周期循环缓缓增长（每个单位最多因此获得 100 点）
	Units.grow_unit_exp(state, report)

	# 10.5 v1.5：客人离去判定 + 单位移动力重置
	Units.guest_leave_tick(state, rng, report)
	Units.reset_unit_moves(state)

	Derived.recompute(state)
	report["happiness"] = Derived.happiness(state)
	report["stability"] = Derived.stability(state)
	Journal.add(state, "第 %d 周期结束：%s" % [report["cycle"], _report_line(state, income, upkeep, growth)], "cycle")
	for e in report["events"]:
		Journal.add(state, e, "warn")

	# 11. 自动存档（按全局设置里的「自动存档周期数」，默认每周期）
	var interval := AppSettings.autosave_interval()
	var due := (int(state["cycle"]) - 1) % interval == 0
	if due:
		Save.autosave(GameState.state)
	report["autosaved"] = due
	report["autosave_interval"] = interval
	GameState.state_changed.emit()
	return report


static func _report_line(state: Dictionary, income: Dictionary, upkeep: Dictionary, pop_change: int) -> String:
	var inc: Array[String] = []
	for k in income.keys():
		inc.append("+%.1f %s" % [float(income[k]), Consts.res_name(k)])
	var upk: Array[String] = []
	for k in upkeep.keys():
		upk.append("-%.1f %s" % [float(upkeep[k]), Consts.res_name(k)])
	var pop_text := "人力不变"
	if pop_change > 0:
		pop_text = "人力 +%d" % pop_change
	elif pop_change < 0:
		pop_text = "人力 %d" % pop_change
	return "收入[%s] 支出[%s] %s" % ["、".join(inc), "、".join(upk), pop_text]


## 玩家等级：由科技、领地、周期共同决定（用于秩序结晶的周期结算）
static func player_level(state: Dictionary) -> int:
	return 1 + int(state["techs"].size()) + int(float(TileManager.owned_tiles(state).size()) / 4.0) \
		+ int(float(state["cycle"]) / 10.0)


## 每周期结算的抽卡货币
static func settle_gacha_currency(state: Dictionary, report: Dictionary) -> void:
	var lv := player_level(state)
	var crystal := Consts.CRYSTAL_PER_CYCLE + Consts.CRYSTAL_PER_LEVEL * float(lv)
	Res.add(GameState.state, "order_crystal", crystal)
	var hp := Derived.happiness(state)
	var culture := Derived.culture_rate(state)
	var cohesion := (Consts.COHESION_PER_CYCLE + Consts.COHESION_PER_HAPPINESS * hp) \
		* (1.0 + culture * Consts.COHESION_CULTURE_BONUS)
	# v1.5：未招募的客人也会提供一点凝聚力
	var guest_coh := Consts.GUEST_COHESION_PER_CYCLE * float(Units.guest_units(state).size())
	cohesion += guest_coh
	Res.add(GameState.state, "cohesion", cohesion)
	report["income"]["order_crystal"] = float(report["income"].get("order_crystal", 0.0)) + crystal
	report["income"]["cohesion"] = float(report["income"].get("cohesion", 0.0)) + cohesion


## 建筑成熟：累计 age，达到 growth_cycles 时加地物 + 换成成熟建筑 ✓
static func _tick_growth(state: Dictionary, report: Dictionary) -> void:
	for t in TileManager.owned_tiles(state):
		for b in t.get("buildings", []):
			var def := BuildingDB.find(str(b.get("id", "")))
			if def == null or def.growth_cycles <= 0:
				continue
			var age := int(b.get("age", 0)) + 1
			b["age"] = age
			if age < def.growth_cycles:
				continue
			if def.mature_cover != "":
				t["cover"] = def.mature_cover
			if def.mature_to_id != "":
				var old_name := def.display_name
				var nd := BuildingDB.find(def.mature_to_id)
				b["id"] = def.mature_to_id
				b["level"] = 1
				b["workers"] = 0
				b.erase("age")
				var msg := "%s 长成树林，已转为%s。" % [old_name,
					nd.display_name if nd != null else def.mature_to_id]
				report["events"].append(msg)
				Journal.add(state, msg, "build")
