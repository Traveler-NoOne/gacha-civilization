class_name Admin
extends RefCounted
## 行政点数：**每周期收支** + 限时 buff / debuff + 收支明细 ✓
##
## 规则（v1.3.1）：
##   · 基底每周期 +1（永久）
##   · 其余来源都是**限时** buff / debuff（`state["admin_effects"]`，每周期 remaining−1）
##   · 另有「当期收支项」：每条为正 +0.1、每条为 0/负 −0.1（每周期按当期经济重算）
##
## ⚠️ `resource_breakdown` 是**唯一**的收支口径 —— 顶部悬浮窗、管理页、真实结算都复用它 ✓

## 当期经济各资源净收支（用于行政点数的收支项判定）
static func balance_lines(state: Dictionary) -> Array[float]:
	var inc := {}
	for t in TileManager.owned_tiles(state):
		var y := Buildings.tile_yield(t)
		for k in y.keys():
			inc[k] = float(inc.get(k, 0.0)) + float(y[k])
	var owned := TileManager.owned_tiles(state)
	if not owned.is_empty():
		inc["production"] = float(inc.get("production", 0.0)) \
			+ Consts.PRODUCTION_PER_TILE * float(owned.size())
	for t in owned:
		for b in t.get("buildings", []):
			inc["production"] = float(inc.get("production", 0.0)) \
				- Consts.BUILDING_UPKEEP_PRODUCTION * float(b.get("level", 1))
	inc["food"] = float(inc.get("food", 0.0)) \
		- Consts.FOOD_UPKEEP_PER_POP * float(state["pop_total"])
	# 单位维护费也算进当期收支（否则收支项判定会与真实收支不符）
	var tot2 := GameState.units_upkeep_total()
	inc["food"] = float(inc.get("food", 0.0)) - float(tot2["food"])
	inc["currency"] = float(inc.get("currency", 0.0)) - float(tot2["currency"])
	var lines: Array[float] = []
	for k in inc.keys():
		lines.append(float(inc[k]))
	return lines


static func settle(state: Dictionary, report: Dictionary) -> void:
	var base := Consts.ADMIN_BASE_PER_CYCLE
	var buffs := 0.0
	for e in state.get("admin_effects", []):
		buffs += float(e.get("delta", 0.0))
	var pos := 0
	var neg := 0
	for v in balance_lines(state):
		if v > 0.0:
			pos += 1
		else:
			neg += 1
	var lines_delta := Consts.ADMIN_PER_POSITIVE_LINE * float(pos) \
		- Consts.ADMIN_PER_NEGATIVE_LINE * float(neg)
	var income := maxf(0.0, base + buffs + lines_delta)
	GameState.add_res("admin", income)
	# 计时递减 + 清理过期项
	var kept: Array = []
	for e in state.get("admin_effects", []):
		e["remaining"] = int(e.get("remaining", 0)) - 1
		if int(e["remaining"]) > 0:
			kept.append(e)
	state["admin_effects"] = kept
	if not report.has("income"):
		report["income"] = {}
	report["income"]["admin"] = float(report["income"].get("admin", 0.0)) + income
	if pos > 0 or neg > 0:
		report["events"].append("行政点数 +%.1f（基底 %.1f｜buff %+.1f｜收支 %d正/%d负）" % [
			income, base, buffs, pos, neg])


## 击杀敌对单位后的行政产出 buff（作弊摧毁不调用）
static func on_enemy_killed(state: Dictionary, tile: Dictionary) -> void:
	if tile.is_empty():
		return
	var kind := UnitDB.enemy_admin_kind(tile)
	if kind == "" or not Consts.ADMIN_KILL_BUFFS.has(kind):
		return
	var b: Dictionary = Consts.ADMIN_KILL_BUFFS[kind]
	add_effect(state, float(b["delta"]), int(b["duration"]), "击杀%s" % UnitDB.enemy_admin_label(kind))


## 友军阵亡后的行政产出 debuff（预留：当前 Demo 无单位阵亡机制）
static func on_unit_died(state: Dictionary, rank: String) -> void:
	if not Consts.ADMIN_DEATH_DEBUFFS.has(rank):
		return
	var b: Dictionary = Consts.ADMIN_DEATH_DEBUFFS[rank]
	add_effect(state, -float(b["delta"]), int(b["duration"]), "%s阵亡" % UnitDB.rank_name(rank))


