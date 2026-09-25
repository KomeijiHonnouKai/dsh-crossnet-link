# 自动化:能全自动的部分,与必须人工的部分

> 最后更新:2026-09-26(t4 集成同步:§1 表的 `security.md §6.2` 收为 `§6`——整行覆盖语义在 §6.1、裸 entry 在 §6.2;§4.1 的跳转补上 `browser-control.md` 小节号)。上一版:2026-09-24 17:04(W4)。本次使用的命令见 `README.md` 的「本次修订」。

## 0. 先看这条:本机默认 ExecutionPolicy = Restricted,裸 `.\xxx.ps1` 跑不起来

实测(本机 Windows 10 工作站,`Get-ExecutionPolicy -List` 五个 Scope 全 `Undefined` ⇒ 生效值 = **Restricted**):

    & .dsh\skills\dsh-remote-tailnet\scripts\verify.ps1 -ServerIp <PEER_IP>
    # ⇒ File ...\verify.ps1 cannot be loaded because running scripts is disabled on this system.
    #    (PSSecurityException / FullyQualifiedErrorId: UnauthorizedAccess)

**所以本 skill 里所有 `.ps1` 一律用下面这种「不依赖机器策略」的形态**(不改任何 ExecutionPolicy 设置,只对这一次进程生效):

    powershell -NoProfile -ExecutionPolicy Bypass -File <脚本绝对或相对路径> -ServerIp <PEER_IP>

例(`<PEER_IP>` = 服务端 tailnet 100.x,本 skill 不写死任何真实对端地址):

    powershell -NoProfile -ExecutionPolicy Bypass -File .dsh/skills/dsh-remote-tailnet/scripts/verify.ps1 -ServerIp <PEER_IP>
    powershell -NoProfile -ExecutionPolicy Bypass -File .dsh/skills/dsh-remote-tailnet/scripts/verify.ps1 -ServerIp <PEER_IP> -Soak -Count 11 -IntervalSeconds 30
    powershell -NoProfile -ExecutionPolicy Bypass -File .dsh/skills/dsh-remote-tailnet/scripts/server-setup.ps1 -CheckOnly

> `-ExecutionPolicy Bypass` 只作用于这个子进程,不改注册表、不改机器/用户策略 ⇒ 可逆、零残留。

## 1. 结论先说

**「全自动跑通」做不到。更要紧的是:`server-setup.ps1` 本身不改动任何东西** —— 它是「只检查 + 只打印」的巡检脚本,不是安装器。

下表逐条对齐「脚本实际行为」,任何脚本不执行的动作都不打 ✅:

| 步骤 | 能否自动 | 脚本实际做到哪一步 | 剩下必须人工做的 |
| --- | --- | --- | --- |
| 装 Tailscale MSI | ❌ 必须人工(需一次 UAC) | `server-setup.ps1` 输出第 1 节:只 `Get-FileHash` **打印** sha256,并**打印** `Start-Process msiexec.exe -Verb RunAs …` 原文。**不下载 MSI、不与期望值比对 sha256、不调用 msiexec** | 人工把打印出来的 hash 与官方值核对,再自己粘贴执行 |
| **登录 Tailscale 账号** | ❌ 必须人工 | 脚本输出第 2 节:只用 `tailscale ip -4` 的退出码判是否已登录;被命名管道拒绝时明确输出「此处无法判定」 | 浏览器 OAuth;agent 不代输账号密码(纪律) |
| `tailscale serve --bg` | ❌ 脚本只打印 | 脚本输出第 4 节:只读 `tailscale serve status`;未配置时**打印** `serve --bg <port>` 这条命令 | 人工在普通窗口执行(CLI 在受限上下文会被拒) |
| 追加 `connection.trustedHosts` | ❌ 脚本只打印 | 脚本输出第 5 节:`Select-String` 查 patch 里有没有该域名;缺了就**打印**要追加的 YAML 片段。**不写文件、不备份、不改任何 profile** | 人工追加(规范写法见 security.md §6) |
| 重启 DSH | ⚠️ 只能人工 | 脚本输出第 6 节(横幅「必须人工完成的四件」):只打印提醒 | 设置 → 桌面/Desktop → 「重启 ▾」→ 重启;禁止第三方重启插件 |
| tailnet policy 收紧 | ❌ 必须人工 | 不涉及 | 控制台网页操作 |
| 客户端首次带 token 打开 | ❌ 必须人工 | 不涉及 | 用户在自己机器地址栏粘贴一次(凭据纪律) |
| 验收/巡检(三态 + soak) | ✅ **真自动** | `verify.ps1` 真的用 `[Net.Sockets.TcpClient]` 探测,并给出有语义的退出码 | — |

