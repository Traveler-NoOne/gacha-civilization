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


## v1.8.21 第 3 段：大陆形状。离世界中心越远 → 越往水拉，于是"中间大陆、四周海洋"。
## ⚠️ 尺度必须用**固定常量**（起始半径 × 1.3），不能用"当前半径"——
## 否则地图一扩张，老格子的地形就会变（1.8.20.9 那条纯函数约束）。
## 1.3 这个系数决定"海岸线落在哪"：太小 → 初始图大半是海；太大 → 看不出海岸。
static func mainland_pull(c: Vector2i) -> float:
	var d := float(Hex.distance(c, Vector2i.ZERO)) / (float(Consts.MAP_START_RADIUS) * 1.3)
	return clampf(d, 0.0, 1.0)


## 某一格的高度（0~1）：多倍频采样 → **大陆形状**（往 1-距离 混）→ 重塑（往下压，让平原多些）
## → **W2（S2）：叠上板块过程**（相向边界造山/造沟、相离边界造脊/造谷）。
## 重塑指数是"水多不多"的旋钮（2.6 那次半张图都是海，别调过头）。
## ⚠️ 板块那一层由 `Plates.effect_at()` 提供，它**只按这一格的坐标 + 种子算**（逐格纯函数）——
## 所以 W1 定的"整图可复现"依然成立（见 docs/更新指导/世界生成-过程模拟.md 3.4）。
static func elevation_of(c: Vector2i, world_seed: int) -> float:
	var n := _elevation_noise(world_seed)
	var e := (n.get_noise_2d(float(c.x), float(c.y)) + 1.0) * 0.5
	e = lerp(e, 1.0 - mainland_pull(c), 0.55)
	e = pow(e, 1.25)
	return clampf(e + Plates.effect_at(c, e, world_seed), 0.0, 1.0)


# ===========================================================================
# v1.8.21 第 4 段：侵蚀（**固定最大范围**的后处理，不看"当前半径"）
#   为什么必须用最大范围：否则地图一扩张，这个后处理看到的格子变多 → 老格子的结果就变了
#   （那会违反 1.8.20.9 那条"扩张出来的格子与一开始生成时一致"）。
#   ⚠️ W1：扩张与 `expand_map()` 已经删除，这条约束**从原理上不再需要**。
#   但**本段暂时保持原样** —— 现在改它（例如改成按当前半径跑）会让**当前地图立刻变样**，
#   而 W1 的验收要求是"观感零变化"。**等 W2 换掉高程管线时再真正拆掉这个写法**
#   （见 docs/更新指导/世界生成-W2.md）。
#   算法（mewo2/terrain 那套的简化版，全程确定、不含随机）：
#     1) 算出最大范围内每格的原始高度；
#     2) 按高度从高到低排序（并列用坐标键兜底 → 确定）；
#     3) 每格往"最矮的邻格"流，沿途累加流量；
#     4) 流量大的地方把高度削下去 → 水路上出现河谷。
#   注意：河不单独算一种地形 —— 被削低之后它自然"更容易成为水/平原"，
#   这与既有模型（地形只由高度+湿度查表）一致，也和"真实过程决定结果"这条原则一致。
# ===========================================================================
## 侵蚀系数：按真实感设的物理量，**不为平衡调**（用户定的原则）。
const EROSION_RATE := 0.02


static var _eroded: Dictionary = {}
static var _eroded_seed := -1
static var _river_keys: Dictionary = {}



