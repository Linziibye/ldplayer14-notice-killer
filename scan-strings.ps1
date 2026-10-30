<#
.SYNOPSIS
    侦察脚本：从雷电模拟器的二进制里提取通知 / 广告相关的字符串、URL 与路径模板。
    用于在自己机器上重新定位机制（雷电换版本、换数据目录后可复用）。

.DESCRIPTION
    四种模式，可用 -Mode 选择，all 表示全跑：
      noice    扫描核心文件中的 noice / RemoteTip 关键字，判断通知归属哪个进程
      context  提取 noiceRemoteTipEX 附近的可打印片段，确认它只是配置键
      ads      专扫 partner 系列 exe，按 advert/promo/push/14/day/Remind 过滤广告类符号
      urls     提取 URL、API 路径、文件与注册表路径模板

    本脚本只读取文件，不修改任何内容。

.PARAMETER InstallDir
    雷电安装目录。默认自动探测注册表与常见安装位置。

.PARAMETER Mode
    noice | context | ads | urls | all（默认 all）

.EXAMPLE
    .\scan-strings.ps1 -Mode urls

.EXAMPLE
    .\scan-strings.ps1 -InstallDir "D:\LDPlayer\LDPlayer14" -Mode ads
#>
[CmdletBinding()]
param(
    [string]$InstallDir,
    [ValidateSet('noice','context','ads','urls','all')]
    [string]$Mode = 'all'
)

$ErrorActionPreference = 'SilentlyContinue'

