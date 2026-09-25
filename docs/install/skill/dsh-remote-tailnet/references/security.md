# 安全:威胁模型、预防、回滚

> 最后更新:2026-09-24(W4 + t18)。t18 修订:§7 回滚第 2 步改为 `tailscale serve reset` 并写明语义;新增 §4.1「撤销的实际操作顺序」。本次使用的命令见 `README.md` 的「本次修订」。
> 本文里带 `dsh-client-connection/lib/index.js:NNN` 的行号 = 本机 `<APP_DIR>\resources\app\node_modules\@deepseek-ai\` 下的实际源码,可逐条复核。

## 1. 谁会看到什么

| 角色 | 能看到 | 看不到 |
| --- | --- | --- |
| Tailscale 控制面 | 设备名、100.x 地址、在线时间、互通关系(元数据) | 内容(WireGuard 端到端) |
| DERP 中继 | 密文与连接元数据 | 内容 |
| tailnet 内其他设备 | 默认 ACL 下**全通**;能否进 DSH 仍取决于是否有 token/cookie | — |
| 拿到带 token URL 的人 | 可直接进入服务端 DSH 界面 | — |
| 服务端本机其他用户/程序 | 能读 profile 凭据或浏览器 cookie 者可冒充 | — |
| 客户端被入侵 | 等于能以客户端身份操作服务端 DSH | — |

**最关键的一句话**:这条链路的价值与风险是同一个东西 —— 「能打开服务端 DSH」就等于「能操作那台机器」。
所以第一优先级不是“把链路打通”,而是**把服务端 DSH 的默认权限与 tailnet 成员范围收好**。

## 2. 预防清单(按优先级)

1. **服务端 DSH 默认权限 = workspace-write**(不能用 danger-full-access)。核查方式:新开一个会话,看它的 sandbox/approval(运行时事实,不看配置文件)。
2. **tailnet 最小成员**:控制台设备列表只保留需要的两台;账号开二次验证(账号被拿走 = 能把新设备加进来)。
3. **ACL 收紧到 IP 级单向 443**:`{"acls":[{"action":"accept","src":["<client>/32"],"dst":["<server>/32:443"]}]}`。
   注意:ACL 的 selector 支持 users/groups/tags/autogroups/**IP/CIDR**;设备名不能当 selector。
   副作用:ICMP 与其他端口会被拒 —— **这是预期**,不要拿 ping 当链路证据。
4. **凭据纪律**:带 token 的 URL 只在用户自己机器的地址栏粘贴一次;**不进入任何会经模型 API/日志/传输通道的地方**(包括 agent 对话、聊天、工单、网盘)。
   一旦原文出机:唯一正确处置是**撤销该凭据**,精确落点见 §4。
5. **不要开 `networkExposure: lan`**:serve 方案不需要它;开了等于把服务端 DSH 暴露给它所在的每个网络(局域网/热点/VPN)。
6. **服务端防火墙**:唯一相关入站是 tailscaled 的 tailnet 侧 443(仅 tailnet 可达);若所在网卡 profile 处于开启状态,需一条窄放行(程序=tailscaled.exe、远端=100.64.0.0/10、端口=443)。
7. **既有暴露面显式登记**:SMB/NetBIOS(139/445/137/138)建议阻断;**服务端本机既有的整机远程控制类工具**登记为「已知的整机远控通道」(本 skill 不使用这类工具,只要求把它登记清楚);用户可写目录 + LocalSystem 服务 = 提权链,建议收紧目录 ACL。
8. **Tailscale 自带防火墙规则**:要收的是 **`Tailscale-Process`(进程级;本机实测 `Edge=TRUE`)**,建议去掉 Edge traversal;注意 **MSI 升级或服务重启后可能被重建**,升级后要复查。
   ⚠️ **不是 `Tailscale-In`** —— 本机实测那两条是 `Edge=No`、`Profiles=Domain,Private`、`LocalIP: <服务端 100.x>/32`;只查它会得到「没有漂移」的错结论。查询命令与判据见 verify.md §5。

## 3. 已知失败模式与预防(本案踩过的)

| 失败模式 | 症状 | 预防/处置 |
| --- | --- | --- |
| 一端 tailscaled 会话失效 | 客户端全端口 timeout;**服务端 netstat 完全看不到包** | **先重启两端 tailscaled**,再谈策略 |
| Host 信任栅栏 | 远端 Web 能开,但 `/api` 403(目录选择器报错、反复“自动重连中”) | 按 §6 追加 `connection.trustedHosts` + 重启 DSH |
| serve 未带 `--bg` | 机器重启后链路静默消失 | 只用 `serve --bg`;巡检 `tailscale serve status` |
| `dsh-desktop.port` 被改 | serve 指向空气 | 保持 43120;改了要重跑 serve |
| 笔记本睡眠 | 整条链路离线 | 电源策略设不休眠/合盖不睡眠(AC/DC 都要) |
| 误用 ping 判定 | 把“单向 ACL 的正常超时”当成“对端掉线” | 判定一律用真实端口(TCP connect)三态 |
| 探针不对称 | 把环境限制(TLS 不可用 / node 不在 PATH)当成链路证据 | 交叉验证前先声明探针能力(verify.md §0.1) |
| 30 天 cookie 到期 + 服务端已重启 | 客户端打不开界面,且**旧的 launch token 已失效**(token 每进程随机) | 见 client-setup.md §3 的续期/锁死路径;**唯一出路是到服务端机器前取新 token** |

## 4. 凭据生命周期与撤销(精确落点)

三种东西的生命周期完全不同,**别混为一谈**:

| 凭据 | 寿命 | 撤销落点(精确) |
| --- | --- | --- |
| 带 token 的 URL 里的 **launch token** | **每个进程一个**:`processLaunchToken` 用 `randomBytes(32)` 生成、存在进程内 `WeakMap` 里(`dsh-client-connection/lib/index.js:227`、`:240-246`)⇒ **DSH 一重启就换新的** | 重启 DSH 即作废(旧的立刻不可用);手动重置也只影响这一个进程 |
| 浏览器 **会话 cookie**(`dsh-auth-<authority>`) | **绝对 30 天**:默认 `cookieMaxAgeDays: z.natural().min(1).default(30)`(`:740`、`:753`);cookie 里 `expiresAt = issuedAt + 30 天`(`:392-406`);校验只看 `payload.expiresAt > now`(`:431-441`)⇒ **不因使用而续期** | ① 客户端**清掉该站点 cookie**(或换 profile);② 让服务端那条签名 secret 失效 —— 见下 |
| 签 cookie 的 **签名 secret** | **持久化**:存在 credentials 里,键 = `credentialKey("client-connection", "browser-session")`(`:219`),由 `initializeSecret` 用 `credentials.modifyRecord` 写入一条 `kind: "grant"` 记录(`:321-338`),每条 32 字节随机 | **删掉 credentials 里 `client-connection` 的 `browser-session` 记录**,再重启 DSH 让它重新生成 ⇒ 所有已发出的 cookie 立即验签失败 |

**两条最容易搞错的结论**:

1. **仅重启 DSH 不会让已发出的 cookie 失效** —— 重启换掉的是 launch token;签名 secret 是持久化的,`initializeSecret` 会读回同一条记录(`:326-330`),所以只要 cookie 未到期、`authority`(host:port)没变,继续有效。要作废必须动 §4 表第 3 行那条记录(或清客户端 cookie)。
2. **cookie 绑 `authority` = 浏览器请求里的 `host:port`**(`:252-261`、`:438`)。**改了入口域名或端口,旧 cookie 直接失效** —— 这是迁移/改端口时的隐藏代价。

### 4.1 撤销的实际操作顺序(插件/自动化读者看这一节)

1. **客户端**:清掉该站点 cookie(`dsh-auth-<authority>`);不确定就换一个浏览器 profile;
2. **服务端**:删掉 credentials 里 `client-connection` 的 `browser-session` 那条记录 —— 文件落点 = `$DSH_HOME\.credentials.yaml`(源码依据:`dsh-credentials-local/lib/index.js:13,18,49,58`,原文「File-backed credentials provider over `$DSH_HOME/.credentials.yaml`」;本机 `DSH_HOME=%USERPROFILE%\.dsh` ⇒ `%USERPROFILE%\.dsh\.credentials.yaml`)。**先备份整个文件,只删那一条记录,并且不要 `cat` 出来**(文件里还有别的凭据原文);
3. **服务端**:用自带入口重启 DSH(设置 → 桌面/Desktop → 「重启 ▾」⇒ 重启)⇒ 重新生成签名 secret ⇒ 所有已发出的 cookie 立即验签失败。

⚠️ 两条最容易搞混的边界(写报告/写插件提示语时照抄):

- `tailscale serve reset` 撤的是**对外入口**,**不碰任何凭据**;凭据撤销只有上面 2+3 两步;
- **仅重启 DSH 不会让已发出的 cookie 失效**(重启换掉的是每进程随机的 launch token;签名 secret 是持久化的,`initializeSecret` 会读回 §4 表第 3 行那条记录)⇒ 想让 30 天 cookie 立刻作废,**必须**动那条记录。

## 5. 加固漂移与巡检项(本案实测暴露出来的)

这些项的共同点是:**判据必须是一手落库值,不是命令回显**(对 §5.5 是「必须看清证据等级」)。

### 5.1 `Tailscale-Process` 的 Edge traversal 会漂移

- 现象:收窄为 `No` 后,某次 MSI 升级/服务重启后变回 `Yes`(且台账仍记着 No);
- **要查的规则是 `Tailscale-Process`(进程级)**,本机实测 `Edge=TRUE`;`Tailscale-In`(本机实测 `Edge=No`)查不出漂移 ⇒ 先 grep 再断言;
- 复核要用**落库值**(不被显示层误读):

      netsh advfirewall firewall show rule name="Tailscale-Process" verbose
      reg query "HKLM\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\FirewallRules" /s | Select-String Edge=

  注册表这条路**非提权可读**(本机实测;键 `{A3F28CE2-C510-4837-AEF0-E35F746000AC}` 那次命中 3 条含 Tailscale 的规则);
- 收窄:`Set-NetFirewallRule -DisplayName 'Tailscale-Process' -EdgeTraversalPolicy Block`;回滚:`Allow`;
- 风险量级(别过度渲染):该规则是**程序级 + UDP + LocalPort Any**,Edge traversal 影响的是 Teredo/IPv6 过渡入站,并非开放端口;但它是「已登记的加固项在漂移」,属纪律问题;
- 因此:**Tailscale 每次升级/服务重启后都要复查这一条**。

### 5.2 ACL 钉死在 443 ⇒ serve 端口一变,ACL 静默失效

- ACL 放的是「客户端 → 服务端 **tcp:443**」;若有人跑 `tailscale serve --bg <其它端口>`,443 监听消失、ACL 不再匹配任何东西,**控制面不会报错**;
- 巡检判据(两条一起看):`tailscale serve status` 的 proxy 目标仍是 `http://127.0.0.1:43120` **且** `netstat` 里 `100.x:443 LISTENING`;
- 这条应与「`serve --bg` 常开」合并为同一条巡检。

