class_name Strongholds
extends RefCounted
## 据点（本作只有首都）✓
##
## 管三件事：**据点表本身**、**某据点包含哪些地块**、**地块的可用土地（land_cap / land_used / land_free）** ✓
## ⚠️ 据点里的两条队列（`queue` 规划队列 / `decrees` 政事队列）**内容**归 `Buildings` / `Decrees` 管，
##    这里只当容器，不碰队列元素 ✓

const CAPITAL_STRONGHOLD := "sh_capital"


## 新档：首都据点（地块上的 stronghold / land_cap 由 `TileManager.setup_new_world()` 打点 ✓）
static func setup_capital(state: Dictionary) -> void:
	state["strongholds"] = [{
		"id": CAPITAL_STRONGHOLD,
		"name": "首都",
		"core": str(state.get("capital", "0,0")),
		"control": 1.0,          # 掌控力（预留，本作恒 1.0）
		"queue": [],             # 规划队列（吃生产力）
		"decrees": [],           # 政事队列（吃行政点数）
	}]


static func all(state: Dictionary) -> Array:
	return state.get("strongholds", [])


static func by_id(state: Dictionary, sid: String) -> Dictionary:
	for s in all(state):
		if str(s.get("id", "")) == sid:
			return s
	return {}


## 当前默认管理的据点（本作仅首都）
static func current(state: Dictionary) -> Dictionary:
	var list := all(state)
	if list.is_empty():
		return {}
	return list[0]


static func of_tile(tile: Dictionary) -> String:
	return str(tile.get("stronghold", ""))


## 某据点包含的地块（仅我方领地）
static func tiles_of(state: Dictionary, sid: String) -> Array:
	var out := []
	for t in TileManager.owned_tiles(state):
		if str(t.get("stronghold", "")) == sid:
			out.append(t)
	return out


# ---------------------------------------------------------------------------
# 可用土地
# ---------------------------------------------------------------------------
static func land_cap(tile: Dictionary) -> float:
	return float(tile.get("land_cap", Consts.LAND_CAP_DEFAULT))


static func land_used(tile: Dictionary) -> float:
	var used := 0.0
	for b in tile.get("buildings", []):
		var def := BuildingDB.find(str(b.get("id", "")))
		if def != null:
			used += def.land
	return used


static func land_free(tile: Dictionary) -> float:
	return maxf(0.0, land_cap(tile) - land_used(tile))


## 建筑实例 id（存档里每个建筑都要有唯一 bid）✓
static func new_bid() -> String:
	return "b_%d_%d" % [Time.get_ticks_usec(), randi() % 100000]


## 掌控力（预留接口：只保留数据结构与骨架，本版不接行为）✓
static func control_of(stronghold: Dictionary) -> float:
	return float(stronghold.get("control", 1.0))
