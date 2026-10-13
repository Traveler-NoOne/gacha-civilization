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

	# ⑦ 扩张：不改动已有地块；新加的那一格 = 同种子同坐标的「标准世界」
	GameState.new_game(20240607)
	var old_tiles: Dictionary = (GameState.state["tiles"] as Dictionary).duplicate(true)
	var added_n: int = WorldGen.expand_map(GameState.state, 1)
	_check(added_n > 0, "扩张加进来 %d 格" % added_n)
	var unchanged := true
	for k in old_tiles.keys():
		if not (GameState.state["tiles"] as Dictionary).has(k) \
				or JSON.stringify((GameState.state["tiles"] as Dictionary)[k]) != JSON.stringify(old_tiles[k]):
			unchanged = false
	_check(unchanged, "扩张不会改动已有地块（逐格逐字段相同）")
	var new_key := ""
	for k in GameState.state["tiles"].keys():
		if not old_tiles.has(k):
			new_key = str(k)
			break
	_check(new_key != "", "找到了扩张出来的新格：%s" % new_key)
	if new_key != "":
		var from_world: Dictionary = WorldGen._make_tile(WorldGen.coord_of(new_key), 20240607)
		_check(JSON.stringify((GameState.state["tiles"] as Dictionary)[new_key]) == JSON.stringify(from_world),
			"新格与「标准世界」同坐标一致（纯函数，与生成顺序无关）")

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
	print("  资源与地貌不符：%d 处" % mismatched.size())
	_check(mismatched.is_empty(), "资源都长在对应地貌上（木头←森林、煤/铜←山丘）")

	_check(capd9 <= edge9, "出生点不贴边境（离中心 %d ≤ %d）" % [capd9, edge9])
	_check(res9 >= 3, "出生点附近不贫瘠（资源点 %d ≥ 3）" % res9)

	print("  相邻格同地形比例：%.0f%%（随机撒点约 20%%，成片则应明显更高）" % (ratio * 100.0))
	_check(ratio > 0.35, "地形是成片的（相邻同地形 %.0f%% > 35%%，随机撒点约 20%%）" % (ratio * 100.0))


	print("== 结果：%s ==" % ("全部通过" if fails == 0 else "%d 项失败" % fails))
	get_tree().quit(1 if fails > 0 else 0)



