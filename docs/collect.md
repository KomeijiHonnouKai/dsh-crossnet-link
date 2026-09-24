# collect.md

> （历史记录）2026-09-24 17:29 的 t13 sanitize pass。当时使用的命令：powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/tests/run-fixtures.ps1 ; release-set scan: Get-ChildItem remote-tailnet-plugin/src,remote-tailnet-plugin/i18n,remote-tailnet-plugin/tests,remote-tailnet-plugin/docs/collect.md -Recurse -File | Select-String -Pattern <the six real identifiers> (expect 0). This pass only replaced real identifiers with neutral placeholders; no structure changed. — 只读采集判定器 + Cordis host 半边(交付说明)

- **最后更新时间**: 2026-09-24(v1.5;t25:①`SERVE_PRESENT` 按 t23 落地后的新语义**全面改写**(证据只来自可读 `tailscale serve status` 的 proxy 目标端口;目标 ≠ 实测 DSH 端口 ⇒ `blocked/serve_port_mismatch`;CLI 不可读/无可解析目标 ⇒ `unknown`;tailnet 监听形状**仅作佐证**);②全文一致性复核,修掉 10 处与当前实现不符之处(**逐条列在 §14**);③新增 §2.1 参数速查(26 个参数,以实现为准);④补「内部资料链接口径」说明。本次命令 = `collect.ps1 -CheckOnly / -AsJson / -Role server / -Role client / -Role both / -Describe`、`tests/run-tests.ps1`、`tests/run-fixtures.ps1`、发布集扫描(仓库根为 cwd)。v1.4:t20 把 §2 的 `<DSH_APP>` 占位化;v1.3:t16 的 F5/F6 修复、`-Port` 非法值拒收、`executionPolicy` 作用域;包状态 `guard-1/pkg-4`)
- **本次使用的命令**(全部只读;无 `platform:"client"` 的 Inspect、无 `ego_*`、无无超时网络请求):

```powershell
# 交付物本体
powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/src/collect.ps1 -CheckOnly
powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/src/collect.ps1 -CheckOnly -AsJson
powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/src/collect.ps1 -CheckOnly -Role server
powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/src/collect.ps1 -CheckOnly -ShowRaw
powershell -NoProfile -Command '$f="remote-tailnet-plugin/src/collect.ps1"; $b=[IO.File]::ReadAllBytes((Resolve-Path $f)); $e=$null; [void][Management.Automation.Language.Parser]::ParseFile((Resolve-Path $f),[ref]$null,[ref]$e); "bom=" + ($b[0..2] -join ",") + " errors=" + @($e).Count'
powershell -NoProfile -Command '(netstat -ano | Select-String "(0\.0\.0\.0|\[::\]):43120").Count'
# 夹具注入 / 回归
powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/src/collect.ps1 -CheckOnly -AsJson -FixturePath remote-tailnet-plugin/tests/fixtures/zh.json -NoNative
powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/tests/run-fixtures.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/src/collect.ps1 -CheckOnly -Role both -DumpFixture remote-tailnet-plugin/tests/fixtures/zh.json
# 取证用的现场探测(读到的原文直接影响了下面 6.1–6.6 的实现决策)
netsh advfirewall monitor show currentprofile        # 交互控制台显示英文,重定向后显示本地化中文(CP936)
netsh advfirewall firewall show rule name=Tailscale-Process verbose
netsh advfirewall show allprofiles
powercfg /query SCHEME_CURRENT 238c9fa8-0aad-41ed-83f4-97be242c8f20 29f6c1db-86da-48c5-9fdb-f2b67b1f44da
Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage'
Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language'
# Cordis host 半边(host 侧 Inspect;全程未用 client Inspect)
cordis_inspect_list; cordis_inspect_query(platform="host", provider="Service", method="listService", input={service:"fs"})
cordis_inspect_query(platform="host", provider="Service", method="listService", input={service:"subprocess"})
cordis_define(...); cordis_run(guard-1, pkg-4, update); remote_tailnet_posture(role="both", fixture=".../zh.json")
```

> 判定项的依据全部来自**真机实测记录与四格组合矩阵的实测结论**,**没有一条是从记忆里写的**;那些设计、复核与实测记录属于**内部资料,不随仓库发布**。
> 本文已把实现所需的设计规则**就地复述**(见 §13),读完本文**不需要**任何内部资料。
>
> ⚠️ **链接口径**:本文不复述任何内部资料的路径,只就地复述结论与规则;发布集边界与裁定见 **§14.1**。
> 需要**可复现的验证流程**时,看仓库内的 `CONTRIBUTING.md` §1(Hard rules)与 §2(PR 前要跑的命令:本采集器的离线套件 + 发布集卫生门禁)。
> 内部证据台账(例如「netstat 形状不是 serve 换端口的正向证据」的实测反例)只存在于团队内部记录里,本文**不复述它的路径**,只复述结论(见 §5 第 11 条)。

---

## 1. 交付物清单

| 文件 | 作用 |
| --- | --- |
| `src/collect.ps1` | 只读采集判定器(Windows PowerShell 5.1;**纯 ASCII**,无 BOM) |
| `i18n/labels.zh.json` | 中文标签 + **本地化文本模式**(netsh 字段名的中英双语正则) |
| `i18n/labels.en.json` | 英文标签 + 英文模式 |
| `tests/run-fixtures.ps1` | 离线回归runner(**7** 个 case,断言 verdict 与退出码) |
| `tests/fixtures/zh.json` | 本机真实抓取(zh-CN,CP936 解码后) |
| `tests/fixtures/en.json` | 同一状态、工具输出换成英文(证明双语模式都可用) |
| `tests/fixtures/win11-server.json` | **Win11 服务端候选**:build 26100 + S0 + `STANDBYIDLE` DC `0x00000e10`(3600 s)+ serve/443 + trustedHosts 已配 ⇒ 证明 Win11 分支、退出码 1(降级)与「枚举来源」的网卡归属 |
| `tests/fixtures/localized-unmatched.json` | 德式字段名:证明「匹配不上 → unknown + 原文,绝不猜」 |
| `tests/fixtures/edge-false.json` | `Tailscale-Process` 的 `Edge=FALSE` 漂移回归夹具 |
| `docs/collect.md` | 本文件 |

Cordis 动态包:**`guard-1` / `pkg-4`**(host 半边;**t16 复核时 `cordis_inspect_self()` 返回 `plugins: []` ⇒ 进程重启后动态包已消失**,需按 `docs/install/install.md` §1 重新 define+run;源码与哈希见 `src/host-half.js`,详见 §11)。

---

