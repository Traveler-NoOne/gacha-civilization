class_name UIKit
extends RefCounted
## ui_kit.gd —— 全局 UI 工具箱（静态类，整个项目共用的一套「皮肤 + 零件」）。
##
## 它本身不是某个界面，而是所有界面都来这儿取东西的地方：
##   1. 配色常量：背景 / 面板 / 描边 / 文字 / 金色强调 / 成功·警告·危险，全项目统一
##   2. 样式函数：给面板和按钮套上统一的描边、圆角、内边距
##   3. 控件工厂：一行代码造出统一风格的标题、文字、按钮、面板、布局、滚动条、进度条
##   4. 弹窗：通用弹窗 dialog() 与「确认 / 取消」框 confirm()
##   5. 图片入口：通用取图 get_icon(name, 类型)；单位立绘 unit_art()，找不到图自动回退几何占位
##
## 里面全是 static 函数，用 UIKit.xxx() 调用，不需要也不应该去实例化它。
## 统一 UI 风格与控件工厂。所有界面优先使用几何色块 + 文字，可选加载美术图标，找不到时回退。

# ---------------------------------------------------------------------------
# 配色常量
# ---------------------------------------------------------------------------
## 最底层背景（近黑带紫）
const BG_DARK := Color(0.055, 0.055, 0.08)
## 普通面板背景
const BG_PANEL := Color(0.10, 0.10, 0.145)
## 面板上的第二层背景（比 BG_PANEL 略亮，常用于按钮 / 嵌套块）
const BG_PANEL_2 := Color(0.135, 0.135, 0.19)
## 槽位 / 格子背景（比面板更暗，用于图标格、卡片底）
const BG_SLOT := Color(0.075, 0.075, 0.115)
## 主要描边色
const LINE := Color(0.28, 0.30, 0.40)
## 次要描边色（用于禁用态等弱化场景）
const LINE_SOFT := Color(0.20, 0.21, 0.29)
## 金色强调色（标题、选中、强调按钮）
const GOLD := Color(0.93, 0.80, 0.45)
## 正文文字色
const TEXT := Color(0.90, 0.91, 0.95)
## 弱化文字色（说明 / 次要信息）
const TEXT_DIM := Color(0.62, 0.64, 0.72)
## 最弱的文字色（禁用 / 占位）
const TEXT_FAINT := Color(0.45, 0.47, 0.56)
## 成功 / 正向数值（绿）
const OK := Color(0.45, 0.85, 0.55)
## 警告 / 注意数值（橙）
const WARN := Color(0.95, 0.62, 0.35)
## 危险 / 负向数值（红）
const BAD := Color(0.92, 0.38, 0.40)

## 美术资源根目录
const ART_DIR := "res://art/"

enum Art {UI, ICON}
const ART_DIRS := {
	Art.UI: "ui",
	Art.ICON: "icons",
}

static var _art_caches := {
	Art.UI: {},
	Art.ICON: {},
}

## 通用取图函数：按「美术类型」枚举映射到子目录，读 art/<子目录>/<name>.png。
## 每类美术各有独立缓存（见 _art_caches），方便以后单独重载某一类；缺图时打日志并返回 null。
static func get_icon(name: String, type: Art) -> Texture2D:
	var cache: Dictionary = _art_caches[type]
	if cache.has(name):
		return cache[name]
	var path := ART_DIR + str(ART_DIRS[type]) + "/" + name + ".png"   # 必须走映射表
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	else:
		print("目标文件不存在：", path)
	cache[name] = tex
	return tex

# ---------------------------------------------------------------------------
# 样式盒
# ---------------------------------------------------------------------------
## 注意：在 Godot 4.7 的 GL Compatibility（OpenGL）后端下，
## StyleBoxFlat 的 1 像素边框实际不会被绘制（2px 同样不可靠）。
## 所以这里强制最小边框宽度为 3 像素，保证所有面板/按钮都有可见描边。
const MIN_BORDER_WIDTH := 3


