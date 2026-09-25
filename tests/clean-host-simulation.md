# 干净机器模拟（clean-host simulation）

> 最后更新：2026-09-24（t45）。本文回答一个问题：**CI 在一台"没有 Tailscale、没有 DSH、全新 Windows Server"上红了 6 条用例，而同一份代码在参考机器上全绿** —— 为什么，怎么在本机复现，怎么修，以及怎么防止下次再靠"推上去撞 CI"来发现这类问题。

## 1. 根因（有源码行号 + 有复现输出）

**一句话**：`src/collect.ps1` 解析 `netstat` / `netsh` / `powercfg` / `tailscale` 四个工具路径时，**只有当夹具声明了 `tools.<name>` 才走夹具，否则一律走真机**（注册表 → Program Files → Program Files (x86) → LOCALAPPDATA → PATH → `Get-Command`）；而 `-NoNative` **不拦这一层**。基线夹具 `tests/cases/_base/server-en.json` / `server-zh.json` 原本**没有 `tools` 块**，所以在参考机器上解析到的是真的 `C:\Program Files\Tailscale\tailscale.exe`，在干净 runner 上解析结果是空。

证据链：

| # | 位置 | 事实 |
|---|---|---|
| 1 | `src/collect.ps1:937-966` | 工具解析循环：`if ($null -ne $script:Fixture) { $fxTool = Get-FixtureProp 'tools' $tn ... continue }`，否则 `Resolve-Tool` 走真机候选路径 |
| 2 | `src/collect.ps1:1292-1317` | `TAILSCALE_CLI_LAYER` 的判定顺序：`if (-not $tsExe) { blocked/ts_not_installed }` **在** 看注入的 `native.tailscale_ip4` 之前 —— 工具没解析到就直接 blocked |
| 3 | `tests/run-tests.ps1`（`Resolve-CaseArgs`） | 每个用例默认带 `-CheckOnly -AsJson -NoNative -DshHome <absent-home> -AppDir <absent-app>`：探针层是夹具驱动的，**工具解析层不是** |
| 4 | `tests/cases/_base/*.json`（修复前） | 没有 `tools` 块 ⇒ 上面第 1 条的"否则"分支在每一条 collector 用例上都生效 |

因此：干净机器上 `$tsExe` 为空 ⇒ `blocked/ts_not_installed` ⇒ 整份报告的退出码从 `1` 变 `2`，凡是断言 `TAILSCALE_CLI_LAYER` 非 blocked、或断言 `exitCode 恰好是 1 / 不能是 2` 的用例全部变红。

## 2. 本机复现（不用 CI）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/tests/run-tests.ps1 `
  -SimulateCleanHost `
  -Filter 'fault-dsh-port-from-env|fault-peer-connected-isolation-clean|fault-peer-other-ports-open|fault-tailscale-cli-probe-unavailable|fault-tailscale-logged-out|fault-tailscale-pipe-denied'
```

**修复前的原始输出**（6/6 全红，与 CI 注解逐字一致）：

```
cases run     : 6
passed        : 0
failed        : 6
  - fault-dsh-port-from-env :: exit code :: expected=1 :: actual=2
  - fault-peer-connected-isolation-clean :: exit code :: expected=anything except [2] :: actual=2
  - fault-peer-connected-isolation-clean :: verdict TAILSCALE_CLI_LAYER :: expected=pass :: actual=blocked
  - fault-peer-other-ports-open :: exit code :: expected=1 :: actual=2
  - fault-tailscale-cli-probe-unavailable :: verdict TAILSCALE_CLI_LAYER :: expected=unknown :: actual=blocked
  - fault-tailscale-cli-probe-unavailable :: reason TAILSCALE_CLI_LAYER :: expected=ts_probe_failed :: actual=ts_not_installed
  - fault-tailscale-cli-probe-unavailable :: reason TAILSCALE_CLI_LAYER :: expected=anything except [ts_cli_ok, ts_pipe_denied, ts_not_logged_in, ts_not_installed] :: actual=ts_not_installed
  - fault-tailscale-logged-out :: verdict TAILSCALE_CLI_LAYER :: expected=unknown :: actual=blocked
  - fault-tailscale-logged-out :: reason TAILSCALE_CLI_LAYER :: expected=ts_not_logged_in :: actual=ts_not_installed
  - fault-tailscale-pipe-denied :: verdict TAILSCALE_CLI_LAYER :: expected=unknown :: actual=blocked
  - fault-tailscale-pipe-denied :: reason TAILSCALE_CLI_LAYER :: expected=ts_pipe_denied :: actual=ts_not_installed
```