> ⚠️ 表里的「输出第 N 节」指 **`scripts/server-setup.ps1` 运行时打印的 `=== N. … ===` 小节**,**不是**本文或 `server-setup.md` 的小节号 —— 两套编号含义不同:`server-setup.md` §6 = 防火墙,而脚本第 6 节 = 横幅「必须人工完成的四件」。脚本横幅实测为:`1. Tailscale 是否已安装` / `2. 登录状态(人工)` / `3. DSH loopback 端口` / `4. serve` / `5. Host 信任(cordis.patch.yml)` / `6. 必须人工完成的四件` / `7. 验收`。

**验收脚本的退出码(实测,不再是恒 0)**:

| 码 | 含义 | 触发条件 |
| --- | --- | --- |
| 0 | 全通 | 链路口(`-LinkPort`,默认 443)connected,且其余探测口全部 timeout(隔离成立);soak 每一轮都 connected |
| 1 | 降级 | 链路口 connected,但非链路口也 connected ⇒ 隔离(ACL)没生效;soak 部分失败 |
| 2 | 阻断 | 链路口 refused/timeout/出错(serve 挂了或包被丢);soak 全失败;或参数非法 |

> 三态与退出码的判读模板见 [verify.md](verify.md)。`server-setup.ps1` **没有**退出码语义(它只打印),别拿它的退出码当验收结论。

## 2. 幂等脚本设计原则(写脚本时照此)

1. **先读后写**:每步先探测当前状态(是否已装/已 serve/已有该行),已满足就跳过;
2. **每步带回滚命令**,并在输出里打印;
3. **改动前后做 hash/状态对照**,证明“只改了说好的那处”;
4. **不出网不必要的请求**;下载必须校验 sha256(地址与期望值写死在文档里);
5. **不代用户登录、不碰 UAC 策略、不改 tailscaled 管道 ACL**;
6. **不新增任何 `0.0.0.0` 监听**;需要放行入站时必须同时给出窄放行(程序 + 远端网段 + 端口);
7. **本版脚本一律「只读」**:`server-setup.ps1` 只检查 + 打印(要改的动作全部交给人),`verify.ps1` 只出网探测。这样「脚本跑过」不可能造成任何不可逆改动;
8. **不要用中文字面量路径**:PowerShell 5.1 在提权/子进程上下文里对含中文的路径字面量做 `Test-Path` 会**假失败**(报「不存在」,实际存在)⇒ 用 `Get-ChildItem | Where-Object { $_.Name -match '<ascii token>' }` 动态匹配(实测踩过:一条「已删除」的假信号差点让残留漏过验收);
9. **删除失败的兜底**:目标 ACL 完全正常、却 `Remove-Item -Recurse -Force` 报「对路径的访问被拒绝」时,换 `[System.IO.Directory]::Delete($path, $true)` —— PowerShell Provider 层与 .NET 层的检查路径不同,后者常能过。
10. **改完 `.ps1` 必须复验编码**:含中文的脚本必须存成 **UTF-8 with BOM**。掉了 BOM 时 PowerShell 5.1 按 ANSI(GBK)读 ⇒ 中文乱码、甚至解析报错(实测:只改了一行中文后 BOM 丢失,`Parser::ParseFile` 立刻报 17 个语法错)。改完做两步复验:
   ```powershell
   $b = [System.IO.File]::ReadAllBytes($f); $b[0..2] -join ','   # 应为 239,187,191
   [void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$null, [ref]$errs); $errs.Count   # 应为 0
   ```

