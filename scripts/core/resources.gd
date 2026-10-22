class_name Res
extends RefCounted
## 资源：读 / 加 / 存储上限 / 支付 / 花费文案 ✓
##
## 所有资源的读写都走这里 —— 上限夹取（`storage_cap`）只在这一个地方生效 ✓
## ⚠️ 需要状态时一律传 `state`（不读全局 GameState.state）✓
##
static func amount(state: Dictionary, key: String) -> float:
	return float(state["res"].get(key, 0.0))


static func add(state: Dictionary, key: String, amount: float) -> void:
	var r: Dictionary = state["res"]
	r[key] = float(r.get(key, 0.0)) + amount
	if r[key] < 0.0:
		r[key] = 0.0
	var cap := storage_cap(state, key)
	if cap >= 0.0 and r[key] > cap:
		r[key] = cap


## 某资源的存储上限；返回 -1 表示无上限（v1.4）
static func storage_cap(state: Dictionary, key: String) -> float:
	match key:
		"production":
			return Consts.PRODUCTION_STORE_CAP
		"research":
			return Consts.RESEARCH_STORE_CAP
		"currency", "admin", "order_crystal", "cohesion":
			return -1.0
	if Consts.CAPPED_CONCRETE.has(key):
		return Consts.STORAGE_CAP_CONCRETE + warehouse_bonus(state)
	return -1.0


## 经典仓储带来的具体资源上限提升（v1.4）
static func warehouse_bonus(state: Dictionary) -> float:
	var lv := 0
	for t in TileManager.owned_tiles(state):
		for b in t.get("buildings", []):
			if str(b.get("id", "")) == "classic_warehouse":
				lv += int(b.get("level", 1))
	return float(lv) * Consts.WAREHOUSE_CAP_PER_LEVEL


static func can_afford(state: Dictionary, cost: Dictionary) -> bool:
	for k in cost.keys():
		if amount(state, k) < float(cost[k]):
			return false
	return true


static func pay(state: Dictionary, cost: Dictionary) -> bool:
	if not can_afford(state, cost):
		return false
	for k in cost.keys():
		add(state, k, -float(cost[k]))
	return true


## 文本形式的消耗，用于按钮提示
static func cost_text(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for k in cost.keys():
		var v := float(cost[k])
		var t := Consts.res_name(k)
		parts.append("%s %.1f" % [t, v] if v != floorf(v) else "%s %d" % [t, int(v)])
	return "、".join(parts)
