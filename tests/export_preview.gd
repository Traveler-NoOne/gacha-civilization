extends Node
## ===========================================================================
## 世界生成**预览导出**（工具，**不是断言测试**）
##
## 为什么需要它：游戏里默认镜头只看得到地图的一小块，**宏观形态**（山脉走向 / 气候带 / 河网）
## 在截图里根本看不出来（这一路上被它挡过好几次）。导出成灰度图之后可以直接看。
##
## 跑法：`godot --headless --path . res://tests/export_preview.tscn`
## 输出：`artifacts/preview/*.png`（`.gitignore` 已排除，属工具产物，不入库）
##
## 导出的几张（同一套"原型图坐标"画布，便于互相叠着看）：
##   01_prototype.png  原型图（地形高度灰度）+ **裁切窗口方框**（这一局用的是哪一块）
##   02_routes.png     水路**线路图**（原型空间：折成六边形**之前**的水路走向）
##   03_hex_rivers.png 折好的**六边形水路**（画在地块边上；线宽随流量）
##   04_koppen.png     柯本气候分类（灰度分级，图例打在控制台）
##   05_temp.png       年均温
##   06_precip.png     年均降水
##   07_world.png      游戏地图全图（每格地形灰点 + 河线）—— 最像"世界地图"的一张
## ===========================================================================

const SEED := 20240607
const OUT_DIR := "res://artifacts/preview"
const S := 8            ## 游戏地图那张的放大倍数（一格 8×8 像素，看得清）
const DOT := 5          ## 每格画多大的点

var _fails := 0


func _ok(cond: bool, what: String) -> void:
	if cond:
		print("  [ok] " + what)
	else:
		_fails += 1
		print("  [FAIL] " + what)


## 一堆 0~1 的浮点 → 灰度 PNG
func _save_gray(vals: PackedFloat32Array, n: int, path: String, lo: float, hi: float) -> void:
	var data := PackedByteArray()
	data.resize(n * n)
	var span := maxf(0.00001, hi - lo)
	for i in n * n:
		data[i] = int(clampf((vals[i] - lo) / span, 0.0, 1.0) * 255.0)
	Image.create_from_data(n, n, false, Image.FORMAT_L8, data).save_png(path)


func _blank(n: int, v: int = 255) -> Image:
	var data := PackedByteArray()
	data.resize(n * n)
	data.fill(v)
	return Image.create_from_data(n, n, false, Image.FORMAT_L8, data)


## 画一段线（Bresenham；Image 自己没有画线）
func _line(img: Image, x0: int, y0: int, x1: int, y1: int, v: int, w: int = 1) -> void:
	var dx := absi(x1 - x0)
	var dy := -absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy
	var guard := 0
	while guard < 20000:
		guard += 1
		for ox in range(-w + 1, w):
			for oy in range(-w + 1, w):
				var px := x0 + ox
				var py := y0 + oy
				if px >= 0 and py >= 0 and px < img.get_width() and py < img.get_height():
					img.set_pixel(px, py, Color8(v, v, v))
		if x0 == x1 and y0 == y1:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy


## 世界坐标（像素空间 size=1）→ 原型图画布像素
func _to_field(p: Vector2, half: Vector2, crop: Vector2, n: int) -> Vector2:
	var q := p + crop
	return Vector2((q.x + half.x) / (2.0 * half.x) * float(n),
		(q.y + half.y) / (2.0 * half.y) * float(n))


