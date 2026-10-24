class_name TipLibrary
extends Resource
## 提示语库（数据在 `res://data/tips.tres`，Inspector 里直接加/改）✓
##
## 为什么做成资源：加载界面、以后的读档界面 / 空状态提示 / 冷启动小贴士都会要同一批文案，
## 统一从这一个文件取，改一次全生效，不会两边各写一份慢慢分叉 ✓

@export var tips: PackedStringArray = PackedStringArray()
