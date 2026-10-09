class_name HexMapView
extends Control
## 六边形世界地图视图：绘制、平移、缩放、点击选格。
## 对应设计文档「世界」章节。

signal tile_selected(key: String)

const SIZE_BASE := 34.0
const SIZE_MIN := 20.0
const SIZE_MAX := 62.0

var hex_size := SIZE_BASE
var origin := Vector2.ZERO
var hover_key := ""
var selected_key := ""
## 可选的高亮标记：{ "q,r": Color }
var marks: Dictionary = {}
var show_axis := false

var _dragging := false
var _drag_start := Vector2.ZERO
var _origin_start := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_center_view()
	resized.connect(_on_resized)


func _on_resized() -> void:
	queue_redraw()


func center_on_axial(c: Vector2i) -> void:
	origin = size * 0.5 - Hex.axial_to_pixel(c.x, c.y, hex_size)
	queue_redraw()


func _center_view() -> void:
	center_on_axial(Vector2i.ZERO)


func axial_to_screen(c: Vector2i) -> Vector2:
	return Hex.axial_to_pixel(c.x, c.y, hex_size) + origin


func screen_to_key(p: Vector2) -> String:
	var c := Hex.pixel_to_axial(p - origin, hex_size)
	return WorldGen.key_of(c)


# ---------------------------------------------------------------------------
# 绘制
# ---------------------------------------------------------------------------
func _draw() -> void:
	if not GameState.state.has("tiles"):
		return
	var tiles: Dictionary = GameState.state["tiles"]
	var capital := WorldGen.coord_of(str(GameState.state.get("capital", "0,0")))

	# 视口裁剪：只画落在可见区域附近的六边形
	for key in tiles.keys():
		var t: Dictionary = tiles[key]
		var c := WorldGen.coord_of(key)
		var center := axial_to_screen(c)
		if center.x < -hex_size * 2.0 or center.x > size.x + hex_size * 2.0 \
				or center.y < -hex_size * 2.0 or center.y > size.y + hex_size * 2.0:
			continue
		_draw_tile(key, t, c, center, capital)

	# 可选：坐标轴标签
	if show_axis:
		_draw_axis()


