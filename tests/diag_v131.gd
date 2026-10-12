extends Node
const U := preload("res://tests/test_util.gd")
## v1.3.1 自检：据点/地块解耦、可用土地计容、规划队列、生产力上限、
##          行政点数（基底/收支/击杀/阵亡）、行政影响力、面板改名。
## 用法：godot --headless --path <项目> res://tests/diag_v131.tscn

var suite := U.reporter("v1.3.1 自检")
func _ready() -> void:
	print("== 1. 据点 / 地块 解耦 ==")
	GameState.new_game(20261006)
	var shs := GameState.strongholds()
	print("  据点数：%d（期望 >= 1）" % shs.size())
	if shs.is_empty():
		suite.failed += 1
	var cap := str(GameState.state["capital"])
	var cap_tile := GameState.tile_at(cap)
	print("  首都地块归属据点：%s（期望 sh_capital）" % GameState.stronghold_of(cap_tile))
	if GameState.stronghold_of(cap_tile) != "sh_capital":
		suite.failed += 1
	var sh0: Dictionary = shs[0] if not shs.is_empty() else {}
	print("  据点名：%s｜掌控力：%.2f（期望 1.0，预留）" % [
		str(sh0.get("name", "")), GameState.control_of(sh0)])
	if not is_equal_approx(GameState.control_of(sh0), 1.0):
		suite.failed += 1

	print("\n== 2. 可用土地计容 + 同种可重复 ==")
	GameState.state["res"]["production"] = 200.0
	GameState.state["res"]["currency"] = 5000.0
	var r1: Dictionary = GameState.build(cap, "classic_field")
	var r2: Dictionary = GameState.build(cap, "classic_field")
	print("  同种建两次：%s / %s（都应成功，允许重复）" % [r1["ok"], r2["ok"]])
	if not (r1["ok"] and r2["ok"]):
		suite.failed += 1
	print("  首都土地：已用 %.1f / 上限 %.1f" % [
		GameState.land_used(cap_tile), GameState.land_cap(cap_tile)])
	var r3: Dictionary = GameState.build(cap, "classic_workshop")   # 0.4 -> 1.2 > 1.0
	print("  再修 0.4 建筑：%s %s（期望失败：土地不足）" % [r3["ok"], str(r3.get("why", ""))])
	if r3["ok"]:
		suite.failed += 1

	print("\n== 3. 规划队列（生产力不足 -> 入队 -> 完工） ==")
	GameState.new_game(777)
	cap = str(GameState.state["capital"])
	cap_tile = GameState.tile_at(cap)
	GameState.build(cap, "classic_workshop")          # 花掉起始 20 生产力
	GameState.assign_worker(cap, "classic_workshop", 1)
	GameState.state["res"]["production"] = 0.0
	var qr: Dictionary = GameState.build(cap, "classic_field")   # 8 生产力，不够 -> 入队
	print("  生产力 0 时修建：ok=%s queued=%s（期望 queued=true）" % [qr["ok"], qr.get("queued", false)])
	if not (qr["ok"] and bool(qr.get("queued", false))):
		suite.failed += 1
	var q: Array = GameState.current_stronghold().get("queue", [])
	print("  队列长度：%d（期望 1）" % q.size())
	if q.size() != 1:
		suite.failed += 1
	for i in 10:
		GameState.end_cycle()
	var q2: Array = GameState.current_stronghold().get("queue", [])
	var fields := GameState.tile_buildings_of(GameState.tile_at(cap), "classic_field").size()
	print("  10 周期后：队列 %d，田地数量 %d（期望队列清空且已建成 1 块）" % [q2.size(), fields])
	if q2.size() != 0 or fields < 1:
		suite.failed += 1

	print("\n== 4. 生产力盈余上限 ==")
	GameState.state["res"]["production"] = 100.0
	GameState.current_stronghold()["queue"] = []
	GameState.end_cycle()
	print("  结算后生产力：%.1f（期望 <= %d）" % [
		GameState.res("production"), int(Consts.PRODUCTION_STORE_CAP)])
	if GameState.res("production") > Consts.PRODUCTION_STORE_CAP + 0.001:
		suite.failed += 1

	print("\n== 5. 行政点数（基底 / 击杀 buff / 阵亡 debuff / 计时） ==")
	var a0 := GameState.res("admin")
	GameState.end_cycle()
	print("  周期结算：行政点数 %.2f -> %.2f（期望增加）" % [a0, GameState.res("admin")])
	if GameState.res("admin") <= a0:
		suite.failed += 1
	GameState.state["admin_effects"] = []
	GameState.on_enemy_killed({"threat": true, "owner": "enemy", "force": 90.0})
	var eff: Array = GameState.state["admin_effects"]
	var delta0 := float(eff[0]["delta"]) if not eff.is_empty() else 0.0
	var dur0 := int(eff[0]["remaining"]) if not eff.is_empty() else 0
	print("  击杀终极威胁 -> buff 数 %d，delta %+.1f，时长 %d（期望 +1.0 / 100）" % [
		eff.size(), delta0, dur0])
	if eff.is_empty() or not is_equal_approx(delta0, 1.0) or dur0 != 100:
		suite.failed += 1
	GameState.end_cycle()
	var remain := 0
	if not (GameState.state["admin_effects"] as Array).is_empty():
		remain = int((GameState.state["admin_effects"] as Array)[0]["remaining"])
	print("  一周期后剩余时长：%d -> %d（期望递减）" % [dur0, remain])
	if remain >= dur0:
		suite.failed += 1
	GameState.on_unit_died(UnitDB.HERO)
	var has_debuff := false
	for e in GameState.state["admin_effects"]:
		if float(e["delta"]) < 0.0:
			has_debuff = true
	print("  角色阵亡后存在 debuff：%s（期望 true）" % has_debuff)
	if not has_debuff:
		suite.failed += 1

	print("\n== 6. 行政影响力（扩张越便宜） ==")
	var base_cost := WorldGen.claim_base_cost(GameState.state)
	GameState.state["res"]["admin"] = 0.0
	var c0 := WorldGen.claim_cost(GameState.state)
	GameState.state["res"]["admin"] = 10.0
	var c1 := WorldGen.claim_cost(GameState.state)
	GameState.state["res"]["admin"] = 100000.0
	var c2 := WorldGen.claim_cost(GameState.state)
	print("  基础 %d｜行政0 -> %.1f｜行政10 -> %.1f｜行政超多 -> %.1f（期望递减，封顶 -50%%）" % [
		int(base_cost), c0, c1, c2])
	if not (c0 > c1 and c1 > c2):
		suite.failed += 1
	if c2 < base_cost * (1.0 - Consts.ADMIN_INFLUENCE_MAX) - 0.01:
		suite.failed += 1

	print("\n== 7. UI：修建浮窗（v1.8.5：旧右侧规划面板已删除） ==")
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(holder)

	var world: Control = load("res://scripts/ui/views/view_world_page.gd").new()
	world.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(world)
	world.size = Vector2(1280, 600)
	for i in 4:
		await get_tree().process_frame
	# 旧面板的入口应该已经彻底不存在（不是"隐藏"，是方法都没了）
	print("  旧规划面板已删除？%s（期望 true）" % str(not world.has_method("switch_plan_tab") and not world.has_method("_refresh_build_list")))
	if world.has_method("switch_plan_tab") or world.has_method("_refresh_build_list"):
		suite.failed += 1
	# 新的修建入口：右键地块 → 🔨 → 修建浮窗
	world.call("_run_tile_action", "build", str(GameState.state["capital"]))
	for i in 4:
		await get_tree().process_frame
	var bp: Variant = world.get("build_panel")
	var bvisible := bp != null and (bp as Control).visible
	var brows := 0
	if bp != null:
		var lb: Variant = (bp as Node).get("list_box")
		if lb is Node:
			brows = (lb as Node).get_child_count()
	print("  修建浮窗：可见=%s  建筑行数=%d（应 > 2）" % [str(bvisible), brows])
	if not bvisible or brows <= 2:
		suite.failed += 1

	suite.finish(get_tree())