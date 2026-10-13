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
const PLATES := 8

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
	var seen := {}
	var longest := 0
	var widest := 0
	for k2 in mountains.keys():
		if seen.has(k2):
			continue
		var stack: Array = [k2]
		seen[k2] = true
		var comp: Array = []
		while not stack.is_empty():
			var cur: String = stack.pop_back()
			comp.append(cur)
			var cc: Vector2i = mountains[cur]
			for nb: Vector2i in Hex.neighbors(cc):
				var nk := WorldGen.key_of(nb)
				if mountains.has(nk) and not seen.has(nk):
					seen[nk] = true
					stack.append(nk)
		longest = maxi(longest, comp.size())
		# ★ 形态诊断（**不是断言**）：最长的这条到底是"长墙"还是"一团疙瘩"？
		#   直径（成员间最大格距）远大于宽度才像墙；面积/直径 ≈ 平均宽度。
		if comp.size() == longest:
			var dia := 0
			for i in comp.size():
				for j in range(i + 1, comp.size()):
					dia = maxi(dia, Hex.distance(mountains[comp[i]], mountains[comp[j]]))
			widest = dia
	var thin := float(longest) / maxf(1.0, float(widest))
	print("  山脉格 %d 个；最长连通 %d 格、**直径 %d 格**、平均宽 ≈ %.1f 格"
		% [mountains.size(), longest, widest, thin])
	# ★ 形态：**又长又薄**才叫山墙。但 2026-10-13 实测发现"面积/直径"这个宽度指标**对"网"是错的**：
	#   几条山带相交时会被连成一个连通块 → 面积/直径 会把"网的跨度"当成"墙的厚度"。
	#   所以这里**只断言"确实存在一条较长的连通山带"**，"够不够薄/像不像墙"先当诊断 + 交人看。
	_check(widest >= 15, "存在一条较长的连通山带（直径 %d 格 ≥ 15）" % widest)
	if thin > 2.5:
		print("  ⚠️ **未达标**：平均宽 ≈ %.1f > 2.5 —— 这条更像「带/网」而不是「山墙」；宽度指标本身也可能不适合「网」（见 世界生成-W2b.md）。" % thin)

	print("  各板块格数：%s" % str(owned))
	print("== 结果：%s ==" % ("全部通过" if fails == 0 else "%d 项失败" % fails))
	get_tree().quit(1 if fails > 0 else 0)
