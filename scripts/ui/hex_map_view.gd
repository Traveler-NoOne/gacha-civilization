class_name HexMapView
extends Control
## 六边形世界地图视图：绘制、平移、缩放、点击选格。
## 对应设计文档「世界」章节。

## v1.8.2：左键点击的统一出口。
##   key  = 点到了哪一格（轴向坐标的字符串键）
##   uid  = 点到了哪个单位的图标（没点到单位则 ""）
##   gpos = 鼠标的全局坐标（浮窗要出现在鼠标位置）
## 地图只报告"空间事实"；"这格是不是我的领地、要不要开窗口"属于语义，由 view_world_page 判断。
signal tile_left_clicked(key: String, uid: String, gpos: Vector2)

## v1.8.5：右键点地块（用于弹"球形图标操作菜单"）
signal tile_right_clicked(key: String, gpos: Vector2)
## v1.8.20.4：鼠标悬停位置改变
signal hover_changed(key: String)

# 这三个常量决定了地图缩放的默认大小和最大缩小和最大放大。
## 地块基础大小
const SIZE_BASE := 34.0
## 地块大小下限
const SIZE_MIN := 20.0
## 地块大小上限
const SIZE_MAX := 62.0

## 设置渲染地块的当前大小（默认值：地块基础大小）
var hex_size := SIZE_BASE
## 地图偏移量 
var origin := Vector2.ZERO
## 鼠标悬停地块
var hover_key := ""
## 可选的高亮标记：{ "q,r": Color }
var marks: Dictionary = {}
var show_axis := false
## 检测拖拽
var _dragging := false
var _drag_start := Vector2.ZERO
var _origin_start := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_center_view()
	resized.connect(queue_redraw)

## 定位到目标地块
func center_on_axial(c: Vector2i) -> void:
	origin = size * 0.5 - Hex.axial_to_pixel(c.x, c.y, hex_size)
	queue_redraw()

## 将摄像头对准首都地块
func _center_view() -> void:
	center_on_axial(WorldGen.coord_of(str(GameState.state["capital"])))

## qr坐标转场景坐标
func axial_to_screen(c: Vector2i) -> Vector2:
	return Hex.axial_to_pixel(c.x, c.y, hex_size) + origin

## 场景坐标转qr坐标
func screen_to_key(p: Vector2) -> String:
	var c := Hex.pixel_to_axial(p - origin, hex_size)
	return WorldGen.key_of(c)


# ---------------------------------------------------------------------------
# 绘制（v1.8.1：按图层）
# ---------------------------------------------------------------------------
## 视口裁剪：只取落在可见区域附近的格子，并把这一格要用的几何**一次算好**。
## 8 个图层共用这一份结果 —— 同一份数据只算一次，不在每层里各算一遍。
## 每个元素：{ "key": String, "t": Dictionary, "c": Vector2i,
##             "center": Vector2, "pts": PackedVector2Array }
func _visible_tiles() -> Array:
	var out: Array = []
	var tiles_v: Variant = GameState.state.get("tiles")
	if tiles_v == null or (tiles_v as Dictionary).is_empty():
		Fatal.fatal("E-MAP-001")
		return out               # 报完之后这一帧仍要返回，别让 _draw 炸
	var tiles: Dictionary = tiles_v

	for key in tiles.keys():
		var c := WorldGen.coord_of(key)
		var center := axial_to_screen(c)
		if center.x < -hex_size * 2.0 or center.x > size.x + hex_size * 2.0 \
				or center.y < -hex_size * 2.0 or center.y > size.y + hex_size * 2.0:
			continue
		out.append({
			"key": key, "t": tiles[key], "c": c, "center": center,
			"pts": Hex.corners(center, hex_size - 1.5),
		})
	return out


## ===========================================================================
## 边的分层与粗细（2026-10-13 用户定）—— **从下到上**：
##   ① 地形层（地形色 + **水路**：河道 / 水陆分界）＝ 基准 × **2.5**（"寻常描边的两三倍"）
##   ④ 领地边 ＝ 基准 × **1.5**
##   ⑦ 悬停高亮（**最上面**，不被任何边压住）
## 图层顺序本来就与之一致（见下面的 8 层说明），这里只是把**粗细**定死成常量，
## 免得以后各层各写一个数字、互相压住。
## ===========================================================================
const EDGE_W_BASE := 1.0            ## 寻常描边（基准）
const EDGE_W_WATER := 2.5           ## 水路（河道 / 水陆分界）= 基准 × 2.5
const EDGE_W_TERRITORY := 1.5       ## 领地边 = 基准 × 1.5


