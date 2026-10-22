class_name Buildings
extends RefCounted
## 建筑：地块上的实例 / 可建判定 / 修建与升级（即时或进规划队列）/ 人力指派 / 产出预览 ✓
##
## ⚠️ 分界：**队列内容**归这里；**据点容器**归 `Strongholds`；**数值**归 `BuildingDB` / `BuildingDef` ✓
## ⚠️ 本文件只调 GameState 的公共接口（付钱 / 资源 / 日志 / 信号），不直接读写它的私有成员 ✓

# ===========================================================================
# 地块上的建筑实例
# ===========================================================================
## 返回该地块上首个同 id 建筑（兼容旧调用）
static func tile_building(tile: Dictionary, id: String) -> Dictionary:
	for b in tile.get("buildings", []):
		if b.get("id", "") == id:
			return b
	return {}


static func tile_buildings_of(tile: Dictionary, id: String) -> Array:
	var out := []
	for b in tile.get("buildings", []):
		if b.get("id", "") == id:
			out.append(b)
	return out


static func tile_building_by_bid(tile: Dictionary, bid: String) -> Dictionary:
	for b in tile.get("buildings", []):
		if str(b.get("bid", "")) == bid:
			return b
	return {}


# ===========================================================================
# 修建 / 升级
# ===========================================================================
## 校验能否在此地块建造该建筑（只看归属 / 科技 / 可用土地；付不付得起交给队列）
static func can_build(state: Dictionary, tile: Dictionary, def: BuildingDef) -> Dictionary:
	if tile.is_empty():
		return {"ok": false, "why": "地块不存在"}
	if tile.get("owner", Consts.Owner.NONE) != Consts.Owner.PLAYER:
		return {"ok": false, "why": "该地块尚未被占领"}
	if def.required_tech != "" and not Techs.unlocked(state, def.required_tech):
		return {"ok": false, "why": "需要科技：%s" % Techs.tech_name(def.required_tech)}
	if Strongholds.land_used(tile) + def.land > Strongholds.land_cap(tile) + 0.0001:
		return {"ok": false, "why": "可用土地不足（需 %.1f，剩余 %.1f）" % [
			def.land, Strongholds.land_free(tile)]}
	return {"ok": true, "why": ""}


## 建造入口：生产力够则立即建成，不够则进规划队列
static func build(state: Dictionary, tile_key: String, id: String) -> Dictionary:
	return request_build(state, tile_key, id)


static func request_build(state: Dictionary, tile_key: String, id: String) -> Dictionary:
	var def := BuildingDB.find(id)
	if def == null:
		return {"ok": false, "why": "未知建筑"}
	var tile := TileManager.tile_at(state, tile_key)
	var chk := can_build(state, tile, def)
	if not chk["ok"]:
		return chk
	var cost := def.upgrade_cost(1)
	var non_prod := non_production_cost(cost)
	if not GameState.can_afford(non_prod):
		return {"ok": false, "why": "资源不足（%s）" % GameState.cost_to_text(non_prod)}
	GameState.pay(non_prod)
	var item := {
		"kind": "build", "tile": tile_key, "id": id, "level": 1, "bid": "",
		"need_prod": float(cost.get("production", 0.0)), "paid_prod": 0.0,
	}
	var queued := _enqueue(state, item, tile_key)
	GameState.add_log("%s：%s" % ["已加入规划队列" if queued else "建造", def.display_name], "build")
	GameState._recompute_derived()
	GameState.state_changed.emit()
	return {"ok": true, "why": "", "queued": queued}


static func request_upgrade_by_bid(state: Dictionary, tile_key: String, bid: String) -> Dictionary:
	var tile := TileManager.tile_at(state, tile_key)
	var b := tile_building_by_bid(tile, bid)
	if b.is_empty():
		return {"ok": false, "why": "该地块没有此建筑"}
	return _request_upgrade_instance(state, tile_key, b)


