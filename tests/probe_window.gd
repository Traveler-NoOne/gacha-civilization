extends Node
## v1.8.20 诊断用探针：窗口尺寸到底能不能改、哪个 API 有效。
##
## 用法（**必须带窗口跑** —— 无头下窗口操作全是空操作）：
##     godot --path . --resolution 1280x720 res://tests/probe_window.tscn
##
## 它会把每一步之后的**实际**窗口尺寸打出来，然后自行退出。
## 用途：像"分辨率设置不生效"这类问题，光读代码猜不出来，必须让程序自己报数。

const TARGET := Vector2i(1600, 900)


func _ready() -> void:
	print("=== 窗口尺寸探针（目标 %s）===" % str(TARGET))
	print("① 初始              : %s" % str(DisplayServer.window_get_size()))

	# 1) 立刻用 DisplayServer API 改
	DisplayServer.window_set_size(TARGET)
	print("② DisplayServer 立刻 : %s" % str(DisplayServer.window_get_size()))

	await get_tree().process_frame
	await get_tree().process_frame
	print("③ 等两帧后           : %s" % str(DisplayServer.window_get_size()))

	# 2) 用 Window 属性改（Godot 文档推荐的写法，会同步视口）
	get_window().size = TARGET
	print("④ Window.size 立刻   : %s" % str(DisplayServer.window_get_size()))

	await get_tree().process_frame
	await get_tree().process_frame
	print("⑤ Window.size 等两帧 : %s" % str(DisplayServer.window_get_size()))

	# 3) 锁定之后再改（验证"锁会把尺寸冻住"这个说法成不成立）
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_RESIZE_DISABLED, true)
	await get_tree().process_frame
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await get_tree().process_frame
	print("⑥ 锁定后改回 1280    : %s" % str(DisplayServer.window_get_size()))
	print("=== 探针结束 ===")
	get_tree().quit(0)