## 生成一个统一的「样式盒」StyleBoxFlat：决定面板 / 按钮的底色、描边、圆角与内边距。
## bg / border / radius 不传时用默认面板配色；width 会被强制不小于 MIN_BORDER_WIDTH。
static func panel_style(bg: Color = BG_PANEL, border: Color = LINE,radius: int = 6, width: int = MIN_BORDER_WIDTH) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(maxi(width, MIN_BORDER_WIDTH))
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


## 把一个已经存在的 PanelContainer / Panel 的背景换成统一面板样式。
## （传进其它类型的控件不会报错，什么也不做。）
## ⚠️ 2026-10-22 起：**默认面板交给主题**（`ui_theme.tres` 里的 `panel` 样式盒），
##    只有调用方明确传了别的颜色/圆角时才在代码里覆盖 ✓
static func apply_panel(p: Control, bg: Color = BG_PANEL, border: Color = LINE,
		radius: int = 6) -> void:
	if bg == BG_PANEL and border == LINE and radius == 6:
		return
	var sb := panel_style(bg, border, radius)
	if p is PanelContainer:
		(p as PanelContainer).add_theme_stylebox_override("panel", sb)
	elif p is Panel:
		(p as Panel).add_theme_stylebox_override("panel", sb)


## 给按钮套上统一外观：按 accent / danger 切换**主题类型变体**。
## 五种状态（normal / hover / pressed / focus / disabled）都在 `ui_theme.tres` 里 ✓
## 两者同时为真时 danger 优先 ✓
static func style_button(b: Button, accent: bool = false, danger: bool = false) -> void:
	# 2026-10-22 起皮肤全在主题里（ui_theme.tres）：
	# 普通按钮 = Button；金色强调 = AccentButton 变体；红色危险 = DangerButton 变体 ✓
	if danger:
		b.theme_type_variation = &"DangerButton"
	elif accent:
		b.theme_type_variation = &"AccentButton"


# ---------------------------------------------------------------------------
# 控件工厂
# ---------------------------------------------------------------------------
## 造一个金色标题文字（Label），size 为字号。
## 等价于 text_label(text, size, GOLD) —— 只差一个默认字号（标题 20 / 正文 13）。
static func title(text: String, size: int = 20) -> Label:
	return text_label(text, size, GOLD)



