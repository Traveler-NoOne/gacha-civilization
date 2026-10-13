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


## 建（或取缓存）这一局种子的气候场。`elev_fn` 传"按格取高度"的函数，
## **用 Callable 传进来是为了避免 Climate ↔ WorldGen 互相引用**（那在 GDScript 里会很难看）。
## 返回 { temp: PackedFloat32Array(MONTHS*GRID*GRID), size: int, seed: int }
static func build(world_seed: int, elev_fn: Callable) -> Dictionary:
	if _cache_seed == world_seed and not _cache.is_empty():
		return _cache
	var size := GRID
	var half := map_half()
	var temp := PackedFloat32Array()
	temp.resize(MONTHS * size * size)
	for gy in size:
		for gx in size:
			# 方格中心 → 像素坐标（场铺在地图外接矩形上）
			var px := (float(gx) + 0.5) / float(size) * 2.0 * half.x - half.x
			var py := (float(gy) + 0.5) / float(size) * 2.0 * half.y - half.y
			var c := Hex.pixel_to_axial(Vector2(px, py), 1.0)
			var e := float(elev_fn.call(c))
			# 纬度：用像素 y 模拟（-1 南极 … +1 北极）。总纲第十一节：这不是真球面
			var lat := clampf(py / maxf(1.0, half.y), -1.0, 1.0)
			var land_h := maxf(0.0, (e - SEA_E) / (1.0 - SEA_E))   # 0 = 海岸，1 = 最高峰
			var lapse := -(land_h * HEIGHT_MAX_M / 100.0) * LAPSE_PER_100M
			for m in MONTHS:
				# 季节：北半球 7 月（m=6）最热；南北反相
				var phase := cos(TAU * float(m - 6) / float(MONTHS))
				var base := lerpf(TEMP_EQUATOR, TEMP_POLE, absf(lat))
				var swing := lerpf(SWING_EQUATOR, SWING_POLE, absf(lat))
				var t := base + swing * phase * (1.0 if lat >= 0.0 else -1.0) + lapse
				temp[m * size * size + gy * size + gx] = t
	_cache = {"temp": temp, "size": size, "seed": world_seed}
	_cache_seed = world_seed
	return _cache


## 按**像素点**取某月温度（双线性）。
## 之所以要有这个入口：① 自检要能验证"采样器本身连续"；② **W3b 的降水要沿风向在像素空间行走**。
static func temp_at_pixel(p: Vector2, month: int, field: Dictionary) -> float:
	var size := int(field["size"])
	var half := map_half()
	var fx := (p.x + half.x) / (2.0 * half.x) * float(size) - 0.5
	var fy := (p.y + half.y) / (2.0 * half.y) * float(size) - 0.5
	var mm := ((month % MONTHS) + MONTHS) % MONTHS
	return _bilinear(field["temp"] as PackedFloat32Array, size, mm * size * size, fx, fy)


## 某格 × 某月的温度（双线性采样）
static func temp_at(c: Vector2i, month: int, field: Dictionary) -> float:
	return temp_at_pixel(Hex.axial_to_pixel(c.x, c.y, 1.0), month, field)


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
