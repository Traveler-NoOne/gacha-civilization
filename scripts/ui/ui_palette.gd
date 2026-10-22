class_name UIPalette
extends Resource
## UI 调色板（资源）✓
##
## ⚠️ **要改颜色请改 `scripts/ui/ui_palette.tres`（在 Inspector 里直接调），不要改这里** ✓
## 这里只声明字段和默认值；代码里一律用 `Palette.XXX` 读 ✓

@export var BG_DARK := Color(0.055, 0.055, 0.08)      ## 最底层背景（近黑带紫）
@export var BG_PANEL := Color(0.10, 0.10, 0.145)      ## 普通面板背景
@export var BG_PANEL_2 := Color(0.135, 0.135, 0.19)   ## 面板上的第二层（按钮 / 嵌套块）
@export var BG_SLOT := Color(0.075, 0.075, 0.115)     ## 槽位 / 图标格背景
@export var LINE := Color(0.28, 0.30, 0.40)           ## 主要描边
@export var LINE_SOFT := Color(0.20, 0.21, 0.29)      ## 次要描边（禁用态等）
@export var GOLD := Color(0.93, 0.80, 0.45)           ## 金色强调（标题 / 悬停 / 强调按钮）
@export var TEXT := Color(0.90, 0.91, 0.95)           ## 正文
@export var TEXT_DIM := Color(0.62, 0.64, 0.72)       ## 弱化文字
@export var TEXT_FAINT := Color(0.45, 0.47, 0.56)     ## 最弱文字（禁用 / 占位）
@export var OK := Color(0.45, 0.85, 0.55)             ## 正向数值
@export var WARN := Color(0.95, 0.62, 0.35)           ## 警告数值
@export var BAD := Color(0.92, 0.38, 0.40)            ## 负向数值 / 危险