func _draw_tile(key: String, t: Dictionary, c: Vector2i, center: Vector2,
		capital: Vector2i) -> void:
	var pts := Hex.corners(center, hex_size - 1.5)
	var discovered: bool = t.get("discovered", false)
	var owner: String = t.get("owner", "")

	if not discovered:
		# 迷雾：几乎不可见的深色六边形
		draw_colored_polygon(pts, Color(0.075, 0.078, 0.11, 0.85))
		var fog := pts.duplicate()
		fog.append(pts[0])
		draw_polyline(fog, Color(0.14, 0.15, 0.20, 0.7), 1.0)
		return

	# 地形底色
	var base: Color = Consts.terrain_color(str(t.get("terrain", "plain")))
	draw_colored_polygon(pts, base)
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, Color(0, 0, 0, 0.35), 1.0)

	# 资源点：中间的小几何图形
	var res: String = str(t.get("resource", ""))
	var amount := float(t.get("amount", 0.0))
	if res != "":
		var has_amount := t.has("amount")
		var r: float = hex_size * 0.24
		var tex := UIKit.get_icon(res, UIKit.Art.ICON)
		if not has_amount or amount > 0.05:
			draw_circle(center, r * 1.9, Color(0, 0, 0, 0.30))
			if tex != null:
				var s := r * 2.6
				draw_texture_rect(tex, Rect2(center - Vector2(s, s) * 0.5, Vector2(s, s)), false)
			else:
				GeoIcon._draw_shape(self, _res_kind(res), center, r, _res_color(res), true, 1.5)
		else:
			# 已耗尽
			if tex != null:
				var s2 := hex_size * 0.52
				draw_texture_rect(tex, Rect2(center - Vector2(s2, s2) * 0.5, Vector2(s2, s2)),
					false, Color(0.45, 0.45, 0.52, 0.75))
			else:
				GeoIcon._draw_shape(self, _res_kind(res), center, hex_size * 0.22,
					Color(0.4, 0.4, 0.45, 0.6), false, 1.2)

	# 建筑标记
	var bs: Array = t.get("buildings", [])
	if not bs.is_empty():
		var bx := center + Vector2(-hex_size * 0.42, hex_size * 0.42)
		for i in mini(bs.size(), 6):
			var b: Dictionary = bs[i]
			var def := GameState.find_building(str(b.get("id", "")))
			var cat: String = def.category if def != null else "工业建筑"
			var bcol := _cat_color(cat)
			var pos := bx + Vector2(float(i) * hex_size * 0.19, 0.0)
			draw_rect(Rect2(pos - Vector2(2.5, 2.5), Vector2(5, 5)), bcol, true)
			if int(b.get("workers", 0)) > 0:
				draw_circle(pos + Vector2(0, -4.5), 1.8, Color(1, 0.95, 0.6))

	# 势力边框
	if owner == "player":
		var o := pts.duplicate()
		o.append(pts[0])
		draw_polyline(o, Color(0.55, 0.85, 1.0), 2.5)
	elif owner == "enemy":
		var o2 := pts.duplicate()
		o2.append(pts[0])
		draw_polyline(o2, Color(0.95, 0.30, 0.32), 2.5)

	# v1.1：驻军标记（每格最多 4 个单位，用职业形状排成一排显示）
	# v1.6.1 修复：不再限定「我方地块」——单位在领地外（无主地块）上也必须显示
	if owner != "enemy":
		var units := GameState.units_on_tile(key)
		if not units.is_empty():
			var n := units.size()
			var span: float = hex_size * 0.36
			var start_x := -span * float(n - 1) * 0.5
			var uy := center + Vector2(0, -hex_size * 0.50)
			# 背景条 + 数量文字，避免与地形/资源图标糊在一起
			var bar_w: float = span * float(n) + hex_size * 0.54
			var bar_h: float = hex_size * 0.34
			draw_rect(Rect2(uy - Vector2(bar_w * 0.5, bar_h * 0.5),
				Vector2(bar_w, bar_h)), Color(0.05, 0.06, 0.09, 0.78), true)
			# 左上角的驻军数量
			var f0 := ThemeDB.fallback_font
			draw_string(f0, uy + Vector2(-bar_w * 0.5 + hex_size * 0.07, hex_size * 0.09),
				"%d" % n, HORIZONTAL_ALIGNMENT_LEFT, -1,
				int(clampf(hex_size * 0.26, 9.0, 13.0)), Color(0.75, 0.9, 1.0))
			var icon_start := uy + Vector2(hex_size * 0.10, 0.0)
			for i in n:
				var u: Dictionary = units[i]
				var prof := str(u.get("profession", "melee"))
				var upos := icon_start + Vector2(span * (float(i) - float(n - 1) * 0.5 + 0.5), 0.0)
				GeoIcon._draw_shape(self, UnitDB.profession_icon(prof), upos,
					hex_size * 0.13, UnitDB.profession_color(prof), true, 1.0)

	# 首都
	if t.get("is_capital", false) or c == capital:
		GeoIcon._draw_shape(self, "star", center, hex_size * 0.42, Color(1.0, 0.88, 0.35), true, 2.0)

	# 据点等级 / 名字
	var nm: String = str(t.get("name", ""))
	if nm != "" and hex_size >= 28.0:
		var f := ThemeDB.fallback_font
		var fs := int(clampf(hex_size * 0.30, 9.0, 14.0))
		if owner == "player":
			if t.get("is_capital", false) or c == capital:
				var max_w: float = hex_size * 2.6
				while fs > 9 and f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > max_w:
					fs -= 1
				draw_string(f, center + Vector2(-max_w * 0.5, hex_size * 0.92), nm, HORIZONTAL_ALIGNMENT_CENTER, max_w, fs, Color(0.85, 0.95, 1.0))
		elif owner == "enemy":
			var label := "危险" if t.get("danger", false) else ("威胁" if t.get("threat", false) else "敌人")
			draw_string(f, center + Vector2(-hex_size * 0.9, hex_size * 0.92), label,
				HORIZONTAL_ALIGNMENT_CENTER, hex_size * 1.8, fs, Color(1.0, 0.55, 0.55))

	# 外部标记
	if marks.has(key):
		var mc: Color = marks[key]
		var o3 := pts.duplicate()
		o3.append(pts[0])
		draw_polyline(o3, mc, 3.0)
		draw_colored_polygon(pts, Color(mc.r, mc.g, mc.b, 0.16))

	# 悬浮 / 选中
	if key == hover_key and key != selected_key:
		var o4 := pts.duplicate()
		o4.append(pts[0])
		draw_polyline(o4, Color(1, 1, 1, 0.45), 1.5)
	if key == selected_key:
		var o5 := pts.duplicate()
		o5.append(pts[0])
		draw_polyline(o5, Color(1.0, 0.92, 0.5), 3.5)


