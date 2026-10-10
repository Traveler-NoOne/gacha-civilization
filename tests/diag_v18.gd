extends Node
const U := preload("res://tests/test_util.gd")
## v1.8.3 专项自检：政事系统（数据 + 队列推进 + 征兵作为第一条政事）
##
## 覆盖：
##   1. 政事表可读
##   2. 前置不满足时拒绝排入
##   3. 满足后能排入，字段初值正确
##   4. 队列按**行政点数**推进（吃的是当期入账的量）
##   5. 攒够后完成 → 真的征到兵、且进驻首都
##   6. 效果无法执行时**退还**已投入的行政点数（不吞玩家的点数）
##   7. 存档往返：队列进度不丢
##   8. 升级：SAVE_VERSION 已随本段 +1
## 用法：godot --headless --path <项目> res://tests/diag_v18.tscn

var suite := U.reporter("v1.8.3 政事系统")
func _ready() -> void:
	await get_tree().process_frame

	print("== 1. 政事表 ==")
	var d := DecreeDB.find(DecreeDB.RECRUIT)
	print("  第一条政事：%s｜消耗行政点数 %.1f" % [str(d.get("name", "?")), float(d.get("cost", 0.0))])
	if d.is_empty() or str(d.get("name", "")) != "征兵":
		suite.fail("政事表里没有「征兵」")
	if not DecreeDB.exists("no_such_decree"):
		pass
	else:
		suite.fail("不存在的政事 id 不该被认作存在")

	print("\n== 2. 前置不满足时应拒绝（首都还没有训练场地） ==")
	GameState.new_game(20240607)
	var reason := GameState.decree_blocked_reason(DecreeDB.RECRUIT)
	print("  阻塞原因：[%s]" % reason)
	if reason == "":
		suite.fail("没有训练场地却能排入政事")
	var r0 := GameState.enqueue_decree(DecreeDB.RECRUIT)
	print("  直接排入 -> ok=%s（期望 false）" % str(r0["ok"]))
	if bool(r0["ok"]):
		suite.fail("前置不满足时不该能排入")

	print("\n== 3. 满足前置后能排入 ==")
	# 直接塞一座训练场地（走建造流程太重）
	var cap := str(GameState.state["capital"])
	var cap_tile := GameState.tile_at(cap)
	cap_tile["buildings"] = [{"id": "classic_training_ground", "bid": "b_test", "level": 1, "workers": 0}]
	GameState.state_changed.emit()
	# 让首都有空位（清掉开局赠送的单位）
	GameState.state["units"] = []
	var r1 := GameState.enqueue_decree(DecreeDB.RECRUIT)
	print("  排入 -> ok=%s why=[%s]" % [str(r1["ok"]), str(r1["why"])])
	if not bool(r1["ok"]):
		suite.fail("满足前置却排不进队列")
	var q: Array = GameState.current_stronghold().get("decrees", [])
	print("  队列长度 = %d" % q.size())
	if q.size() != 1:
		suite.fail("队列里没有这条政事")
	else:
		var item: Dictionary = q[0]
		print("  队首：id=%s cost=%.1f paid=%.1f" % [
			str(item.get("id", "")), float(item.get("cost", 0.0)), float(item.get("paid", 0.0))])
		if absf(float(item.get("cost", 0.0)) - DecreeDB.cost_of(DecreeDB.RECRUIT)) > 0.001:
			suite.fail("queue item 的 cost 与政事表不一致（两处口径）")

	print("\n== 4. 按行政点数推进（不足时不完成） ==")
	GameState._process_decree_queue(5.0)
	var paid_after := float((GameState.current_stronghold()["decrees"][0] as Dictionary).get("paid", 0.0))
	print("  投入 5 点后 paid=%.1f（期望 5.0）" % paid_after)
	if absf(paid_after - 5.0) > 0.001:
		suite.fail("队列没有按投入量推进")
	if GameState.current_stronghold()["decrees"].is_empty():
		suite.fail("点数不够却已经出队了")

	print("\n== 5. 攒够 → 完成并执行（真的征到兵） ==")
	var before_units := (GameState.state["units"] as Array).size()
	GameState._process_decree_queue(100.0)
	var after_units := (GameState.state["units"] as Array).size()
	print("  单位数 %d -> %d（期望 +1）" % [before_units, after_units])
	if after_units != before_units + 1:
		suite.fail("政事完成后没有真的征到兵")
	print("  队列长度 = %d（期望 0，已完成出队）" % (GameState.current_stronghold().get("decrees", []) as Array).size())
	if not (GameState.current_stronghold().get("decrees", []) as Array).is_empty():
		suite.fail("完成后没有出队")
	if after_units > 0:
		var u: Dictionary = GameState.state["units"][after_units - 1]
		print("  新单位：%s  驻守=[%s]（期望首都）" % [str(u.get("name", "")), str(u.get("tile", ""))])
		if str(u.get("tile", "")) != cap:
			suite.fail("征来的兵没有进驻首都")

	print("\n== 6. 效果执行不了时，应退还已投入的行政点数 ==")
	# 把首都塞满，让"征兵"在执行时失败
	GameState.state["units"] = []
	for i in UnitDB.UNITS_PER_TILE:
		var filler := UnitDB.make_soldier("recruit", UnitDB.MELEE, UnitDB.RECRUIT, "占位%d" % i, 1)
		filler["tile"] = cap
		(GameState.state["units"] as Array).append(filler)
	var r2 := GameState.enqueue_decree(DecreeDB.RECRUIT)
	if not bool(r2["ok"]):
		print("  （首都已满，直接排不进去 —— 换一条路：排入后再塞满）")
		GameState.state["units"] = []
		GameState.enqueue_decree(DecreeDB.RECRUIT)
		for i in UnitDB.UNITS_PER_TILE:
			var f2 := UnitDB.make_soldier("recruit", UnitDB.MELEE, UnitDB.RECRUIT, "占位%d" % i, 1)
			f2["tile"] = cap
			(GameState.state["units"] as Array).append(f2)
	var admin_before := GameState.res("admin")
	GameState._process_decree_queue(100.0)
	var admin_after := GameState.res("admin")
	# 正确预期：退还 = 该条政事的消耗量（不是"不变" —— 投入的点数会回到玩家手里）
	var refunded := admin_after - admin_before
	var want_refund := DecreeDB.cost_of(DecreeDB.RECRUIT)
	print("  行政点数 %.1f -> %.1f（退还 %.1f，期望 %.1f）" % [admin_before, admin_after, refunded, want_refund])
	if absf(refunded - want_refund) > 0.001:
		suite.fail("政事执行失败后没有退还行政点数（应退还该条政事的消耗量）")
	print("  队列长度 = %d（期望 0：失败的政事不留在队列里）" % (GameState.current_stronghold().get("decrees", []) as Array).size())

	print("\n== 7. 存档往返：队列进度不丢 ==")
	GameState.state["units"] = []
	GameState.enqueue_decree(DecreeDB.RECRUIT)
	GameState._process_decree_queue(7.0)
	var paid_saved := float((GameState.current_stronghold()["decrees"][0] as Dictionary).get("paid", 0.0))
	GameState.save_to_slot(0)
	var rl := GameState.load_from_slot(0)
	print("  存读档 ok=%s  存档前 paid=%.1f" % [str(rl), paid_saved])
	var q_after: Array = GameState.current_stronghold().get("decrees", [])
	var paid_loaded := float((q_after[0] as Dictionary).get("paid", 0.0)) if not q_after.is_empty() else -1.0
	print("  读档后 paid=%.1f（期望 %.1f）" % [paid_loaded, paid_saved])
	if not q_after.is_empty() and absf(paid_loaded - paid_saved) > 0.001:
		suite.fail("存读档丢失了政事队列的进度")
	elif q_after.is_empty():
		suite.fail("存读档丢掉了整条政事队列")

	print("\n== 8. 存档版本已 +1（本段改了存档结构） ==")
	print("  SAVE_VERSION = %d（期望 3）" % GameState.SAVE_VERSION)
	if GameState.SAVE_VERSION != 3:
		suite.fail("改了存档结构却没升 SAVE_VERSION")

	suite.finish(get_tree())