class_name DecreeDef
extends Resource
## 政事定义（数据在 `res://data/decrees/*.tres`，Inspector 里直接改）✓
##
## ⚠️ 只描述"这条政事是什么"（id / 名字 / 说明 / 要多少点）。
##    "现在能不能做"由 `Decrees.blocked_reason()` 判定（要读存档状态）。

@export var id: String = ""
@export var display_name: String = ""
@export var cost: float = 0.0
@export var desc: String = ""
## 额外提示（为什么不能排之类的补充说明）
@export var hint: String = ""
## 列表排序
@export var sort_index: int = 0
