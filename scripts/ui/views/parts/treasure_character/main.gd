class_name CharacterMain
## 角色页 · 「主要」子页的构建器（无状态）
## 参数：详情容器 / 要显示的单位 / 变化后的回调（通常是页面自己的 refresh）
static func build(detail_host: VBoxContainer, u: Dictionary, on_changed: Callable) -> void:
	var attr_panel := UIKit.panel(UIKit.BG_PANEL_2, UIKit.LINE_SOFT, 6)
	detail_host.add_child(attr_panel)
	var av := VBoxContainer.new()
	av.add_theme_constant_override("separation", UI.fs(4))
	attr_panel.add_child(av)
	av.add_child(UIKit.title("属性信息", 15))

	# 基础属性 vs 位阶修正后的实际战斗属性
	var base: Dictionary = u.get("attr", {})
	var eff: Dictionary = Units.unit_combat_attr(GameState.state, u)
	var mul := UnitDB.rank_multiplier(str(u.get("rank", "")), UnitDB.progress_of(u))
	var names := {
		"atk": "攻击力", "def": "防御力", "hp": "生命值",
		"spd": "移动速度", "agi": "灵敏值",
	}
	var g := UIKit.grid(4, 14, 4)
	av.add_child(g)
	g.add_child(UIKit.dim("属性", 11))
	g.add_child(UIKit.dim("基础", 11))
	g.add_child(UIKit.dim("实战（含位阶）", 11))
	g.add_child(UIKit.dim("倍率", 11))
	for k in ["atk", "def", "hp", "spd", "agi"]:
		if not base.has(k):
			continue
		g.add_child(UIKit.text_label(str(names.get(k, k)), 12, UIKit.TEXT_DIM))
		g.add_child(UIKit.text_label(str(base[k]), 12, UIKit.TEXT))
		g.add_child(UIKit.text_label("%.1f" % float(eff.get(k, 0.0)), 12,
			UIKit.OK if mul >= 1.0 else UIKit.WARN))
		g.add_child(UIKit.dim("×%.2f" % mul, 11))
	av.add_child(UIKit.dim("位阶倍率 ×%.2f = 在 [%.2f, %.2f] 区间内按经验进度插值" % [
		mul, float(UnitDB.RANKS[str(u.get("rank", "recruit"))]["mul_min"]),
		float(UnitDB.RANKS[str(u.get("rank", "recruit"))]["mul_max"])], 11))

	var lv_row := HBoxContainer.new()
	lv_row.add_theme_constant_override("separation", UI.fs(6))
	av.add_child(lv_row)
	lv_row.add_child(UIKit.dim("等级 %d / 上限（星级 %d → %d 级）" % [
		int(u.get("level", 1)), int(u.get("star", 1)), int(u.get("star", 1)) * 20], 12))
	var up := UIKit.small("提升等级（消耗货币）", 12)
	up.pressed.connect(func() -> void:
		var cost := 120.0 * float(u.get("level", 1))
		if Res.amount(GameState.state, "currency") < cost:
			GameState.toast.emit("货币不足（需要 %d）" % int(cost))
			return
		Res.add(GameState.state, "currency", -cost)
		u["level"] = int(u["level"]) + 1
		Journal.add(GameState.state, "%s 提升到 Lv.%d。" % [u["name"], int(u["level"])], "unit")
		GameState.state_changed.emit()
		on_changed.call())
	lv_row.add_child(up)

	# 携带信息
	var carry := UIKit.panel(UIKit.BG_PANEL_2, UIKit.LINE_SOFT, 6)
	detail_host.add_child(carry)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", UI.fs(3))
	carry.add_child(cv)
	var ch := HBoxContainer.new()
	ch.add_theme_constant_override("separation", UI.fs(8))
	cv.add_child(ch)
	ch.add_child(UIKit.title("携带信息", 15))
	var auto_eq := UIKit.small("随机分配一件装备", 11)
	auto_eq.pressed.connect(func() -> void:
		_auto_equip(u, on_changed))
	ch.add_child(auto_eq)
	var eq: Dictionary = u.get("equipped", {"weapon": "", "relic": ""})
	for slot in ["weapon", "relic"]:
		var slot_name := "武装" if slot == "weapon" else "战备"
		var item_id := str(eq.get(slot, ""))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", UI.fs(6))
		cv.add_child(row)
		row.add_child(UIKit.dim(slot_name, 12))
		if item_id == "":
			row.add_child(UIKit.text_label("（空）", 12, UIKit.TEXT_FAINT))
		else:
			var it := _find_equipment(item_id)
			row.add_child(UIKit.text_label(str(it.get("name", item_id)), 12,
				Consts.rarity_color(int(it.get("rarity", 1)))))

	var hint := UIKit.dim("说明：角色可以装备「召唤」获得的武装与战备；训练军 / 募集军不能装备召唤产物。", 11)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_host.add_child(hint)

static func _find_equipment(id: String) -> Dictionary:
	for e in GameState.state["equipment"]:
		if str(e["id"]) == id:
			return e
	return {}


static func _auto_equip(u: Dictionary, on_changed: Callable) -> void:
	var pool: Array = GameState.state["equipment"]
	if pool.is_empty():
		GameState.toast.emit("还没有任何装备，去召唤吧")
		return
	var pick: Dictionary = pool[randi() % pool.size()]
	var eq: Dictionary = u.get("equipped", {"weapon": "", "relic": ""})
	eq[str(pick.get("slot", "weapon"))] = str(pick["id"])
	u["equipped"] = eq
	GameState.toast.emit("%s 装备了 %s" % [u["name"], pick["name"]])
	on_changed.call()