## v1.8.1：绘制顺序 = 图层顺序。
## 图层顺序（同时就是 8 个层函数的顺序）：
##   ① 底色（地形/迷雾） ② 特征物（资源点） ③ 建筑 ④ 领地边框
##   ⑤ 单位（驻军）      ⑥ 据点标记（首都星） ⑦ 标记+悬浮/选中 ⑧ 文字
func _draw() -> void:
	var capital := WorldGen.coord_of(str(GameState.state.get("capital", "0,0")))
	var vis := _visible_tiles()

	# 1-B：按层循环 —— 一整层画完，再画下一层。
	# 与 1-A 的唯一差别：1-A 是"一格画完 8 层再画下一格"，这里是"8 层各扫一遍所有格"。
	# 结果差异只在**跨格重叠**处：文字的层最后画，所以不会再被邻格盖住。
	for v in vis:
		_draw_tile_base(v)
	for v in vis:
		_draw_water_edges(v)      # 水路（水陆分界）：底色之上、领地边之下（用户定的分层）
	for v in vis:
		_draw_tile_features(v)
	for v in vis:
		_draw_tile_buildings(v)
	for v in vis:
		_draw_tile_border(v)
	for v in vis:
		_draw_tile_units(v)
	for v in vis:
		_draw_tile_stronghold(v, capital)
	for v in vis:
		_draw_tile_overlay(v)
	for v in vis:
		_draw_tile_text(v, capital)

	# 可选：坐标轴标签
	if show_axis:
		_draw_axis()


func _draw_tile_base(v: Dictionary) -> void:
	var t: Dictionary = v["t"]
	var pts: PackedVector2Array = v["pts"]
	if not t.get("discovered", false):
		# 迷雾：几乎不可见的深色六边形
		draw_colored_polygon(pts, Color(0.075, 0.078, 0.11, 0.85))
		var fog := pts.duplicate()
		fog.append(pts[0])
		draw_polyline(fog, Color(0.14, 0.15, 0.20, 0.7), 1.0)
		return
	# 地形底色
	draw_colored_polygon(pts, Consts.terrain_color(str(t.get("terrain", "plain"))))
	# v1.8.21：地物（覆盖物）叠一层 —— 内缩一圈的小六边形，这样地形色还看得见
	var cover := str(t.get("cover", ""))
	if cover != "":
		draw_colored_polygon(Hex.corners(v["center"], hex_size * 0.66), Consts.cover_color(cover))

	var outline := pts.duplicate()
	outline.append(pts[0])
	# v1.8.21：河流格曾用**蓝色整格描边**标出（那时河只按格记）。
	# 2026-10-13（W4）：**改成按边画**（见 `_draw_water_edges`）—— 河道是"一条线沿着边走"，
	# 不是"把有河的格子圈起来"。所以这里统一画普通格线。
	draw_polyline(outline, Color(0, 0, 0, 0.35), EDGE_W_BASE)



func _draw_tile_features(v: Dictionary) -> void:
	var t: Dictionary = v["t"]
	if not t.get("discovered", false):
		return
	var res: String = str(t.get("resource", ""))
	if res == "":
		return
	var center: Vector2 = v["center"]
	var amount := float(t.get("amount", 0.0))
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


func _draw_tile_buildings(v: Dictionary) -> void:
	var t: Dictionary = v["t"]
	if not t.get("discovered", false):
		return
	var bs: Array = t.get("buildings", [])
	if bs.is_empty():
		return
	var center: Vector2 = v["center"]
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


func _draw_tile_border(v: Dictionary) -> void:
	var t: Dictionary = v["t"]
	if not t.get("discovered", false):
		return
	var owner: String = t.get("owner", "")
	var pts: PackedVector2Array = v["pts"]
	if owner == "player":
		var o := pts.duplicate()
		o.append(pts[0])
		draw_polyline(o, Color(0.55, 0.85, 1.0), EDGE_W_TERRITORY)
	elif owner == "enemy":
		var o2 := pts.duplicate()
		o2.append(pts[0])
		draw_polyline(o2, Color(0.95, 0.30, 0.32), EDGE_W_TERRITORY)


