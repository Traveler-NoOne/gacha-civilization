class_name Plates
extends RefCounted
## S1：板块与边界（世界生成 W2 的第一步，见 docs/更新指导/世界生成-W2.md）。
##
## ⚠️ 本模块**刻意不碰游戏地图**：它只负责"在方格参数图上算出一张板块图"，
## 由 W2 的后续步骤（高程合成 S2）决定怎么用它。所以现在把它接上与否不影响观感。
##
## 全程**确定**：所有随机都来自 `Hex.hash01(坐标, 盐)`，**不含** RandomNumberGenerator；
## 并列一律按"序号小的优先"兜底 → 同一 (seed, size, plate_count) 每次结果逐位一致。
##
## 边界类型只分三种（相向 / 相离 / 错动）：
##   "碰撞 vs 俯冲"、"裂谷 vs 洋中脊" 要靠**地壳高低**才能分
##   （低的那一侧被压到下面 → 海沟），那是 S2 的事，这里不给结论。

## 边界类型（与 S2 约定：CONVERGENT 会造山/造沟、DIVERGENT 会造谷/造脊、TRANSFORM 只错动）
enum Kind { NONE, CONVERGENT, DIVERGENT, TRANSFORM }

const KIND_NAMES := {
	Kind.NONE: "无", Kind.CONVERGENT: "相向（碰撞/俯冲）",
	Kind.DIVERGENT: "相离（裂谷/洋中脊）", Kind.TRANSFORM: "错动（转换断层）",
}

## 盐值：换一个盐 = 换一条独立的随机流（同一 seed 下互不相关）
const SALT_X := 9101
const SALT_Y := 9102
const SALT_ANGLE := 9103
const SALT_SPEED := 9104

## 判定"以切向为主"的阈值：法向速度小于这个比例，就算转换断层
const TRANSFORM_RATIO := 0.45

## 4 邻域，**顺序固定**（→ 结果确定）。用常量数组而不是每格新建，顺便省掉每格一次分配。
const NEIGHBORS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1),
]


## ===========================================================================
## 无网格原语（W2 的 S2 用这一组把板块接进高程）
##   为什么要有它们：现在的高度是 `f(一格坐标, 种子)` 的**逐格纯函数**
##   （见 world_gen.elevation_of），所以板块也必须能"按一格直接问"，
##   而不是只能先算出整张网格再采样。坐标统一用**像素空间**（Hex.axial_to_pixel，size=1）——
##   那里各向同性，距离/法线才有意义。
## ===========================================================================

## ===========================================================================
## 造山 / 造沟的强度与宽度（**按"相互作用类型"分级**；全是可逆参数，只为"像真实地理"而调）
##   ⚠️ 碰撞必须够大（0.34）：这样"底子 0.40 的陆格"也能被顶过 0.72 的山脉线（world_gen.biome_of），
##      于是整条边界连成一条**长墙**，而不是碰阈值碰出几个孤峰（W2 的老毛病，见 世界生成-W2b.md）。
## ===========================================================================
const AMP_COLLISION := 0.36      ## 陆-陆碰撞：山系（喜马拉雅型）。**别贪大**：0.50 会让整条 4 格宽的带全越线 → 变疙瘩（实测）
const AMP_ARC_LAND := 0.30       ## 俯冲：陆侧的沿岸山链（科迪勒拉型）
const AMP_TRENCH := 0.20         ## 俯冲：洋侧的海沟（往下削）
const AMP_ARC := 0.26            ## 洋-洋相向：另一侧的岛弧
const AMP_RIFT := 0.14           ## 陆内裂谷（往下陷）
const AMP_RIDGE := 0.10          ## 洋中脊（微抬）

