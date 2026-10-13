extends Node

## 随机数种子专项自检（v1.8.20.8）
##
## 只覆盖本次改动，不碰别的东西：
##   ① new_game(种子) → _rng 按这个种子播
##   ② 同种子两局 → 世界 + 随机数流都一致（可复现）
##   ③ 不同种子 → 随机数流不同（种子真的在起作用）
##   ④ new_game() 不传种子 → 取时钟种子（"每局都是新的"没有被破坏）
##   ⑤ 存档 → 搅乱 → 读档 → 种子恢复（读档后能接着同一条流）
##
## 跑法（项目根目录）：
##   godot --headless --path . res://tests/seed_check.tscn
##
## ⚠️ 必须用**场景**跑，不能用 --script —— 后者不注册 autoload，
## 任何引用 GameState 这种单例的生产脚本都编译不过（world_gen.gd 就编译不过，
## 于是 new_game() 里的世界生成整个不执行，"世界"类断言会假通过）。这一点踩过。


var fails := 0
var slot := 0    # 0 号槽是本项目约定的测试槽


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  [ok] " + what)
	else:
		fails += 1
		print("  [FAIL] " + what)


func _ready() -> void:

	print("== 随机数种子专项自检 ==")


	# ① 新游戏按自己的种子播
	GameState.new_game(20240607)
	_check(int(GameState._rng.seed) == 20240607, "new_game(20240607) 后 _rng.seed 就是 20240607（实际 %d）" % int(GameState._rng.seed))

	# ② 同种子两局：世界 + 前 5 个随机数都一致
	var world_a := JSON.stringify(GameState.state["tiles"])
	var draws_a := []
	for i in 5:
		draws_a.append(GameState._rng.randf())
	GameState.new_game(20240607)
	var world_b := JSON.stringify(GameState.state["tiles"])
	var draws_b := []
	for i in 5:
		draws_b.append(GameState._rng.randf())
	_check(world_a == world_b, "同种子两局的世界一致")
	_check(draws_a == draws_b, "同种子两局的随机数流一致（这 5 个数逐位相同）")

	# ③ 换种子要换数
	GameState.new_game(20240608)
	_check(int(GameState._rng.seed) == 20240608, "换种子后 _rng.seed 跟着换（实际 %d）" % int(GameState._rng.seed))
	_check(GameState._rng.randf() != draws_a[0], "不同种子的第一个随机数不同")

	# ④ 不传种子 → 时钟种子，且与 state["seed"] 一致
	GameState.new_game()
	var s1 := int(GameState._rng.seed)
	_check(s1 != 0 and s1 == int(GameState.state["seed"]), "不传种子时取时钟种子、且与 state['seed'] 一致（%d）" % s1)

	# ⑤ 存档 → 搅乱 → 读档 → 种子恢复
	var want := s1
	var saved: bool = GameState.save_to_slot(slot)

	_check(saved, "存档到 %d 号测试槽" % slot)
	GameState.new_game(1)
	_check(int(GameState._rng.seed) == 1, "读档前先把 _rng 搅乱（现在是 1）")
	var ok_load: bool = GameState.load_from_slot(slot)

	_check(ok_load, "读档")
	_check(int(GameState._rng.seed) == want, "读档后 _rng.seed 恢复成本局种子（期望 %d，实际 %d）" % [want, int(GameState._rng.seed)])
	GameState.delete_slot(slot)   # 测试槽用完就清掉，不留垃圾

	# ⑥ 世界生成：地形/资源由「坐标 + 世界种子」决定（v1.8.20.9 新做的行为）
	GameState.new_game(20240607)
	var world_seed_a := JSON.stringify(GameState.state["tiles"])
	var terrain_a := {}
	for k in GameState.state["tiles"].keys():
		var tn := str((GameState.state["tiles"][k] as Dictionary).get("terrain", ""))
		terrain_a[tn] = int(terrain_a.get(tn, 0)) + 1
	GameState.new_game(20240608)
	var world_seed_c := JSON.stringify(GameState.state["tiles"])
	var terrain_c := {}
	for k in GameState.state["tiles"].keys():
		var tn2 := str((GameState.state["tiles"][k] as Dictionary).get("terrain", ""))
		terrain_c[tn2] = int(terrain_c.get(tn2, 0)) + 1
	_check(world_seed_a != world_seed_c, "换种子 → 世界地图不一样（v1.8.20.9 之前两者相同）")
	_check(terrain_a != terrain_c, "换种子 → 地形分布也跟着变")
	GameState.new_game()
	var terrain_d := {}
	for k in GameState.state["tiles"].keys():
		var tn3 := str((GameState.state["tiles"][k] as Dictionary).get("terrain", ""))
		terrain_d[tn3] = int(terrain_d.get(tn3, 0)) + 1
	_check(terrain_a != terrain_d, "不传种子（取时钟）→ 每局也是不同的世界")

	# ⑧ v1.8.21 第 1 段：地形应当是"成片"的，而不是随机撒点。
	#    衡量方法：相邻格同地形的比例。纯随机（5 种地形）期望约 20%；噪声地图应显著更高。
	GameState.new_game(20240607)
	var tiles8: Dictionary = GameState.state["tiles"]
	var terrain_count := {}
	var same := 0
	var pairs := 0
	for k8 in tiles8.keys():
		var t8: Dictionary = tiles8[k8]
		var tn8 := str(t8.get("terrain", ""))
		terrain_count[tn8] = int(terrain_count.get(tn8, 0)) + 1
		var c8 := WorldGen.coord_of(str(k8))
		for nb: Vector2i in Hex.neighbors(c8):
			var nk8 := WorldGen.key_of(nb)
			if not tiles8.has(nk8):
				continue
			pairs += 1
			if str((tiles8[nk8] as Dictionary).get("terrain", "")) == tn8:
				same += 1
	var ratio := 0.0
	if pairs > 0:
		ratio = float(same) / float(pairs)
	print("  地形分布：%s" % str(terrain_count))
	var cover_count := {}
	for k9 in tiles8.keys():
		var cv9 := str((tiles8[k9] as Dictionary).get("cover", ""))
		cover_count[cv9] = int(cover_count.get(cv9, 0)) + 1
	print("  地物分布：%s" % str(cover_count))
	var covers_seen := 0
	for key_c in cover_count.keys():
		if str(key_c) != "":
			covers_seen += 1
	_check(covers_seen >= 3, "地物至少出现 3 种（实际 %d 种）" % covers_seen)

	# ⑨ 出生点：应当是"资源相对丰富且不贴边境"，而不是固定在世界中心
	var cap9 := str(GameState.state["capital"])
	var capc9 := WorldGen.coord_of(cap9)
	var capd9 := Hex.distance(capc9, Vector2i.ZERO)
	var edge9 := int(float(Consts.MAP_START_RADIUS) * 0.78)
	var res9 := 0
	for nb9: Vector2i in Hex.spiral(3):
		var nk9 := WorldGen.key_of(capc9 + nb9)
		if not tiles8.has(nk9):
			continue
		if str((tiles8[nk9] as Dictionary).get("resource", "")) != "":
			res9 += 1
	print("  出生点：%s（离中心 %d 格 / 上限 %d；3 格内资源点 %d 个）" % [cap9, capd9, edge9, res9])

	# ⑩ 资源必须长在"该长的地貌"上：木头←森林地物；煤/铜←山丘。资源分布也打出来看看丰不丰。
	var res_count := {}
	var mismatched := []
	for k10 in tiles8.keys():
		var t10: Dictionary = tiles8[k10]
		var r10 := str(t10.get("resource", ""))
		res_count[r10] = int(res_count.get(r10, 0)) + 1
		if r10 == "wood" and str(t10.get("cover", "")) != "forest":
			mismatched.append("%s(木头但cover=%s)" % [k10, str(t10.get("cover", ""))])
		elif (r10 == "coal" or r10 == "copper") and str(t10.get("terrain", "")) != "hill":
			mismatched.append("%s(%s但terrain=%s)" % [k10, r10, str(t10.get("terrain", ""))])
	print("  资源分布：%s" % str(res_count))

	# ⑫ v1.8.21 第 4 段：侵蚀（固定最大范围的后处理）—— 看它确实削低了格子
	var eroded_n := 0
	var max_drop := 0.0
	for k12 in tiles8.keys():
		var c12 := WorldGen.coord_of(str(k12))
		var raw12 := WorldGen.elevation_of(c12, 20240607)
		var er12 := WorldGen.eroded_elevation_of(c12, 20240607)
		if er12 < raw12 - 0.0001:
			eroded_n += 1
			max_drop = maxf(max_drop, raw12 - er12)
	print("  侵蚀：被削低的格子 %d 个（最大削低 %.3f）" % [eroded_n, max_drop])

	# ⑬ v1.8.21：河流（蓝色描边用的那批格子）—— 要有，而且大致连成链（不是散点）
	var river_n := 0
	var river_with_nb := 0
	var river_in_water := 0        # ★ 用户 2026-10-13 报的 bug：河跑到海里去了
	for k13 in tiles8.keys():
		if not bool((tiles8[k13] as Dictionary).get("river", false)):
			continue
		river_n += 1
		if str((tiles8[k13] as Dictionary).get("terrain", "")) == "water":
			river_in_water += 1
		var c13 := WorldGen.coord_of(str(k13))
		for nb13: Vector2i in Hex.neighbors(c13):
			var t13: Variant = tiles8.get(WorldGen.key_of(nb13))
			if t13 != null and bool((t13 as Dictionary).get("river", false)):
				river_with_nb += 1
				break
	var chain_ratio := 0.0
	if river_n > 0:
		chain_ratio = float(river_with_nb) / float(river_n)
	print("  河流格：%d 个（其中 %.0f%% 有相邻河流格；**在海里的 %d 个**）"
		% [river_n, chain_ratio * 100.0, river_in_water])
	_check(river_n > 0, "存在河流格（要用来画蓝色描边）")
	_check(river_in_water == 0, "**没有一格河在海里**（实际 %d 个）" % river_in_water)

	# ⑭ W4（文明6式）：河道**折成边路径**后，**每相邻两条边必须共顶点**（= 用户"头尾编号"那句话）。
	#    这条断言把"视觉上会不会断"变成可无头测的几何性质 —— 不靠眼睛、也不受镜头限制。
	var rpaths: Array = WorldGen.river_paths(int(GameState.state.get("seed", 0)))
	var path_edges := 0
	var bad_pairs := 0
	var longest_chain := 0
	for chain in rpaths:
		var ch: Array = chain
		path_edges += ch.size()
		longest_chain = maxi(longest_chain, ch.size())
		for i in range(1, ch.size()):
			if not WorldGen.edges_adjacent(str(ch[i - 1]), str(ch[i])):
				bad_pairs += 1
	print("  河道边路径：%d 条链、共 %d 条边、最长一条 %d 条边；**相邻边不共顶点 %d 处**"
		% [rpaths.size(), path_edges, longest_chain, bad_pairs])
	_check(rpaths.size() > 0, "存在河道边路径（%d 条链）" % rpaths.size())
	_check(bad_pairs == 0, "**每相邻两条边都共顶点**（违例 %d）→ 折好了，视觉上不会断" % bad_pairs)
	if river_n > 0:
		# W4（2026-10-13）：**河已经顺着流向补到入海**，所以现在**可以**要求它连成链了。
		# 原先不能要求，是因为河只按"流量前 2%"挑、下游掉出前 2% 就断（那时只有 ~43% 有邻居）。
		_check(chain_ratio >= 0.25, "河格彼此相邻的比例明显高于随机（%.0f%% ≥ 25%%）" % (chain_ratio * 100.0))
		_check(chain_ratio >= 0.80, "**河连成链**（有相邻河格的比例 %.0f%% ≥ 80%%）" % (chain_ratio * 100.0))


	_check(eroded_n > 0, "侵蚀确实削低了部分格子（河谷）")
	_check(max_drop > 0.001, "削低的幅度可见（最大 %.3f > 0.001）" % max_drop)


	# ⑪ v1.8.21 第 3 段：大陆形状 —— 中心应当基本是陆，初始半径边缘应当基本是海
	var edge_tiles := 0
	var edge_water := 0
	var core_tiles := 0
	var core_water := 0
	for k11 in tiles8.keys():
		var d11 := Hex.distance(WorldGen.coord_of(str(k11)), Vector2i.ZERO)
		var is_w := str((tiles8[k11] as Dictionary).get("terrain", "")) == "water"
		if d11 >= Consts.MAP_START_RADIUS - 1:
			edge_tiles += 1
			if is_w:
				edge_water += 1
		elif d11 <= 3:
			core_tiles += 1
			if is_w:
				core_water += 1
	var edge_ratio := 0.0
	if edge_tiles > 0:
		edge_ratio = float(edge_water) / float(edge_tiles)
	var core_ratio := 0.0
	if core_tiles > 0:
		core_ratio = float(core_water) / float(core_tiles)
	print("  大陆形状：边缘含水 %.0f%%（%d/%d）；中心含水 %.0f%%（%d/%d）" % [
		edge_ratio * 100.0, edge_water, edge_tiles, core_ratio * 100.0, core_water, core_tiles])
	_check(edge_ratio >= 0.60, "边缘基本是海（含水 %.0f%% ≥ 60%%）" % (edge_ratio * 100.0))
	_check(core_ratio <= 0.20, "中心基本是陆（含水 %.0f%% ≤ 20%%）" % (core_ratio * 100.0))

	print("  资源与地貌不符：%d 处" % mismatched.size())
	_check(mismatched.is_empty(), "资源都长在对应地貌上（木头←森林、煤/铜←山丘）")

	_check(capd9 <= edge9, "出生点不贴边境（离中心 %d ≤ %d）" % [capd9, edge9])
	_check(res9 >= 3, "出生点附近不贫瘠（资源点 %d ≥ 3）" % res9)

	print("  相邻格同地形比例：%.0f%%（随机撒点约 20%%，成片则应明显更高）" % (ratio * 100.0))
	_check(ratio > 0.35, "地形是成片的（相邻同地形 %.0f%% > 35%%，随机撒点约 20%%）" % (ratio * 100.0))


	print("== 结果：%s ==" % ("全部通过" if fails == 0 else "%d 项失败" % fails))
	get_tree().quit(1 if fails > 0 else 0)



