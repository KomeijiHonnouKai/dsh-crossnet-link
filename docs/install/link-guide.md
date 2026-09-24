# 打通指引：把两台 DSH 连成一条可远程操作的链路

- 最后更新时间：2026-09-25。本文件第一次把「怎么把两台 DSH 连起来」写进仓库。
- 本次使用的命令（全部只读；路径用占位符，换机器只需换括号里的值）：
  1. `tailscale ip -4`、`tailscale serve status`，在普通窗口跑，沙箱说明见第 3.2 小节
  2. `netstat -ano | Select-String '127.0.0.1'`
  3. `[Net.Sockets.TcpClient]` 打真实端口拿三态，第 8 节固定顺序第 1 步
  4. `netsh advfirewall monitor show currentprofile`
  5. `powercfg /query SCHEME_CURRENT 238c9fa8-0aad-41ed-83f4-97be242c8f20`
  6. `Restart-Service Tailscale -Force`，两端各一次，第 8 节第 3 步

> 阅读顺序：第 1 节边界 → 第 2 节前置条件 → 第 3 节十步 → 第 4 节本仓库的角色 →
> 第 5 节凭据纪律 → 第 6 节浏览器操作对端 → 第 7 节验收 → 第 8 节故障速查。
> 第一次做请按第 2、3 节的顺序走完，再跳读其它节。

## 1 这条链路是什么，边界在哪

一句话：两台机器登进同一个 Tailscale 账号（同一 tailnet），服务端用
`tailscale serve --bg` 把它自己 loopback 上的 DSH 端口发布到 tailnet，
tailnet 控制台用窄 ACL 只放「客户端 → 服务端 tcp:443」，
客户端浏览器带一次 token 打开那个 `https://<机器名>.<tailnet>.ts.net/`，
换一张有效的 30 天 cookie，此后就能用自己的浏览器操作另一台机器上的 DSH 界面。

边界（本文只写这一条已实测跑通的路径）：

- 全文不讨论方案选型，不列替代做法，也不给兜底方案。整机远程桌面、
  局域网 HTTPS、第三方中转、公网端口映射都不在本文范围。
- 服务端拿不到一次管理员权限，装 Tailscale 的 MSI 必须提权一次 ⇒ 这条路径走不通。
- 服务端不允许安装 Tailscale 客户端 ⇒ 这条路径走不通。
- 服务端 DSH 的桌面外壳模式不是兼容模式 ⇒ 这条路径走不通，见第 2 节。
- 服务端 DSH 端口不是默认的 43120、也没有同步改 serve 与 ACL ⇒ 链路会静默断开，
  见第 8 节。

风险与价值是同一个东西：能打开服务端 DSH 界面，就等于能以那个 DSH 的权限操作那台机器。
所以第一优先级不是先把链路打通，而是先收好服务端 DSH 的默认权限与 tailnet 成员范围，
也就是前置条件的第 7、8 项。

## 2 前置条件（硬性，缺一条就走不通）

| # | 项 | 要求 |
| --- | --- | --- |
| 1 | 两台机器 | Windows 10 或 11；本文件的命令按 Windows PowerShell 5.1 写 |
| 2 | Tailscale 账号 | 两端登录同一个账号（同一 tailnet），这是窄 ACL 成立的前提 |
| 3 | 管理员权限 | 两端各需一次 UAC：装 Tailscale 的 MSI。此后不再需要 |
| 4 | 服务端 DSH 外壳 | 桌面模式必须是兼容模式；`openBrowser` 必须是 `true` |
| 5 | 服务端 DSH 端口 | 默认 `43120`，且保持不改（serve 指向它，改了 serve 就指向空气） |
| 6 | 服务端 DSH 权限 | 默认权限模式建议 `workspace-write`，不要 `danger-full-access` |
| 7 | tailnet 成员 | 控制台设备列表只留需要的那两台；账号开二次验证（默认 ACL 是全通） |
| 8 | 电源策略 | 服务端插电时不休眠、合盖不睡眠；用电池时 1 小时进待机、链路会断 |
| 9 | 客户端网络 | 系统代理或代理软件的 TUN 不能劫持 `*.ts.net` 与 tailnet 段 |

