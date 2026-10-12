extends Node
## 无头自检（作为主场景运行，这样才能拿到 autoload 单例 GameState）。
##
## 用法：godot --headless --path <项目> res://tests/selfcheck.tscn
## 或者用 --headless --path <项目> 并临时把 run/main_scene 指向本场景。

var failed := 0


func _ready() -> void:
	print("== 脚本加载检查 ==")
	var files := _gd_files("res://")
	for f in files:
		if f.begins_with("res://addons/"):
			continue
		var s: Variant = load(f)
		if s == null:
			print("  [FAIL] %s" % f)
			failed += 1
	print("  共 %d 个脚本，加载失败 %d 个" % [files.size(), failed])

	print("\n== 场景实例化检查 ==")
	_check_scene("res://scenes/main.tscn")

	print("\n== 核心逻辑试跑 ==")
	_core_loop()

	print("\n== 抽卡试跑 ==")
	_gacha_loop()

	print("\n== 威胁推进与攻击结算 ==")
	for i in 9:
		var rep: Dictionary = GameState.end_cycle()
		for e in rep["events"]:
			print("    周期 %d：%s" % [int(rep["cycle"]), e])
	print("  威胁 %s" % str(GameState.state["threats"]))
	print("  敌人地块 %d｜稳定度 %.1f%%｜幸福度 %.0f" % [
		GameState.enemy_tiles().size(), GameState.stability() * 100.0, GameState.happiness()])

	print("\n== 科技 ==")
	print("  研究「炼金-黑土」(缺前置) -> %s" % str(GameState.research("alchemy_black_soil")))
	GameState.add_res("research", 500.0)
	print("  研究「开采」-> %s" % str(GameState.research("mining")))
	print("  重复研究「开采」-> %s" % str(GameState.research("mining")))

	print("\n== 存档 ==")
	print("  保存到槽位 3 -> %s｜摘要 %s" % [GameState.save_to_slot(3), str(GameState.slot_summary(3))])
	var cyc := int(GameState.state["cycle"])
	print("  读取槽位 3 -> %s｜周期 %d" % [GameState.load_from_slot(3), int(GameState.state["cycle"])])
	print("  删除槽位 3 -> %s" % GameState.delete_slot(3))

	print("\n== UI 视图逐个实例化 ==")
	var ui_scripts := [
		"res://scripts/ui/menu_screen.gd",
		"res://scripts/ui/game_screen.gd",
		"res://scripts/ui/views/treasure_view.gd",
		"res://scripts/ui/views/gacha_view.gd",
		"res://scripts/ui/views/log_view.gd",
		"res://scripts/ui/views/view_world_page.gd",
		"res://scripts/ui/views/parts/character_page.gd",
		"res://scripts/ui/views/parts/gear_page.gd",
		"res://scripts/ui/views/parts/item_page.gd",
		"res://scripts/ui/views/parts/task_page.gd",
		"res://scripts/ui/views/parts/record_page.gd",
		"res://scripts/ui/views/parts/codex_page.gd",
		"res://scripts/ui/views/parts/manual_page.gd",
		"res://scripts/ui/hex_map_view.gd",
	]
	for p in ui_scripts:
		var ok := _instantiate_ui(str(p))
		if not ok:
			failed += 1

	print("\n== 试跑结束，失败 %d 项 ==" % failed)
	get_tree().quit(0 if failed == 0 else 1)


func _check_scene(path: String) -> void:
	var ps: PackedScene = load(path)
	if ps == null:
		print("  [FAIL] 无法加载场景 %s" % path)
		failed += 1
		return
	var inst: Node = ps.instantiate()
	if inst == null:
		print("  [FAIL] 无法实例化 %s" % path)
		failed += 1
		return
	print("  [ok] 主场景可实例化：%s" % inst.name)
	# 后台添加一帧再移除，验证 _ready 不报错
	add_child(inst)
	inst.queue_free()


func _instantiate_ui(path: String) -> bool:
	var scr: Variant = load(path)
	if scr == null:
		print("  [FAIL] 无法加载 %s" % path)
		return false
	var c: Variant = (scr as GDScript).new()
	if c == null:
		print("  [FAIL] 无法实例化 %s" % path)
		return false
	var ctrl := c as Control
	if ctrl == null:
		print("  [FAIL] %s 不是 Control" % path)
		return false
	add_child(ctrl)
	# 触发一次绘制与刷新
	ctrl.size = Vector2(1280, 720)
	if ctrl.has_method("refresh"):
		ctrl.refresh()
	if ctrl.has_method("on_cycle_finished"):
		ctrl.on_cycle_finished({})
	ctrl.queue_free()
	print("  [ok] %s" % path.get_file())
	return true


