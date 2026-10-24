extends Control
## v1.8.9：过场加载界面。**新游戏 / 读取存档**都先经过它。
##
## 布局：标题与立绘居中，**左下角 tips**（随机一条），**右下角进度条**。
##
## ⚠️ 进度条是**加载反馈，不是装饰** ✓（2026-10-24 更正：这里原来写"只是仪式感"，那是错的）
##
## 为什么必须有：现在加载很快，但**中后期存档会越长越大、世界会越来越复杂**，
## 读档 / 新世界生成本身就要花时间。屏幕上如果没动静，玩家分不清"在加载"和"卡死了"——
## 于是会反复点击、切窗口、强退，甚至在**存档正在读写的中途**杀进程（那才是真的丢档）。
## 进度条的作用就是一句话：**系统在干活，别动它**。
##
## 顺序仍然是刻意的，但原因不是"仪式感"，而是**先让玩家看到反馈，再开始阻塞**：
##
##     进来 → 把界面画出来 → **然后**才干活 → 进度条走满 → finished
##
## 两条路：
##   · `begin(work)`         —— **同步** work（读档这类快操作），进度条"抬到 8% → 停 → 走满"
##   · `begin_chunked(work)` —— work 是**协程**（内部 await 让帧），进度条走**真实进度** ✓
##     新世界生成走这条：`WorldgenBuilder.generate_async` 每帧只处理一批格子 ✓
##
##   ⚠️ 读档将来要是也变慢了，同样要给它做分帧版，否则会退回"停住不动"的观感。

## 参数 ok：work 返回 false 时说明"这次进不去"（例如继续游戏没有存档），调用方据此回主菜单。
signal finished(ok: bool)

## 保底显示时长（秒）。调试手感就调这一个数。
const MIN_SHOW := 1.25

var _bar: ProgressBar
var _tip: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Palette.BG_DARK
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
	_tip = UIKit.text_label(TipDB.random(), 13, Palette.TEXT)
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
	_bar.add_theme_stylebox_override("background", UIKit.panel_style(Palette.BG_PANEL_2, Palette.LINE_SOFT, 3))
	_bar.add_theme_stylebox_override("fill", UIKit.panel_style(Palette.GOLD, Palette.GOLD, 3))
	add_child(_bar)


## 走完流程 → finished(ok)。调用方收到后自己切场景。
## `work` 里放真正的准备工作（生成世界 / 读档）；它会在**界面已经画出来之后**才执行。
func begin(work: Callable = Callable()) -> void:
	# 先让这一帧画出去（否则"加载界面"本身没机会显示，白做）
	await _wait_frames(2)
	# 先抬一点进度：阻塞期间帧不推进，但至少让玩家看到"已经开始"，而不是停在 0%
	_bar.value = 8.0
	var ok := true
	if work.is_valid():
		var r: Variant = work.call()
		if typeof(r) == TYPE_BOOL:
			ok = bool(r)
	_finish(ok)


## 分帧工作：`work(progress_cb)` 必须是**协程**（内部 await），进度条走真实进度 ✓
## 新游戏生成世界走这条路；读档这类快操作仍用 begin() ✓
func begin_chunked(work: Callable) -> void:
	await _wait_frames(2)
	_bar.value = 1.0
	var ok := true
	if work.is_valid():
		var r: Variant = await work.call(func(p: float) -> void:
			_bar.value = clampf(p, 0.0, 100.0))
		if typeof(r) == TYPE_BOOL:
			ok = bool(r)
	_finish(ok)


func _wait_frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


## 收尾：走满 → 发 finished。保底时长保证玩家能看清"完成"这一步（不至于闪一下）✓
func _finish(ok: bool) -> void:
	var tw := create_tween()
	tw.tween_property(_bar, "value", 100.0, MIN_SHOW)
	tw.tween_callback(func() -> void: finished.emit(ok))