static func add_effect(state: Dictionary, delta: float, duration: int, label: String) -> void:
	if not state.has("admin_effects"):
		state["admin_effects"] = []
	(state["admin_effects"] as Array).append({
		"delta": delta, "remaining": duration,
		"source": "kill" if delta > 0.0 else "death", "label": label,
	})
	GameState.add_log("行政影响：%s，每周期 %+.1f（持续 %d 周期）。" % [label, delta, duration], "world")


## 某项资源的「每周期收支明细」（顶部资源栏点击悬浮窗用）
## 返回 { "income": [{label, amount}...], "upkeep": [{label, amount}...] }，amount 正为收入、负为支出
static func resource_breakdown(state: Dictionary, key: String) -> Dictionary:
	var inc: Array = []
	var upk: Array = []
	var building_out := 0.0
	for t in TileManager.owned_tiles(state):
		var y := Buildings.tile_yield(t)
		building_out += float(y.get(key, 0.0))
		if key == "currency":
			for b in t.get("buildings", []):
				if str(b.get("id", "")) == "classic_house":
					building_out += GameState._housing_gold(int(b.get("level", 1)))
	if absf(building_out) > 0.0001:
		inc.append({"label": "建筑产出", "amount": building_out})
	if key == "production":
		var territory := Consts.PRODUCTION_PER_TILE * float(TileManager.owned_tiles(state).size())
		if territory > 0.0001:
			inc.append({"label": "领地", "amount": territory})
	# 周期结算类（抽卡货币 / 行政）
	if key == "order_crystal":
		inc.append({"label": "周期结算", "amount":
			Consts.CRYSTAL_PER_CYCLE + Consts.CRYSTAL_PER_LEVEL * float(GameState.player_level())})
	elif key == "cohesion":
		var hp := GameState.happiness()
		inc.append({"label": "周期结算", "amount":
			(Consts.COHESION_PER_CYCLE + Consts.COHESION_PER_HAPPINESS * hp)
			* (1.0 + GameState.culture_rate() * Consts.COHESION_CULTURE_BONUS)})
	elif key == "admin":
		inc.append({"label": "行政基底", "amount": Consts.ADMIN_BASE_PER_CYCLE})
		var buffs := 0.0
		for e in state.get("admin_effects", []):
			buffs += float(e.get("delta", 0.0))
		if absf(buffs) > 0.0001:
			inc.append({"label": "击杀/阵亡 buff", "amount": buffs})
		var pos := 0
		var neg := 0
		for v in balance_lines(state):
			if v > 0.0:
				pos += 1
			else:
				neg += 1
		var ld := Consts.ADMIN_PER_POSITIVE_LINE * float(pos) - Consts.ADMIN_PER_NEGATIVE_LINE * float(neg)
		if absf(ld) > 0.0001:
			inc.append({"label": "收支项（%d正/%d负）" % [pos, neg], "amount": ld})
	# 维护 / 消耗
	if key == "production":
		var bup := 0.0
		for t in TileManager.owned_tiles(state):
			for b in t.get("buildings", []):
				bup += Consts.BUILDING_UPKEEP_PRODUCTION * float(int(b.get("level", 1)))
		if bup > 0.0001:
			upk.append({"label": "建筑维护", "amount": -bup})
	elif key == "food":
		var fup := Consts.FOOD_UPKEEP_PER_POP * float(state["pop_total"])
		if fup > 0.0001:
			upk.append({"label": "人口维护", "amount": -fup})
		var uf := float(GameState.units_upkeep_total()["food"])
		if uf > 0.0001:
			upk.append({"label": "单位维护", "amount": -uf})
	elif key == "currency":
		var um := float(GameState.units_upkeep_total()["currency"])
		if um > 0.0001:
			upk.append({"label": "单位维护", "amount": -um})
	return {"income": inc, "upkeep": upk}


## 统一的「每周期收支估算」出口 ✓
## 直接复用 resource_breakdown()（与悬浮窗同一份口径），三者不会再各算一套、数字打架 ✓
static func income_estimate(state: Dictionary) -> Dictionary:
	var out := {}
	for k in Consts.RES_KEYS:
		var bd := resource_breakdown(state, k)
		var sum := 0.0
		for e in bd["income"]:
			sum += float(e["amount"])
		for e in bd["upkeep"]:
			sum += float(e["amount"])
		if absf(sum) > 0.0001:
			out[k] = sum
	return out
