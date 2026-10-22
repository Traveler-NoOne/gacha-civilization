class_name Combat
extends RefCounted
## 战斗：能否通行 / 能否移动 / 可达格 / 移动 / 攻击 / 战斗结算 ✓
##
## ⚠️ 只管"怎么打"；"人"在 `Units`，地块在 `TileManager`，敌人演化在 `Threats` ✓
## ⚠️ 需要状态时一律传 `state`（不读全局 GameState.state）✓
##
static func tile_passable(state: Dictionary, key: String) -> bool:
	var t := TileManager.tile_at(state, key)
	if t.is_empty():
		return false
	if t.get("owner", Consts.Owner.NONE) == Consts.Owner.ENEMY:
		return false
	return bool(t.get("discovered", false))


## 移动：相邻格耗 1、间隔一格耗 2（中间格须可通行）
## 移动合法性校验：move_unit 与 UI 高亮**共用同一份规则**，
## 避免出现"界面高亮可走、实际点下去被拒绝"的不一致（v1.7 修）。
static func can_move_to(state: Dictionary, uid: String, key: String) -> Dictionary:
	var u := Units.unit_by_uid(state, uid)
	if u.is_empty():
		return {"ok": false, "why": "找不到该单位"}
	var from := str(u.get("tile", ""))
	if from == "":
		return {"ok": false, "why": "该单位不在大世界上"}
	if key == from:
		return {"ok": false, "why": "已经在这里了"}
	if bool(u.get("garrisoned", false)):
		return {"ok": false, "why": "该单位正在驻军，先「解除驻军」才能移动"}
	if not (state["tiles"] as Dictionary).has(key):
		return {"ok": false, "why": "地块不存在"}
	var a := TileManager.coord_of(from)
	var b := TileManager.coord_of(key)
	var d := Hex.distance(a, b)
	if d < 1 or d > 2:
		return {"ok": false, "why": "只能移动到 1~2 格内的地块"}
	var cost := Consts.MOVE_COST_NEAR if d == 1 else Consts.MOVE_COST_FAR
	if not tile_passable(state, key):
		return {"ok": false, "why": "目标地块无法通行（敌方或未点亮）"}
	if d == 2:
		var mid := TileManager.middle_key(a, b)
		if mid != "" and not tile_passable(state, mid):
			return {"ok": false, "why": "中间的地块无法通行"}
	if Units.units_on_tile(state, key).size() >= UnitDB.UNITS_PER_TILE:
		return {"ok": false, "why": "目标地块已驻满"}
	if int(u.get("move_left", 0)) < cost:
		return {"ok": false, "why": "移动力不足（需 %d，剩 %d）" % [cost, int(u.get("move_left", 0))]}
	return {"ok": true, "why": "", "cost": cost}


## 某单位当前**真正**能走到的地块（UI 高亮用；与 move_unit 同一份规则）
static func move_candidates(state: Dictionary, uid: String) -> Array[String]:
	var out: Array[String] = []
	var u := Units.unit_by_uid(state, uid)
	if u.is_empty():
		return out
	var from := str(u.get("tile", ""))
	if from == "":
		return out
	var a := TileManager.coord_of(from)
	for d in Hex.DIRECTIONS:
		var k1 := TileManager.key_of(a + d)
		if bool(can_move_to(state, uid, k1)["ok"]) and not out.has(k1):
			out.append(k1)
		for d2 in Hex.DIRECTIONS:
			var k2 := TileManager.key_of(a + d + d2)
			if k2 == from or out.has(k2):
				continue
			if bool(can_move_to(state, uid, k2)["ok"]):
				out.append(k2)
	return out


## 移动：相邻格耗 1、间隔一格耗 2（中间格须可通行）
static func move_unit(state: Dictionary, uid: String, key: String) -> Dictionary:
	var chk := can_move_to(state, uid, key)
	if not bool(chk["ok"]):
		return {"ok": false, "why": str(chk["why"])}
	var u := Units.unit_by_uid(state, uid)
	var cost := int(chk["cost"])
	u["move_left"] = int(u.get("move_left", 0)) - cost
	u["tile"] = key
	# v1.6.2：单位移动会点亮周围一格的迷雾
	TileManager.discover_radius(state, TileManager.coord_of(key), 1)
	GameState.add_log("%s 移动到 %s（消耗 %d 移动力）。" % [str(u["name"]), key, cost], "unit")
	GameState.state_changed.emit()
	return {"ok": true, "why": "", "cost": cost}