## 2. 怎么跑 / 实测结果

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/src/collect.ps1 -CheckOnly
powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/src/collect.ps1 -CheckOnly -AsJson
```

本机(非提权 agent 会话)实测:

| 命令 | 退出码 | 结果 |
| --- | --- | --- |
| `-CheckOnly` | **2** | 24 项:pass 15 / **degraded 2** / **blocked 1** / unknown 6;`overall: blocked -> exit 2` |
| `-CheckOnly -AsJson` | **2** | 单一 JSON 对象,**315,260 字节**(2026-09-24 t25 快照),`ConvertFrom-Json` 可解析,24 项判定(每项含 `id`/`role`/`title`/`status`/`verdict`/`verdictLabel`/`severity`/`reasonKey`/`reason`/`commands[]`/`raw`/`evidence{command,commands,exitCode,source,confidence,window,confidenceDowngrade,confidenceNote}`/`remediation`/`manualReview`/`manualQuestion`) |
| `-CheckOnly -Role server` | 2 | 19 项:14/2/1/2(客户端项按角色不输出) |
| `-CheckOnly -Role client` | **1** | 14 项:9 pass / 5 unknown(无 `-Peer` + HTTPS 恒 unknown)⇒ **`verdict=degraded exit=1`**,演示了「无阻断但有 unknown」这一档 |
| `-CheckOnly -Strictness strict` | 2 | unknown 提升为阻断 |
| `-Describe` | 0 | 打印配置面 / 退出码契约 / 明确不支持清单(**26 行非空输出**,不探测) |
| 夹具 `zh.json -NoNative` | 2 | 与真跑**逐项一致**(默认 `role=both`:24 项 15/2/1/6;加 `-Role server`:19 项 14/2/1/2)⇒ 离线可复现、无隐藏本机依赖 |
| 夹具 `en.json -NoNative` | 2 | 与 zh 夹具**逐项一致**(证明中英双语模式等价) |
| 夹具 `win11-server.json -Role server` | **1** | 19 项:**17 pass** / **2 degraded** / 0 blocked / **0 unknown** ⇒ `verdict=degraded exit=1`;`OS_BUILD.raw.branch=win11`;`POWER…DC=3600 s → power_dc_only`;`SERVE_PRESENT=pass/serve_ok`(可读 serve status 目标 = `43120` = 实测 DSH 端口,且 443 上有 2 条 tailscaled 监听 —— 按 t23 新语义的通过路径) |
| `tests/run-fixtures.ps1` | **0** | `ALL PASS: 7 cases, 0 failed assertions` |

> 本机 2 条 degraded 的来源是**同一类**:判定只能靠本地化文本(§13.1 的「不把本地化工具文本当安全判据」规则允许这种路径存在,但只允许报 **degraded**,不允许报 pass)⇒
> `NIC_PROFILE_ATTRIBUTION`(netsh 文本,`confidence=low`)与 `POWER_S0_CAPABILITY`(powercfg /a 段落结构)。
> 两者都**不伪装成 pass**:`evidence.confidence=low` + `confidenceDowngrade=true` + `confidenceNote` 都在 JSON 里。
| `-Apply` | **2** | 拒绝执行并打印「本采集器只读、没有写路径」 |

本机那条唯一的 **blocked** 是 `TRUSTED_HOSTS_PATCH`:**实际加载的 patch 里 `trustedHosts: []`**。

> 直接证据(逐字):`<DSH_APP>\cordis.patch.yml:28` → `trustedHosts: []`(在 `- id: web-runtime` 那一行下面;`<DSH_APP>` = DSH 应用的 `resources\app` 目录,解析方式见 `docs/install/install.md` §3,本机实测值不写死);
> `<DSH_HOME>\profiles\desktop\cordis.patch.yml`、`cordis.yml`、`settings.yaml` 里 `trustedHosts` 命中 **0**(`<DSH_HOME>` = 本机 `$env:DSH_HOME`,路径不写死)。
> ⇒ 本机若作为服务端,远端界面能打开但 `/api` 会被 403 拦(t2 的 F03/F04)。这条不是「探针不可用」,是**真实存在的前置件缺口**。

unknown 6 项全部带原因,且**没有任何一项是猜的**:
`TAILSCALE_CLI_LAYER`(命名管道沙箱被拒)、`SERVE_PRESENT`(`tailscale serve status` 读不出来 ⇒ 目标端口无从判定,按新语义退 unknown —— 见 §5 第 11 条)、`PEER_TCP_443`/`PEER_ISOLATION_PROBES`/`MAGICDNS_RESOLVE`(未提供 `-Peer`)、`HTTPS_CLIENT_ONLY`(PowerShell 做不了 TLS 判定)。

### 2.1 参数速查(26 个;描述取自 `src/collect.ps1` 的 param 注释,以实现为准)

| 参数 | 默认 | 作用 |
| --- | --- | --- |
| `-CheckOnly` | 关 | **只读本来就是默认行为**,这个开关只是把它写明;所有处置都只打印给人执行,绝不代执行 |
| `-AsJson` | 关 | 在 stdout 输出单一 JSON 报告(该模式下 stdout 不再有人读文本) |
| `-Role` | `both` | `server` / `client` / `both`:决定输出哪些判定项(server 19 项 / client 14 项 / both 24 项) |
| `-Lang` | `auto` | `auto` / `zh` / `en`:人选用的**文案**语言;模式串**始终合并加载**,与解析能力无关 |
| `-LabelsDir` | `<脚本>\..\i18n` | 标签目录(换语言只需往这里丢 `labels.<lang>.json`) |
| `-Port` | 空 | DSH loopback 端口;空 ⇒ `$env:DSH_WEB_URL` ⇒ 内置 43120(并标注「用的是默认值」);非法值拒收并记 `config.dshPort.invalidParam` |
| `-TailnetDomain` | 空 | tailnet DNS 后缀(如 `tailXXXX.ts.net`);给出时同时作为 trusted-host 模式 |
| `-Profile` | 空 | 读哪个 DSH profile 的 patch;**多 profile 且未给 ⇒ `TRUSTED_HOSTS_PATCH` = unknown,绝不静默取第一个** |
| `-Peer` | 空 | 对端 IP 或 MagicDNS 名;不给 ⇒ 客户端侧探针**不跑**(unknown) |
| `-PeerName` | 空 | 对端 MagicDNS 名(给 `-Peer` 为 IP 时用于解析判定) |
| `-DshHome` | 空 | DSH home(显式参数 → `$env:DSH_HOME` → `~\.dsh`) |
| `-AppDir` | 空 | DSH 应用代码目录(默认按进程镜像路径自动发现) |
| `-FixturePath` | 空 | 用 JSON 夹具替换**外部输入**(见 §8);**CLI 不限制路径**,白名单是给面板桥用的 |
| `-NoNative` | 关 | 禁止一切真实读取;夹具里没有的探针 ⇒ unknown(fail-closed) |
| `-Strictness` | `normal` | `strict` 把 unknown 提升为退出码 2 |
| `-TcpTimeoutMs` | `5000` | TCP 握手超时(每端口) |
| `-DnsTimeoutMs` | `4000` | DNS 解析超时 |
| `-CommandTimeoutMs` | `15000` | 每个外部命令的超时 |
| `-OutputCodePage` | `0` | 外部命令输出的解码代码页;**0 = 自动**(注册表 NLS 的 OEMCP,本机 936) |
| `-ToolPath` | `@{}` | 覆盖单个工具路径:`-ToolPath @{netsh='…'}` |
| `-TrustedHostPattern` | `\.ts\.net$` | trustedHosts 的匹配模式 |
| `-OutFile` | 空 | **显式 opt-in 写入 #1**:把报告落盘(不写就是零字节) |
| `-Describe` | 关 | 只打印配置面 / 退出码契约 / 不支持清单,**完全不探测**,exit 0 |
| `-DumpFixture` | 空 | **显式 opt-in 写入 #2**:把本次全部探针结果抓成可回放夹具,exit 0 |
| `-ShowRaw` | 关 | 人读输出里附带各项 `raw` 原始值 |
| `-Apply` | 关 | **接受但永远拒绝**(本版没有写路径):打印命令 + 回滚后 exit 2 |

---

## 3. 退出码语义(替代 skill 里 `verify.ps1` 恒 exit 0 的问题)

| 退出码 | 含义 | 聚合规则 |
| --- | --- | --- |
| **0** | 安全/通 | 所有判定 = pass;**fail-closed:只要存在 unknown,一律不得是 0** |
| **1** | 降级 | 存在 degraded,或存在 unknown(且未开 `-Strictness strict`) |
| **2** | 阻断/不可用 | 存在 blocked,或采集器自身不可用(夹具缺失/解析失败/`-Apply`) |

`-Strictness strict` 把 unknown 升为 2。JSON 里同时给出 `summary.verdict`(pass/degraded/blocked)、`summary.exitCode`、`summary.exitMeaningKey` 与 `summary.failClosed`,可直接当门禁读。

---

## 4. 检测项清单(24 项)

`role` 列:S=服务端候选,C=客户端候选,B=两端都跑。每项的 JSON 里都有 `id`/`role`/`title`/`status`/`verdict`/`verdictLabel`/`severity`/`informational`/`reasonKey`(稳定机器可读)/`reason`(本地化人读)、`commands[]`(检测命令)、`raw{}`(原始值)、`evidence{command,commands,exitCode,source,confidence,window,confidenceDowngrade,confidenceNote}`、`remediation{action,actionKey,command,rollback,needsElevation,applied:false}`、`manualReview`/`manualQuestion`。

| ID | role | 读什么(不读什么) | 通过 | 降级 / 阻断 |
| --- | --- | --- | --- | --- |
| `OS_BUILD` | B | 注册表 `CurrentVersion`(不读 WMI) | 读到即 pass | 读不到 → unknown;分支按 `CurrentBuild>=22000` 判 Win11 |
| `HOST_PS_ENV` | B | `$PSVersionTable`/执行策略/`pwsh`/`node` | PS≥5.1 | PS<5.1 → 降级 |
| `PRIVILEGE_LEVEL` | B | `WindowsPrincipal.IsInRole` | 信息项 | — |
| `TAILNET_ADDRESS` | B | `netsh interface ip show addresses` 里的 **100.64.0.0/10 正则** + netstat 里的 `fd7a:115c:a1e0::/48` | 找到 tailnet 地址 | 找不到 → unknown(可能未登录) |
| `DSH_LOOPBACK_ONLY` | S | `netstat -ano` 按**列**解析(状态词是**可注入模式**,默认 `(?i)LISTENING`;t16 F5) | 该端口所有状态词匹配行都是 `127.0.0.1`,通配/其他接口命中 = 0 | 非回环命中 → **阻断**;端口无监听 → unknown;**状态词整个读不出来 → unknown(绝不 pass)** |
| `WILDCARD_LISTENER_INVENTORY` | B | 同上(非回环清单,**与 DSH 端口分开陈述**) | 无 DSH 进程的对外监听 | DSH 进程对外 → 阻断 |
| `TAILSCALE_CLI_LAYER` | B | 自动发现 exe + `version`/`ip -4`/`serve status` 退出码 | `ip -4` 退出码 0 | 命名管道被拒 → unknown(**不是「未配置」**);exe 缺失 → 阻断 |
| `TAILSCALE_SERVICE` | B | `Get-Service Tailscale` | Running | 未运行/未安装 → 阻断 |
| `TAILSCALE_PROCESS_EDGE_DB` | S | **注册表规则库**里 `Name=Tailscale-Process` 的 `Edge=`(权威)+ netsh 回显(次证) | `Edge=TRUE` | `Edge=FALSE` → **阻断**(漂移);注册表读不到 → unknown |
| `TAILSCALE_IN_RULES` | S | 注册表 `Tailscale-In` × 2 | 2 条、LA4+LA6、覆盖 Domain/Private | 缺失/不完整 → 降级 |
| `NIC_PROFILE_ATTRIBUTION` | S | `Get-NetConnectionProfile`(仅提权可用)→ 否则 netsh 文本 + 本地化模式 → 否则 unknown | Tailscale 网卡落在 Domain/Private | 落在 **Public → 阻断**(Tailscale-In 静默失效) |
| `FIREWALL_PROFILES` | S | 注册表 3 个 `EnableFirewall`(权威)+ netsh(次证) | 三个都 = 1 | 有 profile 关闭 → 降级 |
| `POWER_STANDBY_IDLE_AC_DC` | S | `powercfg /query` 的 **0x 原值**(按最后两行结构解析 + 别名交叉校验,不读本地化标签) | AC=DC=`0x00000000` | DC≠0 → 降级;AC≠0 → 阻断;结构不符 → unknown |
| `POWER_S0_CAPABILITY` | S | `powercfg /a` 段落结构 | 能判定 S0 可用性即 pass(信息项) | 结构不符 → unknown;是否断网**必须人工读原文** |
| `DSH_NETWORK_EXPOSURE` | S | `settings.yaml` 的 `networkExposure`(显式 UTF-8 读) | loopback | **lan → 阻断**(t16 F6:实现/面板/文档同档,该 check 的 `raw.level` 写明理由);读不到/键缺失 → unknown |
| `TRUSTED_HOSTS_PATCH` | S | **实际加载的 patch 链**里的 `trustedHosts` | 含 ts.net 域名 | 有键但无匹配(如 `[]`)→ **阻断**;无键 → unknown |
| `SERVE_PRESENT` | S | **可读的 `tailscale serve status` 的 proxy 目标端口**(netstat 的 tailnet 监听形状**只作佐证**) | 目标端口 = 实测 DSH 端口,且 443 上确有 tailscaled 的监听 | **目标端口 ≠ 实测 DSH 端口 → 阻断**(`serve_port_mismatch`,带 command + rollback);CLI 不可读或无可解析目标 → unknown;443 被非 tailscaled 占用 → 降级(详见 §5 第 11 条) |
| `PEER_TCP_443` | C | ≤5s TCP 握手(`-Peer` 才跑) | connected | refused/timeout → 阻断 |
| `PEER_ISOLATION_PROBES` | C | 135/5357/DSH端口 | 全部不可达 | DSH 端口可达 → 阻断;135/5357 可达 → 降级 |
| `MAGICDNS_RESOLVE` | C | ≤4s DNS | 解析进 tailnet 段 | 不在 tailnet 段 → 降级;HostNotFound → 阻断 |
| `BROWSER_PROXY_TSNET` | C | `Internet Settings` | 未启用或已绕过 | 启用且未绕过 → 降级 |
| `HTTPS_CLIENT_ONLY` | C | 只做能力声明 | — | **恒 unknown**,附可人工执行的 Node 命令 |
| `CREDENTIAL_DISCIPLINE` | B | 自审所有已执行探针命令串 | 无凭据类访问痕迹 | 有 → 阻断 |
| `NO_NEW_WILDCARD_LISTENER` | B | 采集前后 netstat 快照差集 | 无新增通配监听 | 有新增 → 阻断 |

---

## 5. 只读与凭据纪律

1. **默认零写入**:不加 `-OutFile` / `-DumpFixture` 时,脚本一个字节都不写。两个写入开关都是显式 opt-in。
2. **`-Apply` 直接拒绝并 exit 2**:本版本没有写路径;所有处置都只打印命令 + 回滚命令给人工执行。
3. **自证**:`NO_NEW_WILDCARD_LISTENER` 在采集前后各取一次 `netstat -ano` 快照,对 `0.0.0.0` / `[::]` 的 LISTENING 集合判**差集为空**(不看绝对条数 —— 条数会随系统状态浮动)。本机取证:套件级门禁 `G2 wildcard listener set unchanged: OK`(t25 运行快照 26 个通配监听)每轮复核同一断言。**行数从不作为判据**(TIME_WAIT 会浮动)。
4. **凭据**:脚本从不打开 `.credentials.yaml`、`ext-bridge-token`、浏览器 cookie 库或任何 session 日志;`CREDENTIAL_DISCIPLINE` 会**机械地**扫描本次执行过的全部探针命令串与读过的文件路径,出现凭据类痕迹就 fail-closed(本机实测 pass;读过的路径 18 个 = `settings.yaml` + patch 文件)。
5. **不新增监听、不改系统配置、不碰实时 profile**:`webServer.register` 等一律不用;Cordis 半边也不注册任何监听(详见 §11)。

### t16(F5/F6/t7-F1/t7-F2)改了什么

6. **netstat 状态词的 fail-closed(F5)**:`ConvertFrom-NetstatLines` 不再硬匹配 `LISTENING`,改为可注入模式(`Get-Pattern 'netstat_listening'`,默认 `(?i)LISTENING`),并回传 `tcpRowCount` / `parsedRowCount` / `stateWordUnrecognized`。
   `WILDCARD_LISTENER_INVENTORY` 与 `NO_NEW_WILDCARD_LISTENER` 现在**先看探针与解析结果**:探针不可用、状态词读不出来、或一行都没解析出来 ⇒ **unknown**,不再把「什么都没读到」当成「没有通配监听 / 没有新增监听」。
   回归:t11 的 `locale-netstat-state-localized` 保持 `DSH_LOOPBACK_ONLY = unknown/dsh_no_listener`;当初用来记录这两个缺口的 xfail 用例**早已被翻成正常用例**(现名 `fault-netstat-unavailable` 与 `locale-netstat-state-localized`),套件里现在**没有任何 xfail**(t25 快照:`xfail held = 0`,`xpass = 0`)。
7. **`networkExposure=lan` 改为 `blocked`(F6)**:与设计规则「把 DSH 交给通配监听(局域网暴露)= `blocked`,不是 `degraded`」同档(实现 / 面板 / 文档三处等级一致);该 check 的 `raw.level` 写明理由。
8. **`-Port` 非法值拒收**:非数字的 `-Port` 不再被静默接受(否则判定会对着端口 `0` 跑),而是回落 `$env:DSH_WEB_URL` → 内置默认,并在 `config[]` 里留 `dshPort.invalidParam` 记录。
9. **`SERVE_PRESENT.raw.rows` 语义**:`rows` = **全部 tailnet 地址监听行**(serve 被挪到别处时,人仍能看到端口/分类/owner),`serveRows` = 其中 443 的子集;两者现在都只是**佐证**,判定不再由它们决定(见第 11 条)。
10. **`executionPolicy` 作用域(t7-F2)**:`HOST_PS_ENV.raw.executionPolicy=Bypass` 是**本进程**的值(采集器被 `-ExecutionPolicy Bypass` 拉起),机器/用户默认另算 —— 同项新增 `executionPolicyScopes`(`Get-ExecutionPolicy -List` 五个 scope 实测:`MachinePolicy/UserPolicy/CurrentUser/LocalMachine=Undefined`,`Process=Bypass`)。
11. **`SERVE_PRESENT` 的判据改为「serve 目标端口」(t23)**:**证据只来自可读的 `tailscale serve status`** —— 取 `.proxy http://127.0.0.1:<port>` 的端口,与**实测 DSH 端口**比较:不等 ⇒ `blocked/serve_port_mismatch`(command = 重新 `tailscale serve --bg <DSH端口>`,rollback = `tailscale serve reset`);CLI 不可读、或输出里没有可解析目标 ⇒ `unknown`。新增原始值:`raw.serveStatusReadable` / `raw.serveTargetPorts` / `raw.dshPortMeasured` / `raw.listenerShapeNote`。
    **为什么不拿 netstat 的 tailnet 监听形状当证据**:健康节点同样会出现「tailscaled 拥有的非 443 tailnet 监听」(那是 tailscaled 自有端点,与 serve 无关),按它判 blocked 会把**任何已登录节点**误报成「serve 换了端口」。该反例与对照实验(原实现 `unknown` vs 那条已否决的规则 `blocked`)记录在**内部证据台账**(不随仓库发布);**可复现的验证流程**见仓库内 `CONTRIBUTING.md` §1(Hard rules)与 §2(PR 前要跑的命令)。

