class_name Fatal
extends RefCounted
## 致命错误：报码 + 说明 + 结束进程（fail-fast：就着错误跑只会把问题藏起来，重启反而可能自愈）。
## CODES 是码与含义的唯一来源（报错自动带含义）；docs/错误代码.md 是镜像，有自检保证两边同步。
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
