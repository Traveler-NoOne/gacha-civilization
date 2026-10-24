class_name WorldgenBuilder
extends RefCounted
## 世界生成**总控**（噪声版）✓ 2026-10-22 起是**唯一的**生成器（旧 `WorldGen` 已删）✓
##
## 做法（经典骨架 ＋ 三处修正 ✓）：
##   ① **大结构**：fBm 噪声 —— 决定**海陆**和**高原 / 丘陵**的大块形状 ✓
##   ② **山脊**：另一路 **RIDGED（脊状）噪声** —— 它的正值**天生就是狭长的脊** ✓✓
##      只叠在**内陆高地**上 ✓（平原和海洋不加 ✓）→ 山是"狭长的脊" ✓ 大片高地留作高原 ✓
##   ③ 湿度：第三路低频噪声 ✓
##   ④ 从地图中心向外衰减 → 四周必成海 ✓
##   ⑤ **海平面按"目标陆地占比"定**（分位数）✓ 不用手调水线 ✓
##   ⑥ **山脉瘦身**：太胖的山团降级成高原 / 山地（`Peaks`）✓
##
## 高度标尺 = **0~10**：0 = 海沟底 ✓ **1.0 = 海平面** ✓ 5.0 = 珠峰 ✓ 10.0 = 大气层顶 ✓
## ⚠️ **纯函数** ✓：地形 = f(坐标, 种子) ＋ 两个**全图参数**（`lift` / `sea_gain`）✓
##    这两个数在 `generate()` 里算出来，存进 `state["gen"]` ✓ —— `expand_map()` 靠它们复算新格 ✓

## ---- 大结构 / 海陆 ----
## 噪声频率 = 这个数 ÷ 半径 ✓（**跟着地图大小走** ✓ 改半径不用改这里 ✓）
const FREQ_BASE := 0.9
## 水线在噪声上的位置 ✓：噪声高于它 = 陆 ✓
## ⚠️ 它**不再**是"陆地占多少"的旋钮 ✗ —— 海岸线现在由下面的 `LAND_RATIO` 定 ✓
##   它只决定"多少陆地落在**平缓放大**那一段、多少进**幂次抬升**那一段" ✓（改大了山更多 ✗）
const SEA_NOISE := 0.13
## ★ **分段缩放**——治"海洋没有浅海"✗：水下放**缓** ✓ 陆上放**陡** ✓
const SEA_SCALE := 2.2
const LAND_SCALE := 5.0
## ★ **幂次压缩**——治"山太大团"✗：指数 > 1 → 只有**极端高**的噪声才够得着山地线 ✓
##   （指数 1.0 = 线性 ✗ 那会让中高地也变成山 ✓；1.6 能把大片中高地留在高原 / 丘陵 ✓✓）
const LAND_POW := 1.6

## ★ **陆地占比**（2026-10-22 用户定：先按 50% 试 ✓）
##   做法：把整张图的基准高度排序取分位数当海平面 ✓ 于是**每张图**都恰好 LAND_RATIO 的格子在水上 ✓
##   （改这个数就是"海多海少"的总开关 ✓ 改 `SEA_NOISE` 只会让山变多 ✗）
const LAND_RATIO := 0.50
## 海水最深沉到哪（1.0 = 海平面）：陆地一抬，海会整体变浅 ✗ → 水下一段按这个目标拉回去 ✓
const SEA_DEPTH := 0.78

## ---- 山脊 ----
const FREQ_RIDGE := 2.6        ## 比大结构细 ✓ 脊才细 ✓
const RIDGE_AMP := 1.8         ## 山脊的最大抬升 ✓
const RIDGE_START := 2.20      ## 从多高开始叠山脊 ✓（**高原带里**才叠 ✓ 丘陵和低高原不加 ✓）
## ★ **山脊阈值** ✓ —— 只有 ridge 值高过它才叠 ✓
##   ✗ 旧版是"连续叠加"（inland 一接近 1 就整片被抬 ✗）→ 山还是成团 ✗
##   ✓ 现在用阈值**卡出"脊线"**✓ 再配"单层 ridged"（多层叠加会把线糊成片 ✗）
const RIDGE_THRESHOLD := 0.55

