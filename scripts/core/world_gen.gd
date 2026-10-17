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


## 某一格的高度（0~1）：多倍频采样 → **大陆形状**（往 1-距离 混）→ 重塑（往下压，让平原多些）。
## 重塑指数是"水多不多"的旋钮（2.6 那次半张图都是海，别调过头）。
static func elevation_of(c: Vector2i, world_seed: int) -> float:
	var n := _elevation_noise(world_seed)
	var e := (n.get_noise_2d(float(c.x), float(c.y)) + 1.0) * 0.5
	e = lerp(e, 1.0 - mainland_pull(c), 0.55)
	return pow(e, 1.25)


# ===========================================================================
# v1.8.21 第 4 段：侵蚀（按拍板 = **固定最大范围**的后处理，不看"当前半径"）
#   为什么必须用最大范围：否则地图一扩张，这个后处理看到的格子变多 → 老格子的结果就变了
#   （那会直接违反 1.8.20.9 那条"扩张出来的格子与一开始生成时一致"）。
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
		var k := TileManager.key_of(c)
		raw[k] = elevation_of(c, world_seed)
		cells.append(c)
	# 填洼（水文建模的标准一步，之前漏了）：
	# 噪声面上有无数小坑，水一流进去就断了 → 汇流量永远攒不起来，河就成不了链
	#（第一版没这步，全图只有 5 个孤立河格）。做法是迭代松弛：每格抬到不低于"最矮的邻格"，
	# 即"水必须漫过最低的坑沿才能流出去、于是坑被填成平湖"。迭代次数固定 + 遍历顺序固定 → 结果确定。
	for _pass in 8:
		for c1: Vector2i in cells:
			var k1 := TileManager.key_of(c1)
			var lowest_nb := 9.9
			for nb1: Vector2i in Hex.neighbors(c1):
				var nk1 := TileManager.key_of(nb1)
				if raw.has(nk1):
					lowest_nb = minf(lowest_nb, float(raw[nk1]))
			if lowest_nb < 9.9:
				raw[k1] = maxf(float(raw[k1]), lowest_nb)
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:

		var ha: float = raw[TileManager.key_of(a)]
		var hb: float = raw[TileManager.key_of(b)]
		if not is_equal_approx(ha, hb):
			return ha > hb              # 高的先流
		return TileManager.key_of(a) < TileManager.key_of(b))   # 并列用键兜底 → 结果确定
	var flow := {}
	for c2: Vector2i in cells:
		var k2 := TileManager.key_of(c2)
		flow[k2] = int(flow.get(k2, 0)) + 1
		var lowest := ""
		var lowest_h := float(raw[k2])
		var lowest_key := ""
		for nb: Vector2i in Hex.neighbors(c2):
			var nk := TileManager.key_of(nb)
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
	var k := TileManager.key_of(c)
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
			var nk := TileManager.key_of(c + nb)
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
		tiles[TileManager.key_of(c)] = _make_tile(c, world_seed)

	state["tiles"] = tiles
	# v1.8.21：出生点不再固定在世界中心，改成挑一处**资源相对丰富、又不贴边境**的地块
	#（原来这里固定中心 + 下面还有一段"保证附近有基础资源"的强制补丁，那段已删）
	state["capital"] = choose_capital(tiles)

## 造一格（地形 + 基础资源）。
## v1.8.20.9：地形/资源 = f(坐标, 世界种子) 的纯函数 —— 同种子同地图，
## 且 expand_map() 后加的那一格与"一开始就生成这么大"时必然一致。
## 别改成用 rng 按顺序摇地形：那样同一格会随生成顺序变样，这条一致性就没了。

static func _make_tile(c: Vector2i, world_seed: int) -> Dictionary:
	var t := {
		"c": [c.x, c.y],
		"terrain": "plain",
		"cover": "",
		"resource": "",

		"owner": Consts.Owner.NONE,
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
	if _river_keys.has(TileManager.key_of(c)):
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
		var k := TileManager.key_of(c)
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
