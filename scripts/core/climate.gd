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


## 地图的外接矩形半宽/半高（像素空间，size=1）——场的范围就是它
static func map_half() -> Vector2:
	var r := float(Consts.MAP_START_RADIUS)
	return Vector2(Hex.SQRT3 * r, 1.5 * r)


## 像素点 → 网格坐标（含 0.5 偏移，供双线性用）
static func _grid_coord(p: Vector2) -> Vector2:
	var size := float(GRID)
	var half := map_half()
	return Vector2((p.x + half.x) / (2.0 * half.x) * size - 0.5,
		(p.y + half.y) / (2.0 * half.y) * size - 0.5)


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


## 建（或取缓存）这一局种子的气候场。`elev_fn` 传"按格取高度"的函数，
## **用 Callable 传进来是为了避免 Climate ↔ WorldGen 互相引用**（那在 GDScript 里会很难看）。
## 返回 { temp: PackedFloat32Array(MONTHS*GRID*GRID), size: int, seed: int }
static func build(world_seed: int, elev_fn: Callable) -> Dictionary:
	if _cache_seed == world_seed and not _cache.is_empty():
		return _cache
	var size := GRID
	var half := map_half()
	var n2 := size * size
	# ---- 先按格取一遍高度（温度和降水都要用，只取一次）----
	var heights := PackedFloat32Array()
	heights.resize(n2)
	for gy in size:
		for gx in size:
			var px := (float(gx) + 0.5) / float(size) * 2.0 * half.x - half.x
			var py := (float(gy) + 0.5) / float(size) * 2.0 * half.y - half.y
			heights[gy * size + gx] = float(elev_fn.call(Hex.pixel_to_axial(Vector2(px, py), 1.0)))
	# ---- 温度：纬度梯度 × 12 个月 + 海拔递减 ----
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
					moist = minf(1.0, moist + OCEAN_RECHARGE)
				else:
					var climb := maxf(0.0, h - prev_h)
					var cold := clampf((temp[off + idx] + COLD_DRY_C) / 25.0, 0.0, 1.0)
					var rain := moist * (RAIN_BASE + RAIN_ORO * climb) * cold
					precip[off + idx] = rain
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
	var sorted := annual.duplicate()
	sorted.sort()
	var rain_ref := maxf(0.005, sorted[int(float(n2) * 0.85)])
	_cache = {"temp": temp, "precip": precip, "heights": heights, "size": size,
		"seed": world_seed, "rain_ref": rain_ref}
	_cache_seed = world_seed
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


## 某格 × 某月的**降水**（原始量，未归一化）
static func precip_at(c: Vector2i, month: int, field: Dictionary) -> float:
	var g := _grid_coord(Hex.axial_to_pixel(c.x, c.y, 1.0))
	var size := int(field["size"])
	var mm := ((month % MONTHS) + MONTHS) % MONTHS
	return _bilinear(field["precip"] as PackedFloat32Array, size, mm * size * size, g.x, g.y)


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
## W3c：柯本气候分类
##   柯本要的是**绝对量**（年降水毫米 + 最冷月/最热月温度），所以先把降水换成毫米。
## ===========================================================================
## 降水标尺：场里的"原始降水"→ **毫米/年**。
## 标定依据：raw 年均的 85 分位约 0.003，让它落在 ~1600mm（湿润区），
## 于是沙漠（<250mm）／草原（~500mm）／雨林（>2000mm）都能落进合理区间。
## ⚠️ 这是**近似标尺**（不是真实物理量），只为让柯本阈值有意义；可逆。
const PRECIP_MM_PER_RAW := 530000.0


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
	var thr := 20.0 * tmean + 140.0
	if mm < thr:
		return "BW" if mm < thr * 0.5 else "BS"
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
