class_name TileManager
extends RefCounted
## 地块管理 ✓
##
## 判据：**改**格子（归属 / 迷雾 / 资源 / 清剿 / 计数）→ 放这里 ✓
##       地块**键 ↔ 坐标**的互转也在这里（`key_of` / `coord_of` / `tile_key`）✓
##       **造**格子归生成器（`scripts/worldgen/builder.gd`）✓
##
## ⚠️ 依赖方向：本文件**不依赖生成器** ✓
##    `Threats` 反过来要用本文件的 `enemy_tile_count` / `owned_tile_count` / `amount_cap` ✓（也是单向 ✓）
##    所以**不许**在这里反向调 `Threats.*` ✗ —— 需要"找空格"就用本文件的 `free_candidates()` ✓✓


# ===========================================================================
# 地块键工具
# ===========================================================================
## 将v2i坐标转换为str
static func key_of(c: Vector2i) -> String:
	return "%d,%d" % [c.x, c.y]

## 把 "q,r" 键还原成坐标 ✓（`key_of` 的反函数 ✓）
static func coord_of(key: String) -> Vector2i:
	var parts := key.split(",")
	if parts.size() != 2:
		return Vector2i.ZERO
	return Vector2i(int(parts[0]), int(parts[1]))

## 获取目标地块的 qr 坐标（键）
static func tile_key(t: Dictionary) -> String:
	var c: Array = t.get("c", [])
	if c.size() < 2:
		return ""
	return key_of(Vector2i(int(c[0]), int(c[1])))


## 距离 2 时的中间格（轴向坐标下取两点之差的一半）
static func middle_key(a: Vector2i, b: Vector2i) -> String:
	var diff := b - a
	if diff.x % 2 != 0 or diff.y % 2 != 0:
		return ""
	return key_of(a + Vector2i(diff.x / 2, diff.y / 2))


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


## 揭开所有迷雾
static func discover_all(state: Dictionary) -> int:
	var tiles: Dictionary = state["tiles"]
	var n := 0
	for k in tiles.keys():
		var t: Dictionary = tiles[k]
		if not t.get("discovered", false):
			t["discovered"] = true
			n += 1
	return n


# ===========================================================================
# 取地块 / 计数
# ===========================================================================
## 取一格（没有就返回空字典）✓ 只读 ✓
static func tile_at(state: Dictionary, key: String) -> Dictionary:
	var tiles: Dictionary = state["tiles"]
	if tiles.has(key):
		return tiles[key]
	return {}


## 我方地块（返回 tile 字典的数组 ✓ 老接口沿用 ✓）
static func owned_tiles(state: Dictionary) -> Array:
	var out := []
	var tiles: Dictionary = state["tiles"]
	for k in tiles.keys():
		var t: Dictionary = tiles[k]
		if t.get("owner", Consts.Owner.NONE) == Consts.Owner.PLAYER:
			out.append(t)
	return out


## 已点亮的地块
static func discovered_tiles(state: Dictionary) -> Array:
	var out := []
	var tiles: Dictionary = state["tiles"]
	for k in tiles.keys():
		var t: Dictionary = tiles[k]
		if t.get("discovered", false):
			out.append(t)
	return out


## 已点亮、且无主（可以占领的候选）
static func free_tiles(state: Dictionary) -> Array:
	var out := []
	var tiles: Dictionary = state["tiles"]
	for k in tiles.keys():
		var t: Dictionary = tiles[k]
		if t.get("discovered", false) and t.get("owner", Consts.Owner.NONE) == Consts.Owner.NONE:
			out.append(t)
	return out


## 敌方地块（不属于玩家、也不是无主）
static func enemy_tiles(state: Dictionary) -> Array:
	var out := []
	var tiles: Dictionary = state["tiles"]
	for k in tiles.keys():
		var t: Dictionary = tiles[k]
		var o: int = t.get("owner", Consts.Owner.NONE)
		if o != Consts.Owner.NONE and o != Consts.Owner.PLAYER:
			out.append(t)
	return out


## 扩张基础消耗（未打折的行政点数）
## 注意保持"只读传入的 state"这一约定，不去读全局 GameState.state。
static func owned_tile_count(state: Dictionary) -> int:
	return owned_tiles(state).size()


static func enemy_tile_count(state: Dictionary) -> int:
	return enemy_tiles(state).size()


# ===========================================================================
# 占地（扩张）
# ===========================================================================
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
		if tiles.has(nk) and (tiles[nk] as Dictionary).get("owner", Consts.Owner.NONE) == Consts.Owner.PLAYER:
			var sid := str((tiles[nk] as Dictionary).get("stronghold", ""))
			if sid != "":
				return sid
	return Strongholds.CAPITAL_STRONGHOLD


## 可作为扩张目标的格子：已点亮、无主、且与玩家领地相邻
static func claimable_keys(state: Dictionary) -> Array[String]:
	var tiles: Dictionary = state["tiles"]
	var out: Array[String] = []
	for k in tiles.keys():
		var t: Dictionary = tiles[k]
		if not t.get("discovered", false):
			continue
		if t.get("owner", Consts.Owner.NONE) != Consts.Owner.NONE:
			continue
		var c := coord_of(k)
		for n in Hex.neighbors(c):
			var nk := key_of(n)
			if tiles.has(nk) and (tiles[nk] as Dictionary).get("owner", Consts.Owner.NONE) == Consts.Owner.PLAYER:
				out.append(k)
				break
	return out


