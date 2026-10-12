class_name Fatal
extends RefCounted
## 致命错误：**报一个错误码、说明它是什么、然后结束进程**。
##
## 为什么不「就着错误继续跑」：触发点意味着后续本来也走不下去，硬跑只会把问题藏起来、
## 还可能引发别的错；而玩家重启会重新走 new_game() / 读档，反而可能自愈。
##
## 码表放在**代码里**（CODES）是刻意的：报错时能自动带上「这句是什么意思」，
## 不用人去翻文档。`docs/错误代码.md` 是给人和玩家看的镜像 ——
## 两边必须同步，有 `tests/fatal_check.tscn` 看着（加码忘写文档、或写错码都会红）。
##
## 用法：
##     Fatal.fatal("E-MAP-001")        # 报码 + 结束进程
## 自检里先 `Fatal.suppress_quit = true`，免得把测试进程真的杀掉。

const CODES := {
	"E-MAP-001": "地图没有地块数据（state.tiles 缺失或为空）：世界生成没跑成，画面会是空白一片。",
}

## 最近一次致命错误的码（自检用）
static var last_code := ""
## 累计触发次数（自检用）
static var count := 0
## 自检把它设 true：只记录不退出
static var suppress_quit := false


## 报一个致命错误：打错误码 + 含义，然后结束进程（退出码 1 = 异常）。
static func fatal(code: String) -> void:
	last_code = code
	count += 1
	var meaning := str(CODES.get(code, "（未登记的错误码！请补进 Fatal.CODES 与 docs/错误代码.md）"))
	push_error("[致命 %s] %s" % [code, meaning])
	if suppress_quit:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.quit(1)      # deferred 生效：当前这一帧还能正常画完