## 带宽（格）。⚠️ **碰撞取 2 而不是 4/5**：碰撞是**两侧都抬** —— 带宽 4 等于两条 4 格宽的带并排，
## 合起来就是 8 格厚的"双带"，眼睛看就是疙瘩（W2b 前两轮实测平均宽 6.1，元凶在此）。
## 取 2 之后只有 `d=1`（紧贴边界那一圈）能越线 → 两侧各 1 格 → **约 2 格厚的山脊**。
const W_COLLISION := 2
const W_SUBDUCT := 2
const W_NARROW := 3
## 找边界时最多看几格（= 最宽的那一种）
const SCAN_STEPS := 5

## 地壳类型：陆壳 / 洋壳
const CRUST_CONTINENTAL := 0
const CRUST_OCEANIC := 1
## 地壳类型由 **WorldGen.crust_for()** 按"该板覆盖地块的**基础高程均值**"算好再传进来
##（Plates 不依赖 WorldGen，避免循环依赖）。⚠️ 曾经这里按"种子离中心远近"猜 —— 那会让
## 碰撞带常常落在**海里**（陆壳板覆盖的其实是海），长不出长墙；2026-10-13 改成均值判据。

static var _frame_cache := {}


## 某一局种子的板块骨架（种子位置 + 运动矢量），按种子缓存。
## 种子铺在"当前地图外接矩形 × 1.4"的盒子里 —— 这样边界真的会**穿过**地图，
## 而不是整张图落在同一块板里（那样就完全没有山脉了）。
static func frame(world_seed: int, plate_count: int = 8) -> Dictionary:
	var key := "%d/%d" % [world_seed, plate_count]
	if _frame_cache.has(key):
		return _frame_cache[key]
	var n := maxi(2, plate_count)
	var map_r := float(Consts.MAP_START_RADIUS)
	var map_half := Vector2(Hex.SQRT3 * map_r, 1.5 * map_r)
	var half := map_half * 1.4
	var seeds: Array = []
	for i in n:
		var fx := Hex.hash01(Vector2i(i, 0), SALT_X + world_seed)
		var fy := Hex.hash01(Vector2i(i, 0), SALT_Y + world_seed)
		seeds.append(Vector2((fx * 2.0 - 1.0) * half.x, (fy * 2.0 - 1.0) * half.y))
	var out := {"seeds": seeds, "motions": _make_motions(world_seed, n), "count": n,
		"half": half, "map_half": map_half}
	_frame_cache[key] = out
	return out


## 像素坐标属于哪一块板（最近种子；并列取序号小的 → 确定）
static func plate_at_point(p: Vector2, seeds: Array) -> int:
	var best := 0
	var best_d := INF
	for i in seeds.size():
		var s: Vector2 = seeds[i]
		var d := p.distance_squared_to(s)
		if d < best_d - 0.000001:
			best_d = d
			best = i
	return best


## 这一格"**实际会用到的那条边界**"：SCAN_STEPS 格内、相向/相离里**最强**的一条
##（并列保留先遇到的 → 确定）。返回 `{kind, stress, dist}`；没有边界时 kind = `Kind.NONE`。
## 之所以要单独抽出来：自检要能问"函数到底按哪条边界算的"，否则测试只能靠猜（2026-10-13 踩过）。
static func boundary_for(c: Vector2i, world_seed: int, plate_count: int = 8) -> Dictionary:
	var fr := frame(world_seed, plate_count)
	var seeds: Array = fr["seeds"]
	var motions: Array = fr["motions"]
	var p := Hex.axial_to_pixel(c.x, c.y, 1.0)
	var mine := plate_at_point(p, seeds)
	# ⚠️ **按距离由近及远找**，只在同一圈里比强度。
	#    第一版取"全局最强"的那条边界 → 山带的 d 会指向 5 格外的强边界（带外 = 效应 0），
	#    于是山带被撕成碎块（2026-10-13 自检 + 识图一起抓到）。
	for ring in range(1, SCAN_STEPS + 1):
		var found := Kind.NONE
		var best_stress := 0.0
		var best_other := -1
		for o: Vector2i in _ring(ring):
			var q := c + o
			var their := plate_at_point(Hex.axial_to_pixel(q.x, q.y, 1.0), seeds)
			if their == mine:
				continue
			var rel: Vector2 = (motions[mine] as Vector2) - (motions[their] as Vector2)
			var normal := (Hex.axial_to_pixel(q.x, q.y, 1.0) - p).normalized()
			var k := classify(rel, normal)
			if k == Kind.TRANSFORM:
				continue
			var st := absf(rel.dot(normal))
			if found == Kind.NONE or st > best_stress + 0.000001:
				found = k
				best_stress = st
				best_other = their
		if found != Kind.NONE:
			return {"kind": found, "stress": best_stress, "dist": ring, "mine": mine, "other": best_other}
	return {"kind": Kind.NONE, "stress": 0.0, "dist": 0, "mine": mine, "other": mine}


