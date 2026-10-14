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


## 基础高度（0~1，**不含板块作用**）：多倍频采样 → 大陆形状 → 重塑（往下压，让平原多些）。
## 单独拆出来，是因为 W2b 要用它算"**每块板的地壳类型**"（取均值）——
## 那一步**不能**把板块作用算进去，否则是自己引用自己。
static func base_elevation_of(c: Vector2i, world_seed: int) -> float:
	var n := _elevation_noise(world_seed)
	var e := (n.get_noise_2d(float(c.x), float(c.y)) + 1.0) * 0.5
	e = lerp(e, 1.0 - mainland_pull(c), 0.55)
	return pow(e, 1.25)


## **每块板的地壳类型**（W2b）：看这块板**实际覆盖到的地块**的基础高程均值 ——
## 均值 ≥ `CRUST_LAND_MEAN` → 陆壳，否则洋壳。全程确定，按种子缓存。
## ⚠️ 为什么不能用"种子离中心远近"猜：陆壳板会因此**覆盖着海**，
##    于是"陆-陆碰撞"发生在海中央 → 抬出一堆海上孤山，**长不出长墙**（第一版实测如此）。
const CRUST_LAND_MEAN := 0.38
## 板块数量（W2b）。**板越少 → 边界越长 → 山带越长**（8 块时最长山带只有 19 格，5 块应当更长）。
const PLATE_COUNT := 5
static var _crust_seed := -1
static var _crust_arr := PackedByteArray()


static func crust_for(world_seed: int, plate_count: int = PLATE_COUNT) -> PackedByteArray:
	if _crust_seed == world_seed and _crust_arr.size() == plate_count:
		return _crust_arr
	var seeds: Array = (Plates.frame(world_seed, plate_count) as Dictionary)["seeds"]
	var sum := PackedFloat32Array()
	var cnt := PackedInt32Array()
	sum.resize(plate_count)
	cnt.resize(plate_count)
	for c in Hex.spiral(Consts.MAP_START_RADIUS):
		var p := Plates.plate_at_point(Hex.axial_to_pixel(c.x, c.y, 1.0), seeds)
		sum[p] += base_elevation_of(c, world_seed)
		cnt[p] += 1
	var out := PackedByteArray()
	out.resize(plate_count)
	for p in plate_count:
		var mean := sum[p] / maxf(1.0, float(cnt[p]))
		out[p] = Plates.CRUST_CONTINENTAL if mean >= CRUST_LAND_MEAN else Plates.CRUST_OCEANIC
	_crust_seed = world_seed
	_crust_arr = out
	return out


## 某一格的高度（0~1）= **基础高度 + 板块作用**。
## ⚠️ 板块那一层由 `Plates.effect_at()` 提供，它**只按这一格的坐标 + 种子算**（逐格纯函数）——
## 所以 W1 定的"整图可复现"依然成立（见 docs/更新指导/世界生成-过程模拟.md 3.4）。
static func elevation_of(c: Vector2i, world_seed: int) -> float:
	var eff := Plates.effect_at(c, world_seed, crust_for(world_seed), PLATE_COUNT)
	return clampf(base_elevation_of(c, world_seed) + eff, 0.0, 1.0)


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
## 水线（= biome_of 里"水"的判据）。W4 的河流要用它区分"陆上"与"入海"。
const SEA_LEVEL := Consts.SEA_LEVEL   ## 水线；定义在 Consts（River 也认它）
## W4：**河头**的取法 —— 取**陆地格**汇流量的前百分之几当河头（再由河头顺流补到入海）。
## ⚠️ 这是"河多河少"的**唯一旋钮**，纯口味、可逆：
##   0.02 → 全图约 22 格河（2~4 条短河，用户 2026-10-13 觉得"太少太短"）；
##   调大 → 河更多更密；调小 → 更少更长。
const RIVER_FLOW_PERCENT := 0.20


