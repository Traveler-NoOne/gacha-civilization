class_name Climate
extends RefCounted
## W3a：气候参数图 —— **本项目第一次引入"参数图"**（见 docs/更新指导/世界生成-W3.md 第六节）。
##
## 为什么必须有它：**温度可以按格算，但降水不行**。降水本质是"风把水汽从海上吹进来、
## 沿途一路下雨、被山挡住就下在迎风坡" —— 它必须**按一整张场、沿风向一格一格累积**，
## 逐格纯函数做不到。所以先把"场"这个架子搭起来，W3b 的降水才做得下去。
##
## 场是 **128×128 的方格**，铺在地图的**外接矩形**上；任何地块都能**双线性采样**地问它。
## ⚠️ 场**不进存档**（种子 + 配方就能重算）→ 所以 **SAVE_VERSION 不用再升**。

const GRID := 128
const MONTHS := 12

## 温度参数（摄氏度）——**按真实感设，不为平衡调**
const TEMP_EQUATOR := 28.0        ## 赤道年均
const TEMP_POLE := -22.0          ## 极地年均
const SWING_EQUATOR := 2.0        ## 赤道几乎无季节
const SWING_POLE := 22.0          ## 极地季节巨大
const HEIGHT_MAX_M := 3000.0      ## 最高峰相当于多少米
const LAPSE_PER_100M := 0.6       ## 每上升 100 米降温（干绝热那套的简化）
## ⚠️ **水线 = 海平面**：高度必须按 `(e - 水线) / (1 - 水线)` 换算，
## 不能直接拿 e 乘 —— 否则**海岸线（e=0.36）会相当于 1080 米高**，整张陆地被冻住
##（2026-10-13 实测：赤道带年均温只有 8.7℃，自检当场抓出来）。
const SEA_E := 0.36

static var _cache_seed := -1
static var _cache := {}
## W5：缓存也要看**裁切窗口**与**栅格分辨率** —— 换任何一个都是另一套数据，必须重算。
static var _cache_crop := Vector2(-99999.0, -99999.0)
static var _cache_grid := -1


## 地图的外接矩形半宽/半高（像素空间，size=1）——场的范围就是它
static func map_half() -> Vector2:
	var r := float(Consts.MAP_START_RADIUS)
	return Vector2(Hex.SQRT3 * r, 1.5 * r)


## 像素点 → 网格坐标（含 0.5 偏移，供双线性用）。
## ⚠️ W5：先加**裁切偏移**（世界坐标 → 死地图坐标），再按**死地图**的范围归一化。
static func _grid_coord(p: Vector2) -> Vector2:
	var size := float(grid_size())
	var half := dead_half()
	var q := p + _crop
	return Vector2((q.x + half.x) / (2.0 * half.x) * size - 0.5,
		(q.y + half.y) / (2.0 * half.y) * size - 0.5)


## **参考步长**：当前默认配置（`DEAD_SCALE` + `FIELD_GRID`）下一个栅格代表多少像素。
## 降雨/补水那几个常数就是按**它**调出来的 —— 所以换分辨率时要按"实际步长 / 参考步长"缩放，
## 才能做到"**每物理距离**下多少雨"而不是"每格下多少"（2026-10-13 修的尺度依赖，实测 2.18 倍）。
static func ref_step_px() -> float:
	return 2.0 * map_half().x * DEAD_SCALE / float(FIELD_GRID)


