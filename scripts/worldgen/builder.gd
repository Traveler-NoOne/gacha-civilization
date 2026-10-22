class_name WorldgenBuilder
extends RefCounted
## 世界生成**总控**（噪声版）✓
##
## 做法（经典骨架 ＋ 三处修正 ✓）：
##   ① **大结构**：fBm 噪声 —— 决定**海陆**和**高原 / 丘陵**的大块形状 ✓
##   ② **山脊**：另一路 **RIDGED（脊状）噪声** —— 它的正值**天生就是狭长的脊** ✓✓
##      只叠在**内陆高地**上 ✓（平原和海洋不加 ✓）→ 山是"狭长的脊" ✓ 大片高地留作高原 ✓
##   ③ 湿度：第三路低频噪声 ✓
##   ④ 从地图中心向外衰减 → 四周必成海 ✓
##   ★ ⑤ **海平面按"目标陆地占比"定**（分位数）✓ 不再手调水线 ✓
##   ★ ⑥ **山脉瘦身**：太胖的山团降级成高原 / 山地（`Peaks`）✓
##
## 高度标尺 = **0~10**：0 = 海沟底 ✓ **1.0 = 海平面** ✓ 5.0 = 珠峰 ✓ 10.0 = 大气层顶 ✓
## ⚠️ **纯函数** ✓：地形 = f(坐标, 种子) ✓ 同种子同地图 ✓
## ⚠️ 分位数依赖"整张图有哪些格子" ✗ → 这份生成器目前**只做一次性生成**（扩图还没接它 ✗）

## ---- 大结构 / 海陆 ----
## 噪声频率 = 这个数 ÷ 半径 ✓（**跟着地图大小走** ✓ 改半径不用改这里 ✓）
## 越低地形越完整和平缓，越高地形越破碎和陡峭。
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
## ⚠️ 如果图上出现"山长在该是谷的地方"✗ → 把下面判断里的 `rv > RIDGE_THRESHOLD`
##    改成 `rv < -RIDGE_THRESHOLD`（ridged 噪声的"脊"也可能在负值侧 ✓ 看实际效果调 ✓）

## ---- 高度上下限（**刻意不碰 0 和 5.0** ✓）----
const H_MIN := 0.22
const H_MAX := 4.90
## 边缘衰减：半径的多少之后开始下沉 ✓ 到最外圈下沉多少 ✓
const FALLOFF_START := 0.62
const FALLOFF_DEPTH := 4.0


