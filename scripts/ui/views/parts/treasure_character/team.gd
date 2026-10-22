class_name CharacterTeam
## 角色页 · 「team」子页的构建器（无状态）
## 参数：详情容器 / 要显示的单位 / 变化后的回调（通常是页面自己的 refresh）
static func build(detail_host: VBoxContainer, u: Dictionary, on_changed: Callable) -> void:
	var uid := str(u["uid"])
	var cur_team := int(u.get("team", -1))
	var cur_tile := str(u.get("tile", ""))

	# ---- 编队 ----
	detail_host.add_child(UIKit.title("队伍编成（每队最多 %d 个单位）" % UnitDB.UNITS_PER_TEAM, 15))
	var teams: Array = GameState.state["teams"]
	var tg := HBoxContainer.new()
	tg.add_theme_constant_override("separation", UI.fs(6))
	detail_host.add_child(tg)
	for i in teams.size():
		var idx := i
		var team: Dictionary = teams[i]
		var members := Units.team_units(GameState.state, idx)
		var pane := UIKit.panel(Palette.BG_PANEL_2,
			Palette.GOLD if idx == cur_team else Palette.LINE_SOFT, 6)
		pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tg.add_child(pane)
		var pv := VBoxContainer.new()
		pv.add_theme_constant_override("separation", UI.fs(3))
		pane.add_child(pv)
		pv.add_child(UIKit.text_label("%s（%d/%d）" % [str(team["name"]),
			members.size(), UnitDB.UNITS_PER_TEAM], 13,
			Palette.GOLD if idx == cur_team else Palette.TEXT))
		if members.is_empty():
			pv.add_child(UIKit.dim("（空）", 11))
		for m in members:
			var mr := HBoxContainer.new()
			mr.add_theme_constant_override("separation", UI.fs(4))
			pv.add_child(mr)
			var mi := GeoIcon.new()
			mi.custom_minimum_size = Vector2(UI.px(20), UI.px(20))
			mi.setup(UnitDB.profession_icon(str(m.get("profession", ""))),
				UnitDB.profession_color(str(m.get("profession", ""))))
			mr.add_child(mi)
			var ml := UIKit.text_label(str(m["name"]), 11,
				Consts.rarity_color(int(m.get("rarity", 1))))
			ml.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			mr.add_child(ml)
			var x := UIKit.tiny("✕", 10, true)
			x.pressed.connect(func() -> void:
				Units.remove_from_team(GameState.state, str(m["uid"]))
				on_changed.call())
			mr.add_child(x)
		var join := UIKit.small("加入此队" if idx != cur_team else "退出队伍", 11)
		join.pressed.connect(func() -> void:
			if idx == cur_team:
				Units.remove_from_team(GameState.state, uid)
			else:
				var r := Units.assign_team(GameState.state, uid, idx)
				if not r["ok"]:
					GameState.toast.emit(str(r["why"]))
			on_changed.call())
		pv.add_child(join)

	# ---- 派驻 ----
	detail_host.add_child(UIKit.spacer(4))
	detail_host.add_child(UIKit.title("地块派驻（每格最多 %d 个单位）" % UnitDB.UNITS_PER_TILE, 15))
	detail_host.add_child(UIKit.text_label("当前状态：%s" % (
		"驻守 %s" % cur_tile if cur_tile != "" else "未派驻（在营地待命）"), 12,
		Palette.OK if cur_tile != "" else Palette.TEXT_DIM))

	var own := TileManager.owned_tiles(GameState.state)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", UI.fs(3))
	detail_host.add_child(list)
	var shown := 0
	for t in own:
		var key := TileManager.tile_key(t)
		var on_tile := Units.units_on_tile(GameState.state, key)
		var is_here := key == cur_tile
		var row := PanelContainer.new()
		UIKit.apply_panel(row, Palette.BG_PANEL_2, Palette.GOLD if is_here else Palette.LINE_SOFT, 5)
		list.add_child(row)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", UI.fs(6))
		row.add_child(h)
		var label := "%s　[%s]　驻军 %d/%d" % [
			str(t.get("name", key)) if str(t.get("name", "")) != "" else key,
			key, on_tile.size(), UnitDB.UNITS_PER_TILE]
		var ll := UIKit.text_label(label, 12, Palette.TEXT)
		ll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(ll)
		if is_here:
			var wb := UIKit.small("撤回", 11)
			wb.pressed.connect(func() -> void:
				Units.withdraw_unit(GameState.state, uid)
				on_changed.call())
			h.add_child(wb)
		else:
			var db := UIKit.small("派驻", 11)
			db.disabled = on_tile.size() >= UnitDB.UNITS_PER_TILE
			if db.disabled:
				db.tooltip_text = "该地块已驻满"
			db.pressed.connect(func() -> void:
				var r := Units.deploy_unit(GameState.state, uid, key)
				if not r["ok"]:
					GameState.toast.emit(str(r["why"]))
				on_changed.call())
			h.add_child(db)
		var names: Array[String] = []
		for m in on_tile:
			names.append(str(m["name"]))
		if not names.is_empty():
			var nl := UIKit.dim("　".join(names), 10)
			nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(nl)
		shown += 1
	if shown == 0:
		list.add_child(UIKit.dim("你还没有任何领地。"))
	# 原先直接调 refresh() 的地方，改成：
	on_changed.call()