## ===========================================================================
## W3b：降水
##   做法是**推出来的**、不是画上去的：风把水汽从海上吹进来 → 经过陆地就下掉一些 →
##   **爬坡（迎风坡）下得更多** → 翻过山脊之后水汽已经没了 → **背风侧干旱（雨影）**。
##   ⚠️ 只做**东西向**推进（风带本身带南北倾斜，但推进时忽略南北分量）——
##   代价是"南北走向的山"才有明显雨影；够 W3b 用，W3c/将来可补。
## ===========================================================================
const MOIST_START := 0.55         ## 从图外进来的空气初始含水量
const OCEAN_RECHARGE := 0.10      ## 每走一格海面补充多少
const RAIN_BASE := 0.008          ## 平地每格下掉多少（**很小**：空气要能吹进内陆）
const RAIN_ORO := 0.35            ## **迎风爬坡**的降雨系数（雨影强弱主要看它）
const COLD_DRY_C := 5.0           ## 低于这个温度，空气含水能力开始往下掉
## ⚠️ 归一化参考**不再手调**，改成**按场自动定**（见 build 里取"年均降水的 85 分位"）。
## 第一版手调 0.28 时全图均值只有 0.015 —— 因为每格降雨给太大，空气出海岸十几格就下光了。
const RAIN_REF_FALLBACK := 0.05


## 风向（像素空间：+x 向东、+y 向南）。按纬度带：
##   |纬度| < 0.30 → **信风**（由东向西）｜0.30 ~ 0.65 → **西风**（由西向东）｜更外 → **极地东风**
static func wind_at(lat: float) -> Vector2:
	var a := absf(lat)
	if a < 0.30:
		return Vector2(-1.0, 0.25 * signf(lat)).normalized()
	if a < 0.65:
		return Vector2(1.0, -0.25 * signf(lat)).normalized()
	return Vector2(-1.0, 0.2 * signf(lat)).normalized()


## ===========================================================================
## W5：**死地图（原型地形图）+ 裁切窗口**
##   用户 2026-10-13 的比喻："**地形图相当于七大洲四大洋俱全的完整世界**，
##   而裁切下来的游戏地图相当于**只剩下一两个洲、或者干脆就是半个洲**，
##   大洋也只有靠近海岸线的那部分；**或者是某个大洋上的群岛**。"
##   → 所以两者的**比例差距要大**（不是 1.5 倍这种"半个地球"），默认取 **4 倍**。
##
## ⚠️ **关键：分辨率与比例必须解耦**（否则一放大就卡）
##   地形（高程/板块）是**纯函数**，任何坐标都能直接算 → **不需要**跟着死地图放大；
##   只有**降水**必须在一张栅格上沿风向推进。
##   所以：`FIELD_GRID` 固定（只管成本），`DEAD_SCALE` 只管"原型世界多大"。
##   代价：死地图越大，**气候在游戏地图里的采样越粗**（每格覆盖更大范围）。
##   将来 W6 可以把它做成"气候质量档"。
## ===========================================================================
const DEAD_SCALE := 4.0
## 气候栅格的分辨率（固定，不随 DEAD_SCALE 变）——**这是生成耗时的唯一旋钮**。
## 160² 时约 2.5 秒；128² 约 1.5 秒（细一点更准，但开新游戏更久）。
## 气候栅格的分辨率（固定，不随 DEAD_SCALE 变）。
## ⚠️ 2026-10-13 用户批评："你不用总是纠结初始化游戏的加载时长……这又不是什么轻量化的小游戏，
##    你要有一种**大体量 4X 游戏的定位心态**。" → 于是**质量优先**：160 → **384**
##   （世界里约 96 个格点宽，雨影/气候带才够细）。实测建场十几秒 —— **对这个体量可以接受**
##   （对标 4X 的读档/开局时间）。真要快，W6 做成"气候质量档"让玩家选，而不是默默砍精度。
const FIELD_GRID := 384

## 当前裁切窗口的中心（死地图坐标，像素空间 size=1）。**Vector2.ZERO = 不裁（= 现状）**。
static var _crop := Vector2.ZERO


static func set_crop(v: Vector2) -> void:
	_crop = v


static func get_crop() -> Vector2:
	return _crop


## 死地图的半宽/半高（= 地图外接矩形 × `DEAD_SCALE`）
static func dead_half() -> Vector2:
	return map_half() * DEAD_SCALE


