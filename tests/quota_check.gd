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

	print("== 结果：%s ==" % ("全部通过" if fails == 0 else "%d 项失败" % fails))
	get_tree().quit(1 if fails > 0 else 0)
