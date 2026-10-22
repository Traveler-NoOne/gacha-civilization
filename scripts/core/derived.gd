class_name Derived
extends RefCounted
## 派生数值：人口 / 住房 / 幸福度 / 文化率 / 双方战力 / 稳定度 ✓
##
## 这些量**不存盘**，每次按当前状态算出来（贵一点的以后可以在这里加缓存）✓
## ⚠️ 需要状态时一律传 `state`（不读全局 GameState.state）✓
##
static func assigned_pop(state: Dictionary) -> int:
	var n := 0
	for t in TileManager.owned_tiles(state):
		for b in t.get("buildings", []):
			n += int(b.get("workers", 0))
	return n


static func free_pop(state: Dictionary) -> int:
	return maxi(0, int(state["pop_total"]) - assigned_pop(state))


static func housing_capacity(state: Dictionary) -> int:
	# 基础住房 + 每块领地若干 + 民居等级
	var cap := Consts.BASE_HOUSING + Consts.HOUSING_PER_TILE * TileManager.owned_tiles(state).size()
	for t in TileManager.owned_tiles(state):
		for b in t.get("buildings", []):
			if b.get("id", "") == "classic_house":
				cap += Consts.HOUSING_PER_HOUSE_LEVEL * int(b.get("level", 1))
	return mini(cap, Consts.POP_HARD_CAP)


static func culture_rate(state: Dictionary) -> float:
	var c := 0.0
	for t in TileManager.owned_tiles(state):
		for b in t.get("buildings", []):
			var def := BuildingDB.find(b.get("id", ""))
			if def == null:
				continue
			c += float(BuildingDB.meta_of(def, "culture", 0.0)) * float(b.get("level", 1))
	return c


## 幸福度是「基础 + 建筑 + 制度 - 民怨」
static func happiness(state: Dictionary) -> float:
	var h := 50.0
	for t in TileManager.owned_tiles(state):
		for b in t.get("buildings", []):
			var def := BuildingDB.find(b.get("id", ""))
			if def == null:
				continue
			var lv := int(b.get("level", 1))
			if def.id == "classic_house":
				h += _housing_happiness(state, def, lv)
			else:
				h += def.happiness_now(lv)
	# 人力过剩会不满（对应民居描述里的「人力停止增长」）
	var over := assigned_pop(state)
	if over > housing_capacity(state):
		h -= 3.0 * float(over - housing_capacity(state))
	# 粮食短缺
	if GameState.res("food") <= 0.0:
		h -= 15.0
	return clampf(h, 0.0, 100.0)


static func _housing_happiness(state: Dictionary, def: BuildingDef, level: int) -> float:
	var rng: Dictionary = BuildingDB.meta_of(def, "housing_ratio_happy", {"min": 10.0, "max": -10.0})
	var t := _housing_ratio(state)
	return lerpf(float(rng["min"]), float(rng["max"]), t) * float(level) / 5.0


## 人力 / 住房比：0 = 房屋极少人力极多，1 = 房屋极多人手不足
static func _housing_ratio(state: Dictionary) -> float:
	var cap := maxi(1, housing_capacity(state))
	var ratio := float(state["pop_total"]) / float(cap)
	return clampf(ratio, 0.0, 1.0)


static func player_force(state: Dictionary) -> float:
	var f := float(state["pop_total"]) * Consts.FORCE_PER_POP
	f += float(TileManager.owned_tiles(state).size()) * Consts.FORCE_PER_TILE
	# v1.1：单位战力按「位阶倍率修正后的属性」换算，越精锐贡献越大
	for u in state["units"]:
		f += UnitDB.power_of(u)
	for t in TileManager.owned_tiles(state):
		for b in t.get("buildings", []):
			var id: String = b.get("id", "")
			if id == "classic_training_ground":
				f += 4.0 * float(b.get("level", 1))
	return f


static func enemy_force(state: Dictionary) -> float:
	var f := 0.0
	for t in TileManager.enemy_tiles(state):
		f += float(t.get("force", Consts.WANDER_FORCE))
	for _t in state["threats"]:
		f += Consts.THREAT_FORCE
	return f


## 文档公式：稳定度
##   ((玩家总战斗力 / 敌人总战斗力) * (空白格子数 / (空白格子数 + 1)))
##   * (1 - (敌人数量 / 地图总格子数) * 0.5)
static func stability(state: Dictionary) -> float:
	var pf := player_force(state)
	var ef := enemy_force(state)
	var ratio := 1.0
	if ef > 0.0:
		ratio = pf / ef
	else:
		ratio = 2.0   # 没有敌人时视为非常稳定
	ratio = clampf(ratio, 0.0, 2.0)

	var blank := float(TileManager.free_tiles(state).size())
	var blank_factor := blank / (blank + 1.0)

	var total_tiles := maxi(1, state["tiles"].size())
	var enemy_count := float(TileManager.enemy_tiles(state).size() + state["threats"].size())
	var pressure := 1.0 - (enemy_count / float(total_tiles)) * 0.5

	var s := (ratio * blank_factor) * pressure
	return clampf(s, 0.0, 1.0)


## 首都民居按照「房屋比例」给金币
static func housing_gold(state: Dictionary, level: int) -> float:
	var def := BuildingDB.find("classic_house")
	if def == null:
		return 0.0
	var rng: Dictionary = BuildingDB.meta_of(def, "housing_ratio_gold", {"min": 1.0, "max": 10.0})
	# 人力越多（ratio 越小）-> 金币越多
	var t := 1.0 - _housing_ratio(state)
	return lerpf(float(rng["min"]), float(rng["max"]), t) * float(level)


static func recompute(state: Dictionary) -> void:
	# 当前没有需要缓存的重型派生量，占位以便后续扩展
	pass