## 造一个普通文字（Label），可指定字号与颜色。
static func text_label(text: String, size: int = 13, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", UI.fs(size))
	l.add_theme_color_override("font_color", color)
	return l


## 造一个弱化说明文字（灰色小字），等价于 text_label(text, size, TEXT_DIM)。
static func dim(text: String, size: int = 12) -> Label:
	return text_label(text, size, TEXT_DIM)


## 四种按钮的**唯一实现**：造一个套好统一外观的按钮。
## w / h 是最小尺寸（用 1280 基准的数字，内部走 UI.px）；accent / danger 见 style_button。
## 下面四个对外工厂只是它的不同参数写法 —— 以后再加一种（比如"中号"）也只要一行。
static func _button(text: String, size: int, w: float, h: float,
		accent: bool = false, danger: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(UI.px(w), UI.px(h))
	b.add_theme_font_size_override("font_size", UI.fs(size))
	style_button(b, accent, danger)
	return b


## 造一个金色主要按钮（高 40，默认字号 18），用于界面里最显眼的操作。
static func primary(text: String, size: int = 18) -> Button:
	return _button(text, size, 0.0, 40.0, true)


## 造一个普通按钮（高 34，默认字号 14），最常用的按钮类型。
static func normal(text: String, size: int = 14) -> Button:
	return _button(text, size, 0.0, 34.0)


## 造一个小按钮（高 26，默认字号 12），用于次级操作。
static func small(text: String, size: int = 12) -> Button:
	return _button(text, size, 0.0, 26.0)


## 造一个迷你按钮（26×22，默认字号 11），用于列表行内的小操作；danger=true 为红色危险按钮。
static func tiny(text: String, size: int = 11, danger: bool = false) -> Button:
	return _button(text, size, 26.0, 22.0, false, danger)


## 通用「图片按钮」：贴一张 art/ui/<name>.png，抹掉默认方框，可设尺寸与悬停提示。
## 缺图时退回普通按钮外观（看得见、能点），不会变成隐形按钮。
static func image_button(name: String, tooltip_text: String = "", w: int = 48, h: int = 48) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(UI.px(w), UI.px(h))
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tooltip_text
	var tex := get_icon(name, Art.UI)
	if tex != null:
		b.icon = tex
		b.expand_icon = true
		b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		b.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
		b.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	else:
		b.text = name
		style_button(b)
		print("缺失图片:", name)
	return b


## 造一个指定高度的空白撑开块（h 为高度），用于手动加纵向间距。
static func spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, UI.px(h))
	return c


## 把一个控件包进垂直滚动容器后返回（横向滚动禁用，子控件水平/垂直都填满）。
static func scroll(child: Control) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(child)
	return sc


## 造一个统一样式的面板容器（PanelContainer）。
static func panel(bg: Color = BG_PANEL, border: Color = LINE, radius: int = 6) -> PanelContainer:
	var p := PanelContainer.new()
	apply_panel(p, bg, border, radius)
	return p


## 造一个纵向布局容器（VBoxContainer），sep 为子项之间的间距。
static func vbox(sep: int = 6) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", UI.fs(sep))
	return v


## 造一个横向布局容器（HBoxContainer），sep 为子项之间的间距。
static func hbox(sep: int = 6) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", UI.fs(sep))
	return h


## 造一个网格布局容器（GridContainer），cols 为列数，hsep_px / vsep_px 为横/纵间距。
static func grid(cols: int, hsep_px: int = 6, vsep_px: int = 6) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", UI.fs(hsep_px))
	g.add_theme_constant_override("v_separation", UI.fs(vsep_px))
	return g


## 造一个进度条（血条 / 经验条 / 产能条等），尺寸默认 120×12。
## maxv 会被夹到至少 0.0001 防止除零；value 会被夹进 0 ~ maxv 之间；不显示百分比文字。
static func bar(value: float, maxv: float, fill: Color, w: float = 120.0, h: float = 12.0) -> ProgressBar:
	var p := ProgressBar.new()
	p.custom_minimum_size = Vector2(UI.px(w), UI.px(h))
	p.max_value = maxf(0.0001, maxv)
	p.value = clampf(value, 0.0, p.max_value)
	p.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.16, 0.16, 0.21)
	bg.set_corner_radius_all(3)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	fg.set_corner_radius_all(3)
	p.add_theme_stylebox_override("background", bg)
	p.add_theme_stylebox_override("fill", fg)
	return p


## 「标签 + 进度条 + 数值」一行，用于经验之类的进度显示
static func progress_bar_row(value: int, cap: int, progress: float, fill: Color) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", UI.fs(6))
	var l := text_label("经验", 11, TEXT_DIM)
	h.add_child(l)
	var b := bar(float(value), float(maxi(1, cap)), fill, 180.0, 12.0)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(b)
	var t := text_label("%d / %d（%.0f%%）" % [value, cap, progress * 100.0], 11, TEXT)
	h.add_child(t)
	return h


# ---------------------------------------------------------------------------
# 勾选框
# ---------------------------------------------------------------------------
## 自绘勾选框。
##
## 为什么不用 Godot 自带的 CheckBox：在 Godot 4.7 + GL Compatibility 后端下，
## CheckBox 的 checked / unchecked 图标实际不会被绘制出来 —— 只有文字可见，
## 玩家根本看不出有没有勾上（这正是「作弊功能无法正常使用」的根因）。
## 这里用 toggle 模式的 Button + 方括号字符自绘，任何渲染后端下都能看见。
static func toggle_checkbox(label_text: String, on: bool = false) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.button_pressed = on
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, UI.px(32))
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", UI.fs(14))
	_apply_checkbox_look(b, on, label_text)
	b.toggled.connect(func(pressed: bool) -> void:
		_apply_checkbox_look(b, pressed, label_text))
	return b