static var _eroded: Dictionary = {}
static var _eroded_seed := -1



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
	var flow_to := {}       # W4：本轮的"往哪流"
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
			flow_to[k2] = lowest        # W4：把"往哪流"留下来，河道才能画到**边**上
	var out := {}
	var base := log(2.0)   # 流量=1（没人往这儿汇水）对应的"基线"：这一档不该被削
	for k3 in raw.keys():
		# 只削"比别人多汇了水"的地方 —— 否则每一格都会被均匀压低，等于偷偷抬高海平面（不真实）
		var drain := log(1.0 + float(flow.get(k3, 1))) - base
		out[k3] = clampf(float(raw[k3]) - EROSION_RATE * maxf(drain, 0.0), 0.0, 1.0)

	_eroded = out
	_eroded_seed = world_seed
	# ---- 2026-10-14 **解耦**：河道不再由本模块算，交给**独立的水路图层** `River` ----
	# 本模块只负责"水往哪流"（汇流 + 流向）；"路线怎么走、河道在哪条边上"都归 River。
	# 好处（用户定的架构）：水路**不存进地块数据**，需要时**按坐标查那一层**。
	River.build(world_seed, flow, flow_to, out)
	return out


## W1：把"两端坐标"规范化成一条边的键 `"q,r,d"`（owner = 字典序较小者）。
## 两端必须相邻；不相邻或重复则返回空串。
static func edge_key_of(a: String, b: String) -> String:
	var ca := coord_of(a)
	var cb := coord_of(b)
	if ca == cb:
		return ""
	var d := _dir_to(ca, cb)
	if d < 0:
		return ""
	# 字典序较小者当 owner（比较 (q, r)）；换 owner 就要把方向反过来
	if cb.x < ca.x or (cb.x == ca.x and cb.y < ca.y):
		return _edge_key(cb, (d + 3) % 6)
	return _edge_key(ca, d)


## 从 a 到 b 的六方向序号；不相邻返回 -1
static func _dir_to(a: Vector2i, b: Vector2i) -> int:
	for i in Hex.DIRECTIONS.size():
		if a + Hex.DIRECTIONS[i] == b:
			return i
	return -1


## 以 c 为「字典序较小者」时，边 `"q,r,d"` 的规范化键
static func _edge_key(c: Vector2i, d: int) -> String:
	return "%d,%d,%d" % [c.x, c.y, d]


## 绕六边形从 a 到 b 的**最短步数**（0~3）
static func _ring_delta(a: int, b: int) -> int:
	return mini(((b - a) % 6 + 6) % 6, ((a - b) % 6 + 6) % 6)


## 一条边两个**顶点**（像素空间坐标，size=1）
static func _edge_vertices(ek: String) -> Array:
	var parts := ek.split(",")
	if parts.size() != 3:
		return []
	var c := Vector2i(int(parts[0]), int(parts[1]))
	var d := int(parts[2])
	var k := ((6 - d) % 6 + 6) % 6          # 边 k ↔ DIRECTIONS[(−k) mod 6]（已验证）
	var center := Hex.axial_to_pixel(c.x, c.y, 1.0)
	var cs := Hex.corners(center, 1.0)
	return [cs[k], cs[(k + 1) % 6]]


## 两条边**是否共顶点**（= 用户说的"尾接头"）。同一条边视为共顶点。
## ⚠️ 判据用**距离**而不是"把坐标格式化成字符串再比" —— 后者会因为 `-0.000` 与 `0.000`
##    这类浮点符号差异产生**假违例**（实测误报了 3 处）。
static func edges_adjacent(e1: String, e2: String) -> bool:
	if e1 == e2:
		return true
	var v1 := _edge_vertices(e1)
	var v2 := _edge_vertices(e2)
	if v1.is_empty() or v2.is_empty():
		return false
	var a0: Vector2 = v1[0]
	var a1: Vector2 = v1[1]
	var b0: Vector2 = v2[0]
	var b1: Vector2 = v2[1]
	return a0.distance_to(b0) < 0.001 or a0.distance_to(b1) < 0.001 \
		or a1.distance_to(b0) < 0.001 or a1.distance_to(b1) < 0.001