### 5.3 电源前提要精确到 AC/DC

- `powercfg /query STANDBYIDLE`:AC=0(永不)、DC=3600s 是常见默认;
- 转电池后进入 S0 现代待机会**断开网络**(`powercfg /a` 会写明) ⇒ tailnet 必然离线,症状 = 对端所有端口一起超时;
- 所以交付口径应写「**插电时不休眠;用电池时 1 小时进待机,链路会断**」,而不是笼统的「已设置为不休眠」。

### 5.4 备份/回滚陷阱

- 若 profile 的 `cordis.patch.yml.bak-*` 是**改前的空 patch**(内容为 `[]`),拿它回滚会**删掉整段预设**(不只是回退某一项);
- 回滚前先看备份内容,别只看文件名。

### 5.5 网卡归属哪个 profile —— 新的静默失效点

- 判据:**`netsh advfirewall monitor show currentprofile`**(本机实测 **exit=0,非提权可用**;这是本机唯一可得的「网卡 → Domain/Private/Public」判据 —— `Get-NetConnectionProfile`、`NetworkList\Profiles`、`Signatures\Unmanaged` 三条路在本机均不可用);
- **[实测]** 本机 Tailscale 网卡归为 **Private**;
- **[仅配置可推导]** Tailscale 自带的 `Tailscale-In` 规则只覆盖 `Profiles=Domain,Private`。**若 Tailscale 网卡被归为 Public,这些自带规则就不生效**,而 `tailscale serve` / tailnet 侧一切正常 ⇒ **静默失效**(症状会伪装成「ACL 或防火墙把包丢了」);
- ⚠️ **证据等级必须保留**:「本机 = Private」是实测;**「Public 会失效」是从规则的 `Profiles` 字段推出来的,尚未在 Public 归属的机器上实测**。写报告时不得写成「已验证」;要坐实需在 Public 归属的机器上复测,或对照 `tailscale debug netmap`;
- 处置:若发现 Tailscale 网卡是 Public,优先把它归回 Private;做不到就按 §2 第 6 条补一条**窄放行**(程序=tailscaled.exe、远端=100.64.0.0/10、端口=443)。

