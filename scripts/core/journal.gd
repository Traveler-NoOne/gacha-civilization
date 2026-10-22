class_name Journal
extends RefCounted
## 日志：往 state["log"] / state["manual_log"] 里写一条 ✓
##
## ⚠️ 这是**玩家看得到的流水**，不是调试输出 —— 文案与 kind 有既有口径，别随手改 ✓
##
static func add(state: Dictionary, text: String, kind: String = "info") -> void:
	_add(state, text, kind)


static func _add(state: Dictionary, text: String, kind: String) -> void:
	var entry := {"cycle": int(state.get("cycle", 1)), "text": text, "kind": kind}
	var l: Array = state["log"]
	l.append(entry)
	while l.size() > 300:
		l.pop_front()


static func manual(state: Dictionary, text: String) -> void:
	var l: Array = state["manual_log"]
	l.append({"cycle": int(state["cycle"]), "text": text})
	_add(state, "记录：%s" % text, "record")
	GameState.state_changed.emit()
