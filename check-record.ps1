<#
.SYNOPSIS
    复查雷电模拟器的通知记录文件是否被程序改写。

.DESCRIPTION
    跑完 apply-fix.ps1 后，正常启动一次雷电模拟器，再运行本脚本。
    若 partner.data / partner_report2.data 的修改时间仍停留在修复时刻、
    内容仍是未来日期，说明程序无法覆写 => 修复成立。

.PARAMETER DataDir
    雷电数据目录，默认自动探测。

.EXAMPLE
    .\check-record.ps1
#>
[CmdletBinding()]
param([string]$DataDir)

$ErrorActionPreference = 'Continue'
$enc = New-Object System.Text.UnicodeEncoding($false, $false)

function Resolve-LDDataDir {
    param([string]$Explicit)
    if ($Explicit) {
        if (-not (Test-Path $Explicit)) { throw "指定的数据目录不存在: $Explicit" }
        return (Resolve-Path $Explicit).Path
    }
    foreach ($n in @('leidian14','leidian13','leidian12','leidian9','leidian')) {
        $p = Join-Path $env:APPDATA $n
        if (Test-Path (Join-Path $p 'partner.data')) { return $p }
    }
    foreach ($n in @('leidian14','leidian9','leidian')) {
        $p = Join-Path $env:APPDATA $n
        if (Test-Path $p) { return $p }
    }
    throw "未找到雷电数据目录，请用 -DataDir 指定"
}

$dir = Resolve-LDDataDir -Explicit $DataDir
Write-Host "数据目录: $dir`n" -ForegroundColor Cyan

$names = @('partner.data','partner_report2.data','partner_report.data')

foreach ($f in $names) {
    $p = Join-Path $dir $f
    if (-not (Test-Path $p)) { continue }
    $i = Get-Item $p

    $content = switch ($f) {
        'partner_report.data' { '<Unix 时间戳文件，不参与 14 天判定>' }
        default {
            try { [System.IO.File]::ReadAllText($p, $enc) } catch { '<不可读！程序会误判为空记录>' }
        }
    }

    $flag = ''
    if ($content -match '20991231')            { $flag = '  << 已修复' }
    if ($content -eq '<不可读！程序会误判为空记录>') { $flag = '  << 异常，请重新运行 apply-fix.ps1' }

    "{0,-22} 内容='{1}'" -f $f, $content
    "{0,-22} 属性={1}  修改时间={2}{3}" -f '', $i.Attributes, $i.LastWriteTime, $flag
    ""
}

Write-Host "判断标准：修改时间停在 apply-fix 的时刻、内容为未来日期 => 程序无法覆写，修复成立。" -ForegroundColor Gray
Write-Host "若修改时间变成刚才、内容退回真实日期 => 记录被重置，请改用 README 的加强方案。" -ForegroundColor Gray