## 刷新自绘勾选框的外观：按 on 切换方括号勾选符号 [ ✔ ] / [    ]、文字颜色与底色。
static func _apply_checkbox_look(b: Button, on: bool, label_text: String) -> void:
	b.text = "%s  %s" % ["[ ✔ ]" if on else "[    ]", label_text]
	b.add_theme_color_override("font_color", GOLD if on else TEXT)
	b.add_theme_color_override("font_hover_color", GOLD)
	b.add_theme_color_override("font_pressed_color", GOLD)
	var base := Color(0.16, 0.15, 0.10) if on else BG_PANEL_2
	var line := GOLD if on else LINE
	b.add_theme_stylebox_override("normal", panel_style(base, line, 5))
	b.add_theme_stylebox_override("hover", panel_style(base.lightened(0.12), GOLD, 5))
	b.add_theme_stylebox_override("pressed", panel_style(base.darkened(0.15), GOLD, 5))
	b.add_theme_stylebox_override("focus", panel_style(Color(0, 0, 0, 0), GOLD, 5))
	b.tooltip_text = "点击切换：%s" % ("已开启" if on else "已关闭")


# ---------------------------------------------------------------------------
# 贴点弹窗的定位（左键简约小窗 / 右键功能菜单 / 以后任何"点哪弹哪"都走这里）
# ---------------------------------------------------------------------------
## 把「贴着某个点弹出来的浮窗」摆到正确位置。
##
## 专治两个坑 —— 左键简约小窗、右键功能菜单各踩过一次，别再各写一套：
##   1) **坐标**：gpos 是鼠标 / 地块的**全局**坐标，所以必须用 global_position 赋值。
##      写成 position（相对父节点）时，父节点原点只要不是 0 就会整体偏掉。
##   2) **尺寸**：容器的最小尺寸要**下一帧**才会按新内容算准。所以这里把这个点记在 p 身上，
##      等 minimum_size_changed 触发时再摆一次；否则弹窗会从旧位置向下长出屏幕。
##
## 摆放：优先点的右下 offset 处，下方放不下翻到上方，最后夹进视口（尺寸收缩到刚好包住内容）。
## 不管显示/隐藏 —— 那是调用方的事。

static func place_popup_at(p: Control, gpos: Vector2, offset: Vector2 = Vector2(10.0, 10.0)) -> void:
	p.set_meta("popup_anchor", gpos)
	p.set_meta("popup_offset", offset)
	if not p.has_meta("popup_wired"):
		p.set_meta("popup_wired", true)
		p.minimum_size_changed.connect(func() -> void: UIKit.place_popup_now(p))
	UIKit.place_popup_now(p)


## 按记下来的点 + **当前**尺寸真的摆一次（place_popup_at 内部用；也可手动调）。
static func place_popup_now(p: Control) -> void:
	if not is_instance_valid(p) or not p.has_meta("popup_anchor"):
		return
	p.size = p.get_combined_minimum_size()
	var anchor: Vector2 = p.get_meta("popup_anchor")
	var offset: Vector2 = p.get_meta("popup_offset")
	var sz := p.size
	var vp := p.get_viewport_rect().size
	
	# 水平：优先放右侧；右边放不下 → 翻到点的左侧
	var x := anchor.x + offset.x
	if x + sz.x > vp.x:
		x = anchor.x - sz.x - offset.x
		
	var y := anchor.y + offset.y
	if y + sz.y > vp.y:                      # 下方放不下 → 翻到点的上方
		y = anchor.y - sz.y - offset.y
	p.global_position = Vector2(
		clampf(x, 0.0, maxf(0.0, vp.x - sz.x)),
		clampf(y, 0.0, maxf(0.0, vp.y - sz.y)))


