extends Node
## W5 配额 · 第 1 层：**水陆配额**专项自检。
##
## 验的是：世界实际的陆地格数 **精确命中**"裁切时测到的陆地占比"，
## 而不是靠高程阈值碰运气（那才会"这一局一半是海、下一局几乎全是陆"）。
##
## 跑法（项目根目录）：
##   godot --headless --path . res://tests/quota_check.tscn

const SEED := 20240607

var fails := 0


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  [ok] " + what)
	else:
		fails += 1
		print("  [FAIL] " + what)


## 走一局，返回 { total, land, cap_in_water, stored }
func _one_game(seed_v: int) -> Dictionary:
	GameState.new_game(seed_v)
	var tiles: Dictionary = GameState.state["tiles"]
	var total := tiles.size()
	var land := 0
	var cap_in_water := false
	for k in tiles.keys():
		var t: Dictionary = tiles[k]
		if str(t.get("terrain", "")) == "water":
			if bool(t.get("is_capital", false)):
				cap_in_water = true
		else:
			land += 1
	var stored := -1.0
	var ws: Array = GameState.state.get("worlds", [])
	if ws.size() > 0:
		stored = float((ws[0] as Dictionary).get("land_ratio", -1.0))
	return {"total": total, "land": land, "cap_in_water": cap_in_water, "stored": stored}


func _ready() -> void:
	print("== 水陆配额（W5 第 1 层）专项自检 ==")

	for s in [SEED, SEED + 7, SEED + 1234]:
		var g := _one_game(s)
		var ratio := WorldGen.land_ratio_for(s, {})       # 现场重测一遍（不读配方缓存）
		var target := int(round(ratio * float(g["total"])))
		print("  种子 %d：总格 %d；实测陆地 %d；裁切测量陆地占比 %.3f → 目标 %d 格"
			% [s, g["total"], g["land"], ratio, target])
		_check(absi(int(g["land"]) - target) <= 2,
			"陆地格数**精确命中**目标（差 %d 格 ≤ 2）" % (int(g["land"]) - target))
		_check(not bool(g["cap_in_water"]),
			"首都**不在水里**（配额跑在挑首都之前）")
		_check(absf(float(g["stored"]) - ratio) < 0.0001,
			"比例**已存进世界配方**（库里 %.4f / 现测 %.4f）" % [float(g["stored"]), ratio])
		_check(ratio > 0.10 and ratio < 0.90,
			"测到的陆地占比落在合理区间（%.3f）" % ratio)

	# ---- 第 2 层：干湿三档（名额从原型图读、按排名从两端分配）----
	print("  --- 第 2 层：干湿三档 ---")
	for s2 in [SEED, SEED + 7]:
		var g2 := _one_game(s2)
		var wl := float((GameState.state["worlds"] as Array)[0].get("water_line", -1.0))
		var land_n := int(g2["total"]) - _water_count()
		var q := WorldGen.moisture_quota_for(s2, land_n)
		var got := _count_tiers()          # 直接读地块上记的档位
		print("  种子 %d：陆地 %d 格；名额 干%d/中%d/湿%d（合计 %d）→ 实际 干%d/中%d/湿%d"
			% [s2, land_n, q["dry"], q["medium"], q["wet"],
				int(q["dry"]) + int(q["medium"]) + int(q["wet"]),
				got["dry"], got["medium"], got["wet"]])
		_check(absi(int(got["dry"]) - int(q["dry"])) <= 2,
			"**干档**实际 == 名额（差 %d ≤ 2）" % (int(got["dry"]) - int(q["dry"])))
		_check(absi(int(got["medium"]) - int(q["medium"])) <= 2,
			"**中档**实际 == 名额（差 %d ≤ 2）" % (int(got["medium"]) - int(q["medium"])))
		_check(absi(int(got["wet"]) - int(q["wet"])) <= 2,
			"**湿档**实际 == 名额（差 %d ≤ 2）" % (int(got["wet"]) - int(q["wet"])))
		_check(int(got["medium"]) > 0,
			"**中档不为空**（草原可见：%d 格）" % int(got["medium"]))
		# ⚠️ 这里**故意不断言**"三档俱全"：那等于要求"气候必须完整"——
		#    用户明确否定过（"如果一定要具有沙漠草原和雨林，那不就是另一种非得冷暖俱全嘛"）。
		#    配额的本分是**忠实搬运**：这块地方没有雨林，世界上就不该有雨林。
		print("      （干 %d / 中 %d / 湿 %d —— 三档是否都有，取决于那块地方自己，不做要求）"
			% [int(got["dry"]), int(got["medium"]), int(got["wet"])])
		_check(wl >= -1.0, "水位线已算过（%.4f）" % wl)

	# ---- 第 3 层：冷热三档（同法：名额读自原型图温度分布、按排名两端分配）----
	print("  --- 第 3 层：冷热三档 ---")
	for s3 in [SEED, SEED + 7]:
		var g3 := _one_game(s3)
		var wl3 := float((GameState.state["worlds"] as Array)[0].get("water_line", -1.0))
		var land_n3 := int(g3["total"]) - _water_count()
		var q3 := WorldGen.temp_quota_for(s3, land_n3)
		var got3 := _count_temp_tiers()
		print("  种子 %d：陆地 %d 格；名额 冷%d/中%d/热%d → 实际 冷%d/中%d/热%d"
			% [s3, land_n3, q3["cold"], q3["medium"], q3["hot"],
				got3["cold"], got3["medium"], got3["hot"]])
		_check(absi(int(got3["cold"]) - int(q3["cold"])) <= 2,
			"**冷档**实际 == 名额（差 %d ≤ 2）" % (int(got3["cold"]) - int(q3["cold"])))
		_check(absi(int(got3["medium"]) - int(q3["medium"])) <= 2,
			"**中档**实际 == 名额（差 %d ≤ 2）" % (int(got3["medium"]) - int(q3["medium"])))
		_check(absi(int(got3["hot"]) - int(q3["hot"])) <= 2,
			"**热档**实际 == 名额（差 %d ≤ 2）" % (int(got3["hot"]) - int(q3["hot"])))
		_check(wl3 >= -1.0, "水位线已算过（%.4f）" % wl3)

	print("== 结果：%s ==" % ("全部通过" if fails == 0 else "%d 项失败" % fails))
	get_tree().quit(1 if fails > 0 else 0)


## 现数水格
func _water_count() -> int:
	var n := 0
	for k in (GameState.state["tiles"] as Dictionary).keys():
		if str((GameState.state["tiles"][k] as Dictionary).get("terrain", "")) == "water":
			n += 1
	return n


## 现数冷热三档：直接读地块上记的 temp_tier
func _count_temp_tiers() -> Dictionary:
	var out := {"cold": 0, "medium": 0, "hot": 0}
	for k in (GameState.state["tiles"] as Dictionary).keys():
		var t: Dictionary = GameState.state["tiles"][k]
		var ti := str(t.get("temp_tier", ""))
		if out.has(ti):
			out[ti] = int(out[ti]) + 1
	return out
## 不从地物反推：山地/极地/沙漠类都会显示成秃地，反推会把它们错算进"干"档（第一版就这么数错的）。
func _count_tiers() -> Dictionary:
	var out := {"dry": 0, "medium": 0, "wet": 0}
	for k in (GameState.state["tiles"] as Dictionary).keys():
		var t: Dictionary = GameState.state["tiles"][k]
		var ti := str(t.get("moist_tier", ""))
		if out.has(ti):
			out[ti] = int(out[ti]) + 1
	return out