关于第 4、5 项：这两项在 DSH 设置里读，不在文件里猜。桌面模式与 `openBrowser`
改完要重启 DSH，且只用 DSH 自带入口（设置 → 桌面/Desktop → 「重启 ▾」），
不要装任何第三方重启类插件。

跑脚本前的执行策略：Windows 默认 `ExecutionPolicy` 是 `Restricted`，
裸 `.\xxx.ps1` 会被拒，报 `running scripts is disabled on this system`。
一律用下面这种不改机器策略、只对子进程生效的形态：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <脚本路径> <参数>
```

## 3 从零打通的十步

每步给出：动作、可复制命令、期望结果。标【服务端】的在那台被操作的机器上做，
标【客户端】的在做操作的机器上做，标【控制台】的去 tailnet 管理台做。

### 3.1 第 1 步【服务端】装 Tailscale

自己从厂商下载页取 Windows `.msi`，不要用仓库里写死的链接或哈希，
算一次 SHA256、看一次 Authenticode 再装：

```powershell
powershell -NoProfile -Command "(Get-FileHash -Algorithm SHA256 -LiteralPath '<MSI_PATH>').Hash"
powershell -NoProfile -Command "Get-AuthenticodeSignature -LiteralPath '<MSI_PATH>' | Select-Object Status"
msiexec /i "<MSI_PATH>" /passive /norestart
```

期望：哈希与厂商公布值一致、签名 `Valid`、安装过程弹一次 UAC，由你点。装完复核：

```powershell
Get-Service Tailscale | Select-Object Status,StartType    # 期望 Running / Automatic
tailscale version                                        # 期望版本号，exit 0
```

回滚：`msiexec /x "<MSI_PATH>" /passive /norestart`。

### 3.2 第 2 步【服务端】登录并记下自己的 tailnet 地址

托盘 Tailscale 图标 → Log in → 浏览器里用与客户端同一个账号完成登录。
这一步只能人工做：不要代输账号、密码或验证码。

```powershell
tailscale ip -4        # 期望 100.x.x.x，记下来，后面 ACL 要用
tailscale status       # 期望能看到两台设备都在同一 tailnet
```

期望：`ip -4` 打印一个 `100.x.x.x`。沙箱说明：在受限会话里跑 `tailscale`
子命令会报 `Access is denied`，因为守护进程的命名管道被保护；这是设计边界、与链路无关。
这类命令请在普通（非沙箱）窗口里跑。被拒时该项落「无法判定」，不要读成「未登录」。

### 3.3 第 3 步【客户端】同样装 Tailscale、登同一账号

重复第 1、2 步的动作，在客户端机器上做一遍，并记下自己的 tailnet 地址：

```powershell
tailscale ip -4        # 记下客户端的 100.x，第 7 步的 ACL 里要用
```

期望：两台设备互相可见，客户端能列出服务端，反之亦然。
现在不需要能 ping 通——窄 ACL 做出来之后，反向 ping 本就不通，见第 7 节。

### 3.4 第 4 步【服务端】确认 DSH 在 loopback 上监听

```powershell
netstat -ano | Select-String '127.0.0.1:' | Select-String 'LISTENING'
```

期望：出现 `127.0.0.1:43120` 一行，且同一行末尾的 owner PID 是 DSH 的进程。
不要用 `Get-NetTCPConnection -LocalPort 43120` 判有没有监听：这个 cmdlet
实测会不报错地返回 0 行。判监听用上面这条，或者真连一次，见第 8 节第 1 步。

### 3.5 第 5 步【服务端】起 serve，并记下入口域名

```powershell
tailscale serve --bg 43120
tailscale serve status
```

期望：`serve status` 打印一条 `https://<机器名>.<tailnet>.ts.net/`，
proxy 目标为 `http://127.0.0.1:43120`。`--bg` 必须带：不带的话机器重启或
`tailscale up/down` 之后链路会静默消失，带了才会自动恢复。
入口域名里的 `<机器名>` 就是 `tailscale status` 里那台机器的名字。