func _ready() -> void:
	print("== 世界生成预览导出 ==")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	GameState.new_game(SEED)

	var f := WorldGen.climate_for(SEED)
	var n := int(f["size"])
	var half := Climate.dead_half()
	var crop := Climate.get_crop()
	var heights: PackedFloat32Array = f["heights"]

	# ---- 01 原型图（地形高度）+ 裁切窗口 ----
	var hlo := 9.9
	var hhi := -9.9
	for h in heights:
		hlo = minf(hlo, h)
		hhi = maxf(hhi, h)
	_save_gray(heights, n, OUT_DIR + "/01_prototype.png", hlo, hhi)
	var img1 := Image.load_from_file(ProjectSettings.globalize_path(OUT_DIR + "/01_prototype.png"))
	var mh := Climate.map_half()
	var c0 := _to_field(Vector2(-mh.x, -mh.y), half, crop, n)
	var c1 := _to_field(Vector2(mh.x, mh.y), half, crop, n)
	for x in range(int(c0.x), int(c1.x)):
		if x >= 0 and x < n:
			img1.set_pixel(x, int(c0.y), Color8(255, 255, 255))
			img1.set_pixel(x, int(c1.y) - 1, Color8(0, 0, 0))
	for y in range(int(c0.y), int(c1.y)):
		if y >= 0 and y < n:
			img1.set_pixel(int(c0.x), y, Color8(255, 255, 255))
			img1.set_pixel(int(c1.x) - 1, y, Color8(0, 0, 0))
	img1.save_png(OUT_DIR + "/01_prototype.png")
	print("  01 原型图 %dx%d（白框=裁切窗口，也就是这一局用的那一块）" % [n, n])

	# ---- 01b 只看**板块效应**（把"手工的大陆形状"和噪声都排除掉）----
	# 为什么要单独一张：01 里最显眼的是 `mainland_pull` 那一层**手工形状**（径向：中间高、四周低）
	# 以及我画的**裁切方框**（就是那四条直线）；而**板块效应只是窄窄一条带**，
	# 在"按 min/max 归一化"的整图里被压平了 → 于是看起来"没有半点板块痕迹" ✗
	var peff := PackedFloat32Array()
	peff.resize(n * n)
	var crust := WorldGen.crust_for(SEED)
	for iy2 in n:
		for ix2 in n:
			var pp := Vector2((float(ix2) + 0.5) / float(n) * 2.0 * half.x - half.x,
				(float(iy2) + 0.5) / float(n) * 2.0 * half.y - half.y)
			peff[iy2 * n + ix2] = 0.5 + Plates.effect_at(Hex.pixel_to_axial(pp, 1.0), SEED, crust) * 1.5
	_save_gray(peff, n, OUT_DIR + "/01b_plates.png", 0.0, 1.0)
	print("  01b 板块效应单独一张（灰=没影响；亮=抬升、暗=下陷）")

	# ---- 控制台 ASCII 版原型图（**文本**，避开图片管线带来的观感歧义）----
	print("  原型图 ASCII（32×32；@=高，. =低）：")
	var m := 32
	var ramp := " .:-=+*#%@"
	for ay in m:
		var row := "    "
		for ax in m:
			var gx2 := int((float(ax) + 0.5) / float(m) * float(n))
			var gy2 := int((float(ay) + 0.5) / float(m) * float(n))
			var vv := (heights[gy2 * n + gx2] - hlo) / maxf(0.00001, hhi - hlo)
			row += ramp[clampi(int(vv * 9.0), 0, 9)]
		print(row)

	# ---- 诊断：中心那行 / 那列是不是"特殊"的？（验证"四条线从中心连到图片边缘"）----
	# 如果是真的四射线（十字/叉），那"过中心的那一行/那一列"的数值模式会和旁边不一样。
	var mid := n / 2
	var lr := "    中行(高度×100)："
	var lc := "    中列(高度×100)："
	var lr8 := "   偏8行(对照)：  "
	var lr16 := "   偏16行(对照)： "
	for s in range(0, n, 6):
		lr += "%2d " % int(heights[mid * n + s] * 100.0)
		lc += "%2d " % int(heights[s * n + mid] * 100.0)
		lr8 += "%2d " % int(heights[(mid + 8) * n + s] * 100.0)
		lr16 += "%2d " % int(heights[(mid + 16) * n + s] * 100.0)
	print(lr)
	print(lc)
	print(lr8)
	print(lr16)

	# ---- 02 水路线路图（原型空间，折之前的走向）----
	var img2 := _blank(n, 255)
	var routes := River.routes()
	var route_pts := 0
	for r in routes:
		var pts: Array = r
		route_pts += pts.size()
		for i in range(1, pts.size()):
			var a := _to_field(Hex.axial_to_pixel((pts[i - 1] as Vector2i).x, (pts[i - 1] as Vector2i).y, 1.0), half, crop, n)
			var b := _to_field(Hex.axial_to_pixel((pts[i] as Vector2i).x, (pts[i] as Vector2i).y, 1.0), half, crop, n)
			_line(img2, int(a.x), int(a.y), int(b.x), int(b.y), 0, 1)
	img2.save_png(OUT_DIR + "/02_routes.png")
	print("  02 线路图：%d 条线路、共 %d 个点（黑线=水路走向，还没折）" % [routes.size(), route_pts])

	# ---- 03 折好的六边形水路（画在地块边上）----
	var img3 := _blank(n, 255)
	var edges := River.edges()
	for ek in edges.keys():
		var parts := str(ek).split(",")
		if parts.size() != 3:
			continue
		var c := Vector2i(int(parts[0]), int(parts[1]))
		var d := int(parts[2])
		var k := ((6 - d) % 6 + 6) % 6
		var center := Hex.axial_to_pixel(c.x, c.y, 1.0)
		var cs := Hex.corners(center, 1.0)
		var pa := _to_field(cs[k], half, crop, n)
		var pb := _to_field(cs[(k + 1) % 6], half, crop, n)
		_line(img3, int(pa.x), int(pa.y), int(pb.x), int(pb.y), 0, 1)
	img3.save_png(OUT_DIR + "/03_hex_rivers.png")
	print("  03 六边形水路：%d 条边（黑线=河道，画在地块边上）" % edges.size())

	# ---- 04 柯本气候分类（粗采样，灰度分级）----
	var step := 4
	var mn := int(ceil(float(n) / float(step)))
	var kdata := PackedByteArray()
	kdata.resize(n * n)
	var legend := {}
	for iy in mn:
		for ix in mn:
			var px := (float(ix) + 0.5) / float(mn) * float(n)
			var py := (float(iy) + 0.5) / float(mn) * float(n)
			var p := Vector2(px / float(n) * 2.0 * half.x - half.x,
				py / float(n) * 2.0 * half.y - half.y) - crop
			var kl := Climate.koppen_at(Hex.pixel_to_axial(p, 1.0), f)
			legend[kl] = int(legend.get(kl, 0)) + 1
			var lv := _koppen_gray(kl)
			for oy in step:
				for ox in step:
					var gx2 := ix * step + ox
					var gy2 := iy * step + oy
					if gx2 < n and gy2 < n:
						kdata[gy2 * n + gx2] = lv
	Image.create_from_data(n, n, false, Image.FORMAT_L8, kdata).save_png(OUT_DIR + "/04_koppen.png")
	print("  04 柯本分类（灰度分级）：%s" % str(legend))
	print("      灰度对照：Af/Am/Aw=40 ／ BW=200 ／ BS=170 ／ C*=90 ／ D*=130 ／ ET=230 ／ EF=250 ／ 水=255")

	# ---- 05 年均温 / 06 年均降水 ----
	var tvals := PackedFloat32Array()
	tvals.resize(n * n)
	var pvals := PackedFloat32Array()
	pvals.resize(n * n)
	for i in n * n:
		tvals[i] = f["temp"][i]        # 第 0 个月的场（只为看梯度）
		pvals[i] = annual_precip_raw(f, i)
	_save_gray(tvals, n, OUT_DIR + "/05_temp.png", -30.0, 30.0)
	_save_gray(pvals, n, OUT_DIR + "/06_precip.png", 0.0, 0.02)
	print("  05 年均温 / 06 年均降水 已导出")

	# ---- 07 游戏地图全图（每格一个灰点 + 河线）----
	var tiles: Dictionary = GameState.state["tiles"]
	var r := Consts.MAP_START_RADIUS
	var w := (2 * r + 3) * S
	var img7 := _blank(w, 245)
	for k in tiles.keys():
		var t: Dictionary = tiles[k]
		var cc := WorldGen.coord_of(str(k))
		var pos := Hex.axial_to_pixel(cc.x, cc.y, float(S)) + Vector2(w * 0.5, w * 0.5)
		var g := _terrain_gray(str(t.get("terrain", "plain")))
		var x0 := int(pos.x) - int(DOT / 2)
		var y0 := int(pos.y) - int(DOT / 2)
		for oy in DOT:
			for ox in DOT:
				if x0 + ox >= 0 and y0 + oy >= 0 and x0 + ox < w and y0 + oy < w:
					img7.set_pixel(x0 + ox, y0 + oy, Color8(g, g, g))
	for ek2 in River.edges().keys():
		var p2 := str(ek2).split(",")
		if p2.size() != 3:
			continue
		var c2 := Vector2i(int(p2[0]), int(p2[1]))
		var d2 := int(p2[2])
		var k2 := ((6 - d2) % 6 + 6) % 6
		var center2 := Hex.axial_to_pixel(c2.x, c2.y, float(S)) + Vector2(w * 0.5, w * 0.5)
		var cs2 := Hex.corners(center2, float(S))
		_line(img7, int(cs2[k2].x), int(cs2[k2].y), int(cs2[(k2 + 1) % 6].x),
			int(cs2[(k2 + 1) % 6].y), 20, 1)
	img7.save_png(OUT_DIR + "/07_world.png")
	print("  07 游戏地图全图 %dx%d（灰点=地形、黑线=河）" % [w, w])

	print("== 完成：%s ==" % ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit(1 if _fails > 0 else 0)


## 场里第 i 个格子的年均原始降水
func annual_precip_raw(f: Dictionary, i: int) -> float:
	var n := int(f["size"])
	var sz := n * n
	var acc := 0.0
	for m in Climate.MONTHS:
		acc += f["precip"][m * sz + i]
	return acc / float(Climate.MONTHS)


## 柯本类别 → 灰度（分级看得清就行，不是配色方案）
func _koppen_gray(k: String) -> int:
	if k == "BW":
		return 200
	if k == "BS":
		return 170
	if k.begins_with("A"):
		return 40
	if k.begins_with("C"):
		return 90
	if k.begins_with("D"):
		return 130
	if k == "ET":
		return 230
	if k == "EF":
		return 250
	return 255


## 地形 → 灰度（水最深、山顶最亮）
func _terrain_gray(tn: String) -> int:
	match tn:
		"water":
			return 120
		"plain":
			return 190
		"hill":
			return 215
		"dune":
			return 245
		"wasteland":
			return 230
		"mountain":
			return 70
		_:
			return 200
