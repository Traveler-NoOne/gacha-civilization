class_name Units
extends RefCounted
## 单位仓库 / 派驻 / 编队 / 招募 / 维护费 / 经验 / 客人 ✓
##
## ⚠️ 只管"人"：**怎么打**在 `Combat`，**怎么造建筑**在 `Buildings` ✓
## ⚠️ 需要状态时一律传 `state`（不读全局 GameState.state）✓
##
## v1.6：开局赠送 5★ 公民「格蕾修」。
## 她是前文明「方舟计划」的乘员——方舟带着前文明的全部科技成果离开、寻找新的世界。
## 所以她是"从毁灭的世界漂来的遗民"，正是本作核心设定（这枚世界泡靠收留末日来客立起来）
## 的具象化，也是召唤 / 招募系统的预告：她本身就是第一位"客人"（开局已是公民）。
## 数值与 card_db 的 char_grieso 保持一致（攻中等 / 防低 / 血低 / 速中等 / 敏高）。
static func grant_starting(state: Dictionary) -> void:
	var card := CardDB.find("char_grieso")
	if card.is_empty():
		return
	# 数值与职业都从卡池数据取（PROFESSION_BY_ID 里 char_grieso -> projectile），
	# 这样格蕾修的数值只有 card_db 一份来源，改平衡不会漏改这里。
	card = card.duplicate()
	card["profession"] = CardDB.profession_of(card)
	var u := UnitDB.from_card(card)
	u["status"] = UnitDB.STATUS_CITIZEN
	u["tile"] = str(state.get("capital", ""))
	u["acquired_cycle"] = int(state["cycle"])
	u["move_left"] = max_move(state, u)
	(state["units"] as Array).append(u)
	GameState.add_log("格蕾修随方舟的残骸漂流至此，成为你的第一位公民。", "unit")


static func unit_by_uid(state: Dictionary, uid: String) -> Dictionary:
	for u in state["units"]:
		if str(u["uid"]) == uid:
			return u
	return {}


static func units_on_tile(state: Dictionary, key: String) -> Array:
	var out := []
	for u in state["units"]:
		if str(u.get("tile", "")) == key:
			out.append(u)
	return out


## 未派驻到任何地块的单位
static func idle_units(state: Dictionary) -> Array:
	var out := []
	for u in state["units"]:
		if str(u.get("tile", "")) == "":
			out.append(u)
	return out


## 派驻单位到地块（一个格子最多 4 个单位，v1.1 第 9 条）
static func deploy_unit(state: Dictionary, uid: String, key: String) -> Dictionary:
	var u := unit_by_uid(state, uid)
	if u.is_empty():
		return {"ok": false, "why": "找不到该单位"}
	var tile := TileManager.tile_at(state, key)
	if tile.is_empty():
		return {"ok": false, "why": "地块不存在"}
	if tile.get("owner", Consts.Owner.NONE) != Consts.Owner.PLAYER:
		return {"ok": false, "why": "只能派驻到我方地块"}
	if not Strongholds.control_ok(state, key):
		return {"ok": false, "why": "该领地掌控力不足 %.0f%%" % (Consts.CONTROL_SELF_OPERATE * 100.0)}
	var cur := units_on_tile(state, key)
	if str(u.get("tile", "")) == key:
		return {"ok": false, "why": "该单位已经在此地块"}
	if cur.size() >= UnitDB.UNITS_PER_TILE:
		return {"ok": false, "why": "该地块已驻满 %d 个单位" % UnitDB.UNITS_PER_TILE}
	u["tile"] = key
	GameState.add_log("%s 进驻 %s（该地块 %d/%d）。" % [
		str(u["name"]), key, units_on_tile(state, key).size(), UnitDB.UNITS_PER_TILE], "unit")
	GameState.state_changed.emit()
	return {"ok": true, "why": ""}


static func withdraw_unit(state: Dictionary, uid: String) -> Dictionary:
	var u := unit_by_uid(state, uid)
	if u.is_empty():
		return {"ok": false, "why": "找不到该单位"}
	var was := str(u.get("tile", ""))
	if was == "":
		return {"ok": false, "why": "该单位未派驻"}
	u["tile"] = ""
	GameState.add_log("%s 从 %s 撤回。" % [str(u["name"]), was], "unit")
	GameState.state_changed.emit()
	return {"ok": true, "why": ""}