---

## 6. locale-proof:决策与本次踩到的 6 个坑(都有原文)

> 总原则:**能走注册表 / .NET / 原始数值 / GUID 的,一律走那条**;确需解析文本的地方,模式串**外置到 `i18n/labels.*.json`**(可注入、双语夹具验证),匹配失败 → `unknown` + 原文。

### 6.1 重定向后 netsh 说的是**本地化**中文,而且是 **CP936**
现场:
```
交互控制台: Private Profile:
重定向捕获: 专用配置文件:            <-- 必须用 CP936 解码才是这串
```
`[System.Console]::OutputEncoding` 在本环境是 `utf-8`,用它解码得到乱码(`ר�������ļ�`)。
⇒ 实现:`Get-SystemTextEncoding()` 读 `HKLM\SYSTEM\CurrentControlSet\Control\Nls\CodePage` 的 **OEMCP**(本机 = 936)作为 `StandardOutputEncoding`,可用 `-OutputCodePage` 覆盖。
⇒ 教训:**「我在控制台看到英文」不能推出「脚本拿到英文」**。这是本任务最值钱的一条。

### 6.2 本地化字段名必须外置
实测:`边缘遍历: 是` / `专用配置文件:` / `状态 启用` / `确定。`(英文对应 `Edge traversal: Yes` / `Private Profile:` / `State ON` / `Ok.`)。
⇒ `labels.zh.json` 的 `patterns` 段同时写中文与英文写法;`labels.en.json` 只写英文。**所有标签文件的 patterns 会被合并加载**(语言只决定人读文案,不决定能不能解析),所以英文显示语言 + 中文 netsh 输出也能解析。

