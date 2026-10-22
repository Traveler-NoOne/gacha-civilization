class_name Palette
extends RefCounted
## UI 调色板的**代码入口** ✓
##
## ⚠️ 数值存在 `scripts/ui/ui_palette.tres`（Inspector 里直接调），这里只是把它读出来 ✓
## 用法：`Palette.GOLD` / `Palette.TEXT_DIM` ……
##
## 为什么做成 static var 而不是 const：调用点就能保持 `Palette.GOLD` 这种写法不变；
## 它们在脚本第一次加载时从资源读一次 ✓（改 .tres 后重开游戏即生效）

const DATA: UIPalette = preload("res://scripts/ui/ui_palette.tres")

static var BG_DARK: Color = DATA.BG_DARK
static var BG_PANEL: Color = DATA.BG_PANEL
static var BG_PANEL_2: Color = DATA.BG_PANEL_2
static var BG_SLOT: Color = DATA.BG_SLOT
static var LINE: Color = DATA.LINE
static var LINE_SOFT: Color = DATA.LINE_SOFT
static var GOLD: Color = DATA.GOLD
static var TEXT: Color = DATA.TEXT
static var TEXT_DIM: Color = DATA.TEXT_DIM
static var TEXT_FAINT: Color = DATA.TEXT_FAINT
static var OK: Color = DATA.OK
static var WARN: Color = DATA.WARN
static var BAD: Color = DATA.BAD