## 带侵蚀的高度。表里没有的坐标（超出最大范围）退回原始高度。
static func eroded_elevation_of(c: Vector2i, world_seed: int) -> float:
	var table := _eroded_heights(world_seed)
	var k := key_of(c)
	if table.has(k):
		return float(table[k])
	return elevation_of(c, world_seed)




## 某一格的"湿度"（0~1）= **年均降水**，来自气候参数图。
## ⚠️ **W3b 起它不再是一张噪声了**：现在是"风把水汽从海上吹进来 → 沿路下雨 →
## 迎风坡爬升下得更多 → 背风侧干"推出来的（见 climate.gd 的 W3b 段）。
## 所以地图上会出现**雨影沙漠**，而不再是"随机干湿斑块"。
static func moisture_of(c: Vector2i, world_seed: int) -> float:
	return Climate.annual_precip_at(c, climate_for(world_seed))


## 高程 + 湿度 → 一层地形 + 一层地物（Red Blob 那篇的二维查表，阈值按本作的种类改过）。
## 仍是 f(坐标, 种子) 的纯函数。
## ===========================================================================
## W3a：气候参数图（**本项目第一次引入"参数图"**，见 climate.gd 顶部与 世界生成-W3.md 第六节）
##   温度可以按格算，但**降水不行**（要沿风向累积）→ 所以先把"场"搭起来，W3b 才做得下去。
##   场**不进存档**（种子 + 配方可重算）→ SAVE_VERSION 不变。
## ===========================================================================

## 这一局的气候场（128×128，按种子缓存）
static func climate_for(world_seed: int) -> Dictionary:
	var fn := func(c: Vector2i) -> float:
		return elevation_of(c, world_seed)
	return Climate.build(world_seed, fn)


## 某格的**年平均温度**（℃）
static func annual_temp_at(c: Vector2i, world_seed: int) -> float:
	return Climate.annual_temp_at(c, climate_for(world_seed))


## 某格的**年均降水**（归一化 0~1）—— 与 `moisture_of()` 同源，给自检用
static func annual_precip_at(c: Vector2i, world_seed: int) -> float:
	return Climate.annual_precip_at(c, climate_for(world_seed))


## 某格的**柯本气候类别**（W3c，如 "Af" / "BW" / "ET"）
static func koppen_at(c: Vector2i, world_seed: int) -> String:
	return Climate.koppen_at(c, climate_for(world_seed))


## W3c：按**柯本类别**决定"这点湿度能长出什么"。
## 取代 W3a 那个"拍一个温度阈值"的做法 —— 现在"极地不长树""沙漠不长树""草原只长草"
## 都是**气候类别**说了算（判据见 climate.gd 的 koppen_at）。
static func _moist_for_climate(m: float, koppen: String) -> float:
	match koppen:
		"BW":
			return 0.0                                  # 沙漠：什么都不长
		"BS":
			return clampf(maxf(m, 0.30), 0.0, 0.45)     # 草原：至少长草，但别到森林
	return m