function Resolve-LDInstallDir {
    param([string]$Explicit)
    if ($Explicit) {
        if (-not (Test-Path $Explicit)) { throw "安装目录不存在: $Explicit" }
        return (Resolve-Path $Explicit).Path
    }
    $cands = @()
    foreach ($k in @(
        'HKCU:\Software\leidian\LDPlayer14',
        'HKCU:\Software\leidian\LDPlayer9',
        'HKLM:\Software\leidian\ldplayer14',
        'HKLM:\Software\WOW6432Node\leidian\ldplayer14'
    )) {
        $v = (Get-ItemProperty $k -ErrorAction SilentlyContinue).InstallDir
        if ($v) { $cands += $v }
    }
    foreach ($d in @('C:\LDPlayer\LDPlayer14','D:\LDPlayer\LDPlayer14','C:\LDPlayer\LDPlayer9',
                     "$env:ProgramFiles\LDPlayer\LDPlayer14")) {
        $cands += $d
    }
    foreach ($c in $cands) {
        if ($c -and (Test-Path (Join-Path $c 'dnplayer.exe'))) { return (Resolve-Path $c).Path }
    }
    throw "未找到雷电安装目录，请用 -InstallDir 指定，例如 -InstallDir `"D:\LDPlayer\LDPlayer14`""
}

$root  = Resolve-LDInstallDir -Explicit $InstallDir
$latin = [Text.Encoding]::GetEncoding(28591)   # 1:1 字节映射，用来扫 ASCII 串
Write-Host "安装目录: $root`n" -ForegroundColor Cyan

$coreFiles = @('dnplayer.exe','dnplycore.dll','dnconsole.exe','ldplayerhelper.exe',
               'ldplayerservice.exe','ld.exe','ldtool.exe','ldplayerpartner.exe',
               'dnmultiplayer.exe','ld5567.exe') | ForEach-Object { Join-Path $root $_ }

$adsFiles = @('ld5567.exe','ldplayerpartner.exe','ldplayerservice.exe',
              'ldplayerhelper.exe','ldtool.exe') | ForEach-Object { Join-Path $root $_ }

# ---------------------------------------------------------------- noice
if ($Mode -in 'noice','all') {
    Write-Host "===== [noice] noice / RemoteTip 关键字 =====" -ForegroundColor Cyan
    foreach ($f in $coreFiles) {
        if (-not (Test-Path $f)) { continue }
        $name = [IO.Path]::GetFileName($f)
        $b = [IO.File]::ReadAllBytes($f)
        $s = $latin.GetString($b)
        foreach ($m in [regex]::Matches($s,'[\x20-\x7E]{5,200}')) {
            if ($m.Value -match 'noice|Noice|RemoteTip|remoteTip') { "ASCII  $name :: $($m.Value)" }
        }
        $u = [Text.Encoding]::Unicode.GetString($b)
        foreach ($m in [regex]::Matches($u,'[\x20-\x7E\u4e00-\u9fa5]{4,200}')) {
            if ($m.Value -match 'noice|Noice|RemoteTip|remoteTip|通知') { "UTF16  $name :: $($m.Value)" }
        }
    }
    ""
}

# ---------------------------------------------------------------- context
if ($Mode -in 'context','all') {
    Write-Host "===== [context] noiceRemoteTipEX 附近的配置键 =====" -ForegroundColor Cyan
    $f = Join-Path $root 'dnplayer.exe'
    if (Test-Path $f) {
        $b = [IO.File]::ReadAllBytes($f)
        $s = $latin.GetString($b)
        $idx = $s.IndexOf('noiceRemoteTipEX')
        "offset = $idx"
        if ($idx -ge 0) {
            # 只提取附近的可打印片段，避免把代码段打成乱码
            $a = [Math]::Max(0, $idx - 1500)
            $len = [Math]::Min(3000, $s.Length - $a)
            $chunk = $s.Substring($a, $len)
            $seen = @{}
            foreach ($m in [regex]::Matches($chunk,'[\x20-\x7E]{4,120}')) {
                $v = $m.Value
                if (-not $seen.ContainsKey($v)) { $seen[$v] = 1; "  +$($a + $m.Index) :: $v" }
            }
        }
        $u = [Text.Encoding]::Unicode.GetString($b)
        foreach ($m in [regex]::Matches($u,'[\u4e00-\u9fa5\x20-\x7E]{2,60}')) {
            if ($m.Value -match '天|通知|不再|提醒|关闭|忽略') { "U16@$($m.Index) :: $($m.Value)" }
        }
    } else { "dnplayer.exe 不存在: $f" }
    ""
}

# ---------------------------------------------------------------- ads
if ($Mode -in 'ads','all') {
    Write-Host "===== [ads] partner 系列 exe 的广告 / 通知符号 =====" -ForegroundColor Cyan
    foreach ($f in $adsFiles) {
        if (-not (Test-Path $f)) { continue }
        "############ $([IO.Path]::GetFileName($f)) ############"
        $b = [IO.File]::ReadAllBytes($f)
        $s = $latin.GetString($b)
        $seen = @{}
        foreach ($m in [regex]::Matches($s,'[\x20-\x7E]{5,150}')) {
            $v = $m.Value
            if ($v -match 'noice|notice|Notice|Notification|toast|Toast|14|day|Day|Remind|remind|advert|promo|push' -and -not $seen.ContainsKey($v)) {
                $seen[$v] = 1; "ASCII :: $v"
            }
        }
        $u = [Text.Encoding]::Unicode.GetString($b)
        $seen2 = @{}
        foreach ($m in [regex]::Matches($u,'[\u4e00-\u9fa5\x20-\x7E]{3,120}')) {
            $v = $m.Value
            if ($v -match '天|通知|提醒|关闭|不再|广告|推广' -and -not $seen2.ContainsKey($v)) {
                $seen2[$v] = 1; "UTF16 :: $v"
            }
        }
    }
    ""
}

# ---------------------------------------------------------------- urls
if ($Mode -in 'urls','all') {
    Write-Host "===== [urls] URL / API / 路径模板 =====" -ForegroundColor Cyan
    $f = Join-Path $root 'ld5567.exe'
    if (Test-Path $f) {
        $b = [IO.File]::ReadAllBytes($f)
        $s = $latin.GetString($b)

        "### URLs & hosts ###"
        $seen = @{}
        foreach ($m in [regex]::Matches($s,'https?://[^\x00-\x20\x7f"'']{4,160}')) {
            $v = $m.Value
            if (-not $seen.ContainsKey($v)) { $seen[$v] = 1; "URL :: $v" }
        }

        "### hosts / api paths ###"
        $seen = @{}
        foreach ($m in [regex]::Matches($s,'[\x20-\x7E]{4,160}')) {
            $v = $m.Value
            if ($v -match 'ldmnq|leidian|ldplayer|/api/|\.php|\.json|\.do\b|host|Host|domain|Domain' -and -not $seen.ContainsKey($v)) {
                $seen[$v] = 1; "P :: $v"
            }
        }

        "### file / registry path templates ###"
        $seen = @{}
        foreach ($m in [regex]::Matches($s,'[\x20-\x7E]{3,160}')) {
            $v = $m.Value
            if ($v -match 'Software\\|AppData|%s\\|\.dat|\.ini|\.json|reg(open|set)|Reg(Open|Set)|SHGetFolder|GetTempPath|\.data' -and -not $seen.ContainsKey($v)) {
                $seen[$v] = 1; "F :: $v"
            }
        }

        "### UTF16 URLs ###"
        $u = [Text.Encoding]::Unicode.GetString($b)
        $seen = @{}
        foreach ($m in [regex]::Matches($u,'https?://[\x20-\x7E]{4,160}')) {
            $v = $m.Value
            if (-not $seen.ContainsKey($v)) { $seen[$v] = 1; "U :: $v" }
        }
    } else { "ld5567.exe 不存在: $f" }
    ""
}

Write-Host "=== DONE ===" -ForegroundColor Green
