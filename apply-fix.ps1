<#
.SYNOPSIS
    永久关闭雷电模拟器（LDPlayer 14）"关掉 14 天后又弹"的电脑桌面通知 / 桌面广告弹窗。

.DESCRIPTION
    原理：广告模块 ld5567.exe（≡ ldplayerpartner.exe，由服务 LDPlayerSvr 每 30 分钟拉起）
    在 %APPDATA%\leidian14\partner.data 中记录每条广告的上次展示日期，格式为
        _<广告ID>_time<yyyymmdd>_
    程序判断"同一广告距上次展示 >= 14 天 -> 再弹一次"，这就是 14 天周期的来源。
    本脚本把记录日期改到很远的未来（默认 20991231），等于永久处于"刚展示过"状态；
    再加只读属性 + 拒绝写入的 ACL，防止程序把它覆写回真实日期。

    关键设计：ACL 只拒"写"（WD,AD,WEA,WA），不拒"读"。
    若程序读不到文件，会当成空记录判定"从未展示"，反而立刻弹一次。

.PARAMETER DataDir
    雷电数据目录。默认自动探测 %APPDATA%\leidian14（兼容 leidian13/12/9）。

.PARAMETER FutureDate
    写入的日期，格式 yyyyMMdd，默认 20991231。

.PARAMETER DryRun
    只演示流程，不修改任何文件。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\apply-fix.ps1

.EXAMPLE
    .\apply-fix.ps1 -DataDir "D:\LDPlayer\data\leidian14" -DryRun

.NOTES
    可完全回滚：restore.ps1
    只修改本地数据文件与其 ACL，不触碰雷电任何可执行文件、签名与注册表。
#>
[CmdletBinding()]
param(
    [string]$DataDir,
    [string]$FutureDate = '20991231',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$enc = New-Object System.Text.UnicodeEncoding($false, $false)   # UTF-16LE，无 BOM（与原文件一致）
$me  = "$env:USERDOMAIN\$env:USERNAME"

function Resolve-LDDataDir {
    param([string]$Explicit)
    if ($Explicit) {
        if (-not (Test-Path $Explicit)) { throw "指定的数据目录不存在: $Explicit" }
        return (Resolve-Path $Explicit).Path
    }
    # 优先选真正含 partner.data 的目录
    foreach ($n in @('leidian14','leidian13','leidian12','leidian9','leidian')) {
        $p = Join-Path $env:APPDATA $n
        if (Test-Path (Join-Path $p 'partner.data')) { return $p }
    }
    foreach ($n in @('leidian14','leidian9','leidian')) {
        $p = Join-Path $env:APPDATA $n
        if (Test-Path $p) { return $p }
    }
    throw "未找到雷电数据目录。请用 -DataDir 指定，例如：-DataDir `"$env:APPDATA\leidian14`""
}

$dir = Resolve-LDDataDir -Explicit $DataDir
Write-Host "数据目录: $dir" -ForegroundColor Cyan
if ($DryRun) { Write-Host "模式: DryRun（不会修改任何文件）" -ForegroundColor Yellow }

$items = @(
    @{ File = 'partner.data';         Text = "_456_time${FutureDate}_" },
    @{ File = 'partner_report2.data'; Text = "_time${FutureDate}" }
)

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$done  = @()

foreach ($it in $items) {
    $p = Join-Path $dir $it.File
    if (-not (Test-Path $p)) {
        Write-Host ("SKIP  {0,-22} 不存在" -f $it.File) -ForegroundColor DarkGray
        continue
    }

    if ($DryRun) {
        Write-Host ("DRYRUN {0,-22} 将写入 '{1}'" -f $it.File, $it.Text) -ForegroundColor Yellow
        $done += $it.File
        continue
    }

    # 1) 备份原始字节
    $bak = "$p.bak_$stamp"
    Copy-Item $p $bak -Force

    # 2) 解除旧保护（幂等：重复运行也能跑通）
    icacls $p /reset | Out-Null
    attrib -R $p 2>$null | Out-Null

    # 3) 写入未来日期
    [System.IO.File]::WriteAllBytes($p, $enc.GetBytes($it.Text))
    $back = [System.IO.File]::ReadAllText($p, $enc)
    if ($back -ne $it.Text) { throw "写入校验失败: $p" }

    # 4) 只读 + 拒绝写入（不含读权限）
    attrib +R $p | Out-Null
    icacls $p /deny "${me}:(WD,AD,WEA,WA)"     | Out-Null
    icacls $p /deny "SYSTEM:(WD,AD,WEA,WA)"    | Out-Null

    # 5) 保护后仍应可读
    try { $null = [System.IO.File]::ReadAllText($p, $enc) }
    catch { throw "保护设置过严，程序将读不到记录: $p" }

    Write-Host ("OK    {0,-22} -> '{1}'   备份: {2}" -f $it.File, $it.Text, (Split-Path $bak -Leaf)) -ForegroundColor Green
    $done += $it.File
}

if (-not $done.Count) { throw "没有任何记录文件被处理，路径可能不对: $dir" }

if (-not $DryRun) {
    # 6) 覆写测试：必须失败，否则说明保护没生效
    $tp = Join-Path $dir 'partner.data'
    try {
        [System.IO.File]::WriteAllText($tp, 'x', $enc)
        Write-Host "警告: partner.data 仍可写入，保护未生效" -ForegroundColor Red
    } catch {
        Write-Host "覆写测试: 已拒绝（保护生效）" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "完成。下一步：" -ForegroundColor Cyan
Write-Host "  1) 正常启动一次雷电模拟器，随意用一会儿"
Write-Host "  2) 运行 check-record.ps1 复查：修改时间不变、内容仍为 ${FutureDate} => 生效"
Write-Host "  3) 如需撤销：restore.ps1"