## 地形 / 地物：由**高度 + 湿度 + 气候类别**决定。
## ⚠️ W3c 只换了"气候那一层"（`_moist_for_climate`），**下面的高度判断一字未改**。
static func biome_of(e: float, m_in: float, koppen: String = "", tier: String = "",
		temp_tier: String = "") -> Dictionary:
	if e < 0.36:
		return {"terrain": "water", "cover": ""}
	# ---- W3c：极地（E）单独处理 —— 不长树，地面是"荒地"，**不是沙漠**（沙漠是 B 类的事）----
	# W5 第 3 层（冷热档）：**冷档也走这一支** —— 档位是**排名**来的（最冷的那一批），
	#   所以"这里没有植被"同样是**数据**决定的，不是我拍的阈值。
	if temp_tier == "cold" or koppen.substr(0, 1) == "E":
		if e < 0.50:
			return {"terrain": "plain", "cover": ""}
		if e < 0.72:
			return {"terrain": "wasteland", "cover": ""}
		return {"terrain": "mountain", "cover": ""}
	var m := _moist_for_climate(m_in, koppen)
	# W5 配额（第 2 层：干湿三档）：档位由**排名**决定，**不再看绝对阈值** ——
	#   dry → 当"最干"处理（低地成沙、高地成秃地）
	#   medium → 稳稳定在**草原带**（"草原必须看得见"由此从碰运气变成构造保证）
	#   wet → 至少到森林带（本来就很湿的仍会是沼泽，因为下面还按 m 分）
	if tier == "dry":
		m = 0.0
	elif tier == "medium":
		m = clampf(m, 0.23, 0.45)
	elif tier == "wet":
		m = maxf(m, 0.55)
	# BW 沙漠：低地一律显示成"沙"（dune）——
	# 否则会变成"秃丘陵"，玩家根本看不出那是一片沙漠（实测 dune 0 格就是这么来的）。
	if koppen == "BW" and e < 0.62:
		return {"terrain": "dune", "cover": ""}
	# ⚠️ 2026-10-13 重排**湿度分档**：原表把"草地"放在比"森林"更湿的一档（m>0.45→草、m>0.22→林），
	#    结果**草原被挤成一条窄带**（实测只占 8%），而干旱区多半落在丘陵上成了秃地（沙地 0 格）。
	#    常识顺序应当是：**干旱→沙 ／ 中湿→草原 ／ 较湿→森林 ／ 最湿→沼泽**。现在按这个排。
	if e < 0.50:
		if m > 0.75:
			return {"terrain": "plain", "cover": "swamp"}
		if m > 0.50:
			return {"terrain": "plain", "cover": "forest"}
		if m > 0.22:
			return {"terrain": "plain", "cover": "grass"}
		return {"terrain": "dune", "cover": ""}
	if e < 0.62:
		if m > 0.50:
			return {"terrain": "hill", "cover": "forest"}
		if m > 0.22:
			return {"terrain": "hill", "cover": "grass"}
		return {"terrain": "hill", "cover": ""}
	if e < 0.72:
		if m > 0.60:
			return {"terrain": "hill", "cover": "forest"}
		if m > 0.22:
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
## ===========================================================================
## W5 配额 · 第 1 层：**水陆配额**（用户方案："配额不是算的、也不是随机的，
## 而是从裁下来的那块世界图上读出来的；裁切时水陆比例已经知道，存下来就行"）
## ===========================================================================

## 这一局**裁切时测到的陆地占比**。已存进配方就直接用（不重算）——
## 用户原话："裁的时候就知道，存下来就行"。
static func land_ratio_for(world_seed: int, state: Dictionary = {}) -> float:
	if state.has("worlds"):
		var ws: Array = state["worlds"]
		if ws.size() > 0:
			var w0: Dictionary = ws[0]
			if w0.has("land_ratio"):
				return float(w0["land_ratio"])
	var fn := func(cc: Vector2i) -> float:
		return elevation_of(cc, world_seed)
	return Climate.land_fraction(Climate.get_crop(), fn)


## 把"任意水位线"映射成 `biome_of()` 认识的那条线（`SEA_LEVEL`）。
## 这样**不用改 biome_of 的阈值**，陆地内部的地形比例（平原/丘陵/山地）也不会被挤压。
static func remap_above_water(e: float, water_line: float) -> float:
	if e < water_line:
		return 0.0                      # 水下：任何 < SEAL_LEVEL 的值都一样
	var span := maxf(0.0001, 1.0 - water_line)
	return SEA_LEVEL + (e - water_line) * (1.0 - SEA_LEVEL) / span


