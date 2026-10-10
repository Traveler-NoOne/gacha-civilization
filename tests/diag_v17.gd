extends Node
const U := preload("res://tests/test_util.gd")
## v1.7 护栏：把"整体优化"这一轮定下的规矩钉死，防止以后再漂。
## 覆盖：收支口径同源 / 移动高亮即可达 / 资源↔图标一一对应 / 职业映射合法 /
##       卡组列表一致 / 建筑每级加成 > 维护费 / 无死常量。
## 用法：godot --headless --path <项目> res://tests/diag_v17.tscn

var suite := U.reporter("v1.7 护栏")
func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


## 递归收集 res:// 下所有 .gd（跳过点号目录）
func _all_gd(dir_path: String, out: Array) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		var full := dir_path.path_join(n)
		if d.current_is_dir():
			if not n.begins_with(".") and n != "addons":
				_all_gd(full, out)
		elif n.ends_with(".gd"):
			out.append(full)
		n = d.get_next()
	d.list_dir_end()


func _ready() -> void:
	await get_tree().process_frame
	GameState.new_game(20270101)

	print("== 1. 收支口径同源（管理页 = 悬浮窗 = resource_breakdown）==")
	var est := GameState.income_estimate()
	var bad := 0
	for k in est.keys():
		var sum := 0.0
		var bd := GameState.resource_breakdown(k)
		for e in bd["income"]:
			sum += float(e["amount"])
		for e in bd["upkeep"]:
			sum += float(e["amount"])
		if absf(sum - float(est[k])) > 0.001:
			bad += 1
	print("  income_estimate 有 %d 项，与明细不一致 %d 项" % [est.size(), bad])
	if bad > 0:
		suite.fail("income_estimate 与 resource_breakdown 口径不一致")
	# v1.8.10：管理页自 v1.8.7 起**已无入口**，原来的护栏是在检查一具尸体。
	# 这条护栏的本意是"界面显示收支，不许自己再写一套算法" —— 现在把它盯到**活的展示方**上：
	#   · 统计面板（v1.8.11，资源页会显示每周期净收支）
	#   · 顶栏资源栏的收支悬浮窗（game_screen._show_res_info）
	for src_path in [
		"res://scripts/ui/panels/stats_panel.gd",
		"res://scripts/ui/game_screen.gd",
	]:
		var src := _read(src_path)
		if src.contains("_estimate_income"):
			suite.fail("%s 里出现了私有的 _estimate_income（应只用 GameState.resource_breakdown / income_estimate）" % src_path.get_file())
		if not src.contains("resource_breakdown"):
			suite.fail("%s 没有用 resource_breakdown（收支口径应同源）" % src_path.get_file())

	print("\n== 2. 移动高亮 == 实际可达 ==")
	GameState.reset_unit_moves()
	var bad_move := 0
	var checked := 0
	for u in GameState.state["units"]:
		if str(u.get("tile", "")) == "":
			continue
		for k in GameState.move_candidates(str(u["uid"])):
			checked += 1
			if not bool(GameState.can_move_to(str(u["uid"]), k)["ok"]):
				bad_move += 1
	print("  候选格 %d 个，move_unit 会拒绝的 %d 个" % [checked, bad_move])
	if bad_move > 0:
		suite.fail("move_candidates 给出了 can_move_to 不接受的格子（高亮却走不过去）")

	print("\n== 3. 资源 ↔ 图标一一对应 ==")
	var missing: Array[String] = []
	for k in Consts.RES_KEYS:
		if not FileAccess.file_exists("res://art/icons/%s.png" % k):
			missing.append(k)
	print("  RES_KEYS %d 项，缺图 %d 项 %s" % [Consts.RES_KEYS.size(), missing.size(), str(missing)])
	if not missing.is_empty():
		suite.fail("有资源没有对应图标（改名后最容易漏图）")

	print("\n== 4. 职业映射合法 ==")
	var illegal: Array[String] = []
	for card_id in CardDB.PROFESSION_BY_ID.keys():
		var p := str(CardDB.PROFESSION_BY_ID[card_id])
		if not UnitDB.PROFESSIONS.has(p):
			illegal.append("%s->%s" % [card_id, p])
	print("  映射 %d 条，非法 %d 条 %s" % [CardDB.PROFESSION_BY_ID.size(), illegal.size(), str(illegal)])
	if not illegal.is_empty():
		suite.fail("PROFESSION_BY_ID 里有 UnitDB.PROFESSIONS 不认的职业")

	print("\n== 5. 卡组列表一致（GROUPS 去掉「通用」应等于 CIV_GROUPS）==")
	var g: Array[String] = []
	for x in CardDB.GROUPS:
		if str(x) != "通用":
			g.append(str(x))
	print("  轮换顺序 %s ｜ 展示顺序 %s" % [str(g), str(CardDB.CIV_GROUPS)])
	if g != CardDB.CIV_GROUPS:
		suite.fail("GROUPS 与 CIV_GROUPS 的顺序/内容不一致（轮换顺序会与界面不符）")

	print("\n== 6. 建筑：每级加成必须 > 每级维护 ==")
	var weak: Array[String] = []
	for def in GameState.building_defs:
		for k in def.yield_per_level.keys():
			if float(def.yield_per_level[k]) <= Consts.BUILDING_UPKEEP_PRODUCTION:
				weak.append("%s.%s=%.2f" % [def.id, k, float(def.yield_per_level[k])])
	print("  每级维护 %.2f；加成不足的建筑 %d 个 %s" % [
		Consts.BUILDING_UPKEEP_PRODUCTION, weak.size(), str(weak)])
	if not weak.is_empty():
		suite.fail("有建筑的每级加成 <= 每级维护（升级会变成负收益）")

	print("\n== 7. 无死常量（constants.gd 每个常量都被引用过）==")
	var files: Array = []
	_all_gd("res://scripts", files)
	_all_gd("res://tests", files)
	var texts := {}
	for f in files:
		texts[f] = _read(str(f))
	var scr := load("res://scripts/data/constants.gd") as Script
	var dead: Array[String] = []
	# 判定口径：该名字在全项目里出现次数 <= 1（只有声明那一次）才算死。
	# 不能"排除 constants.gd 整个文件" —— 像 RES_NAMES / RARITY_COLORS 这些
	# 是在本文件内被 res_name() / rarity_color() 这类访问函数读的。
	for name in scr.get_script_constant_map().keys():
		var count := 0
		for f in texts.keys():
			count += (texts[f] as String).count(str(name))
		if count <= 1:
			dead.append(str(name))
	print("  常量 %d 个，无人引用 %d 个 %s" % [
		scr.get_script_constant_map().size(), dead.size(), str(dead)])
	if not dead.is_empty():
		suite.fail("constants.gd 里存在死常量：" + str(dead))

	print("\n== 8. 版本号一致（DEMO_VERSION_FULL 应包含 DEMO_VERSION）==")
	print("  %s ｜ %s" % [Consts.DEMO_VERSION, Consts.DEMO_VERSION_FULL])
	if not Consts.DEMO_VERSION_FULL.contains(Consts.DEMO_VERSION):
		suite.fail("版本号两个常量不一致")

	suite.finish(get_tree())