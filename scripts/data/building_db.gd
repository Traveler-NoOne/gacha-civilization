class_name BuildingDB
extends RefCounted
## 建筑数据。v1.6.2：做了一波数值平衡（对照表见 docs/版本记录/v1.6.2.md）。
## 2026-10-24：数据搬进 `res://data/buildings/*.tres`（Resource 化），这里只负责读盘 + 缓存 + 查找 ✓
##
## 平衡口径：
##   · 每级建筑维护 0.25 生产力（BUILDING_UPKEEP_PRODUCTION），所以**每级加成必须 > 0.25**，
##     否则升级反而变亏 —— 这是旧数值最大的问题（满级净收益几乎被维护费吃光）。
##   · 经济建筑（生产/食物/货币）的**回本周期目标 4~8 个周期**（建造消耗 ÷ 满员每周期净产出）。
##   · 科研建筑回本慢是刻意的（科研是科技门槛货币），但产能要比上一档明显高一档。
##   · 「炼金所 / 黑土学院」是科技解锁的高阶建筑、消耗货币，产能约为初级的 3~4 倍。

## 数据位置：`res://data/buildings/*.tres` —— **在 Inspector 里直接改** ✓
## 加建筑 = 在文件夹里新建一个 BuildingDef 资源；删建筑 = 删掉那个文件 ✓
const DATA_DIR := "res://data/buildings/"

static var _cache: Array[BuildingDef] = []


static func all() -> Array[BuildingDef]:
	if not _cache.is_empty():
		return _cache
	var dir := DirAccess.open(DATA_DIR)
	if dir == null:
		push_error("找不到建筑数据目录：" + DATA_DIR)
		return _cache
	for f in dir.get_files():
		if not str(f).ends_with(".tres"):
			continue
		var res: Resource = load(DATA_DIR + str(f))
		if res is BuildingDef:
			_cache.append(res as BuildingDef)
		else:
			push_warning("建筑数据不是 BuildingDef：" + str(f))
	_cache.sort_custom(func(a: BuildingDef, b: BuildingDef) -> bool:
		return a.sort_index < b.sort_index)
	return _cache


## 便捷读取 meta（不存在时给默认值）
static func meta_of(b: BuildingDef, key: String, def_value: Variant) -> Variant:
	if b == null or not (b.special.split(",") as Array).has(key):
		return def_value
	match key:
		"upkeep_per_worker":
			return b.upkeep_per_worker
		"node_bonus":
			return b.node_bonus
		"node_bonus_per_level":
			return b.node_bonus_per_level
		"uses_node":
			return b.uses_node
		"housing_ratio_gold":
			return b.housing_ratio_gold
		"housing_ratio_happy":
			return b.housing_ratio_happy
		"culture":
			return b.culture
	return def_value


## 全部建筑的 id → BuildingDef 索引（`all()` 每次都会重建 12 个对象，这里缓一份 ✓）
static var _by_id: Dictionary = {}

static func find(id: String) -> BuildingDef:
	if _by_id.is_empty():
		for b in all():
			_by_id[b.id] = b
	return _by_id.get(id, null) as BuildingDef