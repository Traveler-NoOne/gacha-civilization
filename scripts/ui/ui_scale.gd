extends Node
## UI 尺寸词典（Autoload 名：UI）。
##
## 为什么要有它：以前整个 UI 写死在 1280×720 上，靠 Godot 的 `canvas_items` 拉伸适配窗口 ——
## 于是「分辨率设置」只是个整体缩放，玩家看不出区别（1080p 上跟自己最大化窗口一样），
## 而且它还不持久化。实装分辨率 = **让 UI 按真实像素排版**，所有尺寸都从这里取、按档位换算。
##
## ⚠️ 和 `UIKit` **不是一回事**：`UIKit` 是静态控件工厂（造按钮 / 面板 / 弹窗），
##    `UI`（本文件）只负责「多大」。命名接近，所以在文件头写清楚。
##
## 用法（1.8.20-B 起全项目逐步改成这样）：
##     custom_minimum_size = Vector2(UI.px(130), UI.px(34))
##     label.add_theme_font_size_override("font_size", UI.fs(13))
##
## 加分辨率：只改下面 SCALES 一处 —— 设置弹窗的选项、窗口尺寸、换算倍率全都从这里来。

## 设计基准：所有 UI 尺寸都是"按 1280×720 量的"
const BASE_KEY := "1280x720"

## 分辨率 key → 倍率。**唯一来源**。
const SCALES := {
	"1280x720": 1.0,
	"1600x900": 1.25,
	"1920x1080": 1.5,
}

## 项目主题（唯一来源）。启动时按倍率复制一份、缩放字号后挂到 root ✓
const THEME_PATH := "res://scripts/ui/ui_theme.tres"

var _key := BASE_KEY
var _theme_base: Theme = null


# ---------------------------------------------------------------------------
# 档位
# ---------------------------------------------------------------------------
## 全部可选分辨率（按字典顺序）
func resolutions() -> Array:
	return SCALES.keys()


## 有没有这一档
func has_key(key: String) -> bool:
	return SCALES.has(key)


## 切成某一档；未知的值回落到基准，避免手改 settings.cfg 把游戏弄成奇怪尺寸
func set_resolution_key(key: String) -> void:
	_key = key if SCALES.has(key) else BASE_KEY
	_apply_theme()


## 把项目主题按当前倍率**复制 + 缩放字号**，挂到 root。
##
## 为什么不用 `gui/theme/custom` 直接用：那套字号是写死的设计值（1280×720 基准），
## 1080p / 2K 下用同一份就会偏小 —— 而主题里的 StyleBox 又不能"按倍率算"。
## 所以：**主题仍然是唯一来源**，只是运行时复制一份把字号乘上倍率 ✓
## 只缩放字号；边框 / 圆角 / 内边距保持设计值（3px 细边放大后依然好看）。
func _apply_theme() -> void:
	if _theme_base == null:
		_theme_base = load(THEME_PATH) as Theme
	if _theme_base == null:
		return
	var s := current_scale()
	var t: Theme = _theme_base.duplicate(true) as Theme
	t.default_font_size = int(round(float(_theme_base.default_font_size) * s))
	for type in _theme_base.get_type_list():
		for item in _theme_base.get_font_size_list(type):
			t.set_font_size(item, type, int(round(float(_theme_base.get_font_size(item, type)) * s)))
	get_tree().root.theme = t


func current_key() -> String:
	return _key


func current_size() -> Vector2i:
	return key_to_size(_key)


func current_scale() -> float:
	return float(SCALES.get(_key, 1.0))


# ---------------------------------------------------------------------------
# 换算
# ---------------------------------------------------------------------------
## 像素值换算：把"按 1280×720 设计"的值换到当前档
func px(v: float) -> float:
	return v * current_scale()


## 字号换算（取整 —— 半像素的字会发虚）
func fs(v: int) -> int:
	return int(round(float(v) * current_scale()))


# ---------------------------------------------------------------------------
# key <-> 尺寸 <-> 显示文字
# ---------------------------------------------------------------------------
func key_to_size(key: String) -> Vector2i:
	var parts := key.split("x")
	if parts.size() != 2:
		return key_to_size(BASE_KEY)
	return Vector2i(int(parts[0]), int(parts[1]))


func key_of(size: Vector2i) -> String:
	return "%dx%d" % [size.x, size.y]


## 给人看的写法："1280 × 720"
func label_of(key: String) -> String:
	var parts := key.split("x")
	if parts.size() != 2:
		return key
	return "%s × %s" % [parts[0], parts[1]]
