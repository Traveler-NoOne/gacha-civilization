extends Node
const U := preload("res://tests/test_util.gd")
## 截图自检：真实渲染主页面、游戏主页各功能页，并保存 PNG 供人工/自动检查字体与排版。
## 用法：godot --path <项目> res://tests/screenshot.tscn

const OUT_DIR := "res://tests/_shots"

## 看门狗：脚本中途报错会直接中断 _ready()，从而走不到 quit()，窗口就永远挂着
## （曾因此卡死两次）。挂上这个定时器后，超时会强制退出并报出停在哪儿。
const WATCHDOG_SEC := 120.0

var shot := 0
var _last_shot := "(尚未开始)"
## 当前游戏主页 / 世界页（_clean() 要拿它们关东西）
var _gs: Variant = null
var _wp: Variant = null
var _menu: Variant = null
## 已成功的截图清单（结尾写成 MANIFEST，给视觉检查用）
var _taken: Array[String] = []

## 每张图**拍的是什么、该看什么** —— 视觉检查时对着这张表看。
## 加新图时记得在这里补一行（结尾会生成 tests/_shots/00_MANIFEST.md）。
const SHOT_DOCS := {
	"01_menu": "主页面（未展开）｜标题、四个按钮、「开始游戏」 | 文字有无重叠/截断，按钮是否居中",
	"01b_loading": "加载界面（进度条走到中段）｜标题+立绘居中、左下 tips、右下进度条 | 进度条真的在走（不是 0%），tips 有内容",
	"02_menu_expanded": "主页面（展开「开始游戏」）｜继续/新游戏/读取三个小按钮 | 展开框没有把下面的按钮挤走",
	"02b_dialog_settings": "设置弹窗｜自动存档周期数等 | 控件对齐、数字可读",
	"02c_dialog_feedback": "反馈弹窗｜版本号 / QQ群 / 邮箱 / 「作弊功能」勾选框 | 文字完整、勾选框可见",
	"02d_dialog_cheat_confirm": "勾选「作弊功能」后的二次确认弹窗 | 确认/取消都在、没有超框",
	"02e_dialog_cheat_checked": "确认后的勾选态 | 勾选态与弹窗关闭流程正常",
	"04_view_treasure": "至宝浮窗（叠在世界地图上）｜四周能看见地图 | 是否还能看出「世界在下面」、标题有没有重复",
	"05_view_gacha": "世界泡浮窗｜三个子系统入口 | 排版、文字",
	"06_log_window": "日志大浮窗（四周留边）｜任务/记录/图鉴/手册 | 四周留边是否露出地图、页签是否齐全",
	"06b_tech_window": "科技树浮窗（左上按钮打开）｜科技条目+研究按钮 | 条目内容、按钮是否可点",
	"06c_stats_res": "统计面板·资源页（默认）｜抽象/具体资源 + 每周期净收支 | 数字与资源栏是否一致、亏损是否为红字",
	"06d_stats_units": "统计面板·单位页｜总数 / 客人公民 / 人力 / 按职业 / 编队 | 分组清晰、数字合理",
	"07_view_world": "大世界（纯地图，无浮窗）｜五个角落按钮 | 地图铺满、四个角按钮都在位、底栏确实没了",
	"08a_tile_info": "简约地块信息小窗（点非我方地块）｜势力/名称/地形/土地/建筑 | 小窗在鼠标处、内容正确、没有残留据点窗口",
	"08b_stronghold_info": "据点管理窗口·信息页（点我方领地）｜掌控力/已用土地/据点明细 | 上方三个按钮在窗口边框外、下半段两条队列",
	"08c_stronghold_decree": "据点管理窗口·政事页｜政事列表+政事队列 | 条目与按钮、队列跑条",
	"08d_stronghold_labor": "据点管理窗口·人力页｜按建筑列人力 | 行内容与「无需人力」过滤",
	"08e_tile_menu": "右键地块弹出的球形菜单｜🔨 修建建筑 | 球形按钮居中、提示文字（tooltip）不截断",
	"08f_build_panel": "修建浮窗（未选中）｜建筑列表 | 列表可读、左下按钮未激活状态",
	"08g_build_selected": "修建浮窗（选中一项）｜完整效果展开 | 效果文字完整、左下 [取消][修建] 已亮起",
	"09_treasure_character": "至宝·角色页 | 单位列表与右侧详情",
	"09_treasure_gear": "至宝·装备页 | 排版",
	"09_treasure_item": "至宝·道具页 | 排版",
	"10_character_main": "角色页·主要（三级按钮：主要/技能/职业/位阶） | 三级按钮排布、属性表",
	"10_character_skill": "角色页·技能 | 技能条目",
	"10_character_profession": "角色页·职业 | 职业说明",
	"10_character_rank": "角色页·位阶 | 位阶与经验倍率",
	"12_log_task": "日志·任务页 | 任务列表、按钮",
	"12_log_record": "日志·记录页 | 10 个存档槽",
	"12_log_codex": "日志·图鉴页 | 两级分类",
	"12_log_manual": "日志·手册页 | 分组导航 + 搜索框",
	"13_codex_civ_rarity": "图鉴：文明组 + 稀有度同时生效 | 两个筛选同时起作用、结果正确",
	"14_codex_profession": "图鉴：职业分类 | 职业条目",
	"17_dialog_draw": "十连抽卡结果弹窗 | 卡片排布、稀有度标识",
	"19_dialog_cheat": "作弊菜单弹窗 | 资源输入框、摧毁敌人列表；**底部按钮没有被挤出屏幕**",
	"20_unit_panel": "世界页·单位操作窗（点中棋子图标）｜立绘 + 攻/移 | 三个按钮（攻击/移动/驻军）",
	"21_recruit_pick": "世界页·招募选地模式 | 可部署地块高亮、提示文字",
	"22_back_to_map": "收尾：全部弹窗/浮窗关掉后的纯地图 | 确认没有残留浮窗（这是「关干净」的证据）",
}


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_arm_watchdog()
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await get_tree().process_frame
	await get_tree().process_frame

	# 1) 主页面
	var menu_holder := U.host(self)
	var menu: Control = load("res://scripts/ui/menu_screen.gd").new()
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_holder.add_child(menu)
	_menu = menu
	await _shoot("01_menu")
	# v1.8.9：加载界面（右下进度条 + 左下 tips）。
	# 它是过场，只在"新游戏/读档"的主流程里出现，所以这里单独摆一个来拍。
	var load_holder := U.host(self)
	var load_scr: Control = load("res://scripts/ui/loading_screen.gd").new()
	load_scr.set_anchors_preset(Control.PRESET_FULL_RECT)
	load_holder.add_child(load_scr)
	for fl in 4:
		await get_tree().process_frame
	load_scr.call("begin")
	# 让它走一会儿，拍"进度条在走"的中间态（而不是 0% 或 100%）
	for fl2 in 30:
		await get_tree().process_frame
	await _shoot("01b_loading")
	load_holder.queue_free()
	for fl3 in 3:
		await get_tree().process_frame
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
	var cheat_box: Variant = U.find_toggle(menu, "作弊功能")
	if cheat_box != null:
		(cheat_box as Button).button_pressed = true
		for f2b in 6:
			await get_tree().process_frame
		await _shoot("02d_dialog_cheat_confirm")
		# 点确认，看勾选态
		var ok_btn: Variant = U.find_button(menu, "确认")
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
	var gs_holder := U.host(self)
	var gs: Control = load("res://scripts/ui/game_screen.gd").new()
	gs.set_anchors_preset(Control.PRESET_FULL_RECT)
	gs_holder.add_child(gs)
	_gs = gs
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

	# 游戏页开拍前先清一遍（主页面那边可能还留着宿主 / 弹窗）
	await _clean("游戏页开拍前")

	# v1.8.6：日志已从一级按钮搬到右上角浮窗，所以这里不再拍"日志页"。
	# 用显式文件名，避免删一张就整体倒号（旧名字保持不变，少一张就少一个号）。
	var views := [["treasure", "04_view_treasure"], ["gacha", "05_view_gacha"], ["world", "07_view_world"]]
	for v in views:
		gs.call("goto_view", str(v[0]))
		# 布局需要几帧才能稳定（尤其是世界页的地图控件）
		for f in 4:
			await get_tree().process_frame
		await _shoot(str(v[1]))

	# 上一组（04/05/07）会留下"至宝 / 世界泡"的页级浮窗 —— 必须先关，否则会串进角落浮窗的图里
	await _clean("角落浮窗前")

	# v1.8.6：两个角落浮窗 —— 日志（右上书本，四周留边露出地图）与科技树（左上）
	gs.call("goto_view", "world")
	for f in 4:
		await get_tree().process_frame
	gs.call("_toggle_log_panel")
	for f in 4:
		await get_tree().process_frame
	await _shoot("06_log_window")
	gs.call("_toggle_log_panel")
	gs.call("_toggle_tech_panel")
	for f in 4:
		await get_tree().process_frame
	await _shoot("06b_tech_window")
	gs.call("_toggle_tech_panel")
	# v1.8.11：统计面板（资源栏中间的「统计」入口，默认看资源）
	gs.call("_toggle_stats_panel")
	for f111 in 5:
		await get_tree().process_frame
	await _shoot("06c_stats_res")
	var v111_sp: Variant = gs.get("stats_panel")
	if v111_sp != null:
		(v111_sp as Node).set("tab", "unit")
		(v111_sp as Node).call("refresh")
		for f112 in 5:
			await get_tree().process_frame
		await _shoot("06d_stats_units")
		(v111_sp as Control).visible = false
		for f113 in 2:
			await get_tree().process_frame

	# v1.8.5：旧的右侧规划面板已删除，改拍新浮窗（简约地块信息 / 据点管理窗口 / 右键菜单 / 修建浮窗）
	gs.call("goto_view", "world")
	for f in 4:
		await get_tree().process_frame
	var wp: Variant = gs.get("views")["world"]
	_wp = wp
	var v185_cap := str(GameState.state["capital"])
	# ① 简约地块信息小窗：点一块非我方地块
	var v185_other := ""
	for k in GameState.state["tiles"].keys():
		if str(k) != v185_cap and str(GameState.tile_at(str(k)).get("owner", "")) != "player":
			v185_other = str(k)
			break
	if v185_other != "":
		(wp as Node).call("_on_tile_clicked", v185_other, "", Vector2(520, 330))
		for f in 4:
			await get_tree().process_frame
		await _shoot("08a_tile_info")
	# 简约信息小窗和据点管理窗口是**两个不同的东西**，中间必须关一次
	await _clean("简约信息小窗拍完")
	# ② 据点管理窗口（三个页签各一张）
	(wp as Node).call("_on_tile_clicked", v185_cap, "", Vector2(400, 300))
	for f in 4:
		await get_tree().process_frame
	await _shoot("08b_stronghold_info")
	var v185_sp: Variant = (wp as Node).get("stronghold_panel")
	if v185_sp != null:
		for v185_tab in [["decree", "08c_stronghold_decree"], ["labor", "08d_stronghold_labor"]]:
			(v185_sp as Node).set("tab", str(v185_tab[0]))
			(v185_sp as Node).call("refresh")
			for f in 4:
				await get_tree().process_frame
			await _shoot(str(v185_tab[1]))
		(v185_sp as Control).visible = false
	await _clean("据点管理窗口拍完")
	# ③ 右键菜单 + 修建浮窗（选中态各一张）
	(wp as Node).call("_on_tile_right_clicked", v185_cap, Vector2(520, 330))
	for f in 4:
		await get_tree().process_frame
	await _shoot("08e_tile_menu")
	(wp as Node).call("_hide_action_menu")
	(wp as Node).call("_run_tile_action", "build", v185_cap)
	for f in 5:
		await get_tree().process_frame
	await _shoot("08f_build_panel")
	var v185_bp: Variant = (wp as Node).get("build_panel")
	if v185_bp != null:
		(v185_bp as Node).call("select_row", "classic_field")
		for f in 4:
			await get_tree().process_frame
		await _shoot("08g_build_selected")
		(v185_bp as Control).visible = false


	await _clean("至宝组开拍前")

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
	# v1.8.10：「编队」入口已隐藏（页面代码还在，但不在游戏里可达）
	for st in ["main", "skill", "profession", "rank"]:
		cp.set("sub_tab", st)
		cp.call("refresh")
		for f0 in 4:
			await get_tree().process_frame
		await _shoot("10_character_%s" % st)

	# ⚠️ 至宝那组是**页级浮窗**（09/10 共 7 张都开着它），不关的话会把下面这一整组日志图全污染掉
	await _clean("日志组开拍前（先关掉至宝浮窗）")

	# 日志的子页（v1.8.6：日志不再是页面，而是右上角书本打开的浮窗；内容还是同一个 log_view）
	gs.call("_toggle_log_panel")
	for f in 4:
		await get_tree().process_frame
	var lv: Variant = (gs.get("log_panel") as Node).get("page")
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



	await _clean("作弊菜单前（先关掉日志浮窗）")

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

	await _clean("抽卡弹窗前")

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
		# v1.8.2：直接点中棋子图标（信号里带 uid）→ 左下角弹出单位操作窗。
		# （以前靠"同格连点两次轮换"轮到单位，那个机制已取消。）
		(wv as Node).call("_on_tile_clicked", cap2, str(c_shot["uid"]), Vector2.ZERO)
	for fw2 in 3:
		await get_tree().process_frame
	await _shoot("20_unit_panel")
	await _clean("招募选地前（关掉单位操作窗）")

	# 招募选地模式
	GameState.begin_recruit(str(g_shot["uid"]))
	if wv != null:
		(wv as Node).call("refresh")
	for fw3 in 3:
		await get_tree().process_frame
	await _shoot("21_recruit_pick")

	# 收尾：全部关掉 → 拍一张"纯地图"作为"关干净"的证据 → 写清单
	await _clean("收尾")
	await _shoot("22_back_to_map")
	_write_manifest()

	print("截图完成，共 %d 张，输出目录 %s" % [shot, OUT_DIR])
	get_tree().quit(0)


