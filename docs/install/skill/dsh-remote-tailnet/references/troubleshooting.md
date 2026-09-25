# 链路故障速查(固定顺序 + 两端条目)

> 最后更新:2026-09-24 19:35(§1 第 2 条扩写:本机 TLS 栈失败被判成「对端 HTTP 层挂了」的实测误判,附原始报错;§2 第 3 条补 `serve` 的版本差异与两种回滚口径;§2 标题计数修正 8 → 13 条)。
> 本次使用的命令(只读):`Select-String` 核对本文件小节号;采集器命令见 §5(未跑,对端不可达)。

## 0. 固定排查顺序(不要跳步)

| 步 | 动作 | 判据 |
| --- | --- | --- |
| 1 | 客户端对 `server:443` 做原始 TCP,拿三态 | connected/refused/timeout 决定走哪条路 |
| 2 | 让服务端在**同一时间窗**看守:`netstat -ano \| findstr <client IP>` | 0 命中 ⇒ 包没进服务端 TCP 栈 |
| 3 | **重启两端 tailscaled**(`Restart-Service Tailscale -Force`,两端都要) | 这一类症状的第一反应,一次解决 |
| 4 | 读服务端实际装载的策略(`tailscale debug netmap` → PacketFilter) | 排除「控制台保存了但没下发」 |
| 5 | 服务端 OS 防火墙 / 网卡 profile | 网卡所在 profile 是否开启、是否有窄放行 |
| 6 | 才轮到中继:DERP 区域、`direct connection not established` | 中继可用但慢是正常 |
| 7 | 复核 Host 栅栏(能开界面但 /api 403) | 服务端 trustedHosts(含写法是否裸 `host[:port]`) |

## 1. 客户端视角(8 条)

1. **三态** —— `node net.Socket()` 连 443;timeout=被丢 / refused=无监听 / connected=通。永远先拿三态。
2. **本机 TLS 栈失败被误读成对端故障** —— 三种实测报错:`curl` 返回 `000`(`schannel: AcquireCredentialsHandle failed: SEC_E_NO_CREDENTIALS`,**握手根本没发生**)、`Invoke-WebRequest` 报「基础连接已经关闭:接收时发生错误」、.NET `SslStream` 报 `No credentials are available in the security package`。**这三条都是本机 TLS 栈在受限上下文(沙箱会话)里的失败,与对端无关。** ⚠️ **不得据此判「对端 HTTP/应用层挂了」或「要改 trustedHosts」** —— 本案就误判过一次:443 三态 connected、soak 4/4 全通,却被这条本地报错读成「对端 DSH 掐断了连接」。判对端 HTTP/应用层的**唯一可靠出处是浏览器**(它不在该受限上下文里;实测打开对端 ts.net 域名能加载 DSH 界面和会话内容),其次才是普通用户窗口里的 Node/OpenSSL 探针。
3. **浏览器超时但脚本通** —— 查 `HKCU:\...\Internet Settings` 的 ProxyEnable 与 clash 的 `enable_tun_mode`;加 ts.net / 100.64.0.0/10 直连规则。
4. **怀疑路由被抢** —— `route print -4 | Select-String '^\s+100\.'` 应有三条 /32 on-link;网卡 Up。
5. **不能跑 CLI 但想知道到中继通不通** —— `(Get-Process tailscaled).Id` + `netstat -ano | Select-String <PID>`;有 DERP ESTABLISHED 即为通(**只证明到中继**)。
6. **不确定对端是否收到** —— 让服务端同时间窗看守 netstat(400ms 采样);0 命中不排除 tailscaled 内部丢弃。
7. **要不要装 CA** —— Node https 带 `rejectUnauthorized:true` 打得通 ⇒ 公共证书,不需要 CA。
8. **别急着收工** —— 跑 soak;结论限定窗口。

## 2. 服务端视角(13 条)