static func _request_upgrade_instance(state: Dictionary, tile_key: String, b: Dictionary) -> Dictionary:
	var def := BuildingDB.find(str(b.get("id", "")))
	if def == null:
		return {"ok": false, "why": "未知建筑"}
	var lv := int(b.get("level", 1))
	if lv >= def.level_cap():
		return {"ok": false, "why": "已达等级上限"}
	var target := lv + 1
	var cost := def.upgrade_cost(target)
	var non_prod := non_production_cost(cost)
	if not GameState.can_afford(non_prod):
		return {"ok": false, "why": "资源不足（%s）" % GameState.cost_to_text(non_prod)}
	GameState.pay(non_prod)
	var item := {
		"kind": "upgrade", "tile": tile_key, "id": str(b.get("id", "")),
		"level": target, "bid": str(b.get("bid", "")),
		"need_prod": float(cost.get("production", 0.0)), "paid_prod": 0.0,
	}
	var queued := _enqueue(state, item, tile_key)
	GameState.add_log("%s → Lv.%d：%s" % [def.display_name, target,
		"已加入规划队列" if queued else "升级完成"], "build")
	GameState._recompute_derived()
	GameState.state_changed.emit()
	return {"ok": true, "why": "", "queued": queued}


## 入队：先把现有储量生产力灌进该项，够则立刻完成，否则 append 到据点队列
static func _enqueue(state: Dictionary, item: Dictionary, tile_key: String) -> bool:
	var tile := TileManager.tile_at(state, tile_key)
	var sh := Strongholds.by_id(state, Strongholds.of_tile(tile))
	if sh.is_empty():
		sh = Strongholds.current(state)
	var need: float = float(item["need_prod"]) - float(item["paid_prod"])
	var give := minf(GameState.res("production"), maxf(0.0, need))
	if give > 0.0:
		GameState.add_res("production", -give)
		item["paid_prod"] = float(item["paid_prod"]) + give
	if float(item["paid_prod"]) + 0.0001 >= float(item["need_prod"]):
		_execute_queue_item(state, item)
		return false
	if sh.is_empty():
		return false
	(sh["queue"] as Array).append(item)
	return true


## 完成一个队列项（真正落地建筑 / 升级）
static func _execute_queue_item(state: Dictionary, item: Dictionary) -> void:
	var tile := TileManager.tile_at(state, str(item.get("tile", "")))
	if tile.is_empty():
		return
	var def := BuildingDB.find(str(item.get("id", "")))
	if str(item.get("kind", "")) == "build":
		if not tile.has("buildings"):
			tile["buildings"] = []
		(tile["buildings"] as Array).append({
			"bid": Strongholds.new_bid(), "id": str(item["id"]), "level": 1, "workers": 0,
		})
	else:
		var b := tile_building_by_bid(tile, str(item.get("bid", "")))
		if b.is_empty():
			return   # 目标建筑已被摧毁，项目作废
		b["level"] = int(item.get("level", 1))
	if def != null:
		GameState.add_log("%s完成：%s" % [
			"建造" if str(item.get("kind", "")) == "build" else "升级", def.display_name], "build")


## 每周期用可用生产力推进队列；返回未被队列消耗的生产力
static func process_queue(state: Dictionary, avail: float) -> float:
	for sh in Strongholds.all(state):
		var q: Array = sh.get("queue", [])
		var i := 0
		while i < q.size():
			if avail <= 0.0:
				break
			var item: Dictionary = q[i]
			var need := float(item.get("need_prod", 0.0)) - float(item.get("paid_prod", 0.0))
			var put := minf(avail, maxf(0.0, need))
			item["paid_prod"] = float(item.get("paid_prod", 0.0)) + put
			avail -= put
			if float(item["paid_prod"]) + 0.0001 >= float(item.get("need_prod", 0.0)):
				q.remove_at(i)
				_execute_queue_item(state, item)   # 完成后下一项顶上，不 i++
			else:
				break   # 队首未完成，后面的不推进
	return maxf(0.0, avail)


## 去掉生产成本那一项（生产单独走队列，其余资源当场付清）
static func non_production_cost(cost: Dictionary) -> Dictionary:
	var out := {}
	for k in cost.keys():
		if str(k) != "production":
			out[k] = cost[k]
	return out