## **关干净**：对话框 / 页级浮窗 / 工具浮窗（科技树·日志·统计）/ 世界页上的各种小窗，一个不留。
## 每个"拍摄组"前后都调用它 —— 不这么做，上一组开着的窗口会串进下一组图里
## （视觉检查时这属于**污染**：会让人分不清"这是新弹的窗"还是"上一张没收的窗"）。
func _clean(tag: String = "") -> void:
	if _menu != null and is_instance_valid(_menu):
		(_menu as Node).call("close_dialog")
	if _gs != null and is_instance_valid(_gs):
		(_gs as Node).call("close_dialog")
		(_gs as Node).call("_close_all_panels")
		(_gs as Node).call("_close_res_popup")
		for key in ["tech_panel", "log_panel", "stats_panel"]:
			var p: Variant = (_gs as Node).get(key)
			if p != null and is_instance_valid(p):
				(p as Control).visible = false
	if _wp != null and is_instance_valid(_wp):
		(_wp as Node).call("_hide_action_menu")
		for key2 in ["tile_info_popup", "stronghold_panel", "build_panel", "unit_panel", "action_menu"]:
			var n: Variant = (_wp as Node).get(key2)
			if n != null and is_instance_valid(n):
				(n as Control).visible = false
		(_wp as Node).call("refresh")
	for i in 3:
		await get_tree().process_frame
	if tag != "":
		print("  [clean] " + tag)


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