### 6.3 `$Args` 是 PowerShell 自动变量
`param(...,[object[]]$Args)` 让 `-f` 格式化**静默失效**:输出里满是 `{0}`。实测截图级证据:改成 `$FmtArgs` 后 `Port 43120: all 1 LISTENING rows bind 127.0.0.1` 正常。

### 6.4 `'0804' -match '^0*4'` 是 **False**
`Nls\Language` 的 `InstallLanguage` 是十六进制 LCID 字符串(`0804` = zh-CN)。`^0*4` 只能吃掉前导 `0`,遇到 `8` 就失败。
⇒ 正确做法:按 `NumberStyles.HexNumber` 解析后 `($lcid -band 0xFF) -eq 0x04`;并且**先用 `InstalledUICulture`**(本环境 `CurrentUICulture` 是 en-US 而系统是 zh-CN,实测)。

### 6.5 「回显 ≠ 落库」
Edge traversal 的**权威判据是注册表规则库里的 `Edge=TRUE/FALSE`**,netsh 回显只作次证;注册表读不到时**不判**(unknown),不能靠回显下结论(t2 F11/F24;要查的是进程级 `Tailscale-Process`,不是 `Tailscale-In`)。

### 6.6 netstat 必须按列解析
`TCP 100.64.0.11:139 0.0.0.0:0 LISTENING 4` 的**远端列**就是 `0.0.0.0:0` —— 用整行 `0.0.0.0` 过滤会**误杀**本机监听行(t1 亲测该表返回空)。实现按列取 local 地址后再判 loopback/通配/tailnet。