## 恰好距离 r 的那一圈（= spiral(r) 减去 spiral(r-1)）
static func _ring(r: int) -> Array:
	var out: Array = []
	var inner := {}
	if r > 1:
		for c in Hex.spiral(r - 1):
			inner[c] = true
	for c in Hex.spiral(r):
		if not inner.has(c):
			out.append(c)
	return out


## 板块对某一格高度的影响（**可正可负**，0 = 无影响）。
## **由两块板的"地壳类型 + 相遇方式"决定**（不再看逐格的噪声底高 —— 那会让同一条边界山沟交替）：
##   陆-陆相向 → **山系**（喜马拉雅型）｜洋-陆相向 → 洋侧**海沟**、陆侧**沿岸山链**（科迪勒拉型）
##   洋-洋相向 → 一侧海沟、另一侧**岛弧**（序号大的那块先俯冲 —— 用它代替"谁更老更密"，确定）
##   陆-陆相离 → **裂谷**｜含洋相离 → 洋侧**洋中脊**、陆侧小裂谷｜错动 → 0
## ⚠️ 振幅**按类型分级、且已按类型定上限**（见本文件顶部的 AMP_* 常量）。
static func effect_at(c: Vector2i, world_seed: int, crust: PackedByteArray, plate_count: int = 8) -> float:
	var b := boundary_for(c, world_seed, plate_count)
	if int(b["kind"]) == Kind.NONE:
		return 0.0
	var d := int(b["dist"])
	var mine := int(b["mine"])
	var other := int(b["other"])
	var my_land := int(crust[mine]) == CRUST_CONTINENTAL
	var their_land := int(crust[other]) == CRUST_CONTINENTAL
	match int(b["kind"]):
		Kind.CONVERGENT:
			if my_land and their_land:
				return _belt(AMP_COLLISION, d, W_COLLISION)
			if not my_land and their_land:
				return -_belt(AMP_TRENCH, d, W_NARROW)
			if my_land and not their_land:
				return _belt(AMP_ARC_LAND, d, W_SUBDUCT)
			return -_belt(AMP_TRENCH, d, W_NARROW) if mine > other else _belt(AMP_ARC, d, W_NARROW)
		Kind.DIVERGENT:
			if my_land and their_land:
				return -_belt(AMP_RIFT, d, W_NARROW)
			return _belt(AMP_RIDGE, d, W_NARROW) if not my_land else -_belt(AMP_RIFT, d, W_NARROW)
		_:
			return 0.0


## 条带衰减：边界上（d=1）取满 amp，到 w 格外衰减到 0
static func _belt(amp: float, d: int, w: int) -> float:
	return amp * clampf(1.0 - float(d - 1) / float(maxi(1, w)), 0.0, 1.0)


## ===========================================================================
## 网格版（保留给将来的"死地图"用：整张参数图一次算完，见总纲）
## ===========================================================================