func _shoot(name: String) -> void:
	_last_shot = name
	# 多等几帧：视觉检查要的是**稳定态**，不能拍到布局还没算完 / 动画刚起步的那一帧
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, name]
	var err := img.save_png(path)
	if err != OK:
		print("  [FAIL] 保存 %s 失败（错误 %d）" % [path, err])
	else:
		shot += 1
		_taken.append(name)
		print("  [ok] %s  (%dx%d)" % [path, img.get_width(), img.get_height()])


## 写一份产物清单：文件名 + 内容 + 该看什么。视觉检查对着它逐张看。
func _write_manifest() -> void:
	var lines: Array[String] = []
	lines.append("# 截图自检产物清单（给视觉检查用）")
	lines.append("")
	lines.append("> 由 `tests/screenshot.gd` 生成；共 %d 张，**按拍摄顺序**排列。" % _taken.size())
	lines.append("> **每张都是「单一状态」**：每个拍摄组前后都会把所有弹窗 / 浮窗关掉（见 `_clean()`），")
	lines.append("> 所以图里出现的窗口一定是**这张图故意开的**，不是你漏关的。")
	lines.append("> 末张 `22_back_to_map` 是「关干净」的证据。")
	lines.append("")
	lines.append("| 文件 | 内容 | 该看什么 |")
	lines.append("| --- | --- | --- |")
	for n in _taken:
		# 文档写法统一是：「内容 · 补充 | 该看什么」——列分隔用 " | "（竖线两边各一个空格）
		var doc := str(SHOT_DOCS.get(n, "（未登记 —— 请在 SHOT_DOCS 里补一行）")).replace("｜", " · ")
		var sep := doc.find(" | ")
		var what := doc if sep < 0 else doc.substr(0, sep)
		var look := "" if sep < 0 else doc.substr(sep + 3)
		lines.append("| `%s.png` | %s | %s |" % [n, what, look])
	var f := FileAccess.open("%s/00_MANIFEST.md" % OUT_DIR, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines) + "\n")
		f.close()
		print("  [ok] 清单已写：%s/00_MANIFEST.md" % OUT_DIR)
