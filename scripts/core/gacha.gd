class_name Gacha
extends RefCounted
## 世界泡系统：召唤 / 打捞 / 发展 三个子系统。
##
## 文档要点：
##  - 召唤系统：消耗凝聚力，只能唤来角色和装备；每次召唤大概率生成游荡敌人（概率不变），
##    90 次游荡敌人后必定生成一次高危游荡敌人。
##  - 打捞系统：消耗秩序结晶，只能捞出材料 / 资源 / 道具；每次打捞小概率生成高危据点（次数越多概率越高，
##    生成后重置），极小概率生成极度高危据点（概率不变，但生成 10 次高危据点后必定生成一次）。
##  - 发展系统：不消耗货币，但必定生成终极威胁；可以抽到各种功能。
##  - 稳定度低于 10% 或 无主地块低于 10 个时无法进行世界泡操作。

enum Pool { ROTATION, RESOURCE, DEVELOPMENT }

const POOL_NAMES := {
	Pool.ROTATION: "轮换",
	Pool.RESOURCE: "资源",
	Pool.DEVELOPMENT: "发展",
}


static func pool_cost(p: int) -> Dictionary:
	match p:
		Pool.ROTATION:
			return {"cohesion": Consts.DRAW_COST_COHESION}
		Pool.RESOURCE:
			return {"order_crystal": Consts.DRAW_COST_CRYSTAL}
		_:
			return {}


## 抽卡限制检查
static func check(state: Dictionary, p: int) -> Dictionary:
	var st := GameState.stability()
	if st < Consts.STABILITY_MIN_BLOCK:
		return {"ok": false, "why": "稳定度仅 %.0f%%，低于 10%%，无法进行世界泡操作" % (st * 100.0)}
	var free := GameState.free_tiles().size()
	if free < Consts.FREE_TILE_MIN_BLOCK:
		return {"ok": false, "why": "无主地块仅 %d 个（少于 10），无法进行世界泡操作" % free}
	var cost := pool_cost(p)
	if not GameState.can_afford(cost):
		return {"ok": false, "why": "货币不足（需要 %s）" % GameState.cost_to_text(cost)}
	return {"ok": true, "why": ""}


## 单抽
static func draw(state: Dictionary, p: int, rng: RandomNumberGenerator) -> Dictionary:
	var chk := check(state, p)
	if not chk["ok"]:
		return {"ok": false, "why": chk["why"], "cards": [], "events": []}

	var cost := pool_cost(p)
	if not cost.is_empty():
		GameState.pay(cost)

	var pool_cards := candidates(state, p)
	if pool_cards.is_empty():
		return {"ok": false, "why": "该卡池当前没有可抽取内容", "cards": [], "events": []}

	var results: Array[Dictionary] = []
	if p == Pool.DEVELOPMENT:
		# 发展页：必定产出一个功能（按权重），并额外单独发放终极威胁
		var r := _roll_card(state, pool_cards, rng, Pool.DEVELOPMENT)
		if not r.is_empty():
			results.append(r)
	else:
		# 每次抽卡 1~? 张：轮换页保底 1 张，偶尔双黄
		var n := 1
		if p == Pool.ROTATION and rng.randf() < 0.12:
			n = 2
		for i in n:
			var rc := _roll_card(state, pool_cards, rng, p)
			if not rc.is_empty():
				results.append(rc)

	var events: Array[String] = []

	# 结算卡片效果
	for c in results:
		_apply_card(state, c)

	# 卡池相关的世界事件
	match p:
		Pool.ROTATION:
			# v1.5：召唤会一并带来游荡敌人 —— 他们并非召唤的目标，只能寻找机会和漏洞挤进来
			var wd := WorldGen.maybe_spawn_wanderer(state, rng)
			if wd["spawned"]:
				if wd["high"]:
					events.append("⚠ 高危游荡敌人在 %s 出现（%d 次保底触发）" % [wd["key"], Consts.WANDER_PITY])
					GameState.add_log("高危游荡敌人出现于 %s。" % wd["key"], "danger")
				else:
					events.append("游荡敌人出现在 %s" % wd["key"])
					GameState.add_log("游荡敌人出现于 %s。" % wd["key"], "danger")
		Pool.RESOURCE:
			# v1.5：直接从量子之海汲取更容易被盯上 —— 一旦被入侵，就是据点形式
			var hz := WorldGen.maybe_spawn_hazard(state, rng)
			if hz["spawned"]:
				if hz["extreme"]:
					events.append("⚠ 极度高危据点出现在 %s（%d 次高危据点保底触发）" % [hz["key"], Consts.HAZARD_PITY])
					GameState.add_log("极度高危据点生成于 %s。" % hz["key"], "danger")
				else:
					events.append("高危据点出现在 %s" % hz["key"])
					GameState.add_log("高危据点生成于 %s。" % hz["key"], "danger")
		Pool.DEVELOPMENT:
			var th := WorldGen.spawn_ultimate_threat(state, rng)
			events.append("☠ 终极威胁降临于 %s：将在 %d 个周期后直扑首都" % [th["key"], Consts.THREAT_WANDER_CYCLES])
			GameState.add_log("终极威胁降临于 %s。" % th["key"], "danger")
			var thr: Dictionary = state["pity"]["development"] if state["pity"].has("development") else {}
			if not thr.is_empty():
				thr["total"] = int(thr.get("total", 0)) + 1

	GameState.state_changed.emit()
	return {"ok": true, "why": "", "cards": results, "events": events}