## 算出这一局的**水位线**（W5 水陆配额）。做法 = **取高程排名的那一档**（等价于取一条等值线）：
##   · **海岸线形状天然保留**（等值线的形状就是原本海岸的形状）；
##   · **水陆数量精确命中**目标（不是靠阈值碰运气）。
## ⚠️ 本函数**只做排名、不改任何地块** —— 调用方必须"**先把水位线算好，再造地块**"，
##    这样地形 / 地物 / **资源**一次算对。
##    （我第一版是"先造地块、再回去改地形"，结果地块上的**资源**还是按旧地形放的 →
##     木头长在非森林上，seed_check 当场报红。顺序不能反：资源是看地形地物放的。）
static func land_quota_water_line(world_seed: int, state: Dictionary) -> float:
	var ratio := land_ratio_for(world_seed, state)
	var all_cells := Hex.spiral(Consts.MAP_START_RADIUS)
	var total := all_cells.size()
	if total <= 2:
		return -1.0
	var target_land := clampi(int(round(ratio * float(total))), 1, total - 1)
	# 1) 收高度（用**侵蚀后**的高度 —— 那才是地形那一层真正用的）
	var heights: Array = []
	for c in all_cells:
		heights.append(float(eroded_elevation_of(c, world_seed)))
	heights.sort()
	# 2) 水位线 = 从低往高数第 (总格数 - 目标陆地数) 个的高度
	var wl := float(heights[total - target_land])
	# 3) 存进世界配方（下次不用重测）
	if state.has("worlds"):
		var ws2: Array = state["worlds"]
		if ws2.size() > 0:
			(ws2[0] as Dictionary)["land_ratio"] = ratio
			(ws2[0] as Dictionary)["water_line"] = wl
	return wl


## W5 配额 · 第 2 层：**干湿三档的名额** —— 从原型图上"**游戏地图所占那一块**"的分布读出来。
## 用户原话要点："读取地形图上记载的水量湿度之类的，再把这个数据转换为配额比例。"
## → 所以名额**不是**我另定的比例、**也不是**随机：是量出来的。
## 分档用**同一套阈值**（后面 biome_of 也是这套）：≤0.22 干 ／ ≤0.50 中 ／ >0.50 湿。
## 返回 { dry, medium, wet }，已按世界的**陆地格数**缩放好。
static func moisture_quota_for(world_seed: int, land_total: int) -> Dictionary:
	var f := climate_for(world_seed)
	var size := int(f["size"])
	var half := Climate.dead_half()
	var crop := Climate.get_crop()
	var scale := 1.0 / Climate.DEAD_SCALE
	var lo := int(float(size) * (0.5 - 0.5 * scale))
	var hi := int(float(size) * (0.5 + 0.5 * scale))
	var heights: PackedFloat32Array = f["heights"]
	var m_lo := float(f.get("m_lo", 0.22))
	var m_hi := float(f.get("m_hi", 0.50))
	var n_dry := 0
	var n_mid := 0
	var n_wet := 0
	for gy in range(lo, hi):
		for gx in range(lo, hi):
			if float(heights[gy * size + gx]) < Climate.SEA_E:
				continue                       # **只统计陆地**（水里不参与湿度分配）
			# 网格点 → 世界坐标（减掉裁切偏移）→ 只取地图圆盘内的点
			var p := Vector2((float(gx) + 0.5) / float(size) * 2.0 * half.x - half.x,
				(float(gy) + 0.5) / float(size) * 2.0 * half.y - half.y) - crop
			var c := Hex.pixel_to_axial(p, 1.0)
			if Hex.distance(c, Vector2i.ZERO) > Consts.MAP_START_RADIUS:
				continue
			var m := Climate.annual_precip_at(c, f)
			if m <= m_lo:
				n_dry += 1
			elif m <= m_hi:
				n_mid += 1
			else:
				n_wet += 1
	var tot := n_dry + n_mid + n_wet
	if tot <= 0:
		return {"dry": 0, "medium": 0, "wet": 0}
	var k := float(land_total) / float(tot)
	return {"dry": int(round(float(n_dry) * k)),
		"medium": int(round(float(n_mid) * k)),
		"wet": int(round(float(n_wet) * k))}