## ---- 高度上下限（**刻意不碰 0 和 5.0** ✓）----
const H_MIN := 0.22
const H_MAX := 4.90
## 边缘衰减：半径的多少之后开始下沉 ✓ 到最外圈下沉多少 ✓
const FALLOFF_START := 0.62
const FALLOFF_DEPTH := 4.0


## 生成一整个世界，填进 `state` ✓（写 `tiles` / `capital` / `gen` ✓）
static func generate(state: Dictionary) -> void:
	# 同步版：一次跑完（测试 / 非加载路径用）✓
	var ctx := _gen_begin(state)
	_gen_heights(ctx, 0, (ctx["cells"] as Array).size())
	_gen_sea(ctx)
	_gen_tiles(ctx, 0, (ctx["cells"] as Array).size())
	_gen_finish(ctx, state)


## 分帧版本：每帧只处理 chunk 个格子，`on_progress(0~100)` 报告**真实进度** ✓
## 为什么需要：同步生成会阻塞主线程，进度条不动，玩家会以为游戏卡死（见 loading_screen 的说明）。
## 分段不改变任何计算顺序，所以同一颗种子产出的地图与同步版完全一致 ✓
static func generate_async(state: Dictionary, on_progress: Callable = Callable(), chunk: int = 400) -> void:
	var ctx := _gen_begin(state)
	var cells: Array = ctx["cells"]
	var n := cells.size()
	# 前半：高度 + 湿度
	var i := 0
	while i < n:
		var j := mini(i + chunk, n)
		_gen_heights(ctx, i, j)
		i = j
		_report(on_progress, 50.0 * float(i) / float(n))
		await (Engine.get_main_loop() as SceneTree).process_frame
	_gen_sea(ctx)
	# 后半：地形
	i = 0
	while i < n:
		var j := mini(i + chunk, n)
		_gen_tiles(ctx, i, j)
		i = j
		_report(on_progress, 50.0 + 48.0 * float(i) / float(n))
		await (Engine.get_main_loop() as SceneTree).process_frame
	_gen_finish(ctx, state)
	_report(on_progress, 100.0)


static func _report(cb: Callable, p: float) -> void:
	if cb.is_valid():
		cb.call(clampf(p, 0.0, 100.0))


## ---- 分段步骤（同步版与分帧版共用；顺序不变 = 结果不变）----
static func _gen_begin(state: Dictionary) -> Dictionary:
	var seed := int(state["seed"])
	var radius := Consts.MAP_START_RADIUS
	return {
		"seed": seed,
		"ns": _noises(seed, radius),
		"cells": Hex.spiral(radius),
		"raw": {},
		"moist": {},
		"tiles": {},
		"lift": 1.0,
		"sea_gain": 1.0,
	}


static func _gen_heights(ctx: Dictionary, from: int, to: int) -> void:
	var ns: Dictionary = ctx["ns"]
	var cells: Array = ctx["cells"]
	var raw: Dictionary = ctx["raw"]
	var moist: Dictionary = ctx["moist"]
	for i in range(from, to):
		var c: Vector2i = cells[i]
		var k := TileManager.key_of(c)
		raw[k] = _raw_height(c, ns)
		moist[k] = _moisture_at(c, ns)


## 定海平面 + 海深补偿（依赖全部 raw 都算完，所以只能放在整段之后）
static func _gen_sea(ctx: Dictionary) -> void:
	var raw: Dictionary = ctx["raw"]
	var lift := 1.0 - _quantile(raw, 1.0 - LAND_RATIO)
	var lowest := 1.0
	for k2 in raw.keys():
		lowest = minf(lowest, float(raw[k2]) + lift)
	var sea_gain := 1.0
	if lowest < 0.999:
		sea_gain = clampf(SEA_DEPTH / (1.0 - lowest), 1.0, 3.0)
	ctx["lift"] = lift
	ctx["sea_gain"] = sea_gain


