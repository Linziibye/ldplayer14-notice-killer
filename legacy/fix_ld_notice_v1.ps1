<#
    [已废弃 / DEPRECATED] 仅作历史留档，请勿使用。

    这是第一版实现，存在一个关键缺陷：
    它用 icacls /deny "<user>:(W)" 拒绝写入，而 (W) = GENERIC_WRITE 包含了读相关的位，
    结果连 ReadAllText 都被拒绝；更糟的是，广告模块若读不到 partner.data，
    会把记录当成空表、判定"从未展示过"，从而立刻弹一次 —— 比不修还糟。

    正确做法见上级目录的 apply-fix.ps1：只拒 (WD,AD,WEA,WA)，保留读权限。

    本文件仅用于说明踩坑过程，保留原样以便对照。
#>

$ErrorActionPreference = 'Stop'
$dir = Join-Path $env:APPDATA 'leidian14'
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'

$targets = @(
    @{ Path = Join-Path $dir 'partner.data';         New = '_456_time20991231_' },
    @{ Path = Join-Path $dir 'partner_report2.data'; New = '_time20991231' }
)

foreach ($t in $targets) {
    $p = $t.Path
    if (-not (Test-Path $p)) { Write-Host "SKIP (不存在): $p"; continue }

    $bak = "$p.bak_$stamp"
    Copy-Item $p $bak -Force

    attrib -R $p 2>$null
    icacls $p /remove:d "$env:USERNAME" 2>$null | Out-Null
    icacls $p /remove:d "SYSTEM"        2>$null | Out-Null

    [System.IO.File]::WriteAllText($p, $t.New, [System.Text.Encoding]::Unicode)

    attrib +R $p
    icacls $p /deny "$($env:USERNAME):(W)" | Out-Null      # <-- 缺陷：连读一起拒
    icacls $p /deny "SYSTEM:(W)"          | Out-Null

    "OK  $p  ->  $($t.New)   (备份: $bak)"
}
