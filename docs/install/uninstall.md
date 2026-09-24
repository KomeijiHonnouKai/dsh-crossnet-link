# 卸载手册:完整、干净、只回滚本插件改过的东西

- **最后更新时间**: 2026-09-24(t37 首版;对应实现 `tools/uninstall.ps1` v1 = t36)
- **本次使用的命令**(全部只读;没有一条会改变系统状态):
  1. `Select-String -Pattern '^\s*\[switch\]|^\s*\[string\]' -Path dsh-crossnet-link/tools/uninstall.ps1` —— 取参数清单(见 §1.0)
  2. `powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/tools/uninstall.ps1 -CheckOnly -StateDir <临时目录>` —— 本机实测:**exit 1**(无 journal 时的 fail-closed 语义),正文与保留清单见 §2/§7
  3. 同一条加 `-AsJson` —— 报告 schema `dsh-crossnet-link/uninstall-report/1`
  4. `powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/panel/prereq.ps1 -CheckOnly -AsJson` —— 读 `uninstall{}` 字段(13 项:7 keep / 6 optional-remove)
  5. `powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/src/collect.ps1 -CheckOnly -AsJson` —— 残留核对的第 6/7 项复用它的判定

> **这一页要解决的问题**:卸载必须「完整干净」,但**干净 ≠ 把看到的都删掉**。本插件的本体是只读的;整个仓库里唯一的写入组件是 `tools/uninstall.ps1`,它只能**回滚 journal 记录过、并且当前值仍然是它自己产出的**那些改动。别人后来改过的东西一律不碰 —— 这一页教你跑完它、看懂它打印的每一项、校验它留下的备份,并自己核对「没有残留」。

---

## 0. 三条硬规则(先记住再动手)

1. **备份先于执行**:`-Apply` 会先把 `<BackupDir>` 写出来并逐文件校验(sha256 + 字节数),校验不过就拒绝执行(exit 2),**一个字节都不改**。
2. **只回滚可归属项**:只有「当前值 == 记录里 `after` 的值」的项会被执行(状态 `revert`)。别人改过 ⇒ 只报告(状态 `left_alone`),退出码 1。
3. **默认干跑**:不加 `-Apply` 就什么都不写。写入动作只有 4 个:`-RecordBefore`、`-RecordAfter`、`-Apply`、`-PurgeBackup`(前两个只写 `<StateDir>` 里的 journal 文件)。

环境:`Windows PowerShell 5.1`(不要用 pwsh 7),下面所有命令把 `<REPO>` 换成你的 checkout 路径(本文按仓库相对路径书写)。

---

## 1. 6 步工作流(每步:命令 + 应观察到什么)

### 1.0 先看参数清单(与实现逐字一致)

`-StateDir`(默认 `$env:USERPROFILE\.dsh-crossnet-link`)、`-Journal`(默认 `<StateDir>\state-journal.json`)、`-RecordBefore`、`-RecordAfter`、`-Plan`、`-Apply`、`-BackupDir`、`-PurgeBackup`、`-RemoveFiles`、`-KeepTailscale`、`-CheckOnly`、`-AsJson`、`-FixturePath`、`-Lang`、`-Manifest`、`-DshHome`、`-Collector`、`-InstallPath`、`-CordisPluginId`、`-RowId`、`-NetworkProfileName`、`-CommandTimeoutMs`。

> 本页只用上面这些名字。**实现里不存在的参数与行为,本页一律不写**;如果你看到别的写法,那是错的。

### 1.1 第 1 步:记录卸载前状态

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <REPO>/tools/uninstall.ps1 -RecordBefore -StateDir "$env:USERPROFILE\.dsh-crossnet-link"
```

**应观察到**:横幅是 `JOURNAL RUN: this run observes and records...`;每一项以 `id` + 该项目的 remediation 命令打印;`<StateDir>\state-journal.json` 被创建,里面是 `records[]`,每条含 `before` / `expected` / `after: null`。**这一步只写这一个文件。**

### 1.2 第 2 步:按第 1 步打印的提示,自己执行 remediation

上一步会逐项打印「要做的事」,例如:

```powershell
# serve(可选删除)
tailscale serve reset

