# 验收与巡检(可直接跑)

> 最后更新:2026-09-26(t4 集成同步:§0.1 的 `ego_*` 行按实测收窄为「轻量查询可用 + 默认 120 s 上限 + 全串行」并删掉过期的「曾 120 秒超时」断言;§0.1 的 ICMP 行与 §3 的反向 ping 断言去掉绝对口径;**小节编号未变**,§1/§2/§4–§7 内容未动)。上一版:2026-09-24 18:29(t9 巡检同步:新增 §7「用采集器把同一批判据机器化」;§0–§6 未改语义)。
> 本次使用的命令(只读):`powershell -NoProfile -ExecutionPolicy Bypass -File .dsh/skills/dsh-remote-tailnet/scripts/verify.ps1 -ServerIp <PEER_IP>`(对端当前不可达 ⇒ EXIT 2 阻断,见 §7 末);`Select-String` 核对本文件小节号唯一。

## 0. 怎么跑:本机默认 ExecutionPolicy = Restricted

裸 `.\verify.ps1` 会被拒(实测原文:`cannot be loaded because running scripts is disabled on this system`,PSSecurityException / UnauthorizedAccess)。一律用下面这种**不改任何策略设置、只对子进程生效**的形态:

    powershell -NoProfile -ExecutionPolicy Bypass -File .dsh/skills/dsh-remote-tailnet/scripts/verify.ps1 -ServerIp <PEER_IP>
    powershell -NoProfile -ExecutionPolicy Bypass -File .dsh/skills/dsh-remote-tailnet/scripts/verify.ps1 -ServerIp <PEER_IP> -Soak -Count 11 -IntervalSeconds 30

下文所有 `scripts/verify.ps1 …` 都指上面这条完整形态的尾部。

## 0.1 探针能力表:按「用哪个探针」归因,不按「哪一端」

**同一个探测命令在不同的「探针」下能得出什么结论是不一样的。** 没有这张表,就会把「环境限制」当成「链路证据」(本案踩过:服务端的 TLS 不可用曾被误读成 HTTPS 结论)。