---

## 7. 零硬编码与「值来自哪」标注

- 脚本内**没有任何**用户目录绝对路径、盘符绝对路径、主机名、tailnet 名、对端 IP、用户名(全部用 `<DSH_HOME>` / `<DSH_APP>` / `<APP_DIR>` 这类占位符)。全文非 ASCII 字节 = **0**(因此不需要 BOM,也不受 PS 5.1 的 ANSI 默认解码影响)。扫描口径(6 类禁止模式 + **已批准的中性占位符**允许清单)与仓库内可复现的检查命令见 `CONTRIBUTING.md` §4(Sanitization rules)与 §2(PR 前要跑的命令)。
- 每个配置值都在 JSON 的 `config[]` 里带 `source`:例如本机实测
  `dshHome=<DSH_HOME> (env:DSH_HOME)`、`dshPort=43120 (env:DSH_WEB_URL)`、`tool.tailscale=…\tailscale.exe (auto(ProgramFiles))`、`appDir=…\resources\app (auto(process image path))`、`patchFiles=17 (auto)`、`nativeOutputDecoding=gb2312 (auto(registry NLS OEMCP))`。
- 解析顺序:`参数 > 环境 > 自动发现 > 文档化的内置默认`;内置默认只有两个:DSH 端口 `43120`(产品 schema 默认)与 `trustedHostPattern`(产品域名后缀)。
- 仅有两处**非机器相关**的常量:Windows 自身的 GUID(睡眠子组/设置项)与产品名(`Tailscale`、`Tailscale-Process`、`Tailscale-In`、`DSH`、`cordis.patch.yml`)。这些在任何 Windows 上一致。

---

## 8. 夹具注入与跨机抓取

- 所有外部输入(命令、注册表、文件、服务、cmdlet、**进程名**、TCP、DNS)都走**同一层探针**(`Invoke-External` / `Get-RegProbe` / `Get-FileProbe` / `Get-FileListProbe` / `Get-ServiceProbe` / `Get-NetProfileProbe` / `Get-ProcName` / `Invoke-TcpProbe` / `Invoke-DnsProbe`),逻辑键不含机器路径。`processes` 段把 PID 映射到映像名,于是「监听 owner 是不是 tailscaled」这类判定也能离线证明(否则夹具回放会因拿不到进程名而退化)。
- `-FixturePath <json>` 替换输入;`-NoNative` 禁止一切真实读取(夹具里没有的探针 → unknown,fail-closed)。
- **在任意机器上抓夹具**:`-DumpFixture <path>` 会把本次所有探针结果(含进程名映射)写成可回放夹具(只读以外的唯一写入,显式 opt-in)。
- **路径白名单是「桥」的约束,不是 CLI 的**:`src/collect.ps1 -FixturePath` 接受任意路径(否则 `-DumpFixture` 抓出来的夹具无法在别处回放);**面板 host 半边**(见 §11)才执行白名单:只接受仓库内 `tests/fixtures/*.json` 的相对路径,绝对路径 / UNC / 含 `..` 一律 `fixture-rejected`。
- 回归:`tests/run-fixtures.ps1` → **7 case / 0 失败**(含「英文输出与中文输出逐项一致」「德式字段名 → unknown」「`Edge=FALSE` → blocked + 带回滚文案」「`-Role client` 不输出服务端项」「无 `-Peer` → unknown」「Win11 服务端:branch=win11 / DC=3600 s 降级 / serve owner=tailscaled / 仅降级 ⇒ exit 1」「`-Apply` 被拒」)。

---

## 9. 陌生用户 clone 后能否直接跑(自评)

