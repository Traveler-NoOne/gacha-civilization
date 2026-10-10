class_name DialogLayer
extends Control
## 通用模态弹窗：半透明遮罩 + 居中面板 + 标题栏 + 内容区。
## 由 UIKit.dialog() 创建，业务代码只需调用 set_content() / close()。

var dialog_title: String = "提示"
var dialog_width: float = 480.0
var show_close_button: bool = true

var _content: Control
var _body: VBoxContainer
var _panel: PanelContainer
var _fit_done := false


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	# 遮罩
	var veil := ColorRect.new()
	veil.color = Color(0, 0, 0, 0.62)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(veil)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(center)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(dialog_width, 0)
	UIKit.apply_panel(_panel, UIKit.BG_PANEL, UIKit.GOLD, 8)
	center.add_child(_panel)
	# 弹窗整体不得超出视口：内容再多也只能在内部滚动，
	# 否则底部的按钮会被挤出屏幕、玩家点不到（作弊菜单就踩过这个坑）
	_panel.clip_contents = true

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 10)
	_panel.add_child(_body)

	# 标题栏
	var head := HBoxContainer.new()
	var t := Label.new()
	t.text = dialog_title
	t.add_theme_font_size_override("font_size", 18)
	t.add_theme_color_override("font_color", UIKit.GOLD)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	if show_close_button:
		var x := UIKit.tiny("✕", 13)
		x.pressed.connect(close)
		head.add_child(x)
	_body.add_child(head)

	var rule := ColorRect.new()
	rule.color = UIKit.LINE_SOFT
	rule.custom_minimum_size = Vector2(0, 1)
	_body.add_child(rule)

	var content_slot := MarginContainer.new()
	content_slot.name = "ContentSlot"
	_body.add_child(content_slot)

	if is_instance_valid(_content):
		content_slot.add_child(_content)
		_content = null

	# 首次布局完成后再算一次高度：刚 add_child 时子节点的最小尺寸还没算出来
	if not _fit_done:
		_fit_done = true
		fit_now.call_deferred()

	# 出现动画
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.15)


## 设置内容（必须在 add_child 之前或之后都可以）
func set_content(c: Control) -> void:
	if _body == null:
		_content = c
		return
	var slot := _body.get_node_or_null("ContentSlot")
	if slot == null:
		return
	for ch in slot.get_children():
		ch.queue_free()
	slot.add_child(c)
	# 内容可能同时被放进树里，延后一帧再量（此时最小尺寸才有效）
	fit_now.call_deferred()


## 把弹窗高度定在视口内。
##
## 为什么需要这个：ScrollContainer 的最小高度恒为 0，所以
## get_combined_minimum_size() 量出来的弹窗高度只有标题栏那么高 ——
## 要么弹窗塌成一条，要么（写了固定值时）内容把弹窗顶出屏幕、底部按钮点不到。
##
## 做法：
##   1. 直接问内容「你到底想要多高」（有 ScrollContainer 就问它里面的子节点）
##   2. 高度 = min(内容想要的高度, 视口可用高度)
##   3. 把这个高度写死到面板上，内容超出的部分交给 ScrollContainer 自己滚
func fit_now() -> void:
	if _panel == null or _body == null:
		return
	var slot := _body.get_node_or_null("ContentSlot")
	if not (slot is Control):
		return
	var slot_c := slot as Control
	var vh := get_viewport_rect().size.y
	if vh <= 1.0:
		vh = 720.0
	var avail := maxf(200.0, vh - 36.0)

	# 除内容槽以外的固定高度（标题栏等）
	slot_c.custom_minimum_size = Vector2(0, 0)
	slot_c.size_flags_vertical = Control.SIZE_FILL
	var panel_min := _panel.get_combined_minimum_size().y
	var slot_min := slot_c.get_combined_minimum_size().y
	var chrome := maxf(0.0, panel_min - slot_min)

	# 内容想要的高度
	var want := _content_height(slot_c)

	var body_room := minf(maxf(60.0, want), maxf(60.0, avail - chrome))
	slot_c.custom_minimum_size = Vector2(0, body_room)
	_panel.custom_minimum_size = Vector2(dialog_width, chrome + body_room)


## 内容槽里内容自然想要的高度。
## ScrollContainer 的最小高度是 0，所以要往下钻一层问它的子节点。
func _content_height(c: Control) -> float:
	var best := 0.0
	for child in c.get_children():
		if not (child is Control):
			continue
		var cc := child as Control
		var h := cc.get_combined_minimum_size().y
		if cc is ScrollContainer:
			# 问它内部的容器要多高
			var inner := 0.0
			for gc in cc.get_children():
				if gc is Control:
					inner += (gc as Control).get_combined_minimum_size().y
			h = maxf(h, inner)
		best = maxf(best, h)
	return best


func close() -> void:
	queue_free()
