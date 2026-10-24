class_name DecreeDB
extends RefCounted
## v1.8.3：政事表（「政事」= 据点级、可以排队的事务）
##
## 机制：每周期把**行政点数**积累进去，攒够 cost 就执行 —— 与「规划队列」同一套手感，
## 区别只在"吃什么"：规划队列吃**生产力**（造/升建筑），政事队列吃**行政点数**（办事情）。
##
## 2026-10-24：数据搬进 `res://data/decrees/*.tres`（DecreeDef 资源），这里只负责读盘 + 查找 ✓
## ⚠️ 本表只描述"这条政事是什么"；"现在能不能做"由 `Decrees.blocked_reason()` 判定（要读存档状态）。

const DATA_DIR := "res://data/decrees/"
const RECRUIT := "recruit"

static var _cache: Array[DecreeDef] = []


## 政事表（唯一来源：UI 与逻辑都从这里取）
static func all() -> Array[DecreeDef]:
	if not _cache.is_empty():
		return _cache
	var dir := DirAccess.open(DATA_DIR)
	if dir == null:
		push_error("找不到政事数据目录：" + DATA_DIR)
		return _cache
	for f in dir.get_files():
		if not str(f).ends_with(".tres"):
			continue
		var res: Resource = load(DATA_DIR + str(f))
		if res is DecreeDef:
			_cache.append(res as DecreeDef)
		else:
			push_warning("政事数据不是 DecreeDef：" + str(f))
	_cache.sort_custom(func(a: DecreeDef, b: DecreeDef) -> bool:
		return a.sort_index < b.sort_index)
	return _cache


static func find(id: String) -> DecreeDef:
	for d in all():
		if d.id == id:
			return d
	return null


static func exists(id: String) -> bool:
	return find(id) != null


static func display_name(id: String) -> String:
	var d := find(id)
	return d.display_name if d != null else id


static func cost_of(id: String) -> float:
	var d := find(id)
	return d.cost if d != null else 0.0
