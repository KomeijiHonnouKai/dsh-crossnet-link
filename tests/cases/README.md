# tests/ — 跨环境与故障注入测试套件

- **最后更新时间**: 2026-09-24（v2；t23:①`SERVE_PRESENT` 改为「只看 `tailscale serve status` 的 proxy 目标端口」—— 删掉 `xfail-serve-moved-port-should-block`,新增 `fault-serve-target-port-mismatch`(正向)+ `fault-serve-status-no-target`(不可解析),`fault-serve-moved-port-8443` 改为负向对照;②扫描命中改为**按每个匹配值**分类,新增 §7.1 已批准占位符允许清单,正向对照用例增种一个占位符。本次命令:`powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/tests/run-tests.ps1`、`… -Filter scan`、`… -Filter serve`。v1 为 v0 骨架后的首个定稿;t27:①§4 的历史说明改为显式「**历史**:该用例已于 t23 重构为新用例 `fault-serve-target-port-mismatch`」并补上当前快照 `52/52/0/0`;②§8-1 去掉一处指向未发布内部资料的取证深链,改为就地说明。**t31**:①§7.2 标题不再点名内部资料(改称「设计规格」;规格文件本身由 `.gitignore` §1 登记,那才是可访问的落点);②本文件整文件行尾由 **CRLF 转 LF**(仓库约定,只改行尾不改文字)。t31 本次命令:`powershell -NoProfile -Command '<收窄判据:发布集 *.md 内指向内部资料的 markdown 链接>'`、`powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/tests/run-tests.ps1`、`powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/.github/scripts/repo-hygiene.ps1 -Json`;**t38**:①`filescan-no-repo-write-paths` 的写动词断言收窄到只读面 —— 加显式 `allowFiles` 只放 `tools/uninstall.ps1`(本仓库**唯一**的可选写入组件:默认干跑、必须 `-Apply` 才写、写前必先落备份),其余 `*.ps1` 仍要求 0 命中;②新增 `kind=uninstall` 与 **10 条离线夹具用例**(见 §6 表尾与 §7.3),驱动 `tools/uninstall.ps1` 并断言退出码、`-AsJson` 报告字段、备份文件集、`MANIFEST.json` 的 sha256/字节数、幸存文件,以及「干跑后临时目录逐字节不变」。t38 本次命令:`powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/tests/run-tests.ps1`、`… -Filter '^uninstall'`、`… -Filter '^uninstall|filescan-no-repo-write-paths'`、`… run-fixtures.ps1`、`… repo-hygiene.ps1 -Json`）;**t43**:①新增一条 `kind=filescan` 用例 `plugin-package-shape`(常驻插件包的形状:①`plugin/package.json` 声明的 `main`/`exports['./client']`/`bundle.patch` 目标都存在 ②两个 ESM 半边 `require(` 计数为 0、JSX 与 TypeScript 专有语法为 0 ③browser bundle 自注册为 package name 且 `require(` 只允许平台 seed `react` ④insert 行 `id`/`name` 都等于 package name 且 `disabled: true` ⑤`docs/install/plugin-package.md` 带可粘贴命令与「三步启用/四步回滚」两节),用例数 **63→64**;②新增 `panel/plugin-preflight.ps1`(常驻插件只读预检,退出码 0/1/2,不写任何文件)由该用例以 `parses`/`no-bom`/`ascii-only` 三条断言钉住;③`tests/cases/README.md` 新增 §7.5 记录该用例与它的限制。t43 本次命令:`powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/tests/run-tests.ps1`、`… -Filter plugin-package-shape`、`… -List`、`powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/panel/plugin-preflight.ps1`、`powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/.github/scripts/repo-hygiene.ps1 -Json`）
- **本套件自己的领地**: `tests/run-tests.ps1`、`tests/cases/`。`tests/fixtures/`（中英双语原始夹具）属 t16 领地，`tests/run-fixtures.ps1` 是 collect.ps1 作者自带的夹具回归；两者本套件**只读**使用。
- **一条命令自证**（Windows PowerShell 5.1，无需安装任何模块）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/tests/run-tests.ps1
```

- **退出码**: `0` = 全过（xfail 保持失败也算过）；`1` = 至少一条用例失败。逐条打印 `case id -> 规则 -> EXPECTED / ACTUAL`。
- **运行纪律**（本套件全程遵守，也是它自己的行为约束）：
  - **R1**：不使用任何客户端 Inspect（`platform:"client"`）——套件完全不碰 Cordis，只跑 PowerShell；
  - **R2**：不使用 `ego_*`、不发起无超时网络请求；需要探测连通性时只用 .NET `TcpClient` 且超时 ≤5 秒（且默认被 `-NoNative` 关掉，改由夹具注入结果）；
  - **R3**：v0 先落盘再迭代；
  - **R4**：同一调用失败一次就换做法，不原样重试（开发记录：`Prop` 的单元素数组展开、`[BLOCKED]` 被当成正则字符类，都是换做法而不是重试）；
  - **R5**：`run-tests.ps1` 文件头记录最后更新时间与本次使用的命令。
- **其他开关**: `-List`（打印下面的对照表）、`-Filter <正则>`（按 id 选）、`-Only <kind>`（按类型选）、`-Verbose`（打印每个子进程的完整命令行与注入的环境变量）、`-KeepTemp`（保留临时目录便于排查）。

## 1. 为什么不用 Pester

本机只有 PowerShell 5.1 自带的 **Pester 3.4.0**：它的 `Should -Be` / `BeforeAll` / 发现规则与 Pester 4/5 完全不同，而 Pester 5 离线拿不到。为了守住「clone 下来一条命令就能跑」这个承诺，`run-tests.ps1` 自带一个约 200 行的断言核（`Assert-Eq` / `Assert-In` / `Assert-NotIn` / `Assert-True` / `Assert-Match` / `Assert-NoMatch`），零外部依赖。

## 2. 目录结构

```
tests/
  run-tests.ps1              入口 + 断言核 + 各类 grader（唯一可执行入口）
  cases/
    _base/server-en.json     干净服务端基线（英文工具文本）
    _base/server-zh.json     同一台机器，中文 netsh / powercfg 文本
    <case-id>/case.json      一条用例：注入 + 期望（夹具内联或引用 _base）
  fixtures/                  只读：t16/smith 的原始抓取夹具
  run-fixtures.ps1           只读：t16/smith 的 collect.ps1 夹具回归