# 防火墙窄放行(可选删除,需管理员窗口)
Remove-NetFirewallRule -DisplayName 'DSH via Tailscale serve (tcp 443)'

# profile 行(可选删除):删掉 <DSH_HOME>\profiles\<name>\cordis.patch.yml 里你加的那几行,然后从 DSH 自带菜单重启
# 动态 Cordis 包(可选删除):在 DSH 会话里执行
cordis_undefine(<PLUGIN_ID>)
```

**应观察到**:命令成功或明确报错。需要提权的**必须由你在管理员窗口自己跑** —— 这个工具从不提权,它只会把该跑的命令打印出来。

### 1.3 第 3 步:再记录一次(填 `after`)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <REPO>/tools/uninstall.ps1 -RecordAfter -StateDir "$env:USERPROFILE\.dsh-crossnet-link"
```

**应观察到**:journal 里每条记录的 `after` 被填上**当前值**。`after` 就是「这个值是本工具造成的」的凭据;没有它,后续只能判 `unknown`(绝不猜)。这一步必须在上一步之后跑。

### 1.4 第 4 步:看计划(默认干跑)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <REPO>/tools/uninstall.ps1 -Plan -StateDir "$env:USERPROFILE\.dsh-crossnet-link"
```

**应观察到**:`DRY RUN: nothing was written or changed...`;一行 `classification: noop=… revert=… left-alone=… unknown=… kept(userOwned)=… unknown(exempt cordis)=…`;每个记录的状态与**溯源**(`recordedBefore` / `recordedExpected` / `recordedAfter` / `observedNow`)。退出码:`0` 干净 / `1` 有 `left-alone`、`unknown` 或残留 / `2` 拒绝执行且什么都没写。

### 1.5 第 5 步:执行(写前自动备份)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <REPO>/tools/uninstall.ps1 -Apply -StateDir "$env:USERPROFILE\.dsh-crossnet-link"
```

**应观察到**:横幅 `WRITE RUN: the backup directory is written and verified BEFORE the first change.`;先打印备份目录与逐文件校验结果,然后才出现 `execution begins only now`;之后只执行状态为 `revert` 的项。备份写不完/校验不过 ⇒ exit 2 且不改任何东西。

### 1.6 第 6 步:残留扫描 + 备份决定

```powershell
# 只看残留(不写;没有 journal 也能跑机器面那几项,但结论会带 attribution=unavailable 并且 exit 1)
powershell -NoProfile -ExecutionPolicy Bypass -File <REPO>/tools/uninstall.ps1 -CheckOnly

# 想连备份一起清掉(必须与 -Apply 同一次运行,见 §4)
powershell -NoProfile -ExecutionPolicy Bypass -File <REPO>/tools/uninstall.ps1 -Apply -PurgeBackup -StateDir "$env:USERPROFILE\.dsh-crossnet-link"
```

**应观察到**:§7 的 8 项残留逐条给出 `pass` / `residue` / `unknown` / `not-recorded` / `not-requested`,以及 `cordis-dynamic-package` 那一节列出的 `cordis_undefine(<id>)`。

---

## 2. 保留清单:默认什么都不删

保留策略有两层:**固定的 5 类**(实现里写死的,打印在报告开头),以及**逐项策略**(机器可读,来自 `panel/prereq-manifest.json` 的 `items[].uninstall{policy, keepReason, removeCommand, impactIfRemoved}`)。

### 2.1 固定的 5 类(实测打印原文)

| 类 | 一句话 |
| --- | --- |
| `tailscale-product` | Tailscale 本体:本工具**从不**卸载它,`-KeepTailscale` 取什么值都一样 |
| `other-plugin-profile-rows` | 别的插件的 profile 行:只有 journal 记录过的 row id 才可能被回滚 |
| `user-firewall-rules` | 本工具从未记录的防火墙规则:不检查、不改动 |
| `workspace-repo-files` | checkout 里的仓库文件:从不删除(只有 `-InstallPath` 声明的路径才可能被删) |
| `user-skill-copies` | 用户级 skill 副本:记录为 `userOwned`,保留 |

