# 回滚手册(两条安装路径 + 每个前置件步骤)

- **最后更新时间**: 2026-09-25(v2.2;本轮修「取最新备份」的判据:`Copy-Item` **保留源文件的 `LastWriteTime`**,
  所以 `Sort-Object LastWriteTime | Select-Object -Last 1` 排的是「源文件最后被改的时间」、不是「哪次备份最新」(I-05);
  §2 的备份/还原命令改用 **`CreationTime`** 并补上「文件真的存在 + Length 非 0」的确认(与 I-04 的假成功配套)。
  v2.1 = t26 去掉对**内部资料**的引用,该位置改为就地复述;v2 = t16 repair-round-2 的 F1/F2/F4/F9)
- **本次使用的命令**(全部只读;本文件不含任何会改变系统状态的命令执行记录):
  1. `& "$env:ProgramFiles\Tailscale\tailscale.exe" serve --help`(**exit=0**)—— F1 的证据台账,见 §3.1
  2. `powershell -NoProfile -Command "Copy-Item -LiteralPath <patch> -Destination <patch>.bak-<stamp> -Force"`(示例,由你执行)
  3. `powershell -NoProfile -Command "(Get-FileHash -LiteralPath <patch> -Algorithm SHA256).Hash"`
  4. `powershell -NoProfile -Command "Get-Content -LiteralPath <backup> -Encoding UTF8"` —— F9:还原前先看备份内容
  5. `powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/src/collect.ps1 -CheckOnly -Role server`
  6. `powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/panel/prereq.ps1 -CheckOnly -Role server`
  7. `cordis_inspect_self()` —— 当前返回 `plugins: []`(见 §1,进程重启后动态包消失)
  8. 内部资料引用扫描:本目录三个文件里**内部文档名应 0 命中**(t26 实测 0)

> **总原则**:本插件自己**不写任何东西**(动态包在进程内存里,安装引导只打印命令)。
> 因此绝大多数「回滚」是**你自己做过的那一步**的逆操作。下表按「改动 → 回滚 → 怎么确认回滚成功」组织。
> 完整卸载(**只回滚可归属项**、备份保留或清空、残留逐项核对与溯源)见 [`uninstall.md`](uninstall.md):那份手册把 6 步工作流、13 项保留策略与 8 项残留扫描逐条写清。

---

## 0. 先看:哪些东西根本不需要回滚

| 本插件做过的事 | 是否需要回滚 | 说明 |
| --- | --- | --- |
| 动态 Cordis 包(t5 `guard-1` / t6 `panel-2`) | 需要(一步) | `cordis_stop` 即清;见 §1 |
| 只读检测(注册表/服务/netstat/有界子进程/文件读取) | **不需要** | 不改任何状态 |
| 打印安装/校验/回滚命令 | **不需要** | 只是字符串 |
| 新增监听 / 路由 / 端口 | **不发生** | 硬约束;无回滚需求 |
| 读写凭据(token / cookie / 密钥 / DSH 凭据库) | **不发生** | 硬约束 |
| 改系统配置(防火墙 / 电源 / 代理 / ExecutionPolicy / UAC) | **不发生** | 只打印给你;真改的话是**你**执行的,按 §3 回滚 |
| DSH 重启类插件 / 杀宿主 / 自拉起 | **不发生** | 结构上禁止 |

---

## 1. 动态 Cordis 包(默认路径)

| 目标 | 命令 | 回滚后应观察到 |
| --- | --- | --- |
| 临时停用面板 | `cordis_stop("panel-2")` | 设置面板里的 `Remote access link (read-only posture)` 分区项消失;host 私有方法 `dsh-crossnet-link/panel/posture` 不再可调用;GUI 正常(无 `Failed to load plugins`) |
| 临时停用采集器 host 半边 | `cordis_stop("guard-1")` | Service `remoteTailnetGuard`、私有方法 `dsh-crossnet-link/posture`、工具 `remote_tailnet_posture` 一起消失;正在跑的子进程被 `terminate()` |
| 永久删除面板 | `cordis_undefine("panel-2")` | Plugin 与全部 Package 删除;`cordis_inspect_self()` 里不再出现;@ 引用失效(历史卡片只留「已移除」记录) |
| 永久删除采集器 | `cordis_undefine("guard-1")` | 同上 |

**状态快照(F4)**:下表说的两个动态包是 **2026-09-24 的 define 快照**;`cordis_inspect_self()` 在本次
t16 复核时返回 **`plugins: []`** ⇒ **进程重启后动态包已消失**(不落盘是设计,不是故障)。
因此本节在默认状态下**无对象可停**:要先按 `install.md` §1 重新 `cordis_define` + `cordis_run`,才能验证
「`cordis_stop` 会移除 Service / 私有方法 / 工具并 `terminate()` 子进程」这一条。