回滚：`tailscale serve reset`。语义是清空这台机器上全部 serve 配置，
不是只撤刚设的这一个端口；先 `tailscale serve status` 记下现状再动手。

### 3.6 第 6 步【服务端】给 DSH 补一条 Host 信任

远端界面能打开、但目录选择器报 403、客户端反复「自动重连中」，就是这个原因：
DSH 对 `/api` 有 Host 信任栅栏。在活动 profile 的补丁文件末尾追加：

```yaml
- id: connection
  name: '@deepseek-ai/dsh-client-connection'
  config:
    trustedHosts: ['<机器名>.<tailnet>.ts.net', ...ctx.webRuntime.trustedHosts]
```

文件落点 = `<DSH_HOME>\profiles\<profile>\cordis.patch.yml`
（`<DSH_HOME>` 未设 `DSH_HOME` 时是 `%USERPROFILE%\.dsh`；默认 profile 名是 `desktop`）。
两个硬要求：

1. `...ctx.webRuntime.trustedHosts` 不能省：补丁的 config 是整行覆盖语义，
   只写字面量会把运行时派生的局域网字面量静默丢掉；
2. 每个 entry 必须是裸 `host[:port]`，不带路径、不带 `user@`、不带首尾空白、
   不写悬空冒号或零填充端口，否则装载时直接抛
   `is not a bare host[:port] authority`。

期望：改完用自带入口重启 DSH（设置 → 桌面/Desktop → 「重启 ▾」→ 重启），
重启后远端界面与目录选择器都能用。回滚：删掉这段再重启。

### 3.7 第 7 步【控制台】把 ACL 收紧成单向 443

tailnet 管理台 → 访问控制策略，改成只放「客户端 → 服务端 tcp:443」：

```json
{"acls":[{"action":"accept","src":["<客户端 100.x>/32"],"dst":["<服务端 100.x>/32:443"]}]}
```

期望：保存成功、策略下发。选择器只支持 users/groups/tags/autogroups 与 IP/CIDR，
设备名不能当选择器。副作用是预期的：ICMP 与其他端口会被拒，
所以反向 ping 不通不是故障，也不能拿 ping 当链路证据，见第 8 节。
同时把设备列表收到只剩这两台，并给账号开二次验证。

### 3.8 第 8 步【服务端】电源策略（笔记本必做）

设置 → 系统 → 电源：接通电源时「合盖不休眠」、闲置不睡眠。
只设 AC 不够，交流与直流要分开确认：

```powershell
$scheme = 'SCHEME_CURRENT'
$sub = '238c9fa8-0aad-41ed-83f4-97be242c8f20'
$setting = '29f6c1db-86da-48c5-9fdb-f2b67b1f44da'
powercfg /query $scheme $sub $setting
```

期望：「当前交流电源设置索引」与「当前直流电源设置索引」都是 `0x00000000`。
只要直流那一项非 0，交电一断、到点进待机，链路必断，症状是客户端所有端口一起超时。
交付措辞写「市电中断 N 秒后链路必断」，不要笼统写「已设为不休眠」。

### 3.9 第 9 步【客户端】带 token 打开一次，换 30 天 cookie

token 只在服务端机器上取：服务端 DSH → 设置 → 桌面/Desktop → 「浏览器访问地址」，
那一栏形如 `http://127.0.0.1:<port>/?token=<TOKEN>`。
只取 `?token=` 后面那串，值不要贴给任何人、任何对话、任何日志，见第 5 节。

然后在客户端浏览器地址栏粘一次：

    https://<机器名>.<tailnet>.ts.net/?token=<TOKEN>