func _core_loop() -> void:
	var cap_key: String = str(GameState.state["capital"])
	print("  地块总数 %d｜已点亮 %d｜无主 %d｜我方 %d" % [
		int(GameState.state["tiles"].size()), GameState.discovered_tiles().size(),
		GameState.free_tiles().size(), GameState.owned_tiles().size()])
	print("  初始 稳定度 %.1f%%｜幸福度 %.1f｜文化率 %.2f｜人力 %d（空闲 %d）" % [
		GameState.stability() * 100.0, GameState.happiness(), GameState.culture_rate(),
		int(GameState.state["pop_total"]), GameState.free_pop()])

	for bid in ["classic_field", "classic_workshop", "classic_house"]:
		var rb: Dictionary = GameState.build(cap_key, bid)
		print("  建造 %-18s -> %s %s" % [bid, rb["ok"], rb["why"]])
	for bid in ["classic_field", "classic_workshop"]:
		var ra: Dictionary = GameState.assign_worker(cap_key, bid, 1)
		print("  指派人力 %-16s -> %s %s" % [bid, ra["ok"], ra["why"]])

	for i in 5:
		var rep: Dictionary = GameState.end_cycle()
		print("  周期 %2d -> 食物 %5.1f 生产力 %5.1f 科研 %4.1f 货币 %6.0f 人力 %2d 幸福 %4.0f 稳定 %3.0f%%" % [
			int(rep["cycle"]), GameState.res("food"), GameState.res("production"),
			GameState.res("research"), GameState.res("currency"), int(GameState.state["pop_total"]),
			rep["happiness"], rep["stability"] * 100.0])
		for e in rep["events"]:
			print("      ！%s" % e)

	var cks := WorldGen.claimable_keys(GameState.state)
	print("  可占领 %d 块｜扩张消耗 %.0f 行政点数" % [cks.size(), WorldGen.claim_cost(GameState.state)])
	if not cks.is_empty():
		GameState.add_res("admin", 800.0)
		var cr: Dictionary = WorldGen.claim(GameState.state, cks[0])
		print("  占领 %s -> %s %s" % [cks[0], cr["ok"], cr["why"]])
		print("  占领后该地块归属据点：%s" % GameState.stronghold_of(GameState.tile_at(cks[0])))


func _gacha_loop() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20240607
	for p in [Gacha.Pool.ROTATION, Gacha.Pool.RESOURCE, Gacha.Pool.DEVELOPMENT]:
		print("  %s 池：%s" % [Gacha.POOL_NAMES[p], Gacha.pity_text(GameState.state, p)])
	GameState.add_res("cohesion", 40000.0)
	GameState.add_res("order_crystal", 300.0)

	var r1: Dictionary = Gacha.draw_ten(GameState.state, Gacha.Pool.ROTATION, rng)
	print("  轮换十连 ok=%s 获得 %d 张" % [r1["ok"], (r1["cards"] as Array).size()])
	_print_cards(r1["cards"])
	for e in r1["events"]:
		print("      事件：%s" % e)

	var r2: Dictionary = Gacha.draw_ten(GameState.state, Gacha.Pool.RESOURCE, rng)
	print("  资源十连 ok=%s 获得 %d 张" % [r2["ok"], (r2["cards"] as Array).size()])
	_print_cards(r2["cards"])

	var r3: Dictionary = Gacha.draw(GameState.state, Gacha.Pool.DEVELOPMENT, rng)
	print("  发展单抽 ok=%s 获得 %d 张" % [r3["ok"], (r3["cards"] as Array).size()])
	_print_cards(r3["cards"])
	for e in r3["events"]:
		print("      事件：%s" % e)

	print("  角色 %d 名｜装备 %d 件｜道具 %d 种｜终极威胁 %d 个" % [
		(GameState.state["units"] as Array).size(), (GameState.state["equipment"] as Array).size(),
		(GameState.state["items"] as Dictionary).size(), (GameState.state["threats"] as Array).size()])
	print("  保底推进后：%s" % Gacha.pity_text(GameState.state, Gacha.Pool.ROTATION))
	print("  手动手卡组轮换 -> %s" % Gacha.rotate_group(GameState.state, rng))


func _print_cards(cards: Array) -> void:
	var by_r := {}
	for c in cards:
		var r := int(c["rarity"])
		if not by_r.has(r):
			by_r[r] = []
		(by_r[r] as Array).append("%s(%s)" % [c["name"], c["kind"]])
	var keys := by_r.keys()
	keys.sort()
	keys.reverse()
	for k in keys:
		print("      %d★ %s" % [k, "、".join(by_r[k])])


func _gd_files(dir: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		var path := dir.path_join(n) if dir != "res://" else "res://" + n
		if d.current_is_dir():
			if n != "." and n != ".." and not n.begins_with("."):
				out.append_array(_gd_files(path))
		elif n.ends_with(".gd"):
			out.append(path)
		n = d.get_next()
	d.list_dir_end()
	return out