## 把三档名额**按排名从两端往中间分配**（用户："一边从最湿的地方开始分配，
## 另一边从最干的地方开始分配；干的和湿的额度用完了，剩下的都算中等湿度"）。
## 返回 { 地块键 -> "dry"/"medium"/"wet" }；**只对陆地格**分配。
## ⚠️ 排序必须**确定**：并列时按坐标键兜底（否则同一配方两次生成可能不一样，违反 W1 的约定）。
static func moisture_tiers_for(world_seed: int, water_line: float) -> Dictionary:
	var land: Array = []
	for c in Hex.spiral(Consts.MAP_START_RADIUS):
		var e := float(eroded_elevation_of(c, world_seed))
		if water_line >= 0.0 and e < water_line:
			continue                            # 水面不参与
		land.append({"k": key_of(c), "m": float(moisture_of(c, world_seed))})
	if land.is_empty():
		return {}
	land.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ma := float(a["m"])
		var mb := float(b["m"])
		if not is_equal_approx(ma, mb):
			return ma < mb
		return str(a["k"]) < str(b["k"]))
	var q := moisture_quota_for(world_seed, land.size())
	var n_dry: int = mini(int(q["dry"]), land.size())
	var n_wet: int = mini(int(q["wet"]), maxi(0, land.size() - n_dry))
	var out := {}
	for i in land.size():
		var tier := "medium"
		if i < n_dry:
			tier = "dry"                       # 最干的那一批
		elif i >= land.size() - n_wet:
			tier = "wet"                       # 最湿的那一批
		out[str((land[i] as Dictionary)["k"])] = tier
	return out


## W5 配额 · 第 3 层：**冷热三档的名额** —— 同法，从原型图那一块的**温度分布**读出来。
## 门槛取"整张原型图**陆地**年均温的 25 / 70 分位"（climate.gd 里算好、存在场里）。
static func temp_quota_for(world_seed: int, land_total: int) -> Dictionary:
	var f := climate_for(world_seed)
	var size := int(f["size"])
	var half := Climate.dead_half()
	var crop := Climate.get_crop()
	var scale := 1.0 / Climate.DEAD_SCALE
	var lo := int(float(size) * (0.5 - 0.5 * scale))
	var hi := int(float(size) * (0.5 + 0.5 * scale))
	var heights: PackedFloat32Array = f["heights"]
	var t_lo := float(f.get("t_lo", -5.0))
	var t_hi := float(f.get("t_hi", 20.0))
	var n_cold := 0
	var n_mid := 0
	var n_hot := 0
	for gy in range(lo, hi):
		for gx in range(lo, hi):
			if float(heights[gy * size + gx]) < Climate.SEA_E:
				continue
			var p := Vector2((float(gx) + 0.5) / float(size) * 2.0 * half.x - half.x,
				(float(gy) + 0.5) / float(size) * 2.0 * half.y - half.y) - crop
			var c := Hex.pixel_to_axial(p, 1.0)
			if Hex.distance(c, Vector2i.ZERO) > Consts.MAP_START_RADIUS:
				continue
			var tv := Climate.annual_temp_at(c, f)
			if tv <= t_lo:
				n_cold += 1
			elif tv <= t_hi:
				n_mid += 1
			else:
				n_hot += 1
	var tot := n_cold + n_mid + n_hot
	if tot <= 0:
		return {"cold": 0, "medium": 0, "hot": 0}
	var k := float(land_total) / float(tot)
	return {"cold": int(round(float(n_cold) * k)),
		"medium": int(round(float(n_mid) * k)),
		"hot": int(round(float(n_hot) * k))}


