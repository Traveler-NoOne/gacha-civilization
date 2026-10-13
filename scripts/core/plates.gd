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


## 生成一张板块图。
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