static func _eroded_heights(world_seed: int) -> Dictionary:
	if _eroded_seed == world_seed and not _eroded.is_empty():
		return _eroded
	var raw := {}
	var cells: Array = []
	for c in Hex.spiral(Consts.MAP_MAX_RADIUS):
		var k := key_of(c)
		raw[k] = elevation_of(c, world_seed)
		cells.append(c)
	# 填洼（水文建模的标准一步，之前漏了）：
	# 噪声面上有无数小坑，水一流进去就断了 → 汇流量永远攒不起来，河就成不了链
	#（第一版没这步，全图只有 5 个孤立河格）。做法是迭代松弛：每格抬到不低于"最矮的邻格"，
	# 即"水必须漫过最低的坑沿才能流出去、于是坑被填成平湖"。迭代次数固定 + 遍历顺序固定 → 结果确定。
	for _pass in 8:
		for c1: Vector2i in cells:
			var k1 := key_of(c1)
			var lowest_nb := 9.9
			for nb1: Vector2i in Hex.neighbors(c1):
				var nk1 := key_of(nb1)
				if raw.has(nk1):
					lowest_nb = minf(lowest_nb, float(raw[nk1]))
			if lowest_nb < 9.9:
				raw[k1] = maxf(float(raw[k1]), lowest_nb)
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:

		var ha: float = raw[key_of(a)]
		var hb: float = raw[key_of(b)]
		if not is_equal_approx(ha, hb):
			return ha > hb              # 高的先流
		return key_of(a) < key_of(b))   # 并列用键兜底 → 结果确定
	var flow := {}
	for c2: Vector2i in cells:
		var k2 := key_of(c2)
		flow[k2] = int(flow.get(k2, 0)) + 1
		var lowest := ""
		var lowest_h := float(raw[k2])
		var lowest_key := ""
		for nb: Vector2i in Hex.neighbors(c2):
			var nk := key_of(nb)
			if not raw.has(nk):
				continue
			var h_nb := float(raw[nk])
			# 取"高度最小、同高则比坐标键"的邻格。填洼保证了每格都至少有一个**不高于**自己的邻格，
			# 所以平地上也能按坐标键定出一个确定的流向；而 (高度, 键) 每步严格递减 → 绝不会打转。
			# （第一版只认"严格更低"，水一进平湖就停了 → 河里全是断口。）
			if h_nb < lowest_h or (is_equal_approx(h_nb, lowest_h) and (lowest_key == "" or nk < lowest_key)):
				lowest_h = h_nb
				lowest_key = nk
				lowest = nk

		if lowest != "":
			flow[lowest] = int(flow.get(lowest, 0)) + int(flow[k2])
	var out := {}
	var base := log(2.0)   # 流量=1（没人往这儿汇水）对应的"基线"：这一档不该被削
	for k3 in raw.keys():
		# 只削"比别人多汇了水"的地方 —— 否则每一格都会被均匀压低，等于偷偷抬高海平面（不真实）
		var drain := log(1.0 + float(flow.get(k3, 1))) - base
		out[k3] = clampf(float(raw[k3]) - EROSION_RATE * maxf(drain, 0.0), 0.0, 1.0)

	_eroded = out
	_eroded_seed = world_seed
	# 顺手把"河流格"挑出来 —— 每次重建，换种子自然就换掉了。
	# 判据用**汇流量的前 2%**（= "流域面积最大的那批"），而不是一个固定数字：
	# 这样"河"的定义随地图规模自动成立，不用为每张图调参（第一版用固定阈值 35，
	# 结果全图只有 3 个河格 —— 这片地形的汇流本来就细）。
	var flows: Array = []
	for k4 in flow.keys():
		flows.append(int(flow[k4]))
	flows.sort()
	var river_want := maxi(1, int(float(flows.size()) * 0.02))
	var river_cut := int(flows[flows.size() - river_want])
	_river_keys = {}
	for k5 in flow.keys():
		if int(flow[k5]) >= river_cut:
			_river_keys[k5] = true

	return out



## 带侵蚀的高度。表里没有的坐标（超出最大范围）退回原始高度。
static func eroded_elevation_of(c: Vector2i, world_seed: int) -> float:
	var table := _eroded_heights(world_seed)
	var k := key_of(c)
	if table.has(k):
		return float(table[k])
	return elevation_of(c, world_seed)




## 某一格的"湿度"（0~1）。必须用**另一张噪声**（换种子 + 换频率）——
## 否则它和高程一模一样，查表就退化成"只看高程"，看不到干湿分区。
static var _moist_noise: FastNoiseLite = null
static var _moist_noise_seed := -1


static func moisture_of(c: Vector2i, world_seed: int) -> float:
	if _moist_noise == null or _moist_noise_seed != world_seed:
		var n2 := FastNoiseLite.new()
		n2.seed = world_seed + 1013
		n2.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n2.frequency = 0.09          # 比高程更"大块"，气候带才连片
		n2.fractal_type = FastNoiseLite.FRACTAL_FBM
		n2.fractal_octaves = 3
		n2.fractal_gain = 0.5
		_moist_noise = n2
		_moist_noise_seed = world_seed
	return (_moist_noise.get_noise_2d(float(c.x), float(c.y)) + 1.0) * 0.5


## 高程 + 湿度 → 一层地形 + 一层地物（Red Blob 那篇的二维查表，阈值按本作的种类改过）。
## 仍是 f(坐标, 种子) 的纯函数。
static func biome_of(e: float, m: float) -> Dictionary:
	if e < 0.36:
		return {"terrain": "water", "cover": ""}
	if e < 0.50:
		if m > 0.70:
			return {"terrain": "plain", "cover": "swamp"}
		if m > 0.45:
			return {"terrain": "plain", "cover": "grass"}
		if m > 0.22:
			return {"terrain": "plain", "cover": "forest"}
		return {"terrain": "dune", "cover": ""}
	if e < 0.62:
		if m > 0.45:
			return {"terrain": "hill", "cover": "forest"}
		if m > 0.22:
			return {"terrain": "hill", "cover": "grass"}
		return {"terrain": "hill", "cover": ""}
	if e < 0.72:
		if m > 0.60:
			return {"terrain": "hill", "cover": "forest"}
		if m > 0.30:
			return {"terrain": "hill", "cover": "grass"}
		return {"terrain": "wasteland", "cover": ""}
	return {"terrain": "mountain", "cover": ""}