## 气候栅格的分辨率（**固定**，不随 DEAD_SCALE 变 —— 见上面"解耦"的说明）
## 气候栅格的分辨率**可以在运行时改**：
##   ① 自检要验"尺度不变性"（一个进程里必须能跑多个分辨率才算得出来）；
##   ② 这也是将来 W6「气候质量档」的挂钩。默认仍是 FIELD_GRID。
static var _field_grid := FIELD_GRID


static func set_field_grid(n: int) -> void:
	_field_grid = maxi(32, n)


static func grid_size() -> int:
	return _field_grid


## 建（或取缓存）这一局种子的气候场。`elev_fn` 传"按格取高度"的函数，
## **用 Callable 传进来是为了避免 Climate ↔ WorldGen 互相引用**（那在 GDScript 里会很难看）。
## 返回 { temp: PackedFloat32Array(MONTHS*size*size), size: int, seed: int, rain_ref: float }
static func build(world_seed: int, elev_fn: Callable) -> Dictionary:
	if _cache_seed == world_seed and _cache_crop == _crop and _cache_grid == _field_grid \
			and not _cache.is_empty():
		return _cache
	var size := grid_size()
	var half := dead_half()
	var n2 := size * size
	# ---- 先按格取一遍高度（温度和降水都要用，只取一次）----
	# ⚠️ **不减去裁切偏移**：死地图 = **原本的完整地球**，这一格的地形就是"地球上那一处"的地形。
	#   世界取用时再加上偏移去采样（见 `_grid_coord`）→ 于是**地形也来自被裁的那片区域**
	#   （我一开始这里减了偏移，结果"地形与裁切无关、只有气候变" —— 那就不是"裁一块地球碎片"了）。
	var heights := PackedFloat32Array()
	heights.resize(n2)
	for gy in size:
		for gx in size:
			var px := (float(gx) + 0.5) / float(size) * 2.0 * half.x - half.x
			var py := (float(gy) + 0.5) / float(size) * 2.0 * half.y - half.y
			heights[gy * size + gx] = float(elev_fn.call(Hex.pixel_to_axial(Vector2(px, py), 1.0)))
	# ---- 温度：纬度梯度 × 12 个月 + 海拔递减 ----
	# ⚠️ 2026-10-13 **按用户的剧情设定**：纬度按**死地图（= 原本的完整地球）**算，**不按世界自己算**。
	#   剧情：原本是完整的地球 + 前文明；**华从冷冻仓出来时只剩残破的世界**，飘零在量子之海中——
	#   大部分土地在坠入量子之海时、以及之后丢失了。所以**游戏里的世界只是原本地球的一小块碎片**，
	#   **"一块世界不冷暖俱全"是设定要求，不是缺陷**：裁到赤道附近就是热带碎片、裁到高纬就是寒带碎片。
	#   （我曾因为"世界内温差变小 + 沙漠变多"把它改回"冷暖俱全"，用户指出这与剧情矛盾 → 改回来。）
	var temp := PackedFloat32Array()
	temp.resize(MONTHS * n2)
	for gy in size:
		var py2 := (float(gy) + 0.5) / float(size) * 2.0 * half.y - half.y
		var lat := clampf(py2 / maxf(1.0, half.y), -1.0, 1.0)
		for gx in size:
			var h := heights[gy * size + gx]
			var land_h := maxf(0.0, (h - SEA_E) / (1.0 - SEA_E))
			var lapse := -(land_h * HEIGHT_MAX_M / 100.0) * LAPSE_PER_100M
			for m in MONTHS:
				var phase := cos(TAU * float(m - 6) / float(MONTHS))
				var base := lerpf(TEMP_EQUATOR, TEMP_POLE, absf(lat))
				var swing := lerpf(SWING_EQUATOR, SWING_POLE, absf(lat))
				var t := base + swing * phase * (1.0 if lat >= 0.0 else -1.0) + lapse
				temp[m * n2 + gy * size + gx] = t
	# ---- 降水：沿风向逐行推进水汽 ----
	# ★ 尺度修正（2026-10-13）：本配置一个栅格代表 `step_px` 像素；降雨/补水都按
	#   `kstep = step_px / 参考步长` 缩放 → 等价于"**每物理距离**下多少雨"，
	#   于是**换分辨率时同一个物理点的降水稳定**（修前实测漂 2.18 倍）。
	#   默认配置下 kstep = 1 → **数值与修前完全一致**（视觉零回归）。
	var step_px := 2.0 * half.x / float(size)
	var kstep := step_px / ref_step_px()
	var precip := PackedFloat32Array()
	precip.resize(MONTHS * n2)
	for m in MONTHS:
		var off := m * n2
		for gy in size:
			var py3 := (float(gy) + 0.5) / float(size) * 2.0 * half.y - half.y
			var lat3 := clampf(py3 / maxf(1.0, half.y), -1.0, 1.0)
			var eastward := wind_at(lat3).x > 0.0
			var moist := MOIST_START
			var prev_h := SEA_E        # 图外的上风侧当作海面
			for i in size:
				var gx := i if eastward else size - 1 - i
				var idx := gy * size + gx
				var h := heights[idx]
				if h < SEA_E:
					# ⚠️ 2026-10-13：这里**试过**改成"指数趋近饱和"（`+(1-m)*r`），
					#    它的数学更漂亮、也确实能压掉一点尺度残差 —— **但它改了模型**：
					#    会挪动 `rain_ref` → 归一化湿度整体上移 → **草原被挤到 0 格**
					#    （用户明确要"草原必须看得见"）。
					#    → 按"改风格要单独决策"的口径**退回原式**，只保留 `* kstep` 这个**纯一致性**折算。
					moist = minf(1.0, moist + OCEAN_RECHARGE * kstep)
				else:
					var climb := maxf(0.0, h - prev_h)
					var cold := clampf((temp[off + idx] + COLD_DRY_C) / 25.0, 0.0, 1.0)
					# ⚠️ 只有**平地那一项**乘 kstep：`climb`（这一格的爬升高度）**本身正比于步长**，
					#    所以 `moist × ORO × climb` 已经是"每物理距离"的雨量 ——
					#    再乘一次 kstep 就是重复折算（第一版修法就这么错的，实测比值反而从 2.18 涨到 2.60）。
					var rain := moist * (RAIN_BASE * kstep + RAIN_ORO * climb) * cold
					# ★ 存进场的必须是**单位距离的雨量**（= 每格雨量 ÷ kstep），不能是"每格雨量"：
					#   后者在粗网格上天生就大 kstep 倍（一格代表更长的距离）→
					#   同一个物理点换个分辨率读数就变（实测**平坦地形**上差 **2.99 倍** —— 2026-10-13 这么查出来的：
					#   把速率按距离折算**还不够**，存的时候也得折算）。
					#   ⚠️ 默认配置下 kstep = 1 → 数值与修前**完全一致**（视觉零回归）。
					precip[off + idx] = rain / maxf(kstep, 0.0001)
					moist = maxf(0.0, moist - rain)
				prev_h = h
	# ---- 归一化参考：按场自动定（年均降水的 85 分位）----
	var annual := PackedFloat32Array()
	annual.resize(n2)
	for i in n2:
		var acc := 0.0
		for mm in MONTHS:
			acc += precip[mm * n2 + i]
		annual[i] = acc / float(MONTHS)
	# ---- 归一化参考：按**游戏地图那一块**的分布定（**不是**整张死地图）----
	# ⚠️ 2026-10-13：原来取整张死地图的 85 分位。死地图比游戏图大 **16 倍面积**、
	#   分布也完全不同 → 裁下来的碎片若比周围湿，归一化值就**整体顶到上限** →
	#   干/中/湿三档被压平 → **草原和沙漠直接消失**（实测地物只剩 2 种、seed_check 报红）。
	#   → 改成只统计"**游戏地图所占的那一小块**"（死地图中央 1/DEAD_SCALE 的方格范围）。
	var lo := int(float(size) * (0.5 - 0.5 / DEAD_SCALE))
	var hi := int(float(size) * (0.5 + 0.5 / DEAD_SCALE))
	var window_vals: Array = []
	for gy_r in range(lo, hi):
		for gx_r in range(lo, hi):
			window_vals.append(annual[gy_r * size + gx_r])
	window_vals.sort()
	var rain_ref := maxf(0.005, float(window_vals[int(float(window_vals.size()) * 0.85)]))
	_cache = {"temp": temp, "precip": precip, "heights": heights, "size": size,
		"seed": world_seed, "rain_ref": rain_ref, "crop": _crop}
	_cache_seed = world_seed
	_cache_crop = _crop
	_cache_grid = _field_grid
	return _cache


