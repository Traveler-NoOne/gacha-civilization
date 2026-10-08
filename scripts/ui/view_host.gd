class_name ViewHost
extends MarginContainer
## 只显示一个子视图的容器（懒加载 + 切换）。

func add_view(v: Control, id: String) -> void:
	v.name = "view_" + id
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.visible = false
	add_child(v)


func show_view(v: Control) -> void:
	for c in get_children():
		if c is Control:
			(c as Control).visible = c == v
