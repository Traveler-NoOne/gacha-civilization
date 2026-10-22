class_name CharacterRank
## 角色页 · 「位阶」子页的构建器（无状态）
## 参数：详情容器 / 要显示的单位 / 变化后的回调（通常是页面自己的 refresh）
static func build(detail_host: VBoxContainer, u: Dictionary, on_changed: Callable) -> void:
	var rank := str(u.get("rank", UnitDB.RECRUIT))
	var exp := int(u.get("exp", 0))
	var cap := UnitDB.exp_cap(rank)
	var prog := UnitDB.progress_of(u)
	var mul := UnitDB.rank_multiplier(rank, prog)

	var head := UIKit.panel(UIKit.BG_PANEL_2, UnitDB.rank_color(rank), 6)
	detail_host.add_child(head)
	var hv := HBoxContainer.new()
	hv.add_theme_constant_override("separation", UI.fs(8))
	head.add_child(hv)
	var ic := GeoIcon.new()
	ic.custom_minimum_size = Vector2(UI.px(52), UI.px(52))
	ic.setup(UnitDB.rank_icon(rank), UnitDB.rank_color(rank))
	hv.add_child(ic)
	var ht := VBoxContainer.new()
	ht.add_theme_constant_override("separation", UI.fs(3))
	ht.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.add_child(ht)
	ht.add_child(UIKit.text_label("当前位阶：%s" % UnitDB.rank_name(rank), 16, UnitDB.rank_color(rank)))
	var d := UIKit.dim(UnitDB.rank_desc(rank), 11)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ht.add_child(d)
	ht.add_child(UIKit.text_label("当前属性倍率：×%.2f" % mul, 13,
		UIKit.OK if mul >= 1.0 else UIKit.WARN))
	ht.add_child(UIKit.progress_bar_row(exp, cap, prog, UnitDB.rank_color(rank)))

	detail_host.add_child(UIKit.title("经验来源", 15))
	var eg := UIKit.grid(2, 16, 3)
	detail_host.add_child(eg)
	eg.add_child(UIKit.dim("经验值上限", 12))
	eg.add_child(UIKit.text_label("%d" % cap, 12, UIKit.TEXT))
	eg.add_child(UIKit.dim("周期循环获得", 12))
	eg.add_child(UIKit.text_label("%d / %d（上限 %d）" % [
		int(u.get("exp_from_cycles", 0)), UnitDB.EXP_FROM_CYCLES_CAP, UnitDB.EXP_FROM_CYCLES_CAP], 12, UIKit.TEXT))
	eg.add_child(UIKit.dim("战斗获得", 12))
	eg.add_child(UIKit.text_label("%d" % int(u.get("exp_from_combat", 0)), 12, UIKit.TEXT))

	detail_host.add_child(UIKit.spacer(4))
	detail_host.add_child(UIKit.title("位阶一览", 15))
	var tbl := UIKit.grid(5, 10, 4)
	detail_host.add_child(tbl)
	tbl.add_child(UIKit.dim("位阶", 11))
	tbl.add_child(UIKit.dim("倍率区间", 11))
	tbl.add_child(UIKit.dim("经验上限", 11))
	tbl.add_child(UIKit.dim("周期经验", 11))
	tbl.add_child(UIKit.dim("说明", 11))
	for r in UnitDB.RANK_ORDER:
		var rd: Dictionary = UnitDB.RANKS[r]
		var is_cur := r == rank
		tbl.add_child(UIKit.text_label(UnitDB.rank_name(r), 11,
			UnitDB.rank_color(r) if is_cur else UIKit.TEXT_DIM))
		tbl.add_child(UIKit.text_label("%.1f ~ %.1f" % [float(rd["mul_min"]), float(rd["mul_max"])], 11, UIKit.TEXT))
		tbl.add_child(UIKit.text_label("%d" % int(rd["exp_cap"]), 11, UIKit.TEXT))
		tbl.add_child(UIKit.text_label("≤ %d" % UnitDB.EXP_FROM_CYCLES_CAP, 11, UIKit.TEXT))
		var sd := UIKit.dim(str(rd["desc"]).split("。")[0], 10)
		sd.custom_minimum_size = Vector2(UI.px(240), UI.px(0))
		sd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tbl.add_child(sd)

	detail_host.add_child(UIKit.spacer(6))
	var ops := HBoxContainer.new()
	ops.add_theme_constant_override("separation", UI.fs(6))
	detail_host.add_child(ops)
	var gain := UIKit.small("模拟训练（+15 战斗经验，消耗货币 80）", 12)
	gain.pressed.connect(func() -> void:
		if Res.amount(GameState.state, "currency") < 80.0:
			GameState.toast.emit("货币不足")
			return
		Res.add(GameState.state, "currency", -80.0)
		var r := Units.gain_exp(GameState.state, str(u["uid"]), 15, "combat")
		GameState.toast.emit("获得经验 %d（%d/%d）" % [int(r.get("gain", 0)),
			int(r.get("exp", 0)), int(r.get("cap", 0))] if r["ok"] else str(r["why"]))
		on_changed.call())
	ops.add_child(gain)

	var prom := UIKit.small("晋升位阶", 12)
	UIKit.style_button(prom, true)
	if not UnitDB.can_promote(u):
		prom.disabled = true
		if UnitDB.next_rank(rank) == "":
			prom.tooltip_text = "已是最高位阶"
		else:
			prom.tooltip_text = "经验未满（%d/%d）" % [exp, cap]
	prom.pressed.connect(func() -> void:
		var r := Units.promote_unit(GameState.state, str(u["uid"]))
		if not r["ok"]:
			GameState.toast.emit(str(r["why"]))
		else:
			GameState.toast.emit("%s 晋升为 %s" % [u["name"], UnitDB.rank_name(str(r["rank"]))])
		on_changed.call())
	ops.add_child(prom)