static func claim(state: Dictionary, key: String) -> Dictionary:
	var tiles: Dictionary = state["tiles"]
	if not tiles.has(key):
		return {"ok": false, "why": "地块不存在"}
	var t: Dictionary = tiles[key]
	if t.get("owner", Consts.Owner.NONE) == Consts.Owner.PLAYER:
		return {"ok": false, "why": "已经是你的地块"}
	if not t.get("discovered", false):
		return {"ok": false, "why": "该地块仍在迷雾中"}
	if not claimable_keys(state).has(key):
		return {"ok": false, "why": "该地块不与你的领地相邻"}
	var cost := {"admin": claim_cost(state)}
	if not GameState.can_afford(cost):
		return {"ok": false, "why": "行政点数不足（需要 %.0f）" % float(cost["admin"])}
	GameState.pay(cost)
	t["owner"] = Consts.Owner.PLAYER
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
# 清剿
# ===========================================================================
## 清剿：计算打下一块敌方地块需要的战力
static func clear_requirement(t: Dictionary) -> float:
	return maxf(20.0, float(t.get("force", Consts.WANDER_FORCE)) * Consts.CLEAR_FORCE_PER_ENEMY)


## 玩家是否可以清剿该地块
static func can_clear(state: Dictionary, key: String) -> Dictionary:
	var tiles: Dictionary = state["tiles"]
	if not tiles.has(key):
		return {"ok": false, "why": "地块不存在"}
	var t: Dictionary = tiles[key]
	var o: int = t.get("owner", Consts.Owner.NONE)
	if o == Consts.Owner.NONE or o == Consts.Owner.PLAYER:
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
		if tiles.has(nk) and (tiles[nk] as Dictionary).get("owner", Consts.Owner.NONE) == Consts.Owner.PLAYER:
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
	Admin.on_enemy_killed(GameState.state, t)   # 依据击杀时的敌人类型给行政产出 buff
	# 清剿消耗：损失一些人力
	var loss := 0
	if rng.randf() < 0.35 and int(state["pop_total"]) > 1:
		loss = 1
		state["pop_total"] = int(state["pop_total"]) - 1
	GameState.clear_enemy_tile(key)
	var kind := "终极威胁" if was_threat else ("高危据点" if was_danger else "游荡敌人")
	GameState.add_log("清剿 %s 的%s成功。" % [key, kind], "combat")
	return {"ok": true, "why": "", "kind": kind, "loss": loss}


# ===========================================================================
# 找空格（给"刷东西"用 —— Threats 与资源点都走这里 ✓ 避免互相引用 ✗）
# ===========================================================================
## 返回"可以放东西"的格子：无主、非水、且离首都 ≥ `min_capital_dist`
## （`Threats` 的刷怪、发展池的资源点，都用这一个 ✓）
static func free_candidates(state: Dictionary, min_capital_dist: int = 2) -> Array[String]:
	var out: Array[String] = []
	var tiles: Dictionary = state["tiles"]
	var cap := coord_of(str(state.get("capital", "")))
	for k in tiles.keys():
		var t: Dictionary = tiles[k]
		if t.get("owner", Consts.Owner.NONE) != Consts.Owner.NONE:
			continue
		if TileLib.is_water(t):
			continue
		if min_capital_dist > 0 and Hex.distance(coord_of(k), cap) < min_capital_dist:
			continue
		out.append(k)
	return out


# ===========================================================================
# 资源点
# ===========================================================================
## 发展系统生成资源地脉：在大世界生成高级资源点
## （原来借用 Threats 的"刷怪候选"，现在改用本文件的 `free_candidates(…, 2)` ✓ 不再跨模块 ✗）
static func spawn_resource_node(state: Dictionary, rng: RandomNumberGenerator, tier: int = 1) -> Dictionary:
	var cands := free_candidates(state, 2)
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


## 资源点每周期能回填到的量上限
static func amount_cap(t: Dictionary) -> float:
	return 6.0 + float(t.get("node_tier", 1)) * 8.0


# ===========================================================================
# 新世界落成后的地块初始化
# ===========================================================================
## 标记首都 + 初始点亮 ✓
## 生成层只管"造出格子" ✗ "把格子改成我方首都 / 点亮"属于改格子 → 归这里 ✓
## 调用时机：`WorldgenBuilder.generate(state)` **之后**（那时 `state["capital"]` 已经挑好了 ✓）
static func setup_new_world(state: Dictionary) -> void:
	var tiles: Dictionary = state["tiles"]
	var cap := coord_of(str(state["capital"]))
	var cap_tile: Dictionary = tiles[key_of(cap)]
	cap_tile["owner"] = Consts.Owner.PLAYER
	cap_tile["discovered"] = true
	cap_tile["is_capital"] = true
	cap_tile["name"] = "首都·初始营地"
	cap_tile["claimable"] = false
	cap_tile["buildings"] = []
	# 2026-10-15 收拢：下面两行原先写在 GameState._setup_capital_stronghold() 里 ✗
	#（"改地块字段"的活儿统一归本文件 ✓）
	cap_tile["stronghold"] = Strongholds.CAPITAL_STRONGHOLD
	if not cap_tile.has("land_cap"):
		cap_tile["land_cap"] = Consts.LAND_CAP_DEFAULT
	# 初始点亮范围
	discover_radius(state, cap, Consts.CAMP_START_RADIUS)
