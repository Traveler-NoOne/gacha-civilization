class_name Threats
extends RefCounted
## 敌人与威胁系统 ✓
##
## 为什么单独一个文件：这些全是"**世界跑起来之后**"的事（刷怪 / 演化 / 打玩家）✗
## 和"造格子"（`scripts/worldgen/builder.gd`）与"改格子"（`tile_manager`）都不是一回事 ✓
##
## 判据：**只跟敌人有关** → 放这里 ✓
##   · 危险据点 / 游荡敌人 / 终极威胁的生成
##   · 每周期演化 `evolve()`（据点吐兵 / 游荡 / 威胁扑首都 / 打玩家 / 超上限消散）
##   · 攻击结算 `_damage_tile()`（破坏建筑 → 地块转无主）
##
## ⚠️ 依赖方向：本文件 → `TileManager`（坐标工具 / 计数 / amount_cap）✓ **单向** ✓


## 高危据点：打捞（资源池）时小概率生成 —— 直接从量子之海汲取更容易被盯上
static func maybe_spawn_hazard(state: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var hz: Dictionary = state["hazard"]
	var chance := float(hz.get("chance", Consts.HAZARD_BASE_CHANCE))
	var result := {"spawned": false, "extreme": false, "key": ""}
	if rng.randf() >= chance:
		hz["chance"] = minf(1.0, chance + Consts.HAZARD_CHANCE_PER_DRAW)
		return result
	# 触发：重置概率
	hz["chance"] = Consts.HAZARD_BASE_CHANCE
	hz["count"] = int(hz.get("count", 0)) + 1
	hz["pity"] = int(hz.get("pity", 0)) + 1
	var extreme := false
	if int(hz["pity"]) >= Consts.HAZARD_PITY:
		extreme = true
		hz["pity"] = 0
	var cands := _enemy_spawn_candidates(state)
	if cands.is_empty():
		return result
	var key: String = cands[rng.randi() % cands.size()]
	var t: Dictionary = state["tiles"][key]
	t["owner"] = Consts.Owner.ENEMY
	t["danger"] = true
	t["force"] = Consts.EXTREME_HAZARD_FORCE if extreme else Consts.HAZARD_FORCE
	t["name"] = "极度高危据点" if extreme else "高危据点"
	t["spawned_cycle"] = int(state["cycle"])
	t["discovered"] = true
	result = {"spawned": true, "extreme": extreme, "key": key}
	return result


## 游荡敌人：召唤（轮换池）时大概率生成 —— 他们并非召唤的目标，只能寻找漏洞挤进来
static func maybe_spawn_wanderer(state: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var wd: Dictionary = state["wander"]
	var result := {"spawned": false, "high": false, "key": ""}
	if rng.randf() >= Consts.WANDER_BASE_CHANCE:
		return result
	wd["count"] = int(wd.get("count", 0)) + 1
	wd["pity"] = int(wd.get("pity", 0)) + 1
	var high := false
	if int(wd["pity"]) >= Consts.WANDER_PITY:
		high = true
		wd["pity"] = 0
	var cands := _enemy_spawn_candidates(state)
	if cands.is_empty():
		return result
	var key: String = cands[rng.randi() % cands.size()]
	var t: Dictionary = state["tiles"][key]
	t["owner"] = Consts.Owner.ENEMY
	t["force"] = Consts.HIGH_WANDER_FORCE if high else Consts.WANDER_FORCE
	t["name"] = "高危游荡敌人" if high else "游荡敌人"
	t["wander"] = true
	t["spawned_cycle"] = int(state["cycle"])
	result = {"spawned": true, "high": high, "key": key}
	return result


## 终极威胁：发展系统必定生成（不受普通敌人数量上限限制）
static func spawn_ultimate_threat(state: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var cands := _threat_spawn_candidates(state)
	var key := ""
	if cands.is_empty():
		# 实在没有空地，就放在首都相邻的地块上
		var cap0 := TileManager.coord_of(str(state["capital"]))
		for d in Hex.DIRECTIONS:
			var nk := TileManager.key_of(cap0 + d)
			if (state["tiles"] as Dictionary).has(nk):
				key = nk
				break
		if key == "":
			key = str(state["capital"])
	else:
		# 尽量远离首都生成
		var cap := TileManager.coord_of(str(state["capital"]))
		var best := -1
		for k in cands:
			var d := Hex.distance(TileManager.coord_of(k), cap)
			if d > best:
				best = d
				key = k
	var tiles: Dictionary = state["tiles"]
	tiles[key]["owner"] = Consts.Owner.ENEMY
	var t: Dictionary = tiles[key]
	t["threat"] = true
	t["force"] = Consts.THREAT_FORCE
	t["name"] = "终极威胁"
	t["threat_timer"] = Consts.THREAT_WANDER_CYCLES
	t["discovered"] = true
	var threats: Array = state["threats"]
	threats.append({"key": key, "timer": Consts.THREAT_WANDER_CYCLES})
	return {"ok": true, "key": key}


## 终极威胁的出生点：任意无主的地块，不必远离首都（只要求不是首都本身）
static func _threat_spawn_candidates(state: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var tiles: Dictionary = state["tiles"]
	var cap := TileManager.coord_of(str(state["capital"]))
	for k in tiles.keys():
		var t: Dictionary = tiles[k]
		if t.get("owner", Consts.Owner.NONE) != Consts.Owner.NONE:
			continue
		if TileManager.coord_of(k) == cap:
			continue
		if TileLib.is_water(t):
			continue
		out.append(k)
	return out


static func _enemy_spawn_candidates(state: Dictionary) -> Array[String]:
	var out: Array[String] = []
	# 敌人数量上限：超过就不再生成新敌人，否则稳定度会陷入死亡螺旋
	if _enemy_tile_count(state) >= enemy_cap(state):
		return out
	var tiles: Dictionary = state["tiles"]
	for k in tiles.keys():
		var t: Dictionary = tiles[k]
		if t.get("owner", Consts.Owner.NONE) != Consts.Owner.NONE:
			continue
		# 不直接刷在首都旁边
		if Hex.distance(TileManager.coord_of(k), TileManager.coord_of(str(state["capital"]))) < 2:
			continue
		if TileLib.is_water(t):
			continue
		out.append(k)
	return out


static func _enemy_tile_count(state: Dictionary) -> int:
	return TileManager.enemy_tile_count(state)


## 世界上同时允许存在的敌方地块数量上限
static func enemy_cap(state: Dictionary) -> int:
	var owned := TileManager.owned_tile_count(state)
	return Consts.ENEMY_CAP_BASE + int(float(owned) * Consts.ENEMY_CAP_PER_OWNED) \
		+ int(float(state.get("cycle", 1)) * Consts.ENEMY_CAP_PER_CYCLE)


# ===========================================================================
# 每周期演化
# ===========================================================================
static func evolve(state: Dictionary, rng: RandomNumberGenerator, report: Dictionary) -> void:
	var cycle := int(state["cycle"])
	var tiles: Dictionary = state["tiles"]

	# 1. 高危据点不断生成游荡敌人
	var danger_count := 0
	for k in tiles.keys():
		var t: Dictionary = tiles[k]
		if t.get("danger", false) and t.get("owner", Consts.Owner.NONE) == Consts.Owner.ENEMY:
			danger_count += 1
			if rng.randf() < 0.35:
				var cands := _enemy_spawn_candidates(state)
				if not cands.is_empty():
					var nk: String = cands[rng.randi() % cands.size()]
					var nt: Dictionary = tiles[nk]
					nt["owner"] = Consts.Owner.ENEMY
					nt["force"] = Consts.WANDER_FORCE
					nt["name"] = "游荡敌人"
					nt["wander"] = true
					nt["spawned_cycle"] = cycle

	# 2. 游荡敌人随机移动
	var wander_keys: Array[String] = []
	for k in tiles.keys():
		if (tiles[k] as Dictionary).get("wander", false) and (tiles[k] as Dictionary).get("owner", Consts.Owner.NONE) == Consts.Owner.ENEMY:
			wander_keys.append(k)
	for k in wander_keys:
		var t: Dictionary = tiles[k]
		if not tiles.has(k) or t.get("owner", Consts.Owner.NONE) != Consts.Owner.ENEMY:
			continue
		var ns := Hex.neighbors(TileManager.coord_of(k))
		var pool: Array[String] = []
		for n in ns:
			var nk := TileManager.key_of(n)
			if tiles.has(nk) and (tiles[nk] as Dictionary).get("owner", Consts.Owner.NONE) == Consts.Owner.NONE:
				pool.append(nk)
		if pool.is_empty():
			continue
		var dest: String = pool[rng.randi() % pool.size()]
		var dt: Dictionary = tiles[dest]
		if dt.get("owner", Consts.Owner.NONE) == Consts.Owner.NONE:
			dt["owner"] = Consts.Owner.ENEMY
			dt["force"] = float(t.get("force", Consts.WANDER_FORCE))
			dt["name"] = str(t.get("name", "游荡敌人"))
			dt["wander"] = true
			dt["spawned_cycle"] = int(t.get("spawned_cycle", cycle))
			t["owner"] = Consts.Owner.NONE
			t["force"] = 0.0
			t["wander"] = false
			t["name"] = ""

	# 3. 终极威胁：先游荡，计时结束直扑首都
	var threats: Array = state["threats"]
	for th in threats:
		var key: String = th.get("key", "")
		if not tiles.has(key):
			continue
		var t: Dictionary = tiles[key]
		th["timer"] = int(th.get("timer", 0)) - 1
		if int(th["timer"]) <= 0:
			# 计时结束：朝首都直线前进
			var cap := TileManager.coord_of(str(state["capital"]))
			var cur := TileManager.coord_of(key)
			var best := key
			var bestd := Hex.distance(cur, cap)
			for n in Hex.neighbors(cur):
				var nk := TileManager.key_of(n)
				if not tiles.has(nk):
					continue
				var d := Hex.distance(n, cap)
				if d < bestd:
					bestd = d
					best = nk
			if best != key:
				var bt: Dictionary = tiles[best]
				if bt.get("owner", Consts.Owner.NONE) == Consts.Owner.PLAYER:
					# 直接攻击玩家地块
					report["events"].append("终极威胁抵达 %s，建筑被破坏！" % best)
					_damage_tile(state, best, rng, report)
					th["timer"] = 0
					continue
				t["owner"] = Consts.Owner.NONE
				t["threat"] = false
				t["force"] = 0.0
				t["name"] = ""
				bt["owner"] = Consts.Owner.ENEMY
				bt["threat"] = true
				bt["force"] = Consts.THREAT_FORCE
				bt["name"] = "终极威胁"
				bt["threat_timer"] = 0
				th["key"] = best
			else:
				# 已经贴着首都，攻击首都
				report["events"].append("终极威胁攻击首都！")
				_damage_tile(state, str(state["capital"]), rng, report)

	# 4. 敌人攻击相邻的玩家地块
	var enemy_keys: Array[String] = []
	for k in tiles.keys():
		if (tiles[k] as Dictionary).get("owner", Consts.Owner.NONE) == Consts.Owner.ENEMY:
			enemy_keys.append(k)
	for k in enemy_keys:
		var t: Dictionary = tiles[k]
		for n in Hex.neighbors(TileManager.coord_of(k)):
			var nk := TileManager.key_of(n)
			if not tiles.has(nk):
				continue
			var nt: Dictionary = tiles[nk]
			if nt.get("owner", Consts.Owner.NONE) != Consts.Owner.PLAYER:
				continue
			if rng.randf() < 0.25:
				_damage_tile(state, nk, rng, report)
			break

	# 4.5 敌人数量超过上限时，最老的游荡敌人自行消散（防止稳定度死亡螺旋）
	var cap := enemy_cap(state)
	var excess := _enemy_tile_count(state) - cap
	if excess > 0:
		var wander: Array[String] = []
		for k in tiles.keys():
			var t: Dictionary = tiles[k]
			if t.get("owner", Consts.Owner.NONE) == Consts.Owner.ENEMY and not t.get("threat", false):
				wander.append(k)
		wander.sort_custom(func(a: String, b: String) -> bool:
			return int((tiles[a] as Dictionary).get("spawned_cycle", 0)) \
				< int((tiles[b] as Dictionary).get("spawned_cycle", 0)))
		var removed := 0
		for k in wander:
			if removed >= excess:
				break
			var t2: Dictionary = tiles[k]
			t2["owner"] = Consts.Owner.NONE
			t2["force"] = 0.0
			t2["wander"] = false
			t2["danger"] = false
			t2["name"] = ""
			removed += 1
		if removed > 0:
			report["events"].append("部分游荡敌人失去了补给，消散了 %d 个。" % removed)

	# 5. 资源点再生（发展系统生成的资源点可再获取）
	for k in tiles.keys():
		var t: Dictionary = tiles[k]
		if t.get("owner", Consts.Owner.NONE) == Consts.Owner.PLAYER and str(t.get("resource", "")) != "":
			var amt := float(t.get("amount", 0.0))
			if t.has("node_tier"):
				t["amount"] = minf(TileManager.amount_cap(t), amt + 0.5)
			elif amt > 0.0:
				t["amount"] = maxf(0.0, amt - 0.2)


## 攻击结算：文档写的是「(防御力 - 攻击力) 后结算，随机破坏建筑，
## 建筑全毁则失去地块并转为无主地块」
static func _damage_tile(state: Dictionary, key: String, rng: RandomNumberGenerator, report: Dictionary) -> void:
	var tiles: Dictionary = state["tiles"]
	if not tiles.has(key):
		return
	var t: Dictionary = tiles[key]
	if t.get("owner", Consts.Owner.NONE) != Consts.Owner.PLAYER:
		return
	var defense := 10.0 + float(t.get("buildings", []).size()) * 5.0 + float(state["pop_total"]) * 0.5
	var attack := 12.0
	for k in tiles.keys():
		var et: Dictionary = tiles[k]
		if et.get("owner", Consts.Owner.NONE) == Consts.Owner.ENEMY and Hex.distance(TileManager.coord_of(k), TileManager.coord_of(key)) <= 1:
			attack += float(et.get("force", 0.0)) * 0.5
	var diff := attack - defense
	if diff <= 0.0:
		return
	var bs: Array = t.get("buildings", [])
	if bs.is_empty():
		# 没有建筑：直接失去地块
		t["owner"] = Consts.Owner.NONE
		t["force"] = 0.0
		t["name"] = ""
		report["events"].append("%s 没有防御建筑，被攻陷转为无主地块。" % key)
		return
	var idx := rng.randi() % bs.size()
	var lost: Dictionary = bs[idx]
	var def := BuildingDB.find(str(lost.get("id", "")))
	var lname := def.display_name if def != null else str(lost.get("id", ""))
	if int(lost.get("level", 1)) > 1:
		lost["level"] = int(lost["level"]) - 1
		lost["workers"] = mini(int(lost.get("workers", 0)), int(lost["level"]) * 2)
		report["events"].append("%s 的 %s 被破坏，等级降至 %d。" % [key, lname, int(lost["level"])])
	else:
		bs.remove_at(idx)
		report["events"].append("%s 的 %s 被彻底摧毁。" % [key, lname])
	# 该建筑若在规划队列里有项目（升级等），一并作废
	GameState.drop_queue_items_for_bid(str(lost.get("bid", "")))
	if bs.is_empty():
		t["owner"] = Consts.Owner.NONE
		t["force"] = 0.0
		t["name"] = ""
		report["events"].append("%s 的建筑全部损毁，地块转为无主。" % key)
