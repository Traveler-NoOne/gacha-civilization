class_name StrongholdPanel
extends PanelContainer
## v1.8.4：据点管理窗口（右侧浮窗）
##
## 结构（按钮在窗口边框**之外的上方**）：
##     [信息][政事][人力]  [✕]
##     ┌────────────────────────┐
##     │ 上半段：随上面的按钮切换    │
##     ├────────────────────────┤
##     │ 政事队列（吃行政点数）      │
##     ├────────────────────────┤
##     │ 规划队列（吃生产力）        │
##     └────────────────────────┘
##
## 触发：左键点我方领地块（v1.8.2 那三档里的"领地"档）。
##
## ⚠️ 本段**不删**旧的右侧规划面板 —— 修建建筑的入口还在那儿，要到 v1.8.5 才搬走。
##    所以过渡期右侧会同时有"旧面板"和"本窗口"：本窗口是浮层，会盖在旧面板上。

const TABS := [
	{"id": "info", "name": "信息"},
	{"id": "decree", "name": "政事"},
	{"id": "labor", "name": "人力"},
]

var tab := "info"
## v1.8.20.4：面板认的是"被点的那一格"，由调用方设进来
var key := ""

var tab_bar: HBoxContainer
var content_box: VBoxContainer
var decree_box: VBoxContainer
var build_box: VBoxContainer


func _init() -> void:
	custom_minimum_size = Vector2(UI.px(340), UI.px(0))
	# ⚠️ 底色必须**完全不透明**。用 0.97 的话，底下旧右侧面板的文字会透上来，
	# 看起来像"内容很暗/有鬼影"（实测踩过）。
	UIKit.apply_panel(self, Color(0.07, 0.07, 0.11, 1.0), UIKit.GOLD, 6)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UI.fs(0))
	add_child(col)

	# ---- 按钮行：在窗口边框之外的上方 ----
	tab_bar = HBoxContainer.new()
	tab_bar.add_theme_constant_override("separation", UI.fs(4))
	col.add_child(tab_bar)
	for t in TABS:
		var tid: String = t["id"]
		var b := UIKit.small(str(t["name"]), 12)
		b.custom_minimum_size = Vector2(UI.px(72), UI.px(26))
		b.pressed.connect(func() -> void:
			tab = tid
			refresh())
		tab_bar.add_child(b)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_bar.add_child(spacer)
	var close := UIKit.tiny("✕", 13, true)
	close.tooltip_text = "关闭（左键点地图空白处也会关）"
	close.pressed.connect(func() -> void: visible = false)
	tab_bar.add_child(close)

	# ---- 上半段：随按钮切换 ----
	content_box = VBoxContainer.new()
	content_box.add_theme_constant_override("separation", UI.fs(4))
	# 上半段放进滚动容器并吃掉剩余高度 —— 下半段两个队列才能稳定贴在窗口底部
	var upper_scroll := UIKit.scroll(content_box)
	upper_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(upper_scroll)

	# ---- 下半段：两个队列，各自跑条 ----
	decree_box = VBoxContainer.new()
	decree_box.add_theme_constant_override("separation", UI.fs(3))
	col.add_child(_queue_section("政事队列（行政点数）", decree_box))

	build_box = VBoxContainer.new()
	build_box.add_theme_constant_override("separation", UI.fs(3))
	col.add_child(_queue_section("规划队列（生产力）", build_box))


func _queue_section(title: String, box: VBoxContainer) -> Control:
	var p := PanelContainer.new()
	UIKit.apply_panel(p, UIKit.BG_PANEL_2, UIKit.LINE_SOFT, 5)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", UI.fs(3))
	p.add_child(v)
	v.add_child(UIKit.text_label(title, 12, UIKit.GOLD))
	v.add_child(box)
	return p


## 每次状态变化 / 切页签都重建内容（内容量小，重建最省心，也不会残留旧状态）
func refresh() -> void:
	if not is_instance_valid(content_box):
		return
	for c in content_box.get_children():
		c.queue_free()
	for c in decree_box.get_children():
		c.queue_free()
	for c in build_box.get_children():
		c.queue_free()
	_refresh_tabs()
	# v1.8.20.4：按"被点的那一格"找据点（认格子）；没给格子时退回旧的"默认据点"
	var sh := GameState.stronghold_by_id(GameState.stronghold_of(GameState.tile_at(key)))
	if sh.is_empty():
		sh = GameState.current_stronghold()
	if sh.is_empty():

		content_box.add_child(UIKit.dim("（没有据点）"))
		return
	match tab:
		"info":
			_refresh_info(sh)
		"decree":
			_refresh_decrees(sh)
		"labor":
			build_labor_rows(content_box, func() -> void: refresh())
		_:
			_refresh_info(sh)
	_refresh_decree_queue(sh)
	_refresh_build_queue(sh)