## 水路层（最底下的边）：**水陆分界**只画"我这一侧"那条边 ——
## 以前整张图只有 1.0 的通用格线，看不出哪里是海岸；现在海岸线是一条粗线。
## 方向索引规范：**边 k ↔ DIRECTIONS[(−k) mod 6]**（2026-10-13 数值验证过，见 hex.gd 顶部）。
func _draw_water_edges(v: Dictionary) -> void:
	var t: Dictionary = v["t"]
	if not t.get("discovered", false):
		return
	var c: Vector2i = v["c"]
	var corners := Hex.corners(v["center"], hex_size - 1.5)
	var mine_water := str(t.get("terrain", "")) == "water"
	var tiles: Dictionary = GameState.state["tiles"]
	for k in 6:
		var d: Vector2i = Hex.DIRECTIONS[(6 - k) % 6]
		var nt: Variant = tiles.get(WorldGen.key_of(c + d))
		var n_water := true          # 图外 / 未发现都当作水 → 边境也有海岸线
		if nt != null:
			var nd: Dictionary = nt
			n_water = (not bool(nd.get("discovered", false))) \
				or str(nd.get("terrain", "")) == "water"
		if mine_water != n_water:
			draw_line(corners[k], corners[(k + 1) % 6], Color(0.30, 0.55, 0.85, 0.95), EDGE_W_WATER)
	# ---- 河道（W4）：**只画"我这一侧"拥有的那条边** ----
	# 边的键是 `"q,r,d"`，owner = 两端坐标字典序较小者 → 同一条边只会有**一端**匹配上，
	# 所以不会出现"两边各画一次变成双倍粗"的问题。
	var redges := WorldGen.river_edges(int(GameState.state.get("seed", 0)))
	for kr in 6:
		var ek := "%d,%d,%d" % [c.x, c.y, kr]
		if not redges.has(ek):
			continue
		# 粗细随流量微调（大江比小溪粗一点）
		var fl := clampf(float(redges[ek]) / 60.0, 0.0, 1.0)
		draw_line(corners[kr], corners[(kr + 1) % 6],
			Color(0.35, 0.70, 1.0, 0.98), EDGE_W_WATER * (1.0 + 0.35 * fl))


## 单位图标在屏幕上的位置。
## 返回：[{ "u": Dictionary, "pos": Vector2 }, ...]
##   "u" 就是该单位的存档数据（uid / profession 都从它取，避免再存一份造成两份口径）
## 【重要】**绘制与点击命中共用这一份几何** —— 两处各算一遍的话，
## 哪天挪了图标位置，命中就会悄悄失准（点得到的地方 ≠ 看到的地方），而且极难查。
func unit_icon_positions(key: String) -> Array:
	var out: Array = []
	# 敌方地块不画单位标记，所以也没有可点的图标
	if str(GameState.tile_at(key).get("owner", "")) == "enemy":
		return out
	var units := GameState.units_on_tile(key)
	var n := units.size()
	if n == 0:
		return out
	var center := tile_center(key)

	var span: float = hex_size * 0.36
	var uy := center + Vector2(0, -hex_size * 0.50)
	var icon_start := uy + Vector2(hex_size * 0.10, 0.0)
	for i in n:
		out.append({
			"u": units[i],
			"pos": icon_start + Vector2(span * (float(i) - float(n - 1) * 0.5 + 0.5), 0.0),
		})
	return out


func _draw_tile_units(v: Dictionary) -> void:
	var t: Dictionary = v["t"]
	if not t.get("discovered", false):
		return
	if str(t.get("owner", "")) == "enemy":
		return
	# 图标位置走 unit_icon_positions()（与点击命中共用），不在这里另算一遍
	var icons := unit_icon_positions(str(v["key"]))
	if icons.is_empty():
		return
	var center: Vector2 = v["center"]
	var n := icons.size()
	var span: float = hex_size * 0.36
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
	for ic in icons:
		var u: Dictionary = ic["u"]
		var prof := str(u.get("profession", "melee"))
		GeoIcon._draw_shape(self, UnitDB.profession_icon(prof), ic["pos"],
			hex_size * 0.13, UnitDB.profession_color(prof), true, 1.0)


func _draw_tile_stronghold(v: Dictionary, capital: Vector2i) -> void:
	var t: Dictionary = v["t"]
	if not t.get("discovered", false):
		return
	# 首都
	if t.get("is_capital", false) or v["c"] == capital:
		GeoIcon._draw_shape(self, "star", v["center"], hex_size * 0.42,
			Color(1.0, 0.88, 0.35), true, 2.0)


func _draw_tile_overlay(v: Dictionary) -> void:
	var t: Dictionary = v["t"]
	if not t.get("discovered", false):
		return
	var key: String = v["key"]
	var pts: PackedVector2Array = v["pts"]
	# 外部标记
	if marks.has(key):
		var mc: Color = marks[key]
		var o3 := pts.duplicate()
		o3.append(pts[0])
		draw_polyline(o3, mc, 3.0)
		draw_colored_polygon(pts, Color(mc.r, mc.g, mc.b, 0.16))
	# 悬浮高亮（v1.8.2：取消"选中地块"的黄框 —— 地块不再可选中）
	if key == hover_key:
		var o4 := pts.duplicate()
		o4.append(pts[0])
		draw_polyline(o4, Color(1, 1, 1, 0.45), 1.5)