1. **对端报「所有端口一起超时」,netstat 里完全没有对端的包** —— 先重启两端 tailscaled;不是先查策略。⚠️ tailscaled 内部被丢的包同样不留记录,所以这一步是「先重启」而不是「先证明」。
2. **`tailscale` 子命令一律 Access is denied** —— 沙箱碰不到命名管道(`ProtectedPrefix\Administrators\...`),是设计边界,与链路无关;该命令只能由用户在普通窗口跑。
3. **怀疑 serve 挂了** —— `netstat -ano | Select-String ':443' | Select-String 'LISTENING'` 应有 `100.x:443 LISTENING`;不在就 `tailscale serve --bg 43120`。**版本差异(实测)**:`serve --bg` 成功后,**新版**会提示用 `tailscale serve --https=443 off` 关闭(窄:只撤这一个端口);**本机实测的 1.102.4 版** `serve --help` 的 USAGE 只有 `<target>` / `status` / `reset`,**没有 `off`**。⇒ 回滚口径:**版本支持就用窄的 `--https=443 off`,否则用 `tailscale serve reset`(语义 = 清空本机全部 serve 配置,范围更大但各版本都在)**。另外 `--bg` 必须带 —— 不带的话重启 / `tailscale up` 之后不会自动恢复。
4. **443 在 netstat 里抓不到命中** —— serve 由 tailscaled 终止 TLS 再转发,可能不经过 Windows TCP 栈;改看 `tailscale debug daemon-logs`。
5. **本机向对端探测必然全超时** —— 单向 ACL 的预期结果;不能拿 ping/单端口定罪。
6. **DSH 重启后 43120 还在不在** —— `netstat` 看 `127.0.0.1:43120 LISTENING` + 直接 TCP connect 期望 True;PID 会变,监听应重建。
7. **HTTPS/证书类判定** —— 服务端沙箱同样可能做不了 TLS;HTTPS 判定的唯一出处是**客户端的 Node/OpenSSL**。
8. **策略类改动的纪律** —— 每次只改一处、改前备份、改后读回实际装载值;不新增 `0.0.0.0` 监听,需要放行就同时给窄放行。
9. **退出码判定别用 cmd 的 `%errorlevel%`** —— 实测同一条 `tailscale ip -4`(打印 `Access is denied`、PowerShell 侧 `$LASTEXITCODE`=1)在 cmd 里 `%errorlevel%` 却是 **0**。判命令成败用 PowerShell 原生 `$LASTEXITCODE`,或 `Start-Process -Wait -PassThru` 的 `.ExitCode`;拿 cmd 的错误码会把失败读成成功。
10. **要证明「serve 是唯一入口」** —— `netstat -ano | findstr <port>` 应只见 `127.0.0.1:<port> LISTENING`;再看**入向连接(ESTABLISHED/TIME_WAIT)的 owner PID**:若指向 `tailscaled`,那就是 serve 把远端流量转发进本机 DSH 的活证据(实测 owner = tailscaled,DSH 自身 PID 只持有那条 loopback 监听)。
11. **「查不到」不等于「不存在」** —— 三种实测过的假阴性,一律落 `unknown(权限被拒/探针不可用)`,**不得**读成结论:① `Get-NetTCPConnection -LocalPort 43120` cmdlet 存在、不报错、**返回 0 行**(同刻 `netstat` 明明有监听行)⇒ 别据此说「没监听」;② `Get-NetFirewallRule` / `Get-NetFirewallProfile` 非提权**拒绝访问** ⇒ 别据此说「无规则/没开」;③ `tailscale status --json` 命名管道被拒 ⇒ 别据此说「未登录」。
12. **别用区域预判工具输出的语言** —— 本机 `Get-Culture = en-US`,但 `powercfg /getactivescheme` 的输出实测是**中文**(「电源方案 GUID: … (高性能)」)⇒ 解析本地化输出时要**同时接受中英两种**形态;匹配失败就走「无法判定」,**别当成「没配置」**。优先用结构化来源(`[Net.Sockets.TcpClient]` 真连、`netsh`、注册表落库值),必须解析文本时按上面处理。
13. **加固项要查对规则名** —— 漂移判据是 `Tailscale-Process` 的 `Edge=` 落库值(本机实测 `Edge=TRUE`);`Tailscale-In` 本机实测 `Edge=No`,查它会得出「没有漂移」的错结论(见 security.md §5.1)。

## 3. 两处静默失效(改配置时最容易踩,症状都出现在客户端)

| 静默失效 | 症状 | 判据 / 修法 |
| --- | --- | --- |
| **serve 端口变了,窄 ACL 还写死 443** | 客户端全端口 timeout;**服务端一切正常**(serve status 也是绿的);重启 tailscaled 无效 | 对比 ACL `dst` 里的端口 与 `serve status` 的 tailnet 端口,必须一致;要么改回 443,要么同步改 ACL |
| **trustedHosts 没含该 ts.net 域名** | 界面**能打开**,但目录选择器报错、客户端反复「自动重连中」、/api 403 | Host 栅栏只拦 `/api`,静态资源不校验 ⇒ 「能开界面」不代表配置对。补 `connection.trustedHosts` 后重启 DSH(写法必须带 `...ctx.webRuntime.trustedHosts`,entry 必须是裸 `host[:port]`,见 security.md §6) |
| **网卡归属被改成 Public** | 服务端侧 `serve` 一切正常、tailnet 侧也正常,客户端却连 443 都不通(或只有部分能通);重启 tailscaled 无效 | `netsh advfirewall monitor show currentprofile`(非提权可用)看 Tailscale 网卡归属。**[实测]** 本机 = Private;**[仅配置可推导]** 若为 Public,Tailscale 自带的 `Tailscale-In`(只覆盖 `Domain,Private`)不生效 ⇒ 静默失效。处置:归回 Private,或按 security.md §2 第 6 条补窄放行。⚠️ 未在 Public 机器上实测,报告里不得写成「已验证」 |

## 4. 本案真因(写在这里防止再走弯路)

**一端 tailscaled 会话状态失效**:客户端打服务端任意端口全部 timeout,且服务端 netstat 完全看不到客户端的包;
客户端重启无效,**服务端 `Restart-Service Tailscale -Force` 后一次全通**。
我们此前在 ACL 写法(grants → acls → IP 选择器)、IP 选择器是否生效、OS 防火墙、DERP 传输层上绕了数轮,全是真因之外。

## 5. 可选:把本页的判据机器化(只读)

本页与 verify.md 里的判据(443 三态、隔离、`serve` 目标口、DSH 只绑 loopback、`Tailscale-Process` 的 `Edge=` 落库值、网卡归属、电源 AC/DC、`trustedHosts`)可由采集器一次跑完,给四态 + 退出码 0/1/2:

    powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/src/collect.ps1 -CheckOnly -Role client -Peer <对端 100.x> -PeerName <机器名>.<tailnet>.ts.net

- 它**只读**:不新增监听、不改配置、不读凭据;`-Apply` 会被拒绝(exit 2)。
- **`unknown` 不是故障**:命名管道被拒、结构化探针返回 0 行、状态词读不出 —— 一律落 `unknown`(见 §2 第 11 条)。整片 `unknown` 时先按 §0 的固定顺序人工排一遍,不要据此断定「链路挂了」。
- 结论冲突时,以本页的**原始 TCP 三态**为准:采集器只是同一判据的机器化,不替代人工判读,也不改变本 skill 只写这一条已跑通路径的边界。
