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

	# ⑤ S2：板块对高度的影响 —— **逐格符号断言**（"山脉/海沟长在正确一侧"的护栏）
	#    问"函数实际会用到哪条边界"（boundary_for），再验它的结果是正还是负。
	var n_conv := 0
	var n_div := 0
	var n_none := 0
	var bad_conv := 0
	var bad_div := 0
	var bad_none := 0
	var max_abs := 0.0
	for cell: Vector2i in Hex.spiral(Consts.MAP_START_RADIUS):
		var eff := P.effect_at(cell, 0.6, SEED, PLATES)     # base=0.6 → 当作**陆地**
		max_abs = maxf(max_abs, absf(eff))
		var bd := P.boundary_for(cell, SEED, PLATES)
		match int(bd["kind"]):
			P.Kind.CONVERGENT:
				n_conv += 1
				if eff <= 0.0:
					bad_conv += 1
			P.Kind.DIVERGENT:
				n_div += 1
				if eff >= 0.0:
					bad_div += 1
			_:
				n_none += 1
				if absf(eff) > 0.000001:
					bad_none += 1
	print("  板块效应（陆地基准）：相向 %d 格 / 相离 %d 格 / 无边 %d 格；最大幅度 %.4f"
		% [n_conv, n_div, n_none, max_abs])
	_check(n_conv > 0 and n_div > 0, "两种边界附近都取到了样本")
	_check(bad_conv == 0, "相向边界附近的陆地格**全部被抬高**（造山）→ 违例 %d" % bad_conv)
	_check(bad_div == 0, "相离边界附近的陆地格**全部被压低**（裂谷）→ 违例 %d" % bad_div)
	_check(bad_none == 0, "没有边界的格子**完全不受板块影响** → 违例 %d" % bad_none)
	_check(max_abs <= P.PLATE_AMPLITUDE + 0.0001,
		"板块效应幅度不超过振幅上限 %.2f（实际最大 %.4f）" % [P.PLATE_AMPLITUDE, max_abs])
	# 海陆基准换一下，符号应当反过来（海侧相向 → 海沟、海侧相离 → 洋中脊）
	_check(P.effect_at(Vector2i(0, 0), 0.2, SEED, PLATES) == -P.effect_at(Vector2i(0, 0), 0.8, SEED, PLATES)
		or P.boundary_for(Vector2i(0, 0), SEED, PLATES)["kind"] == P.Kind.NONE,
		"同一格：陆地侧与海洋侧的符号相反（山 / 沟）")

	print("  各板块格数：%s" % str(owned))
	print("== 结果：%s ==" % ("全部通过" if fails == 0 else "%d 项失败" % fails))
	get_tree().quit(1 if fails > 0 else 0)