## 按**像素点**取某月温度（双线性）。
## 之所以要有这个入口：① 自检要能验证"采样器本身连续"；② W3b 的降水也在像素空间推进。
static func temp_at_pixel(p: Vector2, month: int, field: Dictionary) -> float:
	var g := _grid_coord(p)
	var size := int(field["size"])
	var mm := ((month % MONTHS) + MONTHS) % MONTHS
	return _bilinear(field["temp"] as PackedFloat32Array, size, mm * size * size, g.x, g.y)


## 某格 × 某月的温度
static func temp_at(c: Vector2i, month: int, field: Dictionary) -> float:
	return temp_at_pixel(Hex.axial_to_pixel(c.x, c.y, 1.0), month, field)


## 按**像素点**取某月降水（原始量，未归一化）。
## ⚠️ 之所以必须要有这个入口：自检要验"**同一物理点**在不同窗口/分辨率下稳不稳"。
##   若经过**六边形坐标**（`precip_at` 的入参）取整，"同一点"就落不到同一点 ——
##   2026-10-13 第一版实验就栽在这上面（同一物理点读出 0.86~2.56 倍差异，全是取整artifact）。
static func precip_at_pixel(p: Vector2, month: int, field: Dictionary) -> float:
	var g := _grid_coord(p)
	var size := int(field["size"])
	var mm := ((month % MONTHS) + MONTHS) % MONTHS
	return _bilinear(field["precip"] as PackedFloat32Array, size, mm * size * size, g.x, g.y)


