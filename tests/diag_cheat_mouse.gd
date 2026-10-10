extends Node
const U := preload("res://tests/test_util.gd")
## 作弊功能「在游戏中实际使用」的端到端回归。
##
## 重点验证：开启作弊之后，在游戏里点顶部「作弊」按钮 → 菜单能否打开、
## 加资源是否真的生效、资源栏是否刷新、摧毁敌人是否生效。
##
## 注意：本测试用 --headless 跑。
## 项目用的是 OpenGL(Compatibility) 后端，反复开图形窗口会让渲染栈
## 偶发卡在灰屏（不渲染、进程不退出），所以自动化测试一律不开窗口。
## 用法：godot --headless --path <项目> res://tests/diag_cheat_mouse.tscn

var suite := U.reporter("作弊端到端（鼠标）")
func _ready() -> void:
	# v1.8.20 备忘（两条死路，别再试）：headless 的视口只有 64 高，而且
	#   · DisplayServer.window_set_size(...) 在 headless 下**无效**
	#   · get_window().size = ... 会把测试**直接挂死**（实测 TIMEOUT）
	# 所以本测试不再试图"造一个正常视口"，而是用弹窗自己认定的可用高度（见下面 usable_height）。
	await get_tree().process_frame

	print("== 1. 准备游戏主页 ==")
	GameState.new_game(20240607)
	var gs: Control = load("res://scripts/ui/game_screen.gd").new()
	gs.name = "GameScreen"
	gs.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(gs)
	for i in 8:
		await get_tree().process_frame
	for i in 8:
		await get_tree().process_frame
	print("  游戏主页已就绪 ✓（周期 %d，食物 %.0f）" % [
		int(GameState.state["cycle"]), GameState.res("food")])

	# ---------- 2. 开启作弊功能 ----------
	# 勾选框本身的显示与「勾选 → 二次确认」流程由 tests/screenshot.tscn 的
	# 02c/02d/02e 三张截图覆盖（那是纯 UI 流程）；这里专注验证「开之后能不能用」。
	print("\n== 2. 开启作弊功能 ==")
	GameState.set_cheat_enabled(true)
	print("  cheat_enabled = %s（期望 true）" % GameState.cheat_enabled())
	if not GameState.cheat_enabled():
		suite.fail("开启失败")
		_finish()
		return
	for i in 4:
		await get_tree().process_frame

	# ---------- 3. 顶部「作弊」按钮 ----------
	print("\n== 3. 顶部「作弊」按钮 ==")
	var cheat_btn: Variant = gs.get("cheat_button")
	if cheat_btn == null:
		suite.fail("game_screen 里没有 cheat_button")
		_finish()
		return
	var cb := cheat_btn as Button
	gs.call("_refresh")
	for i in 3:
		await get_tree().process_frame
	print("  visible=%s rect=%s" % [cb.visible, str(cb.get_global_rect())])
	if not cb.visible:
		suite.fail("作弊按钮不可见")
	if cb.get_global_rect().size.x < 1.0:
		suite.fail("作弊按钮尺寸为 0，点不到")
	# headless 下没有真实窗口，直接触发按钮的 pressed 信号（等价于玩家点击）
	cb.pressed.emit()
	for i in 10:
		await get_tree().process_frame
	var dlg: Variant = gs.get("_dialog")
	print("  作弊菜单弹窗存在？%s" % (dlg != null))
	if dlg == null:
		suite.fail("触发作弊按钮后菜单没打开")
		_finish()
		return
	# 关键回归：整个弹窗必须在视口内（之前底部按钮被挤出屏幕，玩家点不到）
	# v1.8.20：参照物改成"弹窗自己认定的可用高度"，不再问真实视口 ——
	# headless 下视口只有 64，拿它当参照会假失败（弹窗其实按基准高度排得好好的）。
	var vh := (dlg as DialogLayer).usable_height()
	var dlc := dlg as Control
	for ch in dlc.get_children():
		if ch is CenterContainer and ch.get_child_count() > 0:
			var pr := (ch.get_child(0) as Control).get_global_rect()
			print("  弹窗面板 rect = %s（视口高 %.0f）" % [str(pr), vh])
			if pr.end.y > vh + 0.5:
				suite.fail("弹窗底部超出视口 %.0f px" % (pr.end.y - vh))
	var destroy_probe: Variant = U.find_button(dlg as Node, "摧毁全部敌对单位")
	if destroy_probe != null:
		var dr := (destroy_probe as Button).get_global_rect()
		print("  「摧毁全部敌对单位」rect = %s，在视口内？%s" % [str(dr), str(dr.end.y <= vh + 0.5)])
		if dr.end.y > vh + 0.5:
			suite.fail("「摧毁全部敌对单位」被挤出屏幕，玩家点不到")

	# ---------- 5. 真的加资源 ----------
	print("\n== 5. 在作弊菜单里加资源 ==")
	var spins: Array = U.collect(dlg as Node, "SpinBox")
	print("  输入框数量 = %d" % spins.size())
	if spins.size() < 9:
		suite.fail("输入框数量不对")
		_finish()
		return
	# 注意：顺序需与 game_screen.gd 的 CHEAT_RESOURCES 保持一致
	var before := {
		"food": GameState.res("food"), "production": GameState.res("production"),
		"currency": GameState.res("currency"), "research": GameState.res("research"),
		"order_crystal": GameState.res("order_crystal"),
		"cohesion": GameState.res("cohesion"), "admin": GameState.res("admin"),
		"wood": GameState.res("wood"),
	}
	var pop_before := int(GameState.state["pop_total"])
	var keys := ["food", "production", "currency", "research", "order_crystal", "cohesion", "admin", "wood"]
	for i in keys.size():
		(spins[i] as SpinBox).value = 300
	for i in 8:
		await get_tree().process_frame
	var apply: Variant = U.find_button(dlg as Node, "一次性添加")
	if apply == null:
		suite.fail("找不到「一次性添加」按钮")
		_finish()
		return
	(apply as Button).pressed.emit()
	for i in 6:
		await get_tree().process_frame
	var any_fail := false
	for k in keys:
		var got := GameState.res(k)
		var want := float(before[k]) + 300.0
		var cap := GameState.storage_cap(k)
		if cap >= 0.0:
			want = minf(want, cap)
		var okk := absf(got - want) < 0.5
		print("  %s：%.0f -> %.0f（期望 %.0f，上限 %s）%s" % [
			Consts.res_name(k), float(before[k]), got, want,
			("%.0f" % cap) if cap >= 0.0 else "无", "✔" if okk else "✘"])
		if not okk:
			any_fail = true
	if any_fail:
		suite.fail("作弊加资源没有全部生效")
	print("  弹窗已关闭？%s" % (gs.get("_dialog") == null))

	# ---------- 6. 顶部资源栏是否立刻刷新 ----------
	print("\n== 6. 顶部资源栏是否同步刷新 ==")
	var bar: Variant = gs.get("resource_bar")
	var chips := U.collect_text(bar as Node)
	print("  资源栏文字：%s" % chips)
	# v1.4：有存储上限，期望看到夹取后的值（货币 600、满格 100 / 100）
	var shows := chips.contains("600") and chips.contains("100 / 100")
	print("  资源栏里出现了作弊后的期望值（货币 600 / 满格 100 / 100）？%s" % shows)
	if not shows:
		suite.fail("顶部资源栏没有刷新，玩家看不到作弊结果")

	# ---------- 7. 摧毁敌对单位 ----------
	print("\n== 7. 摧毁敌对单位 ==")
	var rng := RandomNumberGenerator.new()
	rng.seed = 999
	for i in 300:
		if WorldGen.maybe_spawn_hazard(GameState.state, rng)["spawned"]:
			break
	GameState.state_changed.emit()
	for i in 4:
		await get_tree().process_frame
	var enemies := GameState.enemy_tiles()
	print("  大世界里敌对单位：%d 个" % enemies.size())
	if enemies.is_empty():
		print("  （没生成出来，跳过这一项）")
	else:
		cb.pressed.emit()
		for i in 8:
			await get_tree().process_frame
		var dlg2: Variant = gs.get("_dialog")
		if dlg2 == null:
			suite.fail("第二次打开作弊菜单失败")
		else:
			# 几何诊断：弹窗与关键按钮到底落在哪里
			var dl := dlg2 as Control
			print("  视口 = %s" % str(get_viewport().get_visible_rect().size))
			print("  弹窗 rect = %s" % str(dl.get_global_rect()))
			var panel: Node = null
			for ch in dl.get_children():
				if ch is CenterContainer and ch.get_child_count() > 0:
					panel = ch.get_child(0)
			if panel is Control:
				print("  面板 rect = %s" % str((panel as Control).get_global_rect()))
			var apply2: Variant = U.find_button(dlg2 as Node, "一次性添加")
			if apply2 != null:
				print("  「一次性添加」rect = %s" % str((apply2 as Button).get_global_rect()))
			var destroy: Variant = U.find_button(dlg2 as Node, "摧毁全部敌对单位")
			if destroy == null:
				suite.fail("找不到「摧毁全部敌对单位」按钮")
			else:
				print("  「摧毁全部敌对单位」rect = %s" % str((destroy as Button).get_global_rect()))
				(destroy as Button).pressed.emit()
				for i in 6:
					await get_tree().process_frame
				print("  摧毁后剩余敌对单位：%d 个（期望 0）" % GameState.enemy_tiles().size())
				if GameState.enemy_tiles().size() != 0:
					suite.fail("摧毁全部敌人没有生效")

	_finish()


