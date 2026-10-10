class_name GeoIcon
extends Control
## 用几何多边形代替美术资源绘制的图标控件。

var kind: String = "circle"
var tint: Color = Color(0.8, 0.8, 0.9)
var filled: bool = true
var line_width: float = 2.0
var spin: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(UI.px(48), UI.px(48))


func setup(k: String, c: Color, f: bool = true) -> GeoIcon:
	kind = k
	tint = c
	filled = f
	queue_redraw()
	return self


func _draw() -> void:
	var c := size * 0.5
	var r: float = maxf(6.0, minf(size.x, size.y) * 0.42)
	_draw_shape(self, kind, c, r, tint, filled, line_width, spin)


static func _draw_shape(ci: CanvasItem, k: String, center: Vector2, radius: float,
		color: Color, fill: bool, width: float, rot: float = 0.0) -> void:
	var pts := CardDB.shape_points(k)
	var poly := PackedVector2Array()
	for p in pts:
		var v := p * radius
		if rot != 0.0:
			v = v.rotated(rot)
		poly.append(center + v)
	if fill:
		ci.draw_colored_polygon(poly, color)
		var outline := poly.duplicate()
		outline.append(poly[0])
		ci.draw_polyline(outline, color.lightened(0.5), width)
	else:
		var o := poly.duplicate()
		o.append(poly[0])
		ci.draw_polyline(o, color, width)


class Decor:
	extends Control
	## 主页面背景装饰：缓慢旋转的几何图形。
	## 作为内部类提供，避免额外的 class_name 注册。

	var _t := 0.0
	var _shapes: Array = []

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var kinds := ["triangle", "square", "hexagon", "diamond", "circle", "star"]
		var cols := [
			Color(0.24, 0.30, 0.45), Color(0.30, 0.36, 0.28), Color(0.42, 0.32, 0.24),
			Color(0.32, 0.26, 0.42), Color(0.24, 0.36, 0.40), Color(0.42, 0.36, 0.22),
		]
		for i in 14:
			var r := RandomNumberGenerator.new()
			r.seed = 900 + i * 37
			_shapes.append({
				"kind": kinds[i % kinds.size()],
				"color": cols[i % cols.size()],
				"pos": Vector2(r.randf(), r.randf()),
				"size": 22.0 + r.randf() * 70.0,
				"rot": r.randf() * TAU,
				"speed": (r.randf() - 0.5) * 0.35,
			})
		set_process(true)

	func _process(delta: float) -> void:
		_t += delta
		for s in _shapes:
			s["rot"] = float(s["rot"]) + float(s["speed"]) * delta
		queue_redraw()

	func _draw() -> void:
		for s in _shapes:
			var p: Vector2 = Vector2(float(s["pos"].x) * size.x, float(s["pos"].y) * size.y)
			var col: Color = s["color"]
			var a := 0.20 + 0.14 * sin(_t * 0.6 + float(s["size"]))
			col.a = a
			GeoIcon._draw_shape(self, str(s["kind"]), p, float(s["size"]), col, true, 2.0, float(s["rot"]))
