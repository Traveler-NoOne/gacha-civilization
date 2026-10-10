extends Control
## v1.8.9：过场加载界面。**新游戏 / 读取存档**都先经过它。
##
## 布局：标题与立绘居中，**左下角 tips**（随机一条），**右下角进度条**。
##
## ⚠️ 进度条是**仪式感，不是性能需要** —— 这点写在这里免得以后有人误会，但**顺序很重要**：
##
##     进来 → 把界面画出来 → **然后**才干活 → 进度条走满 → finished
##
## 为什么必须是这个顺序：本作现在加载近乎瞬间，但**内容还没端上来**。
## 等玩家跑了几十个周期、地图上单位/建筑/据点堆满，加载会真的变慢 ——
## 如果那时才做加载界面就晚了，而且如果现在是"先干活再显示界面"，慢加载会全部花在**上一屏（菜单）**上，
## 玩家看到的是**卡住的菜单**，等于白做。
##
## 所以工作通过 `begin(work)` 传进来，在界面**已经画出来之后**才执行。
## 将来真慢了，要做的只是把进度条接上真实分块进度，**这套结构不用动**。

## 参数 ok：work 返回 false 时说明"这次进不去"（例如继续游戏没有存档），调用方据此回主菜单。
signal finished(ok: bool)

## 保底显示时长（秒）。调试手感就调这一个数。
const MIN_SHOW := 1.25

## 左下角的 tips。随机取一条 —— 加内容往这里加就行。
const TIPS: Array[String] = [
	"世界泡是承载着文明的气泡，它之外是一片量子之海。",
	"左键点击地块看详情，右键点地块打开行动菜单。",
	"生产力管修建，行政点数管扩张与政事，别搞混。",
	"结束周期会结算一次产出 —— 先把规划队列排好更划算。",
	"科技树在左上角，日志在右上角的书本图标里。",
]

var _bar: ProgressBar
var _tip: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UIKit.BG_DARK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER)
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	col.grow_vertical = Control.GROW_DIRECTION_BOTH
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", UI.fs(10))
	add_child(col)
	col.add_child(UIKit.title("抽卡文明", 44))
	col.add_child(UIKit.dim("%s　·　正在载入世界泡……" % Consts.DEMO_VERSION_FULL, 14))

	# 立绘：有图就用，没图就不硬撑（"缺图自动降级"是本项目的既定做法）
	var pp := "res://art/units/grieso/portrait.png"
	if ResourceLoader.exists(pp):
		var tr := TextureRect.new()
		tr.texture = load(pp)
		tr.custom_minimum_size = Vector2(UI.px(190), UI.px(170))
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		col.add_child(tr)

	# 左下角：tips
	var tips_h := HBoxContainer.new()
	tips_h.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	tips_h.position = Vector2(UI.px(28.0), UI.px(-48.0))
	tips_h.grow_vertical = Control.GROW_DIRECTION_BEGIN
	tips_h.add_theme_constant_override("separation", UI.fs(6))
	add_child(tips_h)
	tips_h.add_child(UIKit.dim("提示：", 13))
	_tip = UIKit.text_label(TIPS[randi() % TIPS.size()], 13, UIKit.TEXT)
	tips_h.add_child(_tip)

	# 右下角：进度条
	_bar = ProgressBar.new()
	_bar.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_bar.position = Vector2(UI.px(-312.0), UI.px(-50.0))
	_bar.custom_minimum_size = Vector2(UI.px(284), UI.px(16))
	_bar.min_value = 0.0
	_bar.max_value = 100.0
	_bar.value = 0.0
	_bar.show_percentage = false
	_bar.add_theme_stylebox_override("background", UIKit.panel_style(Color(0.14, 0.14, 0.19), UIKit.LINE_SOFT, 3))
	_bar.add_theme_stylebox_override("fill", UIKit.panel_style(UIKit.GOLD, UIKit.GOLD, 3))
	add_child(_bar)


## 走完流程 → finished(ok)。调用方收到后自己切场景。
## `work` 里放真正的准备工作（生成世界 / 读档）；它会在**界面已经画出来之后**才执行。
func begin(work: Callable = Callable()) -> void:
	# 先让这一帧画出去（否则"加载界面"本身没机会显示，白做）
	await get_tree().process_frame
	await get_tree().process_frame

	var ok := true
	if work.is_valid():
		var r: Variant = work.call()
		if typeof(r) == TYPE_BOOL:
			ok = bool(r)

	# 进度条按保底时长走满（仪式感）
	var tw := create_tween()
	tw.tween_property(_bar, "value", 100.0, MIN_SHOW)
	tw.tween_callback(func() -> void: finished.emit(ok))
