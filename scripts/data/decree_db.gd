class_name DecreeDB
extends RefCounted
## v1.8.3：政事表（「政事」= 据点级、可以排队的事务）
##
## 机制：每周期把**行政点数**积累进去，攒够 cost 就执行 —— 与「规划队列」同一套手感，
## 区别只在"吃什么"：规划队列吃**生产力**（造/升建筑），政事队列吃**行政点数**（办事情）。
##
## ⚠️ 本表只描述"这条政事是什么"（id / 名字 / 说明 / 要多少点）。
##    "现在能不能做"（前置条件）由 GameState 判定 —— 因为那要读存档状态。
##    判定入口：GameState.decree_blocked_reason(id)

const RECRUIT := "recruit"


## 政事表（唯一来源：UI 与逻辑都从这里取）
static func all() -> Array:
	return [
		{
			"id": RECRUIT,
			"name": "征兵",
			"cost": 20.0,
			"desc": "把一名空闲人力训练成募集军，进驻首都。",
			"hint": "需要「经典训练场地」与空闲人力，且首都尚有空位；执行时消耗 食物 20、货币 60。",
		},
	]


static func find(id: String) -> Dictionary:
	for d in all():
		if str(d["id"]) == id:
			return d
	return {}


static func exists(id: String) -> bool:
	return not find(id).is_empty()


static func display_name(id: String) -> String:
	var d := find(id)
	return str(d.get("name", id)) if not d.is_empty() else id


static func cost_of(id: String) -> float:
	var d := find(id)
	return float(d.get("cost", 0.0)) if not d.is_empty() else 0.0