| 探针 | 实测行为 | 能不能当证据 |
| --- | --- | --- |
| **`[Net.Sockets.TcpClient]`(原始 TCP 三态)** | 两端都能跑;纯 .NET,不依赖 node / 证书 / 命名管道 | ✅ **唯一两端对称、任何时候都能用的探针**;三态判定的唯一合格出处 |
| **Node / OpenSSL(TLS、HTTPS、证书)** | 本机 `node` **不在 PATH**(`where.exe node` / `node --version` 三路全失败)。可行替代:**`$env:ELECTRON_RUN_AS_NODE=1` + `'<APP_DIR>\DSH Desktop.exe' <script.js>`** —— 实测 `node=v24.18.1`,`zlib.createZstdDecompress` 存在(含 zstd);启动时 stderr 会有一行 crashpad `CreateFile: 拒绝访问 (0x5)`,无害 | ✅ HTTPS/证书判定的权威出处(OpenSSL 实现)。⚠️ 必须显式用 Electron-as-Node 或真正的 node,否则「跑不出结果」只是没有 node,不是链路问题 |
| **schannel(`curl.exe` / .NET 默认 TLS)** | 受限上下文报 `SEC_E_NO_CREDENTIALS` / “No credentials are available in the security package”,`curl` 返回 `000`。**客户端 agent shell 同样报这个** | ❌ 不能用来判定对端状态。schannel 与 OpenSSL 是两套独立实现:schannel 失败 **≠** TLS 目标不可达 |
| **`tailscale` CLI** | 除 `version`(只读二进制自述、不碰守护进程)外,`ip` / `status` / `serve status` 都要走 `\\.\pipe\ProtectedPrefix\Administrators\Tailscale\tailscaled` ⇒ 受限上下文一律 `Access is denied`,exit=1。两端同 | ⚠️ 只能由用户在**普通窗口**跑;看 `version` 的 exit=0 会把「CLI 不可用」误判成可用 |
| **ICMP ping** | 通/不通取决于 policy 写法与方向:窄单向 ACL 下「某一对 IP 之间只要有任何规则放行,**ICMP 也会被放行**」⇒ 客户端 → 服务端**可能通**、反向通常不通 | ❌ 不构成链路证据(通与不通都不说明 443 的状态);判定一律用 TCP 三态(§1) |
| **CIM / WMI** | 部分被拒(本机 `Get-NetFirewallProfile`、`Get-NetFirewallRule`、`Get-NetConnectionProfile` 实测**拒绝访问**) | ⚠️ 被拒时换注册表 / `netsh` 等非提权通路,不要拿「被拒」当结论 |
| **结构化探针也会「假阴性」** | `Get-NetTCPConnection -LocalPort 43120` **cmdlet 存在、不报错、但返回 0 行**(实测;同刻 `netstat` 明确有监听行);`Get-NetFirewallRule` 非提权「拒绝访问」;`tailscale status --json` 命名管道被拒 | ❗ 这三种一律落 **unknown(权限被拒/探针不可用)**,**不得**被读成「未登录 / 没监听 / 无规则」。判「有没有监听」用 `[Net.Sockets.TcpClient]` 真连一次 + `netstat` 的**行结构**(远端列 = `0.0.0.0:0` 才是监听行,不看状态词) |
| **`netsh`(防火墙 / 网卡归属)** | `netsh advfirewall show allprofiles`、`netsh advfirewall firewall show rule … verbose`、`netsh advfirewall monitor show currentprofile` 实测 **exit=0,非提权可用** | ✅ 加固项与「网卡归属哪个 profile」的首选探针(命令回显仍要与注册表落库值互证,见 §5) |
| **浏览器 `ego_*` 桥** | 只适合轻量查询:`ego_status` / `ego_doctor` **实测能跑**;**单次 tool call 默认 120 s 上限,且全部 `ego_*` 串行**(进程内互斥锁,并发会排队) | ❌ 探针/验收**不要依赖**它;跨网浏览器操作一律用 DSH 自带 `browser_*`(首选;完整选型见 browser-control.md §0) |

⇒ 分工固化:**HTTPS/证书 → 只在能跑到 OpenSSL 的那一端判(本机 = Electron-as-Node);TCP 三态 → 两端都能做;`serve status` / `tailscale ip` → 只在用户普通窗口做;防火墙与网卡归属 → `netsh`(非提权)。**

## 1. 三态探测(核心判据)与退出码

对 `<server 100.x>:443` 做**原始 TCP** 连接,只看三态:

- `connected` = 链路通(随后应能拿到 401/303/200);
- `refused` = 链路通但**对端没有监听**(serve 挂了);
- `timeout` = 包被丢(会话/策略/传输)—— 见 troubleshooting.md。

脚本:`scripts/verify.ps1 -ServerIp <100.x>`(内部纯 `[Net.Sockets.TcpClient]`;不用 curl —— 见 §0.1)
`-Ports` 探多个口时必须用逗号或加引号(`-Ports 135,5357` / `-Ports '135 5357'`);写成 `-Ports 135 5357` 时第二个值会被绑到 `-LinkPort` ⇒ 脚本直接报「未探测 -LinkPort」并 EXIT 2,**不会静默少探**。

**退出码(实测,不再是恒 0)**:

| 码 | 含义 | 触发条件 |
| --- | --- | --- |
| 0 | 全通 | 443 connected 且 135/5357 等隔离口全部 timeout;soak 全 connected |
| 1 | 降级 | 443 connected,但隔离口也 connected ⇒ ACL 没生效(链路本身是通的) |
| 2 | 阻断 | 443 refused/timeout/出错;soak 全失败;参数非法 |

脚本末行会打印 `VERDICT …` 与 `EXIT <码>`,可直接当机器的判据。

## 2. HTTPS 探测与证书