期望：一次跳转后正常进入界面，cookie 有效期 30 天，绑定 `host:port`。
证书由 Tailscale 自动签发（公共可信），不应有证书警告；
有警告就说明打开的不是 serve 入口，停下排查。
那一栏显示的 loopback 地址只是「在哪儿显示」的问题，`token` 那串与入口域名无关。

### 3.10 第 10 步 验收

三态探测 + 窗口化 soak，判据与退出码见第 7 节。验收通过后日常直接用
`https://<机器名>.<tailnet>.ts.net/` 打开即可，不再需要带 token。

## 4 本仓库在这条链路里的角色

装完本仓库不会让两台机器连通。它能做四件事：

- 只读体检：采集器给四态判定与退出码 0/1/2，不新增监听、不改配置、不读凭据。
- 前置件检查：逐项告诉你缺什么，只打印「可选修复：由你执行」的命令。
- 只读面板：设置页里一张姿态卡片，没有写入按钮。
- 完整卸载：默认干跑，只按自己的台账回滚自己改过的项。

它不做的：不负责打通两台机器之间的链路、不装任何软件、不提权、不代点 UAC、
不转发流量、不做中转、不卸载 Tailscale、不动你自己建的防火墙规则。

打通的动作在第 3 节与第 8 节，或者按 skill `dsh-remote-tailnet` 做；
那份 skill 与本文件同源，不随本仓库发布。
本仓库能在打通前后告诉你现状是什么、哪里可能有风险、缺哪件前置件：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/src/collect.ps1 -CheckOnly
powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/panel/prereq.ps1 -CheckOnly -Role client
powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/panel/prereq.ps1 -CheckOnly -Role server -ShowInstallPlan
```

判读纪律：`exit 2` 与 `unknown` 都不是「命令失败」，是 fail-closed 的判定。
没有对端地址时链路项无法探测、沙箱里 Tailscale CLI 会被拒，这些如实落 `unknown`；
`trustedHosts` 未配置会落 `blocked`。不确定绝不当通过。

## 5 凭据纪律（先读这一节再动手）

1. 带 token 的 URL 就是凭据。它不进入任何对话、日志、聊天、工单、网盘或截图；
   只由用户在自己机器的地址栏粘贴一次。一旦出机，唯一正确处置是撤销该凭据，见第 3 条。
2. 30 天 cookie 是绝对期限，不因使用而续期。cookie 只在带 token 的那一次签发；
   之后每个请求只校验、从不重签。天天用也不会延长，到第 30 天一律失效。
3. 撤销只有两个落点：① 客户端清掉该站点的 cookie，或换一个浏览器 profile；
   ② 服务端删掉凭据库里 `client-connection` 的 `browser-session` 那条记录，
   再用自带入口重启 DSH，重新生成签名密钥，所有已发出的 cookie 立即验签失败。
   只重启 DSH 不会让已发出的 30 天 cookie 失效：重启换掉的是每进程随机的
   launch token，签名密钥是持久化的。`tailscale serve reset` 撤的是对外入口，不碰凭据。
4. 续期要趁还没到期：cookie 还有效时，在客户端浏览器打开远端界面的
   设置 → 桌面/Desktop → 「浏览器访问地址」，取当前进程的 token，再粘一次
   `https://<机器名>.<tailnet>.ts.net/?token=<TOKEN>`，新的 30 天从这一刻重新起算。
5. 到期了，而且服务端在那之后重启过 ⇒ 远端已经没有任何可用凭据。
   launch token 每进程一个、重启即换，旧 token 全部作废；这种情形必须到服务端机器前，
   用本机浏览器打开 `http://127.0.0.1:<port>/`，取当前 token，再回客户端粘一次。
   没有远程捷径。所以别把「重启服务端」当随手动作：每次重启都会让已贴出去的 token 作废。

## 6 怎么用浏览器操作对端 DSH

链路通了以后，对端 DSH 就是一个普通网页。下面是实测可用的写法，与会话内容无关。

写入（给对端发消息）