### 2.2 13 项逐项策略(7 keep / 6 optional-remove)

**keep(7 项,默认保留;括号里是 `keepReason` 要点)**:

| id | keepReason 要点 |
| --- | --- |
| `TAILSCALE_INSTALLED` | Tailscale 是这条链路赖以工作的产品,本机别的软件也可能在用;卸载它会同时打断链路与所有 tailnet 路由。**任何 `-KeepTailscale` 取值都不会卸载它。** |
| `TAILSCALE_CLI_LAYER` | 这是当前会话的**权限边界**,不是 remediation 造出来的东西:没装东西,也就没有可删的。 |
| `TAILSCALE_SIGNED_IN` | 登录是你自己的账号会话,不是本工具写的文件;注销会让本机离开 tailnet。工具从不登出、不碰凭据。 |
| `DSH_RUNNING_LOOPBACK` | DSH 是被访问的应用,不是链路的产物;工具从不启停它,也不杀它的宿主进程。 |
| `TAILNET_ACL_NARROW` | tailnet policy 在你的管理控制台里;本工具没有凭据、不调 API,读不到也改不了,只有你能编辑。 |
| `CLIENT_FIRST_OPEN_TOKEN` | 30 天 cookie 是你浏览器里的凭据;本工具从不读/打印/存/撤销凭据 ⇒ 撤销步骤(清该站点 cookie,必要时再删服务端凭据记录)始终由你完成,见 `rollback.md` §3。 |
| `CLIENT_MAGICDNS` | 域名解析不需要它自己的产物:本机没有为它安装或改动任何东西。 |

**optional-remove(6 项,默认保留,想删就自己跑它的 `removeCommand`)**

| id | removeCommand | 影响面(`impactIfRemoved` 要点) |
| --- | --- | --- |
| `SERVE_ON_TAILNET_443` | `tailscale serve reset` | 远端 URL 失效:tailnet 侧 443 监听与到 DSH loopback 端口的 proxy 一起没了。⚠️ 这条命令清空**本机整份 serve 配置**,不只这一个端口 ⇒ 你配过的其它 serve 目标也会被清掉。复核:`tailscale serve status`。 |
| `TRUSTED_HOSTS_CONFIGURED` | 删掉你在 `<DSH_HOME>\profiles\<name>\cordis.patch.yml` 里加的 trustedHosts 行,然后从 DSH 自带菜单重启 | 远端界面还能打开,但每个 `/api` 调用都失败(页面会一直重连)。这正是 journal 里 `dsh-profile-row` / `dsh-settings` 两个 surface 记录的那处改动,所以只有当记录的文字没被改过时,卸载器才会回滚它。 |
| `NARROW_INBOUND_ALLOW` | `Remove-NetFirewallRule -DisplayName 'DSH via Tailscale serve (tcp 443)'` | tailnet 客户端再也到不了本机 tcp 443(链路死掉);其余规则与 profile 默认值一律不动。卸载器只删「名字被记录过**且**当前值仍是它自己产出的」那条规则。 |
| `SERVER_POWER_IDLE_SLEEP` | `powercfg /change standby-timeout-ac <previous minutes>` 与 `powercfg /change standby-timeout-dc <previous minutes>` | 服务器可能重新闲置休眠 ⇒ 没人在键盘前时链路会断。命令由 journal 记录的值推导;推不出来就拒绝执行。 |
| `CLIENT_PROXY_BYPASS` | 删掉你加进代理绕过列表的 tailnet 名 / `100.64.0.0/10` 条目(设置 > 网络和 Internet > 代理),或把你关掉的代理重新打开 | 开着代理又没有绕过时,tailnet 页面可能永远加载不出来(即使 TCP 是通的)。 |
| `HOST_SERVICE_FOR_PANEL` | `cordis_undefine(<PLUGIN_ID>)`(在 DSH 会话里,针对你激活过的面板包 `guard-1` 或 `panel-2`) | 可选姿态 Service 与面板消失;采集器本体与面板的兜底路径不受影响,只读姿态检查照旧可用。这是 `cordis-dynamic-package` surface:卸载器**只打印、从不执行**。 |

