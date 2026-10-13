extends Node
## 板块算法（S1）专项自检 —— 世界生成 W2 的第一步。
##
## 这个模块**还没接进游戏地图**，所以本自检只验它自己的性质：
##   ① 确定性（同参数两次逐位一致）
##   ② 每个板块都真的分到了地（没有空板块）
##   ③ 边界三类都出现过，且边界格占比在合理区间
##   ④ 分类函数本身：合成用例（相向 / 相离 / 纯切向）必须分别得到三种结论
##
## 跑法（项目根目录）：
##   godot --headless --path . res://tests/plate_check.tscn
## ⚠️ 必须用场景跑（--script 不注册 autoload）。

const P := preload("res://scripts/core/plates.gd")

const SEED := 20240607
const SIZE := 96          # 自检用小图，快
const PLATES := 5          # 跟 WorldGen.PLATE_COUNT 保持一致（板越少边界越长）

var fails := 0


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  [ok] " + what)
	else:
		fails += 1
		print("  [FAIL] " + what)


func _ready() -> void:
	print("== 板块算法（S1）专项自检 ==")

	var a := P.build(SEED, SIZE, PLATES)
	var b := P.build(SEED, SIZE, PLATES)

	# ① 确定性
	_check(str(a["plate"]) == str(b["plate"]), "同参数两次 → plate 逐位一致")
	_check(str(a["kind"]) == str(b["kind"]), "同参数两次 → kind 逐位一致")
	_check(str(a["stress"]) == str(b["stress"]), "同参数两次 → stress 逐位一致")
	var c := P.build(SEED + 1, SIZE, PLATES)
	_check(str(a["seeds"]) != str(c["seeds"]), "换种子 → 板块位置跟着变")

	# ② 每个板块都分到地
	var owned := {}
	for v in (a["plate"] as PackedInt32Array):
		owned[int(v)] = int(owned.get(int(v), 0)) + 1
	var empty := 0
	for i in PLATES:
		if not owned.has(i) or int(owned[i]) == 0:
			empty += 1
	_check(empty == 0, "每个板块都分到了地（空板块 %d 个）" % empty)

	# ③ 边界统计
	var kinds := P.count_kinds(a)
	var total := SIZE * SIZE
	var border := total - int(kinds.get(int(P.Kind.NONE), 0))
	var ratio := float(border) / float(total)
	var conv := int(kinds.get(int(P.Kind.CONVERGENT), 0))
	var divg := int(kinds.get(int(P.Kind.DIVERGENT), 0))
	var tran := int(kinds.get(int(P.Kind.TRANSFORM), 0))
	print("  边界格：合计 %d（%.1f%%，其中 相向 %d / 相离 %d / 错动 %d）"
		% [border, ratio * 100.0, conv, divg, tran])
	_check(conv > 0 and divg > 0 and tran > 0, "三种边界类型都出现了")
	_check(ratio > 0.02 and ratio < 0.60, "边界格占比在合理区间（%.1f%%）" % (ratio * 100.0))

	# ④ 分类函数本身（合成用例，不依赖随机）
	var east := Vector2(1, 0)
	_check(P.classify(Vector2(1, 0), east) == P.Kind.CONVERGENT,
		"合成：a 向右、b 不动 → 法向分量为正 → 相向")
	_check(P.classify(Vector2(-1, 0), east) == P.Kind.DIVERGENT,
		"合成：a 向左、b 不动 → 法向分量为负 → 相离")
	_check(P.classify(Vector2(0, 1), east) == P.Kind.TRANSFORM,
		"合成：纯切向错动 → 转换断层")

	print("  各板块格数：%s" % str(owned))

	# ⑤ W2b：板块效应 —— **按地壳类型**的符号断言
	var n_coll := 0
	var n_sub_sea := 0
	var n_sub_land := 0
	var bad_coll := 0
	var bad_sub_sea := 0
	var bad_sub_land := 0
	var nz_coll := 0
	var nz_sub_sea := 0
	var nz_sub_land := 0
	var max_abs := 0.0
	var crust := WorldGen.crust_for(SEED, PLATES)
	var n_land_plate := 0
	for v in crust:
		if int(v) == P.CRUST_CONTINENTAL:
			n_land_plate += 1
	print("  地壳（按板块覆盖地块的基础高程均值判）：陆壳板 %d / 洋壳板 %d" % [n_land_plate, PLATES - n_land_plate])
	for cell: Vector2i in Hex.spiral(Consts.MAP_START_RADIUS):
		var eff := P.effect_at(cell, SEED, crust, PLATES)
		max_abs = maxf(max_abs, absf(eff))
		var bd := P.boundary_for(cell, SEED, PLATES)
		if int(bd["kind"]) != P.Kind.CONVERGENT:
			continue
		var my_land := int(crust[int(bd["mine"])]) == P.CRUST_CONTINENTAL
		var their_land := int(crust[int(bd["other"])]) == P.CRUST_CONTINENTAL
		if my_land and their_land:
			n_coll += 1
			if eff < 0.0:
				bad_coll += 1
			if absf(eff) > 0.000001:
				nz_coll += 1
		elif not my_land and their_land:
			n_sub_sea += 1
			if eff > 0.0:
				bad_sub_sea += 1
			if absf(eff) > 0.000001:
				nz_sub_sea += 1
		elif my_land and not their_land:
			n_sub_land += 1
			if eff < 0.0:
				bad_sub_land += 1
			if absf(eff) > 0.000001:
				nz_sub_land += 1
	print("  相向边界（按地壳）：陆-陆碰撞 %d 格 / 洋侧俯冲 %d 格 / 陆侧山链 %d 格；最大幅度 %.4f"
		% [n_coll, n_sub_sea, n_sub_land, max_abs])
	print("  其中**真的产生非零效应**：碰撞 %d / 海沟 %d / 山链 %d（带外为 0 是正常的）"
		% [nz_coll, nz_sub_sea, nz_sub_land])
	_check(n_coll + n_sub_sea + n_sub_land > 0, "相向边界取到了样本")
	_check(bad_coll == 0, "陆-陆碰撞：凡有非零效应的一律**抬高**（山系）→ 违例 %d" % bad_coll)
	_check(bad_sub_sea == 0, "洋-陆俯冲：凡有非零效应的一律**压低**（海沟）→ 违例 %d" % bad_sub_sea)
	_check(bad_sub_land == 0, "洋-陆俯冲：凡有非零效应的一律**抬高**（沿岸山链）→ 违例 %d" % bad_sub_land)
	_check(nz_coll > 0 and nz_sub_sea > 0 and nz_sub_land > 0,
		"三类相互作用**都真的产生了非零效应**（各自 %d / %d / %d 格）" % [nz_coll, nz_sub_sea, nz_sub_land])
	_check(max_abs <= P.AMP_COLLISION + 0.0001,
		"振幅不超过分级上限 %.2f（实际 %.4f）" % [P.AMP_COLLISION, max_abs])

	# ★ 形态断言：**连续山脉格的最长连通长度** —— 把"喜马拉雅/科迪勒拉那种长墙"变成可测的
	#   （W2 之后最长只有 5~6 格；W2b 的"造山带成型"就是要把它拉成几十格）
	var mountains := {}
	for cell2: Vector2i in Hex.spiral(Consts.MAP_START_RADIUS):
		var e2 := WorldGen.elevation_of(cell2, SEED)
		var m2 := WorldGen.moisture_of(cell2, SEED)
		if str(WorldGen.biome_of(e2, m2)["terrain"]) == "mountain":
			mountains[WorldGen.key_of(cell2)] = cell2
	# ★ 形态（**第二版指标**）：**按"哪条边界"分组**再量 长度 × 宽度。
	#   第一版用"面积/直径"，对**网**是错的：几条带相交会连成一个连通块，
	#   于是把"网的跨度"当成"墙的厚度"（实测平均宽 6.1，其实是双带 + 交叉）。
	var groups := {}
	for kg in mountains.keys():
		var cg: Vector2i = mountains[kg]
		# ⚠️ 只统计"真的被板块效应顶过线"的山格 —— 否则**本来就自然很高的山格**也会被算进来，
		#    它们离边界很远，会把"宽度"撑大（实测宽度被撑到 5，而带宽其实只有 2）。
		if absf(P.effect_at(cg, SEED, crust, PLATES)) <= 0.000001:
			continue
		var bg := P.boundary_for(cg, SEED, PLATES)
		if int(bg["kind"]) == P.Kind.NONE:
			continue
		var pa := int(bg["mine"])
		var pb := int(bg["other"])
		var gkey := "%d-%d-%d" % [mini(pa, pb), maxi(pa, pb), int(bg["kind"])]
		if not groups.has(gkey):
			groups[gkey] = []
		(groups[gkey] as Array).append({"c": cg, "d": int(bg["dist"])})
	var best_len := 0
	var best_w := 99
	var best_key := ""
	for gk in groups.keys():
		var arr: Array = groups[gk]
		var dmin := 99
		var dmax := 0
		for it in arr:
			dmin = mini(dmin, int(it["d"]))
			dmax = maxi(dmax, int(it["d"]))
		var w := dmax - dmin + 1
		var ln := int(round(float(arr.size()) / float(w)))
		if ln > best_len:
			best_len = ln
			best_w = w
			best_key = gk
	print("  按边界分组：共 %d 组；最长一组（键 %s）= **长约 %d 格 × 宽 %d 格**"
		% [groups.size(), best_key, best_len, best_w])
	_check(best_len >= 25, "存在一条**沿某条边界的**长山带（长约 %d 格 ≥ 25）" % best_len)
	_check(best_w <= 3, "该山带**够薄**（宽 %d 格 ≤ 3）" % best_w)

	print("  各板块格数：%s" % str(owned))
	print("== 结果：%s ==" % ("全部通过" if fails == 0 else "%d 项失败" % fails))
	get_tree().quit(1 if fails > 0 else 0)
