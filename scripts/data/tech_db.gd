class_name TechDB
extends RefCounted
## 科技数据读取：`res://data/techs/*.tres`（Inspector 里直接改）✓
## 加科技 = 在文件夹里新建一个 TechDef；删科技 = 删掉那个文件 ✓

const DATA_DIR := "res://data/techs/"

static var _cache: Array[TechDef] = []


static func all() -> Array[TechDef]:
	if not _cache.is_empty():
		return _cache
	var dir := DirAccess.open(DATA_DIR)
	if dir == null:
		push_error("找不到科技数据目录：" + DATA_DIR)
		return _cache
	for f in dir.get_files():
		if not str(f).ends_with(".tres"):
			continue
		var res: Resource = load(DATA_DIR + str(f))
		if res is TechDef:
			_cache.append(res as TechDef)
		else:
			push_warning("科技数据不是 TechDef：" + str(f))
	_cache.sort_custom(func(a: TechDef, b: TechDef) -> bool:
		return a.sort_index < b.sort_index)
	return _cache


static func find(id: String) -> TechDef:
	for t in all():
		if t.id == id:
			return t
	return null
