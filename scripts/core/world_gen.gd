class_name WorldGen
extends RefCounted
## 大世界（六边形地图）生成与演化。
##
## 文档要点：
##  - 初始地图 15*15（半径 7 的六边形），提升营地等级后上限扩大。
##  - 初始只有基础资源点（树林、煤矿、铜矿…）；铁矿 / 原油需要「发展系统」
##    才会在大世界生成资源点（「打捞系统」也能拿到，但不会生成可再生资源点）。
##  - 迷雾：点亮后只知道地形，必须派角色/人力占据才能真正获取。
##  - 高危据点会不断生成游荡敌人；终极威胁先游荡若干周期再直扑首都。

const OWNER_NONE := ""
const OWNER_PLAYER := "player"
const OWNER_ENEMY := "enemy"


static func key_of(c: Vector2i) -> String:
	return "%d,%d" % [c.x, c.y]


# ===========================================================================
# v1.8.21（更真实的地图生成·第 1 段）：高程噪声
#   地形不再是"每格一个哈希定死"，而是由一张**高程噪声场**决定 —— 于是海/陆/丘陵会成片出现。
#   用的是引擎内置的 FastNoiseLite（MIT），它按坐标采样 → 天生是 f(坐标, 种子) 的纯函数，
#   所以"扩张出来的格子与一开始生成时一致"（1.8.20.9 那条约束）自动成立。
# ===========================================================================
static var _elev_noise: FastNoiseLite = null
static var _elev_noise_seed := -1


static func _elevation_noise(world_seed: int) -> FastNoiseLite:
	if _elev_noise != null and _elev_noise_seed == world_seed:
		return _elev_noise
	var n := FastNoiseLite.new()
	n.seed = world_seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.14          # 单位是"格"：0.14 ≈ 每 7 格一个起伏
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 4
	n.fractal_gain = 0.5
	_elev_noise = n
	_elev_noise_seed = world_seed
	return n


## 某一格的高度（0~1）：多倍频采样后做**重塑**——把中间高度往下压一点，让平原多些。
## 指数就是"水多不多"的旋钮：调大 → 整体变低 → 水变多（2.6 那次半张图都是海，别调过头）。
static func elevation_of(c: Vector2i, world_seed: int) -> float:
	var n := _elevation_noise(world_seed)
	var e := (n.get_noise_2d(float(c.x), float(c.y)) + 1.0) * 0.5
	return pow(e, 1.25)



## 将字符串坐标转换为vector2i坐标
static func coord_of(key: String) -> Vector2i:
	var parts := key.split(",")
	if parts.size() != 2:
		return Vector2i.ZERO
	return Vector2i(int(parts[0]), int(parts[1]))


# ===========================================================================
# 生成
# ===========================================================================
static func generate(state: Dictionary) -> void:
	# v1.8.20.9：不再自己造 rng —— 每一格的地形/资源由 _make_tile(c, 世界种子) 直接算出来
	var world_seed := int(state["seed"])
	var tiles := {}
	for c in Hex.spiral(Consts.MAP_START_RADIUS):
		tiles[key_of(c)] = _make_tile(c, world_seed)

	state["tiles"] = tiles
	# 首都占据中心
	var cap := coord_of(str(state["capital"]))
	var cap_tile: Dictionary = tiles[key_of(cap)]
	cap_tile["owner"] = OWNER_PLAYER
	cap_tile["discovered"] = true
	cap_tile["terrain"] = "plain"
	cap_tile["is_capital"] = true
	cap_tile["name"] = "首都·初始营地"
	cap_tile["claimable"] = false
	cap_tile["buildings"] = []
	# 初始点亮范围
	discover_radius(state, cap, Consts.CAMP_START_RADIUS)
	# 保证首都不缺基础资源
	_ensure_basic_nearby(state, cap)


