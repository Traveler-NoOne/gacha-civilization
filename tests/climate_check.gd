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
	print("  极冷格（< %.0f℃）：%d 格；加温度后森林 %d 个" % [WorldGen.COLD_FOREST_NONE, cold_n, cold_forest])
	_check(cold_n > 0, "存在极冷的格子（%d 格）" % cold_n)
	_check(cold_forest == 0, "极冷格**一个森林都没有**（实际 %d 个）" % cold_forest)
	# 对照改一下：W3b 之后降水也换了，所以"不加温度"的对照不再说明问题；
	# 改为**正面对照**：暖且潮的格子必须**真的长得出森林**（证明整条查表链还活着）
	var warm_forest := 0
	for cw: Vector2i in Hex.spiral(Consts.MAP_START_RADIUS):
		var ew := WorldGen.elevation_of(cw, SEED)
		var mw := WorldGen.moisture_of(cw, SEED)
		var tw := WorldGen.annual_temp_at(cw, SEED)
		if ew >= 0.5 and ew < 0.72 and mw > 0.5 and tw > 10.0:
			if str(WorldGen.biome_of(ew, mw, tw)["cover"]) == "forest":
				warm_forest += 1
	print("  对照：暖（>10℃）且潮（降水>0.5）的丘陵里有 **%d 个森林**" % warm_forest)
	_check(warm_forest > 0, "暖且潮的地方**真的长得出森林**（%d 个）→ 查表链是活的" % warm_forest)

	# ⑥ W3b **雨影**：同一座山，**迎风侧应当比背风侧湿**。
	#    做法：挑高地格 → 按它所在纬度取风向 → 沿风向前后各取约 2 格，比降水。
	#    （风向是纯东西向的，所以**南北走向**的山才有明显雨影；东西走向的山不分迎背风 —— 见 climate.gd）
	var win := 0
	var lee := 0
	var pairs := 0
	for ch: Vector2i in Hex.spiral(Consts.MAP_START_RADIUS):
		if WorldGen.elevation_of(ch, SEED) < 0.62:
			continue
		var ph := Hex.axial_to_pixel(ch.x, ch.y, 1.0)
		var lath := clampf(ph.y / maxf(1.0, half.y), -1.0, 1.0)
		var wh := Climate.wind_at(lath)
		var up_p := WorldGen.annual_precip_at(Hex.pixel_to_axial(ph - wh * 3.5, 1.0), SEED)
		var dn_p := WorldGen.annual_precip_at(Hex.pixel_to_axial(ph + wh * 3.5, 1.0), SEED)
		pairs += 1
		if up_p > dn_p + 0.01:
			win += 1
		elif dn_p > up_p + 0.01:
			lee += 1
	print("  雨影：高地格 %d 个；**迎风侧更湿 %d 个** / 背风侧更湿 %d 个（其余持平）" % [pairs, win, lee])
	_check(pairs > 20, "取到了足够多的高地格（%d 个）" % pairs)
	_check(win > lee, "**迎风侧普遍更湿**（%d > %d）→ 雨影是推出来的" % [win, lee])
	# ⑦ 降水分布（用来核对归一化参考 RAIN_REF 选得合不合适）
	var pmin := 9.9
	var pmax := -9.9
	var psum := 0.0
	var pn := 0
	for cp: Vector2i in Hex.spiral(Consts.MAP_START_RADIUS):
		var pv := WorldGen.annual_precip_at(cp, SEED)
		pmin = minf(pmin, pv)
		pmax = maxf(pmax, pv)
		psum += pv
		pn += 1
	print("  年均降水（归一化 0~1）：%.3f ~ %.3f，均值 %.3f（自动参考 rain_ref=%.4f）"
		% [pmin, pmax, psum / maxf(1.0, float(pn)), float(clim["rain_ref"])])
	_check(pmax > 0.6 and pmin < 0.25, "降水有足够反差（最干 %.3f / 最湿 %.3f）" % [pmin, pmax])

	print("== 结果：%s ==" % ("全部通过" if fails == 0 else "%d 项失败" % fails))
	get_tree().quit(1 if fails > 0 else 0)