用 **OpenSSL 实现**的探针(本机 = Electron-as-Node):

    powershell -NoProfile -Command "$env:ELECTRON_RUN_AS_NODE=1; & '<APP_DIR>\DSH Desktop.exe' -e ""const https=require('https');https.request({host:'<server 100.x>',port:443,servername:'<ts.net 域名>',path:'/',headers:{Host:'<ts.net 域名>'},rejectUnauthorized:true},r=>{console.log(r.statusCode);process.exit(0)}).on('error',e=>{console.log('ERR',e.message);process.exit(1)}).end()"""

（脚本内容与下面等价:）

    Node: https.request({ host:'<server 100.x>', port:443, servername:'<ts.net 域名>', headers:{ Host:'<ts.net 域名>' }, rejectUnauthorized:true })

期望 **401**(未带 token 时的正常响应),并且**证书校验通过**(证明是 Tailscale 公共证书,不需要装 CA)。
⚠️ Windows 上 `curl.exe` 走 schannel,受限环境做不了 TLS(返回 000)——**不要用 curl 的失败推断服务端状态**,HTTPS 判定一律用 OpenSSL 实现的探针。

## 3. 隔离验证(证明 ACL 生效)

同轮探测非 443 端口(建议 **135 / 5357**,避开我们加固过的 139/445,便于区分是哪一层在拦):期望 **timeout**。
反向(`server → client`)在窄单向 ACL 下通常 **ping 不通** —— 这是 policy 的预期结果,不是故障;但 ICMP 通不通取决于 policy 写法与方向,**不作链路证据**(见 §0.1)。

## 4. soak 巡检

    scripts/verify.ps1 -ServerIp <100.x> -Soak -Count 11 -IntervalSeconds 30

**结论表述必须限定窗口**,例如:「该 5 分钟窗口内 11/11 connected,191–206ms」。
不要写成「链路稳定」——单次或短窗通过不能排除间歇性故障(本案真凶正是「3 分钟内由通变断」)。
soak 退出码:全 connected = 0;部分失败 = 1;全失败 = 2。

## 5. 巡检判据:一律用实测,别读配置

- `dsh-desktop.port` 通常**不存在于** `settings.yaml`(走 schema 默认 43120)⇒ 判定「端口没被改」必须用 `netstat` 看 `127.0.0.1:43120 LISTENING`,**不能读配置文件**;
- 「serve 还活着」也同理:用 `tailscale serve status` 的 proxy 目标 + `100.x:443 LISTENING` 两条一起判;
- 「加固还在不在」用落库值(`netsh … verbose` / 注册表 `Edge=`),不要用命令回显;
- 「加固查的是哪一条规则」:`Tailscale-Process`(**进程级**;本机实测 `Edge=TRUE`),**不是** `Tailscale-In`(本机两条 `Edge=No`)。查错规则会得到「没有漂移」的假结论:

      netsh advfirewall firewall show rule name="Tailscale-Process" verbose
      reg query "HKLM\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\FirewallRules" /s | Select-String Edge=

- 「网卡归属哪个 profile」(决定 Tailscale 自带规则生效不生效):

      netsh advfirewall monitor show currentprofile      # exit=0,非提权;本机 Tailscale 网卡实测 = Private

  ⚠️ 证据等级:`本机 Tailscale 网卡 = Private` 是 **[实测]**;`归为 Public 会让 Tailscale-In(Profiles=Domain,Private)不生效 ⇒ 静默失效` 是 **[仅配置可推导]**(从规则的 Profiles 字段推出),**尚未在 Public 归属的机器上实测**。要坐实需在 Public 机器上复测,或对照 `tailscale debug netmap`。详见 security.md §5.5 与 troubleshooting.md §3。
- 结论表述限定窗口(soak 模板见 §4)。

## 6. 一次性验收清单

