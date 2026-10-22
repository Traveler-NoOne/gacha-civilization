class_name PagePanel
extends PanelContainer
## v1.8.8：通用**二级浮窗**。
##
## 把任意"页面脚本"装进一个有标题栏和关闭按钮的窗口里，浮在常驻的大世界之上。
## 用法：
##     var p := PagePanel.new("至宝", "res://scripts/ui/views/treasure_view.gd", 1120.0, 620.0)
##
## 世界升格为 root 之后，任何二级界面都必须**能关**（✕ / Esc / 再点一次角落按钮），
## 否则玩家就被困在里面了 —— 这是 v1.8.7「至宝/世界泡 要不要 toggle」那个问题的正式答案。

signal closed

var title := ""
## 内部那个页面（外部要拿它做子页签切换、刷新）
var page: Control = null


func _init(p_title: String, script_path: String, w: float = 1120.0, h: float = 620.0) -> void:
	title = p_title
	custom_minimum_size = Vector2(UI.px(w), UI.px(h))
	UIKit.apply_panel(self, Color(0.07, 0.07, 0.11, 1.0), Palette.GOLD, 6)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UI.fs(4))
	add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UI.fs(8))
	col.add_child(head)
	head.add_child(UIKit.title(title, 15))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var close := UIKit.tiny("✕", 13, true)
	close.tooltip_text = "关闭（Esc）"
	close.pressed.connect(close_panel)
	head.add_child(close)

	page = load(script_path).new()
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(page)


func close_panel() -> void:
	visible = false
	closed.emit()