### 2.3 `-KeepTailscale` 的准确语义

`-KeepTailscale` 取 `true`/`false`(也接受 `1`/`0`)或省略,**都只改变打印出来的那条建议**;任何取值都**不会**卸载 Tailscale。在 Windows PowerShell 5.1 上用 `-File` 调用时请写 `-KeepTailscale false` 这种形式(`[bool]` 参数无法从 `-File` 绑定,这是实测结论);传了无法识别的值 ⇒ exit 2,不会猜。

---

## 3. 备份:目录结构与完整性校验

`-Apply` 在**第一次改动之前**写下 `<BackupDir>`(默认在 `<StateDir>` 之下,可用 `-BackupDir` 指定,**但必须在 `<StateDir>` 之内**,否则 exit 2)。

| 文件 | 用途 |
| --- | --- |
| `journal.json` | 当时的 journal 快照。journal 归档后,它就是**溯源依据**(`source=backup-snapshot`)。 |
| `plan.json` | 本次的分类结果 + 溯源 + 时间戳(每个记录的状态、`recordedBefore/After/observedNow`)。 |
| `MANIFEST.json` | **其它每个备份文件的 sha256 与字节数**;写入后立刻被回读校验。 |
| `restore.md` | 每个记录的逆操作,以及它自己的回滚复核命令。 |
| `profile-cordis.patch.yml.bak` | 被改过的那份 profile patch 的**逐字节副本**(只有涉及该 surface 时才生成)。 |
| `firewall-rules.txt` / `serve-status.txt` | 相关只读捕获的原始输出(只有涉及这些 surface 时才生成)。 |

**校验备份完整性**(逐文件比对 MANIFEST 里记录的 sha256 与字节数):

```powershell
$backup = "$env:USERPROFILE\.dsh-crossnet-link\backups\<时间戳目录>"   # 用 -Apply 打印出来的路径
$m = Get-Content -LiteralPath (Join-Path $backup 'MANIFEST.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($f in $m.files) {
  $p = Join-Path $backup $f.rel
  $h = (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash
  $b = (Get-Item -LiteralPath $p).Length
  '{0}  sha256_match={1}  bytes_match={2}' -f $f.rel, ($h -eq $f.sha256), ($b -eq [int64]$f.bytes)
}
```

**应观察到**:每一行 `sha256_match=True bytes_match=True`。任何一行是 `False` ⇒ 备份不可信,**不要**拿它做还原(先按 §7 走一遍),并把这行输出留档。

> 备份先于执行不是注释:它是一个运行时闸门 —— 备份清单未写出并校验通过之前,所有改动入口都会拒绝执行。

---

## 4. 备份的保留 vs 清空

**默认保留:什么都不用做。** 保留下来的备份是**正常状态,不是警告**(退出码 0 里有它一份)。

