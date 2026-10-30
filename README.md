# ldplayer14-notice-killer

永久关闭雷电模拟器（LDPlayer 14）"关掉 14 天后又弹回来"的**电脑桌面通知 / 桌面广告弹窗**。

> **TL;DR** — LDPlayer's ad module keeps `partner.data` as a `_<adId>_time<yyyymmdd>_` log and re-shows an ad
> when 14 days have passed since its last display. Rewrite that date far into the future, then make the file
> readable-but-not-writable. That's the whole trick. 3 commands, fully reversible, no binaries touched.

---

## 1. 问题现象

在雷电模拟器顶部菜单点「不再提示」后，通知确实消失，但 **14 天左右又弹出来**，如此循环，无法永久关闭。

关键点：那个「不再提示」开关（写入 `vms\config\leidians.config` 的 `noiceRemoteTipEX`）**根本不是**这个弹窗的开关，而且该配置文件每次启动都会被重写。

## 2. 机制

弹窗来自广告模块 `ld5567.exe`（与 `ldplayerpartner.exe` 同体），由服务 `LDPlayerSvr` 每 30 分钟拉起一次。

它维护一份**展示记录表**：

```
%APPDATA%\leidian14\partner.data
```

原始内容（UTF-16LE）：

```
_415_time20261002__421_time20261015__456_time20261029_
```

- 格式：`_<广告ID>_time<yyyyMMdd>_`，一条记录 = 一次展示
- 判定：`距上次展示 ≥ 14 天 → 重新弹`
- 上例三条记录间隔 13 天、14 天，完美复现「关 14 天又回来」

配套文件：

| 文件 | 作用 |
|---|---|
| `partner.data` | **主记录表，14 天计时的真正来源** |
| `partner_report2.data` | 上报时间戳副本（同为 `_time<yyyyMMdd>` 格式） |
| `partner_report.data` | 纯 Unix 时间戳，不参与判定 |

从二进制中提取到的相关符号，可作为机制佐证：

```
LDPlayerPartnerModel::todayHasShowAd
LDPlayerPartnerModel::calcShowAD
LDPlayerPartnerImpl::showAdFrame
LDPlayerPartnerImpl::showAdFrame2
LDPlayerPartnerImpl::showAppUpdateAdFrame
LDPlayerPartnerImpl::showGiftPackAdFrame
```

推送接口（用于下发广告/通知内容）：

```
https://mnq-service.ldmnq.com/mnq/windows-msg/push
```

## 3. 修复原理

1. 把记录里的日期改成 `20991231` → 永远处于「刚展示过」状态，14 天判定永不成立
2. 文件加只读属性 + ACL 拒绝写入 → 防止程序把真实日期覆写回去
3. **只拒写、不拒读**（`WD,AD,WEA,WA`，不含 `READ_CONTROL`）→ 这一点是坑：
   若程序读不到文件，会把记录当成空表、判定「从未展示」，立刻弹一次，比不修还糟。
   见 [`legacy/fix_ld_notice_v1.ps1`](legacy/fix_ld_notice_v1.ps1) 的翻车记录。

## 4. 用法

```powershell
# 1) 应用修复（会自动备份原文件并做写入/读取/覆写三重校验）
powershell -ExecutionPolicy Bypass -File .\apply-fix.ps1

# 2) 正常启动一次雷电模拟器，随便用几分钟

# 3) 复查：修改时间应仍停在修复时刻，内容仍为 20991231
powershell -ExecutionPolicy Bypass -File .\check-record.ps1

# 4) 想撤销
powershell -ExecutionPolicy Bypass -File .\restore.ps1
```

先看不动手：

```powershell
.\apply-fix.ps1 -DryRun
```

### 参数

`apply-fix.ps1`