func _draw_axis() -> void:
	var f := ThemeDB.fallback_font
	for q in range(-10, 11):
		for r in range(-10, 11):
			var c := Vector2i(q, r)
			var p := axial_to_screen(c)
			if p.x < 0 or p.y < 0 or p.x > size.x or p.y > size.y:
				continue
			draw_string(f, p + Vector2(-12, 4), "%d,%d" % [q, r],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.5))


static func _res_kind(res: String) -> String:
	match res:
		"wood": return "triangle"
		"coal": return "diamond"
		"copper": return "square"
		"iron": return "hexagon"
		"oil": return "circle"
		"crystal_shard": return "star"
		_: return "circle"


static func _res_color(res: String) -> Color:
	match res:
		"wood": return Color(0.45, 0.80, 0.45)
		"coal": return Color(0.35, 0.35, 0.40)
		"copper": return Color(0.85, 0.55, 0.30)
		"iron": return Color(0.70, 0.75, 0.85)
		"oil": return Color(0.20, 0.20, 0.25)
		"crystal_shard": return Color(0.70, 0.55, 0.95)
		_: return Color(0.8, 0.8, 0.8)


static func _cat_color(cat: String) -> Color:
	match cat:
		"工业建筑": return Color(0.95, 0.72, 0.30)
		"军事建筑": return Color(0.90, 0.35, 0.35)
		"民用建筑": return Color(0.40, 0.75, 0.95)
		_: return Color(0.8, 0.8, 0.8)


# ---------------------------------------------------------------------------
# 交互
# ---------------------------------------------------------------------------
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom(1.12, mb.position)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom(1.0 / 1.12, mb.position)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = true
				_drag_start = mb.position
				_origin_start = origin
			else:
				_dragging = false
				if mb.position.distance_to(_drag_start) < 5.0:
					var k := screen_to_key(mb.position)
					if GameState.state["tiles"].has(k):
						selected_key = k
						tile_selected.emit(k)
						queue_redraw()
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE and mb.pressed:
			_center_view()
			accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging:
			origin = _origin_start + (mm.position - _drag_start)
			queue_redraw()
			accept_event()
		else:
			var k2 := screen_to_key(mm.position)
			if k2 != hover_key:
				hover_key = k2
				queue_redraw()


func _zoom(factor: float, pivot: Vector2) -> void:
	var before := Hex.pixel_to_axial(pivot - origin, hex_size)
	var ns := clampf(hex_size * factor, SIZE_MIN, SIZE_MAX)
	if is_equal_approx(ns, hex_size):
		return
	hex_size = ns
	# 让鼠标下方的地块保持不动
	origin = pivot - Hex.axial_to_pixel(before.x, before.y, hex_size)
	queue_redraw()


func reset_view() -> void:
	hex_size = SIZE_BASE
	_center_view()
	queue_redraw()