```

`_base/server-en.json` 与 `server-zh.json` 描述**同一台完全健康的服务端**，两者只差工具输出的语言。用例用 `base` + `layer` 只写自己那一点差异（`layer` 是深合并：对象按键合并，数组/标量整体替换），因此「注入了什么」在文件里一眼可见。

## 3. case.json 字段

| 字段 | 作用 |
|---|---|
| `id` / `title` / `titleZh` | 用例标识与一句话标题（两者都打印，控制台 ASCII 与中文并存） |
| `kind` | `collector` / `scan` / `filescan` / `isolation` / `portability` / `prereq` |
| `why` | 这条用例存在的原因、它证明的规则、依据（写给人看，也是 review 的入口） |
| `inject` | 「注入了什么」的一句话，进入对照表 |
| `expectSummary` | 「期望判定 + 退出码」的一句话，进入对照表 |
| `base` | 引用的基线夹具（相对 `tests/cases/`） |
| `layer` / `unset` | 在基线上的覆盖 / 删除的探针路径（`a.b.c`） |
| `args` / `env` | 传给 collect.ps1 的参数 / 只在该用例生效的环境变量；两者都支持 `<CASEDIR>` `<TMP>` `<ABSENT_HOME>` `<ABSENT_APP>` 占位符 |
| `tmp` | `collector`/`isolation` 用：临时 `DSH_HOME`（可带 `settings` 与 `profiles`） |
| `checkOnly` / `noNative` | 默认 `true`：自动附加 `-CheckOnly -AsJson -NoNative`；`-Describe` / `-Apply` 用例关掉 `checkOnly` |
| `expect` | 期望集合，见下表 |

默认注入 `-NoNative` 是**硬要求**：`-NoNative` 之下，夹具里没写的探针一律「不可用 ⇒ unknown」，而不是偷偷去读真实机器。这是让用例在任何机器上结果一致的前提（实测教训：少了它，`unset native.netstat` 的用例会通过自动发现找到真实监听并报 pass）。

### 3.1 `expect` 支持的键

| 键 | 含义 |
|---|---|
| `exitCode` / `exitCodeNot` / `exitCodeIn` | 退出码精确值 / 不等于某值 / 属于集合 |
| `summary` | `total/pass/degraded/blocked/unknown` 计数（用于把整体行为钉住） |
| `verdicts` / `notVerdicts` | 某个 check 的四态等于 / 不等于（`notVerdicts` 是 fail-closed 的主要武器） |
| `reasons` / `reasonNot` | `reasonKey` 精确等于 / 不等于（区分「权限被拒」与「没配置」靠它） |
| `confidence` / `confidenceDowngrade` | 低置信度路径必须显式暴露，不能被当成「已证明」 |
| `present` / `absent` | 该 check 是否应被角色过滤掉 |
| `manualReview` / `remediation` | 必须标人工复核；`applied` 必须为 `false` 且 command/rollback 非空 |
| `raw.<点路径>` | 直接断言 `raw` 内部字段（支持数组下标；数字同时可能是对象的键，取真实键优先、下标次之） |
| `config` | 生效来源（`value` + `source`），例如端口是从参数还是环境变量来的 |
| `info` | 报告顶层字段（`collector.readOnly`、`collectorFaultsCount` 等） |
| `stdoutMatch` / `stdoutNotMatch` / `stderrEmpty` | 原始 stdout 的正则（注意：`ConvertTo-Json` 会把 `<` `>` `&` 转义成 `\uXXXX`，断言这类字符要挑不含尖括号的子串） |
| `sameVerdictsAs` | 与前面某条用例的**全部**判定逐条相等（中英等价就是用这个钉住的） |

### 3.2 六种 grader

| kind | 做什么 |
|---|---|
| `collector` | 组装夹具 → 真跑 `src/collect.ps1` → 断言报告。**判定逻辑一定是真跑的**，夹具只替换外部命令的「输出」，从不 mock 判定本身。 |
| `scan` | 六条禁止模式扫 `*.ps1/*.psm1/*.js/*.mjs/*.md/*.json`；`root=planted` 会在临时目录里种下违规样本做阳性对照，样本本身用 `{PLANT-PEER-IP}` `{PLANT-HOSTNAME}` `{PLANT-USERPATH}` 占位，保证用例文件自身干净。 |
| `filescan` | 静态断言：PS 语法可解析、无 BOM、纯 ASCII、某段文本存在、某字面量在仓库里 0 命中 / 至少 N 次命中 / 命中只出现在允许的路径。 |
| `isolation` | 造一个像真的临时 `DSH_HOME`（settings + 两个 profile + 一个从不读取的凭据占位文件），跑前跑后对每个文件取 SHA256，任何新增/删除/改动即失败。 |
| `portability` | 把 `src/collect.ps1` 与 `i18n/` 复制到名为「插件 目录 带空格」的临时目录（用码点拼出，保证本脚本仍是纯 ASCII）再跑，并与原地跑逐条比对判定与退出码。 |
| `prereq` | 跑 `panel/prereq.ps1`，断言 `ranAnyInstall=false`、不存在 `-Yes/-Apply/-Force` 声明、文本里没有 `msiexec/Start-Process/runas`。 |

## 4. xfail 语义（已知缺口）

一条用例可以带 `"xfail": {reason, severity, requiredFix}`：它描述一个**已确认还存在**的缺口（期望行为 vs 实际行为）。

- 它仍然失败 ⇒ 打印 `XFAIL`，**不算套件失败**（缺口还在，符合预期）；
- 它开始通过 ⇒ 打印 `XPASS`，**套件失败**，提示把这行标记翻掉。

这样「已知缺口」既不会阻塞绿灯，也不会在修好之后悄悄腐烂成一句过期的注释。**当前没有任何 xfail**（t43 复跑快照：`cases run = 64 / passed = 64 / failed = 0 / xfail held = 0 / xpass = 0`，退出码 0；t41 那年是 63，t43 加了一条 `plugin-package-shape`）。**历史**：最后一条 xfail 用例已于 **t23** 按新语义重构为新用例 **`fault-serve-target-port-mismatch`**（连同负向对照 `fault-serve-moved-port-8443`），它原来的名字 `xfail-serve-moved-port-should-block` **已从套件中删除**，不应再被当作现存用例引用 —— 机制保留着，供下一个真缺口用。

本套件在开发过程中用这条机制抓到并推动了 3 个真实缺陷的修复，修好后按语义翻成了正常用例（历史保留在各用例的 `why` 里）：
1. `WILDCARD_LISTENER_INVENTORY` 在 netstat 行读不出来（状态词被本地化）时**报 pass** —— 安全判定上的假通过；
2. 同一检查在 netstat 探针完全不可用时**报 pass**；
3. `networkExposure: lan` 报 `degraded`，而规格 §4.1/§7-13 要求 `blocked`。

## 5. 套件级 gate（真实机器，跑在夹具之外）

| gate | 内容 | 判定 |
|---|---|---|
| `G1a` | `tests/` 下没有文件被创建/删除/修改 | 失败 |
| `G1b` | 被测的 `collect.ps1` 在整个运行期间哈希不变 | 失败（结果必须归属于同一个修订） |
| `G1c` | `tests/` 之外的文件在运行期间变了 | 只报告（并打印被测 collect.ps1 的哈希）：本套件只写 `%TEMP%`，这类改动属于同时编辑仓库的人，不应污染判定；静态证据见 `filescan-no-repo-write-paths` |
| `G2` | 通配监听集合：只把**本套件可能拉起的进程**（powershell/pwsh/conhost/cmd/dsh/node）新开的监听算作失败，其它软件的活动只报告 | 失败/报告 |
| `G3` | 跑完不留临时目录 | 失败 |

## 6. 用例对照表（`-List` 输出，逐字）

| case id | kind | injected input | expected judgement + exit code |
|---|---|---|---|
| `canary-filescan-treewide-assertions-live` | canary | a throw-away tree under %TEMP% with, per assertion type, one planted violation and one clean twin | planted => the hit-count failure with EXPECTED 0 / ACTUAL 1 plus its raw detail line (literal-zero), 'found 1' below minCount 3 (literal-min) and the confinement failure with EXPECTED 0 / ACTUAL 1 plus its raw detail line (hits-confined-to); clean twins => 0 failures each |
| `fault-apply-refused` | collector | the -Apply switch, with no -CheckOnly | exit 2 and a REFUSED explanation on stdout |
| `fault-describe-surface` | collector | the -Describe switch | exit 0 with the resolution order, the exit-code contract and the NOT-supported list; no report is produced |
| `fault-dsh-no-listener` | collector | the DSH listening row removed from both netstat snapshots (only the 443 row survives) | DSH_LOOPBACK_ONLY unknown/dsh_no_listener (never pass), exit != 0 |
| `fault-dsh-port-from-env` | collector | environment DSH_WEB_URL=http://127.0.0.1:49999 with no -Port on the command line | config dshPort=49999 source=env:DSH_WEB_URL, DSH_LOOPBACK_ONLY pass, and 43120 appears nowhere |
| `fault-dsh-port-param-then-discovery` | collector | DSH_WEB_URL points at 49999 while -Port 50001 is passed; only 49999 is actually listening | config dshPort=50001 source=param, discoveredPort=49999, judgedPort=49999, pass |
| `fault-dsh-wildcard-exposed` | collector | netstat shows 0.0.0.0:49999 owned by the DSH process next to the loopback row | DSH_LOOPBACK_ONLY blocked/dsh_exposed + WILDCARD_LISTENER_INVENTORY blocked/inv_dsh_exposed, exit 2 |
| `fault-edge-drift-blocked` | collector | the stored Tailscale-Process rule carries Edge=FALSE while Tailscale-In is untouched | TAILSCALE_PROCESS_EDGE_DB blocked/edge_false while TAILSCALE_IN_RULES stays pass, exit 2 |
| `fault-edge-registry-unavailable` | collector | the firewall_rules registry probe removed; the netsh rule echo is still available | EDGE_DB unknown/edge_registry_unavailable and TAILSCALE_IN_RULES unknown/fw_registry_unavailable, exit != 0 |
| `fault-https-401-manual-only` | collector | a client-role run with a peer: the collector is expected to declare the HTTPS judgement as out of scope, not to fabricate one | HTTPS_CLIENT_ONLY unknown/https_client_only, manualReview=true, manual Node command present |
| `fault-magicdns-hostnotfound` | collector | DNS probe for peer.example.test returns socketError=HostNotFound | MAGICDNS_RESOLVE blocked/dns_hostnotfound, exit 2 |
| `fault-netstat-unavailable` | collector | both netstat snapshots removed from the fixture while native access is disabled (-NoNative) | DSH_LOOPBACK_ONLY, WILDCARD_LISTENER_INVENTORY and SERVE_PRESENT all unknown, exit != 0 |
| `fault-nic-public-blocked` | collector | netsh show currentprofile lists the Tailscale adapter under the Public section | NIC_PROFILE_ATTRIBUTION blocked/nic_public with remediation, exit 2 |
| `fault-node-missing` | collector | PATH reduced to System32 so the node lookup fails | HTTPS_CLIENT_ONLY unknown/https_client_only with nodeAvailable=false, manualReview=true, exit != 0 |
| `fault-nonadmin-probes-denied` | collector | the admin-only cmdlet and powercfg query replaced by an access-denied result; the netsh fallback removed as well | NIC unknown/nic_probe_failed, POWER unknown/power_unparsed, FIREWALL_PROFILES still pass from the registry, exit != 0 |
| `fault-peer-connected-isolation-clean` | collector | 443 connected; 135, 5357 and the DSH port refused | PEER_TCP_443 pass/peer_443_ok + PEER_ISOLATION_PROBES pass/peer_iso_ok, no blocked item |
| `fault-peer-dsh-port-open-on-peer` | collector | TCP probe result for 203.0.113.5:<DSH port> replaced by 'connected' | PEER_ISOLATION_PROBES blocked/peer_iso_dsh_open, exit 2 |
| `fault-peer-offline-timeout` | collector | TCP probe result for 203.0.113.5:443 replaced by 'timeout' (5000 ms budget) | PEER_TCP_443 blocked/peer_443_timeout, exit 2 |
| `fault-peer-other-ports-open` | collector | TCP probe result for 203.0.113.5:135 replaced by 'connected' | PEER_ISOLATION_PROBES degraded/peer_iso_too_open, no blocked item |
| `fault-peer-refused` | collector | TCP probe result for 203.0.113.5:443 replaced by 'refused' | PEER_TCP_443 blocked/peer_443_refused, exit 2 |
| `fault-serve-moved-port-8443` | collector | the tailnet 443 row replaced by a tailnet 8443 row owned by tailscaled, while 'tailscale serve status' is readable and its proxy target equals the measured DSH port | SERVE_PRESENT unknown/serve_unknown (never pass, never blocked - the listener shape is not evidence) and the 8443 tailnet row visible in WILDCARD_LISTENER_INVENTORY |
| `fault-serve-not-listening` | collector | the tailnet 443 row removed from both netstat snapshots; 'tailscale serve status' exits 1 | SERVE_PRESENT unknown/serve_unknown (never pass), exit != 0 |
| `fault-serve-status-no-target` | collector | tailscale serve status exits 0 with 'No serve config' (no proxy target line) on the otherwise clean baseline | SERVE_PRESENT unknown/serve_unknown, manualReview=true, never pass/degraded/blocked, exit != 0 |
| `fault-serve-target-port-mismatch` | collector | a readable 'tailscale serve status' whose proxy target is 127.0.0.1:43120 while the DSH port is 49999 (netstat carries a tailscaled 8443 row and no 443) | SERVE_PRESENT blocked/serve_port_mismatch with command + rollback, never pass/degraded/unknown, exit != 0 (negative control: fault-serve-moved-port-8443) |
| `fault-settings-key-absent` | collector | settings.yaml without a networkExposure line | DSH_NETWORK_EXPOSURE unknown/exposure_key_absent, exit != 0 |
| `fault-settings-lan-exposure` | collector | settings.yaml carrying networkExposure: lan | DSH_NETWORK_EXPOSURE blocked/exposure_lan with a rollback, never pass, exit 2 |
| `fault-tailscale-cli-probe-unavailable` | collector | -NoNative with the tailscale ip -4 probe removed from the fixture | TAILSCALE_CLI_LAYER unknown/ts_probe_failed, exit != 0 |
| `fault-tailscale-logged-out` | collector | 'tailscale ip -4' exits 1 with the logged-out text | TAILSCALE_CLI_LAYER unknown/ts_not_logged_in, exit != 0 |
| `fault-tailscale-not-installed` | collector | fixture declares tools.tailscale as absent, so the candidate chain resolves nothing | TAILSCALE_CLI_LAYER blocked/ts_not_installed with command + rollback, config tool.tailscale empty/'missing', exit 2 |
| `fault-tailscale-not-installed-fails-no-install` | collector | fixture declares tools.tailscale absent, the run is rendered for a human instead of as JSON | exit 2, stdout shows the blocked item, names Tailscale, and mentions installing it by hand |
| `fault-tailscale-pipe-denied` | collector | version exits 0, while 'ip -4' exits 1 with the ProtectedPrefix access-denied text | TAILSCALE_CLI_LAYER unknown/ts_pipe_denied (never ts_cli_ok, never ts_not_logged_in), exit != 0 |
| `fault-tailscale-service-absent` | collector | the Tailscale service query returns 'cannot find any service' | TAILSCALE_SERVICE blocked/ts_service_missing, exit 2 |
| `fault-tailscale-service-stopped` | collector | Get-Service Tailscale returns status Stopped | TAILSCALE_SERVICE blocked/ts_service_stopped, exit 2 |
| `fault-trustedhosts-empty-blocked` | collector | the whole patch chain replaced by one file that carries trustedHosts: [] | TRUSTED_HOSTS_PATCH blocked/th_blocked with a rollback, exit 2 |
| `fault-trustedhosts-key-absent` | collector | the patch chain replaced by files that never mention trustedHosts | TRUSTED_HOSTS_PATCH unknown/th_key_absent, exit != 0 |
| `fault-trustedhosts-multi-profile` | collector | a temp DSH_HOME with profiles Alpha and Beta, no -Profile argument | TRUSTED_HOSTS_PATCH unknown/th_multi_profile, exit != 0 |
| `fault-trustedhosts-profile-selected` | collector | the same temp DSH_HOME with profiles Alpha and Beta, this time with -Profile Alpha | TRUSTED_HOSTS_PATCH pass/th_ok, config profile=Alpha, exit 1 |
| `filescan-no-localized-hardmatch-and-ascii` | filescan | the plugin's *.ps1 sources, checked for the netstat state literal, the localized field names, the Get-Pattern call sites and the ASCII/BOM/parse rules | no Chinese literals in *.ps1; the state token only in collect.ps1 and run-tests.ps1; >=4 Get-Pattern netsh_ call sites |
| `filescan-no-repo-write-paths` | filescan | the suite's own source text plus every *.ps1 in the repository, scanned for write verbs; `tools/uninstall.ps1` is the only allow-listed path | run-tests.ps1: parses, ASCII-only, no BOM; every write verb outside the allow-listed `tools/uninstall.ps1` has 0 hits |
| `filescan-pattern-table-matches-spec` | filescan | the runner source and docs/defensive-spec.md, checked for the shared pattern names | all six pattern names present in both files |
| `isolation-no-writes-to-dsh-home` | isolation | a temp DSH_HOME with settings.yaml, two profiles and an untouched .credentials.yaml; the collector is pointed at it with -DshHome | every file hash unchanged, no file created or deleted, CREDENTIAL_DISCIPLINE pass, exit 1 |
| `locale-culture-en-us-tools-zh` | collector | -Lang en selected, Chinese netsh/powercfg tool text, cmdlet probe removed | NIC_PROFILE_ATTRIBUTION degraded/nic_ok and FIREWALL_PROFILES pass from CHINESE text while the English label file is active |
| `locale-en-clean-baseline` | collector | nothing: the clean server baseline (_base/server-en.json) replayed fully offline (-NoNative) | pass=18 degraded=1 blocked=0 unknown=0, exit 1 |
| `locale-en-netsh-text-only` | collector | -NoNative with the cmdlet probe removed from the fixture, so only the netsh text can answer | NIC_PROFILE_ATTRIBUTION degraded/nic_ok confidence=low confidenceDowngrade=true |
| `locale-netstat-state-localized` | collector | netstat -ano output whose state column reads the localized word instead of LISTENING, including a real 0.0.0.0 listener row | DSH_LOOPBACK_ONLY unknown/dsh_no_listener and WILDCARD_LISTENER_INVENTORY unknown/netstat_unavailable, exit != 0 |
| `locale-powercfg-labels-randomized` | collector | powercfg /query output with every label replaced by random words while the AC/DC 0x lines stay intact | POWER_STANDBY_IDLE_AC_DC pass/power_ok (both indices 0) |
| `locale-unmatched-tool-text` | collector | netsh section headers and the whole powercfg structure replaced with unmatched spellings (no hex indices, no pattern hit) | NIC_PROFILE_ATTRIBUTION unknown/nic_unparsed with raw preserved, POWER_STANDBY_IDLE_AC_DC unknown/power_unparsed, exit != 0 |
| `locale-zh-clean-baseline` | collector | the same state with Chinese netsh/powercfg text (_base/server-zh.json), offline | identical verdict map to locale-en-clean-baseline, exit 1 |
| `locale-zh-netsh-text-only` | collector | -NoNative, cmdlet probe removed, Chinese netsh section headers and Chinese state word | identical verdict map to locale-en-netsh-text-only |
| `plugin-package-shape` | filescan | the plugin package (plugin/package.json, plugin/cordis.patch.yml, plugin/lib/*.js), docs/install/plugin-package.md and the preflight script, checked for the declared-path, module-shape and disabled-row facts | package.json declares module/main/exports[./client]/bundle.patch and each target exists; require( appears only in plugin/lib/client.js (seed react); no JSX, no TypeScript syntax; the insert row has id==name==package.json name and disabled: true; the doc carries the paste-ready commands and the three-step/four-step headings |
| `portability-chinese-space-path` | portability | src/collect.ps1 plus i18n/labels.*.json copied into a temp folder named '插件 目录 带空格', then run with the same fixture | same 19 verdicts and exit code as the in-place run; NIC pass, POWER pass, exit 1 |
| `scan-md-json-confined-to-docs-and-fixtures` | scan | every *.md and *.json in the plugin, with the two documented roots excluded | 0 hits outside docs/ and tests/fixtures/ |
| `scan-plugin-script-surface` | scan | the plugin's own *.ps1 / *.psm1 / *.js / *.mjs files, scanned with the six patterns from defensive-spec section 2.1 | 0 hits (no allowlist for the script surface) |
| `scan-positive-control-catches-each-extension` | scan | a temp tree with a planted peer address (.ps1), host name (.md), absolute user path (.json) and one approved placeholder (.md) | exactly 3 hits, one per extension, plus 1 approved placeholder match that is not counted |
| `uninstall-apply-backup-verifiable` | uninstall | the revertable dsh-settings fixture with -Apply -AsJson and an explicit -StateDir inside the case temp dir | exit 0, backup.created=true with the 4 always-present files, every MANIFEST sha256/byte count verifies, the revert stays would-do in fixture mode |
| `uninstall-apply-firewall-capture-and-residue` | uninstall | the revertable firewall fixture with -Apply -AsJson: the firewall observation is present, so the revert is attributable while the residue scan still sees the rule | exit 1, backup contains firewall-rules.txt and verifies, the revert stays would-do in fixture mode, residue item recorded-firewall-rules-absent = residue |
| `uninstall-checkonly-without-journal-not-clean` | uninstall | an empty fixture (no journal, no observations) with -CheckOnly -AsJson | exit 1, attribution=unavailable, residue unknown (never pass), cordis unknown but exempt, nothing written |
| `uninstall-checkonly-writes-nothing` | uninstall | the clean fixture (one noop record plus the cordis record) with -CheckOnly -AsJson | exit 0, attribution=available, and the case temp dir is byte-identical afterwards |
| `uninstall-left-alone-foreign-change-kept` | uninstall | a fixture whose power-plan observation (0x00001c20) matches neither the recorded before nor the recorded after value, plus a second record still at its before value | exit 1, records[0] left-alone/changed_by_somebody_else with full provenance, records[1] noop, no record executable, nothing written |
| `uninstall-plan-dry-run-writes-nothing` | uninstall | a fixture with one noop record and one cordis-dynamic-package record, plus -Plan -AsJson | exit 0, classification noop=1, unknownExempt=1, backup.created=false, and nothing in the case temp dir changed |
| `uninstall-purge-without-apply-refused` | uninstall | an empty fixture plus -PurgeBackup -AsJson and no -Apply | exit 2, refusals[0].reasonKey=purge_without_apply (journal_required second), temp dir untouched |
| `uninstall-recordafter-without-journal-refused` | uninstall | an empty fixture plus -RecordAfter -AsJson | exit 2, summary.verdict=refused, refusals[0].reasonKey=journal_required, and the case temp dir is untouched |
| `uninstall-removefiles-hash-mismatch-kept` | uninstall | a plugin-files record whose after value is a deliberately wrong sha256, a real installed-file.js under the case temp dir, and -Apply -RemoveFiles -AsJson | exit 1, deletions[0] kept (hash guard), installed-file.js still present with the same bytes |
| `uninstall-revert-only-attributable` | uninstall | a fixture whose dsh-settings observation equals the recorded after value plus a power-plan record still at its before value, with -Plan -AsJson | exit 0 clean, revert=1 noop=1 left_alone=0, records[0] revert/equals_recorded_after executable=true action=would-revert, records[1] noop executable=false |

## 7. 覆盖面

### 7.1 对齐本任务验收条文

| 验收要求 | 由哪些用例覆盖 |
|---|---|
| 零外部依赖、PS 5.1 直接跑、退出码 0/1 | 入口本身（`run-tests.ps1` 无 Pester/无 node/无网络）；实测 63 例 0 fail 时退出码 0 |
| 对端离线 | `fault-peer-offline-timeout`（超时）`fault-peer-refused`（拒绝）`fault-peer-connected-isolation-clean`（正常）`fault-peer-other-ports-open`（ACL 过宽）`fault-peer-dsh-port-open-on-peer`（对端 DSH 口可达）`fault-magicdns-hostnotfound` |
| serve 未配置 / 已关闭 | `fault-serve-not-listening`、`fault-serve-status-no-target`、`fault-serve-moved-port-8443`、`fault-tailscale-service-stopped`、`fault-tailscale-service-absent` |
| DSH 端口被改 | `fault-dsh-port-from-env`（环境变量发现）、`fault-dsh-port-param-then-discovery`（参数优先 + 实测发现回退） |
| ACL 只放 443 而 serve 指向了错误端口 | `fault-serve-target-port-mismatch`（正向:目标 ≠ 实测 DSH 端口 ⇒ blocked + 回滚）、`fault-serve-moved-port-8443`（负向对照:同样的监听形状但目标正确 ⇒ unknown,证据仍在报告里）、`fault-serve-status-no-target`（读不出目标 ⇒ unknown,不猜） |
| cookie 过期（401） | `fault-https-401-manual-only`、`fault-node-missing`（同一条判定的降级形态） |
| trustedHosts 缺失（403） | `fault-trustedhosts-empty-blocked`、`fault-trustedhosts-key-absent`、`fault-trustedhosts-multi-profile`、`fault-trustedhosts-profile-selected` |
| 非管理员（提权探针被拒） | `fault-nonadmin-probes-denied` |
| 未安装 tailscale | `fault-tailscale-not-installed`、`fault-tailscale-not-installed-fails-no-install`、`fault-tailscale-cli-probe-unavailable` |
| tailscale CLI 被命名管道拒 | `fault-tailscale-pipe-denied`（同时证明 `version` 退出码 0 不算可用）、`fault-tailscale-logged-out`（不同 reasonKey） |
| 缺 node | `fault-node-missing` |
| 路径含空格或中文 | `portability-chinese-space-path` |
| locale：中英文两套 netsh/powercfg/netstat + 未知文本判 unknown | `locale-en-clean-baseline`、`locale-zh-clean-baseline`（逐条等价）、`locale-en-netsh-text-only`、`locale-zh-netsh-text-only`、`locale-culture-en-us-tools-zh`（culture 英文 + 工具中文）、`locale-unmatched-tool-text`、`locale-powercfg-labels-randomized`、`locale-netstat-state-localized` |
| 隔离性：不改系统、不改 profile、不新增监听 | `isolation-no-writes-to-dsh-home`、`fault-apply-refused`、`filescan-no-repo-write-paths` + 套件级 `G1a/G1b/G2/G3` |
| 每条用例给「注入 → 期望」对照表 | 第 6 节（由 `-List` 生成） |
| 零硬编码扫描覆盖 `*.ps1/*.md/*.json` | `scan-plugin-script-surface`、`scan-md-json-confined-to-docs-and-fixtures`、`scan-positive-control-catches-each-extension`、`filescan-pattern-table-matches-spec` |
| 判定逻辑不得被 mock | 设计上：`kind=collector` 全部真跑 `src/collect.ps1`，夹具只替换探针输出；`-NoNative` 保证「没注入的探针」变 unknown 而不是回落真实访问 |

### 7.2 与设计规格的检查清单对齐

> 「§10」指内部设计规格(portability / defensive design spec)的 §10 检查清单。该规格文件按 `.gitignore` §1 属**内部资料、不随仓库发布**,所以下表把每条**判据本身**都写出来,读者不需要打开规格文件;它被登记为内部资料这件事可在 `.gitignore` §1 与门禁脚本 `.github/scripts/repo-hygiene.ps1` §0 复核(t27/t31 口径:发布集文件不深链内部资料)。

| §10 条目 | 由哪些用例覆盖 |
|---|---|
| §1 `-Describe` 列出全部可覆盖项与实际生效来源 | `fault-describe-surface`、`fault-dsh-port-from-env`、`fault-dsh-port-param-then-discovery` |
| §2 零硬编码 0 未白名单命中 + 空格/中文路径可跑 | `scan-*`（3 条）、`portability-chinese-space-path` |
| §3 无本地化文本判据、双语 fixture、未知文本判 unknown | 8 条 `locale-*`、`filescan-no-localized-hardmatch-and-ascii` |
| §4 四态 + evidence、unknown 不算 pass、blocked 退出码非 0 | 每条 collector 用例都断言 `verdict` + `reasonKey`；fail-closed 专项：`fault-netstat-unavailable`、`locale-netstat-state-localized`、`fault-dsh-no-listener`、`fault-settings-key-absent`、`fault-nic-public-blocked` |
| §5 输出无凭据、未读凭据 | `CREDENTIAL_DISCIPLINE` 被 `locale-en-clean-baseline` / `isolation-no-writes-to-dsh-home` 断言；（未读取 `.credentials.yaml` 内容本身属于实现契约，套件用「跑完文件哈希不变」间接证明） |
| §6 默认零写 + 写操作四道门槛 | `fault-apply-refused`、`filescan-no-repo-write-paths`、`isolation-no-writes-to-dsh-home`；`filescan-no-localized-hardmatch-and-ascii` 顺带断言脚本里不存在 `msiexec/Start-Process/runas` 之类执行路径 |
| §7 13 类异常环境 | 非 Windows：无（套件只跑 Windows，且本轮不伪造平台）；无 tailscale：`fault-tailscale-not-installed*`；非管理员：`fault-nonadmin-probes-denied`；PS 5.1：入口本身；缺 node：`fault-node-missing`；空格/中文路径：`portability-chinese-space-path`；`DSH_HOME` 非默认：`fault-trustedhosts-multi-profile`/`-profile-selected`（临时 `DSH_HOME`）；多 profile：同上；端口被改：`fault-dsh-port-*`；DSH 未运行：`fault-dsh-no-listener`；serve 目标端口：`fault-serve-target-port-mismatch` / `fault-serve-status-no-target` / `fault-serve-moved-port-8443` |
| §8 ≥8 类环境差异 | 上述各条 + `locale-culture-en-us-tools-zh`（语言/区域差异） |
| §9 版本矩阵与「不支持」声明出现在 `-Describe` | `fault-describe-surface`（断言 `NOT supported` 与解析顺序同时出现在输出里） |

### 7.3 uninstall 用例（离线夹具驱动，t38）

`tools/uninstall.ps1` 是**本仓库唯一**的可选写入组件（默认干跑，必须 `-Apply` 才写，写前必先落备份并逐文件校验）。围绕它新增的 10 条 `kind=uninstall` 用例全部离线、零网络、可重复：`-FixturePath` 提供 journal 与当前观测，`-StateDir` 指向用例临时目录，断言落在**退出码 + `-AsJson` 字段 + 文件系统事实**三层上。

| 要证明的性质 | 用例 |
|---|---|
| 干跑不写（对临时目录做 sha256 前后快照，逐字节不变） | `uninstall-plan-dry-run-writes-nothing`、`uninstall-checkonly-writes-nothing`、`uninstall-left-alone-foreign-change-kept`、`uninstall-recordafter-without-journal-refused`、`uninstall-purge-without-apply-refused` |
| 只回滚可归属项（正例）+ 别人改过就不动（反例） | 正例 `uninstall-revert-only-attributable`（`now == after` ⇒ `revert` / executable=true）；反例 `uninstall-left-alone-foreign-change-kept`（`now` 既不是 before 也不是 after ⇒ `left-alone` + 完整 provenance + exit 1） |
| 备份先落且可被第三方校验 | `uninstall-apply-backup-verifiable`、`uninstall-apply-firewall-capture-and-residue`（逐条重算 `MANIFEST.json` 里的 sha256 与字节数） |
| 清理有门（删除必须同时带 `-Apply`） | `uninstall-purge-without-apply-refused`（exit 2 / `purge_without_apply`） |
| 哈希不匹配 ⇒ 保留文件 + exit 1 | `uninstall-removefiles-hash-mismatch-kept` |
| 没有 journal 时不假绿灯 | `uninstall-checkonly-without-journal-not-clean`（exit 1 / `attribution=unavailable`）、`uninstall-recordafter-without-journal-refused`（exit 2 / `journal_required`） |

### 7.4 防失效正控（canary，t41）

`canary-filescan-treewide-assertions-live` 是**给测试自己上的测试**。背景：t32–t38 期间 `Invoke-FileScanCase` 里一个无条件 `continue` 让 `literal-zero` / `literal-min` / `hits-confined-to` 三类断言**从未执行**，两条 filescan 用例一直是 vacuous pass —— 能被静默关掉的静态断言比没有断言更糟。

这条 canary 的做法是**驱动真实引擎**（不是重写一份断言）：handler 在 `%TEMP%` 下种违规文件、通过 `$script:ScanRootOverride` 把引擎指向那棵树，再对引擎产出的 failure 记录做断言（rule 文本 + EXPECTED + ACTUAL，日志里由 `CANARY evidence` 行原样打印）。三类各有一个「种了必须红」和一个「没种必须绿」的孪生。

**它真的能抓住死代码（对照实验，t41 现场做过）**：

- 把那个无条件 `continue` 临时加回 ⇒ canary **FAIL**，6 条断言给出 `EXPECTED 1 / ACTUAL 0` 与 `EXPECTED true / ACTUAL failures: 0`，evidence 行变成 `0 engine failures`（正是死代码特征）；
- 去掉该 `continue` ⇒ canary **PASS**，evidence 行恢复成原始文本：`literal /Set-Content/ hit count :: EXPECTED 0 / ACTUAL 1`、`appears at least 3 times :: EXPECTED true / ACTUAL found 1`、`all /T41CANARY/ hits inside /^allowed// :: EXPECTED 0 / ACTUAL 1`。

规则：任何人改 `Invoke-FileScanCase` 之后，只要这条 canary 变红，就说明三类断言被静音了 —— **不要改 canary 让它变绿**。

### 7.5 常驻插件包形状（t43）

`plugin-package-shape` 是**离线静态**用例：它不安装任何东西、不碰用户 profile、不加载 Cordis。它证明的是「这个包在**形状上**可以被 profile 装进去」，而不是「它已经跑起来了」。

它断言的事实与取证来源：

| 断言 | 事实 | 取证来源（仓库内） |
|---|---|---|
| 声明路径存在 | `main` / `exports['.']` / `exports['./client']` / `exports['./package.json']` / `dsh.bundle.patch` 五个目标都存在 | `plugin/package.json`;参照 `<DSH_HOME>\profiles\desktop\node_modules\dsh-ego-browser\package.json:5-12,22-36` 与 `…\@nanmicoder\dsh-agent-teams\package.json:5-19,65-81` |
| 两个 ESM 半边 | `plugin/lib/index.js`(host)与 `plugin/lib/client/index.js`(client 源码)`require(` 计数 **0** | 两份文件；形态参照 agent-teams 的 `lib/client/index.js`(2872 字节,打包前的 ESM 源码) |
| browser bundle | `plugin/lib/client.js` 用 `window.__ModuleLoader__.load({ id: "remote-tailnet-guard", … })` 自注册,`require("…")` 只允许平台 seed(实测只有 `react`) | `plugin/lib/client.js`;平台侧依据 `<APP_DIR>\node_modules\@deepseek-ai\dsh-client-modules\lib\client.js:229-233`(注册)、`:248`(未注册即抛)、`:300-310`(require 只认 seed/已物化/图行),seed 表见 `dsh-web-frontend\dist\assets\index-*.js` |
| 无 JSX / 无 TS 语法 | 表格里 `</[A-Za-z]`、`return (<` 与 5 类 TypeScript 专有标记全库 `*.js` **0 命中**;`React.createElement` 只出现在两个客户端半边 | 6 个 `*.js`(4 个既有 + 本任务 2 个) |
| insert 行 | 恰好一个 `- insert:` 块、恰好一行,`id`=`name`=package name,且 **`disabled: true`** | `plugin/cordis.patch.yml`;disabled 语义见 `<APP_DIR>\node_modules\@deepseek-ai\cordis-plugin-loader\lib\index.js:359-378,389-392`,客户端图跳过 disabled 见 `dsh-client-modules\lib\index.js:775-781` |
| 文档 | `docs/install/plugin-package.md` 同时含 `dsh plugin --profile`、`<DSH_HOME>`、`disabled: true`、`plugin-preflight.ps1` 与「三步启用」「四步回滚」两节 | 该文档 |

**它不能证明什么（不改口径）**：真实加载。`plugin/` 的 host/client 半边**从未在真实 DSH 里跑过**，「设置里出现该分区」必须在用户机器上启用一次才算验证。另外 `panel/plugin-preflight.ps1` 的 `node --check` 三连在本机是 **SKIP**（`node` 不在 PATH），所以「能作为普通 JS 解析」目前只有正则级静态断言，不是解析器级证明。

## 8. 诚实的限制（不藏）

1. ~~**`SERVE_PRESENT` 的「serve 换端口」只做到 fail-closed，没做到规格的 `blocked`**~~ **已在 t23 闭环,且口径先被 t22 的实验纠正过一次**:原裁定想拿「tailnet 侧存在 tailscaled 拥有的非 443 监听、且没有 443」当正向证据 —— **t22 实测推翻**了它:本机健康状态就长这个形状(`<PEER_IP>:33588` 与 `[<ULA_IP>]:56868` 都是 tailscaled 自有端点),按那条规则实现会把**任何已登录节点**误报成「serve 换了端口」(`%TEMP%` 副本对照:原实现 `unknown` vs 该补丁 `blocked`,otherPorts=33588/56868)。t23 改为**只看 `tailscale serve status` 的 proxy 目标端口**:目标 ≠ 实测 DSH 端口 ⇒ `blocked/serve_port_mismatch`(带 command + rollback);CLI 不可读、或输出里没有可解析目标 ⇒ `unknown`。原意(serve 指向别处 ⇒ 只放行 443 的窄 ACL 静默失效)**没有削弱**,由 `fault-serve-target-port-mismatch` 正向钉住,并由 `fault-serve-moved-port-8443` 作负向对照。(本条的取证 = t22 的 `%TEMP%` 副本对照 + t23 的落地,记在本套件 `fault-serve-*` 用例的 `why` 与 §10 的原始尾部输出里,**不指向任何未发布的内部资料**。)
2. **`blocked/ts_not_installed` 只能靠夹具钩子跑出来**：实测证明环境变量重定向在 PS 5.1 下无法表达「未安装」——子进程会重建 `%ProgramFiles%`；因此该分支用夹具的 `tools.<name>` 钩子注入（它同样是「所有候选路径都解析不到」这一状态），而**不是**真的卸掉 Tailscale。
3. **无法在本机验证的形态**：非 Windows 平台分支、真实对端在线（对端可能离线，一律用夹具模拟 connected/refused/timeout）、真实 TLS/证书与 401/403 的区分（collector 刻意不发 HTTP 请求，故只给 unknown + 人工命令）。
4. **同时编辑仓库时 `G1c` 只会报告**：被测 `collect.ps1` 若在运行中途被改，`G1b` 会硬失败（结果必须属于同一修订）；其它文件的变化只报告，避免把别人的编辑算成套件的写入。**任何一条全绿结论都必须在同一次运行里 `G1b` 为 OK**。
5. **日志不逐字入库**：collector 的报告里带有本机主机名与 `%TEMP%` 下的绝对路径。为了守住零硬编码（`scan-md-json-confined-to-docs-and-fixtures` 要求 `tests/cases/` 下的 `.md`/`.json` 0 命中），原始输出留在任务报告里，仓库内只保留不含机器标识的摘要。

6. **uninstall 用例是夹具模式（fixture mode），不碰真实系统面**：`kind=uninstall` 一律带 `-FixturePath` 并显式给 `-StateDir`（离线运行因此永远不会创建真实的 `%USERPROFILE%` 状态目录）。fixture 模式下 `tools/uninstall.ps1` **不会**改动系统面：每一条可归属的回滚都以 `would-do` / `executed=false` 出现在报告里（`uninstall-apply-backup-verifiable` 与 `uninstall-apply-firewall-capture-and-residue` 正是断言这一点）。真机执行 `Remove-NetFirewallRule` / `powercfg` / `tailscale serve reset` 的系统面路径只做了静态与分支验证，**不在本套件里真机跑** —— 要真机验证，必须在明确接受「会改本机防火墙/电源/serve」的机器上人工执行。

7. **写动词规则的两个**刻意**边界（t41 裁定，已记录不磨平）**：①**删除类动词(`Remove-Item`)不纳入该 pattern** —— 它在本套件、`tests/run-smoke.ps1` 与 `.github/scripts/repo-hygiene.ps1` 里被合法地用于 `%TEMP%` 清理;若硬禁就得靠 allowFiles 把这些文件放行,规则随即失去意义。匹配是**大小写敏感**的,所以「移动类动词」那个选项不会再把它意外卷进来。②**真正的强保证是路径判据**——「每个写动词的路径参数都必须落在 `%TEMP%` 下」——它是**路径**判据而不是命中计数判据,**本次未实现**,按已知局限记录(要落地需要一段能提取每个调用点路径实参的静态分析,或一条「跑一遍套件后断言仓库树零变化」的运行期判据,而后者已由套件级 `G1a/G1c` 部分覆盖)。

## 9. 怎么加一条用例

1. 建目录 `tests/cases/<case-id>/case.json`；
2. 从 `_base/server-en.json`（或 `server-zh.json`）出发，用 `layer`/`unset` 只写差异；
3. 写 `why`（这条用例证明什么规则、依据是什么）、`inject`、`expectSummary`；
4. `expect` 里**至少**断言 `verdict` 或 `exitCode`，涉及 fail-closed 的一律加 `notVerdicts`；
5. 跑 `run-tests.ps1 -Filter <case-id> -Verbose`，把结果贴进 `expect`；
6. 先确认它在**旧行为**下会失败（否则它不是一条测试），再确认它在当前行为下通过。

## 10. 最近一次全绿运行

- 命令：`powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/tests/run-tests.ps1`（t43 定格；t23 的 52 例 + t38 的 10 条 uninstall 用例 + t41 的 1 条 canary 用例 + t43 的 1 条 `plugin-package-shape` 用例 = **64**）
- 被测 `src/collect.ps1` SHA256：`06A69B349FFFF7E348A73B5C49BA2D42F024F84440BBC77241F75CE37A21A9A5`
- 结果：`cases run = 64 / passed = 64 / failed = 0 / xfail held = 0 / xpass = 0`，退出码 **0**（64 = t23 的 52 + t38 新增的 10 条 `kind=uninstall` 用例 + t41 新增的 1 条 `kind=canary` 防失效正控 + t43 新增的 1 条 `kind=filescan` 常驻插件包形状用例；`xfail held` 与 `xpass` 仍同时为 0）
- 另外两条同轮全绿：`tests/run-fixtures.ps1` = `ALL PASS: 7 cases, 0 failed assertions`（退出码 0）；`.github/scripts/repo-hygiene.ps1 -Json` = `verdict: CLEAN (0 blocking finding(s))`、`blockingTotal=0`、`files=104`（退出码 0）。**files 计数说明（t43 实测）**：本次比 §10 上一次快照（99）多出的文件里，有 **3 个是本任务新增的发布集文件** —— `panel/plugin-preflight.ps1`、`docs/install/plugin-package.md`、`tests/cases/plugin-package-shape/case.json`；另有 `README.zh-CN.md` 被同一窗口的另一个任务登记进 `$PublishRoots`。**`plugin/` 目录目前不在 `$PublishRoots` 里**，本任务**没有**擅自改发布集（发布集定义在 `.github/scripts/repo-hygiene.ps1`，属别的成员领地），留给 captain 决定是否把它纳入。
- skip：**没有**。本套件没有 skip 机制：`-Filter`/`-Only` 只会减少运行条数并在头部如实打印 `cases run`，任何被选中的用例都会真实执行并给出 PASS/FAIL/XFAIL/XPASS 之一。
- 尾部原始输出（不含机器标识，逐字节选：canary 的 evidence 行 + 首尾各一条用例 + 套件级门）：

```
        CANARY evidence literal-zero(planted): rule=literal /Set-Content/ hit count :: EXPECTED 0 / ACTUAL 1
        CANARY evidence literal-zero(clean): 0 engine failures
        CANARY evidence literal-min(short): rule=literal /Get-Pattern 'netsh_/ appears at least 3 times :: EXPECTED true / ACTUAL found 1
        CANARY evidence hits-confined-to(outside): rule=all /T41CANARY/ hits inside /^allowed// :: EXPECTED 0 / ACTUAL 1
[ 1] PASS  canary-filescan-treewide-assertions-live planted => the hit-count assertion failure with EXPECTED 0 / ACTUAL 1 plus its raw detail line (literal-zero), the min-count failure reporting 'found 1' below minCount 3 (literal-min) and the confinement failure with EXPECTED 0 / ACTUAL 1 plus its raw detail line (hits-confined-to); clean twins => 0 failures each
# t43 新增的用例在本次运行里的序号是 [50](目录名 p 排在 l 之后、s 之前);下面这段 uninstall 用例的编号仍是 t38 的原文,本次运行里它们整体是 [55]..[64]。
[50] PASS  plugin-package-shape                   package.json declares module/main/exports[./client]/bundle.patch and each target exists; require( appears only in plugin/lib/client.js (seed react); no JSX, no TypeScript syntax; the insert row has id==name==package.json name and disabled: true; the doc carries the paste-ready commands and the three-step/four-step headings
# 注:t41 新增的 canary 目录名以 c 开头、排在全部 fault-* 之前,所以下面这些用例在 t41 运行里的序号整体 +1([53]→[54] … [62]→[63]);t43 又加了一条 p 开头的用例,它们再 +1([53]→[55] … [62]→[64])。逐字原文保留 t38 的编号,末尾汇总行才是本次(t43)的真实值。
[53] PASS  uninstall-apply-backup-verifiable      exit 0, backup.created=true with the 4 always-present files, every MANIFEST sha256/byte count verifies, the revert stays would-do in fixture mode
[54] PASS  uninstall-apply-firewall-capture-and-residue exit 1, backup contains firewall-rules.txt and verifies, the revert stays would-do in fixture mode, residue item recorded-firewall-rules-absent = residue
[55] PASS  uninstall-checkonly-without-journal-not-clean exit 1, attribution=unavailable, residue unknown (not pass), cordis unknown but exempt, nothing written
[56] PASS  uninstall-checkonly-writes-nothing     exit 0, attribution=available, and the case temp dir is byte-identical afterwards
[57] PASS  uninstall-left-alone-foreign-change-kept exit 1, records[0] left-alone/cchanged_by_somebody_else with provenance, records[1] noop, no record executable, nothing written
[58] PASS  uninstall-plan-dry-run-writes-nothing  exit 0, classification noop=1, unknownExempt=1, backup.created=false, and nothing in the case temp dir changed
[59] PASS  uninstall-purge-without-apply-refused  exit 2, refusals[0].reasonKey=purge_without_apply (and journal_required second), temp dir untouched
[60] PASS  uninstall-recordafter-without-journal-refused exit 2, summary.verdict=refused, refusals[0].reasonKey=journal_required, and the case temp dir is untouched
[61] PASS  uninstall-removefiles-hash-mismatch-kept exit 1, deletions[0] kept (hash guard), installed-file.js still present with the same bytes
[62] PASS  uninstall-revert-only-attributable     exit 0 clean, revert=1 noop=1 left_alone=0, records[0] revert/equals_recorded_after executable=true action=would-revert, records[1] noop executable=false

--- suite-level gates (real machine, measured outside the fixtures) ---
G1a no file under tests/ was created, deleted or modified: OK
G1b the collector under test is unchanged for the whole run: OK (06A69B349FFFF7E3...)
G1c no file outside tests/ changed during the run: OK
tested collector sha256: 06A69B349FFFF7E348A73B5C49BA2D42F024F84440BBC77241F75CE37A21A9A5
G2  wildcard listener set unchanged: OK (26 listeners)
G3  temp dirs removed (no leftovers): OK

cases run     : 64
passed        : 64
failed        : 0
xfail held    : 0 (known gaps that still exist - they do not fail the suite)
xpass         : 0 (a known gap disappeared - the suite fails until the marker is flipped)
skipped       : 0 (assertions whose target is deliberately unpublished and declares ifMissing=skip; a skip never fails the run)
ALL PASS
```

> 若 `G1c` 打印了 `NOTE - files outside tests/ changed...`，说明运行期间有人在编辑仓库（不是本套件写入）；`G1b` 才是「结果属于同一修订」的判据。