## 生成一整个世界，填进 `state` ✓（写 `tiles` ＋ `capital` ✓）
static func generate(state: Dictionary) -> void:
	var seed := int(state["seed"]) # 读取种子
	var radius := Consts.MAP_START_RADIUS # 地图大小

	# ① 大结构：fBm ✓ 决定海陆 / 高原 / 丘陵的大块形状 ✓
	var n_base := FastNoiseLite.new()
	n_base.seed = seed
	n_base.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n_base.frequency = FREQ_BASE / float(radius)
	n_base.fractal_type = FastNoiseLite.FRACTAL_FBM
	n_base.fractal_octaves = 4      # 4 层够了 ✓ 层数越多海岸线越碎 ✗
	n_base.fractal_gain = 0.5

	# ② 山脊：**脊状噪声** ✓ 它的正值天然是**狭长的脊** ✓✓（用 fBm 做山必然成团 ✗）
	var n_ridge := FastNoiseLite.new()
	n_ridge.seed = seed + 5551
	n_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n_ridge.frequency = FREQ_RIDGE / float(radius)
	n_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	# ⚠️ **单层** ✓ —— 多层 ridged 叠加会把"线状的脊"糊成"片" ✗（这也是山成团的原因之一 ✓）
	n_ridge.fractal_octaves = 1
	n_ridge.fractal_gain = 0.5

	# ③ 湿度：另一路低频噪声 ✓（与高度无关 ✓ 以后再考虑"地形雨"之类的耦合 ✓）
	var n_moist := FastNoiseLite.new()
	n_moist.seed = seed + 9871
	n_moist.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n_moist.frequency = 0.8 / float(radius)
	n_moist.fractal_type = FastNoiseLite.FRACTAL_FBM
	n_moist.fractal_octaves = 3

	# 【第 1 步】先算**基准高度**（1.0 = 旧海平面）＋ 湿度；山脊留到定完海平面再加 ✓
	var cells := Hex.spiral(radius)
	var raw := {}
	var moist := {}
	for c: Vector2i in cells:
		# 用**像素坐标**取噪声 ✓ —— 地形只跟坐标和种子有关 ✓
		var p := Hex.axial_to_pixel(c.x, c.y, 1.0)
		var dv := n_base.get_noise_2d(p.x, p.y) - SEA_NOISE
		var h := 1.0
		if dv < 0.0:
			# 水下：**放慢** ✓ → 浅海带变宽 ✓（不然一离开水线就掉到 clamp 下限、全是深海 ✗）
			h = 1.0 + dv * SEA_SCALE
		else:
			# 陆上：**幂次压缩** ✓ → 只有极端高的才成山 ✓ 大片中高地留在高原 / 丘陵 ✓✓
			h = 1.0 + pow(dv, LAND_POW) * LAND_SCALE
		# ④ 从中心向外衰减 → 四周必成海 ✓
		var d := float(Hex.distance(c, Vector2i.ZERO)) / float(radius)
		if d > FALLOFF_START:
			h -= FALLOFF_DEPTH * (d - FALLOFF_START) / (1.0 - FALLOFF_START)
		var k := TileManager.key_of(c)
		raw[k] = h
		moist[k] = (n_moist.get_noise_2d(p.x, p.y) + 1.0) * 0.5    # 0 ~ 1 ✓

	# 【第 2 步】定海平面：取分位数 → 恰好 LAND_RATIO 的格子在水面之上 ✓（同种子同结果 ✓ 不用手调阈值 ✓）
	var lift := 1.0 - _quantile(raw, 1.0 - LAND_RATIO)

	# 【第 3 步】海深补偿：陆地一抬，海水就浅了 ✗ → 把水下那一段按 SEA_DEPTH 拉回去 ✓（海岸线不动 ✓）
	var lowest := 1.0
	for k2 in raw.keys():
		lowest = minf(lowest, float(raw[k2]) + lift)
	var sea_gain := 1.0
	if lowest < 0.999:
		sea_gain = clampf(SEA_DEPTH / (1.0 - lowest), 1.0, 3.0)

	var tiles := {}
	for c: Vector2i in cells:
		var k := TileManager.key_of(c)
		var h := float(raw[k]) + lift
		if h < 1.0:
			h = 1.0 - (1.0 - h) * sea_gain
		elif h >= RIDGE_START:
			# ★ 山脊：**阈值卡出"脊线"** ✓ 而且只在**高原之上**才叠 ✓✓
			#   → "山"是细长的一条条脊 ✓ 大片高地的身份是"高原"✓ 不会被顶成山 ✗
			var p := Hex.axial_to_pixel(c.x, c.y, 1.0)
			var rv := n_ridge.get_noise_2d(p.x, p.y)
			if rv > RIDGE_THRESHOLD:
				var up := (rv - RIDGE_THRESHOLD) / (1.0 - RIDGE_THRESHOLD)      # 0~1 ✓
				var inland := clampf((h - RIDGE_START) / 0.8, 0.0, 1.0)         # 越往高叠得越多 ✓
				h += RIDGE_AMP * up * inland
		h = clampf(h, H_MIN, H_MAX)
		tiles[k] = TileLib.make(c, seed, {"height": h, "moisture": float(moist[k])})

	# ⑤ 山脉瘦身：太胖的山团降级（靠高原的转高原、其余转山地）✓ 嫌太碎就删这一行 ✓
	Peaks.thin_mountains(tiles)

	state["tiles"] = tiles
	state["capital"] = WorldGen.choose_capital(tiles)   # 纯函数 ✓ 用 is_water ✓ 新地块照样能用 ✓


## 取分位数（0~1）：返回值 v，使约 q 比例的格子 ≤ v ✓（排序 → 与遍历顺序无关 ✓）
static func _quantile(table: Dictionary, q: float) -> float:
	var vals: Array[float] = []
	for k in table.keys():
		vals.append(float(table[k]))
	vals.sort()
	var i := clampi(int(floor(q * float(vals.size()))), 0, vals.size() - 1)
	return vals[i]
