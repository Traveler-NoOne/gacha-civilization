extends Node
const U := preload("res://tests/test_util.gd")
## 作弊开关「跨开始游戏存活」回归测试。
##
## 复现用户报的问题：勾选作弊后，点「新游戏 / 继续游戏 / 读取游戏」，
## 顶部没有「作弊」按钮，回主菜单一看勾选又被取消了。
##
## 根因：作弊开关原本存在 GameState.state 里，而 new_game() / 读档 会重建 state，
## 开关被重置。现在改成全局设置 AppSettings（user://settings.cfg）。
##
## 用法：godot --headless --path <项目> res://tests/diag_cheat_persist.tscn

var suite := U.reporter("作弊设置持久化")


func _ready() -> void:
	# 清掉可能存在的旧设置文件，从干净状态开始
	var abs_path := ProjectSettings.globalize_path(AppSettings.SETTINGS_PATH)
	if FileAccess.file_exists(AppSettings.SETTINGS_PATH):
		DirAccess.remove_absolute(abs_path)
	AppSettings.load_settings()
	AppSettings.set_cheat_enabled(false)
	AppSettings.set_autosave_interval(1)

	print("== 0. 初始状态 ==")
	print("  作弊开关 = %s（期望 false）" % AppSettings.cheat_enabled())

	# ---------- 1. 勾选作弊 ----------
	print("\n== 1. 勾选作弊功能 ==")
	AppSettings.set_cheat_enabled(true)
	print("  勾选后 = %s（期望 true）" % AppSettings.cheat_enabled())
	if not AppSettings.cheat_enabled():
		suite.fail("勾选没生效")
	print("  设置文件是否写入？%s" % FileAccess.file_exists(AppSettings.SETTINGS_PATH))

	# ---------- 2. 新游戏后开关必须还在 ----------
	print("\n== 2. 点「新游戏」之后 ==")
	GameState.new_game(20240607)
	print("  new_game() 之后 作弊开关 = %s（期望 true）" % AppSettings.cheat_enabled())
	if not AppSettings.cheat_enabled():
		suite.fail("new_game() 把作弊开关重置了")

	# 建一个游戏主页，检查顶部按钮
	var gs: Control = load("res://scripts/ui/game_screen.gd").new()
	gs.name = "GameScreen"
	gs.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(gs)
	for i in 6:
		await get_tree().process_frame
	var cb: Variant = gs.get("cheat_button")
	print("  顶部「作弊」按钮 visible = %s（期望 true）" % (cb as Button).visible)
	if not (cb as Button).visible:
		suite.fail("新游戏后顶部没有作弊按钮")

	# ---------- 3. 继续游戏（读自动存档） ----------
	print("\n== 3. 点「继续游戏」之后 ==")
	GameState.add_res("food", 123.0)     # 留个标记，确认读档真的发生了
	GameState.autosave()
	GameState.new_game(111)              # 先切到别的状态
	var loaded := GameState.continue_game()
	print("  读档成功？%s｜周期 %d" % [loaded, int(GameState.state["cycle"])])
	print("  读档后 作弊开关 = %s（期望 true）" % AppSettings.cheat_enabled())
	if not AppSettings.cheat_enabled():
		suite.fail("读档把作弊开关重置了")
	(cb as Button).visible = AppSettings.cheat_enabled()
	gs.call("_refresh")
	for i in 4:
		await get_tree().process_frame
	print("  顶部「作弊」按钮 visible = %s（期望 true）" % (cb as Button).visible)
	if not (cb as Button).visible:
		suite.fail("继续游戏后顶部没有作弊按钮")

	# ---------- 4. 读取游戏（手动槽位） ----------
	print("\n== 4. 点「读取游戏」之后 ==")
	GameState.save_to_slot(3)
	GameState.new_game(222)
	print("  新开一局后 作弊开关 = %s（期望 true，因为它是全局设置）" % AppSettings.cheat_enabled())
	var loaded2 := GameState.load_from_slot(3)
	for i in 4:
		await get_tree().process_frame
	gs.call("_refresh")
	print("  读档成功？%s｜作弊开关 = %s（期望 true）" % [loaded2, AppSettings.cheat_enabled()])
	if not AppSettings.cheat_enabled():
		suite.fail("读取游戏把作弊开关重置了")
	print("  顶部「作弊」按钮 visible = %s（期望 true）" % (cb as Button).visible)
	if not (cb as Button).visible:
		suite.fail("读取游戏后顶部没有作弊按钮")
	GameState.delete_slot(3)

	# ---------- 5. 关掉作弊后不应该再出现 ----------
	print("\n== 5. 取消勾选之后 ==")
	AppSettings.set_cheat_enabled(false)
	for i in 4:
		await get_tree().process_frame
	print("  顶部「作弊」按钮 visible = %s（期望 false）" % (cb as Button).visible)
	if (cb as Button).visible:
		suite.fail("取消勾选后按钮还在")
	GameState.new_game(333)
	for i in 4:
		await get_tree().process_frame
	print("  新游戏后 作弊开关 = %s（期望 false）" % AppSettings.cheat_enabled())
	if AppSettings.cheat_enabled():
		suite.fail("取消勾选后又自己打开了")

	# ---------- 6. 设置文件持久化（模拟重启游戏） ----------
	print("\n== 6. 模拟重启：重新读取设置文件 ==")
	AppSettings.set_cheat_enabled(true)
	AppSettings.set_autosave_interval(4)
	# 清掉内存里的值，再从文件读
	AppSettings._cheat_enabled = false
	AppSettings._autosave_interval = 1
	AppSettings.load_settings()
	print("  重读设置：作弊 = %s（期望 true）｜自动存档间隔 = %d（期望 4）" % [
		AppSettings.cheat_enabled(), AppSettings.autosave_interval()])
	if not AppSettings.cheat_enabled():
		suite.fail("重启后作弊开关没恢复")
	if AppSettings.autosave_interval() != 4:
		suite.fail("重启后自动存档间隔没恢复")

	# ---------- 7. 旧存档里残留字段要被清掉 ----------
	print("\n== 7. 旧存档兼容 ==")
	var slot := 7
	var legacy := {
		"magic": GameState.SAVE_MAGIC, "version": 1, "saved_at": "legacy",
		"state": {
			"cycle": 5, "capital": "0,0", "tiles": GameState.state["tiles"],
			"res": {}, "techs": [], "log": [],
			# 旧版本把这些存在存档里
			"cheat_enabled": false, "autosave_interval": 9,
		},
	}
	var f := FileAccess.open(GameState.slot_path(slot), FileAccess.WRITE)
	f.store_string(JSON.stringify(legacy, "  "))
	f.close()
	GameState.load_from_slot(slot)
	print("  读旧存档后：state 里还有 cheat_enabled 吗？%s（期望 false）" % GameState.state.has("cheat_enabled"))
	print("  读旧存档后：state 里还有 autosave_interval 吗？%s（期望 false）" % GameState.state.has("autosave_interval"))
	print("  而全局设置仍然是：作弊 = %s（期望 true，不受存档影响）" % AppSettings.cheat_enabled())
	if GameState.state.has("cheat_enabled") or GameState.state.has("autosave_interval"):
		suite.fail("旧存档的残留字段没有被清掉")
	if not AppSettings.cheat_enabled():
		suite.fail("读旧存档影响了全局作弊开关")
	GameState.delete_slot(slot)

	# 收尾：恢复默认
	AppSettings.set_cheat_enabled(false)
	AppSettings.set_autosave_interval(1)

	suite.finish(get_tree())