## 6. 配置写法:`connection.trustedHosts` 的规范形态

### 6.1 写哪一行、写成什么

profile(`%USERPROFILE%\.dsh\profiles\<profile>\cordis.patch.yml`)里追加:

    - id: connection
      name: '@deepseek-ai/dsh-client-connection'
      config:
        trustedHosts: ['<机器名>.<tailnet>.ts.net', ...ctx.webRuntime.trustedHosts]

**为什么必须带 `...ctx.webRuntime.trustedHosts`**:patch 的 config 是**整行覆盖**语义 —— 你写什么,这一行的 config 就是什么。只写一个 ts.net 字面量,等于把运行时派生出来的那些 LAN 字面量**静默丢掉**(`dsh-client-connection/lib/index.js:134`:Host 栅栏接受 loopback、**deployment-derived LAN IP literals**、以及声明过的 `trustedHosts` 三类)。
今天这么写**不会**打断本机访问:**loopback 是内建短路放行的**(`isTrustedApiRequest` 在 `:206` 先判 `isLoopbackHostname` ⇒ 命中就直接通过,不看 `trustedHosts`)。所以「本机能开」不能证明这行写对了 —— 丢掉的只是派生字面量。

### 6.2 ⚠️ 每个 entry 必须是**裸 `host[:port]`**