CI（run 36000196743 / job 107634684291）注解里的原文 —— `fault-tailscale-logged-out :: verdict TAILSCALE_CLI_LAYER :: expected=unknown :: actual=blocked`、`reason :: expected=anything except [ts_cli_ok, ts_pipe_denied, ts_not_logged_in, ts_not_installed] :: actual=ts_not_installed`、`:: reason expected=ts_probe_failed :: actual=ts_not_installed` —— **与上表逐字对上**。

> **注解取证的已知上限（t45，captain 确认）**：GitHub 每一步最多保留 **10 条注解**，而当时那版 CI 包装先发 6 条 `FAIL` 行、再发末尾 20 行，于是真正带字段明细的 `FAILURES` 块被挤掉，10 条里只留下 3 条 tailscale 明细。所以 `fault-dsh-port-from-env`（以及两条 peer 用例的部分字段）**没有 CI 注解原文可引**：它们的归类依据是**本机 `-SimulateCleanHost` 复现**（上表第 34、35、37 行的原始输出），不是 CI 日志。t47 已把"注解优先级改成先发 `FAILURES` 逐条明细"写进验收，这类明细以后不会再丢。

## 3. 修复（不在断言上让步）

- **只改 `tests/cases/_base/server-en.json` 与 `server-zh.json`**：新增 `tools` 块，把四个工具**钉死在夹具里**（`netstat` / `netsh` / `powercfg` → `C:\Windows\System32\*`，`tailscale` → `C:\Program Files\Tailscale\tailscale.exe`），并加一条 `_toolsNote` 记录原因。
  这些路径只是**身份**不是机器事实：夹具模式下已声明的探针**不会被执行**，只有"有没有安装"这一条分支会读它。
- **6 条用例的 `case.json` 一个字节都没改** ⇒ 断言强度不变。
- `fault-tailscale-not-installed` **仍然是独立判定**：它自己把 `tools.tailscale` 覆写成 `""`（"所有候选路径都解析不到"），继续得到 `blocked/ts_not_installed` + 修复建议 + `exit 2`；上面 5 条仍是 `unknown` + 各自的 reasonKey。两类判定没有被合并。
- 没有使用任何"放宽断言"的手段（没有把 `exitCode` 改成 `exitCodeNot`，没有删 `reasonNot`，没有加白名单）。

| 用例 | 断言字段 | 修复前（干净机器） | 修复后（干净机器模拟） |
|---|---|---|---|
| `fault-dsh-port-from-env` | `exitCode=1`；`config.dshPort.source=env:DSH_WEB_URL`；`DSH_LOOPBACK_ONLY=pass`；`judgedPort=49999`；报告里不出现 `"value": "43120"` | `exitCode=2`（被 `TAILSCALE_CLI_LAYER=blocked` 拉高）[^注解上限] | 原断言 **全部通过** |
| `fault-peer-connected-isolation-clean` | `exitCodeNot 2`；`TAILSCALE_CLI_LAYER/SERVICE=pass`；`PEER_TCP_443=pass/peer_443_ok`；`PEER_ISOLATION_PROBES=pass/peer_iso_ok` | `exit=2`；`TAILSCALE_CLI_LAYER=blocked` | 原断言 **全部通过** |
| `fault-peer-other-ports-open` | `exitCode=1`；`PEER_ISOLATION_PROBES=degraded/peer_iso_too_open`；`PEER_TCP_443=pass` | `exit=2` | 原断言 **全部通过** |
| `fault-tailscale-cli-probe-unavailable` | `unknown/ts_probe_failed`；`reasonNot[ts_cli_ok,ts_pipe_denied,ts_not_logged_in,ts_not_installed]`；`raw.ip4.available=false` | `blocked/ts_not_installed` | 原断言 **全部通过** |
| `fault-tailscale-logged-out` | `unknown/ts_not_logged_in`；`reasonNot[ts_pipe_denied,ts_cli_ok]` | `blocked/ts_not_installed` | 原断言 **全部通过** |
| `fault-tailscale-pipe-denied` | `unknown/ts_pipe_denied`；`reasonNot[ts_cli_ok,ts_not_logged_in,ts_probe_failed]`；`raw.version.exitCode=0`、`raw.ip4.exitCode=1` | `blocked/ts_not_installed` | 原断言 **全部通过** |
| `fault-tailscale-not-installed`（对照） | `blocked/ts_not_installed` + `config.tool.tailscale=missing` + remediation | 本来就通过 | 仍 **blocked/ts_not_installed**（与上面 5 条仍是不同判定） |

