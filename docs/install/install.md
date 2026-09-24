# 安装与激活(动态包默认 / 持久化 profile 需你授权)

- **最后更新时间**: 2026-09-24(v1.2;t26)。本轮新增 **§0 非侵入性承诺与影响面**(设计底线:只读体检器,不改用户既有配置与防火墙;影响面与「可选修复:由你执行」的措辞统一),并把内部资料引用改成**就地复述**(发布集文件不深链内部文档)。v1.1(t20):**状态口径只有一条** —— 动态 Cordis 包只活在**进程内存**里、**随会话/进程结束消失**,所以本文件里所有「running / 已 define」都只是**某个快照时刻**的读数,要用就先按 §1.1 重新 `cordis_define` + `cordis_run`;并新增 **§1.4 会话归属限制**(带 client 半边的面板**必须**在普通交互会话里 define+run)。
- **本次使用的命令**(全部只读;无 `platform:"client"` 的 Inspect、无 `ego_*`、无长等待):
  1. `cordis_inspect_list`
  2. `cordis_inspect_query(platform="host", provider="Service", method="listService", input={service:"fs"})`
  3. `cordis_inspect_query(platform="host", provider="Service", method="listService", input={service:"subprocess"})`
  4. `grep -n "settings\.section" <app>\node_modules\@deepseek-ai\**\lib\*.js`
  5. `grep -n "React|host\.call|listBuiltins|inject: \[|slots" <app>\node_modules\@deepseek-ai\dsh-cordis-client-runner\lib\client.js`
  6. `cordis_define(...)`(host+client)/ `cordis_inspect_self(...)`
  7. `powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/panel/prereq.ps1 -CheckOnly`(t26 复跑:无安装执行路径,`ranAnyInstall=false`)
  8. `powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/src/collect.ps1 -Apply`(t26 复跑:**被拒绝**,exit 2)
  9. `powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/tests/run-tests.ps1`(t26 复跑:52/52,含三条「无写路径」用例)
  10. `powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/tests/run-fixtures.ps1`(7/7)
  11. 发布集卫生扫描 + **内部资料引用扫描**(6 类禁止模式、已批准中性占位符允许清单;**内部资料的文件名在本文件内应 0 命中**)
  12. 会话归属对照实验:同一条成员会话里 `cordis_inspect_self()` —— host-only 的 `guard-1` 能 running,带 client 半边的 `panel-2` 必然 failed ⇒ §1.4

> `panel/client-half.js` 与 `panel/host-half.js` **就是**传给 `cordis_define` 的 `code.client` / `code.host` 原文
> (文件先落盘,payload 逐字取自该文件;要机器核对可 `cordis_inspect_self(pluginId="panel-2", packageId="pkg-5")` 比对源码长度与关键行)。
> 本任务**只交付已 define 的包源码 + 激活清单**;运行时激活与「GUI 不出现 Failed to load plugins」的观察按 §2 点一次完成 —— 但**必须在普通交互会话里点**(成员会话里必然失败,见 §1.4)。

---

## 0. 非侵入性承诺与影响面(先读这一节)

> **一句话**:这个插件是**只读体检器**,不是配置修改器。它**不会**改你的防火墙、profile、`cordis.patch.yml` 或其它插件配置;
> 它只告诉你「现状是什么、哪里可能有风险」。**任何修复都是可选的,而且由你执行** —— 面板与文档里的命令一律是**打印给你**,不是**替你跑**。
> 怀疑「要用它就得先改我的机器」的读者,读完本节可以直接跳到 §0.2 的「什么都不改也能用」。

