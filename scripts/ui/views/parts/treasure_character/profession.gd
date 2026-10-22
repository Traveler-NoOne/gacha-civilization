class_name CharacterProfession
## 角色页 · 「职业」子页的构建器（无状态）
## 参数：详情容器 / 要显示的单位 / 变化后的回调（通常是页面自己的 refresh）
static func build(detail_host: VBoxContainer, u: Dictionary, on_changed: Callable) -> void:
	var my := str(u.get("profession", UnitDB.MELEE))
	var head := UIKit.panel(Palette.BG_PANEL_2, UnitDB.profession_color(my), 6)
	detail_host.add_child(head)
	var hv := HBoxContainer.new()
	hv.add_theme_constant_override("separation", UI.fs(8))
	head.add_child(hv)
	var ic := GeoIcon.new()
	ic.custom_minimum_size = Vector2(UI.px(52), UI.px(52))
	ic.setup(UnitDB.profession_icon(my), UnitDB.profession_color(my))
	hv.add_child(ic)
	var ht := VBoxContainer.new()
	ht.add_theme_constant_override("separation", UI.fs(2))
	hv.add_child(ht)
	ht.add_child(UIKit.text_label("当前职业：%s" % UnitDB.profession_name(my), 16, UnitDB.profession_color(my)))
	var d := UIKit.dim(UnitDB.profession_desc(my), 11)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ht.add_child(d)
	var rng := int((UnitDB.PROFESSIONS[my] as Dictionary).get("range", 1))
	if rng >= 2:
		ht.add_child(UIKit.text_label("攻击距离：%d 格（可以隔一格攻击）" % rng, 11, Palette.OK))

	detail_host.add_child(UIKit.title("克制关系总览", 15))
	var g := UIKit.grid(6, 8, 4)
	detail_host.add_child(g)
	g.add_child(UIKit.dim("攻方＼守方", 11))
	for p in UnitDB.PROFESSION_ORDER:
		g.add_child(UIKit.text_label(UnitDB.profession_name(p), 11, UnitDB.profession_color(p)))
	for a in UnitDB.PROFESSION_ORDER:
		g.add_child(UIKit.text_label(UnitDB.profession_name(a), 11, UnitDB.profession_color(a)))
		for b in UnitDB.PROFESSION_ORDER:
			var adv := UnitDB.advantage(a, b)
			var txt := "—"
			var col := Palette.TEXT_FAINT
			if adv > 0:
				txt = "克制 +30%"
				col = Palette.OK
			elif adv < 0:
				txt = "被克制 −20%"
				col = Palette.BAD
			var cell := UIKit.text_label(txt, 10, col)
			g.add_child(cell)

	detail_host.add_child(UIKit.spacer(4))
	detail_host.add_child(UIKit.title("该单位的克制结果", 15))
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", UI.fs(2))
	detail_host.add_child(rows)
	for enemy in UnitDB.PROFESSION_ORDER:
		var a2 := UnitDB.advantage(my, enemy)
		var e2 := UnitDB.advantage(enemy, my)
		var text := "对 %s：均势" % UnitDB.profession_name(enemy)
		var col2 := Palette.TEXT_DIM
		if a2 > 0 and e2 < 0:
			text = "对 %s：单方面克制（+30%% 伤害）" % UnitDB.profession_name(enemy)
			col2 = Palette.OK
		elif a2 > 0:
			text = "对 %s：互相克制（+30%% / −20%%）" % UnitDB.profession_name(enemy)
			col2 = Palette.WARN
		elif a2 < 0 and e2 > 0:
			text = "对 %s：被单方面克制（−20%% 伤害）" % UnitDB.profession_name(enemy)
			col2 = Palette.BAD
		rows.add_child(UIKit.text_label(text, 11, col2))

	# 防御者/支援者的特殊说明
	detail_host.add_child(UIKit.spacer(4))
	var note := UIKit.panel(Palette.BG_PANEL_2, Palette.LINE_SOFT, 5)
	detail_host.add_child(note)
	var nv := VBoxContainer.new()
	note.add_child(nv)
	nv.add_child(UIKit.title("职业机制说明", 14))
	var notes := [
		"防御者：小幅度减免所在格子及队伍中单位所受伤害（−20%），对投射者的伤害大幅度减免（−60%）。",
		"支援者：不直接造成伤害，而是根据条件增幅特定单位的伤害或提供减免。",
		"投射者：射程为 2 格，能够攻击间隔一个格子的目标。",
		"战斗规则：除非有专门设计，伤害都是个体对个体结算；目标格子存在多个单位时需要专门选择，敌人 AI 面对多单位格子随机选择，只有高危及以上的敌人才会考虑克制关系。",
	]
	for n in notes:
		var l := UIKit.dim(n, 11)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nv.add_child(l)