static func unit_attack(state: Dictionary, uid: String, key: String) -> Dictionary:
	var u := Units.unit_by_uid(state, uid)
	if u.is_empty():
		return {"ok": false, "why": "找不到该单位"}
	var from := str(u.get("tile", ""))
	if from == "":
		return {"ok": false, "why": "该单位不在大世界上"}
	if Hex.distance(TileManager.coord_of(from), TileManager.coord_of(key)) != 1:
		return {"ok": false, "why": "只能攻击相邻地块"}
	var t := TileManager.tile_at(state, key)
	if t.is_empty() or t.get("owner", Consts.Owner.NONE) != Consts.Owner.ENEMY:
		return {"ok": false, "why": "目标不是敌方地块"}
	if bool(u.get("garrisoned", false)):
		return {"ok": false, "why": "该单位正在驻军，先「解除驻军」才能攻击"}
	if int(u.get("move_left", 0)) <= 0:
		return {"ok": false, "why": "该单位本周期已行动"}
	var lines: Array[String] = []
	var force := float(t.get("force", Consts.WANDER_FORCE))
	var enemy_prof := UnitDB.enemy_profession(t)
	var enemy := {"profession": enemy_prof, "attr": {"atk": force * Consts.ENEMY_ATK_MUL, "def": force * Consts.ENEMY_DEF_MUL}}
	var r := UnitDB.resolve_damage(u, enemy)
	var dmg := float(r["damage"])
	var adv := int(r["advantage"])
	var tag := "（克制！）" if adv > 0 else ("（被克制）" if adv < 0 else "")
	force -= dmg
	lines.append("%s 对 %s 造成 %.1f 伤害%s" % [str(u["name"]), UnitDB.enemy_label(t), dmg, tag])
	Units.gain_exp(state, uid, 12, "combat")

	var won := force <= 0.0
	if won:
		Admin.on_enemy_killed(state, t)
		GameState.clear_enemy_tile(key)
		lines.append("战斗胜利：%s 的敌人被清剿。" % key)
		GameState.add_log("战斗胜利：%s 被 %s 清剿。" % [key, str(u["name"])], "combat")
	else:
		t["force"] = force
		var cr := UnitDB.resolve_damage(enemy, u)
		var back := float(cr["damage"])
		u["hp"] = int(u.get("hp", 1)) - int(round(back))
		lines.append("%s 反击 %s，造成 %.1f 伤害" % [UnitDB.enemy_label(t), str(u["name"]), back])
		if int(u.get("hp", 1)) <= 0:
			lines.append("%s 阵亡。" % str(u["name"]))
			GameState.add_log("%s 在进攻 %s 时阵亡。" % [str(u["name"]), key], "combat")
			Admin.on_unit_died(state, str(u.get("rank", UnitDB.RECRUIT)))
			state["units"].erase(u)
		else:
			GameState.add_log("战斗未决：%s 的敌人仍在顽抗。" % key, "combat")

	u["move_left"] = 0   # 攻击耗尽本周期行动
	GameState.state_changed.emit()
	return {"ok": true, "why": "", "won": won, "lines": lines, "damage": dmg,
		"died": int(u.get("hp", 1)) <= 0}