## v1.8.21：挑出生点（首都）。全部由地形/资源决定、**不含随机** → 同一局永远选到同一格。
##   候选：非水、且离世界中心不超过「起始半径 × 0.78」（= 不贴边境）
##   得分：周围 3 格内"有资源的地块数"（越丰富越好）
##   取最高分；并列取离中心更近的；再并列取先遇到的（字典是插入序 → 确定）
static func choose_capital(tiles: Dictionary) -> String:
	var limit := int(float(Consts.MAP_START_RADIUS) * 0.78)
	var best_key := ""
	var best_score := -1
	var best_dist := 9999
	for k in tiles.keys():
		var t: Dictionary = tiles[k]
		if str(t.get("terrain", "")) == "water":
			continue
		var c := coord_of(str(k))
		var d := Hex.distance(c, Vector2i.ZERO)
		if d > limit:
			continue
		var score := 0
		for nb: Vector2i in Hex.spiral(3):
			var nk := key_of(c + nb)
			if not tiles.has(nk):
				continue
			var nt: Dictionary = tiles[nk]
			if str(nt.get("terrain", "")) == "water":
				continue
			if str(nt.get("resource", "")) != "":
				score += 1
		if score > best_score or (score == best_score and d < best_dist):
			best_score = score
			best_dist = d
			best_key = str(k)
	return best_key




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
	# v1.8.21：出生点不再固定在世界中心，改成挑一处**资源相对丰富、又不贴边境**的地块
	#（原来这里固定中心 + 下面还有一段"保证附近有基础资源"的强制补丁，那段已删）
	state["capital"] = choose_capital(tiles)

	var cap := coord_of(str(state["capital"]))
	var cap_tile: Dictionary = tiles[key_of(cap)]
	cap_tile["owner"] = OWNER_PLAYER
	cap_tile["discovered"] = true
	cap_tile["is_capital"] = true
	cap_tile["name"] = "首都·初始营地"
	cap_tile["claimable"] = false
	cap_tile["buildings"] = []
	# 初始点亮范围
	discover_radius(state, cap, Consts.CAMP_START_RADIUS)



## 造一格（地形 + 基础资源）。
## 地形/资源 = f(坐标, 世界种子)：同种子同地图，且**与生成顺序无关**（并列一律按坐标兜底）。
## ⚠️ W1 起约束变了：不再要求"逐格独立、扩张不能改变老格"（**扩张已废弃**）；
## 但**"整图可复现"必须保住** —— 同一配方（种子 + 尺寸 + 裁切窗口）每次生成必须**逐位一致**，
## 否则读档重算就等于换了一张图（见 docs/更新指导/世界生成-过程模拟.md 第 3.4 节）。
## 别改成用 rng 按顺序摇地形：那样同一格会随生成顺序变样。

static func _make_tile(c: Vector2i, world_seed: int) -> Dictionary:

	var t := {
		"c": [c.x, c.y],
		"terrain": "plain",
		"cover": "",
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
	# v1.8.21 第 2 段：地形（地貌）与地物（覆盖物）分两层，由高程 + 湿度查表得出
	var b := biome_of(eroded_elevation_of(c, world_seed), moisture_of(c, world_seed))

	t["terrain"] = b["terrain"]
	t["cover"] = b["cover"]
	# v1.8.21：河流格（上面那次侵蚀已经顺便挑好了，这里只是取用）
	if _river_keys.has(key_of(c)):
		t["river"] = true




	# 基础资源点
	var rr := Hex.hash01(c, 31 + world_seed)
	if t["cover"] == "forest" and rr < 0.55:
		t["resource"] = "wood"
		t["amount"] = 4.0 + rr * 8.0
	elif t["terrain"] == "hill" and rr < 0.45:
		t["resource"] = "coal" if rr < 0.22 else "copper"
		t["amount"] = 3.0 + rr * 8.0
	return t






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
# 地图半径
# ===========================================================================
## W1：`expand_map()` 已删除 ——「扩张」这个玩法要废弃，将来改由**发展卡池给一整个世界**
## （见 docs/更新指导/世界生成-W7.md）。这里只留下"量一下当前地图半径"这个小工具。


static func map_radius(state: Dictionary) -> int:
	var r := 0
	for k in state["tiles"].keys():
		r = maxi(r, Hex.distance(coord_of(k), Vector2i.ZERO))
	return r