| 参数 | 默认 | 说明 |
|---|---|---|
| `-DataDir` | 自动探测 `%APPDATA%\leidian14` | 雷电数据目录；兼容 `leidian13` / `leidian12` / `leidian9` |
| `-FutureDate` | `20991231` | 写入的日期，`yyyyMMdd` |
| `-DryRun` | 关 | 只演示流程，不改文件 |

`check-record.ps1` / `restore.ps1` 也接受 `-DataDir`。

## 5. 脚本清单

| 文件 | 作用 |
|---|---|
| `apply-fix.ps1` | **主修复**。探测目录 → 备份 → `icacls /reset` → 写未来日期 → 读回校验 → 只读 + 拒写 ACL → 再验读 → 覆写测试 |
| `check-record.ps1` | 复查。打印三个记录文件的内容、属性、修改时间，并标注是否处于已修复状态 |
| `restore.ps1` | 一键回滚。重置 ACL、去只读、把最新 `.bak_*` 拷回 |
| `scan-strings.ps1` | 侦察工具。从雷电二进制中提取通知/广告字符串、URL、路径模板，用于新版本重新定位 |

`scan-strings.ps1` 的 `-Mode`：

```powershell
.\scan-strings.ps1 -Mode noice     # noice / RemoteTip 关键字，判断通知归属进程
.\scan-strings.ps1 -Mode context   # noiceRemoteTipEX 的二进制上下文
.\scan-strings.ps1 -Mode ads       # partner 系列 exe 的广告符号
.\scan-strings.ps1 -Mode urls      # URL / API / 文件与注册表路径模板
.\scan-strings.ps1 -Mode all       # 全跑（默认）
```

安装目录同样自动探测（读 `HKCU\Software\leidian\LDPlayer14` 的 `InstallDir`），也可 `-InstallDir "D:\LDPlayer\LDPlayer14"`。

## 6. 如果还是弹（加强方案）

按温和度递增，需手动执行：

```powershell
# A. 只断消息推送通道，不影响模拟器主体（以管理员编辑 hosts）
#    C:\Windows\System32\drivers\etc\hosts  追加一行：
#    0.0.0.0 mnq-service.ldmnq.com

# B. 禁止广告模块执行（副作用：log\logsvr.txt 每半小时多一行报错）
icacls "<安装目录>\ld5567.exe"          /deny "SYSTEM:(X)"
icacls "<安装目录>\ldplayerpartner.exe" /deny "SYSTEM:(X)"

# C. 防程序删档重建（影响整个数据目录，最后手段）
icacls "$env:APPDATA\leidian14" /deny "SYSTEM:(DC)"
```

## 7. 兼容性与范围

- 验证环境：LDPlayer **14.0.29.0**，Windows 10/11，PowerShell 5.1 与 7 均可用。
- 脚本用 UTF-8 with BOM 保存，避免 PS 5.1 下中文乱码。
- **只改本地数据文件及其 ACL**，不修改、不破解、不重打包雷电任何可执行文件，不动数字签名。
- **完全可逆**：`restore.ps1`，或手动 `icacls /reset` + 拷回 `.bak_*`。
- 雷电大版本升级若更换数据目录或记录格式，`apply-fix.ps1` 会因找不到 `partner.data` 而报错退出（不会误改别的文件），届时用 `scan-strings.ps1` 重新定位即可。
- 不含任何个人标识：脚本内所有路径均通过 `$env:APPDATA` / `$env:USERDOMAIN` / 注册表探测得到，不含用户名、计算机名或固定安装路径。

## 8. 隐私说明

本仓库所有脚本与文档中**不存在**以下内容：用户名、计算机名、主机名、IP、MAC、浏览器数据、账号凭据、聊天记录、文件历史。

- 路径一律用环境变量或自动探测表达
- ACL 中的用户身份用 `$env:USERDOMAIN\$env:USERNAME` 运行时求值
- README 里的 `partner.data` 示例内容仅为技术说明用途的广告 ID 与日期，不含任何个人可识别信息

## 9. License

MIT