# ===========================================================================
# 规划队列编辑（UI 用）
# ===========================================================================
static func queue_move(state: Dictionary, sid: String, index: int, delta: int) -> void:
	var sh := Strongholds.by_id(state, sid)
	if sh.is_empty():
		return
	var q: Array = sh.get("queue", [])
	var j := index + delta
	if index < 0 or index >= q.size() or j < 0 or j >= q.size():
		return
	var tmp: Variant = q[index]
	q[index] = q[j]
	q[j] = tmp
	GameState.state_changed.emit()


static func queue_remove(state: Dictionary, sid: String, index: int) -> void:
	var sh := Strongholds.by_id(state, sid)
	if sh.is_empty():
		return
	var q: Array = sh.get("queue", [])
	if index < 0 or index >= q.size():
		return
	q.remove_at(index)
	GameState.state_changed.emit()


## 移除所有指向某建筑实例的队列项（该建筑被摧毁 / 降级时用）
static func drop_queue_items_for_bid(state: Dictionary, bid: String) -> void:
	if bid == "":
		return
	for sh in Strongholds.all(state):
		var q: Array = sh.get("queue", [])
		var kept: Array = []
		for item in q:
			if str(item.get("bid", "")) != bid:
				kept.append(item)
		sh["queue"] = kept


# ===========================================================================
# 人力指派
# ===========================================================================
## 指派 / 撤回人力（delta 可正可负）；按 id 命中首个同种建筑
static func assign_worker(state: Dictionary, tile_key: String, id: String, delta: int) -> Dictionary:
	var tile := TileManager.tile_at(state, tile_key)
	var b := tile_building(tile, id)
	if b.is_empty():
		return {"ok": false, "why": "该地块没有此建筑"}
	return _assign_worker_instance(state, b, delta)


static func assign_worker_by_bid(state: Dictionary, tile_key: String, bid: String, delta: int) -> Dictionary:
	var tile := TileManager.tile_at(state, tile_key)
	var b := tile_building_by_bid(tile, bid)
	if b.is_empty():
		return {"ok": false, "why": "该地块没有此建筑"}
	return _assign_worker_instance(state, b, delta)


static func _assign_worker_instance(state: Dictionary, b: Dictionary, delta: int) -> Dictionary:
	var def := BuildingDB.find(str(b.get("id", "")))
	if def == null:
		return {"ok": false, "why": "未知建筑"}
	var cur := int(b.get("workers", 0))
	var cap := def.max_workers(int(b["level"]))
	if delta > 0:
		if cur >= cap:
			return {"ok": false, "why": "已达该等级人力上限（%d）" % cap}
		if GameState.free_pop() <= 0:
			return {"ok": false, "why": "没有空闲人力"}
	b["workers"] = clampi(cur + delta, 0, cap)
	GameState._recompute_derived()
	GameState.state_changed.emit()
	return {"ok": true, "why": ""}


# ===========================================================================
# 产出预览
# ===========================================================================
## 该地块当前建筑的产出预览 ✓（纯函数：只看地块 + 建筑数据）
static func tile_yield(tile: Dictionary) -> Dictionary:
	var out := {}
	for b in tile.get("buildings", []):
		var def := BuildingDB.find(str(b.get("id", "")))
		if def == null:
			continue
		var lv := int(b.get("level", 1))
		var w := int(b.get("workers", 0))
		var y := def.yield_now(lv, w)
		# 矿场：依赖地块资源点
		var uses_node := bool(BuildingDB.meta_of(def, "uses_node", false))
		if uses_node and tile.get("resource", "") != "":
			var bonus := float(BuildingDB.meta_of(def, "node_bonus", 1.0)) \
				+ float(BuildingDB.meta_of(def, "node_bonus_per_level", 0.25)) * float(lv)
			var rk: String = tile["resource"]
			y[rk] = float(y.get(rk, 0.0)) + bonus
		# 磨坊等：人力维护
		var upk: Dictionary = BuildingDB.meta_of(def, "upkeep_per_worker", {})
		for k in upk.keys():
			y[k] = float(y.get(k, 0.0)) - float(upk[k]) * float(w)
		for k in y.keys():
			out[k] = float(out.get(k, 0.0)) + float(y[k])
	return out