- [ ] 三态:443 = connected(脚本退出码 0 或 1;仅 1 表示链路通但隔离失效);
- [ ] HTTPS:401 + 证书校验通过(OpenSSL 探针;schannel 的 000 不算);
- [ ] 隔离:135/5357 = timeout;反向 ping 不通(预期);
- [ ] 客户端浏览器:带 token 打开一次后可正常使用(30 天 cookie;见 client-setup.md §3 的续期/锁死路径);
- [ ] soak:窗口内无失败,结论已限定窗口;
- [ ] **ACL 端口 vs serve 端口一致**(窄 ACL 写死 `server:443`;serve 一旦换端口,链路会静默断开而服务端一切正常);
- [ ] 无新增 `0.0.0.0` 监听(`netstat` 里 DSH 端口只应出现在 `127.0.0.1`);
- [ ] 加固未漂移:`Tailscale-Process` 的 `Edge=` 落库值仍为 `FALSE`(不是看 `Tailscale-In`);
- [ ] 网卡归属:`netsh advfirewall monitor show currentprofile` 里 Tailscale 网卡不是 Public(本机实测 Private;若是 Public 要查是否 Tailscale 规则失效);
- [ ] 服务端:`serve status` 正常、`dsh-desktop.port` 未变、电源策略已改(AC 与 DC 分别确认,见 server-setup.md §8,核验判据见其 §8.2);

## 7. 可选:用采集器把同一批判据机器化(只读)

`dsh-crossnet-link/src/collect.ps1` 把本文件的巡检项实现成同一批判据,输出四态 `pass`/`degraded`/`blocked`/`unknown` 与退出码 0/1/2(**`unknown` 不计入 pass,fail-closed**)。它只读:不新增监听、不改配置、不读凭据,`-Apply` 会被直接拒绝。**它不替代本文件的人工判读**:结论冲突时,以本文件的原始 TCP 三态 + 限定窗口为准。

    powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/src/collect.ps1 -CheckOnly
    powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/src/collect.ps1 -CheckOnly -Role client -Peer <对端 100.x> -PeerName <机器名>.<tailnet>.ts.net

判据对照(本文件 → 采集器 id),差别写在第三列:

| 本文件巡检项 | 采集器 id | 要说清的差别 |
| --- | --- | --- |
| 443 三态(§1)、隔离(§3) | `PEER_TCP_443`、`PEER_ISOLATION_PROBES` | 同一 `[Net.Sockets.TcpClient]` 判据;不给 `-Peer` 时是 `unknown`(`peer_not_provided`),不是故障 |
| serve 还在不在(§5) | `SERVE_PRESENT` | 证据**只**取自可读的 `tailscale serve status` proxy 目标口;读不出 ⇒ `unknown`;`netstat` 形状只作佐证 |
| DSH 端口只绑 loopback(§5/§6) | `DSH_LOOPBACK_ONLY`、`NO_NEW_WILDCARD_LISTENER` | 后者是「运行前后通配监听集合一致」的自证;探针不可用 ⇒ `unknown`,不写成「没监听」 |
| 加固漂移(§5) | `TAILSCALE_PROCESS_EDGE_DB` | 只看 `Tailscale-Process` 的 `Edge=` **落库值**;`Tailscale-In` 是另一个 id(它 `Edge=No` 属正常) |
| 网卡归属(§5/§6) | `NIC_PROFILE_ATTRIBUTION` | 枚举源 ⇒ pass(`confidence: high`);本地化文本路径 ⇒ **degraded**(`confidence: low`);读不出 ⇒ `unknown` |
| 电源 AC/DC(server-setup.md §8) | `POWER_STANDBY_IDLE_AC_DC` | AC=DC=0 ⇒ pass;DC≠0 ⇒ degraded(电池下必断) |
| Host 栅栏(§6) | `TRUSTED_HOSTS_PATCH` | 读**实际装载**的 patch;空/缺 ⇒ blocked(远端 `/api` 403) |
| HTTPS/证书(§2) | `HTTPS_CLIENT_ONLY` | 只有能跑 OpenSSL 探针的那一端能判;schannel 的 `000` 不是证据(§0.1) |

> 纪律不变:插件/采集器只把**判定**交给你,三态与 soak 的结论仍按 §1/§4 的窗口口径自己写;不要把 `unknown` 写成「没配置」,也不要把面板上的一行当成链路验收。对端当前不可达时,第 1/3/4/5 项照旧可跑,涉及对端的项会如实落 `unknown` 或 `timeout`。