## 造一格（地形 + 基础资源）。
## v1.8.20.9：地形/资源 = f(坐标, 世界种子) 的纯函数 —— 同种子同地图，
## 且 expand_map() 后加的那一格与"一开始就生成这么大"时必然一致。
## 别改成用 rng 按顺序摇地形：那样同一格会随生成顺序变样，这条一致性就没了。

static func _make_tile(c: Vector2i, world_seed: int) -> Dictionary:

	var t := {
		"c": [c.x, c.y],
		"terrain": "plain",
		"resource": "",
		"owner": OWNER_NONE,
		"discovered": false,
		"is_capital": false,
		"name": "",
		"buildings": [],
		"force": 0.0,
		"threat": false,
		"danger": false,   # 高危据点
		"stronghold": "",  # v1.3.1：所属据点（我方地块才有）
		"land_cap": Consts.LAND_CAP_DEFAULT,   # v1.3.1：可用土地上限
	}
	# v1.8.21 第 1 段：地形由**高程**决定（成片）；本段先用现有这 5 种，
	# 第 2 段引入"地物"层后，forest 会改落到 cover 上。
	var e := elevation_of(c, world_seed)
	if e < 0.36:
		t["terrain"] = "water"
	elif e < 0.50:
		t["terrain"] = "plain"
	elif e < 0.62:
		t["terrain"] = "hill"
	elif e < 0.72:
		t["terrain"] = "forest"

	else:
		t["terrain"] = "wasteland"


	# 基础资源点
	var rr := Hex.hash01(c, 31 + world_seed)

	var dist := Hex.distance(c, Vector2i.ZERO)
	if t["terrain"] == "forest" and rr < 0.55:
		t["resource"] = "wood"
		t["amount"] = 4.0 + rr * 8.0
	elif t["terrain"] == "hill" and rr < 0.45:
		t["resource"] = "coal" if rr < 0.22 else "copper"
		t["amount"] = 3.0 + rr * 8.0
	elif dist > 4 and rr < 0.12:
		t["resource"] = "wood"
		t["amount"] = 5.0 + rr * 6.0
	return t


static func _ensure_basic_nearby(state: Dictionary, center: Vector2i) -> void:
	var tiles: Dictionary = state["tiles"]
	var i := 0
	for d in Hex.DIRECTIONS:
		var c := center + d
		var k := key_of(c)
		if not tiles.has(k):
			continue
		var t: Dictionary = tiles[k]
		if i == 0:
			t["terrain"] = "forest"
			t["resource"] = "wood"
			t["amount"] = 6.0
		elif i == 1:
			t["terrain"] = "hill"
			t["resource"] = "coal"
			t["amount"] = 5.0
		elif i == 2:
			t["terrain"] = "hill"
			t["resource"] = "copper"
			t["amount"] = 5.0
		else:
			break
		i += 1


# ===========================================================================
# 迷雾
# ===========================================================================
static func discover_radius(state: Dictionary, center: Vector2i, radius: int) -> int:
	var tiles: Dictionary = state["tiles"]
	var n := 0
	for c in Hex.spiral(radius):
		var k := key_of(center + c)
		if not tiles.has(k):
			continue
		var t: Dictionary = tiles[k]
		if not t.get("discovered", false):
			t["discovered"] = true
			n += 1
	return n


# ===========================================================================
# 扩张
# ===========================================================================
## 扩张基础消耗（未打折的行政点数）
## v1.7：从 state 里数地块（以前 claim_base_cost / enemy_cap / _enemy_tile_count 各写一遍循环）。
## 注意保持"只读传入的 state"这一约定，不去读全局 GameState.state。
static func owned_tile_count(state: Dictionary) -> int:
	var n := 0
	for k in (state["tiles"] as Dictionary).keys():
		if (state["tiles"][k] as Dictionary).get("owner", "") == OWNER_PLAYER:
			n += 1
	return n