# ---------------------------------------------------------------------------
# 弹窗
# ---------------------------------------------------------------------------

## 造一个通用弹窗（DialogLayer），只设好标题与宽度；内容之后再调 d.set_content(...) 塞入。
static func dialog(title_text: String, width: float = 480.0) -> DialogLayer:
	var layer := DialogLayer.new()
	layer.dialog_title = title_text
	layer.dialog_width = UI.px(width)
	return layer


## 造一个「确认 / 取消」弹窗：点「确认」会先关窗再执行回调 on_ok，点「取消」只关窗。
static func confirm(title_text: String, message: String, on_ok: Callable) -> DialogLayer:
	var d := dialog(title_text, 420.0)
	var v := vbox(10)
	v.add_child(text_label(message, 14))
	var row := hbox(8)
	row.alignment = BoxContainer.ALIGNMENT_END
	var cancel := small("取消")
	var ok := small("确认", 12)
	style_button(ok, true)
	cancel.pressed.connect(func() -> void: d.close())
	ok.pressed.connect(func() -> void:
		d.close()
		on_ok.call())
	row.add_child(cancel)
	row.add_child(ok)
	v.add_child(row)
	d.set_content(v)
	return d


## 造一个卡池卡片的展示块（稀有度描边 + 几何图标 + 名字 + n★ 标签）。
## 注意：这是纯展示用的静态卡片，本身不可点击；要能点请在外层套按钮。
static func card_button(card: Dictionary, w: float = 104.0, h: float = 128.0) -> Control:
	var holder := PanelContainer.new()
	var rarity := int(card.get("rarity", 1))
	var col: Color = Consts.rarity_color(rarity)
	apply_panel(holder, BG_SLOT, col, 6)
	holder.custom_minimum_size = Vector2(UI.px(w), UI.px(h))
	var v := vbox(2)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	holder.add_child(v)
	var icon := GeoIcon.new()
	icon.kind = str(card.get("kind", "circle"))
	icon.tint = col
	icon.custom_minimum_size = Vector2(UI.px(w - 16), UI.px(h - 56))
	v.add_child(icon)
	var name_l := text_label(str(card.get("name", "?")), 12, col)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(name_l)
	var sub := text_label("%d★ %s" % [rarity, Consts.rarity_name(rarity)], 10, TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	return holder


# ---------------------------------------------------------------------------
# v1.7：从三个视图里提到这里的重复小工具
# ---------------------------------------------------------------------------
## 数值显示：接近整数就显示整数，否则一位小数
static func fmt_num(v: float) -> String:
	if absf(v - roundf(v)) < 0.05:
		return "%d" % int(roundf(v))
	return "%.1f" % v


## 沿父链找到承载弹窗的游戏主页（找不到返回 null）
static func game_screen_of(n: Node) -> Node:
	var c: Node = n
	while c != null:
		if c.has_method("open_dialog"):
			return c
		c = c.get_parent()
	return null


# ---------------------------------------------------------------------------
# v1.7：单位立绘槽
# ---------------------------------------------------------------------------
## 单位图标槽：有立绘就用立绘（等比裁满，不拉伸变形），没有就退回几何占位。
## 角色页大立绘 / 单位操作窗 / 底部单位条三处共用同一个入口，避免各写一套。
static func unit_art(u: Dictionary, slot: String, px: Vector2) -> Control:
	var tex := UnitDB.art_of(u, slot)
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.custom_minimum_size = px * UI.current_scale()
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return tr
	var ic := GeoIcon.new()
	ic.custom_minimum_size = px * UI.current_scale()
	ic.setup(str(u.get("kind", "circle")), Consts.rarity_color(int(u.get("rarity", 1))))
	return ic