func _refresh_tabs() -> void:
	for i in tab_bar.get_child_count():
		var c := tab_bar.get_child(i)
		if not (c is Button):
			continue
		# 末尾的 ✕ 不在 TABS 里
		if i >= TABS.size():
			break
		var active: bool = str(TABS[i]["id"]) == tab
		UIKit.style_button(c as Button, active)
		(c as Button).add_theme_color_override("font_color",
			UIKit.GOLD if active else UIKit.TEXT)


# ---------------------------------------------------------------------------
# 上半段三页
# ---------------------------------------------------------------------------
## 信息：**只显示** 掌控力 / 已用土地 / 据点明细（地块明细归 v1.8.2 的简约信息小窗）
func _refresh_info(sh: Dictionary) -> void:
	var tiles := GameState.stronghold_tiles(str(sh.get("id", "")))
	var land_cap := 0.0
	var land_used := 0.0
	for t in tiles:
		land_cap += GameState.land_cap(t)
		land_used += GameState.land_used(t)
	content_box.add_child(_kv("据点", str(sh.get("name", "")), UIKit.GOLD))
	content_box.add_child(_kv("掌控力", "%.0f%%" % (GameState.control_of(sh) * 100.0), UIKit.TEXT))
	content_box.add_child(_kv("已用土地", "%.1f / %.1f" % [land_used, land_cap], UIKit.TEXT))
	content_box.add_child(UIKit.spacer(2))
	content_box.add_child(UIKit.dim("据点明细：", 11))
	if tiles.is_empty():
		content_box.add_child(UIKit.dim("（暂无领地）", 11))
	for t in tiles:
		var key := GameState.tile_key(t)
		var nm := str(t.get("name", ""))
		if nm == "":
			nm = key
		var bcount := (t.get("buildings", []) as Array).size()
		var l := UIKit.dim("· %s [%s]　土地 %.1f/%.1f　建筑 %d" % [
			nm, key, GameState.land_used(t), GameState.land_cap(t), bcount], 10)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content_box.add_child(l)


## 政事：列出政事表里每一条，能排的给按钮，不能排的显示原因
func _refresh_decrees(sh: Dictionary) -> void:
	content_box.add_child(UIKit.dim("每周期把行政点数积累进去，攒够就执行。", 10))
	for d in DecreeDB.all():
		var id := str(d["id"])
		var row := PanelContainer.new()
		var why := GameState.decree_blocked_reason(id)
		UIKit.apply_panel(row, UIKit.BG_PANEL_2, UIKit.LINE if why == "" else UIKit.LINE_SOFT, 4)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", UI.fs(2))
		row.add_child(v)
		v.add_child(UIKit.text_label("%s（行政点数 %.0f）" % [str(d["name"]), float(d["cost"])], 12, UIKit.TEXT))
		var dd := UIKit.dim(str(d.get("desc", "")), 10)
		dd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(dd)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", UI.fs(6))
		v.add_child(h)
		var b := UIKit.small("排入队列", 11)
		if why != "":
			b.disabled = true
			b.tooltip_text = why
			h.add_child(b)
			h.add_child(UIKit.dim(why, 10))
		else:
			b.pressed.connect(func() -> void:
				var r: Dictionary = GameState.enqueue_decree(id)
				if not r["ok"]:
					GameState.toast.emit(str(r["why"]))
				refresh())
			h.add_child(b)
		var hh := UIKit.dim(str(d.get("hint", "")), 9)
		hh.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(hh)
		# ⚠️ 别忘了挂上去：节点内容建好 ≠ 已经显示（漏这行的话，界面上什么都没有，极难发现）
		content_box.add_child(row)
	content_box.add_child(UIKit.spacer(2))