static func enemy_tile_count(state: Dictionary) -> int:
	var n := 0
	for k in (state["tiles"] as Dictionary).keys():
		var o: String = (state["tiles"][k] as Dictionary).get("owner", "")
		if o != "" and o != OWNER_PLAYER:
			n += 1
	return n


static func claim_base_cost(state: Dictionary) -> float:
	return Consts.CLAIM_BASE_COST + Consts.CLAIM_COST_PER_TILE * float(owned_tile_count(state))


## 实际消耗：基础消耗 ×（1 − 行政影响力），v1.3.1 扩张改用行政点数
static func claim_cost(state: Dictionary) -> float:
	var base := claim_base_cost(state)
	var influence := minf(Consts.ADMIN_INFLUENCE_MAX,
		float((state.get("res", {}) as Dictionary).get("admin", 0.0)) * Consts.ADMIN_INFLUENCE_PER_POINT)
	return maxf(1.0, base * (1.0 - influence))


## 新占领地块归属：就近并入相邻的我方据点（本作仅首都）
static func _stronghold_for_claim(state: Dictionary, key: String) -> String:
	var tiles: Dictionary = state["tiles"]
	for n in Hex.neighbors(coord_of(key)):
		var nk := key_of(n)
		if tiles.has(nk) and (tiles[nk] as Dictionary).get("owner", "") == OWNER_PLAYER:
			var sid := str((tiles[nk] as Dictionary).get("stronghold", ""))
			if sid != "":
				return sid
	return GameState.CAPITAL_STRONGHOLD


## 可作为扩张目标的格子：已点亮、无主、且与玩家领地相邻
static func claimable_keys(state: Dictionary) -> Array[String]:
	var tiles: Dictionary = state["tiles"]
	var out: Array[String] = []
	for k in tiles.keys():
		var t: Dictionary = tiles[k]
		if not t.get("discovered", false):
			continue
		if t.get("owner", "") != OWNER_NONE:
			continue
		var c := coord_of(k)
		for n in Hex.neighbors(c):
			var nk := key_of(n)
			if tiles.has(nk) and (tiles[nk] as Dictionary).get("owner", "") == OWNER_PLAYER:
				out.append(k)
				break
	return out


static func claim(state: Dictionary, key: String) -> Dictionary:
	var tiles: Dictionary = state["tiles"]
	if not tiles.has(key):
		return {"ok": false, "why": "地块不存在"}
	var t: Dictionary = tiles[key]
	if t.get("owner", "") == OWNER_PLAYER:
		return {"ok": false, "why": "已经是你的地块"}
	if not t.get("discovered", false):
		return {"ok": false, "why": "该地块仍在迷雾中"}
	if not claimable_keys(state).has(key):
		return {"ok": false, "why": "该地块不与你的领地相邻"}
	var cost := {"admin": claim_cost(state)}
	if not GameState.can_afford(cost):
		return {"ok": false, "why": "行政点数不足（需要 %.0f）" % float(cost["admin"])}
	GameState.pay(cost)
	t["owner"] = OWNER_PLAYER
	t["force"] = 0.0
	t["danger"] = false
	t["threat"] = false
	if not t.has("buildings"):
		t["buildings"] = []
	t["stronghold"] = _stronghold_for_claim(state, key)
	if not t.has("land_cap"):
		t["land_cap"] = Consts.LAND_CAP_DEFAULT
	if str(t.get("name", "")) == "":
		t["name"] = "%s·领地" % Consts.terrain_name(str(t["terrain"]))
	var c := coord_of(key)
	var revealed := discover_radius(state, c, 1)
	GameState.add_log("占领 %s（周围点亮 %d 格）。" % [key, revealed], "world")
	return {"ok": true, "why": "", "revealed": revealed}


