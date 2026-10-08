extends Control
## 【日志】页：任务 / 记录 / 图鉴。
## 对应设计文档「4日志」章节。

const SUB_TABS := [
	{"id": "task", "name": "任务", "script": "res://scripts/ui/views/parts/task_page.gd"},
	{"id": "record", "name": "记录", "script": "res://scripts/ui/views/parts/record_page.gd"},
	{"id": "codex", "name": "图鉴", "script": "res://scripts/ui/views/parts/codex_page.gd"},
	{"id": "manual", "name": "手册", "script": "res://scripts/ui/views/parts/manual_page.gd"},
]

var sub_bar: HBoxContainer
var host: ViewHost
var pages: Dictionary = {}
var current := "task"


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	var head := UIKit.hbox(10)
	root.add_child(head)
	head.add_child(UIKit.title("日志", 20))
	head.add_child(UIKit.dim("任务追踪、存档管理、内容图鉴、名词手册"))

	sub_bar = HBoxContainer.new()
	sub_bar.add_theme_constant_override("separation", 6)
	root.add_child(sub_bar)
	for t in SUB_TABS:
		var tid: String = t["id"]
		var b := UIKit.normal(str(t["name"]), 14)
		b.custom_minimum_size = Vector2(120, 34)
		b.pressed.connect(func() -> void: _switch(tid))
		sub_bar.add_child(b)

	host = ViewHost.new()
	host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(host)
	_switch("task")


func _switch(id: String) -> void:
	current = id
	if not pages.has(id):
		var def: Dictionary = {}
		for t in SUB_TABS:
			if t["id"] == id:
				def = t
				break
		var scr: Control = load(str(def["script"])).new()
		pages[id] = scr
		host.add_view(scr, id)
	host.show_view(pages[id])
	refresh()


func refresh() -> void:
	for k in pages.keys():
		var p: Variant = pages[k]
		if p.has_method("refresh"):
			p.refresh()
	var i := 0
	for child in sub_bar.get_children():
		if child is Button:
			var active: bool = SUB_TABS[i]["id"] == current
			UIKit.style_button(child as Button, active)
			(child as Button).add_theme_color_override("font_color", UIKit.GOLD if active else UIKit.TEXT)
			i += 1


func on_cycle_finished(_rep: Dictionary) -> void:
	refresh()