func _finish() -> void:
	suite.finish(get_tree())
func _click(pos: Vector2) -> void:
	# 项目开了 canvas_items 拉伸，UI 坐标与窗口坐标不是 1:1，
	# 必须换算成窗口坐标，否则真实鼠标事件点不到正确的位置。
	var wp := _viewport_to_window(pos)
	if wp.x < 0.0 or wp.y < 0.0 or wp.x > 1280.0 or wp.y > 720.0:
		suite.fail("点击坐标越界（窗口坐标）：%s（视口坐标 %s）" % [str(wp), str(pos)])
		return
	var move := InputEventMouseMotion.new()
	move.position = wp
	move.global_position = wp
	Input.parse_input_event(move)
	await get_tree().process_frame
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = wp
	down.global_position = wp
	Input.parse_input_event(down)
	await get_tree().process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = wp
	up.global_position = wp
	Input.parse_input_event(up)
	await get_tree().process_frame


## 视口坐标 -> 窗口坐标
func _viewport_to_window(vp: Vector2) -> Vector2:
	var v := get_viewport()
	var vr := v.get_visible_rect()
	var ws := Vector2(DisplayServer.window_get_size())
	if vr.size.x < 1.0 or vr.size.y < 1.0:
		return vp
	return Vector2(vp.x / vr.size.x * ws.x, vp.y / vr.size.y * ws.y)