**注意**:`cordis_stop` 与 `cordis_undefine` 都不撤销「用户已授权」这一事实以外的任何东西;
进程重启后动态包本来就会消失(不落盘),所以「重启后看不到面板」不是回滚失败,是预期行为。

**如果 GUI 出现 `Failed to load plugins` / 卡在恢复模式**:
第一动作就是 `cordis_stop("panel-2")`(它只会移除本包的效果)。然后按要求跑静态检查,确认 `*.js/.mjs/.cjs` 里对已删包的引用数为 0。

---

## 2. 持久化 profile 安装(需你先执行过 §4 才存在)

| 改动 | 回滚 | 确认 |
| --- | --- | --- |
| 在 `<DSH_HOME>\profiles\<name>\cordis.patch.yml` 加了一行 `- id: dsh-crossnet-link-panel / name: dsh-crossnet-link` | **推荐先停用**:在同一行下加 `disabled: true`(profile 配置有 ~1 秒 HMR 重组合,不必重启) | 设置面板里分区项消失;`cordis_inspect_self()` 里该 Plugin 不在 |
| 要彻底移除 | 删掉那一行,保存 | 同上看不到 |
| 改坏了整个 patch 文件 | 从备份整文件还原(见下) | 还原后 `Get-FileHash` 与备份时记录的值一致 |
| 删掉了 package.json / 构建产物 | 从版本库 `git checkout -- dsh-crossnet-link/` 还原 | `git status` 干净 |

**备份与还原(可粘贴;路径运行时解析,不写死)**

> ⚠️ **F9 陷阱(来自 skill §5.4,实测复核)**:备份出来的 `.bak` **可能是一个空 patch(`[]`)** ——
> 如果 `cordis.patch.yml` 本来就只有注释、或你备份的是另一个 profile 的层,**整文件还原会把整段预设行删掉**
> (本机 `app\cordis.patch.yml` 里 `permission` 预设与 `ego-browser` 的 `chromePath` 就是靠这种行存在的)。
> ⇒ **还原前必须先看备份内容**,不要拿一个空文件盖回去。另外 PS 5.1 下读无 BOM 的 UTF-8 会乱码(中文预设名尤其明显),
> 所以读备份**必须显式 `-Encoding UTF8`**;哈希比对仍是字节级判据,不要只靠肉眼看。

> ⚠️ **「取最新备份」的判据(I-05,实测)**:`Copy-Item` **保留源文件的 `LastWriteTime`** —— 新副本的这个字段
> 等于源文件的值,不是"复制发生的那一刻"。所以 `Sort-Object LastWriteTime | Select-Object -Last 1` 选出来的是
> **源文件最后被改的时间**,不是你的最后一次备份;对端实测两次不同时刻的备份 `LastWriteTime` **完全相同**。
> **改用 `CreationTime`(副本自己的创建时间)或按备份文件名里的时间戳排序**,并且**用之前先确认它真的存在、`Length` 非 0**
> (`Copy-Item` 被拒抛的是**非终止错误**,脚本可能一边报"备份成功"一边什么都没写)。

```powershell
# 0) 备份前:先看清原文件长什么样(以及它是否只是注释)
$dshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE '.dsh' }
$patch   = Join-Path $dshHome 'profiles\desktop\cordis.patch.yml'   # 多 profile 时明确选一个
Get-Content -LiteralPath $patch -Encoding UTF8 | Select-Object -First 20
"sha256 = " + (Get-FileHash -LiteralPath $patch -Algorithm SHA256).Hash
"bytes  = " + (Get-Item -LiteralPath $patch).Length

# 1) 备份(执行持久化之前必做)
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = "$patch.bak-$stamp"
Copy-Item -LiteralPath $patch -Destination $backup -Force
"backup=$backup"
(Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash   # 把这个值记下来

# 1b) 立刻确认备份真的落地(非终止错误会让"备份成功"是假的)
Test-Path -LiteralPath $backup                                # 期望 True
(Get-Item -LiteralPath $backup).Length                        # 期望 > 0 且与源文件一致

# 1c) 「取最新备份」的正确排序键:CreationTime(不是 LastWriteTime)
Get-ChildItem -LiteralPath ($patch + '.bak-*') | Sort-Object CreationTime | Select-Object -Last 3 FullName,Length,CreationTime,LastWriteTime
# 或按文件名时间戳排序(与文件系统元数据无关):
Get-ChildItem -LiteralPath ($patch + '.bak-*') | Sort-Object Name | Select-Object -Last 3 FullName,Length

# 2) F9:还原前先核对备份内容 —— 空 patch / 空文件一律不要还原
Get-Content -LiteralPath $backup -Encoding UTF8            # 必须显式 UTF8,否则中文预设名乱码
(Get-Item -LiteralPath $backup).Length                     # 0 或只剩注释(如 "[]")=> 停止,别还原
"backup sha256 = " + (Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash
"live   sha256 = " + (Get-FileHash -LiteralPath $patch  -Algorithm SHA256).Hash   # 备份时应与 backup 相同

# 3) 还原(仅当第 2 步确认备份是完整内容)
Copy-Item -LiteralPath "$patch.bak-<你记下的时间戳>" -Destination $patch -Force
(Get-FileHash -LiteralPath $patch -Algorithm SHA256).Hash   # 字节级复核:与第 1 步记录的值一致
```

