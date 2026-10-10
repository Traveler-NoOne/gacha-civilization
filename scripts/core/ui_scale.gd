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
	"2560x1440": 2.0,
}

var _key := BASE_KEY


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