## 冷热三档按排名**从两端往中间分配**：最冷的占冷名额、最热的占热名额，剩下全算中等。
## 与干湿档同构（并列同样按坐标兜底，保证同配方逐位一致）。
static func temp_tiers_for(world_seed: int, water_line: float) -> Dictionary:
	var land: Array = []
	for c in Hex.spiral(Consts.MAP_START_RADIUS):
		var e := float(eroded_elevation_of(c, world_seed))
		if water_line >= 0.0 and e < water_line:
			continue
		land.append({"k": key_of(c), "t": float(annual_temp_at(c, world_seed))})
	if land.is_empty():
		return {}
	land.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ta := float(a["t"])
		var tb := float(b["t"])
		if not is_equal_approx(ta, tb):
			return ta < tb
		return str(a["k"]) < str(b["k"]))
	var q := temp_quota_for(world_seed, land.size())
	var n_cold: int = mini(int(q["cold"]), land.size())
	var n_hot: int = mini(int(q["hot"]), maxi(0, land.size() - n_cold))
	var out := {}
	for i in land.size():
		var tier := "medium"
		if i < n_cold:
			tier = "cold"                     # 最冷的那一批
		elif i >= land.size() - n_hot:
			tier = "hot"                      # 最热的那一批
		out[str((land[i] as Dictionary)["k"])] = tier
	return out


static func generate(state: Dictionary) -> void:
	# v1.8.20.9：不再自己造 rng —— 每一格的地形/资源由 _make_tile(c, 世界种子) 直接算出来
	var world_seed := int(state["seed"])
	var tiles := {}
	var wl := land_quota_water_line(world_seed, state)
	# W5 配额（第 2 层：干湿三档）：名额从原型图那一块的分布读出来 → 按排名从两端分配
	var tiers := moisture_tiers_for(world_seed, wl)
	# W5 配额（第 3 层：冷热三档）：同法 —— 名额读自原型图那一块的温度分布
	var ttiers := temp_tiers_for(world_seed, wl)
	for c in Hex.spiral(Consts.MAP_START_RADIUS):
		var kk := key_of(c)
		tiles[kk] = _make_tile(c, world_seed, wl, str(tiers.get(kk, "")), str(ttiers.get(kk, "")))

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

## `water_line` ≥ 0 时，用 W5 的**水陆配额水位线**（把高度按它重映射到 biome_of 认的那条线）；
## 传 -1（默认）则按原来的固定水线走。
## `tier` 是 W5 第 2 层的**干湿三档**（"dry"/"medium"/"wet"，空串=不用配额）；
## `temp_tier` 是第 3 层的**冷热三档**（"cold"/"medium"/"hot"）。
static func _make_tile(c: Vector2i, world_seed: int, water_line: float = -1.0,
		tier: String = "", temp_tier: String = "") -> Dictionary:

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
	# W3c：多给一个**柯本气候类别**（由最冷月/最热月温度 + 年降水毫米判）→ 决定地物
	# W5：高程先按**配额水位线**重映射（水位线以下是水，以上按比例铺开）→ 水陆比例精确命中
	var e_here := float(eroded_elevation_of(c, world_seed))
	if water_line >= 0.0:
		e_here = remap_above_water(e_here, water_line)
	var b := biome_of(e_here, moisture_of(c, world_seed), koppen_at(c, world_seed), tier, temp_tier)

	t["terrain"] = b["terrain"]
	t["cover"] = b["cover"]
	# W5 配额：把**档位**记在地块上（不靠"从地物反推"——山地/极地/沙漠类都会显示成秃地，反推会数错）
	if tier != "":
		t["moist_tier"] = tier
	if temp_tier != "":
		t["temp_tier"] = temp_tier




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