# ===========================================================================
# 世界泡引发的世界事件
# ===========================================================================
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
	t["owner"] = OWNER_ENEMY
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
	t["owner"] = OWNER_ENEMY
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
		var cap0 := coord_of(str(state["capital"]))
		for d in Hex.DIRECTIONS:
			var nk := key_of(cap0 + d)
			if (state["tiles"] as Dictionary).has(nk):
				key = nk
				break
		if key == "":
			key = str(state["capital"])
	else:
		# 尽量远离首都生成
		var cap := coord_of(str(state["capital"]))
		var best := -1
		for k in cands:
			var d := Hex.distance(coord_of(k), cap)
			if d > best:
				best = d
				key = k
	var tiles: Dictionary = state["tiles"]
	tiles[key]["owner"] = OWNER_ENEMY
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
	var cap := coord_of(str(state["capital"]))
	for k in tiles.keys():
		var t: Dictionary = tiles[k]
		if t.get("owner", "") != OWNER_NONE:
			continue
		if coord_of(k) == cap:
			continue
		if t.get("terrain", "") == "water":
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
		if t.get("owner", "") != OWNER_NONE:
			continue
		# 不直接刷在首都旁边
		if Hex.distance(coord_of(k), coord_of(str(state["capital"]))) < 2:
			continue
		if t.get("terrain", "") == "water":
			continue
		out.append(k)
	return out


static func _enemy_tile_count(state: Dictionary) -> int:
	return enemy_tile_count(state)


## 世界上同时允许存在的敌方地块数量上限
static func enemy_cap(state: Dictionary) -> int:
	var owned := owned_tile_count(state)
	return Consts.ENEMY_CAP_BASE + int(float(owned) * Consts.ENEMY_CAP_PER_OWNED) \
		+ int(float(state.get("cycle", 1)) * Consts.ENEMY_CAP_PER_CYCLE)


## 清剿：计算打下一块敌方地块需要的战力
static func clear_requirement(t: Dictionary) -> float:
	return maxf(20.0, float(t.get("force", Consts.WANDER_FORCE)) * Consts.CLEAR_FORCE_PER_ENEMY)


## 玩家是否可以清剿该地块
static func can_clear(state: Dictionary, key: String) -> Dictionary:
	var tiles: Dictionary = state["tiles"]
	if not tiles.has(key):
		return {"ok": false, "why": "地块不存在"}
	var t: Dictionary = tiles[key]
	var o: String = t.get("owner", "")
	if o == "" or o == OWNER_PLAYER:
		return {"ok": false, "why": "该地块不是敌方地块"}
	if not _adjacent_to_player(state, key):
		return {"ok": false, "why": "该地块不与你的领地相邻"}
	var need := clear_requirement(t)
	if GameState.player_force() < need:
		return {"ok": false, "why": "战力不足：需要 %.0f，当前 %.0f" % [need, GameState.player_force()]}
	return {"ok": true, "why": ""}


static func _adjacent_to_player(state: Dictionary, key: String) -> bool:
	var tiles: Dictionary = state["tiles"]
	for n in Hex.neighbors(coord_of(key)):
		var nk := key_of(n)
		if tiles.has(nk) and (tiles[nk] as Dictionary).get("owner", "") == OWNER_PLAYER:
			return true
	return false


## 执行清剿：敌方地块转为无主地块
static func clear_tile(state: Dictionary, key: String, rng: RandomNumberGenerator) -> Dictionary:
	var chk := can_clear(state, key)
	if not chk["ok"]:
		return chk
	var t: Dictionary = state["tiles"][key]
	var was_threat: bool = t.get("threat", false)
	var was_danger: bool = t.get("danger", false)
	GameState.on_enemy_killed(t)   # 依据击杀时的敌人类型给行政产出 buff
	# 清剿消耗：损失一些人力
	var loss := 0
	if rng.randf() < 0.35 and int(state["pop_total"]) > 1:
		loss = 1
		state["pop_total"] = int(state["pop_total"]) - 1
	GameState.clear_enemy_tile(key)
	var kind := "终极威胁" if was_threat else ("高危据点" if was_danger else "游荡敌人")
	GameState.add_log("清剿 %s 的%s成功。" % [key, kind], "combat")
	return {"ok": true, "why": "", "kind": kind, "loss": loss}


