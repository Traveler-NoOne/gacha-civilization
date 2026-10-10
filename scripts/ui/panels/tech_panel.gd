class_name TechPanel
extends PanelContainer
## v1.8.6：科技树浮窗（左上角的「科技树」按钮打开）
##
## 内容从「管理页 → 中控区 → 科技树」整块搬来，**功能不变**（消耗科研点、解锁后常驻）。
## 搬完之后管理页里那个页签已移除 —— 避免同一个东西有两个入口。

var list_box: VBoxContainer


func _init() -> void:
	custom_minimum_size = Vector2(UI.px(560), UI.px(480))
	UIKit.apply_panel(self, Color(0.07, 0.07, 0.11, 1.0), UIKit.GOLD, 6)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UI.fs(6))
	add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UI.fs(8))
	col.add_child(head)
	head.add_child(UIKit.title("科技树", 15))
	head.add_child(UIKit.dim("消耗科研点；解锁后常驻，并开放对应建筑", 11))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var close := UIKit.tiny("✕", 13, true)
	close.tooltip_text = "关闭"
	close.pressed.connect(func() -> void: visible = false)
	head.add_child(close)

	list_box = VBoxContainer.new()
	list_box.add_theme_constant_override("separation", UI.fs(5))
	col.add_child(UIKit.scroll(list_box))


func refresh() -> void:
	if not is_instance_valid(list_box):
		return
	for c in list_box.get_children():
		c.queue_free()
	for t in Consts.TECHS:
		var id := str(t["id"])
		var unlocked := GameState.tech_unlocked(id)
		var row := UIKit.panel(UIKit.BG_PANEL_2, UIKit.OK if unlocked else UIKit.LINE_SOFT, 5)
		list_box.add_child(row)
		var v := UIKit.vbox(2)
		row.add_child(v)
		var head := UIKit.hbox(6)
		v.add_child(head)
		head.add_child(UIKit.text_label(str(t["name"]), 13, UIKit.OK if unlocked else UIKit.GOLD))
		head.add_child(UIKit.dim(str(t["era"]), 11))
		head.add_child(UIKit.dim("科研点 %d" % int(t["cost"]), 11))
		v.add_child(UIKit.dim(str(t["desc"]), 11))
		var b := UIKit.small("已完成" if unlocked else "研究", 12)
		b.disabled = unlocked
		if not unlocked:
			var chk := GameState.can_research(id)
			if not bool(chk["ok"]):
				b.disabled = true
				b.tooltip_text = str(chk["why"])
			b.pressed.connect(func() -> void:
				var r: Dictionary = GameState.research(id)
				if not bool(r["ok"]):
					GameState.toast.emit(str(r["why"]))
				refresh())
		v.add_child(b)
