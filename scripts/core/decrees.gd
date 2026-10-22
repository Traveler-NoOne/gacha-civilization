class_name Decrees
extends RefCounted
## 政事队列（据点级、吃行政点数）✓
##
## 「政事」= 可以排队的事务，每周期把**当期入账的行政点数**填进度条，填满才执行 ✓
## 规则：**队首没办完，后面的不推进**（避免摊薄）✓
## 数据在 `DecreeDB`（第一条政事是**征兵**）✓

## 政事能不能排？"" 表示可以。**只检查，不改状态** ✓
static func blocked_reason(state: Dictionary, id: String) -> String:
	if not DecreeDB.exists(id):
		return "没有这条政事"
	if id == DecreeDB.RECRUIT:
		return Units.recruit_blocked_reason(GameState.state, UnitDB.MELEE)
	return ""


## 把一条政事排进据点队列
static func enqueue(state: Dictionary, id: String, profession: String = UnitDB.MELEE) -> Dictionary:
	if not DecreeDB.exists(id):
		return {"ok": false, "why": "没有这条政事"}
	var why := blocked_reason(state, id)
	if why != "":
		return {"ok": false, "why": why}
	var sh := Strongholds.current(state)
	if sh.is_empty():
		return {"ok": false, "why": "没有据点"}
	if not sh.has("decrees"):
		sh["decrees"] = []
	(sh["decrees"] as Array).append({
		"id": id,
		"profession": profession,
		"cost": DecreeDB.cost_of(id),
		"paid": 0.0,
	})
	Journal.add(GameState.state, "政事「%s」已排入队列。" % DecreeDB.display_name(id), "admin")
	GameState.state_changed.emit()
	return {"ok": true, "why": ""}


## 每周期用**当期入账的行政点数**推进政事队列 ✓（结构同 Buildings.process_queue）
static func process_queue(state: Dictionary, avail: float) -> void:
	for sh in Strongholds.all(state):
		var q: Array = sh.get("decrees", [])
		var i := 0
		while i < q.size():
			if avail <= 0.0:
				break
			var item: Dictionary = q[i]
			var need := float(item.get("cost", 0.0)) - float(item.get("paid", 0.0))
			var put := minf(avail, maxf(0.0, need))
			item["paid"] = float(item.get("paid", 0.0)) + put
			avail -= put
			if float(item["paid"]) + 0.0001 >= float(item.get("cost", 0.0)):
				q.remove_at(i)
				_execute(state, item)
			else:
				break


## 政事完成时执行效果。
## 若效果**执行不了**（前置在这期间变了，比如首都已驻满），
## **把已投入的行政点数退还**并记日志 —— 不白吞玩家的点数 ✓
static func _execute(state: Dictionary, item: Dictionary) -> void:
	var id := str(item.get("id", ""))
	var paid := float(item.get("paid", 0.0))
	if id == DecreeDB.RECRUIT:
		var r := Units.recruit_soldier(GameState.state, str(item.get("profession", UnitDB.MELEE)))
		if bool(r["ok"]):
			Journal.add(GameState.state, "政事「征兵」完成：%s 进驻首都。" % str((r["unit"] as Dictionary).get("name", "")), "admin")
		else:
			Res.add(GameState.state, "admin", paid)
			Journal.add(GameState.state, "政事「征兵」未能执行（%s），已退还行政点数 %.1f。" % [str(r["why"]), paid], "admin")
	else:
		Res.add(GameState.state, "admin", paid)
		Journal.add(GameState.state, "未知政事「%s」，已退还行政点数 %.1f。" % [id, paid], "admin")