## 3. 验收与巡检(可全自动)

- 三态:对 `<server 100.x>:443` 做 TCP connect,拿 connected / refused / timeout;
- 通:HTTPS GET `https://<ts.net 域名>/`,期望 200/303/401(**401 = 正常且未带 token**);
- 隔离:同轮探测非 443 端口(建议 135/5357,避开我们加固过的 139/445),期望 timeout;
- soak:每 30 秒一次、5–30 分钟;结论表述**必须限定窗口**(“该 5 分钟内 11/11”),不要写成“链路稳定”。
- 上面全部由 `verify.ps1` 执行,并落成退出码 0/1/2(见 §1 表)。

## 4. 跨机协作的用法(本 skill 的副产品)

打通之后,两台 DSH 可以互换「对方网络里能看到、自己看不到」的事实:
- 常态代理的那一端可以联网核对文档/下载/版本(服务端常开代理 ⇒ 适合做外部核实);
- 校园网/受限网那一端适合做本地代码与配置审计、三态探测、soak;
- **互通的前提是先声明各自的探针能力**(能否 TLS / ICMP / UDP / 跑 tailscale CLI),否则会把环境限制当成链路证据。分栏表见 [verify.md](verify.md) §0.1。

### 4.1 读对方会话:网页读不全时,走「下载 Session 日志」

> 本节只是摘要。完整的两套工具选型(`browser_*` 首选 / `ego_*` 只做轻量查询)、写入 composer 的坑、选会话的索引规则、以及**可直接粘贴的整段读取命令**见 [browser-control.md](browser-control.md)(§0 选型 / §2 写入 / §2.1 选会话 / §3.1 读取命令原文 / §4 已知局限)。

用浏览器操作对方的 DSH 时,**长会话的尾部读不到** —— `browser_get_text` / snapshot 只给页面文本的前 ~8.4 KB,`selector` 又难定位"最后一条消息"(`querySelector` 只返回第一个匹配)。实测可用的通道:

1. 对方会话页 →「更多操作」(⋯) → **下载 Session 日志**;
2. 浏览器下载 `dsh-session-session-<id>.zip`(实测 560 KB);
3. 解压得 `session.v3.jsonl`,每行一个事件:`user/message`、`assistant/message`(content 数组含 `reasoning` / `text` / `tool-call`)、`tool/call`(**工具写入的文件原文就在 `arguments` 里**)、`turn/end`;
4. 解析:

```powershell
$lines = [System.IO.File]::ReadAllLines('session.v3.jsonl', [System.Text.Encoding]::UTF8)
# Never index by line number (the tail is usually turn/end): filter by event type.
$line = $lines | Where-Object { $_ -match '"type"\s*:\s*"assistant/message"' } | Select-Object -Last 1
$o = $line | ConvertFrom-Json
$o.data.message.content | Where-Object { $_.type -eq 'text' } | ForEach-Object { $_.text }
```

⚠️ **别按行号取**:按「倒数第 N 行」定位这类写法在一份真实导出上实测**静默无输出** —— 该导出尾部三条依次是 `assistant/message`、`step/end`、`turn/end`,按倒数第 4 行取到的那条没有 `text` 块,于是命令既不报错、也不打印任何东西。正确做法是按 `"type":"assistant/message"` 过滤再取**最后一条**;块是带类型的,`reasoning` / `thinking` 必须滤掉、只留 `text`。上面这 5 行**纯 ASCII、可直接粘贴**(实测该导出:块类型 `reasoning, text`,取到正文 25,488 字符)。**完整可粘贴命令**(下载 zip → `.NET` 只解 `session.v3.jsonl` → 事件分诊 → 自包含取正文)见 [browser-control.md](browser-control.md) §3.1。

> 走文件而不是读 DOM,长会话、展开的卡片、代码块全都能拿到。注意:导出里可能含凭据原文,按纪律 10 **不得外传**。
