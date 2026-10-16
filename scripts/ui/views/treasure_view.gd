extends Control
## 【至宝】页：角色 / 装备 / 道具。
## 对应设计文档「2至宝」章节。

const SUB_TABS := [
	{"id": "character", "name": "角色", "script": "res://scripts/ui/views/parts/treasure_character.gd"},
	{"id": "gear", "name": "装备", "script": "res://scripts/ui/views/parts/treasure_gear.gd"},
	{"id": "item", "name": "道具", "script": "res://scripts/ui/views/parts/treasure_item.gd"},
]

var sub_bar: HBoxContainer
var host: ViewHost
var pages: Dictionary = {}
var current := "character"


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", UI.fs(6))
	add_child(root)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UI.fs(10))
	root.add_child(head)
	head.add_child(UIKit.title("至宝", 20))
	head.add_child(UIKit.dim("所有世界泡产出（非消耗品）都会归入这里"))

	# 二级按钮：角色 / 装备 / 道具
	sub_bar = HBoxContainer.new()
	sub_bar.add_theme_constant_override("separation", UI.fs(6))
	root.add_child(sub_bar)
	for t in SUB_TABS:
		var tid: String = t["id"]
		var b := UIKit.normal(str(t["name"]), 14)
		b.custom_minimum_size = Vector2(UI.px(120), UI.px(34))
		b.pressed.connect(func() -> void: _switch(tid))
		sub_bar.add_child(b)

	host = ViewHost.new()
	host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(host)

	_switch("character")


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
	_refresh_bar()


func _refresh_bar() -> void:
	var i := 0
	for child in sub_bar.get_children():
		if child is Button:
			var active: bool = SUB_TABS[i]["id"] == current
			UIKit.style_button(child as Button, active)
			(child as Button).add_theme_color_override("font_color",
				UIKit.GOLD if active else UIKit.TEXT)
			i += 1


func refresh() -> void:
	for k in pages.keys():
		var p: Variant = pages[k]
		if p.has_method("refresh"):
			p.refresh()
	_refresh_bar()


func on_cycle_finished(_rep: Dictionary) -> void:
	refresh()