## 政事队列：队首 + 进度条（吃行政点数）
func _refresh_decree_queue(sh: Dictionary) -> void:
	var q: Array = sh.get("decrees", []) # 获取政事队列
	if q.is_empty(): # 如果政事队列为空
		decree_box.add_child(UIKit.dim("队列为空。到上面的「政事」页排一条。", 10))
		return
	for i in q.size():
		var item: Dictionary = q[i]
		var cost := maxf(0.0001, float(item.get("cost", 0.0)))
		var paid := float(item.get("paid", 0.0))
		var head := "▶ " if i == 0 else "· "
		decree_box.add_child(UIKit.text_label("%s%s　%.0f / %.0f" % [
			head, DecreeDB.display_name(str(item.get("id", ""))), paid, cost], 11,
			UIKit.GOLD if i == 0 else UIKit.TEXT_DIM))
		decree_box.add_child(UIKit.bar(paid, cost, UIKit.GOLD if i == 0 else UIKit.LINE, 280.0, 8.0))


## 规划队列：队首 + 进度条（吃生产力）
func _refresh_build_queue(sh: Dictionary) -> void:
	var q: Array = sh.get("queue", [])
	if q.is_empty():
		# 1.8.21.2：这行原来写「到「世界 → 地块规划页」…」，但那个页面 v1.8.5 就删了 —— 玩家照它找不到入口。
		# 顺带开自动换行：文案长，原来会被窗口右边缘直接切掉（bug#1 / bug#11）。
		var empty_tip := UIKit.dim("队列为空。右键地块 → 🔨 选择建筑修建。", 10)
		empty_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		build_box.add_child(empty_tip)
		return
	for i in q.size():
		var item: Dictionary = q[i]
		var need := maxf(0.0001, float(item.get("need_prod", 0.0)))
		var paid := float(item.get("paid_prod", 0.0))
		var def := GameState.find_building(str(item.get("bid", "")))
		var nm := def.display_name if def != null else str(item.get("bid", "?"))
		var head := "▶ " if i == 0 else "· "
		build_box.add_child(UIKit.text_label("%s%s　%.0f / %.0f" % [head, nm, paid, need], 11,
			UIKit.GOLD if i == 0 else UIKit.TEXT_DIM))
		build_box.add_child(UIKit.bar(paid, need, UIKit.GOLD if i == 0 else UIKit.LINE, 280.0, 8.0))


func _kv(k: String, v: String, col: Color) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", UI.fs(6))
	h.add_child(UIKit.dim(k, 11))
	var l := UIKit.text_label(v, 12, col)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	return h


# ---------------------------------------------------------------------------
# 共用的"人力管理"行构造
# ---------------------------------------------------------------------------
## 人力管理行（**管理页与本窗口共用这一份**，避免两处口径）。
## 注意 v1.7.2 的规矩：**不需要人力的建筑不进列表**（判定问的是建筑数据本身）。
static func build_labor_rows(parent: VBoxContainer, on_changed: Callable) -> void:
	for c in parent.get_children():
		c.queue_free()
	var sh := GameState.current_stronghold()
	if sh.is_empty():
		parent.add_child(UIKit.dim("（没有据点）"))
		return
	var any := false
	for t in GameState.stronghold_tiles(str(sh.get("id", ""))):
		var key := GameState.tile_key(t)
		for b in t.get("buildings", []):
			var def := GameState.find_building(str(b.get("id", "")))
			if def == null:
				continue
			var level := int(b.get("level", 1))
			var maxw := def.max_workers(level)
			if maxw <= 0:
				continue
			any = true
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", UI.fs(4))
			parent.add_child(row)
			var l := UIKit.text_label("%s Lv.%d（%s）" % [def.display_name, level, key], 11, UIKit.TEXT)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			row.add_child(l)
			var bid := str(b.get("bid", ""))
			var minus := UIKit.tiny("−", 12)
			minus.pressed.connect(func() -> void:
				GameState.assign_worker_by_bid(key, bid, -1)
				on_changed.call())
			var num := UIKit.text_label("%d/%d" % [int(b.get("workers", 0)), maxw], 11, UIKit.TEXT)
			var plus := UIKit.tiny("＋", 12)
			plus.pressed.connect(func() -> void:
				var r2: Dictionary = GameState.assign_worker_by_bid(key, bid, 1)
				if not r2["ok"]:
					GameState.toast.emit(str(r2["why"]))
				on_changed.call())
			row.add_child(minus)
			row.add_child(num)
			row.add_child(plus)
	if not any:
		parent.add_child(UIKit.dim("还没有已修建、且需要人力的建筑。"))