`assertTrustedAuthority`(`:165-169`)在装载时逐条校验,任何「被 WHATWG 解析会改写」的写法**直接抛错、整行装载失败**:

    client-connection: trustedHosts entry "<原样>" is not a bare host[:port] authority

会被拒的例子(源码注释 `:151-163`):`harness.internal/path`(带路径)、`user@harness.internal`(会把内嵌主机名授权出去)、首尾空白、悬空冒号 `host:`、零填充端口 `host:0443`、非规范拼写(`0x7f.0.0.1`、百分号编码、不带方括号的 IPv6);IDN 主机要写 punycode。
另:`host:port` 精确匹配该 authority;不带端口只匹配主机名(任意端口)(`:188-193`)。

## 7. 回滚(按逆序)

1. 客户端:清掉该站点 cookie;**若怀疑 cookie 已泄漏,还要删服务端 credentials 里 `client-connection` / `browser-session` 那条记录**(§4)并重启 DSH;
2. 服务端:`tailscale serve reset`(撤销对外入口;**语义 = 清空这台机器上**全部** serve 配置,不只是你刚设的那个端口** —— 本机实测 `tailscale serve --help`(exit=0)的 USAGE 只有 `<target>` / `status [--json]` / `reset`,**没有 `off`**);
3. 控制台:policy 还原、移除多余设备;
4. 服务端:移除 `connection.trustedHosts` 那一行(如不再需要)+ 重启 DSH;
5. 服务端:防火墙窄放行规则 `Remove-NetFirewallRule`;
6. 任意一台:卸载 Tailscale(`msiexec /x`)并 `tailscale logout`;
7. 若怀疑凭据泄漏:重启 DSH 换 launch token(每个进程一换,自动完成)+ 换掉任何受影响账号口令;**不要忘了第 1 条那条 credential 记录**(它才是 30 天 cookie 的根)。
