# 威胁模型:谁能看到什么、谁能做什么

- **最后更新时间**: 2026-09-24(v1;t16 repair-round-2 新增,对应评审 finding F7)
- **本次使用的命令**(全部只读;无 `platform:"client"` 的 Inspect、无 `ego_*`、无长等待):
  1. `powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/src/collect.ps1 -CheckOnly -AsJson`(本机姿态)
  2. `netstat -ano`(按列解析;本机 43120 与 tailnet 侧监听)
  3. 读源码:`dsh-client-connection\lib\index.js:188-206,219,227,240-246,321-338,554`(Host/Origin 栅栏、token 生命周期、cookie/grant 记录)
  4. `Get-ItemProperty 'HKLM:\...\FirewallRules'` / `netsh advfirewall monitor show currentprofile`(t2 D5 交叉)
  5. `Select-String -Path dsh-crossnet-link -Pattern 'Invoke-WebRequest|Invoke-RestMethod|curl|fetch\(|credentials\.yaml|ext-bridge-token|Cookies'`(插件自身面)
  6. 证据来源:本机**真机实测**(姿态采集 `-AsJson` + 按列解析的 `netstat`)、**四格组合矩阵**的实测结论、以及一次**独立安全评审**的逐条结论 —— 设计与评审记录属于**不随仓库发布的内部文件**,本文只就地复述结论;连接层语义由第一方源码直接确认(见下方 `[源码]` 档标注)。

> **本文件的定位**:插件要发 GitHub,所以威胁模型必须在**本仓库里**能读到,而不是只存在于 skill 里。
> 结论分三档标注:**[实测]** 本机可复现 · **[源码]** 读第一方源码得到的确定性语义 · **[原理/未实测]** 依赖协议或官方文档,本机无从观测。

---

## 1. 资产、边界与信任假设

| # | 资产 | 位置 | 谁"本来就有权"访问 |
| --- | --- | --- | --- |
| A1 | 服务端 DSH 的**全部能力**(会话、文件读写、执行工具、subagent) | 服务端机 `127.0.0.1:43120` | 服务端本机的**任何**本地进程/用户(loopback 无认证,见 §2.5) |
| A2 | 那张 **30 天浏览器 cookie** | 客户端浏览器 + 服务端 credentials 的 `client-connection`/`browser-session` 记录 | 客户端机的浏览器用户;能读到该 cookie 的任何客户端进程 |
| A3 | **一次性 token**(带 token 的 URL) | 服务端进程内存(每进程随机)| 能读到 DSH 启动输出/URL 的人 |
| A4 | 服务端 DSH 的**凭据库**(`.credentials.yaml`、provider key) | 服务端 `$DSH_HOME` | 服务端本机该用户 |
| A5 | tailnet **连接元数据**(谁在何时连了谁、流量大小/时间) | tailnet 控制面 + DERP 中继 | tailnet 管理员;中继运营方(见 §2.2) |

**信任边界**:①客户端机 → ②tailnet(WireGuard 加密隧道 + ACL)→ ③服务端机的 `tailscaled` →(TLS 终结)→ ④`127.0.0.1:43120` 的 DSH。
**本插件(dsh-crossnet-link)不在这条链路上**:它只**读**本机姿态,不代理、不转发、不常驻、不监听。

---

## 2. 逐条回答

### 2.1 tailnet 内**其他设备**(同 tailnet 的第三台机器)

| 维度 | 结论 | 证据等级 |
| --- | --- | --- |
| 能看到什么 | 该 tailnet 的**节点清单**与各自 tailnet IP/DNS 名;能否连上**取决于 ACL**。本链路的 ACL 只放「客户端 → 服务端 `tcp:443`」,所以第三台机器**连不上** 443,也看不到 DSH 界面内容 | **[原理/未实测]**(ACL 在控制台,本机读不到:tailscale CLI 被命名管道拒,见 t1 §1.6) |
| 能做什么 | 若 ACL 是宽放行:第三台机器**直接打开界面 = 直接操作那台机器**(见 §3.1)。若像本链路这样窄放行:除了自己的节点名,TCP 层什么都拿不到 | **[原理/未实测]** |
| 我们的对策 | ① 窄 ACL 只放 client→server `tcp:443`(skill §server-setup §6 与本插件 `prereq-manifest` 的 `TAILNET_ACL_NARROW` 都把它列为必须人工确认项);② DSH 侧 `trustedHosts` 只填服务端自己的 MagicDNS 名,别的 Host 一律 `403`(见下) | **[源码]** |
| 残余风险 | ACL 改动是**控制台操作**,本插件无法观测、无法校验(**`TAILNET_ACL_NARROW` 恒为 unknown/manual**,不假装通过) | — |

**Host/Origin 栅栏(第二道闸)**:`dsh-client-connection\lib\index.js:188-206` 的 `isTrustedApiRequest` 只放行 loopback 与 `trustedHosts` 里的权威;`:554` 对不匹配的 `/api` 请求返回 **403**。本机实测该配置是**空的**:
`app\cordis.patch.yml:28` → `trustedHosts: []`,因此本机若当服务端,远端界面能打开但 `/api` 一律 403(`TRUSTED_HOSTS_PATCH = blocked`)。**[实测]**