## 返回 { plate: PackedInt32Array, kind: PackedByteArray, stress: PackedFloat32Array,
##        seeds: Array[Vector2], motions: Array[Vector2], size: int, plate_count: int }
## 索引约定：i = y * size + x（行优先）。
static func build(world_seed: int, size: int, plate_count: int = 8) -> Dictionary:
	var n := maxi(2, plate_count)
	var seeds := _make_seeds(world_seed, size, n)
	var motions := _make_motions(world_seed, n)

	var plate := PackedInt32Array()
	plate.resize(size * size)
	for y in size:
		for x in size:
			plate[y * size + x] = _nearest_plate(x, y, seeds)

	var kind := PackedByteArray()
	var stress := PackedFloat32Array()
	kind.resize(size * size)
	stress.resize(size * size)
	for y in size:
		for x in size:
			var i := y * size + x
			var a := plate[i]
			# 按固定顺序找第一个"属于别的板块"的邻居（4 邻域，顺序固定 → 确定）
			for d in NEIGHBORS:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx < 0 or ny < 0 or nx >= size or ny >= size:
					continue
				var b: int = plate[ny * size + nx]
				if b == a:
					continue
				var rel: Vector2 = motions[a] - motions[b]
				var normal := Vector2(float(d.x), float(d.y)).normalized()
				var k := classify(rel, normal)
				kind[i] = k
				stress[i] = absf(rel.dot(normal))   # 法向挤压/拉张的强度（S2 用它决定造山/造谷的幅度）
				break
	return {
		"plate": plate, "kind": kind, "stress": stress,
		"seeds": seeds, "motions": motions, "size": size, "plate_count": n,
	}


## 边界分类：rel = 两块板块的相对速度（a 减 b），normal = **从 a 指向 b** 的法向。
## 法向分量为**正**（a 沿法向朝 b 靠拢）→ 相向；为**负**（彼此拉开）→ 相离；法向太弱 → 错动。
## ⚠️ 这个符号 2026-10-13 被合成用例抓出来过一次（原来写反了）—— 别凭直觉改。
static func classify(rel: Vector2, normal: Vector2) -> int:
	var vn := rel.dot(normal)
	if absf(vn) < TRANSFORM_RATIO * rel.length():
		return Kind.TRANSFORM
	return Kind.CONVERGENT if vn > 0.0 else Kind.DIVERGENT


## 板块种子位置（确定：坐标哈希，不含 rng）
static func _make_seeds(world_seed: int, size: int, n: int) -> Array:
	var out: Array = []
	for i in n:
		var fx := Hex.hash01(Vector2i(i, 0), SALT_X + world_seed)
		var fy := Hex.hash01(Vector2i(i, 0), SALT_Y + world_seed)
		# 留 10% 边距，免得种子贴在边上、板块被切掉一半
		out.append(Vector2(0.1 * size + fx * 0.8 * size, 0.1 * size + fy * 0.8 * size))
	return out


## 每个板块的运动矢量（方向 + 速度，确定）
static func _make_motions(world_seed: int, n: int) -> Array:
	var out: Array = []
	for i in n:
		var ang := Hex.hash01(Vector2i(i, 1), SALT_ANGLE + world_seed) * TAU
		var spd := 0.5 + Hex.hash01(Vector2i(i, 1), SALT_SPEED + world_seed) * 0.5
		out.append(Vector2(cos(ang), sin(ang)) * spd)
	return out


## 最近种子：平方距离比较；**并列取序号小的**（保证确定）
static func _nearest_plate(x: int, y: int, seeds: Array) -> int:
	var best := 0
	var best_d := INF
	for i in seeds.size():
		var s: Vector2 = seeds[i]
		var dx := float(x) - s.x
		var dy := float(y) - s.y
		var d := dx * dx + dy * dy
		if d < best_d - 0.000001:
			best_d = d
			best = i
	return best


## 给自检用的统计：各类边界格数量
static func count_kinds(grid: Dictionary) -> Dictionary:
	var out := {}
	var kind: PackedByteArray = grid["kind"]
	for k in kind:
		out[int(k)] = int(out.get(int(k), 0)) + 1
	return out
