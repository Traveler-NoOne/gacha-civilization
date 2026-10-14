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
		# ⚠️ 世界只是**原本地球的一块碎片**（死地图 4 倍大 → 世界只占 ±1/4 的纬度），
		#    所以世界内部温差**天生就小**：这里只要求**方向对**（赤道带比极地带暖）。
		#    "这块碎片落在哪个气候带"由**裁切窗口**决定 —— 见下面 ⑤c 的断言。
		var lat := absf(Hex.axial_to_pixel(c.x, c.y, 1.0).y) / maxf(1.0, Climate.map_half().y)
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
	_check(eq_avg > pole_avg + 4.0,
		"赤道带比极地带暖 4℃ 以上（差 %.1f℃；世界是「地球碎片」，跨度天生小）" % (eq_avg - pole_avg))

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

	# ⑤ **真的接进了地貌**（W3c 起按**柯本类别**判）：极地不长树、沙漠不长树、草原不长树（只长草）
	var e_n := 0
	var e_forest := 0
	var bw_n := 0
	var bw_forest := 0
	var bs_n := 0
	var bs_forest := 0
	for c: Vector2i in Hex.spiral(Consts.MAP_START_RADIUS):
		var k := WorldGen.koppen_at(c, SEED)
		var e := WorldGen.elevation_of(c, SEED)
		var m := WorldGen.moisture_of(c, SEED)
		var cv := str(WorldGen.biome_of(e, m, k)["cover"])
		if k == "EF" or k == "ET":
			e_n += 1
			if cv == "forest":
				e_forest += 1
		elif k == "BW":
			bw_n += 1
			if cv == "forest":
				bw_forest += 1
		elif k == "BS":
			bs_n += 1
			if cv == "forest":
				bs_forest += 1
	print("  极地(E) %d 格→森林 %d；沙漠(BW) %d 格→森林 %d；草原(BS) %d 格→森林 %d"
		% [e_n, e_forest, bw_n, bw_forest, bs_n, bs_forest])
	_check(e_n > 0, "存在极地格（%d）" % e_n)
	_check(e_forest == 0, "极地格**不长树**（实际 %d）" % e_forest)
	_check(bw_n > 0, "存在沙漠格（%d）" % bw_n)
	_check(bw_forest == 0, "沙漠**不长树**（实际 %d）" % bw_forest)
	_check(bs_forest == 0, "草原**不长树**（实际 %d，草原只长草）" % bs_forest)
	# 正面对照：暖且潮的地方必须**真的长得出森林**（证明整条查表链还活着）
	var warm_forest := 0
	for cw: Vector2i in Hex.spiral(Consts.MAP_START_RADIUS):
		var kw := WorldGen.koppen_at(cw, SEED)
		var ew := WorldGen.elevation_of(cw, SEED)
		var mw := WorldGen.moisture_of(cw, SEED)
		if ew >= 0.5 and ew < 0.72 and mw > 0.5 and (kw == "Af" or kw == "Am" or kw == "Cf" or kw == "Df"):
			if str(WorldGen.biome_of(ew, mw, kw)["cover"]) == "forest":
				warm_forest += 1
	print("  对照：暖且潮（Af/Am/Cf/Df 且降水>0.5）的丘陵里有 **%d 个森林**" % warm_forest)
	_check(warm_forest > 0, "暖且潮的地方**真的长得出森林**（%d 个）→ 查表链是活的" % warm_forest)

	# ⑤b 柯本分类本身：类别数够多（气候有分带，不是"一种气候铺满全图"）
	var kinds := {}
	for ck: Vector2i in Hex.spiral(Consts.MAP_START_RADIUS):
		var kk := WorldGen.koppen_at(ck, SEED)
		kinds[kk] = int(kinds.get(kk, 0)) + 1
	print("  柯本类别分布：%s" % str(kinds))
	_check(kinds.size() >= 4, "柯本类别数 ≥ 4（实际 %d 类）→ 气候分带出来了" % kinds.size())

	# ⑤c W5：**裁切窗口** —— 换个窗口 = 另一块世界；而且**能切回来、逐位一致**。
	#   ⚠️ 断言的量要选对：纬度是"按世界自己"算的，所以**裁切不改变同纬度处的温度**，
	#   它改变的是**那里的地形与降水**（同一个世界坐标，采样到死地图上的另一处）。
	var probe := Vector2i(0, 0)
	var field0 := WorldGen.climate_for(SEED)
	var mm_home := Climate.annual_precip_mm(probe, field0)
	var t_home := WorldGen.annual_temp_at(probe, SEED)
	Climate.set_crop(Vector2(18.0, 18.0))
	var mm_far := Climate.annual_precip_mm(probe, WorldGen.climate_for(SEED))
	var t_far := WorldGen.annual_temp_at(probe, SEED)
	Climate.set_crop(Vector2.ZERO)
	var mm_back := Climate.annual_precip_mm(probe, WorldGen.climate_for(SEED))
	var t_back := WorldGen.annual_temp_at(probe, SEED)
	print("  裁切窗口：窗口(0,0) 降水 %.0fmm／%.2f℃ ／ 窗口(18,18) %.0fmm／%.2f℃ ／ 切回(0,0) %.0fmm／%.2f℃"
		% [mm_home, t_home, mm_far, t_far, mm_back, t_back])
	_check(absf(t_far - t_home) > 1.0,
		"换个裁切窗口 → 同一格**温度**也不同（%.2f vs %.2f℃）→ 裁到的确实是另一片地方"
		% [t_far, t_home])
	# ⚠️ 比**绝对降水（毫米）**，不要比"归一化 0~1"的那个 —— 后者会被钳在上限（实测 1.000/1.000），
	#    拿被钳过的值判"有没有变化"是没有意义的。
	_check(absf(mm_far - mm_home) > 1.0,
		"换个裁切窗口 → 同一格**降水**也不同（%.0f vs %.0f mm）" % [mm_far, mm_home])
	_check(absf(mm_back - mm_home) < 0.001 and absf(t_back - t_home) < 0.0001,
		"切回原窗口 → **逐位一致**（降水 %.4f vs %.4f mm；温度 %.4f vs %.4f℃）"
		% [mm_back, mm_home, t_back, t_home])

	# ⑤d W5：**按水陆比挑裁切窗口**（用户："裁切的时候只要满足水陆比例就足够了，
	#    无论冷暖是否俱全，都是可接受的"）→ 水陆比是挑窗口的**唯一硬指标**。
	var fn_elev := func(cc: Vector2i) -> float:
		return WorldGen.elevation_of(cc, SEED)
	var lf_home := Climate.land_fraction(Vector2.ZERO, fn_elev)
	var best_crop := Climate.pick_crop(fn_elev)
	var lf_best := Climate.land_fraction(best_crop, fn_elev)
	print("  水陆比：不裁 (0,0) 陆地 %.0f%% ；挑出来的窗口 %s 陆地 %.0f%%（合格区间 %.0f%%~%.0f%%）"
		% [lf_home * 100.0, str(best_crop), lf_best * 100.0,
			Climate.LAND_MIN_OK * 100.0, Climate.LAND_MAX_OK * 100.0])
	_check(lf_best >= Climate.LAND_MIN_OK - 0.0001 and lf_best <= Climate.LAND_MAX_OK + 0.0001,
		"挑出来的窗口**水陆比合格**（陆地 %.0f%%）" % (lf_best * 100.0))
	_check(absf(lf_best - 0.5) <= absf(lf_home - 0.5) + 0.0001,
		"挑出来的窗口**不比不裁差**（离 50%% 的距离：%.3f vs %.3f）" % [absf(lf_best - 0.5), absf(lf_home - 0.5)])

	# ⑤e **尺度不变性实验**（另一个 AI 指出的关键一条）——**只诊断、不断言**。
	#   目的：把"降水**尺度依赖**"和"毫米标定错"这两件事**分开**。
	#   做法：固定**原型图上的同一个物理点** D。采样时会 +crop，所以：
	#     crop=0 → 取世界坐标 p=D；crop=c → 取 p=D−c。两种读法拿到的是**同一个物理点**。
	#   （我上一轮拿"窗口(0,0) vs 窗口(18,18) 的同一个**世界格**"比较 —— 那根本是两个不同地方，
	#     什么都证明不了。这个实验才是对的。）
	var d_point := Vector2(6.0, 6.0)
	var crop_c := Vector2(24.0, 12.0)
	var raws: Array = []
	var lines: Array = []
	for grid_n in [128, 192, 384]:
		Climate.set_field_grid(grid_n)
		Climate.set_crop(Vector2.ZERO)
		var field_a := WorldGen.climate_for(SEED)
		var raw_a := Climate.precip_at(Hex.pixel_to_axial(d_point, 1.0), 3, field_a)
		Climate.set_crop(crop_c)
		var field_b := WorldGen.climate_for(SEED)
		var raw_b := Climate.precip_at(Hex.pixel_to_axial(d_point - crop_c, 1.0), 3, field_b)
		raws.append(raw_a)
		lines.append("      栅格 %3d：同一点同月 raw = %.5f（crop 0）／ %.5f（crop 24,12）→ %.2f 倍"
			% [grid_n, raw_a, raw_b, raw_b / maxf(raw_a, 0.0000001)])
	Climate.set_field_grid(Climate.FIELD_GRID)     # 恢复默认，别影响后面的用例
	Climate.set_crop(Vector2.ZERO)
	print("  尺度不变性实验（同一物理点、同一月，raw 降水随**栅格分辨率**怎么变）：")
	for line_txt in lines:
		print(line_txt)
	var vmax := 0.0
	var vmin := 99999.0
	for v in raws:
		vmax = maxf(vmax, float(v))
		vmin = minf(vmin, float(v))
	print("      → 跨分辨率的 raw 最大/最小 = **%.2f 倍**（接近 1 = 尺度无关；明显偏离 = 尺度依赖）"
		% (vmax / maxf(vmin, 0.0000001)))

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