[^注解上限]: **归类依据 = 本机 `-SimulateCleanHost` 复现**（§2 第 34 行的原始输出），不是 CI 注解 —— 该用例的 CI 明细因 GitHub「每步最多 10 条注解」的上限未取到（captain 已于 t45 确认是注解被挤掉，不是漏找；t47 会把注解优先级改成先发 `FAILURES` 逐条明细）。

## 4. 一页 recipe：在本机验"机器无关"

```powershell
# ① 模拟干净机器跑整套（应 64/64 全绿、skipped=0）
powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/tests/run-tests.ps1 -SimulateCleanHost

# ② 常规整套（同一份代码，参考机器）
powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/tests/run-tests.ps1

# ③ 夹具回归 / 门禁 / 门禁自测
powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/tests/run-fixtures.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/.github/scripts/repo-hygiene.ps1 -Json
powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/.github/scripts/repo-hygiene.ps1 -SelfTest
```

期望（2026-09-24 实测，t45）：

```
① cases run 64 / passed 64 / failed 0 / ALL PASS（exit 0，skipped 0 —— 说明没有夹具需要补 tools）
② cases run 64 / passed 64 / failed 0 / ALL PASS（exit 0）
③ ALL PASS: 7 cases, 0 failed assertions
③ verdict: CLEAN (0 blocking finding(s)) / blockingTotal=0
③ self-test: 16 control(s), 0 failed
```

## 5. `-SimulateCleanHost` 的行为与边界

**它做什么**：对每个用例，在基线/内联/`layer` 之后检查夹具有没有钉住那四个工具；**没钉住的**就注入成"缺失"（等价于干净机器上真机解析为空），并打印一行 `SKIP clean-host simulation ...` 说明注入了哪些。这样任何"依赖机器才成立"的用例都会在本机变红，而不是推上去才红。

**它不做什么（边界，别过度解读）**：

1. 它**只**模拟"工具解析为空"这一类依赖 —— 这正是 CI 那 6 条的根因。它**不**假装是一台真干净机器：真机上还有别的差异（没有 DSH 进程、没有服务、没有注册表项），而套件里这些面本来就是夹具驱动的（`native.*` / `services.*` / `registry.*` / `cmdlets.*` / `files.*` / `network.*`），并且默认带 `-NoNative`；`appDir`/`DSH_HOME` 也由 `-AppDir <absent-app>` / `-DshHome <absent-home>` 固定。
2. 它**不会**让已钉住工具的夹具变红（`_base` 修复之后，整轮 `skipped=0` 就是"没有夹具依赖机器"的证据）。
3. 它**不是** CI 的替代品：CI 的价值是在真实全新系统上跑一遍。它只是把"这类依赖"提前到本机可见。
4. 新增 collector 用例时：**要么**用 `_base`（已含 `tools`），**要么**自带 `tools`（或在 `why` 里写明为什么它故意不 pin，例如 `fault-tailscale-not-installed` 用 `tools.tailscale=""` 表达"所有候选路径都解析不到"）。

## 6. 复跑本页所有结论的最小命令

```powershell
$f='dsh-crossnet-link/tests/run-tests.ps1'   # 相对克隆所在的那一级目录;克隆在别处时换成你自己的路径
# 复现（把 _base 的 tools 块临时删掉即可回到修复前状态）
Select-String -Path (Join-Path (Split-Path $f) 'cases\_base\server-en.json') -Pattern '"tools"'
# 取证
powershell -NoProfile -ExecutionPolicy Bypass -File $f -SimulateCleanHost
powershell -NoProfile -ExecutionPolicy Bypass -File $f -SimulateCleanHost -Filter 'fault-tailscale-'
```
