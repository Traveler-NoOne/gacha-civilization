extends Node
## v1.8.9 专项自检：加载界面。
##
## 重点不是"好不好看"，而是三件事：
##   ① 保底显示时间真的存在（否则加载界面会一闪而过 = 白做）
##   ② 进度条真的在动，而且最后会走满
##   ③ `finished` 真的会发出来（不能被卡住；卡住的话主流程就永远进不了游戏）

var failed := 0
## ⚠️ 这些必须是**成员变量**：GDScript 的 lambda **按值捕获局部变量**，
## 写成 `var done := false` + `connect(func(): done = true)` 是改不到外面的（第一次写这测试就踩了）。
var _done := false
var _done2 := false
var _work_ran := false
var _ran_before_done := false


func _ready() -> void:
	await get_tree().process_frame
	print("\n== v1.8.9 加载界面 ==")

	var scr: Control = load("res://scripts/ui/loading_screen.gd").new()
	add_child(scr)
	for i in 3:
		await get_tree().process_frame

	# 常量要用 get_script_constant_map() 读 —— Object.get() 拿不到 const
	var consts: Dictionary = (scr.get_script() as GDScript).get_script_constant_map()
	var min_show := float(consts.get("MIN_SHOW", 0.0))
	print("  保底显示时长：%.2f 秒（应 >= 0.5，否则会一闪而过）" % min_show)
	if min_show < 0.5:
		failed += 1

	var tips: Array = consts.get("TIPS", [])
	print("  tips 条数：%d（应 >= 3）" % tips.size())
	if tips.size() < 3:
		failed += 1
	var uniq := {}
	for t in tips:
		uniq[str(t)] = true
	if uniq.size() != tips.size():
		print("  [FAIL] tips 里有重复的")
		failed += 1

	var bar: Variant = scr.get("_bar")
	if bar == null:
		print("  [FAIL] 找不到进度条节点")
		failed += 1
	else:
		var v0: float = (bar as ProgressBar).value
		var t0 := Time.get_ticks_msec()
		scr.finished.connect(func(_ok: bool) -> void: _done = true)
		scr.call("begin")
		for i in 3:
			await get_tree().process_frame
		var v1: float = (bar as ProgressBar).value
		print("  进度条：begin 前 %.1f → 3 帧后 %.1f（应该在涨）" % [v0, v1])
		if v1 <= v0:
			failed += 1
		while not _done and Time.get_ticks_msec() - t0 < 6000:
			await get_tree().process_frame
		var dt := float(Time.get_ticks_msec() - t0) / 1000.0
		print("  finished：%s，用时 %.2f 秒（应 >= 保底 %.2f）" % [str(_done), dt, min_show])
		if not _done:
			print("  [FAIL] 6 秒内没发出 finished —— 主流程会卡在加载界面")
			failed += 1
		if dt + 0.15 < min_show:
			print("  [FAIL] 比保底时间还快 —— 保底没生效")
			failed += 1
		var vend: float = (bar as ProgressBar).value
		print("  走满后进度条：%.1f（应为 100）" % vend)
		if vend < 99.9:
			failed += 1

	# 顺序检查：工作必须是"界面画出来之后、finished 之前"执行
	# （将来地图内容变多时，慢加载就会花在这张界面上，而不是卡在菜单上）
	var scr2: Control = load("res://scripts/ui/loading_screen.gd").new()
	add_child(scr2)
	for i in 2:
		await get_tree().process_frame
	var t1 := Time.get_ticks_msec()
	scr2.finished.connect(func(_ok: bool) -> void:
		_ran_before_done = _work_ran
		_done2 = true)
	scr2.call("begin", func() -> bool:
		_work_ran = true
		return true)
	# ⚠️ 超时要用**循环外存好的起点**比较；写成 get_ticks_msec() - get_ticks_msec() 是自己减自己，恒约等于 0 → 死循环
	while not _done2 and Time.get_ticks_msec() - t1 < 6000:
		await get_tree().process_frame
	print("  工作是先跑、再走进度条：%s（应为 true）" % str(_ran_before_done))
	if not _ran_before_done:
		failed += 1
	print("  work 返回 true 时 finished(ok)=true：%s" % str(_done2))
	if not _done2:
		failed += 1

	print("\n== v1.8.9 自检结束，失败 %d 项 ==" % failed)
	get_tree().quit(0 if failed == 0 else 1)