static func _gen_tiles(ctx: Dictionary, from: int, to: int) -> void:
	var ns: Dictionary = ctx["ns"]
	var cells: Array = ctx["cells"]
	var raw: Dictionary = ctx["raw"]
	var moist: Dictionary = ctx["moist"]
	var tiles: Dictionary = ctx["tiles"]
	var seed := int(ctx["seed"])
	var lift := float(ctx["lift"])
	var sea_gain := float(ctx["sea_gain"])
	for i in range(from, to):
		var c: Vector2i = cells[i]
		var k := TileManager.key_of(c)
		var h := _normalize(float(raw[k]), c, ns, lift, sea_gain)
		tiles[k] = TileLib.make(c, seed, {"height": h, "moisture": float(moist[k])})


static func _gen_finish(ctx: Dictionary, state: Dictionary) -> void:
	var tiles: Dictionary = ctx["tiles"]
	# 山脉瘦身：太胖的山团降级（靠高原的转高原、其余转山地）✓ 嫌太碎就删这一行 ✓
	Peaks.thin_mountains(tiles)
	state["tiles"] = tiles
	state["capital"] = choose_capital(tiles)
	# ⚠️ 扩图要靠这两个数复算新格 ✓ 所以必须进存档 ✓
	state["gen"] = {"lift": float(ctx["lift"]), "sea_gain": float(ctx["sea_gain"])}


## 生成之后追加 `rings` 圈新格子（发展系统 / 营地扩建）✓
## ⚠️ 新格必须与"一开始就生成这么大"一致 ✓ → 用 `generate()` 存下的 `lift` / `sea_gain` 复算 ✓
##    ✗ **不能**重跑 `generate()` —— 那会按新地图重算海平面，**老格子全变** ✗
static func expand_map(state: Dictionary, rings: int = 1) -> int:
	var tiles: Dictionary = state["tiles"]
	var seed := int(state["seed"])
	var cur := _radius_of(tiles)
	var target := mini(cur + rings, Consts.MAP_MAX_RADIUS)
	if target <= cur:
		return 0
	var gen: Dictionary = state["gen"]
	var lift := float(gen["lift"])
	var sea_gain := float(gen["sea_gain"])
	var ns := _noises(seed, Consts.MAP_START_RADIUS)
	var added := 0
	for c: Vector2i in Hex.spiral(target):
		var k := TileManager.key_of(c)
		if tiles.has(k):
			continue
		var h := _normalize(_raw_height(c, ns), c, ns, lift, sea_gain)
		tiles[k] = TileLib.make(c, seed, {"height": h, "moisture": _moisture_at(c, ns)})
		added += 1
	return added


## 挑出生点（首都）：非水、不贴边境、周围 3 格资源越多越好 ✓ 不含随机 → 同一张图永远同一格 ✓
static func choose_capital(tiles: Dictionary) -> String:
	var limit := int(float(Consts.MAP_START_RADIUS) * 0.78)
	var best_key := ""
	var best_score := -1
	var best_dist := 9999
	# ⚠️ 邻域螺旋是常量：**必须提到循环外**。原来每格都重建一次（7651 × 37），实测吃掉 239ms ✓
	var ring := Hex.spiral(3)
	for k in tiles.keys():
		var t: Dictionary = tiles[k]
		if TileLib.is_water(t):
			continue
		var c := TileManager.coord_of(str(k))
		var d := Hex.distance(c, Vector2i.ZERO)
		if d > limit:
			continue
		var score := 0
		for nb: Vector2i in ring:
			var nk := TileManager.key_of(c + nb)
			if not tiles.has(nk):
				continue
			var nt: Dictionary = tiles[nk]
			if TileLib.is_water(nt):
				continue
			if str(nt.get("resource", "")) != "":
				score += 1
		if score > best_score or (score == best_score and d < best_dist):
			best_score = score
			best_dist = d
			best_key = str(k)
	return best_key


