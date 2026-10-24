class_name TipDB
extends RefCounted
## 提示语读取器：唯一来源 `res://data/tips.tres` ✓
##
## 用法：
##     label.text = TipDB.random()      # 随便来一条
##     for t in TipDB.all(): ...        # 全部（做列表 / 统计用）

const PATH := "res://data/tips.tres"

static var _lib: TipLibrary = null


static func _library() -> TipLibrary:
	if _lib == null:
		_lib = load(PATH) as TipLibrary
		if _lib == null:
			push_error("找不到提示语库：" + PATH)
			_lib = TipLibrary.new()
	return _lib


static func all() -> PackedStringArray:
	return _library().tips


## 随机一条；库为空时返回空串（调用方自己兜底）✓
static func random() -> String:
	var tips := all()
	if tips.is_empty():
		return ""
	return tips[randi() % tips.size()]
