class_name CharacterSkill
## 角色页 · 「技能」子页的构建器（无状态）
## 参数：详情容器 / 要显示的单位 / 变化后的回调（通常是页面自己的 refresh）
static func build(detail_host: VBoxContainer, u: Dictionary, on_changed: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UI.fs(6))
	detail_host.add_child(row)

	var tal := UIKit.panel(UIKit.BG_PANEL_2, UIKit.LINE_SOFT, 6)
	tal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(tal)
	var tv := VBoxContainer.new()
	tal.add_child(tv)
	tv.add_child(UIKit.title("天赋", 15))
	tv.add_child(UIKit.dim("伴随等级提升而解锁", 11))
	var unlock_levels := [1, 10, 20, 40]
	var tnames := ["%s·共鸣" % u["name"], "%s·强化" % u["name"],
		"%s·领域" % u["name"], "%s·终焉" % u["name"]]
	for i in unlock_levels.size():
		var need := int(unlock_levels[i])
		var unlocked := int(u.get("level", 1)) >= need
		tv.add_child(UIKit.text_label("%s %s" % ["✔" if unlocked else "✖", tnames[i]], 12,
			UIKit.OK if unlocked else UIKit.TEXT_FAINT))
		tv.add_child(UIKit.dim("　　Lv.%d 解锁" % need, 10))

	var sk := UIKit.panel(UIKit.BG_PANEL_2, UIKit.LINE_SOFT, 6)
	sk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sk)
	var sv := VBoxContainer.new()
	sk.add_child(sv)
	sv.add_child(UIKit.title("技能", 15))
	sv.add_child(UIKit.dim("需要通过使用、训练、强化来提升", 11))
	var skills: Array = u.get("skills", [])
	if skills.is_empty():
		sv.add_child(UIKit.dim("（尚未觉醒技能）"))
	for s in skills:
		sv.add_child(UIKit.text_label("· %s Lv.%d" % [str(s.get("name", "?")), int(s.get("level", 1))], 12))
	var add := UIKit.small("训练一次（消耗货币 200）", 12)
	add.pressed.connect(func() -> void:
		if GameState.res("currency") < 200.0:
			GameState.toast.emit("货币不足")
			return
		GameState.add_res("currency", -200.0)
		var arr: Array = u.get("skills", [])
		var nm := "%s·奥义" % u["name"]
		var found := false
		for s in arr:
			if str(s.get("name", "")) == nm:
				s["level"] = int(s["level"]) + 1
				found = true
		if not found:
			arr.append({"name": nm, "level": 1})
		u["skills"] = arr
		GameState.add_log("%s 的技能获得提升。" % u["name"], "unit")
		GameState.state_changed.emit()
		on_changed.call())
	sv.add_child(add)

	# v1.1：独特机制接口（为抽卡角色预留）
	var uniq := UIKit.panel(UIKit.BG_PANEL_2, UIKit.LINE_SOFT, 6)
	detail_host.add_child(uniq)
	var uv := VBoxContainer.new()
	uniq.add_child(uv)
	uv.add_child(UIKit.title("独特机制（预留接口）", 15))
	var uniques: Array = u.get("unique", [])
	if uniques.is_empty():
		uv.add_child(UIKit.dim("该单位暂时没有独特机制。召唤角色可以挂载以下接口：", 11))
	else:
		for key in uniques:
			uv.add_child(UIKit.text_label("· " + str(UnitDB.UNIQUE_HOOKS.get(str(key), key)), 12, UIKit.GOLD))
	var gh := HBoxContainer.new()
	gh.add_theme_constant_override("separation", UI.fs(4))
	uv.add_child(gh)
	for key2 in UnitDB.UNIQUE_HOOKS.keys():
		if uniques.has(key2):
			continue
		var kb := UIKit.tiny(str(UnitDB.UNIQUE_HOOKS[key2]).split("：")[0], 11)
		kb.tooltip_text = str(UnitDB.UNIQUE_HOOKS[key2])
		kb.pressed.connect(func() -> void:
			(u["unique"] as Array).append(key2)
			GameState.toast.emit("已为该单位挂载机制：%s" % str(UnitDB.UNIQUE_HOOKS[key2]))
			on_changed.call())
		gh.add_child(kb)
