extends Node
## 截图自检：真实渲染主页面、游戏主页各功能页，并保存 PNG 供人工/自动检查字体与排版。
## 用法：godot --path <项目> res://tests/screenshot.tscn

const OUT_DIR := "res://tests/_shots"

## 看门狗：脚本中途报错会直接中断 _ready()，从而走不到 quit()，窗口就永远挂着
## （曾因此卡死两次）。挂上这个定时器后，超时会强制退出并报出停在哪儿。
const WATCHDOG_SEC := 120.0

var shot := 0
var _last_shot := "(尚未开始)"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_arm_watchdog()
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await get_tree().process_frame
	await get_tree().process_frame

	# 1) 主页面
	var menu_holder := _host()
	var menu: Control = load("res://scripts/ui/menu_screen.gd").new()
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_holder.add_child(menu)
	await _shoot("01_menu")
	# 展开「开始游戏」的三个小按钮
	menu.call("_toggle_expand")
	await _shoot("02_menu_expanded")
	# v1.2：设置窗口（含自动存档周期数）
	menu.call("_open_settings")
	for f0 in 6:
		await get_tree().process_frame
	await _shoot("02b_dialog_settings")
	menu.call("close_dialog")
	for f1 in 2:
		await get_tree().process_frame
	# v1.2：反馈窗口（版本号 / QQ群 / 邮箱 / 作弊勾选框）
	menu.call("_open_feedback")
	for f2 in 6:
		await get_tree().process_frame
	await _shoot("02c_dialog_feedback")
	# v1.3：勾选「作弊功能」后的二次确认弹窗 + 勾选态
	var cheat_box: Variant = _find_toggle(menu, "作弊功能")
	if cheat_box != null:
		(cheat_box as Button).button_pressed = true
		for f2b in 6:
			await get_tree().process_frame
		await _shoot("02d_dialog_cheat_confirm")
		# 点确认，看勾选态
		var ok_btn: Variant = _find_button(menu, "确认")
		if ok_btn != null:
			(ok_btn as Button).pressed.emit()
			for f2c in 6:
				await get_tree().process_frame
			await _shoot("02e_dialog_cheat_checked")
	menu.call("close_dialog")
	for f3 in 2:
		await get_tree().process_frame
	GameState.set_cheat_enabled(false)
	menu.queue_free()
	await get_tree().process_frame

	# 2) 游戏主页各功能页
	GameState.new_game(20240607)
	var gs_holder := _host()
	var gs: Control = load("res://scripts/ui/game_screen.gd").new()
	gs.set_anchors_preset(Control.PRESET_FULL_RECT)
	gs_holder.add_child(gs)
	await get_tree().process_frame

	# 先造几个建筑并抽卡，让界面有内容
	# v1.3.1：地块有可用土地上限，需把建筑铺到多块领地上
	var cap: String = str(GameState.state["capital"])
	GameState.add_res("admin", 800.0)
	GameState.state["res"]["production"] = 800.0   # 直达赋值，绕过存储上限，纯为截图铺内容
	GameState.add_res("currency", 30000.0)
	for i in 3:
		var ck := WorldGen.claimable_keys(GameState.state)
		if not ck.is_empty():
			WorldGen.claim(GameState.state, ck[0])
	var build_tiles: Array[String] = [cap]
	for t in GameState.owned_tiles():
		build_tiles.append(WorldGen.key_of(Vector2i(int(t["c"][0]), int(t["c"][1]))))
	for bid in ["classic_field", "classic_workshop", "classic_house", "classic_academy",
			"classic_training_ground"]:
		for k in build_tiles:
			GameState.state["res"]["production"] = 300.0   # 每次直给，绕过上限
			if GameState.build(k, bid)["ok"]:
				break
	GameState.assign_worker(cap, "classic_field", 1)
	GameState.assign_worker(cap, "classic_workshop", 1)
	GameState.add_res("cohesion", 30000.0)
	GameState.add_res("order_crystal", 200.0)
	GameState.state["res"]["production"] = 400.0
	GameState.add_res("food", 400.0)
	GameState.add_res("currency", 3000.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	Gacha.draw_ten(GameState.state, Gacha.Pool.ROTATION, rng)
	Gacha.draw_ten(GameState.state, Gacha.Pool.RESOURCE, rng)
	Gacha.draw(GameState.state, Gacha.Pool.DEVELOPMENT, rng)
	# v1.1：招募各职业募集兵 + 派驻 + 编队，让界面有内容
	for p in UnitDB.PROFESSION_ORDER:
		GameState.recruit_soldier(p)
	for i in 3:
		var cks := WorldGen.claimable_keys(GameState.state)
		if not cks.is_empty():
			WorldGen.claim(GameState.state, cks[0])
	# 把前 4 个待命单位派到首都，并编入第一队
	var idle := GameState.idle_units()
	for j in mini(4, idle.size()):
		GameState.deploy_unit(str(idle[j]["uid"]), cap)
		GameState.assign_team(str(idle[j]["uid"]), 0)
	WorldGen.maybe_spawn_hazard(GameState.state, rng)
	GameState.state_changed.emit()
	await get_tree().process_frame

	var views := ["manage", "treasure", "gacha", "log", "world"]
	for i in views.size():
		gs.call("goto_view", views[i])
		# 布局需要几帧才能稳定（尤其是世界页的地图控件）
		for f in 4:
			await get_tree().process_frame
		await _shoot("%02d_view_%s" % [i + 3, views[i]])

	# v1.3.1：世界页「规划面板」的两个页签
	gs.call("goto_view", "world")
	for f in 4:
		await get_tree().process_frame
	var wp: Variant = gs.get("views")["world"]
	wp.call("switch_plan_tab", "info")
	for f in 4:
		await get_tree().process_frame
	await _shoot("08a_plan_info")
	wp.call("switch_plan_tab", "plan")
	for f in 4:
		await get_tree().process_frame
	await _shoot("08b_plan_tile")
	# v1.3.1：管理页「据点详情 + 规划队列」
	gs.call("goto_view", "manage")
	for f in 4:
		await get_tree().process_frame
	await _shoot("08c_stronghold_queue")

	# v1.3：中控区的三个页签（指挥 / 军队 / 科技树）
	gs.call("goto_view", "manage")
	for f in 4:
		await get_tree().process_frame
	var mgr_page: Variant = gs.get("views")["manage"]
	for tab in ["army", "tech"]:
		mgr_page.call("switch_ctrl_tab", tab)
		for f2 in 5:
			await get_tree().process_frame
		await _shoot("08b_ctrl_%s" % tab)

	# 至宝的三个子页
	gs.call("goto_view", "treasure")
	await get_tree().process_frame
	var tv: Variant = gs.get("views")["treasure"]
	for sub in ["character", "gear", "item"]:
		tv.call("_switch", sub)
		for f in 4:
			await get_tree().process_frame
		await _shoot("09_treasure_%s" % sub)
	# v1.1：角色页的五个三级按钮（主要 / 技能 / 职业 / 位阶 / 编队）
	tv.call("_switch", "character")
	for f00 in 4:
		await get_tree().process_frame
	var cp: Variant = tv.get("pages")["character"]
	for st in ["main", "skill", "profession", "rank", "team"]:
		cp.set("sub_tab", st)
		cp.call("refresh")
		for f0 in 4:
			await get_tree().process_frame
		await _shoot("10_character_%s" % st)

	# 日志的子页
	gs.call("goto_view", "log")
	for f in 4:
		await get_tree().process_frame
	var lv: Variant = gs.get("views")["log"]
	for sub2 in ["task", "record", "codex", "manual"]:
		lv.call("_switch", sub2)
		for f2 in 4:
			await get_tree().process_frame
		await _shoot("12_log_%s" % sub2)

	# v1.1：图鉴里文明组 + 稀有度同时生效
	lv.call("_switch", "codex")
	for f5 in 4:
		await get_tree().process_frame
	var cxp: Variant = lv.get("pages")["codex"]
	cxp.set("cat", "character")
	cxp.set("picks", {"civ": "提瓦特", "rarity": "4"})
	cxp.call("refresh")
	for f6 in 5:
		await get_tree().process_frame
	await _shoot("13_codex_civ_rarity")
	# 职业图鉴
	cxp.set("cat", "profession")
	cxp.set("picks", {})
	cxp.call("refresh")
	for f7 in 5:
		await get_tree().process_frame
	await _shoot("14_codex_profession")

	# v1.1：征兵对话框
	gs.call("goto_view", "manage")
	for f8 in 4:
		await get_tree().process_frame
	var mv: Variant = gs.get("views")["manage"]
	mv.call("_open_recruit")
	for f9 in 8:
		await get_tree().process_frame
	await _shoot("16_dialog_recruit")
	gs.call("close_dialog")
	for f10 in 2:
		await get_tree().process_frame

	# v1.2：据点下拉选择菜单（v1.4 起管理页里的对应方法是 _open_stronghold_picker）
	if mv.has_method("_open_stronghold_picker"):
		mv.call("_open_stronghold_picker")
		for f11 in 8:
			await get_tree().process_frame
		await _shoot("18_dialog_stronghold_picker")
		gs.call("close_dialog")
		for f12 in 2:
			await get_tree().process_frame
	else:
		print("  [skip] view_manage_page 没有 _open_stronghold_picker，跳过据点选择弹窗")

	# v1.2：作弊菜单（先开启作弊功能）
	GameState.set_cheat_enabled(true)
	gs.call("_refresh")
	for f13 in 3:
		await get_tree().process_frame
	gs.call("_open_cheat_menu")
	for f14 in 8:
		await get_tree().process_frame
	await _shoot("19_dialog_cheat")
	gs.call("close_dialog")
	GameState.set_cheat_enabled(false)
	for f15 in 3:
		await get_tree().process_frame

	# 弹窗：抽卡结果
	gs.call("goto_view", "gacha")
	for f3 in 4:
		await get_tree().process_frame
	var gv: Variant = gs.get("views")["gacha"]
	gv.call("_do_draw", 10)
	for f4 in 4:
		await get_tree().process_frame
	await _shoot("17_dialog_draw")

	# v1.5：世界页 —— 单位操作窗 + 招募选地模式
	gs.call("close_dialog")
	var wv: Variant = gs.get("views")["world"]
	var cap2 := str(GameState.state["capital"])
	var g_shot := UnitDB.from_card({
		"id": "shot_guest", "name": "截图客人", "rarity": 5, "group": "通用",
		"kind": "star", "profession": UnitDB.MELEE, "rank": UnitDB.HERO,
		"atk": 46, "def": 22, "hp": 210, "spd": 4, "agi": 12,
	})
	g_shot["acquired_cycle"] = int(GameState.state["cycle"])
	GameState.state["units"].append(g_shot)
	var c_shot := UnitDB.make_soldier("recruit", UnitDB.DEFENDER, UnitDB.RECRUIT, "截图公民", 1)
	c_shot["tile"] = cap2
	c_shot["move_left"] = GameState.max_move(c_shot)
	GameState.state["units"].append(c_shot)
	gs.call("goto_view", "world")
	for fw1 in 4:
		await get_tree().process_frame
	if wv != null:
		# 同格连点两次：第 1 档市中心、第 2 档单位 → 左下角弹出单位操作窗
		(wv as Node).call("_on_tile_clicked", cap2, "", Vector2.ZERO)
		(wv as Node).call("_on_tile_clicked", cap2, "", Vector2.ZERO)
	for fw2 in 3:
		await get_tree().process_frame
	await _shoot("20_unit_panel")
	# 招募选地模式
	GameState.begin_recruit(str(g_shot["uid"]))
	if wv != null:
		(wv as Node).call("refresh")
	for fw3 in 3:
		await get_tree().process_frame
	await _shoot("21_recruit_pick")

	print("截图完成，共 %d 张，输出目录 %s" % [shot, OUT_DIR])
	get_tree().quit(0)


## 超时兜底：任何一步卡住 / 报错，都不允许把窗口一直挂着
func _arm_watchdog() -> void:
	var wd := Timer.new()
	wd.wait_time = WATCHDOG_SEC
	wd.one_shot = true
	wd.process_mode = Node.PROCESS_MODE_ALWAYS
	wd.timeout.connect(func() -> void:
		var msg := "截图自检超时 %.0f 秒，最后完成的是：%s" % [WATCHDOG_SEC, _last_shot]
		push_error(msg)
		print("[TIMEOUT] %s" % msg)
		get_tree().quit(1))
	add_child(wd)
	wd.start()


func _host() -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(c)
	return c


## 按包含关系找 toggle 勾选框
func _find_toggle(n: Node, text: String) -> Button:
	if n is Button and not (n is CheckBox) and (n as Button).text.contains(text):
		return n as Button
	for c in n.get_children():
		var r := _find_toggle(c, text)
		if r != null:
			return r
	return null


## 按精确文字找按钮
func _find_button(n: Node, text: String) -> Button:
	if n is Button and not (n is CheckBox) and (n as Button).text == text:
		return n as Button
	for c in n.get_children():
		var r := _find_button(c, text)
		if r != null:
			return r
	return null


func _shoot(name: String) -> void:
	_last_shot = name
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, name]
	var err := img.save_png(path)
	if err != OK:
		print("  [FAIL] 保存 %s 失败（错误 %d）" % [path, err])
	else:
		shot += 1
		print("  [ok] %s  (%dx%d)" % [path, img.get_width(), img.get_height()])