**要清空:用 `-PurgeBackup`,并且必须与 `-Apply` 在同一次运行里**(单独跑 `-PurgeBackup` 会被拒绝):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <REPO>/tools/uninstall.ps1 -Apply -PurgeBackup -StateDir "$env:USERPROFILE\.dsh-crossnet-link"
```

清空前的保证(实现原文语义):

- **删除前**会打印完整文件清单、**总字节数与每个文件的 sha256**;删除后再打印一份「已删除清单」。
- 只会删 `<StateDir>` **之下**、且**带 `MANIFEST.json` 并且每个列出的文件都逐字节吻合**的那个目录 —— 这就是代码里「没备份过的就不删」的含义。
- 路径越界(`-BackupDir` 落在 `<StateDir>` 之外)⇒ **exit 2,拒绝执行**;目录里没有可信 `MANIFEST.json` ⇒ 同样拒绝。

---

## 5. 判定表:只重置「本插件改过的」

分类是对 `(journal, 当前观测)` 的**纯函数**。四个主状态如下(定义取自实现的 `detail` 原文,中文为意译):

| 状态 | 定义 | 卸载器的动作 | `reasonKey` |
| --- | --- | --- | --- |
| `noop` | 当前值 == 记录的 `before`(本工具的东西不在这里) | 不动 | `equals_before` |
| `revert` | 当前值 == 记录的 `after`,且 `after != before`(仍然恰好是我们产出的值) | **唯一会被执行的类**;`-Apply` 时按记录的逆操作回滚 | `equals_recorded_after` |
| `left_alone` | 当前值既不是 `before` 也不是 `after`(别人后来改过) | **一律不碰**,只报告 + 溯源 | `changed_by_somebody_else` |
| `unknown` | 观测读不出来,或「与原值不同但没有 `after` 记录」 | 不碰;强制非零退出码(唯一豁免:动态 Cordis 包) | `observation_unreadable` / `after_missing` / `memory_only_instruction` |

另有两条特殊状态:`kept_user_owned`(`userOwned` 记录,`reasonKey=user_owned_never_touched`,只报告)与动态 Cordis 包的 `unknown`(结构上无法从文件系统验证,**豁免** exit-0 规则,报告里单独列 `cordis_undefine(<id>)`)。

### 5.1 `left_alone` 的原文样例

实现里该分支的原文(逐字,`tools/uninstall.ps1` 的分类段):

```text
status   = 'left_alone'
reasonKey = 'changed_by_somebody_else'
detail   = 'the current value is neither the recorded before nor the recorded after value:
            somebody changed it afterwards, so it is reported and left exactly as it is'