## 发展系统生成资源地脉：在大世界生成高级资源点
static func spawn_resource_node(state: Dictionary, rng: RandomNumberGenerator, tier: int = 1) -> Dictionary:
	var cands := _enemy_spawn_candidates(state)
	if cands.is_empty():
		return {"ok": false}
	var key: String = cands[rng.randi() % cands.size()]
	var t: Dictionary = state["tiles"][key]
	var pool: Array[String] = Consts.ADVANCED_RESOURCES.duplicate()
	if tier >= 2:
		pool.append("crystal_shard")
	var pick: String = pool[rng.randi() % pool.size()]
	t["resource"] = pick
	t["amount"] = 6.0 + float(tier) * 6.0
	t["node_tier"] = tier
	t["discovered"] = true
	t["name"] = "%s资源点" % Consts.res_name(pick)
	return {"ok": true, "key": key, "resource": pick}


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
		if t.get("danger", false) and t.get("owner", "") == OWNER_ENEMY:
			danger_count += 1
			if rng.randf() < 0.35:
				var cands := _enemy_spawn_candidates(state)
				if not cands.is_empty():
					var nk: String = cands[rng.randi() % cands.size()]
					var nt: Dictionary = tiles[nk]
					nt["owner"] = OWNER_ENEMY
					nt["force"] = Consts.WANDER_FORCE
					nt["name"] = "游荡敌人"
					nt["wander"] = true
					nt["spawned_cycle"] = cycle

	# 2. 游荡敌人随机移动
	var wander_keys: Array[String] = []
	for k in tiles.keys():
		if (tiles[k] as Dictionary).get("wander", false) and (tiles[k] as Dictionary).get("owner", "") == OWNER_ENEMY:
			wander_keys.append(k)
	for k in wander_keys:
		var t: Dictionary = tiles[k]
		if not tiles.has(k) or t.get("owner", "") != OWNER_ENEMY:
			continue
		var ns := Hex.neighbors(coord_of(k))
		var pool: Array[String] = []
		for n in ns:
			var nk := key_of(n)
			if tiles.has(nk) and (tiles[nk] as Dictionary).get("owner", "") == OWNER_NONE:
				pool.append(nk)
		if pool.is_empty():
			continue
		var dest: String = pool[rng.randi() % pool.size()]
		var dt: Dictionary = tiles[dest]
		if dt.get("owner", "") == OWNER_NONE:
			dt["owner"] = OWNER_ENEMY
			dt["force"] = float(t.get("force", Consts.WANDER_FORCE))
			dt["name"] = str(t.get("name", "游荡敌人"))
			dt["wander"] = true
			dt["spawned_cycle"] = int(t.get("spawned_cycle", cycle))
			t["owner"] = OWNER_NONE
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
			var cap := coord_of(str(state["capital"]))
			var cur := coord_of(key)
			var best := key
			var bestd := Hex.distance(cur, cap)
			for n in Hex.neighbors(cur):
				var nk := key_of(n)
				if not tiles.has(nk):
					continue
				var d := Hex.distance(n, cap)
				if d < bestd:
					bestd = d
					best = nk
			if best != key:
				var bt: Dictionary = tiles[best]
				if bt.get("owner", "") == OWNER_PLAYER:
					# 直接攻击玩家地块
					report["events"].append("终极威胁抵达 %s，建筑被破坏！" % best)
					_damage_tile(state, best, rng, report)
					th["timer"] = 0
					continue
				t["owner"] = OWNER_NONE
				t["threat"] = false
				t["force"] = 0.0
				t["name"] = ""
				bt["owner"] = OWNER_ENEMY
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
		if (tiles[k] as Dictionary).get("owner", "") == OWNER_ENEMY:
			enemy_keys.append(k)
	for k in enemy_keys:
		var t: Dictionary = tiles[k]
		for n in Hex.neighbors(coord_of(k)):
			var nk := key_of(n)
			if not tiles.has(nk):
				continue
			var nt: Dictionary = tiles[nk]
			if nt.get("owner", "") != OWNER_PLAYER:
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
			if t.get("owner", "") == OWNER_ENEMY and not t.get("threat", false):
				wander.append(k)
		wander.sort_custom(func(a: String, b: String) -> bool:
			return int((tiles[a] as Dictionary).get("spawned_cycle", 0)) \
				< int((tiles[b] as Dictionary).get("spawned_cycle", 0)))
		var removed := 0
		for k in wander:
			if removed >= excess:
				break
			var t2: Dictionary = tiles[k]
			t2["owner"] = OWNER_NONE
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
		if t.get("owner", "") == OWNER_PLAYER and str(t.get("resource", "")) != "":
			var amt := float(t.get("amount", 0.0))
			if t.has("node_tier"):
				t["amount"] = minf(amount_cap(t), amt + 0.5)
			elif amt > 0.0:
				t["amount"] = maxf(0.0, amt - 0.2)


