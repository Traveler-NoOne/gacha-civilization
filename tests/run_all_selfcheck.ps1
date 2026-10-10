# 抽卡文明 · 全套自检运行器
#
# 【谁用】你（人）用。双击项目根目录的「跑自检.bat」就会跑这个文件，不用手敲任何命令。
# 【什么时候用】每次改完代码就双击一次。看到"全绿"才继续；有红的就截图发我。
# 【它做什么】把 tests/ 下的自检各跑一遍（无窗口后台跑），逐项报通过/失败。项数按下面的列表算，加测试不用改这里。
# 【为什么要跑】自检是唯一能告诉你"我刚才改的东西有没有搞坏别处"的东西。
#              项目里有个约定：任何改动都必须保持全绿（现在是 15 项）。

# ↓↓↓ 如果哪天 Godot 换了安装位置，只改下面这一行 ↓↓↓
$godot = 'C:\Program Files\Godot_v4.4.1-stable_mono_win64\Godot_v4.7.2-stable_win64_console.exe'

# 每项最多等 90 秒；超时就杀掉，报"超时"，不会把窗口挂死。
$timeoutMs = 90000

$proj = Split-Path -Parent $PSScriptRoot

$tests = @(
    ,@('selfcheck',          '基础自检：术语 / 数值 / 引用完整性')
    ,@('diag_units',         '单位与术语一致性（43 条）')
    ,@('diag_v12',           'v1.2 专项（含存档版本校验）')
    ,@('diag_v131',          'v1.3.1 专项')
    ,@('diag_v14',           'v1.4 专项')
    ,@('diag_v141',          'v1.4.1 专项（资源收支悬浮窗）')
    ,@('diag_v15',           'v1.5 专项（客人 / 公民 / 维护费）')
    ,@('diag_v16',           'v1.6 专项（招募全流程）')
    ,@('diag_v17',           'v1.7 护栏（收支同源 / 高亮即可达 / 无死常量）')
    ,@('diag_cheat_mouse',   '作弊菜单端到端')
    ,@('diag_cheat_persist', '作弊设置持久化')
    ,@('diag_v18',           'v1.8.3 政事系统（数据 / 队列 / 征兵 / 存档往返）')
    ,@('diag_v19',           'v1.8.9 加载界面（保底时长 / 进度条 / finished）')
    ,@('diag_v110',          'v1.8.10 死入口走查（主菜单->加载->世界->各浮窗->右键->修建）')
    ,@('autoplay',           '自动试跑一遍（周期循环）')
)

Write-Host ""
Write-Host "==========================================================" -ForegroundColor DarkCyan
Write-Host ("  抽卡文明 · 全套自检（" + $tests.Count + " 项）") -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor DarkCyan
Write-Host "  项目：$proj"
Write-Host ""

if (-not (Test-Path -LiteralPath $godot)) {
    Write-Host "  [错误] 找不到 Godot 程序：" -ForegroundColor Red
    Write-Host "        $godot" -ForegroundColor Red
    Write-Host "        如果 Godot 换位置了，用记事本打开本文件，改第 10 行。" -ForegroundColor Yellow
    Read-Host "  按回车关闭"
    exit 1
}

# 游戏开着的时候跑自检，偶发会超时；提醒一句（不强杀你的游戏）
$running = @(Get-Process -Name 'Godot*' -ErrorAction SilentlyContinue |
             Where-Object { $_.MainWindowHandle -ne 0 })
if ($running.Count -gt 0) {
    Write-Host "  [提示] 检测到游戏正开着（还有窗口）。建议先关掉它，否则个别项可能超时。" -ForegroundColor Yellow
    Write-Host ""
}

# 15 项自检：内部名 -> 中文说明（顺序与之前的固定跑法一致）

$pass = 0
$failed = @()
$tmp = Join-Path $env:TEMP ("cmdc_selfcheck")
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

$i = 0
foreach ($t in $tests) {
    $i++
    $name = $t[0]
    $label = $t[1]
    Write-Host ("  [{0,2}/{1}] {2}" -f $i, $tests.Count, $label) -NoNewline

    $out = Join-Path $tmp "$name.log"
    $err = Join-Path $tmp "$name.err"
    Remove-Item $out, $err -ErrorAction SilentlyContinue

    $p = Start-Process -FilePath $godot `
        -ArgumentList '--headless', '--path', $proj, "res://tests/$name.tscn" `
        -RedirectStandardOutput $out -RedirectStandardError $err -PassThru

    if (-not $p.WaitForExit($timeoutMs)) {
        try { $p.Kill() } catch {}
        Write-Host "   ... 超时" -ForegroundColor Yellow
        $failed += ("{0}（超时）" -f $name)
        continue
    }

    if ($p.ExitCode -eq 0) {
        Write-Host "   ... 通过" -ForegroundColor Green
        $pass++
    } else {
        Write-Host "   ... 失败（退出码 $($p.ExitCode)）" -ForegroundColor Red
        $failed += $name
        # 把最后几行输出贴出来，方便截图给我看
        $tail = Get-Content $out -Tail 6 -ErrorAction SilentlyContinue
        if ($tail) {
            Write-Host "        ---- 它说的最后几句 ----" -ForegroundColor DarkGray
            foreach ($line in $tail) { Write-Host "        $line" -ForegroundColor DarkGray }
        }
        $serr = Get-Content $err -ErrorAction SilentlyContinue |
                Select-String -Pattern 'SCRIPT ERROR|Parse Error' | Select-Object -First 3
        if ($serr) {
            Write-Host "        ---- 报错 ----" -ForegroundColor DarkYellow
            foreach ($line in $serr) { Write-Host "        $($line.Line.Trim())" -ForegroundColor DarkYellow }
        }
    }
}

Write-Host ""
Write-Host "==========================================================" -ForegroundColor DarkCyan
if ($failed.Count -eq 0) {
    Write-Host ("  全绿：{0} / {1} 通过 —— 可以放心继续下一步" -f $pass, $tests.Count) -ForegroundColor Green
} else {
    Write-Host ("  通过 {0} / {1}" -f $pass, $tests.Count) -ForegroundColor Yellow
    Write-Host "  有问题的是：" -ForegroundColor Red
    foreach ($f in $failed) { Write-Host "    - $f" -ForegroundColor Red }
    Write-Host "  （把上面整段截图发我，我来判断是哪里出问题）" -ForegroundColor Yellow
}
Write-Host "==========================================================" -ForegroundColor DarkCyan
Write-Host ""