provenance = { recordedBefore, recordedExpected, recordedAfter, observedNow, comparedAgainst = 'after' }
```

人类可读报告里,你会看到该记录的 `status=left_alone`、上面的 `detail`,以及四个溯源值 —— 例如「`recordedBefore=present` / `recordedAfter=absent` / `observedNow=<你现在机器上的值>`」这种形式:它一次说清**我们当初把它改成了什么、现在是谁的值**。

**纪律:别人后来改过的一律不触碰,只报告并 exit 1。** 想让它变成可回滚项,只有两条路:你把值改回我们产出的那个,或者你按 §7 自己核对后手工处理。

---

## 6. 退出码

| 码 | 含义 |
| --- | --- |
| `0` | 计划或执行完成;没有 `left-alone` 项;残留扫描干净;唯一的 `unknown` 是被豁免的动态 Cordis 包。**保留备份是正常态,永不因此报警。** |
| `1` | 至少有一项 `left-alone` / `unknown` / 残留。有人改过它、读不出来,或没能回滚。**从不静默,也从不替你决定。** |
| `2` | 拒绝执行,且**没有写入任何东西**:该有 journal 的动作没有 journal、状态目录不可用、路径逃出状态目录、`-PurgeBackup` 没跟 `-Apply` 同一次运行、`-RecordAfter` 没有 journal、参数值不可用。 |

注意:`-CheckOnly` 在没有 journal 时**不是拒绝**,机器面的残留项照样跑,但结论不会是干净 —— 报告带 `attribution=unavailable`(`reasonKey=journal_absent_cannot_attribute`)并以 `1` 退出:「这台机器上从来没装过东西」不是没有 journal 时能证明的事实。

---

## 7. 残留核对清单(卸载后逐项自查)

卸载器自己的残留扫描有 **8 项**(`-CheckOnly` 就会打印)。下表把它们与你可以**亲手复核**的命令配起来:

| # | 检查项(residue id) | 你自己怎么核对 | 期望 |
| --- | --- | --- | --- |
| 1 | `profile-rows-absent` | 在 `<DSH_HOME>\profiles\*\cordis.patch.yml` 里搜本插件的 row id(默认 `dsh-crossnet-link-panel`);或在 DSH 会话里 `cordis_inspect_self()` 看该 Plugin 是否还在 | 记录过的 row id **0 命中**;没记录过则报 `not-recorded` |
| 2 | `install-artifacts-absent` | 只有带 `-RemoveFiles` 时才检查:逐个看你用 `-InstallPath` 声明过的路径 | 记录过的路径**回到 `before`**(即消失);没给 `-RemoveFiles` ⇒ `not-requested`(按设计保留) |
| 3 | `recorded-firewall-rules-absent` | `Get-NetFirewallRule -DisplayName '<记录过的规则名>'`(或 `netsh advfirewall firewall show rule name=<名字>`) | journal 记录过的规则名 **0 命中**;⚠️ **未记录的规则不检查也不动** —— 别拿「机器上还有别的规则」当残留 |
| 4 | `serve-target-restored` | `tailscale serve status` | proxy 目标**回到 `before`**,或 `not-configured` |
| 5 | `state-dir-contents` | `Get-ChildItem -Force $env:USERPROFILE\.dsh-crossnet-link` | 只剩 `backups\…`(或目录已不存在/已清空);出现别的条目就是残留 |
| 6 | `no-new-wildcard-listener` | `powershell -NoProfile -ExecutionPolicy Bypass -File <REPO>/src/collect.ps1 -CheckOnly -AsJson`,看 `NO_NEW_WILDCARD_LISTENER` | `pass`;`blocked` ⇒ 真出现新通配监听;读不出来 ⇒ `unknown`(**不是** pass) |
| 7 | `collector-delta` | 与第 1 步/第 3 步记录下来的采集器结果比 | **没有新出现的** degraded/blocked;有 ⇒ 报 `new_collector_findings` 并算残留 |
| 8 | `cordis-dynamic-package` | 在 DSH 会话里 `cordis_inspect_self()` | 工具**永远报 `unknown`**(动态包只活在进程内存里,文件系统看不见),按它列出的 `cordis_undefine(<id>)` 自己执行;这一项豁免 exit-0 规则 |
| 9 | 备份决定(人工项) | 见 §4:保留(默认)或 `-Apply -PurgeBackup` 清空 | 二选一即可;保留 = 正常态 |

---

## 8. 溯源:每一项都能追到「谁/何时/从什么变成什么」

- **journal**(`<StateDir>\state-journal.json`)是唯一的事实来源:每条记录带 `id`、`surface`(闭集:`dsh-profile-row`、`plugin-files`、`firewall-rule`、`tailscale-serve`、`dsh-settings`、`power-plan`、`network-profile`、`user-skill-copy`、`cordis-dynamic-package`)、`before`、`expected`、`after`、`revert{kind,command,note}`、`verify{command,expect}`、`userOwned`,以及 `remediation` / `recordedAtLocal` / `recordedBy` 这些**溯源附加字段**。
- **「从什么变成什么」**:`before → expected`(第 1 步记的意图)与 `before → after`(第 3 步记的实际结果);再与 `observedNow` 一比,就得到 §5 的四种状态之一。
- **「谁」**:`recordedBy` 记下是哪条会话/工具写的这条记录;`userOwned=true` 明确标注「这是用户自己的东西」。
- **「何时」**:`recordedAtLocal` / `updatedAtLocal`(journal)与 `generatedAtLocal`(报告)、`plan.json` 里的时间戳。
- **备份与 MANIFEST 的作用**:journal 被归档进备份后,`journal.json` 快照就是**溯源依据**(后续 `-CheckOnly` 会自动改用它,报告里 `source=backup-snapshot`);`MANIFEST.json` 让「这份备份是不是原件」可被**逐字节**验证;`restore.md` 把每个记录的逆操作与复核命令放在一起,便于你或下一个人接手。

---

## 9. 常见问题

**退出码 1 是不是失败?** 不是崩溃,是**判定**:有东西被别人改过、读不出来或确属残留。看报告里那些 `left_alone` / `unknown` / `residue` 项,逐条处理或明确接受。

**为什么动态 Cordis 包总是 `unknown`?** 它只活在 DSH 进程内存里、随进程消失,文件系统看不见。工具不猜,只在报告里列 `cordis_undefine(<id>)` 让你在会话里执行。

**为什么我加的别的防火墙规则没被删?** 因为**只有 journal 记录过的**规则会被检查与回滚;没记录过的一律不动(§7 第 3 项)。

**想彻底不留备份?** §4:`-Apply -PurgeBackup` 同一次运行。默认保留也完全正常。

**想连 DSH 一起清掉?** 不在本工具范围:它从不启停/重启 DSH,也不杀它的宿主进程。DSH 自己的去留由你决定。
