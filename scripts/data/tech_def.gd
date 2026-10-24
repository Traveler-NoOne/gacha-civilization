class_name TechDef
extends Resource
## 科技定义（数据在 `res://data/techs/*.tres`，Inspector 里直接改）✓

@export var id: String = ""
@export var display_name: String = ""
## 时代标签（UI 上显示，如「远古时代」「七神时代」）
@export var era: String = ""
## 前置：科技 id 或「发展抽卡得到的标记」
@export var prereq: Array[String] = []
@export var cost: float = 0.0
## 研究后解锁的建筑 id
@export var unlocks: Array[String] = []
@export var desc: String = ""
## 列表排序
@export var sort_index: int = 0