## 十连
static func draw_ten(state: Dictionary, p: int, rng: RandomNumberGenerator) -> Dictionary:
	var all: Array[Dictionary] = []
	var events: Array[String] = []
	for i in 10:
		var r := draw(state, p, rng)
		if not r["ok"]:
			if i == 0:
				return r
			break
		all.append_array(r["cards"])
		for e in r["events"]:
			if not events.has(e):
				events.append(e)
	return {"ok": true, "why": "", "cards": all, "events": events}


## 当前卡池的可抽取内容
static func candidates(state: Dictionary, p: int) -> Array[Dictionary]:
	var cards: Array[Dictionary] = GameState.cards
	match p:
		Pool.ROTATION:
			return CardDB.rotation_cards(cards)
		Pool.RESOURCE:
			return CardDB.resource_cards(cards, str(state.get("active_group", "提瓦特")))
		_:
			return CardDB.development_cards(cards)


## 稀有度权重（含保底）
static func rarity_weights(state: Dictionary, p: int) -> Dictionary:
	var w := Consts.RARITY_WEIGHTS.duplicate()
	var pity: Dictionary = state["pity"]
	if p == Pool.ROTATION:
		var pr: Dictionary = pity["rotation"]
		var since5 := int(pr.get("since5", 0))
		if since5 >= Consts.PITY_HARD - 1:
			return {5: 1.0}
		if since5 >= Consts.PITY_SOFT:
			# 软保底：每抽提升 5★ 权重
			var steps := float(since5 - Consts.PITY_SOFT + 1)
			w[5] = float(w[5]) + steps * 6.0
		if int(pr.get("since4", 0)) >= 9:
			w[4] = float(w[4]) + 40.0
	elif p == Pool.RESOURCE:
		var pr2: Dictionary = pity["resource"]
		var s4 := int(pr2.get("since4", 0))
		if s4 >= Consts.PITY_HARD_RES - 1:
			return {4: 1.0}
		if s4 >= Consts.PITY_SOFT_RES:
			w[4] = float(w[4]) + float(s4 - Consts.PITY_SOFT_RES + 1) * 8.0
	else:
		# 发展页偏向高稀有度
		w[1] = 30.0
		w[2] = 30.0
		w[3] = 25.0
		w[4] = 12.0
		w[5] = 3.0
	return w


static func _roll_card(state: Dictionary, pool_cards: Array[Dictionary],
		rng: RandomNumberGenerator, p: int) -> Dictionary:
	# 1. 先按权重决定稀有度
	var weights := rarity_weights(state, p)
	var rarity := _weighted_pick(weights, rng)
	# 2. 在该稀有度中筛选
	var filtered: Array[Dictionary] = []
	for c in pool_cards:
		if int(c["rarity"]) == rarity:
			filtered.append(c)
	if filtered.is_empty():
		# 稀有度没有对应卡片就整体回退
		filtered = pool_cards
		rarity = int(filtered[rng.randi() % filtered.size()]["rarity"])
	var picked: Dictionary = filtered[rng.randi() % filtered.size()].duplicate(true)

	# 3. 更新保底计数
	var pity: Dictionary = state["pity"]
	if p == Pool.ROTATION:
		var pr: Dictionary = pity["rotation"]
		pr["total"] = int(pr.get("total", 0)) + 1
		if rarity >= 5:
			pr["since5"] = 0
			pr["since4"] = 0
		else:
			pr["since5"] = int(pr.get("since5", 0)) + 1
			if rarity >= 4:
				pr["since4"] = 0
			else:
				pr["since4"] = int(pr.get("since4", 0)) + 1
	elif p == Pool.RESOURCE:
		var pr2: Dictionary = pity["resource"]
		pr2["total"] = int(pr2.get("total", 0)) + 1
		if rarity >= 4:
			pr2["since4"] = 0
		else:
			pr2["since4"] = int(pr2.get("since4", 0)) + 1
	picked["new"] = true
	return picked


