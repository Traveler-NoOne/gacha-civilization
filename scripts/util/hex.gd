class_name Hex
extends RefCounted
## 尖顶(pointy-top)六边形轴向坐标工具。
## 轴向坐标 q/r，像素坐标 y 轴向下（Godot 2D 约定）。

const SQRT3 := 1.7320508075688772

## 六个邻居方向（轴向坐标）
const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]


static func axial_to_pixel(q: int, r: int, size: float) -> Vector2:
	var x := size * SQRT3 * (float(q) + float(r) * 0.5)
	var y := size * 1.5 * float(r)
	return Vector2(x, y)


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

## 计算距离
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
