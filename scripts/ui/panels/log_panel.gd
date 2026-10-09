class_name LogPanel
extends PanelContainer
## v1.8.6：日志浮窗（右上角的书本按钮打开）
##
## **居中的大浮窗，四周各留一点边** —— 故意露出底下的地图：
## 用"看得见世界"来暗示这是一个浮窗，而不是把世界切走了。
##
## 内容**直接复用原来整页的 `log_view`**（任务 / 记录 / 图鉴 / 手册四个子页签），不重写一遍。

## 内部那页（测试与外部要从这里拿 log_view 的子页签）
var page: Control


func _init() -> void:
	UIKit.apply_panel(self, Color(0.07, 0.07, 0.11, 1.0), UIKit.GOLD, 6)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	head.add_child(UIKit.dim("日志", 12))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var close := UIKit.tiny("✕", 13, true)
	close.tooltip_text = "关闭"
	close.pressed.connect(func() -> void: visible = false)
	head.add_child(close)

	page = load("res://scripts/ui/views/log_view.gd").new()
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(page)
