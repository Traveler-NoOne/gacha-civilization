class_name Save
extends RefCounted
## 存档槽：路径 / 是否存在 / 摘要 / 写 / 读 / 删 / 自动存档 ✓
##
## ⚠️ 分工：本文件只管**文件**；把读出来的 `state` 装进本局、并给随机数播种，
##    是 `GameState.load_from_slot()` 的事 ✓
## ⚠️ 1.0 期不做旧档兼容：版本不符**直接删档**（地形/数据模型换了，留着只会显示成不认识的种类）✓

const MAGIC := "gacha_civilization_demo"
const VERSION := 5


static func path(slot: int) -> String:
	return "%s/slot_%02d.json" % [Consts.SAVE_DIR, slot]


static func exists(slot: int) -> bool:
	return FileAccess.file_exists(path(slot))


static func summary(slot: int) -> Dictionary:
	if not exists(slot):
		return {}
	var f := FileAccess.open(path(slot), FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = parsed
	var st: Dictionary = d.get("state", {})
	return {
		"slot": slot,
		"cycle": int(st.get("cycle", 0)),
		"tiles": int((st.get("tiles", {}) as Dictionary).size()),
		"chars": (st.get("units", []) as Array).size(),
		"time": str(d.get("saved_at", "")),
	}


static func write(slot: int, state: Dictionary) -> bool:
	var payload := {
		"magic": MAGIC,
		"version": VERSION,
		"saved_at": Time.get_datetime_string_from_system(),
		"state": state,
	}
	var f := FileAccess.open(path(slot), FileAccess.WRITE)
	if f == null:
		GameState.toast.emit("存档失败：无法写入槽位 %d" % slot)
		return false
	f.store_string(JSON.stringify(payload, "  "))
	f.close()
	state["current_slot"] = slot
	GameState.toast.emit("已保存到槽位 %d" % (slot + 1))
	GameState.state_changed.emit()
	return true


## 读一个槽位：校验魔数 / 版本（不符直接删档）→ 返回 `state`；任何失败都返回 `{}` ✓
static func read(slot: int) -> Dictionary:
	if not exists(slot):
		GameState.toast.emit("槽位 %d 没有存档" % (slot + 1))
		return {}
	var f := FileAccess.open(path(slot), FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		GameState.toast.emit("存档损坏")
		return {}
	var d: Dictionary = parsed
	if d.get("magic", "") != MAGIC:
		GameState.toast.emit("存档格式不匹配")
		return {}
	# 1.0 期不做旧档兼容 —— 版本不符直接拒绝并删掉（留到 2.0 再谈迁移）
	if int(d.get("version", 0)) != VERSION:
		var was := int(d.get("version", 0))
		erase(slot)
		GameState.toast.emit("存档已过期（该档 v%d，当前 v%d），已删除，请新开一局" % [was, VERSION])
		return {}
	var loaded: Dictionary = d.get("state", {})
	if loaded.is_empty():
		GameState.toast.emit("存档内容为空")
		return {}
	return loaded


static func erase(slot: int) -> bool:
	if not exists(slot):
		return false
	var err := DirAccess.remove_absolute(ProjectSettings.globalize_path(path(slot)))
	if err != OK:
		GameState.toast.emit("删除失败（错误 %d）" % err)
		return false
	GameState.toast.emit("已删除槽位 %d" % (slot + 1))
	GameState.state_changed.emit()
	return true


static func autosave(state: Dictionary) -> void:
	write(Consts.AUTOSAVE_SLOT, state)


static func has_continue() -> bool:
	return exists(Consts.AUTOSAVE_SLOT)


static func any() -> bool:
	for i in Consts.SAVE_SLOTS:
		if exists(i):
			return true
	return false