1. 先确认受控标签页就是那个 `https://<机器名>.<tailnet>.ts.net/`，丢了就重新挂上；
2. 重新取一次页面快照，找到输入框；把文本逐字键入，直接注入剪贴板粘不进去；
3. 点「发送消息」；若 composer 里已有排队文本，按钮会显示为「排队发送」；
4. 判据：按钮变成「停止生成」= 已发出；回到「发送消息」= 那一轮跑完了。

两个已知坑：新建会话页面的输入框键入后发送按钮仍是禁用状态，那是启动器组件，
协商要在已有会话里做；对端生成中再发一条会显示「排队发送」，
等它当前轮结束才处理。

读取（拿对端的完整回复）：网页读不全，走导出

页面文本只能拿到前 ~8.4 KB，这是实测值，长会话的最新回复永远在截断之外；
`selector` 也只取第一个匹配，定位不到「最后一条消息」。可行通道是导出会话日志：

1. 对端会话页 →「更多操作」→「下载 Session 日志」，这是实测最可靠的对端 UI 操作入口；
2. 浏览器把它下到当前用户的下载目录，文件名形如 `dsh-session-session-<id>.zip`；
3. 解压得到 `session.v3.jsonl`，每行一个事件，例如 `user/message`、`assistant/message`、
   `tool/call`、`turn/end`；
4. 取结论时按时间顺序找最后一条助手消息，只读它的 `text` 内容区块；
   工具写入的文件原文在 `tool/call` 的 `arguments` 里。

```powershell
$zip = Get-ChildItem $env:USERPROFILE\Downloads -Filter 'dsh-session-session-*.zip' |
       Sort-Object LastWriteTime -Descending | Select-Object -First 1
Expand-Archive $zip.FullName -DestinationPath <解压目录> -Force
$lines = [IO.File]::ReadAllLines((Join-Path <解压目录> 'session.v3.jsonl'), [Text.Encoding]::UTF8)
$o = $lines[-1] | ConvertFrom-Json
$o.data.message.content | Where-Object { $_.type -eq 'text' } | ForEach-Object { $_.text }
```

下载目录要全列：同一会话可能导出多份，文件名会带 `(1)`、`(2)` 后缀，
先比大小与时间再取，别只看排在最前面的那个。

还要知道的三件事：① 下载可能被浏览器扣成「未确认」的临时文件而不产出新文件，
这时需要用户在下载栏点一次「保留」再重试；② 页面里的「复制」按钮点击返回成功，
但内容不会真的进剪贴板，它需要文档焦点，别指望「点复制 + 读剪贴板」；
③ 「在新对话中分支」与「打开文件」卡片都绕不开上面那 8.4 KB 的截断。
实在拿不到时，让对端把结论写成文件、由用户取回。

## 7 验收（三态 + windowed soak）

对服务端做原始 TCP 三态，只看三件事：

- `connected`：链路通，随后应能拿到 401 或 303、200。
- `refused`：链路通，但对端没有监听，也就是 serve 挂了。
- `timeout`：包被丢，可能是会话状态、策略或传输问题，走第 8 节。

退出码与脚本 summary 的读法：

- 0 全通：443 connected，且隔离口全部 timeout。
- 1 降级：443 connected，但隔离口也 connected，说明 ACL 没生效、链路本身是通的。
- 2 阻断：443 refused、timeout、出错，或参数非法。

配套：

- 隔离验证：同轮探非 443 端口，建议 135 或 5357，期望 timeout；
  反向 ping 不通是单向 ACL 的预期结果。
- HTTPS 与证书：期望 401，这是未带 token 时的正常响应；证书校验通过，
  证明用的是 Tailscale 公共证书，不需要装任何 CA。
- soak：连续探多次，例如 30 秒一次、共 11 次；结论必须限定窗口，
  例如「该 5 分钟窗口内 11/11 connected」。不要写成「链路稳定」，
  单次或短窗通过不能排除间歇性故障。
