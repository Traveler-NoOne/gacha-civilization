class_name KeyBinds
extends RefCounted
## 快捷键（Input Map 的薄封装）✓
##
## 为什么要有它：InputMap 本身只活在内存里，改完重开就没了；
## 这里负责「列出可改的动作 + 读写玩家覆盖 + 生成显示文字」，
## 真正的按键表还是 project.godot 的 Input Map（默认值）✓

## 可改键的动作。**id 必须和 project.godot → Input Map 里的名字一字不差** ✓
const ACTIONS := [
	{"id": "end_cycle", "name": "结束周期"},
	{"id": "view_treasure", "name": "打开至宝"},
	{"id": "view_gacha", "name": "打开世界泡"},
	{"id": "view_world", "name": "回到世界"},
	{"id": "close_ui", "name": "关闭窗口 / 取消"},
]


## 启动时调一次：把玩家存过的键位覆盖到 InputMap 上 ✓
static func apply_saved() -> void:
	for a in ACTIONS:
		var id := str(a["id"])
		var code := AppSettings.key_bind(id)
		if code > 0:
			_set_key(id, code)


## 改一个键：写进 InputMap + 持久化 ✓
static func rebind(action: String, ev: InputEventKey) -> void:
	var code := ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
	if code <= 0:
		return
	_set_key(action, code)
	AppSettings.set_key_bind(action, code)


## 恢复默认：清掉覆盖，重新读 project.godot 的默认事件 ✓
static func reset_defaults() -> void:
	InputMap.load_from_project_settings()
	AppSettings.clear_key_binds()


## 当前按键的显示文字（"Space" / "Esc" / "1" …）✓
static func key_text(action: String) -> String:
	if not InputMap.has_action(action):
		return "—"
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			var k := e as InputEventKey
			var code := k.physical_keycode if k.physical_keycode != 0 else k.keycode
			return OS.get_keycode_string(code)
	return "—"


static func _set_key(action: String, code: int) -> void:
	if not InputMap.has_action(action):
		return
	InputMap.action_erase_events(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	InputMap.action_add_event(action, ev)