# ---------------------------------------------------------------------------
# v1.5：客人 / 公民、部署（掌控力门槛）、移动与攻击
# ---------------------------------------------------------------------------


static func units_by_status(state: Dictionary, s: String) -> Array:
	var out := []
	for u in state["units"]:
		if str(u.get("status", UnitDB.STATUS_CITIZEN)) == s:
			out.append(u)
	return out


static func guest_units(state: Dictionary) -> Array:
	return units_by_status(state, UnitDB.STATUS_GUEST)


static func citizen_units(state: Dictionary) -> Array:
	return units_by_status(state, UnitDB.STATUS_CITIZEN)


## 合法部署地块：我方领地 + 掌控力达标 + 未驻满
static func deployable_keys(state: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for t in TileManager.owned_tiles(state):
		var k := TileManager.tile_key(t)
		if k == "" or not Strongholds.control_ok(state, k):
			continue
		if units_on_tile(state, k).size() >= UnitDB.UNITS_PER_TILE:
			continue
		out.append(k)
	return out


## 最大移动力：2 移动速度 = 1 移动力（用基础速度，不吃位阶/等级倍率）
static func max_move(state: Dictionary, unit: Dictionary) -> int:
	var spd := float((unit.get("attr", {}) as Dictionary).get("spd", 2))
	return maxi(1, int(floor(spd / float(Consts.MOVE_PER_SPEED))))


## 招募第一步：只校验，不改状态（真正的转换在 confirm_recruit）
static func begin_recruit(state: Dictionary, uid: String) -> Dictionary:
	var u := unit_by_uid(state, uid)
	if u.is_empty():
		return {"ok": false, "why": "找不到该单位"}
	if str(u.get("status", "")) != UnitDB.STATUS_GUEST:
		return {"ok": false, "why": "只有客人可以招募"}
	var keys := deployable_keys(state)
	if keys.is_empty():
		return {"ok": false, "why": "没有可部署的领地（需掌控力 ≥ 80% 且未驻满）"}
	state["pending_recruit"] = uid
	GameState.state_changed.emit()
	return {"ok": true, "why": "", "tiles": keys}


## 取消招募：客人保持客人，不做任何转换
static func cancel_recruit(state: Dictionary) -> void:
	if state.has("pending_recruit"):
		state.erase("pending_recruit")
		GameState.state_changed.emit()


static func pending_recruit_uid(state: Dictionary) -> String:
	return str(state.get("pending_recruit", ""))


## 招募的唯一转换点：客人 → 公民 + 落地
static func confirm_recruit(state: Dictionary, uid: String, key: String) -> Dictionary:
	var u := unit_by_uid(state, uid)
	if u.is_empty():
		return {"ok": false, "why": "找不到该单位"}
	if str(u.get("status", "")) != UnitDB.STATUS_GUEST:
		return {"ok": false, "why": "只有客人可以招募"}
	var t := TileManager.tile_at(state, key)
	if t.is_empty() or t.get("owner", Consts.Owner.NONE) != Consts.Owner.PLAYER:
		return {"ok": false, "why": "只能部署到我方领地"}
	if not Strongholds.control_ok(state, key):
		return {"ok": false, "why": "该领地掌控力不足 %.0f%%" % (Consts.CONTROL_SELF_OPERATE * 100.0)}
	if units_on_tile(state, key).size() >= UnitDB.UNITS_PER_TILE:
		return {"ok": false, "why": "该地块已驻满 %d 个单位，请另选" % UnitDB.UNITS_PER_TILE}
	u["status"] = UnitDB.STATUS_CITIZEN
	u["tile"] = key
	u["acquired_cycle"] = int(state["cycle"])
	u["move_left"] = max_move(state, u)
	state.erase("pending_recruit")
	GameState.add_log("%s 接受了招募，成为公民并进驻 %s。" % [str(u["name"]), key], "unit")
	GameState.state_changed.emit()
	return {"ok": true, "why": ""}


## 遣返：把客人送回他自己的世界（直接从库存移除）
static func dismiss_guest(state: Dictionary, uid: String) -> Dictionary:
	var u := unit_by_uid(state, uid)
	if u.is_empty():
		return {"ok": false, "why": "找不到该单位"}
	if str(u.get("status", "")) != UnitDB.STATUS_GUEST:
		return {"ok": false, "why": "只有客人可以遣返"}
	state["units"].erase(u)
	GameState.add_log("%s 被遣返回了自己的世界。" % str(u["name"]), "unit")
	GameState.state_changed.emit()
	return {"ok": true, "why": ""}


## 从库存移除一个单位（阵亡 / 遣返共用）
static func remove_unit(state: Dictionary, uid: String) -> bool:
	var u := unit_by_uid(state, uid)
	if u.is_empty():
		return false
	state["units"].erase(u)
	return true


## v1.6.1：驻军 —— 驻守在当前地块。
## 驻军时维护费打折（领地内 −60% / 领地外 −10%），代价是**不能移动或攻击**。
static func toggle_garrison(state: Dictionary, uid: String) -> Dictionary:
	var u := unit_by_uid(state, uid)
	if u.is_empty():
		return {"ok": false, "why": "找不到该单位"}
	if str(u.get("tile", "")) == "":
		return {"ok": false, "why": "该单位不在大世界上"}
	var g := not bool(u.get("garrisoned", false))
	u["garrisoned"] = g
	GameState.add_log("%s %s。" % [str(u["name"]), "开始驻军" if g else "解除驻军"], "unit")
	GameState.state_changed.emit()
	return {"ok": true, "why": "", "garrisoned": g}


## 编队：把单位加入某队（一队最多 4 个单位，v1.1 第 10 条）
static func assign_team(state: Dictionary, uid: String, team_index: int) -> Dictionary:
	var u := unit_by_uid(state, uid)
	if u.is_empty():
		return {"ok": false, "why": "找不到该单位"}
	var teams: Array = state["teams"]
	if team_index < 0 or team_index >= teams.size():
		return {"ok": false, "why": "队伍不存在"}
	var team: Dictionary = teams[team_index]
	var members: Array = team["members"]
	if members.has(uid):
		return {"ok": false, "why": "该单位已在此队伍"}
	if members.size() >= UnitDB.UNITS_PER_TEAM:
		return {"ok": false, "why": "该队伍已满 %d 个单位" % UnitDB.UNITS_PER_TEAM}
	# 先从原队伍移除（一个单位只能属于一个队伍）
	for t in teams:
		(t["members"] as Array).erase(uid)
	members.append(uid)
	u["team"] = team_index
	GameState.add_log("%s 编入%s。" % [str(u["name"]), str(team["name"])], "unit")
	GameState.state_changed.emit()
	return {"ok": true, "why": ""}


static func remove_from_team(state: Dictionary, uid: String) -> Dictionary:
	var u := unit_by_uid(state, uid)
	if u.is_empty():
		return {"ok": false, "why": "找不到该单位"}
	for t in state["teams"]:
		(t["members"] as Array).erase(uid)
	u["team"] = -1
	GameState.state_changed.emit()
	return {"ok": true, "why": ""}


static func team_units(state: Dictionary, team_index: int) -> Array:
	var teams: Array = state["teams"]
	if team_index < 0 or team_index >= teams.size():
		return []
	var out := []
	for uid in (teams[team_index]["members"] as Array):
		var u := unit_by_uid(state, str(uid))
		if not u.is_empty():
			out.append(u)
	return out


## 单位叠加装备后的战斗属性
static func unit_combat_attr(state: Dictionary, u: Dictionary) -> Dictionary:
	var a := UnitDB.effective_attr(u)
	var eq: Dictionary = u.get("equipped", {})
	for slot in ["weapon", "relic"]:
		var item_id := str(eq.get(slot, ""))
		if item_id == "":
			continue
		for e in state["equipment"]:
			if str(e["id"]) == item_id:
				var ea: Dictionary = e.get("attr", {})
				for k in ea.keys():
					a[k] = float(a.get(k, 0.0)) + float(ea[k])
	return a


## 获取经验（来源分「周期循环」与「战斗」两类，周期循环最多贡献 100 点）
static func gain_exp(state: Dictionary, uid: String, amount: int, source: String = "combat") -> Dictionary:
	var u := unit_by_uid(state, uid)
	if u.is_empty():
		return {"ok": false, "why": "找不到该单位"}
	var rank := str(u.get("rank", UnitDB.RECRUIT))
	var cap := UnitDB.exp_cap(rank)
	var cur := int(u.get("exp", 0))
	if cur >= cap:
		return {"ok": false, "why": "经验已满，可尝试晋升"}
	var gain := amount
	if source == "cycle":
		var used := int(u.get("exp_from_cycles", 0))
		var room := maxi(0, UnitDB.EXP_FROM_CYCLES_CAP - used)
		gain = mini(amount, room)
		if gain <= 0:
			return {"ok": false, "why": "周期循环经验已达上限（%d）" % UnitDB.EXP_FROM_CYCLES_CAP}
		u["exp_from_cycles"] = used + gain
		u["exp_from_cycle"] = int(u.get("exp_from_cycle", 0)) + gain
	else:
		u["exp_from_combat"] = int(u.get("exp_from_combat", 0)) + gain
	u["exp"] = mini(cap, cur + gain)
	GameState.state_changed.emit()
	return {"ok": true, "why": "", "gain": gain, "exp": int(u["exp"]), "cap": cap}


## 晋升到更高位阶（募集军 -> 正规军 -> 角色）
static func promote_unit(state: Dictionary, uid: String) -> Dictionary:
	var u := unit_by_uid(state, uid)
	if u.is_empty():
		return {"ok": false, "why": "找不到该单位"}
	var rank := str(u.get("rank", UnitDB.RECRUIT))
	var nxt := UnitDB.next_rank(rank)
	if nxt == "":
		return {"ok": false, "why": "已经是最高位阶"}
	if int(u.get("exp", 0)) < UnitDB.exp_cap(rank):
		return {"ok": false, "why": "经验未满（%d/%d）" % [int(u.get("exp", 0)), UnitDB.exp_cap(rank)]}
	u["rank"] = nxt
	u["exp"] = 0
	u["exp_from_cycles"] = 0
	u["exp_from_combat"] = 0
	GameState.add_log("%s 晋升为%s。" % [str(u["name"]), UnitDB.rank_name(nxt)], "unit")
	GameState.state_changed.emit()
	return {"ok": true, "why": "", "rank": nxt}


## 每周期给所有单位少量经验（周期循环来源，上限 100 点）
static func grow_unit_exp(state: Dictionary, report: Dictionary) -> void:
	var gained := 0
	for u in state["units"]:
		var r := gain_exp(state, str(u["uid"]), UnitDB.EXP_PER_CYCLE, "cycle")
		if r["ok"]:
			gained += int(r["gain"])
	if gained > 0:
		report["events"].append("单位在周期循环中累计获得 %d 点经验。" % gained)


# ---------------------------------------------------------------------------
# v1.5：单位维护费 / 客人离去 / 移动力重置
# ---------------------------------------------------------------------------


## 单个单位的周期维护费（客人只吃食物；公民吃食物 + 货币，驻守我方领地 −60%、领地外 −10%）
static func unit_upkeep_of(state: Dictionary, u: Dictionary) -> Dictionary:
	if UnitDB.is_guest(u):
		return {"food": Consts.GUEST_FOOD_PER_CYCLE, "currency": 0.0}
	var t := TileManager.tile_at(state, str(u.get("tile", "")))
	var own: bool = (not t.is_empty()) and t.get("owner", Consts.Owner.NONE) == Consts.Owner.PLAYER
	# v1.6.1：只有「驻军」状态才享受维护费折扣（领地内 −60% / 领地外 −10%）；行军时全额
	var mul := 1.0
	if bool(u.get("garrisoned", false)):
		mul = Consts.UPKEEP_MUL_IN_TERRITORY if own else Consts.UPKEEP_MUL_OUTSIDE
	return {"food": Consts.UNIT_UPKEEP_FOOD * mul, "currency": Consts.UNIT_UPKEEP_CURRENCY * mul}


## v1.7：全体单位的维护费合计（原来在 3 个地方各遍历一遍、口径容易漂）
static func units_upkeep_total(state: Dictionary) -> Dictionary:
	var out := {"food": 0.0, "currency": 0.0}
	for u in state["units"]:
		var uk := unit_upkeep_of(state, u)
		out["food"] = float(out["food"]) + float(uk.get("food", 0.0))
		out["currency"] = float(out["currency"]) + float(uk.get("currency", 0.0))
	return out


## 把单位维护费并进本期收支（end_cycle 段 3.5 调用，之后段 4 会统一结算）
static func _units_upkeep_into(state: Dictionary, _income: Dictionary, upkeep: Dictionary) -> void:
	var tot := units_upkeep_total(state)
	upkeep["food"] = float(upkeep.get("food", 0.0)) + float(tot["food"])
	upkeep["currency"] = float(upkeep.get("currency", 0.0)) + float(tot["currency"])


## 客人：超过 15 个周期后，每周期按累计概率离去
static func guest_leave_tick(state: Dictionary, rng: RandomNumberGenerator, report: Dictionary) -> void:
	var cyc := int(state["cycle"])
	var leaving: Array = []
	for u in guest_units(state):
		var age := cyc - int(u.get("acquired_cycle", cyc))
		if age < Consts.GUEST_LEAVE_FROM_CYCLE:
			continue
		var p := float(u.get("leave_chance", 0.0)) \
			+ rng.randf_range(Consts.GUEST_LEAVE_STEP_MIN, Consts.GUEST_LEAVE_STEP_MAX)
		u["leave_chance"] = p
		if rng.randf() < p:
			leaving.append(u)
	for u in leaving:
		GameState.add_log("%s 等得太久，离开了（未招募的客人会自行离去）。" % str(u["name"]), "unit")
		(state["units"] as Array).erase(u)
	if not leaving.is_empty():
		report["events"].append("%d 位客人等不到招募，离开了。" % leaving.size())


## 每周期重置移动力
static func reset_unit_moves(state: Dictionary) -> void:
	for u in state["units"]:
		u["move_left"] = max_move(state, u)


## 征兵：把空闲人力转成募集军（对应文档「军事建筑 - 经典训练场地」的思路，
## 但募集军是「刚招募、经验为负修正」的那一类，见 v1.1 第 25 条）
## 征兵的花费（唯一来源：检查与支付都用它）
const RECRUIT_COST := {"food": 20.0, "currency": 60.0}


## 征兵是否可行 —— **只检查，不花钱、不落单位**。
## v1.8.3：把这套检查抽出来，好让"直接征兵"与"政事：征兵"两条路**共用同一份判定**
## （两处各写一遍的话，迟早一边改了另一边没改）。返回 "" 表示可以。
static func recruit_blocked_reason(state: Dictionary, profession: String) -> String:
	if Derived.free_pop(GameState.state) <= 0:
		return "没有空闲人力"
	if not UnitDB.PROFESSIONS.has(profession):
		return "未知职业"
	# 需要一座训练场地
	var has_ground := false
	for t in TileManager.owned_tiles(state):
		for b in t.get("buildings", []):
			if str(b.get("id", "")) == "classic_training_ground":
				has_ground = true
	if not has_ground:
		return "需要先建造「经典训练场地」"
	if not Res.can_afford(GameState.state, RECRUIT_COST):
		return "资源不足（%s）" % Res.cost_text(RECRUIT_COST)
	# v1.5：公民必须存在于大世界 —— 直接派驻首都；首都满员则拒绝
	if units_on_tile(state, str(state.get("capital", ""))).size() >= UnitDB.UNITS_PER_TILE:
		return "首都已驻满 %d 个单位，先空出位置再征兵" % UnitDB.UNITS_PER_TILE
	return ""


static func recruit_soldier(state: Dictionary, profession: String) -> Dictionary:
	var why := recruit_blocked_reason(state, profession)
	if why != "":
		return {"ok": false, "why": why}
	Res.pay(GameState.state, RECRUIT_COST)
	# v1.5：公民必须存在于大世界 —— 直接派驻首都
	var cap_key := str(state.get("capital", ""))
	var nm := "%s·募集兵" % UnitDB.profession_name(profession)
	var u := UnitDB.make_soldier("recruit", profession, UnitDB.RECRUIT, nm, 1)
	u["tile"] = cap_key
	u["acquired_cycle"] = int(state["cycle"])
	u["move_left"] = max_move(state, u)
	(state["units"] as Array).append(u)
	GameState.add_log("招募了 %s（进驻首都）。" % nm, "unit")
	GameState.state_changed.emit()
	return {"ok": true, "why": "", "unit": u}
