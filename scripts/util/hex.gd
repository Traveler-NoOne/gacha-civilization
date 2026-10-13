class_name Hex
extends RefCounted
## 尖顶(pointy-top)六边形轴向坐标工具。
## 轴向坐标 q/r，像素坐标 y 轴向下（Godot 2D 约定）。

const SQRT3 := 1.7320508075688772

## ⚠️ 画"地块的边"时（河流 `river_edge` / 水陆分界 `water_edge`）**必须照下面这张对照表**——
## 这是 W1 定下的「方向索引规范」，搞错就会**把河画到错误的边上**（肉眼一看就不对、代码里查半天那种）。
##
##     边 k（第 k 个顶点 → 第 k+1 个顶点）  对应邻居方向  DIRECTIONS[(−k) mod 6]
##       k=0 → 0    k=1 → 5    k=2 → 4    k=3 → 3    k=4 → 2    k=5 → 1
##
## 依据：`corners()` 的顶点角是 `60°·i − 30°`，逐边取中点当外法线、与各方向 `axial_to_pixel()` 的像素角比对，
## **6 条边全部 0.00° 吻合**（2026-10-13 数值验算）。共享边只由一个主人记录：**owner = 两端坐标字典序较小者**，
## 查另一侧用 `(d + 3) % 6`（见 docs/更新指导/世界生成-过程模拟.md 第 3.3 节）。

## 六个邻居方向（轴向坐标）。**反向 = `(i + 3) % 6`**
const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]

## qr坐标转像素坐标
static func axial_to_pixel(q: int, r: int, size: float) -> Vector2:
	var x := size * SQRT3 * (float(q) + float(r) * 0.5)
	var y := size * 1.5 * float(r)
	return Vector2(x, y)

## 像素坐标转qr坐标
static func pixel_to_axial(pos: Vector2, size: float) -> Vector2i:
	var q := (SQRT3 / 3.0 * pos.x - pos.y / 3.0) / size
	var r := (2.0 / 3.0 * pos.y) / size
	return axial_round(q, r)


static func axial_round(qf: float, rf: float) -> Vector2i:
	# 立方坐标舍入
	var xf := qf
	var zf := rf
	var yf := -xf - zf
	var rx := roundi(xf)
	var ry := roundi(yf)
	var rz := roundi(zf)
	var dx := absf(float(rx) - xf)
	var dy := absf(float(ry) - yf)
	var dz := absf(float(rz) - zf)
	if dx > dy and dx > dz:
		rx = -ry - rz
	elif dy > dz:
		ry = -rx - rz
	else:
		rz = -rx - ry
	return Vector2i(rx, rz)


static func distance(a: Vector2i, b: Vector2i) -> int:
	var dq := a.x - b.x
	var dr := a.y - b.y
	return int((absi(dq) + absi(dq + dr) + absi(dr)) / 2)


static func neighbors(c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in DIRECTIONS:
		out.append(c + d)
	return out


## 半径 rad 的六边形范围内全部坐标（含中心）
static func spiral(radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for q in range(-radius, radius + 1):
		var r1: int = maxi(-radius, -q - radius)
		var r2: int = mini(radius, -q + radius)
		for r in range(r1, r2 + 1):
			out.append(Vector2i(q, r))
	return out


## 六边形的 6 个顶点（尖顶朝上）
static func corners(center: Vector2, size: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var ang := deg_to_rad(60.0 * float(i) - 30.0)
		pts.append(center + Vector2(cos(ang), sin(ang)) * size)
	return pts


## 用于确定性的伪随机：把坐标混成一个 0..1 的数
static func hash01(c: Vector2i, salt: int = 0) -> float:
	var h := int(c.x) * 374761393 + int(c.y) * 668265263 + salt * 2166136261
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(absi(h) % 1000003) / 1000003.0