# ===========================================================================
# 内部：噪声 / 单格高度 / 湿度 / 分位数
# ===========================================================================
## 三路噪声 ✓（大结构 / 山脊 / 湿度 ✓）
static func _noises(seed: int, radius: int) -> Dictionary:
	var base := FastNoiseLite.new()
	base.seed = seed
	base.noise_type = FastNoiseLite.TYPE_SIMPLEX
	base.frequency = FREQ_BASE / float(radius)
	base.fractal_type = FastNoiseLite.FRACTAL_FBM
	base.fractal_octaves = 4      # 4 层够了 ✓ 层数越多海岸线越碎 ✗
	base.fractal_gain = 0.5

	var ridge := FastNoiseLite.new()
	ridge.seed = seed + 5551
	ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX
	ridge.frequency = FREQ_RIDGE / float(radius)
	ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	# ⚠️ **单层** ✓ —— 多层 ridged 叠加会把"线状的脊"糊成"片" ✗
	ridge.fractal_octaves = 1
	ridge.fractal_gain = 0.5

	var moist := FastNoiseLite.new()
	moist.seed = seed + 9871
	moist.noise_type = FastNoiseLite.TYPE_SIMPLEX
	moist.frequency = 0.8 / float(radius)
	moist.fractal_type = FastNoiseLite.FRACTAL_FBM
	moist.fractal_octaves = 3

	return {"base": base, "ridge": ridge, "moist": moist}


## 基准高度（1.0 = 旧海平面；含边缘衰减；不含 lift / 海深补偿 / 山脊）✓
static func _raw_height(c: Vector2i, ns: Dictionary) -> float:
	var n_base: FastNoiseLite = ns["base"]
	var p := Hex.axial_to_pixel(c.x, c.y, 1.0)
	var dv := n_base.get_noise_2d(p.x, p.y) - SEA_NOISE
	var h := 1.0
	if dv < 0.0:
		# 水下：**放慢** ✓ → 浅海带变宽 ✓（不然一离开水线就掉到 clamp 下限、全是深海 ✗）
		h = 1.0 + dv * SEA_SCALE
	else:
		# 陆上：**幂次压缩** ✓ → 只有极端高的才成山 ✓ 大片中高地留在高原 / 丘陵 ✓✓
		h = 1.0 + pow(dv, LAND_POW) * LAND_SCALE
	# 从中心向外衰减 → 四周必成海 ✓（半径用**起始半径**：扩图的新格才与"一开始就生成这么大"一致 ✓）
	var d := float(Hex.distance(c, Vector2i.ZERO)) / float(Consts.MAP_START_RADIUS)
	if d > FALLOFF_START:
		h -= FALLOFF_DEPTH * (d - FALLOFF_START) / (1.0 - FALLOFF_START)
	return h


## 基准高度 → 最终高度（海平面平移 + 海深补偿 + 山脊）✓
static func _normalize(raw: float, c: Vector2i, ns: Dictionary, lift: float, sea_gain: float) -> float:
	var h := raw + lift
	if h < 1.0:
		h = 1.0 - (1.0 - h) * sea_gain
	elif h >= RIDGE_START:
		# ★ 山脊：**阈值卡出"脊线"** ✓ 而且只在**高原之上**才叠 ✓✓
		var n_ridge: FastNoiseLite = ns["ridge"]
		var p := Hex.axial_to_pixel(c.x, c.y, 1.0)
		var rv := n_ridge.get_noise_2d(p.x, p.y)
		if rv > RIDGE_THRESHOLD:
			var up := (rv - RIDGE_THRESHOLD) / (1.0 - RIDGE_THRESHOLD)      # 0~1 ✓
			var inland := clampf((h - RIDGE_START) / 0.8, 0.0, 1.0)         # 越往高叠得越多 ✓
			h += RIDGE_AMP * up * inland
	return clampf(h, H_MIN, H_MAX)


static func _moisture_at(c: Vector2i, ns: Dictionary) -> float:
	var n_moist: FastNoiseLite = ns["moist"]
	var p := Hex.axial_to_pixel(c.x, c.y, 1.0)
	return (n_moist.get_noise_2d(p.x, p.y) + 1.0) * 0.5    # 0 ~ 1 ✓


## 取分位数（0~1）：返回值 v，使约 q 比例的格子 ≤ v ✓（排序 → 与遍历顺序无关 ✓）
static func _quantile(table: Dictionary, q: float) -> float:
	var vals: Array[float] = []
	for k in table.keys():
		vals.append(float(table[k]))
	vals.sort()
	var i := clampi(int(floor(q * float(vals.size()))), 0, vals.size() - 1)
	return vals[i]


static func _radius_of(tiles: Dictionary) -> int:
	var r := 0
	for k in tiles.keys():
		r = maxi(r, Hex.distance(TileManager.coord_of(str(k)), Vector2i.ZERO))
	return r