## 战斗模拟：让某单位的队伍去打一块敌方地块（抽象结算，替代战棋）
## 返回详细的战斗日志，供 UI 展示
static func simulate_battle(state: Dictionary, key: String) -> Dictionary:
	var tile := TileManager.tile_at(state, key)
	if tile.is_empty():
		return {"ok": false, "why": "地块不存在"}
	var owner: int = tile.get("owner", Consts.Owner.NONE)
	if owner == Consts.Owner.NONE or owner == Consts.Owner.PLAYER:
		return {"ok": false, "why": "该地块不是敌方地块"}
	var attackers := units_on_tile_neighbors(state, key)
	if attackers.is_empty():
		return {"ok": false, "why": "相邻我方地块没有驻军，请先派驻单位"}
	var enemy_force := float(tile.get("force", Consts.WANDER_FORCE))
	var log_lines: Array[String] = []
	var total_damage := 0.0
	var enemy_hp := enemy_force * Consts.ENEMY_HP_MUL
	var advantage_hits := 0

	# 敌方也要选目标：高危以上才会考虑克制，否则随机（v1.1 第 30 条）
	var is_high_risk: bool = tile.get("danger", false) or tile.get("threat", false)
	var enemy_profession := UnitDB.enemy_profession(tile)

	for u in attackers:
		if enemy_hp <= 0.0:
			break
		var my_prof := str(u.get("profession", UnitDB.MELEE))
		# 敌方 AI：高危敌人会挑被自己克制的目标，否则随机
		var enemy_attacker := {"profession": enemy_profession, "attr": {"atk": enemy_force * Consts.ENEMY_ATK_MUL}}
		var adv := UnitDB.advantage(my_prof, enemy_profession)
		var r := UnitDB.resolve_damage(u, enemy_attacker)
		enemy_hp -= float(r["damage"])
		total_damage += float(r["damage"])
		var tag := ""
		if adv > 0:
			tag = "（克制！）"
			advantage_hits += 1
		elif adv < 0:
			tag = "（被克制）"
		log_lines.append("%s[%s] 对 %s 造成 %.1f 伤害%s" % [
			str(u["name"]), UnitDB.profession_name(my_prof),
			UnitDB.enemy_label(tile), float(r["damage"]), tag])
		Units.gain_exp(state, str(u["uid"]), 12, "combat")

	# 敌人反击：随机挑一个攻击单位（高危才会优先针对克制目标）
	var counter_target: Dictionary = {}
	if not attackers.is_empty():
		if is_high_risk:
			for u2 in attackers:
				if UnitDB.advantage(enemy_profession, str(u2.get("profession", ""))) > 0:
					counter_target = u2
					break
		if counter_target.is_empty():
			counter_target = attackers[randi() % attackers.size()]
	if not counter_target.is_empty():
		var cr := UnitDB.resolve_damage(
			{"profession": enemy_profession, "attr": {"atk": enemy_force * Consts.ENEMY_ATK_MUL_LOW}},
			counter_target)
		log_lines.append("%s 反击 %s，造成 %.1f 伤害" % [
			UnitDB.enemy_label(tile), str(counter_target["name"]), float(cr["damage"])])

	var won := enemy_hp <= 0.0
	if won:
		Admin.on_enemy_killed(state, tile)   # 依据击杀时的敌人类型给行政产出 buff（须在清空标记前）
		GameState.clear_enemy_tile(key)
		log_lines.append("战斗胜利：%s 被清剿。" % key)
		GameState.add_log("战斗胜利：%s 的%s被消灭。" % [key, UnitDB.enemy_label(tile)], "combat")
	else:
		log_lines.append("战斗未决：敌方剩余战力 %.0f。" % (enemy_hp * 0.5))
		GameState.add_log("战斗未决：%s 的敌人仍在顽抗。" % key, "combat")

	GameState.state_changed.emit()
	return {
		"ok": true, "why": "", "won": won, "lines": log_lines,
		"damage": total_damage, "advantage_hits": advantage_hits,
		"attackers": attackers.size(), "high_risk": is_high_risk,
	}


## 参与进攻的单位：与目标相邻的我方地块上的驻军
static func units_on_tile_neighbors(state: Dictionary, key: String) -> Array:
	var out := []
	for n in Hex.neighbors(TileManager.coord_of(key)):
		var nk := TileManager.key_of(n)
		var t := TileManager.tile_at(state, nk)
		if t.is_empty() or t.get("owner", Consts.Owner.NONE) != Consts.Owner.PLAYER:
			continue
		out.append_array(Units.units_on_tile(state, nk))
	return out
