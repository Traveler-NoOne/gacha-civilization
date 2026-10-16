class_name Cheat
extends RefCounted

## 作弊系统
## 开关 在 autoload 'AppSettings'


## 作弊系统开关
static func set_enabled(on: bool) -> void:
	AppSettings.set_cheat_enabled(on)
	if on:
		GameState.add_log("作弊功能已开启。", "cheat")
	else:
		GameState.add_log("作弊功能已关闭。", "cheat")

## 批量增加资源
static func add_resources(amounts: Dictionary) -> Dictionary:
	var parts: Array[String] = [] # 日志记载
	for k in amounts.keys(): # 循环资源类型
		var v := float(amounts[k]) # 需要添加的数量
		if v == 0.0:
			continue
		if k == "pop_total": # 添加人力
			GameState.state["pop_total"] = clampi(int(GameState.state["pop_total"]) + int(v), 1, Consts.POP_HARD_CAP)
			parts.append("人力 %+d" % int(v))
		else: # 添加资源
			GameState.add_res(str(k), v)
			parts.append("%s %+d" % [Consts.res_name(str(k)), int(v)])
	if parts.is_empty():
		return {"ok": false, "why": "没有填写任何数量", "summary": ""}
	var summary := "、".join(parts)
	GameState.add_log("【作弊】获得 %s。" % "、".join(parts), "cheat")
	GameState.state_changed.emit()
	return {"ok": true, "why": "", "summary": summary}

## 摧毁目标地块的敌人
static func destroy_tile_enemies(key: String) -> Dictionary:
	var tiles: Dictionary = GameState.state["tiles"]
	if not tiles.has(key):
		return {"ok": false, "why": "地块不存在", "label": ""}
	var t: Dictionary = tiles[key]
	var owner: String = t.get("owner", "")
	if owner == "" or owner == "player":
		return {"ok": false, "why": "该地块没有敌对单位", "label": ""}
	var label := UnitDB.enemy_label(t)
	GameState.clear_enemy_tile(key)
	GameState.add_log("【作弊】直接摧毁了 %s 的%s。" % [key, label], "cheat")
	GameState.state_changed.emit()
	return {"ok": true, "why": "", "label": label}

## 摧毁所有的敌人
static func destroy_all_enemies() -> int:
	var keys: Array[String] = []
	for k in (GameState.state["tiles"] as Dictionary).keys():
		var t: Dictionary = GameState.state["tiles"][k]
		var o: String = t.get("owner", "")
		if o != "" and o != "player":
			keys.append(str(k))
	for k in keys:
		destroy_tile_enemies(k)
	GameState.add_log("【作弊】清空了全部敌对单位(%d 个)。" % keys.size(), "cheat")
	GameState.state_changed.emit()
	return keys.size()

## 揭开所有迷雾
static func reveal_all() -> int:
	var n := WorldGen.discover_all(GameState.state)
	GameState.add_log("【作弊】揭开了全部迷雾（新揭开 %d 格）。" % n, "cheat")
	GameState.state_changed.emit()
	return n