### 2.2 DERP 中继(Tailscale 的中继服务器)

| 维度 | 结论 | 证据等级 |
| --- | --- | --- |
| 能看到什么 | **只有连接元数据**:哪两个节点在通信、时间、包的数量/大小与时序;看不到 HTTP 内容、看不到 token、看不到 cookie、看不到 DSH 的会话数据 —— 中继转发的是 **WireGuard 加密报文**,密钥只在两端 | **[原理/未实测]**:本机**无法**观测中继(tailnet 控制面/DERP 日志都不在本机);本链路 2026-09-23 实测「中继模式下工作正常,~191–206 ms」(t2 §7 台账) |
| 能做什么 | 断连、丢包、限速(拒绝服务);理论上做**流量分析**(例如从包大小/时序推断你在用聊天界面),但**不能**解密或篡改(篡改会被 WireGuard 检出) | **[原理/未实测]** |
| 我们的对策 | ① 不把「有没有直连」当故障:中继不是降级(t2 明文写「无直连不等于故障」);② 服务端只暴露 `serve` 的 443,**不额外开端口**,所以在中继路径上也只有这一条流;③ token/cookie 从不进日志、不进对话、不落盘(见 §4) | **[实测]** 43120 只绑 `127.0.0.1`;`NO_NEW_WILDCARD_LISTENER = pass` |
| 残余风险 | 中继可见「这台机器在对端活跃」这一事实;要消除只能自建 DERP/headscale,超出本插件范围 | — |

### 2.3 客户端被入侵(客户端机的恶意进程/浏览器扩展)

| 维度 | 结论 | 证据等级 |
| --- | --- | --- |
| 能看到什么 | ① 该 **30 天 cookie**(在浏览器 cookie 库里)→ 可随时重放;② 打开的界面内容(会话、文件树);③ 若 cookie 尚未签发,还能看到你粘贴过的 token(浏览器历史/剪贴板/网络面板) | **[源码]** 凭据语义:`dsh-client-connection\lib\index.js:219`(记录键名)、`:321-338`(持久化 grant 记录)、`:392` 附近(带 token 的 `GET /` 才签发 cookie) |
| 能做什么 | 用那张 cookie 在**任何**能连到 443 的地方操作服务端 DSH = 操作那台机器(§3.1) | **[源码]** |
| 我们的对策 | ① 本插件在客户端机上**不落任何凭据**:面板只显示姿态,不做 token/cookie 的读写/显示/传输;② 撤销路径写清(清 cookie + 删服务端 credentials 记录 + 明白「只重启不失效」),见 `install/rollback.md` §3 与 skill `references/security.md` §4;③ 建议把 30 天 cookie 当长期凭据对待:客户端机是要信任的机器 | **[实测]** 采集器输出经 5 类凭据形态扫描 **0 命中**(t8 C7 + 本次 `CREDENTIAL_DISCIPLINE = pass`) |
| 残余风险 | 无法防客户端上的键盘记录/扩展;cookie 一旦泄漏,在到期前**持续有效**(这正是 F2 要写清的事实) | — |

### 2.4 拿到「带 token 的 URL」的人

| 维度 | 结论 | 证据等级 |
| --- | --- | --- |
| 能看到什么 | 打开界面的能力;那一次 `GET /` 之后服务端**签发 30 天 cookie**,此后不再需要 token | **[源码]** (`:227`/`:240-246` 每进程随机 launch token;`:321-338` 持久化记录) |
| 能做什么 | **直接进入服务端 DSH 界面并操作那台机器**(§3.1);不需要二次确认、不需要服务端本机交互 | **[源码]** + **[实测]** 本链路 2026-09-23 就是这么打通的 |
| 我们的对策 | ① 一次性 token 属**凭据**,本插件**绝不**打印/传输/自动化它(`CLIENT_FIRST_OPEN_TOKEN` 是 manual 项,文本只用 `<TOKEN>` 占位符);② 明确「URL 泄漏 = 控制权泄漏」,并要求用后即撤销(§2.3 的三步) | **[实测]** 仓库内 `tskey-*`/JWT/真实 cookie 命中 **0**(t8 评审 §6) |
| 残余风险 | URL 可能进浏览器历史/剪贴板/聊天记录 —— 本插件只能提示,不能替你清理 | — |

### 2.5 **服务端本机**的其他用户或程序