static func _weighted_pick(weights: Dictionary, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for k in weights.keys():
		total += float(weights[k])
	var roll := rng.randf() * total
	var acc := 0.0
	var last := 1
	for k in weights.keys():
		last = int(k)
		acc += float(weights[k])
		if roll <= acc:
			return int(k)
	return last


## 卡片数据里战斗属性是平铺的（atk/def/hp/spd/agi），这里整理成字典
static func _attr_of(c: Dictionary) -> Dictionary:
	var out := {}
	for k in ["atk", "def", "hp", "spd", "agi"]:
		if c.has(k):
			out[k] = int(c[k])
	return out


## 卡片落地效果
static func _apply_card(state: Dictionary, c: Dictionary) -> void:
	var pool: String = c["pool"]
	var aff: Dictionary = state["affinity"]
	aff[c["group"]] = int(aff.get(c["group"], 0)) + 1

	match pool:
		"character":
			# v1.1：抽到的角色直接生成带「职业 / 位阶 / 经验」的单位条目
			var units: Array = state["units"]
			# v1.5：召唤来的角色以「客人」身份进入至宝
			var nu := UnitDB.from_card(c)
			nu["acquired_cycle"] = int(state["cycle"])
			nu["move_left"] = GameState.max_move(nu)
			units.append(nu)
		"weapon", "relic":
			var eq: Array = state["equipment"]
			eq.append({
				"id": c["id"], "name": c["name"], "rarity": int(c["rarity"]),
				"group": c["group"], "kind": c["kind"], "slot": pool,
				"attr": _attr_of(c),
			})
		"item", "material", "advanced":
			var items: Dictionary = state["items"]
			items[c["id"]] = int(items.get(c["id"], 0)) + 1
			if c.has("give"):
				for k in (c["give"] as Dictionary).keys():
					GameState.add_res(str(k), float(c["give"][k]))
		"function":
			var items2: Dictionary = state["items"]
			items2[c["id"]] = int(items2.get(c["id"], 0)) + 1
			# 功能卡的特殊效果
			if c.has("spawn_resource"):
				var r := WorldGen.spawn_resource_node(state, GameState._rng, int(c["spawn_resource"]))
				if r["ok"]:
					GameState.add_log("资源地脉生效：%s 出现 %s资源点。" % [r["key"], Consts.res_name(str(r["resource"]))], "world")
			if c.has("tech"):
				var flag := str(c["tech"])
				if not (state["techs_owned_flags"] as Array).has(flag):
					state["techs_owned_flags"].append(flag)
			if c.has("research"):
				GameState.add_res("research", float(c["research"]))
			if c.has("regen"):
				var rk := str(c["regen"])
				if not (state["techs_owned_flags"] as Array).has("regen_" + rk):
					state["techs_owned_flags"].append("regen_" + rk)
			if c.has("expand_map"):
				var added := WorldGen.expand_map(state, GameState._rng, int(c["expand_map"]))
				if added > 0:
					GameState.add_log("营地扩建：可探索范围增加了 %d 格。" % added, "world")
		_:
			pass


## 手动 / 按天轮换卡组
static func rotate_group(state: Dictionary, rng: RandomNumberGenerator) -> String:
	var groups := CardDB.GROUPS
	var cur := str(state.get("active_group", "提瓦特"))
	var idx := groups.find(cur)
	if idx < 0:
		idx = 0
	var nxt: String = str(groups[(idx + 1) % groups.size()])
	state["active_group"] = nxt
	GameState.add_log("卡组轮换：%s -> %s" % [cur, nxt], "gacha")
	return nxt


## 当前池的保底信息文本
static func pity_text(state: Dictionary, p: int) -> String:
	var pity: Dictionary = state["pity"]
	match p:
		Pool.ROTATION:
			var pr: Dictionary = pity["rotation"]
			return "5★保底还差 %d 抽（软保底 %d）｜4★保底还差 %d 抽｜累计 %d 抽" % [
				maxi(0, Consts.PITY_HARD - int(pr.get("since5", 0))),
				Consts.PITY_SOFT, maxi(0, 10 - int(pr.get("since4", 0))), int(pr.get("total", 0))]
		Pool.RESOURCE:
			var pr2: Dictionary = pity["resource"]
			return "4★保底还差 %d 抽（软保底 %d）｜累计 %d 抽" % [
				maxi(0, Consts.PITY_HARD_RES - int(pr2.get("since4", 0))),
				Consts.PITY_SOFT_RES, int(pr2.get("total", 0))]
		_:
			var pr3: Dictionary = pity["development"]
			return "发展系统不消耗货币｜必定生成终极威胁｜累计 %d 次" % int(pr3.get("total", 0))