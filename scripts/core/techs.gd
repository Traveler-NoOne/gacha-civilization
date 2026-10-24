class_name Techs
extends RefCounted
## 科技树：查名字 / 解锁判定 / 研究 ✓
##
## 科技数据在 `res://data/techs/*.tres`（TechDB）；这里只管"能不能研、研了之后改哪些状态" ✓
## ⚠️ 前置可能是**科技**，也可能是「发展抽卡得到的标记」（`techs_owned_flags`）✓

static func tech_name(id: String) -> String:
	for t in TechDB.all():
		if t.id == id:
			return t.display_name
	if id == "genesis_crystal":
		return "创世结晶"
	return id


static func unlocked(state: Dictionary, id: String) -> bool:
	return (state["techs"] as Array).has(id)


## 发展抽卡得到的标记（不是科技，但当前置用）✓
static func has_flag(state: Dictionary, f: String) -> bool:
	return (state["techs_owned_flags"] as Array).has(f)


static func can_research(state: Dictionary, id: String) -> Dictionary:
	var def := TechDB.find(id)
	if def == null:
		return {"ok": false, "why": "未知科技"}
	if unlocked(state, id):
		return {"ok": false, "why": "已研究"}
	for p in def.prereq:
		# 前置可能是科技，也可能是「发展抽卡得到的标记」
		if unlocked(state, p) or has_flag(state, p):
			continue
		return {"ok": false, "why": "缺少前置：%s" % tech_name(p)}
	if Res.amount(GameState.state, "research") < float(def["cost"]):
		return {"ok": false, "why": "科研点不足（需要 %d）" % int(def["cost"])}
	return {"ok": true, "why": ""}


static func research(state: Dictionary, id: String) -> Dictionary:
	var chk := can_research(state, id)
	if not chk["ok"]:
		return chk
	var t := TechDB.find(id)
	if t != null:
		Res.add(GameState.state, "research", -t.cost)
		(state["techs"] as Array).append(id)
		var names: Array[String] = []
		for bid in t.unlocks:
			var bd := BuildingDB.find(str(bid))
			if bd != null:
				names.append(bd.display_name)
		Journal.add(GameState.state, "研究完成：%s（解锁 %s）" % [t.display_name, "、".join(names)], "tech")
	GameState.state_changed.emit()
	return {"ok": true, "why": ""}