static func amount_cap(t: Dictionary) -> float:
	return 6.0 + float(t.get("node_tier", 1)) * 8.0


## 攻击结算：文档写的是「(防御力 - 攻击力) 后结算，随机破坏建筑，
## 建筑全毁则失去地块并转为无主地块」
static func _damage_tile(state: Dictionary, key: String, rng: RandomNumberGenerator, report: Dictionary) -> void:
	var tiles: Dictionary = state["tiles"]
	if not tiles.has(key):
		return
	var t: Dictionary = tiles[key]
	if t.get("owner", "") != OWNER_PLAYER:
		return
	var defense := 10.0 + float(t.get("buildings", []).size()) * 5.0 + float(state["pop_total"]) * 0.5
	var attack := 12.0
	for k in tiles.keys():
		var et: Dictionary = tiles[k]
		if et.get("owner", "") == OWNER_ENEMY and Hex.distance(coord_of(k), coord_of(key)) <= 1:
			attack += float(et.get("force", 0.0)) * 0.5
	var diff := attack - defense
	if diff <= 0.0:
		return
	var bs: Array = t.get("buildings", [])
	if bs.is_empty():
		# 没有建筑：直接失去地块
		t["owner"] = OWNER_NONE
		t["force"] = 0.0
		t["name"] = ""
		report["events"].append("%s 没有防御建筑，被攻陷转为无主地块。" % key)
		return
	var idx := rng.randi() % bs.size()
	var lost: Dictionary = bs[idx]
	var def := GameState.find_building(str(lost.get("id", "")))
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
		t["owner"] = OWNER_NONE
		t["force"] = 0.0
		t["name"] = ""
		report["events"].append("%s 的建筑全部损毁，地块转为无主。" % key)


# ===========================================================================
# 扩展地图上限（发展系统 / 营地升级）
# ===========================================================================
## v1.8.20.9：不收 rng —— 地形由坐标 + 世界种子决定，扩张出来的格子与"一开始就生成这么大"时一致。

static func expand_map(state: Dictionary, rings: int = 1) -> int:

	var tiles: Dictionary = state["tiles"]
	var current_radius := 0
	for k in tiles.keys():
		current_radius = maxi(current_radius, Hex.distance(coord_of(k), Vector2i.ZERO))
	var target := mini(current_radius + rings, Consts.MAP_MAX_RADIUS)
	if target <= current_radius:
		return 0
	var added := 0
	for c in Hex.spiral(target):
		var k := key_of(c)
		if tiles.has(k):
			continue
		tiles[k] = _make_tile(c, int(state["seed"]))

		added += 1
	return added


static func map_radius(state: Dictionary) -> int:
	var r := 0
	for k in state["tiles"].keys():
		r = maxi(r, Hex.distance(coord_of(k), Vector2i.ZERO))
	return r