**纪律**:持久化安装必须由**你显式授权后由你执行**;本任务没有执行过它,所以这部分回滚在默认状态下**无事可做**。

---

## 3. 前置件步骤的回滚(只在你照 `prerequisites.md` 做过之后才需要)

| 步骤 | 逆操作(回滚) | 确认 |
| --- | --- | --- |
| `tailscale serve --bg <DSH_PORT>`(暴露那一步) | **`tailscale serve reset`**(见 §3.1:这是唯一正确的逆操作,**`serve off` / `--bg off` 不存在**) | `tailscale serve status` 显示已无 serve 配置;tailnet 侧 443 监听消失(`netstat` 或 `collect.ps1 -Role server` 的 `SERVE_PRESENT`) |
| `New-NetFirewallRule -DisplayName 'DSH via Tailscale serve (tcp 443)'` | `Remove-NetFirewallRule -DisplayName 'DSH via Tailscale serve (tcp 443)'` | `Get-NetFirewallRule -DisplayName 'DSH via Tailscale serve (tcp 443)'` 为空(需提权) |
| 在 patch 里加 `connection.trustedHosts` | 删掉你加的那几行,然后用 **DSH 自带的重启菜单**重启 | `collect.ps1 -CheckOnly -Role server` 的 `TRUSTED_HOSTS_PATCH` 回到改动前的 verdict |
| `powercfg /change standby-timeout-ac\|dc 0` | `powercfg /change standby-timeout-ac <原分钟数>` / `...dc <原分钟数>`(**改前必须先记录原值**) | `powercfg /query SCHEME_CURRENT 238c9fa8-0aad-41ed-83f4-97be242c8f20 29f6c1db-86da-48c5-9fdb-f2b67b1f44da` 的 AC/DC 回到原值 |
| 代理绕过列表加了 tailnet 项 | 删掉该项(或重新启用代理) | 设置 → 代理 页面里该项消失 |
| 改了 tailnet ACL | 把控制台里改之前的策略文本粘回去 | 客户端 → 服务端 tcp 443 仍可达;反向 ping 仍不通(单向后本来就如此) |
| 安装 Tailscale(`msiexec /i`) | `msiexec /x "<MSI_PATH>" /passive /norestart`(或 设置 → 应用 → 卸载) | `Get-Command tailscale.exe` 失败;服务 `Tailscale` 消失 |
| Tailscale 登录(浏览器 OAuth) | 托盘菜单 Disconnect,或在控制台移除该设备 | `netsh interface ip show addresses` 里不再有 100.64.0.0/10 地址 |
| 首次带 token 打开(那一次 `GET /` 换到 30 天 cookie) | 按「先查清、再动手」三步(**F2 修正**):①**清客户端该站点的 cookie**(浏览器 → 该站点 → 清除站点数据);②**若怀疑 cookie 已泄漏**:删掉服务端 credentials 里的 `client-connection` / `browser-session` 记录(`dsh-client-connection/lib/index.js:219` 的键名、`:321-338` 的持久化 grant 记录),然后**用 DSH 自带菜单重启**;③**注意:仅重启 DSH 不会让已发出的 cookie 失效** —— 重启只换每个进程新生成的 launch token,已签发的那张 30 天 cookie 在到期前一直有效。语义与落点以 skill `references/security.md` §4(撤销路径)为准 | 清 cookie 后:再打开需要重新带 token。删 credentials 记录后:`cordis_inspect_self`/界面表现为未授权,旧 cookie 在 `browser-session` 记录消失后不再被接受(以 skill §4 的判据为准) |
| 把 `networkExposure` 改成 `lan`(若有) | 改回 `loopback`,用 DSH 自带菜单重启 | `settings.yaml` 里该键回到 `loopback` |

### 3.1 serve 的逆操作:唯一正确的是 `tailscale serve reset`(F1 证据台账)

> ⚠️ **`tailscale serve reset` 是整机级回退**:它清空本机**所有** serve 配置(不止 DSH 那一个端口),
> 你配过的其它 serve 目标也会一起被清掉。**回退前先 `tailscale serve status` 把现有配置记下来**,以便之后按原样重建。