| # | 承诺 | 事实与证据 |
| --- | --- | --- |
| 1 | **默认零写入、只读** | 不加 `-OutFile` / `-DumpFixture` 时脚本**一个字节都不写**;`collect.ps1 -Apply` **被拒绝**并 exit 2(本版没有写路径);`panel/prereq.ps1` **没有任何安装执行路径**(无 `-Yes`/`-Apply`,无 `msiexec` / `Start-Process` / `runas` 调用,`-AsJson` 里恒为 `ranAnyInstall=false`)。套件里 `fault-apply-refused`、`isolation-no-writes-to-dsh-home`、`filescan-no-repo-write-paths` 三条**每轮复跑**这些断言(见 §5 的 verify #4) |
| 2 | **不修改任何防火墙规则** | 只**读**注册表规则库与 `netsh … show rule` / `show currentprofile`;**不调用** `New-NetFirewallRule` / `Set-NetFirewallRule` / `Remove-NetFirewallRule`。漂移(例如 `Tailscale-Process` 的 `Edge=FALSE`)只**报告**,并给**可选**命令 + **回滚** + 影响面(§0.1) |
| 3 | **不要求改动既有 profile / `cordis.patch.yml` / 其它插件配置** | 默认形态是**动态 Cordis 包**(进程内、不落盘):面板与工具用完即消失,`cordis_stop` 或进程重启即完全恢复;面板用**全新 id** 注册分区项,不顶掉出厂分区 |
| 4 | **采集前后不新增监听** | 采集器自己取采集前后两次 `netstat` 快照,对 `0.0.0.0` / `[::]` 求差集:**差集为空**;报告里 `NO_NEW_WILDCARD_LISTENER = pass`(§5 verify #5 有原文) |
| 5 | **可逆** | 所有副作用都挂在 disposer 上(`ctx.effect` / `slots.register` 的返回值);`cordis_stop` 立即移除,不留监听、不留文件、不改设置 |

### 0.1 如果你**选择**改,影响面在这里(可选修复:由你执行)

> 这一节存在的理由:**只读 ≠ 改了没代价**。下面每一项都可以**不做**;一旦要做,先看影响面与回滚。

| 可选动作(会改动系统) | 可能影响什么(**影响面**) | 回滚 |
| --- | --- | --- |
| 收窄 / 修复 `Tailscale-Process` 的 Edge traversal 注册表值 | 这条是**进程级**规则,影响**这台机器上所有 Tailscale 功能**(不只本链路):改错会让部分 NAT / 穿透场景变差(包括依赖 Teredo / IPv6 转发的路径),而 serve 与 `tailscale status` 侧看不出异常 | 改前**记下原值**(原始 `Edge=` 那一串),改回原值;重装/修复 Tailscale 也会重建该规则 |
| 新增一条窄入向放行(tcp 443、仅 tailnet 段) | 可能与**既有规则重叠**(同端口多条规则并存,后续排查更乱);**不要**改成放宽 profile 默认策略 —— 影响面远大于本插件需求 | `Remove-NetFirewallRule -DisplayName '<你起的名字>'` —— 所以**规则名要唯一**,回滚才准 |
| 修改活动 profile 的 `cordis.patch.yml`(加 `trustedHosts`) | 同一个 profile 的**所有会话**都会读到这份 patch,写错会连带影响你在该 profile 里的其它工作 | 删掉你加的那几行;改坏了用 `rollback.md` §2 的**整文件还原**(先看备份内容,别拿空 patch 覆盖) |
| **持久化**安装这个面板(往 profile 加一行) | 该 profile 的**所有会话**都会加载这个插件行 —— 这是它与「动态包」最大的差别 | 先备份 → 先 `disabled: true` → 不当再整文件还原(§4.2 / §4.4 / §4.5) |
| `tailscale serve --bg <端口>` / `tailscale serve reset` | 改变本机在 tailnet 上的发布面;`reset` 会**清空本机全部 serve 配置**(不是只停某一个端口) | 先记录 `tailscale serve status` 的当前内容,再按它重建;`reset` 之后必须重建 |

**本插件从来不做的**(与上表相对):不装软件、不改 `ExecutionPolicy` / UAC / Defender、**不放宽防火墙默认策略**、不改 `networkExposure`、不装重启类插件、不杀宿主、不代你点 UAC、不代你登录账号。

### 0.2 「可选修复:由你执行」是什么口径

- 面板与文档里出现的每条命令都标为**可选**;需要提权的会标 `needsElevation`,并且**都带一行回滚**。
- 「必须」一词只用于**你决定要这条链路能工作**时的前置件(例如 Tailscale 已安装、DSH 在跑);它**不是**「你必须接受我们改你的机器」。
- **什么都不改也能用**:①面板与工具默认走**动态包**(不落盘);②只想先看结论就直接跑 `collect.ps1 -CheckOnly`(只读,退出码 0/1/2);③`NOT PASS` 的项**不阻塞**你继续用这台机器,它只是告诉你哪里可能有风险。
- 链接口径:本文件**不深链内部资料**(那些文档不随仓库发布)。需要可复现的检查流程时看仓库内的 `CONTRIBUTING.md` §1/§2;本文需要的结论都已**就地复述**。

---

## 1. 默认路径:动态 Cordis 包(进程内,不落盘)

| 包 | pluginId / packageId | 半边 | 状态(**2026-09-24 快照,非实时**) | 作用 |
| --- | --- | --- | --- | --- |
| t5 采集器 host 半边 | `guard-1` / `pkg-4` | host | 快照时刻 running(run-4);**动态包,会话/进程结束即消失** | Service `remoteTailnetGuard` + 私有方法 `remote-tailnet-guard/posture` + 工具 `remote_tailnet_posture`。**源码已落盘**:`src/host-half.js`(sha256 `464BB4059B282118D5626A09B759B4557E57734FAB69E6528B159B6BF5A74E7E`,19877 B) |
| t6 面板 | `panel-2` / `pkg-5` | host + client | 快照时刻已 define、未激活;**且它属于 subagent 成员会话 ⇒ 结构上不可激活(§1.4)** | host:私有方法 `remote-tailnet-guard/panel/posture`;client:`settings.section` 里的只读姿态面板 |

> ⚠️ **动态包的生命周期(t16 F4/X5 实测 + t20 复核)**:动态包只活在**进程内存**里。`cordis_inspect_self()` 在 t16 复核时返回
> `{"mode":"plugins","plugins":[]}` —— 所有包都随 DSH 进程重启**消失**。「重启后还在不在」只有一个答案:**不在**。
> 所以上表(以及任何「当前 running / 已 define」的说法)都只是**快照时刻**的读数;要复核 disposer / `terminate()` 这一类行为,
> 先按 §1.1 重新 `cordis_define` + `cordis_run`,再观察。会话层面同理:插件的属主是**定义它的那条会话**,而带 client 半边的包只能由该会话激活 ⇒ §1.4。

### 1.1 激活步骤(你执行一次)

1. 确认采集器 host 半边在跑(`cordis_inspect_self` 看 `guard-1` 是否 `running`)。若不在:
   `cordis_run(pluginId="guard-1", packageId="pkg-4", mode="run")`(有 current 时用 `mode="update"`)。
   *可选*:不必激活它,面板的 host 半边会自己跑采集器(`source=direct`),只是少一次复用。
2. `cordis_run(pluginId="panel-2", packageId="pkg-5", mode="run")`。
   ⚠️ **这一步必须在「普通交互会话」里做**(工作区级 / 用户自己的会话)。在**团队成员(subagent 路由)会话**里执行**必然失败**,失败原文、三条判据与源码依据见 **§1.4**;此时**不要重试**——重试只会再消耗一次批准点击,结果逐字相同。
   因为带 client 半边,**未授权时它会返回 `awaiting-approval`**:需要你在界面上点同意(单个勾 = 只授权这一个 Package;双勾 = 授权该 Plugin 后续版本)。
   `awaiting-approval` / `starting` 都不是成功;等系统通过状态回报最终结果。
   若 `panel-2` 已经属于某条成员会话,直接按 §1.4 的「最小正确做法」**新建**一个插件,不要复用 `panel-2`。
3. 授权后返回 `starting`,client 半边在浏览器里异步激活。

### 1.2 预期出现位置 / 观察点 / 成功判据

| 项 | 预期 |
| --- | --- |
| 出现位置 | **设置面板左侧分区导航**多出一项 `Remote access link (read-only posture)`(slot `settings.section`,注册 `id=remote-tailnet-guard`,`order=100`) |
| 打开后可见 | 顶部总判定 + `pass=/degraded=/blocked=/unknown=` 计数;下面一行退出码读法;`fail-closed` 说明;`source=` / `script=` / `generated=` 溯源行 |
| 列表 | 全部判定按「最坏优先」排列,每项含四态标签、`id`、本地化原因;`confidence=low` 的降级项带 `low confidence: localized-text path, reported as degraded` 标记;需人工的项带 `manual step required` 且单列一节 |
| 底部 | **四条 notice**:凭据纪律三条(不读凭据 / 只显示判定、原始输出不过桥 / 不安装不监听不改设置不重启)+ **非侵入性一条**(不改任何设置、不碰防火墙、不动 profile,**建议修复由你执行**) |
| 首次查询 | 视角选择器默认 `client`(客户端机器最常见),可切 `server` / `both` 重新查询 |
| GUI 状态 | **不出现** `Failed to load plugins`,不进恢复模式 |

### 1.3 失败判据与处置

| 现象 | 含义 | 处置 |
| --- | --- | --- |
| GUI 出现 `Failed to load plugins` / 卡恢复模式 | client 半边加载失败(最可能是打包期 externals 漂移) | `cordis_stop("panel-2")` 立刻恢复;然后按 §5 的静态检查重验 `*.js` 里不引用已删包 |
| 设置里**看不到**该分区项 | `settings.section` 未被声明(`sidebar.settings` 那个入口还没挂载),或 `slots.inject` 未触发 | 先打开一次设置面板再退出;仍无则 `cordis_stop("panel-2")` 并回报(不要反复重试) |
| 面板显示 `No posture available yet: ...` + `[collector-missing]` / `[no-subprocess]` | host 半边定位不到采集器或取不到子进程能力 | 手工确认采集器能跑:`powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/src/collect.ps1 -CheckOnly`;或先激活 `guard-1/pkg-4` |
| `[json-parse-failed]` | 采集器输出被别的输出污染 | 手工跑 `-AsJson` 看是否可解析 |
| 列表里全是 unknown | 本会话探针不可用(命名管道/权限/无对端) | 这是**设计预期**的 fail-closed 结果,不是面板故障 |
| 面板一直 `checking...` | host 方法没回 | 采集器单次运行约 10–20 秒;超过 60 秒用 `cordis_stop` 停掉再排查 |

### 1.4 ⚠️ 会话归属限制(面板为什么必须在**普通交互会话**里 define+run)

**实测失败原文**(2026-09-24,在一条**团队成员会话**里对 `panel-2/pkg-5` 执行 `cordis_run`,并在界面上点了批准之后):

```
host-half-failed
message: session/agent-busy: session "<SUBAGENT_SESSION_ID>" is owned by subagent routing
currentPackageId: none
nextPackageId: pkg-5
```

`<SUBAGENT_SESSION_ID>` 是**定义该插件的那条成员会话**的 id(原文里该 id 是逐字打印的,这里只做占位)。

**判据(三条同时成立即可确诊;别当成偶发故障)**

1. 报错里的 `session "<ID>"` = **定义该插件的那条会话**(= 该成员在团队状态里的 id)。
2. **批准能点**:Run 卡片先 `awaiting-approval`,批准后变 `failed`,而 `currentPackageId` 始终是 `none` ⇒ 不是语法/加载错误,是 **host 半边根本没被执行**。
3. **只有带 client 半边的包会失败**:同一条成员会话里,host-only 的 `guard-1/pkg-4` 能正常 `running`(对照实验),说明成员会话本身没坏。

**为什么(源码依据;路径 = `<DSH_APP>\node_modules\@deepseek-ai\`)**

| 环节 | 证据(文件 : 行) | 说明 |
| --- | --- | --- |
| 批准后由**浏览器侧**发起 host 半边激活 | `dsh-cordis-client-runner\lib\client.js:927` `runHostHalf(plan.agentId, …)`,`agentId` = `plugin.sessionId` | 传的是**会话 id 字符串** |
| 该 RPC 首参类型是 `Agent`,先由 typert 查表解析 | `dsh-cordis-host-runner\lib\typert.host.js:122-127`(参数 schema) | 解析失败 ⇒ 方法体与 host 代码都没进 |
| 解析收口到 Session 控制器 | `dsh-api-session-controller\lib\index.js:185-189`(lookups)、`:195-199`(host context `"agent"`)→ `resolveAgent` | 两条路都走 `resolveAgent` |
| subagent 归属的会话被**设计性拒绝** | 同文件 `:124-130` `hasApiSessionSubagentOwner`(`origin === 'subagent'` ⇒ true;父归属同理)、`:136-137` 抛出 `session/agent-busy`、`:368-372` `liveAgent()` 直接返回该错误 | **静态归属**,与会话是否「正忙」无关 |
| 失败被记成 `host-half-failed` | `dsh-cordis-client-runner\lib\client.js:5100-5104`(把 RPC 错误格式化为 `${code}: ${message}`)、`:876-885` | 正是报错卡片上那两行的来源 |

**结论:host 半边**不能**解耦这条会话依赖(源码级理由)**

1. 失败发生在**参数绑定**,早于任何 host 代码被求值:`client.js:925-934` 是先 `await this.env.host.runHostHalf(...)`,失败后再由 `:876-885` 记账;`panel/host-half.js` 的 `apply()` 从未被执行。
2. 所以 host 半边里**没有任何一行**能影响这一步:加 `inject`、改 `ctx.get(...)`、把采集器逻辑搬进 host 代码,都发生在绑定成功**之后**,对绑定结果无影响。
3. **拆成 host-only 包也救不了面板**:注册 `settings.section` 必须有 client 半边,而「有 client 半边」就必然走审批 + `runHostHalf(agentId)`(`dsh-cordis-host-runner\lib\index.js:1707-1715`:有 client 半边才 arm 审批,没有则直接 activate)。
4. **也不能换会话替我激活**:`owned(agent, pluginId)` 要求 `plugin.sessionId === agent.id`(`dsh-cordis-host-runner\lib\index.js:2550-2553`),插件只能由定义它的那条会话激活;而那条会话是 subagent 归属 ⇒ 死结。

**最小正确做法(不需要改本仓库任何文件)**

1. 在**普通交互会话**(工作区级或用户自己的顶层会话)里,把 `panel/host-half.js` 与 `panel/client-half.js` 的**全文**分别作为 `code.host` / `code.client` 传给 `cordis_define`(**新建**插件:新 idPrefix,3–6 个小写字母,例如 `rtgp`);
2. `cordis_run(pluginId="<新 id>", packageId="<新 pkg>", mode="run")` → `awaiting-approval` → 你在界面上点批准;
3. 按 §1.2 的位置与判据观察;**回滚** = `cordis_stop("<新 id>")`(或 `cordis_undefine`)。

> 只想立刻拿到判定、不需要 GUI 的话:直接跑 §1.3 里的 `collect.ps1 -CheckOnly`(或用 host-only 的 `guard-1` 提供的工具 `remote_tailnet_posture`),这两条路都不经过上面的审批与 Agent 解析。

### 1.5 可逆性

- `cordis_stop("panel-2")`:移除 host 私有方法 + client 槽位注册,面板分区项消失;**不落盘、不改设置、不留监听**。
- `cordis_stop("guard-1")`:移除 Service / 私有方法 / 工具,并 `terminate()` 正在跑的子进程。
- `cordis_undefine(...)`:永久删除(仅在确定不再需要时用)。
- 进程重启后动态包消失 —— 这是本版「不落盘、可逆」的取舍;持久化形态见 §4。

---

## 2. 激活清单(供 t9 待办清单里点一次)

> 本任务**不做**运行时激活取证(契约要求延后)。你在 t9 点这一次时,照下表核对即可。

| # | 步骤 | 预期位置 | 观察点 | 通过判据 | 失败判据 |
| --- | --- | --- | --- | --- | --- |
| 1 | `cordis_inspect_self()` | 会话内的 Plugin 列表 | `panel-2` 是否存在、`pkg-5` 是否是 `nextPackageId` | `pkg-5` 已被 define 且未报错 | 找不到 `panel-2` ⇒ 进程已重启,需重新 define |
| 2 | `cordis_run("panel-2","pkg-5","run")`(**先确认你在普通交互会话里**,见 §1.4) | Run 卡片 | 返回值 | 先 `awaiting-approval`(需你点同意)→ 再 `starting` | 报 `host-half-failed: … is owned by subagent routing` ⇒ 见 §1.4(当前会话是 subagent 归属;换会话**新建**插件,不要重试);报语法/加载错误 ⇒ 读 `cordis_inspect_self` 诊断 |
| 3 | 打开设置面板 | GUI 设置左侧分区导航 | 是否多出 `Remote access link (read-only posture)` | 出现;点开无白屏 | 不出现 ⇒ §1.3 第 2 行 |
| 4 | 看总判定与计数 | 分区顶部 | 四态计数 + 退出码说明 | 计数和 `collect.ps1` 的 `summary` 一致 | 数字与 CLI 不一致 ⇒ 采集器路径不同,回报 |
| 5 | 看 `low confidence` 标记 | 列表里的降级项 | 至少 `NIC_PROFILE_ATTRIBUTION` / `POWER_S0_CAPABILITY` 带该标记 | 标记出现 | 无标记 ⇒ host 半边的 confidence 透传断了 |
| 6 | 看底部**四条** notice(凭据纪律三条 + 非侵入性一条) | 分区底部 | 文案 | 四条都在 | 缺失 ⇒ 回报 |
| 7 | 确认 GUI 健康 | 整个界面 | 顶部有无 `Failed to load plugins` | 无;可选其它会话正常 | 有 ⇒ 立刻 `cordis_stop("panel-2")` |

---

## 3. Slot / Builtin 契约证据(本地源码;零 client Inspect)

**硬性纪律**:本任务全程**没有**调用过 `platform:"client"` 的 `cordis_inspect_query`(无页面应答时会挂起约 4 分钟再报错)。
client 侧契约只来自两条本地路:**t3 的源码取证结论** + **直读 `node_modules\@deepseek-ai\` 下 `dsh-client-*` 与 `dsh-cordis-client-runner` 的 `lib\*.js`**。

`<app>` = DSH 应用的**代码目录**(占位符,**别写死机器路径**):`<DSH_APP>`,即 `<APP_DIR>\resources\app`(`<APP_DIR>` = DSH Desktop 安装目录)。
解析方式(**任何机器都适用,不要抄字面量**):

```powershell
$exe = (Get-Process -Name 'DSH Desktop' -ErrorAction Stop | Select-Object -First 1).Path
$app = Join-Path (Split-Path -Parent $exe) 'resources\app'    # ⇒ <DSH_APP> = <APP_DIR>\resources\app
```

> 本文与其它文档里所有 `<app>\…`、`<DSH_APP>\…`、`<APP_DIR>\…` 都指上面这段解析出来的目录;源码证据的**行号**与基线读数不随机器改变,只有路径前缀被占位化。

| 契约 | 取值 | 证据(文件 : 行) |
| --- | --- | --- |
| 目标 slot | `settings.section` | `dsh-cordis-client-runner\lib\client.js:3871-3920`(契约条目:`key`/`kind`/`scope`/`registerOptions`/`ownerProps`/`declaredBy`/`occupants`/`replaceRisk`/`example`);该条目自称来源 `packages/client/ui-settings/src/client/contract/slots.ts:54` |
| slot 类型 | `kind: "list"` ⇒ **必须给 `options.id`** | 同上 `:3873`;校验实现在 `dsh-client-ui-slots\lib\index.js:90-95`(`list slot "…" requires options.id`) |
| 注册选项 | `id`(必填,string)、`order`(可选 number,升序)、`label`(可选 `string | (() => string)`) | `client.js:3877-3896` |
| owner props | `{ close: () => void }`(面板打开状态由外壳拥有) | `client.js:3897`(`SettingsSectionOwnerProps`) |
| 谁声明该 slot | `sidebar.settings` 里的一个入口(`client-ui-settings-general`),**该入口挂载期间才存在** ⇒ 必须用 `slots.inject` 等声明 | `client.js:3910`(`declaredBy`) |
| 官方注册范例 | `ctx.slots.inject('settings.section', () => ctx.slots.register({ name, id, order, label }, () => React.createElement(...)))` | `client.js:3918` |
| 未声明 slot 直接抛 | `slot "…" is not declared (a parent entry's children table must declare it)` | `dsh-client-ui-slots\lib\index.js:74` |
| 同 id 同 priority 冲突 | list slot 同 `id`+同 `priority` 已存在 ⇒ 抛 | `dsh-client-ui-slots\lib\index.js:92-94` |
| 排序 | 按 `priority` 升序,list 再按 `order` 升序 | `dsh-client-ui-slots\lib\index.js:130` |
| 释放 | `register` 返回 disposer;disposer 递归释放其声明的子 slot | `dsh-client-ui-slots\lib\index.js:146-151`(及 `:371-391`) |
| 替换风险 | `replaceRisk: none` —— 用**全新 id** 会加在既有项旁边,不会顶掉 `general`/`models`/`plugins`/`agent-presets` | `client.js:3911-3917` |
| client Builtin | `React`(`createElement` / `useState` / `useEffect`)与 `host.call(method, args)` | `client.js:4636-4641`(React 三签名)、`:4647`(`host.call` 签名)、`:155`(`"React"` 在允许的闭包符号表里) |
| 没有浏览器计时器 | 用计时器必须 `inject: ['timer']` | `client.js:41` |
| 不能 `require`/`import` | `modules cannot be imported here. React arrives as the React closure symbol; everything else goes through ctx services or host.call.` | `client.js:55` |
| 未声明的 service 会被拒 | `ctx.get` 拿到的是受控面;可用 `ctx.on` / `ctx.provide` / 注入后的 timer + 你在 `inject` 里声明的 service(`slots` / `theme` 是常见 UI 席位) | `client.js:322-323` |
| Host↔Client 私有 RPC | Host `harness.handle(method, fn)`;Client `host.call(method, args)`;**同 Package 私有**,只传无损 JSON(host 侧实现见 `panel/host-half.js` 全文) | `client.js:5042-5071`(client 侧 Builtin 列表含 `slots`) |
| 已删包雷区 | client 半边不得引用 `@deepseek-ai/dsh-client-runtime`(**本机该包目录已不存在**;任何客户端入口 require 它都会让 GUI 卡在 `Failed to load plugins`) | 本任务静态检查实测为 **0**(见 §5 verify #2) |

### 3.1 刻意**没有**用的东西(以及原因)

| 没用 | 原因 |
| --- | --- |
| `tool.view.cordis`(`key:'self'`) | 那会把面板绑在 `cordis_run` 卡片上;姿态面板属于设置页,而动态包是临时的,放设置里更像「产品的一部分」 |
| 主题 token 覆盖 / 全局样式 | 面板只需要中性排版;覆盖主题影响面远大于本功能,收益为 0 |
| 声明 `children` | 不声明 ⇒ disposer 只管自己那一项,不会连带移除别人的子 slot |
| 复用 `general`/`models` 等既有 id | 会顶掉出厂分区(`client.js:3882` 明确警告);用全新 id |
| `settings.general.item` | 那是「一行偏好」的席位(full page 才是 `settings.section`);本面板是一整页 |

### 3.2 本轮**未能**取证的点(需页面在位,不阻塞)

- **运行时活的 slot 树与当前占位者**:`Slots.listSubTree` 属 client Inspect,按纪律禁用。因此「此刻 `settings.section` 里到底有哪几项在渲染」未取证;契约里的 `occupants` 列表来自源码目录,could 与运行时略有差异。
- **实际视觉呈现**(间距/暗色主题下的对比度):需要页面在位才能截图核对;本轮只保证用的是主题中性的内联样式与语义标签,没有依赖任何硬编码产品 DOM 选择器。

---

## 4. 持久化 profile 安装(清单 + 备份 + 回滚;**本任务未执行**)

> 契约要求:持久化安装**只提供**清单 / 备份 / 回滚,**必须由你显式授权后由你执行**。本节只给步骤与命令,**没有**在本任务里跑过。
> **影响面(先读)**:这一行会被该 profile 的**所有会话**加载 —— 这是它与动态包最大的差别。不确定就先按 §4.4 用 `disabled: true` 试。
> **措辞统一为「可选修复:由你执行」:不做持久化也能用**(默认是动态包,见 §1 与 §0.2)。

### 4.1 需要什么(仓库层,属 t12 的领地)

| 项 | 要求 | 现状 |
| --- | --- | --- |
| `remote-tailnet-plugin/package.json` | 声明 `dsh.client`(`platform`/`inject`)与 **`exports["./client"]`** 指向真实 client bundle | **未创建**(本任务不建,避免与 t12 冲突) |
| 真实 client bundle | 由打包产物提供;必须能被 `dsh-client-modules` 解析出 `clientPath`,否则 `__DSH_BOOT__` 404 | **未创建** |
| `remote-tailnet-plugin/cordis.patch.yml` | 一行 loader entry(`- id:` + `name:`) | **未创建** |
| profile 行 | 加到活动 profile 的 patch 层 | **未执行** |

### 4.2 备份(执行持久化的第 0 步,必做)

```powershell
# 运行时解析 profile 目录(不要写死路径)
$dshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE '.dsh' }
$patch   = Join-Path $dshHome 'profiles\desktop\cordis.patch.yml'      # 多 profile 时先用 -Profile 明确选一个
$stamp   = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup  = "$patch.bak-$stamp"
Copy-Item -LiteralPath $patch -Destination $backup -Force
"backup = $backup"
(Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash
(Get-FileHash -LiteralPath $patch  -Algorithm SHA256).Hash   # 两者应相同
```

> ⚠️ **F9(skill §5.4 的陷阱,必须读)**:备份出来的 `.bak` **可能是空 patch / 只有注释**(例如内容就是 `[]`)。
> 直接拿它整文件还原会**把整段预设行删掉**(`app\cordis.patch.yml` 里 `permission` 预设、`ego-browser` 的 `chromePath` 都靠这种行存在)。
> ⇒ **还原前必须先看备份内容**,并且**读备份必须显式 `-Encoding UTF8`**(PS 5.1 默认按 ANSI 读无 BOM 的 UTF-8,中文预设名会乱码);
> 哈希比对仍是**字节级**判据。完整命令见 §4.5 与本目录 `rollback.md` §2。

### 4.3 加行(由你执行,需显式授权)

```yaml
# 在 <DSH_HOME>\profiles\<name>\cordis.patch.yml 末尾追加(缩进与原文件一致)
- id: remote-tailnet-guard-panel
  name: remote-tailnet-plugin
```

### 4.4 行级开关与移除

```yaml
# 临时停用(推荐先这样试):HMR 约 1 秒重组合,无需重启
- id: remote-tailnet-guard-panel
  name: remote-tailnet-plugin
  disabled: true
```

> **影响面**:`disabled: true` 只影响你刚加的这一行;反过来说,**未**禁用的持久化行会被这个 profile 的**所有会话**加载。
> 只想试一下 → 优先用**动态包**(§1),别动 profile;确实要持久化 → 先备份(§4.2)、先 `disabled: true` 验证、再决定是否长期保留。

### 4.5 回滚(可粘贴)

```powershell
# A) 只停用:把上面那行改成 disabled: true,保存即可(HMR 约 1s 生效)
# B) 彻底移除:把添加的行删掉,保存
# C) 从备份整文件还原(改坏了才用)—— 先看内容,再还原(F9)

$dshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE '.dsh' }
$patch   = Join-Path $dshHome 'profiles\desktop\cordis.patch.yml'
$backup  = "$patch.bak-<你记下的时间戳>"

# C1) 先核对备份内容:空文件 / 只有 "[]" / 没有你要保留的预设行 => 停止,别还原
Get-Content -LiteralPath $backup -Encoding UTF8          # 必须显式 UTF8,否则中文预设名乱码
(Get-Item -LiteralPath $backup).Length
"backup sha256 = " + (Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash
"live   sha256 = " + (Get-FileHash -LiteralPath $patch  -Algorithm SHA256).Hash

# C2) 确认无误后再还原,并做字节级复核
Copy-Item -LiteralPath $backup -Destination $patch -Force
(Get-FileHash -LiteralPath $patch -Algorithm SHA256).Hash   # 与备份时记录的值逐字节一致
```

**持久化路径同样不做的事**:不装重启类插件、不改 `ExecutionPolicy`、不动 UAC、不新增监听。
回滚验证:`cordis_inspect_self()` 里该 Plugin 消失 / 设置里该分区项消失 / GUI 无 `Failed to load plugins`。

---

## 5. 安全硬约束自证

| 约束 | 事实 | 证据 |
| --- | --- | --- |
| 不新增监听 | host 半边只 `harness.handle` 一个私有方法;不调 `webServer.register`,不开端口,不建路由 | `panel/host-half.js` 全文;`guard-1/pkg-4` 同理 |
| 不落凭据 | 面板只渲染 host 返回的有界字段(id/role/title/verdict/label/reason/manual/remediation/**confidence**),`raw` 永不过桥;不读 token/cookie/凭据库 | `panel/host-half.js` 的 `boundedCheck()`;`panel/client-half.js` 的 `CREDENTIAL_NOTICES` |
| 不改系统配置 | 面板与安装引导只打印命令;`prereq.ps1` 没有执行路径,`-Apply`/`-Yes` 之类的开关不存在 | `panel/prereq.ps1` 头部声明 + 代码里无安装调用;`prereq-manifest.json` 的 `automationBoundary.never`;套件用例 `fault-apply-refused`、`isolation-no-writes-to-dsh-home`、`filescan-no-repo-write-paths` 每轮复跑这几条断言(§5 verify #4) |
| 不改防火墙 | 只读规则库与 netsh;**写操作没有调用点** —— 唯一命中是 `rem_fw_on` 的**文本**命令(`netsh advfirewall set allprofiles state on`,打印给人工执行),不是调用 | `src/collect.ps1` 全文 + `panel/prereq.ps1` 全文(§5 verify #6 有逐文件命中数);面板四条 notice 的第 4 条 |
| 绝不 require 已删包 | `*.js/.mjs/.cjs` 静态检查命中数 = **0** | 见下方 verify #2 的原始输出 |
| 无重启类逻辑 | 无杀宿主 / detached 自拉起 / `app.relaunch`;宿主**形态**证据:DSH 用 Electron `utilityProcess.fork` 拉起宿主(`<DSH_APP>\lib\main.js`),而 `<DSH_APP>\lib\host-process-entry.js:202-203` 在拿不到 `parentPort` 时**直接抛错** ⇒ 「杀宿主 + 自拉起」在本机必然失败 | `panel/*.js` 全文 |
| 不放宽安全设置当安装前置 | `automationBoundary.never` 显式列出 ExecutionPolicy / UAC / 防火墙默认 / Defender / networkExposure | `prereq-manifest.json` |
| 可逆 | 面板三项副作用(`slots.register` 的槽位项、host 的私有方法、host 的 Service)都挂在 `ctx.effect` / `slots.register` 的 disposer 上 | `panel/client-half.js` 末尾 `apply()`;`panel/host-half.js` 末尾 `ctx.effect(...)` |

**契约 verify 实测(2026-09-24;t26 复跑,全部只读)**:

1. `powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/src/collect.ps1 -CheckOnly`
   → 退出码 **2**(本机 verdict:1 blocked + 6 unknown;fail-closed,**不是命令失败**),`total=24 pass=15 degraded=2 blocked=1 unknown=6`。
2. `powershell -NoProfile -Command '(Get-ChildItem remote-tailnet-plugin -Recurse -Include *.js,*.mjs,*.cjs | Select-String -SimpleMatch "@deepseek-ai/dsh-client-runtime" | Measure-Object).Count'`
   → **0**
3. `powershell -NoProfile -Command 'Get-ChildItem remote-tailnet-plugin -Recurse -File | Measure-Object | Select-Object -Expand Count'`
   → **93**(t26 复核值;t20 是 85、t6 是 18。数字随任务变动,**判据是「同一条命令可复现」,不是某个固定值**)
4. **无写路径(两处硬证据)**
   - `powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/src/collect.ps1 -Apply` → 退出码 **2**,原文:
     `REFUSED: -Apply. This collector is read-only; no write path exists.` / `Nothing was changed. Re-run without -Apply and execute the printed remediation commands yourself.`
   - `powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/panel/prereq.ps1 -CheckOnly` → 退出码 **2**,尾行原文:
     `Nothing was installed, elevated, signed in, written or changed by this run.`;`-AsJson` 里 **`ranAnyInstall=false`**、`readOnly=true`。
     静态复核:`prereq.ps1` 里 `Start-Process|runas|msiexec|Register-ScheduledTask` **只有 2 处命中** —— 头注那一行,与
     `if ($installCmd -match 'msiexec')` 这个**字符串判断**(它只决定是否显示哈希门)**没有调用点**。
   - 套件每轮复跑这三条:`fault-apply-refused`(拒绝 `-Apply` 并 exit 2)、`isolation-no-writes-to-dsh-home`(整棵临时 DSH home 逐字节不变)、
     `filescan-no-repo-write-paths`(套件自己的写动作全部落在 `%TEMP%`)—— 见下面第 5 条的 52/52。
5. `powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/tests/run-tests.ps1` → **52/52 PASS / 0 failed / 0 xfail held / 0 xpass**,退出码 **0**;
   `powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/tests/run-fixtures.ps1` → `ALL PASS: 7 cases, 0 failed assertions`。
6. **不新增监听 + 不写防火墙**:`collect.ps1 -CheckOnly -AsJson` 里 `NO_NEW_WILDCARD_LISTENER = pass`(`ro_no_new_wildcard`:采集前后通配监听差集为空);
   防火墙**写操作**在 `src/` 与 `panel/` 里**没有调用点** —— 唯一命中是 `rem_fw_on` 的**文本**命令
   (`netsh advfirewall set allprofiles state on`,打印给人工执行的那一条),不是调用。

**已知限制(如实登记)**:

1. 动态包不落盘、进程重启即消失;持久化形态需要 §4.1 的仓库层产物(t12)。
2. **带 client 半边的动态包在 subagent 路由归属的会话里无法激活**(§1.4;实测失败原文 `session/agent-busy: session "…" is owned by subagent routing`)⇒ 在成员会话里对 `panel-2/pkg-5` **重试无意义**,正确做法是在普通交互会话里**新建**插件。
3. 运行时激活的观察(§1.2 的位置与判据、GUI 不出现 `Failed to load plugins`)需在**普通交互会话**里按 §1.1 点一次;这一步不改变本仓库任何文件。