| 维度 | 结论 | 证据等级 |
| --- | --- | --- |
| 能看到什么 | ① `netstat` 里 `127.0.0.1:43120` 的存在;② **任何本地进程都能直接打开 `http://127.0.0.1:43120`** —— 因为栅栏把 loopback 视为可信(`isLoopbackHostname` 分支,`:206`),loopback 请求**不需要** token/cookie;③ 若 `trustedHosts`/`networkExposure` 被改宽,局域网内其他机器也能打开 | **[源码]** + **[实测]** 本机 `DSH_LOOPBACK_ONLY = pass`(只绑 loopback) |
| 能做什么 | ②意味着:**同机的另一个用户/程序可以驱动 DSH 的全部能力**(读写该用户的会话与工具)。这是 DSH 的固有模型,不是本插件引入的;本插件不改变它 | **[源码]** |
| 我们的对策 | ① 明确写出来(不掩盖):「能打开界面 = 能操作那台机器」,loopback 也一样;② 本插件**不新增**任何监听、不加任何代理(否则会把 loopback 面放大到网络面);③ `DSH_NETWORK_EXPOSURE` 若被改成 `lan` ⇒ **blocked**(t16 F6:实现/面板/文档统一按安全项处理);④ 采集器只读(注册表/`netstat`/patch 文件/`settings.yaml`),**不读** `.credentials.yaml`,不提权 | **[实测]** `exposure_ok`(本机 loopback)、`NO_NEW_WILDCARD_LISTENER = pass`、`CREDENTIAL_DISCIPLINE = pass` |
| 残余风险 | 同机未授权进程仍可访问 loopback;要收紧只能靠 OS 层(独立用户 + 会话隔离)或改 DSH 的认证模型 —— 都不在本插件范围 | — |

---

## 3. 两条必须写死的结论

### 3.1 「能打开界面」= 「能操作那台机器」

服务端 DSH 的界面不是只读看板:它带着该用户的会话、文件读写、工具执行与 subagent 能力。
因此任何能拿到**界面访问权**的主体(带 token URL 的人、持有 30 天 cookie 的客户端、服务端本机任何本地进程、被 ACL 放行的 tailnet 节点)**都等于拿到了那台机器的操作权**。
本插件的一切设计都建立在这个前提上:窄 ACL、窄 `trustedHosts`、不新增监听、不代理、凭据不进日志。

### 3.2 DERP 中继**可见连接元数据,但看不到内容**

中继转发的是 WireGuard 加密报文 ⇒ 它能看到「哪两个节点、什么时候、多少流量」,**看不到** HTTP 正文、token、cookie、会话数据。
所以:① 不要把「走中继」当故障或降级(实测 ~191–206 ms 可用);② 也不要把中继当作隐私边界 —— 元数据仍然暴露「这台机器在对端活跃」。
**[原理/未实测]**:本机无从观测中继行为,这条依赖协议语义与官方文档;标注为未实测是本文件的诚实要求。

---

## 4. 本插件自身增加的攻击面(逐条)

| 我们加了什么 | 攻击面 | 抑制 |
| --- | --- | --- |
| `src/collect.ps1`(只读采集器) | 会读:注册表(OS/防火墙规则库/`EnableFirewall`/Internet Settings)、`netsh`/`netstat`/`powercfg` 输出、patch 文件、`settings.yaml`;**不读**凭据 | 无写路径;`CREDENTIAL_DISCIPLINE` 机械自审;`-Apply` 直接拒绝;**无网络探测**(除非操作者显式给 `-Peer`,且 ≤5s) |
| host 半边(`src/host-half.js`,动态包 `guard-1`) | 一个包私有 RPC + 一个模型工具,能拉起采集器子进程 | 只读;bounded 字段(不含 `raw`);`fixture` 参数白名单(`tests/fixtures/**`,拒绝对路径/UNC/`..`);全挂 `ctx.effect` ⇒ `cordis_stop` 可逆 |
| client 半边(`panel/client-half.js`) | 设置页一个只读面板 | 只渲染姿态与凭据纪律文案;唯一的 host 调用;不读 DOM 全局(沙箱只给 `React`/`host.call`) |
| 插件整体 | 不发遥测、不新增监听、不做重启 | 见 `SECURITY.md` 的可校验承诺清单 |

---

## 5. 未实测 / 复测条件(不假装覆盖)

| # | 未实测的事 | 为什么 | 复测条件 |
| --- | --- | --- | --- |
| T1 | tailnet ACL 的实际放行集 | CLI 被命名管道拒(t1 §1.6) | 用户在普通窗口跑 `tailscale status` / 看控制台 |
| T2 | DERP 侧实际可见字段 | 本机无中继日志 | 自建 DERP 或抓包 |
| T3 | `serve` 目标与 tailnet 443 现值 | 本机是客户端角色且 CLI 被拒 ⇒ `SERVE_PRESENT = unknown` | 对端在线 + 用户在普通窗口跑 `tailscale serve status` |
| T4 | 对端(服务端)本机的本地用户/进程面 | 未触达对端(按 token 计费,不发消息) | 对端在线时跑同一份 `collect.ps1 -Role server` |
| T5 | 30 天 cookie 在服务端记录被删后是否**立即**失效 | 需要真实撤销一次并观测 | 在测试机上撤销一次,记录判据回填 skill §4 |
| T6 | 长期暴露(soak)下的行为 | 本版不做(团队已决定不做容错实测) | — |