## 某格 × 某月的**降水**（原始量，未归一化）
static func precip_at(c: Vector2i, month: int, field: Dictionary) -> float:
	return precip_at_pixel(Hex.axial_to_pixel(c.x, c.y, 1.0), month, field)


## **年均降水**归一化到 0~1 —— 这才是 `world_gen.moisture_of()` 要的数
## （归一化参考取场自带的 85 分位，见 build —— 这样每个种子都有合适的干湿反差）
static func annual_precip_at(c: Vector2i, field: Dictionary) -> float:
	var s := 0.0
	for m in MONTHS:
		s += precip_at(c, m, field)
	var ref := maxf(0.001, float(field.get("rain_ref", RAIN_REF_FALLBACK)))
	return clampf(s / float(MONTHS) / ref, 0.0, 1.0)


## 年平均温度（W3a 先用它；W3c 会换成用"最冷月/最热月 + 降水"的完整柯本判据）
static func annual_temp_at(c: Vector2i, field: Dictionary) -> float:
	var s := 0.0
	for m in MONTHS:
		s += temp_at(c, m, field)
	return s / float(MONTHS)


## 最冷月 / 最热月的温度（柯本要用；W3a 先备好，W3c 直接用）
static func month_range(c: Vector2i, field: Dictionary) -> Vector2:
	var lo := 999.0
	var hi := -999.0
	for m in MONTHS:
		var t := temp_at(c, m, field)
		lo = minf(lo, t)
		hi = maxf(hi, t)
	return Vector2(lo, hi)