**结论:能跑,而且默认就是只读、fail-closed。** 命令只有一条:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/src/collect.ps1 -CheckOnly
```

仍然依赖本机环境的地方(全部登记,并给出消除办法):

| # | 仍依赖什么 | 影响 | 消除办法(已实现/建议) |
| --- | --- | --- | --- |
| 1 | **Tailscale 的规则名** `Tailscale-Process` / `Tailscale-In` | 用户改过规则名 → `edge_rule_missing`(阻断)或 `ts_in_missing`(降级) | 已把判据写成「按名字查,查不到明确报缺」;**不猜**。若要支持改名,可加 `-RuleNamePattern` 参数(未实现,登记) |
| 2 | **netsh 的本地化字段名** | 非中/英系统(如德语)→ `NIC_PROFILE_ATTRIBUTION` = unknown + 原文 | 已实现模式外置:丢一个 `i18n/labels.de.json`(只写 `patterns`)即可;**Patterns 会合并加载**,不必改脚本 |
| 3 | **`-NonElevated` 下 `Get-NetConnectionProfile` 不可用** | 网卡 profile 归属只能走 netsh 文本 | 已实现三级来源(该 cmdlet → netsh → unknown),提权时自动用更可靠的那条 |
| 4 | **tailnet 地址必须存在** | 未登录/未连接 → `TAILNET_ADDRESS` = unknown,相关判定跟着 unknown | 这是「前置件缺失」的诚实表达,不是缺陷 |
| 5 | **`netsh`/`powercfg`/`netstat`/`tailscale.exe` 路径** | 一律自动发现(SystemRoot / ProgramFiles / LOCALAPPDATA / 注册表 / PATH),可用 `-ToolPath @{netsh='…'}` 覆盖 | 已实现 |
| 6 | **`settings.yaml` / patch 文件位置** | 走 `DSH_HOME` / `DSH_APP_DIR` / 进程镜像路径自动发现,可用 `-DshHome` / `-AppDir` 覆盖 | 已实现(找不到就是 unknown,不假装读到) |
| 7 | **控制台编码** | 默认按 OEMCP 解码;若某工具用了别的编码 | 已实现 `-OutputCodePage` 覆盖 |
| 8 | **`.ps1` 执行策略** | 陌生机器可能禁跑脚本 | 已文档化:必须 `-ExecutionPolicy Bypass -File`;脚本自身不写策略 |
| 9 | **i18n 目录缺失** | 判定仍成立(verdict/reasonKey/raw 全在),只有人读文案退化为 reasonKey | `labels.missingKeys` 会显式列出缺的键,便于自检 |

判断:**这 9 条都不构成「跑不起来」**,最多是「某些项 unknown」—— 而 unknown 正是设计要的结果(不猜)。所以对陌生用户的门槛是「要知道怎么解释 unknown」,不是「装不出来」。

---

## 10. 关于「113 KB 单文件是否拆 `src/data/*.psd1`」的判断

**建议:暂不拆,理由是拆分在这里会降低而不是提高可读性/可测性。**

1. 体积来源不是内嵌表格,而是 24 个检测项**各自的内联判定逻辑**(每项 10–30 行:探针 → 结构解析 → 判定 → 原始值装箱)。拆成 `data/*.psd1` 只能搬走「标题/原因文案」这类数据,而那部分**已经在 `i18n/labels.*.json` 里**(t25 快照:**89 个 `reason.*` 键**,其中 11 条 `rem_*` 处置文案;外加 **12 个本地化模式**与 24 个 `title.*` 键),`src/` 里本来就没有大块数据表。
2. 真正该外置的「易变数据」(本地化模式、人读文案、夹具)已经全部外置,并且是**可注入 + 双语夹具验证**的形态。
3. 拆文件会新增「PS 5.1 下 dot-source 路径/编码/`$PSScriptRoot`」这一类新的可移植性面,与本文遵循的「显式编码、少依赖」原则相冲突。
4. 若以后要拆,最小收益的拆法是:`src/collect.ps1`(框架+CLI) + `src/checks/*.ps1`(每组检测项一个文件,dot-source)。**不建议**拆成 `data/*.psd1`:psd1 的默认编码与解析器行为和 JSON 不同,会再引入一处编码坑。

单文件 + 外置 labels/fixtures 的代价是「约 **111 KB**(113,577 字节,纯 ASCII、无 BOM、`Parser::ParseFile` errors=0)的脚本要靠分节注释导航」,已用 `# section 1..6` 分节 + 每项一段的方式缓解。

---

## 11. Cordis host 半边(动态包 `guard-1` / `pkg-4`;源码已落盘 `src/host-half.js`)

> **状态快照(t16)**:`cordis_inspect_self()` 现返回 `plugins: []` —— 动态包在进程重启后消失(设计如此,不落盘)。
> 源码与哈希已落盘:`remote-tailnet-plugin/src/host-half.js`,sha256 = `464BB4059B282118D5626A09B759B4557E57734FAB69E6528B159B6BF5A74E7E`(19877 B)。
> 要复核 disposer / `terminate()`,按 `docs/install/install.md` §1 重新 define+run 一次即可。

**purpose(一句话)**:暴露一个只读姿态 Service,把 `collect.ps1` 的结构化判定(pass/degraded/blocked/unknown)按需查询出来给面板/模型用。

暴露面(最小):

| 面 | 名称 | 说明 |
| --- | --- | --- |
| Service | `remoteTailnetGuard`(`ctx.provide`) | `collect(options)` / `lastSummary()`;`readOnly: true`;`collector` 字段给出仓库相对路径 |
| 私有方法 | `remote-tailnet-guard/posture`(`harness.handle`) | **给 t6 的 client 半边用**:`host.call('remote-tailnet-guard/posture', {role,peer,peerName,fixture})` → `{ok,exitCode,summary,checks[]}` |
| 模型工具 | `remote_tailnet_posture` | 自证的触发面,参数 `role`/`peer`/`peerName`/`fixture` |

实现要点(全部与硬约束对齐):

- **只读**:只 spawn `powershell.exe -NoProfile -ExecutionPolicy Bypass -File <collect.ps1> -CheckOnly -AsJson`;不注册路由、不新增监听、不写文件、不读凭据。
- **可逆**:Service、私有方法、工具三者的 disposer 都挂在 `ctx.effect(...)` 的返回值里;effect 释放时还会 `terminate()` 正在运行的子进程。`cordis_stop guard-1` 即完全移除。
- **不 require `@deepseek-ai/dsh-client-runtime`**;没有 client 半边(本任务不碰 client);**没有任何「杀宿主+自拉起」逻辑**。
- **跨边界只传最小 JSON**:`checks[]` 只带 id/role/title/verdict/verdictLabel/reasonKey/reason/manualReview/manualQuestion/remediationAction/remediationRollback/autoApplied,**不带 `raw`**(raw 可能有几十 KB 的原文;需要原文时用 CLI `-OutFile`)。
- **无机器路径**:脚本定位用「fs 默认基准 → 逐级向上找 `remote-tailnet-plugin/src/collect.ps1`」的祖先回溯(实测 fs 的默认基准**不是**工作区根,直接相对解析会 `collector-missing`),命中的那一级同时作为子进程 cwd,使相对的 `-FixturePath` 生效。

激活步骤(我已在本次会话执行):

```
cordis_define(kind=new, idPrefix=guard)      → guard-1/pkg-1(失败:defineTool 的 required:false 不被 DSL 接受)
cordis_define(kind=existing, pluginId=guard-1) → guard-1/pkg-2(DSL 修正版)
cordis_run(guard-1, pkg-2, run)              → running(run-2)
cordis_define(kind=existing, pluginId=guard-1) → guard-1/pkg-3(祖先回溯定位)
cordis_run(guard-1, pkg-3, update)           → running(run-3)
cordis_define(kind=existing, pluginId=guard-1) → guard-1/pkg-4(有界检查带上 evidence/confidence;t5 收尾版)
cordis_run(guard-1, pkg-4, update)           → running(run-4)  ← 2026-09-24 快照;**t16 复核时已消失(plugins: [])**
remote_tailnet_posture(role="both", fixture="remote-tailnet-plugin/tests/fixtures/zh.json")
  → verdict=blocked exit=2 (pass=15 degraded=2 blocked=1 unknown=6),逐项与 CLI 一致
```

**t16 增补**:`pkg-4` 的源码已落盘为 `src/host-half.js`(sha256 见本节开头),并加上 `fixture` 参数白名单
(只接受仓库内 `tests/fixtures/*.json` 相对路径;绝对路径、UNC、`..` 一律 `fixture-rejected`)。
头注同时记录了一个实测差异:**CLI 直跑与插件 spawn 的计数可以不同** —— 插件子进程由 DSH 宿主进程派生,
不在本 agent 会话的受限令牌里,因此它**能**打开 tailscaled 命名管道,`TAILSCALE_CLI_LAYER`/`SERVE_PRESENT`
可能得到确定性结论;不要把两者当成同一组探针计数比较。

停止/回滚:`cordis_stop guard-1`(立即移除三个副作用);彻底删除用 `cordis_undefine guard-1`。
进程重启后动态包消失(不落盘),需要时重新 define+run;这不是缺陷,而是本版「不落盘、可逆」的取舍(持久化形态见 t3 的 profile 行结论)。

---

## 12. 已知限制(不装作没有)
1. **HTTPS/证书层**:PowerShell 5.1 无可靠 TLS+SNI 客户端路径 ⇒ 恒 unknown,附 Node 命令(本机 node 不在 PATH,见 baseline §1.4)。
2. **`tailscale serve status`**:agent 沙箱里必被命名管道拒 ⇒ 只能人工在普通窗口跑;CLI 读不出来时 `SERVE_PRESENT` 就是 `unknown`(按新语义**绝不因此判 pass**,也**绝不按 netstat 形状判 blocked**);读得到时判据是**目标端口 vs 实测 DSH 端口**(见 §5 第 11 条)。
3. **S0 段的「网络已断开连接」措辞**:由 `powercfg /a` 的本地化文本给出,无法机读 ⇒ 只给「S0 是否可用 + 原文」+ `manualReview`。
4. **对端相关判定**:没有 `-Peer` 就是 unknown;即便给了,`serve` 目标、ACL、对端电源都要对端在线复测(t2 的诚实分层)。
5. **本机 `NIC_PROFILE_ATTRIBUTION` 的 Pass 来源是 netsh 文本**(`Get-NetConnectionProfile` 非提权被拒、COM `NetworkListManager` 在本机 ProgID/CLSID 拿到的连接对象没有可用类型信息)⇒ 在非中英系统上会退化为 unknown(可加 `labels.<lang>.json` 解决)。
6. **未做**:soak/长窗口观测、对端实测、`-RuleNamePattern`、`src/checks/*.ps1` 拆分(见 §10)。

---

## 13. 设计规则 vs 实现:逐条就地复述

> 本节把采集器遵循的**设计规则本身**就地复述一遍,再写它的落地位置与证据 —— **读者不需要任何不随仓库发布的设计记录**。三条口径:
> (a) 每条先复述规则(采集器应当做什么),再写实际行为、为什么这样做、落地在哪;
> (b) 「已落地」= 实现里有对应的代码路径与用例;「未落地」见 §13.2,且原因必须能当规则读;
> (c) 与规则存在差异时,差异必须在正文里讲清楚,不能用「已对齐」一句话带过。

### 13.1 已落地(规则 → 实现)

| 规则(就地复述) | 落地位置 / 证据 |
| --- | --- |
| 配置面每一项都能覆盖、能追溯来源:参数 > 环境变量 > 自动发现 > 内置默认,并把生效来源打进输出 | `config[]` 里每个值带 `source`(param / env / auto / builtin-default / missing);`-Describe` 打印优先级 |
| DSH 端口按固定优先级发现:`-Port` > `$env:DSH_WEB_URL` > 内置 43120;用默认值时必须标注「未实测」 | 同左;输出里写明「用的是默认值,未实测」 |
| 提供一条只读的 `-Describe`,打印全部可覆盖项与实际生效来源 | `-Describe`(**26 行非空输出**,exit 0) |
| 零硬编码:脚本面按代码处理,不得出现用户名 / 主机名 / 绝对路径 / 真实 IP;夹具里的真实值一律占位化 | `collect.ps1` 与 `run-fixtures.ps1` 非 ASCII 字节 = 0,无用户名/主机名/绝对路径/真实 IP;仅保留 Windows GUID 与产品名常量;夹具里的用户路径替换成 `<DSH_HOME>` / `<APP_DIR>` |
| 不把本地化工具文本当安全判据:权威判据走注册表 / `.NET` / 原始 0x / GUID;确需文本时中英双语模式外置,且匹配失败 ⇒ `unknown` | 权威判据全部走结构化来源;文本路径见 §6 |
| 探针必须把 stdout / stderr / 退出码分开回传,退出码参与判定 | 探针返回 `stdout`/`stderr`/`exitCode` 三件套;`version` exit 0 不算可用 |
| 双语夹具 + 一个「匹配不上」的用例:zh/en 逐项等价,第三份(字段名不匹配)⇒ unknown | `zh.json` / `en.json` 逐项等价 + `localized-unmatched.json` ⇒ unknown;夹具由 `-DumpFixture` 真机抓取,非手工誊写 |
| 四态 + 低置信度必须显式:每项给出 status 与 `evidence.confidence`,文本解析路径不得报 pass | 每项 `status`(=verdict)、`evidence.confidence`;文本解析路径报 **degraded** |
| fail-closed + 四态分开计数:任何 `unknown` 不得返回 0;strict 模式把 `unknown` 升为 2 | `summary{pass,degraded,blocked,unknown}`;`-Strictness strict` 提升退出码 |
| 每项输出齐全:`{id, status, evidence{command, exitCode, source, raw?}}` | 每项都有 `id`/`status`/`verdict`/`reasonKey`/`commands[]`/`evidence{command,commands,exitCode,source,confidence,window,confidenceDowngrade}`/`raw` |
| 凭据纪律机械化自审 + fail-closed:不读凭据库 / bridge token / 浏览器 cookie 库 | `CREDENTIAL_DISCIPLINE` 自审项负责这一条 |
| 默认零写:只有显式 opt-in 才写 | 只有 `-OutFile` / `-DumpFixture` 两个显式 opt-in 写入 |
| 写操作要四道门槛(缺一不可),否则不实现写路径 | 本版**没有**写路径:`-Apply` 直接拒绝(exit 2),处置只打印命令 + 回滚 |
| 异常环境必须优雅降级并给出提示语,不得半途失败 | 无 tailscale / 非提权 / 无 pwsh / `DSH_HOME` 非默认 / 多 profile / 无 node / 代理干扰 都有显式分支与提示语 |
| 多 profile 不得静默取第一个 | 多于一个 profile 且未给 `-Profile` ⇒ `TRUSTED_HOSTS_PATCH` = unknown(`th_multi_profile`);给了 `-Profile` 只过滤 **profile 层**,app/包层 patch 始终保留(否则会把真 blocked 错判成 unknown —— 实测踩到并修复) |
| serve 换端口必须能被判出:**证据只来自可读的 `tailscale serve status` 的 proxy 目标端口**,与实测 DSH 端口比较;不等 ⇒ `blocked/serve_port_mismatch`;不可读 / 无可解析目标 ⇒ `unknown`;netstat 监听形状**只作佐证** | `SERVE_PRESENT` 现按此判定(带 command + rollback);用例 `fault-serve-target-port-mismatch`(正向)、`fault-serve-status-no-target`(不可解析)、`fault-serve-moved-port-8443`(负向对照) |
| 「明确不支持」清单必须同时出现在 `-Describe` 输出与本文 | `-Describe` 的最后 4 行 + 本文件 §12 |

### 13.2 未落地(附原因与替代做法)

| 规则(就地复述) | 现状 | 原因 / 替代做法 |
| --- | --- | --- |
| 夹具按**探针粒度**命名(每个探针一份 `<probe>.zh-CN.txt` + `<probe>.en-US.txt`) | 改用「场景级 JSON 夹具」(zh / en / unmatched / edge-false / win11) | 内容上等价(双语等价 + unknown case 都已断言),命名不同;要按探针粒度采集,可用 `-DumpFixture` 直接产出,不必改脚本 |
| 写操作配一对显式开关(`-AllowWrite` + `-Yes`) | 未实现 | 本版**没有任何**写路径,给一个默认关闭的写开关没有收益;真要做写动作时,按 §13.1 的「写操作四道门槛」规则实现 |
| 除行为断言外,还要有**扫描 / 单元 / 变异**三类测试脚本 | **已落地在测试套件里**:`tests/run-tests.ps1` + `tests/cases/`(**52 个用例:52 pass / 0 fail / 0 xfail / 0 xpass**),含零硬编码扫描 + 正向对照、locale 矩阵、隔离与可移植性用例 | 套件与采集器脚本分开维护;本文件自带的 `tests/run-fixtures.ps1` 仍是 7 条离线行为断言。本文只描述采集器行为,不把套件实现细节抄进来 |
| tailnet 地址发现可以走 `tailscale status --json` | 未采用 | 本机实测该命令必被命名管道拒(agent 沙箱边界)⇒ 走它只会多一个 unknown;留作「提权 / 普通窗口」下的可选增强 |
| 仓库层文件(`README.md` / `LICENSE` / `.github/`)的写法 | 本文件未涉及 | 它们属仓库层,与采集器行为无关(边界裁定见 §14.1) |

### 13.3 我主动发现并修掉的三个自伤缺陷(都在本次实测里暴露)

1. `$Args` 作为参数名 ⇒ `-f` 格式化静默失效,输出里满是 `{0}`(§6.3)。
2. `-Profile` 过滤把 **app 层 patch** 也一起滤掉 ⇒ 本机那条真实 blocked 被错判成 unknown(§13.1 的「多 profile 不得静默取第一个」行)。
3. 夹具回放时进程名拿不到 ⇒ 「serve 的 owner 是不是 tailscaled」无法离线证明;已把 **PID → 映像名**也做成可注入输入(`processes` 段)。

---

## 14. t25 一致性复核(改掉的 10 处不一致)+ 发布集边界裁定

> 复核口径(唯一事实来源):`src/collect.ps1` 的 param 注释与 `New-Check`/`Set-Verdict` 调用、一次真实运行(`-CheckOnly` / `-Role server` / `-Role client` / `-AsJson`)、`-Describe` 输出、`i18n/labels.*.json` 的键数、以及套件门禁的实测输出。

| # | 位置 | 旧文 | 现状 / 改法(t25) |
| --- | --- | --- | --- |
| 1 | §4 `SERVE_PRESENT` 行 + §2 unknown 清单「无非本机端的 serve 证据」 | 「netstat 里 tailnet 地址 + 443 + owner;owner 是别的进程 → 降级;没有 → unknown」 | 按 t23 新语义重写:证据 = **可读 `serve status` 的 proxy 目标端口**;目标 ≠ 实测 DSH 端口 ⇒ `blocked/serve_port_mismatch`;不可读/无可解析目标 ⇒ `unknown`;**监听形状只作佐证** |
| 2 | §4 `DSH_NETWORK_EXPOSURE` 行「lan → 降级」 | 与本文件 §5 第 7 条(t16 F6)自相矛盾 | 改为 **blocked**(实现里 `exposure_lan` 就是 blocked) |
| 3 | §2 `-CheckOnly -AsJson` 体积「151,744 字节」 | 早于 t16/t19/t23 的实现 | 实测 **315,260 字节**(t25 快照) |
| 4 | §2 `-Describe`「27 行」+ §13.1 同处 | 行数早已变化 | 实测 **26 行非空输出** |
| 5 | §2 夹具 `zh.json` 行「(服务端角色 14/2/1/2)」 | 没写清是哪个 role 的口径 | 拆成:默认 `role=both` 24 项 15/2/1/6;**加 `-Role server`** 19 项 14/2/1/2 |
| 6 | §2 win11 夹具行「`SERVE_PRESENT=pass(owner=tailscaled)`」 | 旧判据的表述 | 改为新语义的表述(可读目标 `43120` = 实测 DSH 端口 + 443 上有 2 条 tailscaled 监听);数字仍为 19 项 17/2/0/0、exit 1 |
| 7 | §5 第 3 条「本机实测 24 → 24,差集空」 | 绝对条数会漂 | 改为只断言**差集为空**,取证 = 套件门禁 `G2 wildcard listener set unchanged: OK`(26 个通配监听快照) |
| 8 | §5 第 6 条「`xfail-netstat-unreadable-wildcard-inventory` 由 XFAIL 变 XPASS,需 t11 翻标记」 | 那两个 xfail 用例早已被翻成正常用例 | 改为「套件里**没有任何 xfail**(`xfail held = 0` / `xpass = 0`)」 |
| 9 | §10「82 KB / 约 91 KB」「76 个原因键 + 10 条处置文案 + 10 个本地化模式」+ §13.2「扫描/单元/变异脚本**未实现**(只有 run-fixtures 的 7 个断言)」 | 体积、键数、套件状态全部过期 | 脚本 **113,577 字节**;labels = **89 个 `reason.*`(其中 11 条 `rem_*`)+ 12 个 patterns + 24 个 title**;套件 = `tests/run-tests.ps1` + `tests/cases/` **52 用例(52 pass / 0 fail / 0 xfail / 0 xpass)** |
| 10 | §2 的 `TRUSTED_HOSTS_PATCH` 证据块、§7 首条与 §7 的 `config[]` 示例:三处写着**用户主目录的绝对路径**(盘符 + `Users\` + 用户名那种形状) | 虽然用户名已是 `<USER>` 占位,但这条**形状**本身会命中发布集扫描的 `abs-user-path` | 统一改成 **`<DSH_HOME>`** 记号(与 §13.1 的 `<DSH_HOME>`/`<APP_DIR>` 口径一致),使发布集扫描**不依赖允许清单**也能为 0 |

另有两处**非「不一致」但影响可发布性**的补充:①新增 **§2.1 参数速查**(26 个参数,含旧文完全没提的 `-Lang`/`-Strictness`/`-ToolPath`/`-ShowRaw`/`-Apply`);②顶部加**链接口径**说明(内部资料不复述路径,验证流程指向仓库内 `CONTRIBUTING.md` §1/§2)。

### 14.1 发布集边界与去内部深链(已裁定;不再逐处再议)

三件事已经定了,写在这里,后来者不必再去问任何人:

1. **`docs/collect.md` 属于发布集。** 仓库门禁 `.github/scripts/repo-hygiene.ps1` 的 `$PublishRoots` 明确包含 `docs\collect.md`,门禁在默认扫描根上对它做阻断项扫描。
2. **其余设计、复核与实测记录不随仓库发布。** `.gitignore` 第 1 节(`INTERNAL MATERIAL — deliberately NOT part of the released repository`)逐条排除它们;`README.md` 有对应的边界句(`Internal analysis and review material does not ship with the repository`);门禁把这份排除清单纳入检查(`missingIgnores`)。
3. **由此得出的唯一规则(已裁定):发布集文件不得把读者指向未发布文件。** 本文件已按这条规则把所需的全部设计规则**就地复述**(§6 与 §13);其他发布集文件里若还有同类引用,按同一条规则机械处理即可 —— 就地复述,或改指仓库内文件(例如 `CONTRIBUTING.md`)。

> 一条历史归属说明(不是缺陷,也无需处理):`tests/cases/README.md` 里有一处历史描述仍提到早已删除的 xfail 用例名,那是作者在同轮记录的历史归属。
