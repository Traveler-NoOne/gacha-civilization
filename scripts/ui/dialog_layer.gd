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
	set_anchors_preset(Control.PRESET_FULL_RECT) # 让 DialogLayer 铺满全屏，作为遮罩和居中容器。
	mouse_filter = Control.MOUSE_FILTER_STOP # 让 DialogLayer 拦截鼠标，防止点击穿透到底层 UI。


func _ready() -> void:

	var veil := ColorRect.new() # 底层遮罩
	veil.color = Color(0, 0, 0, 0.62)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(veil)

	var center := CenterContainer.new() # 用于居中子控件
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(center)

	_panel = PanelContainer.new() # 创建面板容器
	_panel.custom_minimum_size = Vector2(dialog_width, 0)
	_panel.clip_contents = true
	UIKit.apply_panel(_panel, Palette.BG_PANEL, Palette.GOLD, 8)
	center.add_child(_panel)

	_body = VBoxContainer.new() 
	_body.add_theme_constant_override("separation", UI.fs(10))
	_panel.add_child(_body)

	# 标题栏
	var head := HBoxContainer.new()
	var t := Label.new()
	t.text = dialog_title
	t.add_theme_font_size_override("font_size", UI.fs(18))
	t.add_theme_color_override("font_color", Palette.GOLD)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	if show_close_button:
		var x := UIKit.tiny("✕", 13)
		x.pressed.connect(close)
		head.add_child(x)
	_body.add_child(head)

	var rule := ColorRect.new() # 分割线
	rule.color = Palette.LINE_SOFT
	rule.custom_minimum_size = Vector2(UI.px(0), UI.px(1))
	_body.add_child(rule)

	var content_slot := MarginContainer.new() # 内容槽
	content_slot.name = "ContentSlot"
	_body.add_child(content_slot)

	if is_instance_valid(_content): # 检测暂存	
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


## 设置内容
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
	# v1.8.20：窗口已经锁死在真实分辨率档位，所以"视口小得离谱"只可能出现在
	# 无头/退化环境（实测 headless 下视口只有 64 高）。这时按设计基准高度兜底，
	# 否则弹窗会被 get_viewport_rect() 夹扁，内容溢出、底部按钮点不到。
	if vh < 200.0:
		vh = UI.current_size().y
	_usable_h = vh   # 暴露给自检：弹窗"自己认定"的可用高度（上一步兜底之后的值）
	var avail := maxf(UI.px(200.0), vh - UI.px(36.0))

	# 除内容槽以外的固定高度（标题栏等）
	slot_c.custom_minimum_size = Vector2(UI.px(0), UI.px(0))
	slot_c.size_flags_vertical = Control.SIZE_FILL
	_panel.custom_minimum_size = Vector2(dialog_width, 0)
	var panel_min := _panel.get_combined_minimum_size().y
	var slot_min := slot_c.get_combined_minimum_size().y
	var chrome := maxf(0.0, panel_min - slot_min)

	# 内容想要的高度
	var want := _content_height(slot_c)

	var body_room := minf(maxf(UI.px(60.0), want), maxf(UI.px(60.0), avail - chrome))
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


## v1.8.20：弹窗"自己认定"的可用高度（`fit_now()` 兜底之后的值）。
## 自检拿它判断"按钮是否在弹窗认为可用的区域里" —— 不要去问真实视口：
## headless 下视口只有 64，拿它当参照会得出错误结论（假失败）。
var _usable_h := 0.0


func usable_height() -> float:
	return _usable_h


func close() -> void:
	queue_free()