## ===========================================================================
## W5：**按水陆比挑裁切窗口**（用户 2026-10-13："裁切的时候只要满足水陆比例就足够了，
## 无论冷暖是否俱全，都是可接受的"）
##   → 于是"挑窗口"的**唯一硬指标**是**水陆比例**；气候全不全**不参与筛选**。
## ===========================================================================
## 合格区间（计划里定的松口径：25%~75% 都算合格），越接近 50:50 越优先。
const LAND_MIN_OK := 0.25
const LAND_MAX_OK := 0.75
## 候选窗口的偏移步长（像素）。步长越小越准、越慢 ——
## 每个候选都要在世界范围内取样一遍（约 1400 格 × 取一次高度），所以别调太小：
## 9.0 时是 13×13=169 个候选（约 23 万次取高度）→ 实测偏慢；**18.0 → 7×7=49 个候选**，够用。
const CROP_STEP := 27.0


## 某个裁切窗口下，这一块世界的**陆地占比**。
## ⚠️ 用**粗格点阵**取样（不是逐格扫全世界）——`pick_crop` 要试上百个候选窗口，
##    逐格扫会慢到不可用（实测：4 倍死地图 × 逐格扫 = 十几秒）。
static func land_fraction(crop: Vector2, elev_fn: Callable) -> float:
	var half := map_half()
	var n := 17                      # 17×17 = 289 个取样点，够判水陆比
	var land := 0
	var total := 0
	for iy in n:
		for ix in n:
			var p := Vector2(
				(float(ix) + 0.5) / float(n) * 2.0 * half.x - half.x,
				(float(iy) + 0.5) / float(n) * 2.0 * half.y - half.y)
			var c := Hex.pixel_to_axial(p, 1.0)
			if Hex.distance(c, Vector2i.ZERO) > Consts.MAP_START_RADIUS:
				continue             # 地图是圆盘：外接矩形的四角不算
			total += 1
			if float(elev_fn.call(Hex.pixel_to_axial(p + crop, 1.0))) >= SEA_E:
				land += 1
	if total == 0:
		return 0.0
	return float(land) / float(total)


## 在死地图上扫一圈候选窗口，挑一个**水陆比最接近 50:50**的（都在合格区间外时退回最接近的）。
## 全程确定（候选顺序固定、并列取先遇到的）→ 同种子每次挑到同一个窗口。
static func pick_crop(elev_fn: Callable) -> Vector2:
	var best := Vector2.ZERO
	var best_score := 9.9
	var half := dead_half()
	var n := int(floor(half.x / CROP_STEP))
	for iy in range(-n, n + 1):
		for ix in range(-n, n + 1):
			var cand := Vector2(float(ix) * CROP_STEP, float(iy) * CROP_STEP)
			var lf := land_fraction(cand, elev_fn)
			if lf < LAND_MIN_OK or lf > LAND_MAX_OK:
				continue                      # 不合格：直接跳过（"只要满足水陆比例就足够了"）
			var score := absf(lf - 0.5)
			if score < best_score - 0.000001:
				best_score = score
				best = cand
	return best



## ===========================================================================
## W3c：柯本气候分类
##   柯本要的是**绝对量**（年降水毫米 + 最冷月/最热月温度），所以先把降水换成毫米。
## ===========================================================================
## 降水标尺：场里的"原始降水"→ **毫米/年**。
## 标定依据：raw 年均的 85 分位约 0.003，让它落在 ~1600mm（湿润区），
## 于是沙漠（<250mm）／草原（~500mm）／雨林（>2000mm）都能落进合理区间。
## ⚠️ 这是**近似标尺**（不是真实物理量），只为让柯本阈值有意义；可逆。
const PRECIP_MM_PER_RAW := 530000.0
## ⚠️ 2026-10-13 试过把它放大一倍以压沙漠占比（41%），**完全没效果**（572 格 → 572 格）——
## 说明"沙漠太多"的根因**不是标尺**，而是**降水分布太偏**：空气在第一个迎风坡上就把水汽放光，
## 内陆几乎零降水 → 大片内陆被判成沙漠。真正的修法是 W3b 的水汽模型（例如调大 `RAIN_BASE`，
## 让空气**沿途慢慢下**而不是一次下光），不是动这里。


