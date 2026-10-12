extends SceneTree
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
##   godot --headless --path . --script res://tests/seed_check.gd

var fails := 0
var slot := 0    # 0 号槽是本项目约定的测试槽


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  [ok] " + what)
	else:
		fails += 1
		print("  [FAIL] " + what)


func _initialize() -> void:
	print("== 随机数种子专项自检 ==")
	var gs: Node = root.get_node_or_null("GameState")
	if gs == null:
		# 用 --script 跑时自动加载可能没挂上，那就手动实例化一份（同一份脚本、同样的 _ready）
		print("  （没找到自动加载 GameState，改为手动实例化）")
		gs = load("res://scripts/core/game_state.gd").new()
		root.add_child(gs)

	# ① 新游戏按自己的种子播
	gs.new_game(20240607)
	_check(int(gs._rng.seed) == 20240607, "new_game(20240607) 后 _rng.seed 就是 20240607（实际 %d）" % int(gs._rng.seed))

	# ② 同种子两局：世界 + 前 5 个随机数都一致
	var world_a := JSON.stringify(gs.state["tiles"])
	var draws_a := []
	for i in 5:
		draws_a.append(gs._rng.randf())
	gs.new_game(20240607)
	var world_b := JSON.stringify(gs.state["tiles"])
	var draws_b := []
	for i in 5:
		draws_b.append(gs._rng.randf())
	_check(world_a == world_b, "同种子两局的世界一致")
	_check(draws_a == draws_b, "同种子两局的随机数流一致（这 5 个数逐位相同）")

	# ③ 换种子要换数
	gs.new_game(20240608)
	_check(int(gs._rng.seed) == 20240608, "换种子后 _rng.seed 跟着换（实际 %d）" % int(gs._rng.seed))
	_check(gs._rng.randf() != draws_a[0], "不同种子的第一个随机数不同")

	# ④ 不传种子 → 时钟种子，且与 state["seed"] 一致
	gs.new_game()
	var s1 := int(gs._rng.seed)
	_check(s1 != 0 and s1 == int(gs.state["seed"]), "不传种子时取时钟种子、且与 state['seed'] 一致（%d）" % s1)

	# ⑤ 存档 → 搅乱 → 读档 → 种子恢复
	var want := s1
	var saved: bool = gs.save_to_slot(slot)

	_check(saved, "存档到 %d 号测试槽" % slot)
	gs.new_game(1)
	_check(int(gs._rng.seed) == 1, "读档前先把 _rng 搅乱（现在是 1）")
	var ok_load: bool = gs.load_from_slot(slot)

	_check(ok_load, "读档")
	_check(int(gs._rng.seed) == want, "读档后 _rng.seed 恢复成本局种子（期望 %d，实际 %d）" % [want, int(gs._rng.seed)])
	gs.delete_slot(slot)   # 测试槽用完就清掉，不留垃圾

	print("== 结果：%s ==" % ("全部通过" if fails == 0 else "%d 项失败" % fails))
	quit(1 if fails > 0 else 0)