func _draw_tile_text(v: Dictionary, capital: Vector2i) -> void:
	var t: Dictionary = v["t"]
	if not t.get("discovered", false):
		return
	var nm: String = str(t.get("name", ""))
	if nm == "" or hex_size < 28.0:
		return
	var owner: String = t.get("owner", "")
	var center: Vector2 = v["center"]
	var f := ThemeDB.fallback_font
	var fs := int(clampf(hex_size * 0.30, 9.0, 14.0))
	if owner == "player":
		if t.get("is_capital", false) or v["c"] == capital:
			var max_w: float = hex_size * 2.6
			while fs > 9 and f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > max_w:
				fs -= 1
			draw_string(f, center + Vector2(-max_w * 0.5, hex_size * 0.92), nm,
				HORIZONTAL_ALIGNMENT_CENTER, max_w, fs, Color(0.85, 0.95, 1.0))
	elif owner == "enemy":
		var label := "危险" if t.get("danger", false) else ("威胁" if t.get("threat", false) else "敌人")
		draw_string(f, center + Vector2(-hex_size * 0.9, hex_size * 0.92), label,
			HORIZONTAL_ALIGNMENT_CENTER, hex_size * 1.8, fs, Color(1.0, 0.55, 0.55))


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
	if event is InputEventMouseButton: # 检测event是否为鼠标点击事件
		var mb := event as InputEventMouseButton # 将event转换为鼠标点击事件储存到mb
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed: # 如果鼠标滚轮向上
			_zoom(1.12, mb.position) # 放大地图
			accept_event() 
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed: # 如果鼠标滚轮向下
			_zoom(1.0 / 1.12, mb.position) # 缩小地图
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT: # 如果鼠标左键按下
			if mb.pressed:
				_dragging = true # 按住时将拖拽设置为true
				_drag_start = mb.position # 将点击时的位置储存进拖拽起点
				_origin_start = origin # 将偏移量存进偏移起点
			else:
				_dragging = false # 按住时将拖拽设置为false
				if mb.position.distance_to(_drag_start) < 5.0: # 如果拖拽结束点的距离小于5
					var k := screen_to_key(mb.position)
					if GameState.state["tiles"].has(k): # 如果qr坐标存在地块
						# v1.8.2：把"公布qr坐标 + 单位UID + 鼠标位置"一起报出去
						var uid := unit_uid_at(k, mb.position) # 获取最近的棋子
						tile_left_clicked.emit(k, uid, get_global_transform() * mb.position)
						queue_redraw()
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			# v1.8.5：右键 = 弹该地块的操作菜单（球形图标按钮）
			var kr := screen_to_key(mb.position)
			if GameState.state["tiles"].has(kr):
				tile_right_clicked.emit(kr, get_global_transform() * mb.position)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE and mb.pressed:
			_center_view()
			accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging:
			origin = _origin_start + (mm.position - _drag_start)
			queue_redraw()
			# 平移途中不显示悬停信息（并通知外面收起）
			if hover_key != "":
				hover_key = ""
				hover_changed.emit("")
			accept_event()
		else:
			var k2 := screen_to_key(mm.position)
			if k2 != hover_key:
				hover_key = k2
				queue_redraw()
				hover_changed.emit(k2)



## 某一格的中心（地图本地坐标）。绘制与命中都用它，避免出现两份口径。
func tile_center(key: String) -> Vector2:
	return axial_to_screen(WorldGen.coord_of(key))


## 点中的是不是这一格的首都星？**收全局坐标**（转换放在这里，调用方不用操心）。
## 半径与绘制共用 _draw_tile_stronghold() 里的 hex_size * 0.42 —— 看到多大，就能点多中。
func capital_star_hit(key: String, global_pos: Vector2) -> bool:
	var t := GameState.tile_at(key)
	if not bool(t.get("discovered", false)):
		return false
	if not bool(t.get("is_capital", false)) and key != str(GameState.state.get("capital", "")):
		return false
	var local := get_global_transform().affine_inverse() * global_pos
	return local.distance_to(tile_center(key)) <= hex_size * 0.42

## 这一格上，点到了哪个单位的图标？（没点中返回 ""）
## 需要参数：qr坐标: srt，鼠标位置: vec2
## 命中口径 与绘制共用 unit_icon_positions() —— 位置一致，不会"看得到却点不到"。
## 多个图标都落进范围内时取 最近 的那个。
func unit_uid_at(key: String, pos: Vector2) -> String:
	var best := ""
	var best_d := INF
	var reach: float = hex_size * 0.22
	for ic in unit_icon_positions(key):
		var d: float = pos.distance_to(ic["pos"])
		if d <= reach and d < best_d:
			best_d = d
			best = str((ic["u"] as Dictionary).get("uid", ""))
	return best


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