## 原始年均降水（未归一化）
static func annual_precip_raw_at(c: Vector2i, field: Dictionary) -> float:
	var s := 0.0
	for m in MONTHS:
		s += precip_at(c, m, field)
	return s / float(MONTHS)


## 年降水（毫米）
static func annual_precip_mm(c: Vector2i, field: Dictionary) -> float:
	return annual_precip_raw_at(c, field) * PRECIP_MM_PER_RAW


## 最干那个月的降水（毫米）—— 柯本用它分 Af/Am/Aw 与 f/s/w
static func driest_month_mm(c: Vector2i, field: Dictionary) -> float:
	var lo := 999999.0
	for m in MONTHS:
		lo = minf(lo, precip_at(c, m, field) * PRECIP_MM_PER_RAW)
	return lo


## 柯本气候分类（**简化版**，够本作用）：E 极地 / B 干旱 / A 热带 / C 温带 / D 大陆，
## 再按干湿给一个子字母。返回 2 个字符的类别码。
##   判据顺序照柯本原意：**先看最热月**（够不够暖）→ 再看**干湿**（够不够湿）→ 最后看**最冷月**（冷不冷）。
static func koppen_at(c: Vector2i, field: Dictionary) -> String:
	var mm := annual_precip_mm(c, field)
	var rng := month_range(c, field)          # Vector2(最冷月, 最热月)
	var tcold := rng.x
	var twarm := rng.y
	var tmean := annual_temp_at(c, field)
	# ---- E 极地：最热月都不足 10℃ ----
	if twarm < 10.0:
		return "EF" if twarm <= 0.0 else "ET"
	# ---- B 干旱：降水低于"随温度走的阈值"（柯本-桑斯韦特那套的简化）----
	# ⚠️ 2026-10-13：沙漠/草原的分界从"阈值的一半"放宽到 **0.35** ——
	#   原式下**草原带几乎不存在**（实测 BS=0 格）。用户明确要"草原必须看得见"，
	#   而这是游戏不是气候学研究，所以把草原带放宽，让"沙漠→草原→森林"的过渡真的出现。
	var thr := 20.0 * tmean + 140.0
	if mm < thr:
		return "BW" if mm < thr * 0.35 else "BS"
	# ---- A 热带：最冷月也 ≥ 18℃ ----
	if tcold >= 18.0:
		if driest_month_mm(c, field) >= 60.0:
			return "Af"
		if mm >= 2500.0:
			return "Am"
		return "Aw"
	# ---- C 温带 / D 大陆：看最冷月是否到 0℃ 以下 ----
	var head := "D" if tcold < 0.0 else "C"
	var driest := driest_month_mm(c, field)
	if driest < 30.0:
		# 干季在冬天还是夏天？用"最热月降水 vs 最冷月降水"粗判（够用）
		var pw := precip_at(c, 6, field) * PRECIP_MM_PER_RAW
		var pc := precip_at(c, 0, field) * PRECIP_MM_PER_RAW
		return head + ("s" if pw < pc else "w")
	return head + "f"


static func _bilinear(a: PackedFloat32Array, size: int, off: int, fx: float, fy: float) -> float:
	var x0 := int(floor(fx))
	var y0 := int(floor(fy))
	var tx := fx - float(x0)
	var ty := fy - float(y0)
	var xa := mini(size - 1, maxi(0, x0))
	var ya := mini(size - 1, maxi(0, y0))
	var xb := mini(size - 1, maxi(0, x0 + 1))
	var yb := mini(size - 1, maxi(0, y0 + 1))
	var v00 := a[off + ya * size + xa]
	var v10 := a[off + ya * size + xb]
	var v01 := a[off + yb * size + xa]
	var v11 := a[off + yb * size + xb]
	return lerpf(lerpf(v00, v10, tx), lerpf(v01, v11, tx), ty)
