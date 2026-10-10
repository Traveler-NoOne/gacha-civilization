extends Node
## v1.8.9 专项自检：加载界面。
##
## 重点不是"好不好看"，而是三件事：
##   ① 保底显示时间真的存在（否则加载界面会一闪而过 = 白做）
##   ② 进度条真的在动，而且最后会走满
##   ③ `finished` 真的会发出来（不能被卡住；卡住的话主流程就永远进不了游戏）

var failed := 0
var _done := false


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
		scr.finished.connect(func() -> void: _done = true)
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

	print("\n== v1.8.9 自检结束，失败 %d 项 ==" % failed)
	get_tree().quit(0 if failed == 0 else 1)
