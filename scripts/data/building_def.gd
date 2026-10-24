class_name BuildingDef
extends Resource
## 建筑定义。数值全部来自设计文档《建筑系统》。

@export var id: String = ""
## 显示排序（想调顺序改这个数字，不用动代码）✓
@export var sort_index: int = 0
@export var display_name: String = ""
@export var category: String = "工业建筑"      ## 工业建筑 / 军事建筑 / 民用建筑
@export var subcategory: String = ""           ## 食物 / 生产 / 陆军 / 居住 / 教育
@export var desc: String = ""

## 每级最多可指派的人力
@export var max_workers_per_level: int = 0
## 每级基础产量（每个周期，乘以该建筑分配的每个人力）
@export var yield_per_worker: Dictionary = {}
## 每级额外加成（每升一级追加一次，独立于人力）
@export var yield_per_level: Dictionary = {}

## 升级消耗：基础值 + 每级增量
@export var cost_base: Dictionary = {}
@export var cost_per_level: Dictionary = {}

## 幸福度：基础 + 每级增量（可为负）
@export var happiness_base: float = 0.0
@export var happiness_per_level: float = 0.0

@export var max_level: int = 5
@export var required_tech: String = ""
## 占用的「可用土地」（地块计容用，v1.3.1）
@export var land: float = 0.4
## 只能建在拥有矿物资源点的地块上
@export var needs_resource_node: bool = false

## --- 2026-10-25：地物条件 / 成熟期（林场用；以后别的建筑也能用）---
## 地块地物必须是其中之一才能建（空 = 不限制）
@export var needs_cover: PackedStringArray = PackedStringArray()
## 地块地物**不能**是其中之一（空 = 不限制）；林场用它来保证"种在空地上"✓
@export var forbids_cover: PackedStringArray = PackedStringArray()
## 建成后要经过这么多周期才算成熟（成熟前**不产出**，维护费照扣）✓
@export var growth_cycles: int = 0
## 成熟时给地块加的地物（如 "forest"）
@export var mature_cover: String = ""
## 成熟时把自己替换成这个建筑 id（如造林场 → 林场）
@export var mature_to_id: String = ""
## 特殊效果标记（逗号分隔），由 GameState 解释；**只有声明过的才会被读到**
@export var special: String = ""

## 下面这些原来用 metadata 存，v2026-10-24 改成真字段 —— 这样才能在 Inspector 里直接改 ✓
## 是否需要"矿物资源点"才能建造
@export var uses_node: bool = false
## 建在资源点上时，每级的产量倍率（基础 + 每级增量）
@export var node_bonus: float = 1.0
@export var node_bonus_per_level: float = 0.25
## 每个工人的额外维护（资源 → 数量）
@export var upkeep_per_worker: Dictionary = {}
## 住房：每点住房换算成货币/幸福的区间
@export var housing_ratio_gold: Dictionary = {}
@export var housing_ratio_happy: Dictionary = {}
## 每级提供的文化率
@export var culture: float = 0.0


func level_cap() -> int:
	return maxi(1, max_level)


func max_workers(level: int) -> int:
	return max_workers_per_level * level


## 升到 next_level 需要的消耗
func upgrade_cost(next_level: int) -> Dictionary:
	var out := {}
	for k in cost_base.keys():
		var base: float = float(cost_base[k])
		var inc: float = float(cost_per_level.get(k, 0.0))
		out[k] = base + inc * float(maxi(0, next_level - 1))
	return out


func yield_now(level: int, workers: int) -> Dictionary:
	var out := {}
	for k in yield_per_worker.keys():
		out[k] = float(yield_per_worker[k]) * float(workers)
	for k in yield_per_level.keys():
		out[k] = float(out.get(k, 0.0)) + float(yield_per_level[k]) * float(level)
	return out


func happiness_now(level: int) -> float:
	return happiness_base + happiness_per_level * float(level)


func cost_text(next_level: int) -> String:
	var parts: Array[String] = []
	var c := upgrade_cost(next_level)
	for k in c.keys():
		parts.append("%s %d" % [Consts.res_name(k), int(round(float(c[k])))])
	return "、".join(parts)


func summary() -> String:
	var lines: Array[String] = []
	lines.append(desc)
	if max_workers_per_level > 0:
		lines.append("每级可指派人力：%d" % max_workers_per_level)
	if not yield_per_worker.is_empty():
		var p: Array[String] = []
		for k in yield_per_worker.keys():
			p.append("%s %.2f" % [Consts.res_name(k), float(yield_per_worker[k])])
		lines.append("每个人力每周期产出：%s" % "、".join(p))
	if not yield_per_level.is_empty():
		var p2: Array[String] = []
		for k in yield_per_level.keys():
			p2.append("%s %.2f" % [Consts.res_name(k), float(yield_per_level[k])])
		lines.append("每级额外增加：%s" % "、".join(p2))
	if happiness_base != 0.0 or happiness_per_level != 0.0:
		lines.append("幸福度：基础 %+.1f，每级 %+.1f" % [happiness_base, happiness_per_level])
	lines.append("消耗：%s　升级：上次 +%s　上限：%s" % [
		cost_text(1), _cost_inc_text(), _level_text()])
	return "\n".join(lines)


func _cost_inc_text() -> String:
	var parts: Array[String] = []
	for k in cost_per_level.keys():
		parts.append("%d %s" % [int(round(float(cost_per_level[k]))), Consts.res_name(k)])
	if parts.is_empty():
		return "0"
	return "、".join(parts)


func _level_text() -> String:
	match max_level:
		3: return "三级"
		5: return "五级"
		_: return "%d级" % max_level