- 不要拿 `curl` 的失败推断对端状态：受限上下文里本机 TLS 栈会失败，
  报 `SEC_E_NO_CREDENTIALS` 或返回 `000`，握手根本没发生；
  那是本机环境限制，不是对端应用层挂了。

## 8 故障速查（固定顺序，不要跳步）

| 步 | 动作 | 判据 |
| --- | --- | --- |
| 1 | 客户端对服务端 443 做原始 TCP，拿三态 | 三态决定走哪条路 |
| 2 | 服务端在同一时间窗看守 `netstat -ano` 与客户端地址 | 0 命中 ⇒ 包没进服务端 TCP 栈 |
| 3 | 两端各重启 tailscaled：`Restart-Service Tailscale -Force` | 这类症状的第一反应 |
| 4 | 读服务端实际装载的策略：`tailscale debug netmap` | 排除「保存了但没下发」 |
| 5 | 服务端 OS 防火墙与网卡归属哪个 profile | 网卡 profile 是否开启、有无窄放行 |
| 6 | 才轮到中继：DERP 区域、`direct connection not established` | 中继可用但慢是正常 |
| 7 | 复核 Host 栅栏，界面能开但 `/api` 403 时 | `trustedHosts` 是否含该域名 |

最常见的真因：某一端的 tailscaled 会话状态失效。症状是客户端所有端口一起超时、
而服务端 `netstat` 里完全看不到客户端的包；客户端自己重启无效，
服务端重启一次常常就全通。这一类不要去改 ACL、不要去查 OS 防火墙，先按第 3 步。

两种静默失效，改配置时最容易踩，症状都出现在客户端：

- serve 换过端口，窄 ACL 还写死 443：客户端全端口 timeout，服务端一切正常，
  重启 tailscaled 无效。修法是让 ACL 的端口与 `serve status` 的端口一致。
- `trustedHosts` 漏了该 ts.net 域名：界面能开，但目录选择器报错。
  修法见第 3.6 小节，补上后重启 DSH。

网卡归属：`netsh advfirewall monitor show currentprofile` 非提权即可读，
看 Tailscale 网卡落在哪一段。若被归为 `Public`，Tailscale 自带那两条
`Tailscale-In` 规则只覆盖 `Domain,Private`，会因此不生效，链路静默失效。
这一条是从规则的 `Profiles` 字段推导出来的，公开机器上请自己复测一次，
别写成「已验证」。处置：把网卡归回 `Private`，或补一条窄入向放行，
参数是 tcp 443、远端 `100.64.0.0/10`、程序 `%ProgramFiles%\Tailscale\tailscaled.exe`：

```powershell
$rule = @{
  DisplayName   = 'DSH via Tailscale serve (tcp 443)'
  Direction     = 'Inbound'
  Action        = 'Allow'
  Protocol      = 'TCP'
  LocalPort     = 443
  RemoteAddress = '100.64.0.0/10'
  Program       = "$env:ProgramFiles\Tailscale\tailscaled.exe"
  Profile       = 'Any'
}
New-NetFirewallRule @rule
Remove-NetFirewallRule -DisplayName 'DSH via Tailscale serve (tcp 443)'   # 回滚
```

「查不到」不等于「不存在」：非提权下 `Get-NetFirewallRule`、`Get-NetFirewallProfile`
会拒绝访问；结构化探针也可能不报错地返回 0 行。这些一律落 `unknown`，
不得读成「没监听 / 无规则 / 未登录」。判命令成败用 PowerShell 的
`$LASTEXITCODE`，不要用 cmd 的 `%errorlevel%`：同一条命令实测 `$LASTEXITCODE=1`
而 `%errorlevel%=0`，会把失败读成成功。

收窄过加固项的机器：Tailscale 每次升级或服务重启后，复查要查的是
`Tailscale-Process` 这个进程级规则的 `Edge=` 落库值，不是命令回显；
也不要查 `Tailscale-In`，它本来就是 `Edge=No`，查错规则会得到「没有漂移」的假结论：

```powershell
reg query "HKLM\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\FirewallRules" /s | Select-String Edge=
```