**命令原文**(本机 Tailscale `1.102.4-t3caf7d9e7-g084ee3b64`,2026-09-24 复核,**exit=0**):

```powershell
& "$env:ProgramFiles\Tailscale\tailscale.exe" serve --help
```

```
USAGE
  tailscale serve <target>
  tailscale serve status [--json]
  tailscale serve reset
...
SUBCOMMANDS
  status      View current serve configuration
  reset       Reset current serve config
  drain       Drain a service from the current node
  clear       Remove all config for a service
  advertise   Advertise this node as a service proxy to the tailnet
  get-config  Get service configuration to save to a file
  set-config  Define service configuration from a file
```

**判读**:
1. `USAGE`/`SUBCOMMANDS` 里**没有 `off`**(只有 `reset` 等)⇒ 把 `off` 当作 `serve` 的参数写出来**不是有效命令**;
   把它当回滚命令 = **暴露那一步没有回滚**。正确命令是 **`tailscale serve reset`**(语义:清空当前全部 serve 配置,不是「关一个端口」)。
2. 复核:`tailscale serve status`(期望不再显示 `https://<机器名>.<tailnet>.ts.net/` 与 proxy 目标);再跑
   `collect.ps1 -CheckOnly -Role server` 看 `SERVE_PRESENT` 与 tailnet 侧 443 监听。
3. **采集注意**:本命令的正文走 **stderr**(PowerShell 会把它包成 `NativeCommandError` 记录),但 `$LASTEXITCODE` 仍是
   **0** —— 判「命令是否可用」只看退出码,不要因为看到一条红字就以为失败。
4. `--bg` 只影响「配置是否在重启/`tailscale up|down` 后自动恢复」,**与逆操作无关**;
   `reset` 之后若还要暴露,重新执行 `tailscale serve --bg <DSH_PORT>` 即可。

> ⚠️ **本插件仓库内已按此改过的位置**:本文件 §3 的「首次带 token 打开」那一行、§3.1 的证据台账,以及 `panel/prereq-manifest.json` 与 `docs/install/prerequisites.md` §3.5 —— 四处口径一致(`tailscale serve reset`,不是 `off`)。

---

## 4. 记录纪律(避免「回滚不了」)

任何**写**动作前,先把这三样记下来(本插件的所有 remediation 文案都按这个要求写的):

1. **原值**:电源超时(分钟)、原 `trustedHosts` 内容、原 ACL 文本、原代理绕过列表。
2. **回滚命令**:每条 `remediation` 都带 `rollback` 字段;`collect.ps1 -AsJson` 里可直接读。
3. **备份哈希**:`Get-FileHash` 的值,写进你自己的变更记录。

**验证回滚**:回滚后用同一套判据复查,不要凭感觉 ——

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/src/collect.ps1 -CheckOnly -Role server
powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/panel/prereq.ps1 -CheckOnly -Role server
```

期望:相应项的 `verdict` 回到改动前的值,且 `summary` 的计数与你的记录一致。

> **注意调用方(与 `plugin-package.md` §7.1 同一条口径)**:同一份 `src/collect.ps1`,由 **agent 工具的受限沙箱**调用与由
> **宿主 `spawn`** 调用会给出**不同判定** —— 对端实测:同一条 `tailscale ip -4`,前者报
> `open \\.\pipe\…tailscaled: Access is denied`(exit 1,该项只能 `unknown`),后者 **exit 0**(`TAILSCALE_CLI_LAYER` pass)。
> 所以**回滚验证的判据以「普通窗口 / 宿主 spawn」那一侧为准**;在 agent 沙箱里跑出来的 `unknown` **不能**当成
> 「回滚没生效」。两边不一致时,先报告"哪个调用方跑出来的",再解释差异,不要互相覆盖。

---

## 5. 出问题时的最短路径

| 症状 | 第一动作 | 之后 |
| --- | --- | --- |
| GUI 报 `Failed to load plugins` | `cordis_stop("panel-2")` | 跑 §5(install.md)的静态检查;确认没有引用已删包 |
| 设置里分区项消失/异常 | `cordis_stop("panel-2")` | 重新 `cordis_run` 一次;仍不行就回报,不要反复重试 |
| 面板显示未知 | **不用回滚** | 这是 fail-closed 的预期结果;按 `reasonKey` 逐条处理 |
| 采集器跑不起来 | 不用回滚 | 手工跑 `collect.ps1 -CheckOnly -AsJson` 看原始输出 |
| 你自己改了防火墙/电源想撤销 | 按 §3 对应行 | 用 §4 的命令复查 |
| 持久化安装后想彻底恢复 | 按 §2:先 `disabled: true`,再删行,必要时整文件还原 | 比对备份哈希 |
