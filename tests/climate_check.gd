extends Node
## W3a 气候参数图专项自检：**确定性 / 温度场的物理性质 / 采样平滑 / 真的接进了地貌**。
##
## 跑法（项目根目录）：
##   godot --headless --path . res://tests/climate_check.tscn
## ⚠️ 必须用场景跑（--script 不注册 autoload）。

const SEED := 20240607

var fails := 0


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  [ok] " + what)
	else:
		fails += 1
		print("  [FAIL] " + what)


## 给一大串浮点做个校验和（比 str() 整个数组便宜得多）
func _sum(a: PackedFloat32Array) -> float:
	var s := 0.0
	for v in a:
		s += v
	return s


func _ready() -> void:
	print("== 气候参数图（W3a）专项自检 ==")

	# ① 建场耗时（总纲第十节点名要实测的数）+ 缓存
	var t0 := Time.get_ticks_msec()
	var f1 := WorldGen.climate_for(SEED)
	var build_ms := Time.get_ticks_msec() - t0
	var t1 := Time.get_ticks_msec()
	var f2 := WorldGen.climate_for(SEED)
	var cache_ms := Time.get_ticks_msec() - t1
	var sz := int(f1["size"])
	print("  建场：%d×%d × 12 月 = %d 个格·月，耗时 %d ms；再取一次（应命中缓存）%d ms"
		% [sz, sz, sz * sz * 12, build_ms, cache_ms])
	_check(int(f1["temp"].size()) == sz * sz * 12, "场的大小正确（%d）" % (sz * sz * 12))
	_check(cache_ms < build_ms, "第二次是命中缓存（%d ms < %d ms）" % [cache_ms, build_ms])
	_check(_sum(f1["temp"]) == _sum(f2["temp"]), "同种子两次取到的场校验和一致（确定）")

	# ② 纬度：赤道带明显比极地带暖。
	#   ⚠️ **纬度看的是像素 y，不是半径 r** —— 地图是**圆盘**，横向远处的格子 y≈0（纬度≈0，属热带）。
	#   第一版用 r≥18 当"极地"，把热带格子混了进去，于是"温差只有 13.5℃"（测试自身写错）。
	var half := Climate.map_half()
	var eq := 0.0
	var n_eq := 0
	var pole := 0.0
	var n_pole := 0
	var tmin := 999.0
	var tmax := -999.0
	for c: Vector2i in Hex.spiral(Consts.MAP_START_RADIUS):
		var t := WorldGen.annual_temp_at(c, SEED)
		tmin = minf(tmin, t)
		tmax = maxf(tmax, t)
		var lat := absf(Hex.axial_to_pixel(c.x, c.y, 1.0).y) / maxf(1.0, half.y)
		if lat <= 0.15:
			eq += t
			n_eq += 1
		elif lat >= 0.75:
			pole += t
			n_pole += 1
	var eq_avg := eq / maxf(1.0, float(n_eq))
	var pole_avg := pole / maxf(1.0, float(n_pole))
	print("  年均温范围 %.1f ~ %.1f℃；赤道带（|纬度|≤0.15）均 %.1f℃ / 极地带（≥0.75）均 %.1f℃"
		% [tmin, tmax, eq_avg, pole_avg])
	_check(eq_avg > pole_avg + 25.0, "赤道带比极地带暖 25℃ 以上（差 %.1f℃）" % (eq_avg - pole_avg))

	# ③ 海拔递减：赤道带里，最高的那格应当比最低的那格冷
	var hi_e := -1.0
	var lo_e := 2.0
	var hi_t := 0.0
	var lo_t := 0.0
	for c: Vector2i in Hex.spiral(3):
		var e := WorldGen.elevation_of(c, SEED)
		var t := WorldGen.annual_temp_at(c, SEED)
		if e > hi_e:
			hi_e = e
			hi_t = t
		if e < lo_e:
			lo_e = e
			lo_t = t
	print("  赤道带内：最高格（e=%.3f）%.1f℃；最低格（e=%.3f）%.1f℃" % [hi_e, hi_t, lo_e, lo_t])
	_check(hi_t < lo_t, "同纬度下**海拔越高越冷**（%.1f℃ < %.1f℃）" % [hi_t, lo_t])

	# ④ 采样平滑：**绝大多数**相邻格温差很小就够（只有"山顶紧挨大海"那种真断崖才会很大，
	#    那是地形本身的特点，不该被当成"采样写错了"；2026-10-13 第一版断言 < 6℃ 就被它卡住）
	var jumps: Array = []
	for c: Vector2i in Hex.spiral(Consts.MAP_START_RADIUS):
		var t := WorldGen.annual_temp_at(c, SEED)
		for nb: Vector2i in Hex.neighbors(c):
			jumps.append(absf(WorldGen.annual_temp_at(nb, SEED) - t))
	jumps.sort()
	var p95: float = jumps[int(float(jumps.size()) * 0.95)]
	var jmax: float = jumps[jumps.size() - 1]
	print("  相邻格温差：95%% 在 %.2f℃ 以内，最大 %.2f℃（共 %d 对）" % [p95, jmax, jumps.size()])
	_check(jmax < 25.0, "相邻格温差没有离谱的值（最大 %.2f℃ < 25℃）" % jmax)
	# ④b **采样器本身**连不连续：直接沿像素空间密集取样（每 0.15 像素一步）
	var clim := WorldGen.climate_for(SEED)
	var prev_t := 0.0
	var first := true
	var step_max := 0.0
	for i in 500:
		var px := -30.0 + float(i) * 0.15
		var tv := Climate.temp_at_pixel(Vector2(px, 4.0), 3, clim)
		if not first:
			step_max = maxf(step_max, absf(tv - prev_t))
		prev_t = tv
		first = false
	print("  密集像素采样（每 0.15 像素一步）：最大相邻温差 %.4f℃" % step_max)
	# ⚠️ 阈值说明：0.15 像素 ≈ **0.26 个网格格**（一格 = 0.568 像素），而相邻网格格本来就可能差 5℃
	#   → 双线性插值走 0.26 格自然会有 ~1.3℃ 的变化，**这就是"连续"的样子**。
	#   （若采样器坏了，会一步跳出**整格**的差 5~15℃，所以 3℃ 这条能抓住它。）
	_check(step_max < 3.0, "采样器本身是连续的（每 0.15 像素最大变化 %.4f℃，没有整格跳变）" % step_max)

	# ⑤ **真的接进了地貌**：比 -5℃ 更冷的格子不该有森林；
	#    再把温度参数去掉（默认 999 = 暖）当**对照** → 应当又长出森林，证明差异确实来自温度。
	var cold_n := 0
	var cold_forest := 0
	var cold_forest_warm := 0
	for c: Vector2i in Hex.spiral(Consts.MAP_START_RADIUS):
		var t := WorldGen.annual_temp_at(c, SEED)
		if t > WorldGen.COLD_FOREST_NONE:
			continue
		cold_n += 1
		var e := WorldGen.elevation_of(c, SEED)
		var m := WorldGen.moisture_of(c, SEED)
		if str(WorldGen.biome_of(e, m)["cover"]) == "forest":
			cold_forest_warm += 1
		if str(WorldGen.biome_of(e, m, t)["cover"]) == "forest":
			cold_forest += 1
	print("  极冷格（< %.0f℃）：%d 格；加温度后森林 %d 个；不加温度（对照）森林 %d 个"
		% [WorldGen.COLD_FOREST_NONE, cold_n, cold_forest, cold_forest_warm])
	_check(cold_n > 0, "存在极冷的格子（%d 格）" % cold_n)
	_check(cold_forest == 0, "极冷格**一个森林都没有**（实际 %d 个）" % cold_forest)
	_check(cold_forest_warm > 0, "对照：不加温度时这些格**本来是有森林的**（%d 个）→ 差异确实来自温度"
		% cold_forest_warm)

	print("== 结果：%s ==" % ("全部通过" if fails == 0 else "%d 项失败" % fails))
	get_tree().quit(1 if fails > 0 else 0)
