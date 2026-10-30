<#
.SYNOPSIS
    一键回滚：撤销雷电模拟器通知记录上的所有修改与保护。

.DESCRIPTION
    对每个记录文件：
      1) icacls /reset 恢复继承权限
      2) 去掉只读属性
      3) 若存在 .bak_* 备份，把最新的一份拷回原位
    完成后雷电回到原始状态，14 天弹窗行为恢复原样。

.PARAMETER DataDir
    雷电数据目录，默认自动探测。

.EXAMPLE
    .\restore.ps1
#>
[CmdletBinding()]
param([string]$DataDir)

$ErrorActionPreference = 'Continue'
$me = "$env:USERDOMAIN\$env:USERNAME"

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

$files = @('partner.data','partner_report2.data')

foreach ($f in $files) {
    $p = Join-Path $dir $f
    if (-not (Test-Path $p)) { Write-Host "SKIP  $f 不存在" -ForegroundColor DarkGray; continue }

    icacls $p /reset 2>$null | Out-Null
    icacls $p /remove:d $me       2>$null | Out-Null
    icacls $p /remove:d 'SYSTEM'  2>$null | Out-Null
    attrib -R $p 2>$null | Out-Null

    $bak = Get-ChildItem "$p.bak_*" -ErrorAction SilentlyContinue |
           Sort-Object LastWriteTime -Descending | Select-Object -First 1

    if ($bak) {
        Copy-Item $bak.FullName $p -Force
        Write-Host "已还原 $f  <-  $($bak.Name)" -ForegroundColor Green
    } else {
        Write-Host "无备份可还原，仅解除了 $f 的保护（雷电下次启动会自行重建记录）" -ForegroundColor Yellow
    }
}

Write-Host "`n完成。若之前设过 hosts 拦截或 exe 执行拒绝，请自行移除：" -ForegroundColor Cyan
Write-Host "  hosts: 删掉 mnq-service.ldmnq.com 那一行"
Write-Host "  icacls `"<安装目录>\ld5567.exe`" /remove:d SYSTEM"
