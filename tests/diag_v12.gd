extends Node
## v1.2 自检：自动存档周期、管理页减负、地块下拉、单位列表可选中、作弊菜单、反馈信息。

var failed := 0


func _ready() -> void:
	GameState.new_game(20240607)
	print("== 1. 自动存档周期数 ==")
	# ⚠️ 自动存档间隔是**全局设置**（落到 user://settings.cfg），会跨会话保留。
	# 所以**不能断言"当前值 == 默认常量"**——那会随玩家自己改过的设置变红（测试不隔离，
	# 而且会让人误以为改坏了代码）。正确做法三步：
	#   ① 断言常量本身（纯值，不随机器变）
	#   ② 测"设值 → 读回"的往返
	#   ③ 测完把原来的值**还原**，别让测试改了玩家的设置
	print("  默认常量：%d（期望 1）" % Consts.AUTOSAVE_INTERVAL_DEFAULT)
	if Consts.AUTOSAVE_INTERVAL_DEFAULT != 1:
		print("  [FAIL] 默认常量不是 1")
		failed += 1
	var kept_interval := GameState.autosave_interval()
	GameState.set_autosave_interval(3)
	print("  设为 3：%d" % GameState.autosave_interval())
	if GameState.autosave_interval() != 3:
		print("  [FAIL] 设成 3 之后读回不是 3")
		failed += 1
	# 跑 6 个周期，看 autosaved 标记落在哪些周期
	var saved_cycles: Array[int] = []
	for i in 6:
		var rep: Dictionary = GameState.end_cycle()
		if bool(rep.get("autosaved", false)):
			saved_cycles.append(int(rep["cycle"]))
	print("  设成每 3 周期后，实际触发存档的周期：%s（期望每 3 个一次）" % str(saved_cycles))
	if saved_cycles.size() != 2:
		print("  [FAIL] 触发次数不是 2")
		failed += 1
	GameState.set_autosave_interval(kept_interval)
	print("  已还原为测试前的值：%d" % GameState.autosave_interval())

	print("\n== 2. 作弊功能开关 ==")
	# 作弊开关现在是全局设置（AppSettings，落到 user://settings.cfg），
	# 会跨会话保留，所以这里先显式归零再测
	GameState.set_cheat_enabled(false)
	print("  归零后：%s（期望 false）" % GameState.cheat_enabled())
	if GameState.cheat_enabled():
		failed += 1
	GameState.set_cheat_enabled(true)
	print("  开启后：%s" % GameState.cheat_enabled())

	print("\n== 3. 作弊：添加资源 ==")
	var before := {
		"food": GameState.res("food"), "production": GameState.res("production"),
		"currency": GameState.res("currency"), "research": GameState.res("research"),
		"order_crystal": GameState.res("order_crystal"), "cohesion": GameState.res("cohesion"),
		"wood": GameState.res("wood"),
	}
	var pop_before := int(GameState.state["pop_total"])
	GameState.cheat_add_resources({
		"food": 500, "production": 300, "currency": 1000, "research": 200,
		"order_crystal": 50, "cohesion": 2000, "wood": 100, "pop_total": 5,
	})
	for k in before.keys():
		print("  %s：%.0f -> %.0f（+%d）" % [Consts.res_name(k), float(before[k]),
			GameState.res(k), int(GameState.res(k) - float(before[k]))])
	print("  人力：%d -> %d（+5）" % [pop_before, int(GameState.state["pop_total"])])

	print("\n== 4. 作弊：摧毁敌对单位 ==")
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in 200:
		if WorldGen.maybe_spawn_hazard(GameState.state, rng)["spawned"]:
			break
	var enemies := GameState.enemy_tiles()
	print("  生成敌对单位：%d 个" % enemies.size())
	if not enemies.is_empty():
		var key := WorldGen.key_of(Vector2i(int(enemies[0]["c"][0]), int(enemies[0]["c"][1])))
		var r: Dictionary = GameState.cheat_destroy_tile(key)
		print("  摧毁 %s -> %s %s" % [key, r["ok"], str(r.get("label", ""))])
		print("  剩余敌对单位：%d 个" % GameState.enemy_tiles().size())
		# 再生成几个，测一键清空
		for i in 200:
			if WorldGen.maybe_spawn_hazard(GameState.state, rng)["spawned"]:
				break
		var n := GameState.cheat_destroy_all_enemies()
		print("  一键清空 -> 摧毁 %d 个，剩余 %d 个" % [n, GameState.enemy_tiles().size()])
		if GameState.enemy_tiles().size() != 0:
			print("  [FAIL] 没有清空")
			failed += 1

	print("\n== 5. 单位列表：多角色后可选中（v1.2 修复的 bug） ==")
	var cap: String = str(GameState.state["capital"])
	GameState.add_res("cohesion", 60000.0)
	GameState.add_res("order_crystal", 400.0)
	GameState.add_res("production", 500.0)
	GameState.add_res("food", 500.0)
	GameState.add_res("currency", 5000.0)
	# 反复抽卡，把单位列表撑到十几个（原 bug 只在单位多了以后才出现）
	for i in 4:
		Gacha.draw_ten(GameState.state, Gacha.Pool.ROTATION, rng)
	print("  单位总数：%d" % (GameState.state["units"] as Array).size())

	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(holder)
	var page: Control = load("res://scripts/ui/views/parts/character_page.gd").new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(page)
	page.size = Vector2(1280, 600)
	for i in 6:
		await get_tree().process_frame

	var list_box: VBoxContainer = page.get("list_box")
	print("  列表里的行数：%d" % list_box.get_child_count())
	if list_box.get_child_count() < 2:
		print("  [FAIL] 列表行数不足，无法测试选择")
		failed += 1
	else:
		# 逐行模拟点击，检查 selected_id 是否真的换成了该行的单位
		var tested := 0
		for idx in mini(list_box.get_child_count(), 6):
			var row := list_box.get_child(idx) as Button
			if row == null:
				print("  [FAIL] 第 %d 行不是 Button，无法点击" % (idx + 1))
				failed += 1
				continue
			var units: Array = page.call("_filtered_units")
			var expect_uid := str((units[idx] as Dictionary)["uid"])
			var expect_name := str((units[idx] as Dictionary)["name"])
			row.emit_signal("pressed")
			for f in 2:
				await get_tree().process_frame
			var got := str(page.get("selected_id"))
			var ok := got == expect_uid
			print("  点击第 %d 行（%s）-> selected_id %s %s" % [
				idx + 1, expect_name, got, "✔" if ok else "✘"])
			if not ok:
				failed += 1
			tested += 1
		print("  共测试 %d 行" % tested)

	print("\n== 6. 管理页减负（不再有重复 UI） ==")
	var mgr: Control = load("res://scripts/ui/views/view_manage_page.gd").new()
	mgr.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(mgr)
	mgr.size = Vector2(1280, 600)
	for i in 4:
		await get_tree().process_frame
	var has_res_grid := mgr.get("res_grid") != null
	var has_happy := mgr.get("happiness_label") != null
	var has_tile_list := mgr.find_child("TileList", true, false) != null
	print("  资源总览网格还在？%s（期望 false）" % has_res_grid)
	print("  部落概况标签还在？%s（期望 false）" % has_happy)
	print("  独立领地列表还在？%s（期望 false）" % has_tile_list)
	if has_res_grid or has_happy or has_tile_list:
		failed += 1
	var title: Variant = mgr.get("stronghold_title")
	print("  据点标题是可点击按钮？%s" % (title is Button))
	if not (title is Button):
		failed += 1
	else:
		print("  标题文字：%s" % str((title as Button).text))

	print("\n== 6.5 中控区：只剩「军队」页签（v1.8.6：科技树已搬到左上角浮窗） ==")
	var tabs: Array = mgr.get("CTRL_TABS")
	var tab_names: Array[String] = []
	for t in tabs:
		tab_names.append(str(t["name"]))
	print("  页签名：%s（%d 个）" % ["、".join(tab_names), tab_names.size()])
	if tab_names.size() != 1 or tab_names.has("科技树"):
		failed += 1
	var pages: Dictionary = mgr.get("ctrl_pages")
	print("  页签容器：%s" % str(pages.keys()))
	if pages.size() != 1:
		print("  [FAIL] 页签容器数量不是 1")
		failed += 1
	# 逐个切换，检查同一时刻只有一个页签可见
	for t2 in tabs:
		var tid := str(t2["id"])
		mgr.call("switch_ctrl_tab", tid)
		for f in 3:
			await get_tree().process_frame
		var visible_ids: Array[String] = []
		for k in pages.keys():
			var pg: Variant = pages[k]
			if pg is Control and (pg as Control).visible:
				visible_ids.append(str(k))
		var cur := str(mgr.get("ctrl_tab"))
		var ok := visible_ids.size() == 1 and visible_ids[0] == tid and cur == tid
		print("  切到「%s」-> ctrl_tab=%s，可见页签 %s %s" % [
			str(t2["name"]), cur, str(visible_ids), "✔" if ok else "✘"])
		if not ok:
			failed += 1
	# 军队页签
	mgr.call("switch_ctrl_tab", "army")
	for f in 3:
		await get_tree().process_frame
	var unit_box: Variant = mgr.get("unit_box")
	var unit_rows := 0
	if unit_box is Node:
		unit_rows = (unit_box as Node).get_child_count()
	print("  军队页签里的条目数：%d（应 > 0）" % unit_rows)
	if unit_rows <= 0:
		failed += 1

	print("\n== 7. 一级入口只剩三个（v1.8.7：管理/日志都已不是一级入口），休眠页已删除 ==")
	var gscr: Control = load("res://scripts/ui/game_screen.gd").new()
	gscr.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(gscr)
	for i in 4:
		await get_tree().process_frame
	var view_list: Array = gscr.get("VIEWS")
	var names: Array[String] = []
	for v in view_list:
		names.append(str(v["name"]))
	print("  一级按钮：%s（%d 个）" % ["、".join(names), names.size()])
	if names.size() != 3 or names.has("休眠") or names.has("日志") or names.has("管理"):
		failed += 1
	print("  悬浮导航按钮：%s（%d 个，期望 2：至宝/世界泡）" % [str((gscr.get("nav_buttons") as Dictionary).keys()), (gscr.get("nav_buttons") as Dictionary).size()])
	if (gscr.get("nav_buttons") as Dictionary).size() != 2:
		failed += 1
	if FileAccess.file_exists("res://scripts/ui/views/sleep_view.gd"):
		print("  [FAIL] sleep_view.gd 仍然存在")
		failed += 1
	else:
		print("  sleep_view.gd 已删除 ✔")

	print("\n== 8. 反馈信息 ==")
	print("  demo 版本：%s" % Consts.DEMO_VERSION_FULL)
	print("  QQ 群：%s" % Consts.FEEDBACK_QQ_GROUP)
	print("  邮箱：%s" % Consts.FEEDBACK_EMAIL)

	print("\n== 9. 存档版本校验（v1.7：1.0 不做旧档兼容） ==")
	# 1.0 期间不为旧档买单：版本不符直接拒绝，且不能污染当前局与全局设置
	var cheat_before := GameState.cheat_enabled()
	var interval_before := GameState.autosave_interval()
	var slot := 6
	var legacy := {
		"magic": GameState.SAVE_MAGIC, "version": 1, "saved_at": "legacy-version",
		"state": {"cycle": 9, "capital": "0,0", "tiles": GameState.state["tiles"],
			"res": {}, "techs": [], "log": []},
	}
	var f := FileAccess.open(GameState.slot_path(slot), FileAccess.WRITE)
	f.store_string(JSON.stringify(legacy, "  "))
	f.close()
	var rejected := GameState.load_from_slot(slot)
	print("  读取 v1 旧档 -> %s（期望 false：版本不符应被拒绝）" % rejected)
	print("  拒绝后仍停在原局？周期 %d（期望不是 9）" % int(GameState.state["cycle"]))
	print("  全局设置未被影响？作弊 %s→%s｜间隔 %d→%d（期望不变）" % [
		cheat_before, GameState.cheat_enabled(), interval_before, GameState.autosave_interval()])
	if rejected:
		failed += 1
	if int(GameState.state["cycle"]) == 9:
		failed += 1
	if GameState.cheat_enabled() != cheat_before:
		failed += 1
	if GameState.autosave_interval() != interval_before:
		failed += 1
	GameState.delete_slot(slot)

	print("\n== v1.2 自检结束，失败 %d 项 ==" % failed)
	get_tree().quit(0 if failed == 0 else 1)
