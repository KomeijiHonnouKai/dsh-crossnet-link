# remote-tailnet-guard

**English original: [README.md](README.md)**

> 最后更新:2026-09-24(captain 收尾 —— GitHub 账号 `KomeijiHonnouKai` 已写入 clone URL,§17.4 的最后一项未决
>             随之关闭;GitHub 账号与版权持有人是同一个名字(`KomeijiHonnouKai`);在此之前任务 t39 —— `tools/`
>             加入发布集、§17 增加卸载一行、§21 记录卸载器的六步、四种分类、退出码与只读承诺边界;过期的
>             「激活 / 许可」措辞也一并收口)
> 用过的命令  : `powershell -NoProfile -ExecutionPolicy Bypass -File .github/scripts/repo-hygiene.ps1 -Json`
>              `powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-tests.ps1`
>              `powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-fixtures.ps1`
>              `Select-String -Path README.md -Pattern 'uninstall'`
>              `powershell -NoProfile -Command '(Select-String -Path README.md -SimpleMatch <仓库名> | Measure-Object).Count'` —— 期望 **1**(下面 clone URL 是它唯一的出处;因此本页头部只用描述指代它,不写字面量)
>              `powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-smoke.ps1`

---

## 中文版完整度声明(请先读这一段)

这份 `README.zh-CN.md` 是英文 `README.md` 的**逐节镜像**:章节编号、顺序与层级与英文原文一一对应,`# remote-tailnet-guard` 标题、头部条目(Status / License / Repository / Platform / Security policy)、§1–§12、以及 Part II 的 §13–§21 全部在位,**没有任何一节被静默删掉**。

下表逐节点名每一节的处理方式。只有**维护者过程记录类**的节做了**忠实压缩**(把逐次时间线、逐轮毫秒数、内部评审过程压成结论),其余节是全文翻译;压缩的节都给出了指向英文原文的锚点(`README.md` + 节号)。压缩的含义是「信息不删、细节减写」:结论、命令、判据、边界、未验证项都保留;被压掉的只是重复的过程叙述。

| 英文原节(锚点) | 本文件的处理 | 说明 |
| --- | --- | --- |
| H1 `# remote-tailnet-guard` | 原样保留 | 仓库 / 产品名不翻译 |
| 头部 `LAST UPDATED` / `COMMANDS USED` 引用块 | 全文翻译 | 日期、任务号、命令原样 |
| 英文原文里的两处中文段落(`## 中文说明(先读这一段)`、`**中文摘要**`) | 不重复照搬 | 它们是「中文优先首页」方案的产物;本文件已把内容吸收进下面的〈目的〉〈三分钟上手〉〈中文文档在哪〉,事实口径以英文原文 §1 / §5 / §21 为准 |
| `## 目的:它解决什么问题` / `What it is for` | 全文翻译(两份 README 同名节) | 见 `README.md` 的 `## What it is for` |
| `## 插件界面(GUI)在哪里` | 全文翻译(两份 README 同名节) | 见 `README.md` 的 `## Plugin GUI: where it lives` |
| `## 实现方式与作者` | 全文翻译(两份 README 同名节) | 见 `README.md` 的 `## How it was built, and by whom` |
| §1 这是什么 | 全文翻译 | 三件交付物表逐行 |
| §2 检查哪些项 | 全文翻译 | 分组表 6 行 + 四态表 + 退出码 |
| §3 刻意**不**做什么 | 全文翻译 | 7 条逐条 |
| §4 安装 | 全文翻译 | 路径 A / 路径 B / 前置件 |
| §5 用法 | 全文翻译 | 采集器 / 前置件检查器 / 测试套件,命令原样 |
| §6 四格支持矩阵 | 全文翻译 | A/B/C/D 与证据等级 |
| §7 安全姿态 | 全文翻译 | P1–P8、威胁模型、安装包哈希策略 |
| §8 仓库布局与发布集 | 全文翻译 **+ 两处新增登记** | 布局块与发布集清单加入 `README.zh-CN.md`(t42)与 `plugin/` + `panel/plugin-preflight.ps1` + `docs/install/plugin-package.md`(t44) |
| §9 CI 与仓库卫生 | 全文翻译 | 两个 job / 三个门禁 / PSScriptAnalyzer |
| §10 发布集里的残留标识符 | 全文翻译 | 分类表逐行 |
| §11 版本号、标签与发布步骤 | 全文翻译 | 7 步 |
| §12 贡献与许可 | 全文翻译 | MIT 与版权行 |
| 本文件的 `Verification commands`(英文原文 2026-09-24 / task t12 那一块) | 全文翻译 | 见英文原文 §12 之后的同名小节 |
| `# Part II — detection contract, activation, wake-up to-dos and evidence chain (task t9)` | 全文翻译 | Part II 抬头与它的 `LAST UPDATED` / `COMMANDS USED` 引用块 |
| §13 检测项与每一项到底判什么 | 全文翻译 | 13.1 的 24 行表、13.2 的 13 行表、13.3 的 10 条不支持清单全部逐行 |
| §14 激活插件 —— 路径 A | 全文翻译 | 14.1 的会话归属坑与实测文本逐字 |
| §15 路径 B —— 常驻插件包 | 全文翻译 | 15.1/15.2/15.3 含备份与回滚代码块 |
| §16 四种 Windows 组合的前置件与坑 | 全文翻译 | 4 行矩阵表逐行 |
| §17 只能由人来做的待办 | **忠实压缩** | 见 `README.md` §17:17.1–17.6 每条的 what / how / why-the-machine-cannot 全部保留;逐次时间线、逐轮毫秒数、skill 文件逐文件对比过程压成结论。§17.2 的实测失败文本与 §17.4 的发布状态逐字保留 |
| §18 证据链(实测 / 引用 / 未验证) | **忠实压缩** | 见 `README.md` §18:18.1 的原始命令块、18.3 的未验证清单逐条保留;18.2 的「引用自其它任务」表按来源任务归并(任务号全部保留),18.4 压成两句 |
| §19 未决项与刻意的决定 | **忠实压缩** | 见 `README.md` §19:19.1 的七条判断每条保留一句,19.2 的表(含「已关闭」注记)逐行保留 |
| §20 交付清单与陌生人需要的三条命令 | 全文翻译 | 清单表逐行 + 三条命令原样 |
| §21 卸载与残留 | 全文翻译 | 六步表 / 四种分类 / 退出码 / 承诺边界逐条 |

**跨文档一致性**:本文件里的文件路径、命令、参数名与 `README.md` 逐个对齐。核对方式与结果:把本文件里所有以 `-` 开头的参数抽出来(41 个去重值),与仓库内 7 个脚本(采集器、前置件检查器、卸载器、三个测试入口、卫生门禁)以及它们引用的外部脚本(skill 的 `verify.ps1` / `server-setup.ps1`、`.dsh/tools/sync-skill.ps1`)的 `param()` 声明、加上实际 cmdlet 的参数集逐个比对 —— **invented = 0**;本文件引用的仓库相对路径逐个 `Test-Path` 核对 —— **全部存在**(含 `i18n/labels.{en,zh}.json` 花括号写法展开的两个文件)。两份 README 的〈目的〉〈GUI〉〈实现方式与作者〉三节内容一致,只是语言不同。若两份文件出现不一致,**以英文 `README.md` 为准**,并把本文件视为需要修的那一份。

---

## 目的:它解决什么问题(What it is for)

**一句话**:本仓库是「让 A 电脑的浏览器直接操作 B 电脑的 DSH 界面」这条跨网链路的**前置件与安全姿态体检器**——它不负责把链路打通,它负责判定链路现在处于什么姿态、还缺哪些前置件、以及怎么把它干净地卸掉。

**被体检的那条链路是什么**(只认这一条,已实测跑通的那一条):

1. 两台机器**不在同一个网络**(例如一台在公司、一台在家);
2. 两台机器加入**同一个 tailnet**(Tailscale 的私有网络);
3. 服务端机器上 DSH 只监听 **loopback** 端口,用 `tailscale serve --bg` 把它暴露到 tailnet 的 443;
4. tailnet 的 **ACL 收窄**到只放行「客户端 → 服务端 `tcp:443`」,服务端其它端口一律不放;
5. 客户端机器上的浏览器**带一次性 token 打开一次**那个地址,换到一枚长期 cookie;
6. 此后 A 机器的浏览器可以直接操作 B 机器的 DSH 界面(等价于能在那台机器上操作)。

**本仓库是这条链路里的哪一环**:

| 环 | 在哪 |
| --- | --- |
| 「怎么把链路打通」的操作手册 | 是 skill `dsh-remote-tailnet`,**不在本仓库** |
| 链路当前姿态的**只读判定**(四态 + 退出码 fail-closed) | 本仓库 `src/collect.ps1`(24 项检查) |
| **前置件检查**(装没装、签没签、要不要人工做) | 本仓库 `panel/prereq.ps1` + `panel/prereq-manifest.json`(13 项) |
| DSH **设置页里的只读面板** | 本仓库 `panel/client-half.js` + `panel/host-half.js`(见下一节) |
| **可完整干净卸载**的卸载器(默认干跑) | 本仓库 `tools/uninstall.ps1`(§21) |

**边界(一句话)**:它**不是**远控软件、**不做**代理、**不转发**任何流量、**不改**你的配置。它只读、只报,修不修、怎么修由你决定,每条建议都附回滚。

## 插件界面(GUI):它以两种形态交付

**GUI 已经做了**,就是 DSH 设置页里的一个分区,标题 `Remote access link (read-only posture)`,内容 = 只读姿态(四态 `pass / degraded / blocked / unknown`)+ 凭据纪律提示 + 「这里不会改动任何东西」的承诺。面板是**只读展示**,没有任何写入按钮。

它以**两种形态**交付,两者注册的是**同一个** `settings.section` 座位:

| # | 形态 | 怎么装载 | 活多久 |
|---|---|---|---|
| 1 | **动态 Cordis 包**(默认) | `cordis_define` + `cordis_run`,代码来自 `panel/host-half.js` + `panel/client-half.js`;见 §14 | **只在进程内存** —— 重启进程就消失,不落盘,所以没有东西需要卸载 |
| 2 | **常驻插件包**(`plugin/`,随发布集发布) | `plugin/package.json`(`type: module`、`main: ./lib/index.js`、`exports["./client"]` → `./lib/client.js`、`dsh.client` 块、`dsh.bundle.patch`)**加上** `plugin/cordis.patch.yml` 里那一行挂载行;见 §15 | 在磁盘上:重启也还在,直到那一行被移除 |

形态 1 的注册在 `panel/client-half.js`:`ctx.slots.inject('settings.section', …)` + `ctx.slots.register({ name:'settings.section', id:'remote-tailnet-guard', order:100, label:'Remote access link (read-only posture)' })` 注册。形态 2 从 `plugin/lib/client.js` 与 `plugin/lib/index.js` 注册**同一个**座位。

**口子(照实说)**:本修订版交付的座位**只有这个设置页分区**。「设置 → 插件」页里的**插件卡片**是另一个座位(`settings.plugin.item`),**本修订版没有实现** —— 所以启用形态 2 只会把包加进 profile 的 bundle 列表、把分区加进设置页,**不会**在插件页里多出一张卡片(见 §19.2)。

**为什么形态 2 是第二步、并且默认 `disabled: true`**:安装它会写进**你自己的** DSH profile(`dsh plugin --profile <name> add <这个包>` 会把包装进 profile 并调整 profile 的 bundle 列表),而那一行会影响该 profile 的**全部会话**;client 入口一旦写错,整个 GUI 会卡在「Failed to load plugins」的恢复模式(这是本机 `AGENTS.md` 里记录过的真实坑,不是理论风险)。所以 `plugin/cordis.patch.yml` 里那一行挂载行**默认 `disabled: true`**:只要它还是禁用状态,loader 就不会启动这一行、client 模块扫描也会跳过禁用项 —— 两条锚点都记在该文件自己的注释里(`cordis-plugin-loader/lib/index.js:391`、`dsh-client-modules/lib/index.js:778`)—— 因此在**你启用它之前,装上这个包什么都不做**。启用前先跑只读预检(`panel/plugin-preflight.ps1`,退出码 0/1/2),并且首次启用建议用**一次性 profile**。

**出问题时的第一动作**:把那一行改回 `disabled: true`(或直接删掉那三行),然后从 DSH 自带菜单重启;如果 GUI 已经坏了,就用第 1 步的备份**整文件还原** `cordis.patch.yml`。这就是 [`docs/install/plugin-package.md`](docs/install/plugin-package.md) §6(四步回滚)与 §7(第一动作);同一份文件的 §5 是三步启用、§4 是只读预检。

**哪些已验证、哪些没有**:包的形状、编码、唯一一行禁用挂载、以及 client 共享正文逐字节一致,由离线预检与静态用例 `tests/cases/plugin-package-shape/` 覆盖;**在真实 DSH 里装载过没有做到** —— 那需要你启用那一行(§15,或 `docs/install/plugin-package.md` §8 的一次性 profile 路线)。

激活、观察点、成功/失败判据与回滚:见本文 §14(形态 1,默认)与 §15(形态 2,需你显式授权)。

## 实现方式与作者

本仓库**由 AI 全程实现**:在 DSH Desktop 内以多智能体协作完成,分工为研究 / 工程 / 测试 / 文档 / 安全评审,所用模型为 `deepseek-official/deepseek-v4-flash-vision-exp`(DeepSeek V4 Flash)。**人负责需求、决策与验收。**

因此本仓库里没有任何一句「自称」的结论:所有验收结论都来自**可复现命令** —— 门禁 `.github/scripts/repo-hygiene.ps1`、离线套件 `tests/run-tests.ps1`、夹具套件 `tests/run-fixtures.ps1`、冒烟入口 `tests/run-smoke.ps1`。跑一遍就知道,不必相信这段文字。

许可与版权行保持原样:`LICENSE` 是最终 MIT 文本,版权行为 `Copyright (c) 2026 KomeijiHonnouKai`(见 §12)。

## 三分钟上手(下面每条都是只读的;唯一会写东西的是最后那条,而它默认**干跑**)

```powershell
# 1) 在工作区根克隆 —— 第二个参数不能省(原因见下面 Repository 一行)
git clone https://github.com/KomeijiHonnouKai/dsh-crossnet-link remote-tailnet-plugin
cd remote-tailnet-plugin
# 2) 离线、只读、确定性的冒烟入口:一条命令自证(它自己声明三级退出码:
#    0 = 全绿;1 = 没有 FAIL 但有 SKIP(干净环境里的正常结果,例如没有对端就跳过链路判定);2 = 有 FAIL)
powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-smoke.ps1
# 3) 看本机姿态(加 -AsJson 得到机器可读报告)
powershell -NoProfile -ExecutionPolicy Bypass -File src\collect.ps1 -CheckOnly
# 4) 卸载:默认干跑、不写任何东西;要真回滚才加 -Apply(写前自动备份)
powershell -NoProfile -ExecutionPolicy Bypass -File tools\uninstall.ps1 -Plan
```

**中文文档在哪**

| 想看什么 | 看哪里 |
| --- | --- |
| 装什么、怎么装、每步怎么回滚 | [`docs/install/prerequisites.md`](docs/install/prerequisites.md)、[`docs/install/install.md`](docs/install/install.md)、[`docs/install/rollback.md`](docs/install/rollback.md) |
| **完整卸载**(保留清单 / 备份保留或清空 / 残留自查) | [`docs/install/uninstall.md`](docs/install/uninstall.md) |
| 采集器 24 项判据与实现说明 | [`docs/collect.md`](docs/collect.md) |
| 谁能看到什么、边界在哪 | [`docs/threat-model.md`](docs/threat-model.md) |
| 安全承诺 P1–P8 与逐条复核命令 | [`SECURITY.md`](SECURITY.md) |
| 本 README 的英文原文 | [`README.md`](README.md) |

**卸载的三条硬规则**(全文见 [`docs/install/uninstall.md`](docs/install/uninstall.md))

1. **只回滚它自己改过的**:journal 记录过、**且当前值仍等于本工具 remediation 应产生值**的项才回滚;别人后来改过的一律只报告、不触碰。
2. **默认保留**:Tailscale 本体、其它 DSH 插件、**你自己写的防火墙规则**、工作区文件、用户级 skill 副本 —— 全部保留;工具里没有任何卸载 Tailscale 的代码路径。
3. **备份可留可清**:备份默认保留;要清空得显式 `-PurgeBackup`,而且只删它在 `StateDir` 下自己创建、且逐文件 sha256 校验通过的备份目录。

## 目录

- [§1 这是什么](#1-这是什么)
- [§2 检查哪些项](#2-检查哪些项)
- [§3 刻意不做什么](#3-刻意不做什么)
- [§4 安装](#4-安装)
- [§5 用法](#5-用法)
- [§6 支持矩阵(四种 Windows 组合)](#6-支持矩阵四种-windows-组合)
- [§7 安全姿态](#7-安全姿态)
- [§8 仓库布局与发布集](#8-仓库布局与发布集)
- [§9 CI 与仓库卫生](#9-ci-与仓库卫生)
- [§10 发布集里的残留标识符](#10-发布集里的残留标识符)
- [§11 版本号、标签与发布步骤](#11-版本号标签与发布步骤)
- [§12 贡献与许可](#12-贡献与许可)
- [Part II 抬头](#part-ii--检测契约激活待办与证据链task-t9)
- [§13 检测项与每一项到底判什么](#13-检测项与每一项到底判什么)
- [§14 激活插件 —— 路径 A](#14-激活插件--路径-a动态-cordis-包的默认路径)
- [§15 路径 B —— 常驻插件包](#15-路径-b--常驻插件包可选需你显式授权)
- [§16 四种 Windows 组合的前置件与坑](#16-四种-windows-组合的前置件与坑)
- [§17 只能由人来做的待办](#17-待办--只能由人来做的事)
- [§18 证据链](#18-证据链本任务实测引用自其它任务仍未验证)
- [§19 未决项与刻意的决定](#19-未决项与刻意的决定请不要顺手修)
- [§20 交付清单与三条命令](#20-交付清单与陌生人需要的三条命令)
- [§21 卸载与残留](#21-卸载与残留--完整干净且从不静默)

---

## 1. 这是什么

四件交付物,共用一个检测内核:

| 件 | 入口 | 是什么 |
|---|---|---|
| 采集器 / 判定器 | `src/collect.ps1` | 24 项检查、四种判定、退出码 0/1/2,可注入夹具(fixture) |
| 前置件检查器 | `panel/prereq.ps1` + `panel/prereq-manifest.json` | 13 项前置件,每项带角色、检测方式、**只打印不执行**的安装命令、验证与回滚 |
| DSH 插件(动态 Cordis 包) | `src/host-half.js`、`panel/host-half.js`、`panel/client-half.js` | host 半边暴露一个有边界的姿态读取;设置页面板是**只读展示** |
| 常驻插件包 | `plugin/package.json`、`plugin/cordis.patch.yml`、`plugin/lib/index.js`(host 半边)、`plugin/lib/client.js`(loader bundle)、`plugin/lib/client/index.js`(ESM 孪生源) | 同一个只读设置页分区,做成可安装的包;它唯一那行挂载行默认 `disabled: true`,所以装上之后在你启用之前什么都不做 |

配套材料:`i18n/labels.{en,zh}.json`(全部非 ASCII 文案)、`docs/collect.md`(实现说明)、`docs/threat-model.md`(谁能看到什么、能做什么)、`docs/install/{prerequisites,install,rollback}.md`、`docs/install/plugin-package.md`(常驻包的启用 / 验证 / 回滚)、`panel/plugin-preflight.ps1`(它的只读预检,退出码 0/1/2),以及离线套件 `tests/run-tests.ps1`(`tests/cases/` 下每个目录一个用例)。

## 2. 检查哪些项

| 分组 | 检查项 |
|---|---|
| Host | `OS_BUILD`、`HOST_PS_ENV`(探测能力)、`PRIVILEGE_LEVEL` |
| Link | `TAILNET_ADDRESS`、`MAGICDNS_RESOLVE`、`PEER_TCP_443`(connected / refused / timeout)、`PEER_ISOLATION_PROBES`(135、5357 与 DSH 端口都**不得**应答)、`SERVE_PRESENT` |
| Exposure | `DSH_LOOPBACK_ONLY`、`WILDCARD_LISTENER_INVENTORY`、`DSH_NETWORK_EXPOSURE`、`TRUSTED_HOSTS_PATCH`、`NO_NEW_WILDCARD_LISTENER`(前后自证) |
| Tailscale | `TAILSCALE_CLI_LAYER`、`TAILSCALE_SERVICE`、`TAILSCALE_PROCESS_EDGE_DB`、`TAILSCALE_IN_RULES` |
| Windows 姿态 | `FIREWALL_PROFILES`、`NIC_PROFILE_ATTRIBUTION`、`POWER_STANDBY_IDLE_AC_DC`、`POWER_S0_CAPABILITY`、`BROWSER_PROXY_TSNET` |
| 仅客户端 | `HTTPS_CLIENT_ONLY`(需要 Node/OpenSSL 探测;schannel 下的 `curl` 会误报) |
| 自审计 | `CREDENTIAL_DISCIPLINE`(把它本轮执行过的每一条探测命令字符串重新审一遍) |

判定是 **fail-closed**(不确定绝不当通过):

| 判定 | 含义 |
|---|---|
| `pass` | 该性质在这台机器上被**证明**成立 |
| `degraded` | 该性质只部分成立,或证据是经本地化 / 回退路径读到的(报告里 `confidence: low`) |
| `blocked` | 该性质被违反,或采集器根本跑不起来 |
| `unknown` | 没有任何探测能回答。**绝不**被当成通过;`-Strictness strict` 会把它抬升为退出码 2 |

退出码:`0` 每一项判定都通过;`1` 至少一项 degraded/unknown;`2` 至少一项 blocked,或采集器根本跑不起来。

## 3. 刻意**不**做什么

**这个插件是只读、只报告的。** 它从不修改防火墙,从不要求你改已有的 DSH profile 或别的插件的配置,也从不重启 DSH;它建议的每一个修复都由**你**来执行,而且每条都随附回滚方式与影响面([`docs/install/rollback.md`](docs/install/rollback.md))。下面每一条都是这一立场的一个具体情形。

- **永远不安装任何东西。** 没有 `msiexec`,没有 `Start-Process`,没有 `runas`,没有计划任务,不改执行策略。缺前置件时,它只给出一条可打印、给人执行的命令。
- **不新增监听、路由、防火墙规则,也不做 `tailscale serve` 发布。** `-Apply` 会被接受但**被拒绝**(退出 2),因为本修订版没有任何写入路径。tailnet ACL 始终是人在 Tailscale 管理台里做的动作。
- **不碰凭据。** 它从不打开 DSH 凭据库、bridge token 文件、浏览器 cookie 数据库或会话日志;从不打印、存储或外传任何秘密材料。
- **没有遥测、没有回调、没有自动更新。**
- **没有重启逻辑。** DSH host 是一个 Electron `utilityProcess` 子进程,离开它的 supervisor 就无法存活,所以「杀掉 host 再重新拉起」这类设计会把产品搞坏。本仓库里没有这种东西。
- **不做局域网 / 整机桌面 / 非 Windows 的路径。** 本工具只覆盖一条已实测的链路:同一 tailnet + 服务端 `tailscale serve` + 只放行「客户端 → 服务端 TCP 443」的窄 ACL + 浏览器用 token URL 换长期 cookie。它不是通用远控管理器,也不提供任何兜底机制。
- **不做自动 soak 测试,也不做自动修复。** 长时间观测与每一个修复都刻意留在人手里。

## 4. 安装

**路径 A(默认):动态 Cordis 包 —— 进程内,不落盘。** 用 `panel/host-half.js` 与 `panel/client-half.js` 定义这个包、运行它,设置页里就会出现那个分区。进程重启后什么都不剩,所以也**没有什么需要卸载**。完整步骤与成功/失败判据:[`docs/install/install.md`](docs/install/install.md) §1。

**路径 B:常驻插件包 —— 需要显式授权。** 包现在随仓库发布在 `plugin/`,但安装它会写进**你自己的** DSH profile(`<DSH_HOME>/profiles/<name>/…`),所以本项目只写文档、**从不代你执行**:先跑只读预检,备份 profile patch,安装,验证设置页里出现分区,然后用两种方式之一回滚 —— 把那一行改回 `disabled: true`,或整文件还原。三步启用、四步回滚与一次性 profile 路线:[`docs/install/plugin-package.md`](docs/install/plugin-package.md) §5 / §6 / §8;更早的「手写一行」变体:`docs/install/install.md` §4 与 [`docs/install/rollback.md`](docs/install/rollback.md)。

前置件(Tailscale、登录、DSH 端口只监听 loopback、防火墙规则、ACL、首次 token 打开、代理绕行)按角色列出检测方式与回滚:[`docs/install/prerequisites.md`](docs/install/prerequisites.md)。

## 5. 用法

### 采集器

```powershell
# 默认:人类可读,只读
powershell -NoProfile -ExecutionPolicy Bypass -File src/collect.ps1 -CheckOnly

# 机器可读报告
powershell -NoProfile -ExecutionPolicy Bypass -File src/collect.ps1 -CheckOnly -AsJson

# 只跑一侧(纯客户端机器不需要服务端那些检查)
powershell -NoProfile -ExecutionPolicy Bypass -File src/collect.ps1 -CheckOnly -Role client `
  -Peer <PEER_IP> -PeerName <HOST>.<TAILNET_DOMAIN>

# 它解析出了什么、从哪来的(参数 > 环境变量 > 自动发现 > 默认值)
powershell -NoProfile -ExecutionPolicy Bypass -File src/collect.ps1 -Describe

# 离线:判定一份抓下来的夹具,彻底禁止真实探测
powershell -NoProfile -ExecutionPolicy Bypass -File src/collect.ps1 -CheckOnly -FixturePath tests/fixtures/en.json -NoNative

# 需要显式开启的写入(这是本脚本唯一能做的写入)
powershell -NoProfile -ExecutionPolicy Bypass -File src/collect.ps1 -CheckOnly -AsJson -OutFile $env:TEMP\rtg-report.json
```

其它开关:`-Lang auto|zh|en`、`-LabelsDir`、`-Port`、`-TailnetDomain`、`-Profile`、`-DshHome`、`-AppDir`、`-Strictness normal|strict`、`-TcpTimeoutMs`、`-DnsTimeoutMs`、`-CommandTimeoutMs`、`-ToolPath`、`-TrustedHostPattern`、`-DumpFixture`、`-ShowRaw`、`-Apply`(会被拒绝)。

在参考机器上实测(2026-09-24,Windows 10 Pro 19045,Windows PowerShell 5.1.19041,未给 `-Peer`,约 12 秒):

```
total=24  pass=15  degraded=2  blocked=1  unknown=6   exit=2
```

请如实读这行数据:`blocked` 那一项是本机 DSH 的 `trustedHosts` 补丁(本机没打),6 个 `unknown` 是需要对端地址、或需要一个普通(非沙箱)终端窗口才能问到的项。在一对**配置齐全**的机器上,同一条命令不会报 unknown;这个工具的意义就在于:这两种情况都不靠猜。

### 前置件检查器

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File panel/prereq.ps1 -CheckOnly
powershell -NoProfile -ExecutionPolicy Bypass -File panel/prereq.ps1 -CheckOnly -Role client
powershell -NoProfile -ExecutionPolicy Bypass -File panel/prereq.ps1 -CheckOnly -Role server -ShowInstallPlan
powershell -NoProfile -ExecutionPolicy Bypass -File panel/prereq.ps1 -CheckOnly -AsJson
powershell -NoProfile -ExecutionPolicy Bypass -File panel/prereq.ps1 -Describe
```

`-Role both`(默认)会同时检查服务端**和**客户端的要求,所以一台纯客户端机器非零退出是**正常的** —— 那是 fail-closed 的判定,不是命令出错。其它开关:`-Manifest`、`-Lang`、`-DshHome`、`-AppDir`、`-Port`、`-MsiPath`、`-CommandTimeoutMs`、`-NetstatStdoutFixture`、`-NetstatStatePattern`。本机实测(`-CheckOnly -AsJson`,只读):`total=13 pass=6 blocked=1 unknown=6 exit=2`。

### 测试套件

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-tests.ps1 -List
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-tests.ps1 -Filter locale
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-tests.ps1 -Only isolation
```

`tests/cases/` 下每个目录一个用例(2026-09-24 是 **64** 个),每个用例都拿真实的采集器去跑注入的夹具:对端离线/拒绝/超时、serve 被挪走或不存在、DSH 端口被改、cookie 过期(401)、缺 `trustedHosts` 键、非管理员探测、Tailscale 不存在/未登录/读不到、带空格和中文的路径、本地化陷阱(包含「中文工具输出 + culture 设成 `en-US`」这一种)、写隔离与零硬编码扫描 —— 再加上它们自己的**正对照**。其中有**一个**用例不跑采集器,而是对常驻插件包做静态形状检查:`tests/cases/plugin-package-shape/` 断言 37 条静态事实(`plugin/lib/*.js` 的解析、编码与「经典脚本」形态,`package.json` 的字段,唯一一个 `- insert:` 块与它的 `disabled` 键,以及被标记的 SHARED BODY 区段在 `plugin/lib/client.js` 与 `plugin/lib/client/index.js` 里逐字节相同)。要求:`tests/run-tests.ps1` 只需要 Windows PowerShell 5.1。

套件是自己数字的唯一出处:它在表头打印 `cases run / passed / failed / xfail held / xpass`,退出码就是结论,所以请读那些数字,不要读某份冻结的快照(用例数就是 `tests/cases/` 下的目录数)。`xfail` 标记是「已知规格缺口」的携带方式,用了它就不会把缺口藏起来;本套件当前一个都没挂。要求:只要 Windows PowerShell 5.1 —— 不需要 Pester、不需要模块、不需要网络。

## 6. 支持矩阵(四种 Windows 组合)

检测器与 OS 版本无关:它**结构化地**读 OS build、防火墙状态与电源能力,从不从「这是不是 Windows 11」去推断待机行为。

| # | 客户端 | 服务端 | 证据等级 |
|---|---|---|---|
| A | Windows 10 | Windows 11 | **唯一**做过实时端到端跑的组合(客户端 + 服务端并排,2026-09-24) |
| B | Windows 11 | Windows 10 | 服务端侧已在 Windows 10 上实测;客户端路径与 A 是同一段代码,但没有可用的 Win11 客户端做过实时跑 |
| C | Windows 10 | Windows 10 | 服务端侧已实测;客户端路径同 A |
| D | Windows 11 | Windows 11 | **没有实时验证过**;Win11 服务端姿态由夹具 `tests/fixtures/win11-server.json` 覆盖 |

「Windows 11 机器一定会进入 modern standby,所以链路必掉」在这里**不是**一个受支持的结论 —— `POWER_S0_CAPABILITY` 报的是那台机器上 `powercfg /a` 实际说的话,解释权留给人。上面任何被标为 `degraded`/`unknown` 的,在输出里就照那样报。

## 7. 安全姿态

- [`SECURITY.md`](SECURITY.md) 存着承诺索引与逐条的确切复核命令:**P1** 不新增监听 socket / 路由 / 防火墙规则,**P2** 默认只读,**P3** 不做自动写入且 `-Apply` 被拒绝,**P4** 不读/不打印/不存储/不外传凭据,**P5** 无遥测、无回调,**P6** 无重启逻辑,**P7** 每个副作用都挂在 `ctx.effect` 上且可移除,**P8** 面板是只读展示。
- [`docs/threat-model.md`](docs/threat-model.md) 回答「谁能看到什么」:tailnet 上的其它节点、DERP 中继(只有元数据 —— 流量是 WireGuard 加密的)、被攻陷的客户端、拿到 token URL 的人、以及服务端上的其它进程。值得重复的两条结论:**能打开那个 UI 就等于能操作那台机器**,以及 **loopback 按设计就是可信的**(本工具不改变这一点,也从不扩大它)。
- 客户端到 host 的数据只过一份有边界的字段白名单;原始块从不离开 host 半边。

### 安装包哈希策略

本仓库**不**预置厂商安装包的哈希。仓库里钉死的哈希会随上游下一次发版而过期,而过期的钉值要么挡住一次合法安装、要么把被篡改的包放过去 —— 两者都比另一种做法更糟。因此 `panel/prereq.ps1` 验证的是 Authenticode 签名,并支持一个**可选**的钉值(`panel/prereq-manifest.json` → `hashPolicy.pinnedSha256`),由操作者从**自己的**下载里算出并填入。在有人钉值之前,哈希门禁报 `blocked (hash_not_pinned)` —— 它从不猜,检查器也从不下载或运行任何东西。

## 8. 仓库布局与发布集

```
src/                collect.ps1(采集器)、host-half.js(插件 host 半边)
i18n/               labels.en.json、labels.zh.json
panel/              prereq.ps1、prereq-manifest.json、plugin-preflight.ps1(只读预检,退出码 0/1/2)、client-half.js、host-half.js
tools/              uninstall.ps1(唯一的可选写入组件:默认干跑,见 §21)
plugin/             package.json、cordis.patch.yml(唯一那行挂载行默认禁用)、lib/index.js(host 半边)、lib/client.js(loader bundle)、lib/client/index.js(ESM 孪生源)—— 常驻插件包
docs/collect.md     采集器的实现说明(随仓库发布)
docs/threat-model.md  威胁模型(随仓库发布)
docs/install/       prerequisites.md、install.md、rollback.md、uninstall.md、plugin-package.md(随仓库发布)
tests/              run-tests.ps1、run-fixtures.ps1、run-smoke.ps1、cases/、fixtures/
.github/            workflows/ci.yml、scripts/repo-hygiene.ps1、scripts/check-workflows.py
LICENSE  README.md  README.zh-CN.md  CHANGELOG.md  SECURITY.md  CONTRIBUTING.md  .gitignore  .editorconfig  .gitattributes
```

发布集就是上面这些路径,而且 **`panel/` 是其中一员**:前置件检查器(`panel/prereq.ps1`)、它的机器可读清单(`panel/prereq-manifest.json`,包括操作者用来钉哈希的 `hashPolicy` 块)以及插件的两个半边(`panel/host-half.js`、`panel/client-half.js`)都**随仓库发布**。面板不是可选的附加物:`.gitignore` 不排除它,卫生门禁把它当作**默认扫描根**(以前需要 `-ExtraRoots panel` 参数才行,而那意味着一个已发布文件只要待在错的目录里就能逃出门禁)。

**`tools/` 也是其中一员**:`tools/uninstall.ps1` —— 本仓库唯一的**可选写入**组件(默认干跑、必须 `-Apply`、写入前先备份,§21)—— 随仓库发布,同样是**默认扫描根**,因为一份缺了卸载器的克隆无法支撑「完整、干净地移除」这个承诺。

**`README.zh-CN.md` 同样随发布集发布**:它是本文件的**逐节中文镜像**(章节编号、顺序与英文原文一一对应),已登记进卫生门禁的默认扫描根,因此它不会漂到门禁覆盖范围之外。

**`plugin/` 也是其中一员**:常驻插件包(`plugin/package.json`、`plugin/cordis.patch.yml`、`plugin/lib/index.js`、`plugin/lib/client.js`、`plugin/lib/client/index.js`)随仓库发布,同样是**默认扫描根**;它的只读预检(`panel/plugin-preflight.ps1`)与中文的启用/验证/回滚说明(`docs/install/plugin-package.md`)也一并发布。`plugin/cordis.patch.yml` 里那唯一一行挂载行**默认 `disabled: true`**,所以已发布的这个包在操作者启用之前是**惰性**的(见 §15)。

**内部分析与评审材料不随仓库发布**:`.gitignore` 第 1 节列出的研究笔记、评审报告与验证记录,是设计检查项期间收集的工作文档,含有机器细节。它们被 `.gitignore` 排除,而排除清单不完整时卫生门禁会失败(清单的出处是**门禁**,不是这份文件)。

## 9. CI 与仓库卫生

`.github/workflows/ci.yml` 跑在 **windows** runner 上,分两个 job 完成:

1. 发布集卫生门禁 `.github/scripts/repo-hygiene.ps1`(被挡的标识符、私网段与节点后缀、凭据**值**形态、编码、二进制产物、已被移除的 client-runtime 引用、内部材料排除、文档标记)以及它自己的正/负 **self-test**;
2. workflow 解析 + schema 门禁 `.github/scripts/check-workflows.py`(把 PyYAML 6.0.2 钉为权威解析器,并带一个零依赖回退,所以离线也能跑);
3. 完整测试套件 `tests/run-tests.ps1`,在 Windows PowerShell 5.1 下运行;
4. 用 **PSScriptAnalyzer 1.22.0**(按钉定版本安装)做静态分析;error 级别失败即构建失败,warning 级别只打印供参考。

卫生门禁刻意严格:**被挡标识符、私网段与节点后缀命中 0**、凭据值形态 **0**、**未分类 token 0** —— 一个没有任何允许规则能解释的 token 本身就是一条阻断性发现,所以允许清单永远不能变成眼罩。它在发布集上报 `verdict: CLEAN`,发布集包含 `panel/` 下的全部四个文件,并在表头打印**实时文件数**(第一次写这一行时是 85;在 `tools/`、`README.zh-CN.md` 与 `plugin/` 都成为默认扫描根之后,实测为 **109**);CI job 不传任何扫描根参数,因为发布集**就是**默认范围。门禁**不**当作阻断的一切,其分类见第 10 节。本地跑同一套门禁:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .github/scripts/repo-hygiene.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .github/scripts/repo-hygiene.ps1 -SelfTest
python .github/scripts/check-workflows.py --selftest
```

## 10. 发布集里的残留标识符

**没有。** 门禁在发布集上报 `verdict: CLEAN`(0 条阻断性发现)。过去有两行文档带着开发机器上的绝对应用路径;随后的文档任务(t20,2026-09-24)已把这两处换成 `<DSH_APP>` / `<APP_DIR>` 替换值。门禁就是证据,而它对发现的东西**做分类**,不是只数个数:

| 命中类别 | 2026-09-24 实测(门禁每次运行都会打印实时数字) | 判定 |
|---|---|---|
| 被挡标识符(真实地址、主机名、用户路径) | 0 | 必须为 0 |
| 文档化前缀之外的私网 /24 与 ULA 节点后缀 | 0 | 必须为 0 |
| 凭据值形态(`tskey-…`、JWT、`key = <12+ 字符>`) | 0 | 必须为 0 |
| 作为字段名的凭据词、「从不读取」声明、夹具词汇 | 运行时会按文件报出来(几百条量级) | 在允许清单内;报出来供人工确认,本身从不致命(门禁打印实时数字与逐文件分布,文档里提到那五个词之一就会让它动) |
| 产品常量与净化后的替换值 | 12 个不同 token、135 次出现(`README.zh-CN.md` 加入发布集之前是 119 次) | 按 **token** 由 `.github/scripts/repo-hygiene.ps1` 顶部那份共享允许清单放行;**未分类 token 0**,而出现未分类 token 就会让门禁失败 |
| 未批准的 token(允许清单里没有任何规则能解释) | 0 | 必须为 0 —— 门禁的 self-test 会种一个进去,并证明它单独一个就能把判定翻成 FAIL |
| 已被移除的 client-runtime 包 | 代码引用 0、文档提及 2 | 代码必须为 0;文档是刻意引用这条禁令与检查命令 |
| 编码、二进制产物、内部材料排除、文档标记 | 0 | 必须为 0 |
| 行尾 | 全仓 LF;今天 2 个 CRLF 文件 | 两个都是 `tests/fixtures/` 下**故意**保留 CRLF 的抓取输出夹具,而且门禁现在**一条行尾备注都不报**了 —— 最后那一条(`tests/cases/README.md`)已经转成 LF;`repo-hygiene.ps1 -StrictLineEndings` 仍会把任何非夹具的 CRLF 文件升级成阻断性发现 |

复现方式:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .github/scripts/repo-hygiene.ps1 -Json
powershell -NoProfile -ExecutionPolicy Bypass -File .github/scripts/repo-hygiene.ps1 -SelfTest
```

`-SelfTest` 会在 `%TEMP%` 里为每一类违规各种一个文件,断言门禁确实报出了它们,然后再种一棵干净的树、断言 0 条发现 —— 于是一扇悄悄不再匹配的门禁会让它自己的对照失败,而不是给出一片假绿。

## 11. 版本号、标签与发布步骤

语义化版本:`MAJOR.MINOR.PATCH`。判定含义、退出码或 JSON 字段发生不兼容变化时升 `MAJOR`;新增检查项、用例或文档升 `MINOR`;修文字或检测逻辑、且不改契约时升 `PATCH`。标签是 annotated,名字为 `vMAJOR.MINOR.PATCH`(候选发布为 `vX.Y.Z-rc.N`),只由维护者创建。

发布步骤:

1. `LICENSE` 是最终 MIT 文本,带维护者的版权行(已定 —— 任务 t24)。
2. `tests/run-tests.ps1` 在 Windows 上全绿。
3. `.github/scripts/repo-hygiene.ps1` 打印 `verdict: CLEAN`。
4. `python .github/scripts/check-workflows.py --require-pyyaml` 全绿。
5. 把 `Unreleased` 的 changelog 条目移到新版本标题下,并写上发布日期。
6. 提交、创建 annotated tag、推标签。
7. 不附任何二进制:本仓库按政策是纯文本仓库。

## 12. 贡献与许可

硬规则(只读、fail-closed、零硬编码、编码表、净化规则)与「开 PR 之前要跑的命令」见 [`CONTRIBUTING.md`](CONTRIBUTING.md)。安全问题走 [`SECURITY.md`](SECURITY.md),不要开公开 issue。

许可:**MIT**。[`LICENSE`](LICENSE) 载有完整 MIT 文本与版权行 `Copyright (c) 2026 KomeijiHonnouKai`,`CHANGELOG.md` 也说了同样的话。这个选择已经定下来,因此本仓库里的一切都在 MIT 下发布,没有任何未决项。

---

### 本次交付用过的验证命令(2026-09-24,任务 t12)

```powershell
Get-ChildItem remote-tailnet-plugin -File | Select-Object -ExpandProperty Name
(Get-ChildItem remote-tailnet-plugin -Recurse -File | Select-String -Pattern '<blocked-identifier regex>' | Measure-Object).Count
Test-Path remote-tailnet-plugin/.github/workflows
powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/.github/scripts/repo-hygiene.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/.github/scripts/repo-hygiene.ps1 -SelfTest
powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/tests/run-tests.ps1
python remote-tailnet-plugin/.github/scripts/check-workflows.py --selftest
```

被挡标识符的正则在这里刻意不写出来:那份清单住在 `.github/scripts/repo-hygiene.ps1` 第 0 节,由片段拼装而成,这样门禁自己就不会成为它唯一的命中。

---

# Part II —— 检测契约、激活、待办与证据链(任务 t9)

> **最后更新**:2026-09-24(任务 t9 —— 集成与交接;下面第 13–21 节)。
> **用过的命令**(全部只读;没有 `platform:"client"` 的 Inspect、没有 `ego_*`、没有长等待):
> `powershell -NoProfile -ExecutionPolicy Bypass -File .github/scripts/repo-hygiene.ps1 -Json`
> (第一手:一开始是 `verdict: CLEAN (0 blocking finding(s))`、`blockedHits=0`、`credValueHits=0`、
> `unclassified=0`;门禁会打印实时文件数,所以这里不冻结它);`[Net.Sockets.TcpClient]` 5 秒探测(对端 443 在当地时间 18:25 为 `timeout`);
> `Select-String` 扫描检查项 id、允许清单里的替换值、以及四格判据(原始输出引在 §18);
> `Get-ChildItem` / `Get-FileHash` 对发布集做清单。第 1–12 节是仓库级 README(任务 t12/t24);这一部分加上
> **检测契约、激活路径、只能由人做的事与证据链**,不与前面重复。

## 13. 检测项与每一项到底判什么

这里随仓库发布的是**两套互相独立的检查项**:采集器(24 项检查、一份 JSON 报告、退出码 0/1/2)与前置件检查器(13 项,面向安装计划)。它们共用词汇,但**不共用阈值**。

### 13.1 采集器的检查项(24)

`role` 是这一项属于哪一侧;报告会给每一项打上这个标记,这样一次纯客户端运行不会因为缺了服务端项而看起来「坏了」。`evidence` 是判定的读取来源 —— **绝不是**某个配置文件,也绝不是一条没有 `confidence: low` 降级的本地化字符串。

| # | id | role | 判什么 | pass / degraded / blocked / unknown 怎么定 | 证据来源 |
|---|---|---|---|---|---|
| 1 | `OS_BUILD` | both | OS build 与分支 | 结构化读 build 号;`branch = win10 / win11` ⇒ pass;非 Windows 主机 ⇒ `unsupported-platform` blocked | 注册表 / CIM 回退 |
| 2 | `HOST_PS_ENV` | both | PowerShell host + 探测能力 | PS 5.1 Desktop ⇒ pass;答不出来的 host ⇒ degraded/unknown,**绝不** pass | `$PSVersionTable`、host 名 |
| 3 | `PRIVILEGE_LEVEL` | both | 当前进程是否提权 | 未提权是一种合法状态;把它报出来,是为了让后面每一次「探测被拒」读作 unknown | 令牌提权信息 |
| 4 | `TAILNET_ADDRESS` | both | 本机 tailnet 地址 / 是否入网 | 地址表里有 `100.64.0.0/10` 或 `fd7a:115c:a1e0::/48` 地址 ⇒ pass;**找不到 ⇒ unknown**(已登出不算 blocked) | `netsh interface ip show addresses` |
| 5 | `DSH_LOOPBACK_ONLY` | server | DSH 端口只在 loopback 上可达 | 监听行的 remote 列是 `0.0.0.0:0` **并且**真的能 TCP 连上 ⇒ pass;探测不可用 ⇒ unknown(`dsh_no_listener`) | `netstat` 行形态 + `TcpClient` |
| 6 | `WILDCARD_LISTENER_INVENTORY` | both | 非 loopback 监听,与 DSH 端口分开陈述 | 行解析出来了 ⇒ pass/degraded;探测不可用 / 状态词读不出 / 0 行 ⇒ `unknown`(`netstat_unavailable`) | `netstat`(+ 可注入的状态正则) |
| 7 | `TAILSCALE_CLI_LAYER` | both | CLI 分层 | 由 `ip` / `serve` 的退出码决定;命名管道被拒 ⇒ `unknown`(`ts_pipe_denied`),**绝不**写成「未登录」 | `tailscale ip -4`、`serve status` |
| 8 | `TAILSCALE_SERVICE` | both | Tailscale 服务状态 | 服务存在/运行 ⇒ pass;不存在/已停 ⇒ blocked/degraded | `Get-Service Tailscale` |
| 9 | `TAILSCALE_PROCESS_EDGE_DB` | server | 规则 `Tailscale-Process` **存储的** `Edge=` | `Edge=FALSE` ⇒ pass;`Edge=TRUE`/缺失 ⇒ **blocked**(`edge_false` 漂移);`Tailscale-In` 那组规则刻意是另一个检查项 | 注册表 `FirewallRules`(非提权可读) |
| 10 | `TAILSCALE_IN_RULES` | server | 内置的 `Tailscale-In` 入站允许 | 那里的 `Edge=No` 是**正常**的 ⇒ pass;不存在就报出来,不猜 | 注册表 `FirewallRules` |
| 11 | `NIC_PROFILE_ATTRIBUTION` | server | Tailscale 网卡落在哪个防火墙 profile | 走 enum 源 ⇒ pass,`confidence: high`;走本地化文本路径 ⇒ **degraded**,`confidence: low`;读不出 ⇒ unknown | `Get-NetConnectionProfile` → `netsh advfirewall monitor show currentprofile` |
| 12 | `FIREWALL_PROFILES` | server | 三个 profile 的状态 | 三个都读到 ⇒ 照实报告;读不到的 profile 是 unknown,不是「关着」 | `netsh advfirewall show allprofiles` |
| 13 | `POWER_STANDBY_IDLE_AC_DC` | server | AC/DC 空闲待机秒数 | AC=DC=0 ⇒ pass;DC≠0 ⇒ **degraded**(`power_dc_only`,例如 3600 秒)—— 用电池时链路会断 | `powercfg /query` 十六进制索引 |
| 14 | `POWER_S0_CAPABILITY` | server | S0/S3 能力与 `powercfg /a` 关于链路丢失说了什么 | 结构化解析 ⇒ `degraded` + `confidence: low`;原始行保留给人看 | `powercfg /a` |
| 15 | `DSH_NETWORK_EXPOSURE` | server | `networkExposure` | `loopback` ⇒ pass;`lan` ⇒ **blocked**(按定义那已经是一个新的通配监听) | settings / `-Describe` 的解析结果 |
| 16 | `TRUSTED_HOSTS_PATCH` | server | **实际加载的**补丁里的 `trustedHosts` | 一个裸 `host[:port]` 条目 ⇒ pass;空/缺失 ⇒ **blocked**(远端 UI 会拿到 `/api` 403) | profile 补丁文件 |
| 17 | `SERVE_PRESENT` | server | tailnet 侧的 443 serve 监听 | **t23 语义**:证据只来自**可读的 `tailscale serve status` proxy target 端口**;读不出 ⇒ `unknown`;`netstat` 形态只作旁证,**永不**当判定 | `tailscale serve status`(→ `netstat` 旁证) |
| 18 | `PEER_TCP_443` | client | 对端 443 的三态 | connected / refused / timeout,原样报告;没给 `-Peer` ⇒ `unknown`(`peer_not_provided`) | `[Net.Sockets.TcpClient]` |
| 19 | `PEER_ISOLATION_PROBES` | client | 对端非 443 端口**不得**应答 | 全部探测无应答 ⇒ pass;任一端口应答 ⇒ degraded(ACL 不够窄) | `[Net.Sockets.TcpClient]` |
| 20 | `MAGICDNS_RESOLVE` | client | 对端 MagicDNS 名能解析 | 解析成功 ⇒ pass;失败 ⇒ blocked/unknown,按原因分开 | DNS |
| 21 | `BROWSER_PROXY_TSNET` | client | 浏览器代理劫持 tailnet | 存在代理绕行 ⇒ pass;症状是「脚本一切正常、浏览器超时」的劫持 ⇒ degraded | `HKCU:\...\Internet Settings` |
| 22 | `HTTPS_CLIENT_ONLY` | client | HTTPS/证书判定 | 需要 Node/OpenSSL 探测:schannel 下的 `curl` 会误报,所以它的 `000` **不是**证据(见 skill 的探测能力表) | `rejectUnauthorized:true` 的 https 请求 |
| 23 | `CREDENTIAL_DISCIPLINE` | both | 自审计 | 把本轮执行过的每一条探测命令字符串重新扫一遍;出现任何凭据形态 ⇒ blocked | 它自己的报告 |
| 24 | `NO_NEW_WILDCARD_LISTENER` | both | 只读自证 | 运行前后的通配监听集合必须完全一致;探测答不出来 ⇒ `unknown`(`ro_probe_unavailable`) | 它自己的前后快照 |

权威措辞住在 `i18n/labels.{en,zh}.json`(每个 id、每种判定对应的 `title` / `reason`),每个注入故障的期望判定住在 `tests/cases/<name>/case.json`。上表是**阅读指南,不是第二处真相**:万一两者不一致,以 labels 与用例期望为准。

### 13.2 前置件检查器的检查项(13)

每一项都带 `roles`、`os`、`title`、`detect`、`whenMissing`,通常还有 `install`。

| id | roles | 检测 | 清单里的回滚 |
|---|---|---|---|
| `TAILSCALE_INSTALLED` | server+client | 命令 `tailscale version` → 注册表回退 | 有(卸载命令) |
| `TAILSCALE_CLI_LAYER` | server+client | 命令退出码(不是 `version`) | 无 |
| `TAILSCALE_SIGNED_IN` | server+client | 监听 / 守护进程状态 | 无 |
| `DSH_RUNNING_LOOPBACK` | server+client | 监听探测 | 无 |
| `SERVE_ON_TAILNET_443` | server | 监听探测 | 有(`tailscale serve reset` —— 见 §15.3) |
| `TRUSTED_HOSTS_CONFIGURED` | server | 委托给采集器那一项 | 有(删掉那一行) |
| `NARROW_INBOUND_ALLOW` | server | 注册表 | 有(`Remove-NetFirewallRule`) |
| `SERVER_POWER_IDLE_SLEEP` | server | 命令(`powercfg`) | 有 |
| `TAILNET_ACL_NARROW` | server | **人工**(管理台) | 无 |
| `CLIENT_FIRST_OPEN_TOKEN` | client | **人工**(由人粘贴一次 URL) | 无 |
| `CLIENT_MAGICDNS` | client | 委托 | 无 |
| `CLIENT_PROXY_BYPASS` | client | 注册表 | 有 |
| `HOST_SERVICE_FOR_PANEL` | server+client | 委托给插件 host 半边 | 无 |

有**三条清单级政策**比这些行更重要:

- **13 项的 `install.automatic` 全是 `false`。** 检查器只把命令打印给人看,它没有执行路径。`automationBoundary.never` 另外禁止:`runas`、`Start-Process -Verb RunAs`、计划任务、放宽 `ExecutionPolicy` / UAC / 防火墙 / Defender / `networkExposure`、登录、安装重启类插件,以及新增监听/路由/规则。
- **哈希政策**:不预置任何厂商哈希。在操作者于 `hashPolicy.pinnedSha256` 里钉一个之前,安装步骤报 `blocked (hash_not_pinned)` —— 算出来和钉进去必须并排发生,绝不猜。
- **读不出的探测文本**:`probeUnavailable` 提供「探测读不出时」使用的句子,判定是 `unknown`,永不是 `pass`(t16 F5:netstat 的状态词可注入,一个匹配不上任何东西的本地化结果会落到 unknown)。

### 13.3 本项目**不**覆盖什么(明确的不支持清单)

在 §3(不安装、不写入、不碰凭据、无遥测、无重启逻辑、无局域网/桌面路径)之外,规格还钉死了下面这份清单,而且它在 `-Describe` 输出里必须保持完全一致:

1. **非 Windows** 主机 —— `unsupported-platform`,立即退出;不做半吊子实现。
2. **非 Tailscale 的跨网方案** —— 整机桌面共享、局域网 HTTPS、第三方远控、SSH 隧道。只认一条路径:同一 tailnet + 服务端 `tailscale serve --bg` + 只放行「客户端 → 服务端 `tcp:443`」的窄 ACL。
3. **任何新增监听** —— `networkExposure: lan`、在 `0.0.0.0` 上 `serve --tcp`、或反向代理 ⇒ **blocked**(框架会断言不变量并抛错)。
4. **重启行为或重启类插件** —— host 是 Electron `utilityProcess.fork` 子进程;插件不得杀掉或重新拉起它。
5. **把本地化工具文本当成安全判定** —— `confidence: low` 降级就是为此存在的。
6. **读取、打印或外传凭据**(token、cookie、key 文件、凭据库)。
7. **默认写入操作** —— 一次写入需要同时满足四个闸门(显式开关 + 点名目录 + 打印出回滚 + 幂等),否则就不实现。
8. **只在 PowerShell 7 能用的语法** —— 下限是 Windows PowerShell 5.1。
9. **未验证的 DSH Desktop 版本** —— 能跑但不保证;启动横幅只打印已验证的那一对版本。
10. **任何必须由人做的事** —— 安装、登录、收窄 ACL、首次 token 打开、soak,以及每一个修复:工具打印出确切的步骤和确切的回滚,而不是替你做。

## 14. 激活插件 —— 路径 A(动态 Cordis 包的默认路径)

这条路径上**没有任何东西需要安装**:两个半边作为插件代码交给框架,并且**只活在进程内存里**。

| 包 | 半边 | 贡献了什么 |
|---|---|---|
| `guard-1` / `pkg-4`(只有 host) | `src/host-half.js` | Service `remoteTailnetGuard`、私有方法 `remote-tailnet-guard/posture`、工具 `remote_tailnet_posture` |
| `panel-2` / `pkg-5`(host + client) | `panel/host-half.js`、`panel/client-half.js` | 私有方法 `remote-tailnet-guard/panel/posture` + 一个只读的 `settings.section` 面板 |

步骤(由人执行一次,在**普通交互会话**里 —— 不是团队成员会话;原因见下面的坑):

1. `cordis_run(pluginId="guard-1", packageId="pkg-4", mode="run")` —— 可选:当共享 Service 不存在时,面板的 host 半边会自己跑采集器(`source=direct`),而那**不是**故障。
2. `cordis_run(pluginId="panel-2", packageId="pkg-5", mode="run")` —— 因为带 client 半边,首次激活会返回 `awaiting-approval`;**在 UI 里批准它**:单击勾 = 只授权这一个包,双击勾 = 授权同一个插件以后的版本。`awaiting-approval` 与 `starting` 都表示「还没完成」;请等到最终状态。
3. 可逆性:`cordis_stop("panel-2")` 会移除面板分区与那个私有方法(不留文件、不留设置、不留监听);`cordis_stop("guard-1")` 还会终止采集器子进程;`cordis_undefine(...)` 会永久删除这些定义。

### 14.1 ⚠️ 会话归属的坑(实测过 —— 而且被搁置的那张批准卡就会撞上它)

带 client 半边的包是由浏览器经由 host runner 激活的,而 runner 拿到的是**定义这个插件那个会话的 id**。由 subagent 路由持有的会话会被按设计拒绝(`session/agent-busy`、`hasApiSessionSubagentOwner`),host 半边的 `apply()` 根本不会被求值,任何 host 侧的改动都救不了它。实测失败文本(2026-09-24,一个团队成员会话,**在批准已被点过之后**):

```
host-half-failed
message: session/agent-busy: session "<SUBAGENT_SESSION_ID>" is owned by subagent routing
currentPackageId: none
nextPackageId: pkg-5
```

三个同时出现的症状可以确认这件事:消息里的 id 就是那个**定义者**会话;批准卡**可以**点,点完会翻成 `failed`,而 `currentPackageId` 一直是 `none`;同一会话里一个只有 host 的包仍然正常运行(这就是对照实验)。**最小正确动作是在一个普通交互会话里定义一个全新的插件**(新的 3–6 字母 idPrefix,例如 `rtgp`,把 `panel/host-half.js` 和 `panel/client-half.js` 分别当 `code.host` / `code.client`),然后批准**那个** —— 再点一次被搁置的那张卡,只会为同样的结果再花掉一次批准。两者的回滚都是 `cordis_stop("<id>")`。

**实测成功 —— 这个坑的建设性那一半(2026-09-24,默认工作区会话)。** 从本仓库的 `panel/client-half.js` 加一份等价的 host 半边(`panel/host-half.js` 作 `code.host`)在一个全新 idPrefix 下定义了**新**包 —— `rtgpnl-3` / `pkg-6` —— 并且 `cordis_run(pluginId="rtgpnl-3", packageId="pkg-6", mode="run")` 返回了 `awaiting-approval`。在 UI 里点勾之后,这次 run 到达 **completed**(run 6),面板出现在左侧设置导航里。所以正确的顺序是:**不要点属于成员会话的那张被搁置的卡;在一个普通工作区级会话里定义新包,然后批准那一个。** 成功判据、`awaiting-approval`/`starting` 的注意事项与回滚见 §17.2。

完整证据、源码锚点与失败表:`docs/install/install.md` §1.4 与 §2。

## 15. 路径 B —— 常驻插件包(可选,需要你显式授权)

这条路径会把包安装进你自己的 DSH profile;项目只负责**发布与写文档**、**从不代你安装**。仓库侧的前置件**现在已经存在**:[`plugin/package.json`](plugin/package.json)(`type: module`、`main: ./lib/index.js`、`exports["./client"]` → `./lib/client.js`、`dsh.client` 块、`dsh.bundle.patch`)与 [`plugin/cordis.patch.yml`](plugin/cordis.patch.yml)(恰好一个 `- insert:` 块,块里恰好一行,`disabled: true`)。`panel/plugin-preflight.ps1` 会在你动任何东西之前把这份形状只读地检查一遍;三步启用、四步回滚与一次性 profile 路线在 [`docs/install/plugin-package.md`](docs/install/plugin-package.md) §5 / §6 / §8。更早的「手写一行」变体仍在 `docs/install/install.md` §4。

**这里没有验证过的**:还没有人在真实 DSH 里装载过这个包。启用那一行是操作者的动作,而「设置页里出现这个分区」就是该验证的成功判据 —— 见 `docs/install/plugin-package.md` §5(启用)与 §9(未验证清单及原因)。

### 15.1 前置件

- 一个普通交互会话(与 §14.1 同一套归属规则),以及这个插件自己的文件都在位。
- profile 目录在运行时解析(`$env:DSH_HOME`,否则用户 profile)—— **绝不**硬编码路径;存在多个 profile 时必须显式选一个。

### 15.2 备份(第 0 步,必做)

```powershell
$dshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE '.dsh' }
$patch   = Join-Path $dshHome 'profiles\desktop\cordis.patch.yml'      # 多 profile 时:显式选一个
$stamp   = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup  = "$patch.bak-$stamp"
Copy-Item -LiteralPath $patch -Destination $backup -Force
"backup = $backup"
(Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash
(Get-FileHash -LiteralPath $patch  -Algorithm SHA256).Hash   # 与上一行相同
```

### 15.3 那一行、开关与回滚

```yaml
# plugin/cordis.patch.yml 里发布的就这一行(id 与 name 都必须等于 package.json 的 `name`)
- insert:
    - id: remote-tailnet-guard
      name: remote-tailnet-guard
      disabled: true      # 发布状态;改成 false 即为启用
```

`docs/install/plugin-package.md` §5 会把同样三行、但 `disabled: false` 的覆盖行追加到 profile patch 末尾,然后要求从 DSH 自带菜单重启;§6 的第 1 步把它改回 `disabled: true`(或删掉那三行),第 2 步用备份整文件还原。

回滚,从最便宜的开始:**(A)** 给这一行加 `disabled: true`;**(B)** 删掉这一行;**(C)** 用备份整份还原 —— **但先读一遍备份**,因为改动前的那份 `.bak` 可能是一份空补丁(`[]`),还原它会连带删掉别的 preset 行:

```powershell
Get-Content -LiteralPath $backup -Encoding UTF8      # 显式 UTF8:PS 5.1 会把无 BOM 的 UTF-8 当 ANSI 读
(Get-Item -LiteralPath $backup).Length
Copy-Item -LiteralPath $backup -Destination $patch -Force   # 只有上面这步检查通过之后才做
(Get-FileHash -LiteralPath $patch -Algorithm SHA256).Hash   # 与记录下来的值逐字节相同
```

前置件侧的回滚住在 `docs/install/rollback.md`。其中曾经写错、现在已修的那一条:撤销一次 `serve` 发布要用 **`tailscale serve reset`**(它会清掉那台机器上的**整份** serve 配置 —— 它不是按端口停用);用 `tailscale serve status` 验证。证据台账(`tailscale serve --help`,退出 0:USAGE 只列 `<target>` / `status [--json]` / `reset`,**没有** `off`)记录在 `docs/install/rollback.md` §3.1。

## 16. 四种 Windows 组合 —— 前置件与坑

检测器从不从 OS 标签推断能力:它结构化地读 build、防火墙状态与电源能力。证据等级刻意分开列。

| # | 客户端 → 服务端 | 客户端侧前置件 | 服务端侧前置件 | 预期会遇到的坑 / 差异 | 证据等级 |
|---|---|---|---|---|---|
| **A** | Win10 → Win11 | 装了 Tailscale 且已登录、MagicDNS 能解析、没有被代理劫持、由人完成首次 token 打开 | DSH 端口只监听 loopback、`serve --bg`、窄 ACL(只放 443)、`trustedHosts` 一行、电源策略 AC **和** DC | 唯一做过实时端到端跑的组合;Win11 **服务端**走 enum 源过 NIC profile 检查(pass,`confidence: high`),而 Win10 服务端回退到本地化文本(`degraded`,`confidence: low`) | 实时(客户端 + 服务端),2026-09-24 |
| **B** | Win11 → Win10 | 客户端清单相同;**没有可用的实时 Win11 客户端** | 服务端清单相同;服务端是 Windows 10 机器,所以随时可以重测 | Win10 服务端没有 `pwsh`、`PATH` 上也没有 `node`,所以 HTTPS 判定需要「用 Electron 当 Node」的探测;非提权时 `Get-NetConnectionProfile` 被拒 ⇒ NIC 归属走低置信度路径 | 服务端实时,客户端路径未实时 |
| **C** | Win10 → Win10 | 客户端清单相同 | 服务端清单相同 | 两端都带上面那些 Win10 限制;不要把 NIC 的低置信度结果读成「没有 profile」 | 服务端实时,客户端路径未实时 |
| **D** | Win11 → Win11 | 客户端清单相同 | 服务端清单相同 | **完全没有实时验证过**;Win11 服务端姿态由 `tests/fixtures/win11-server.json` 覆盖。「Win11 ⇒ modern standby ⇒ 链路会断」**不是**受支持的结论 —— 去读 `POWER_S0_CAPABILITY` 和 `powercfg /a` 的原始行 | 仅夹具 |

每一格的共同前置件:两台机器在同一个 tailnet 且登录同一个账号;DSH 端口保持**只监听 loopback**;`tailscale serve --bg` 让 tailnet 侧停在 443;ACL 只放行「客户端 → 服务端 `tcp:443`」;服务端补丁里带一个裸 `host[:port]` 的 `trustedHosts` 条目;客户端打开一次 token URL(那枚 30 天绝对过期 cookie、它的续期与锁死路径在 skill 的 `references/client-setup.md` §3);两端的浏览器都没有代理掉 tailnet。

## 17. 待办 —— 只能由人来做的事

下面每一条要么是**一条可直接粘贴的命令**,要么是**一个 UI 点击位置**。「机器为什么不能做」那一列就是自动化在此停下的理由;这些都不是疏漏。

| # | 事项 | 怎么做(一行) | 机器为什么做不了 |
|---|---|---|---|
| **17.1** | 把 skill 同步到**用户级**副本 —— **已经做过**(11/11 文件逐字节相同、逐文件 SHA256 已核对);仅在 skill 再次改动后才需要重跑 | 干跑:`powershell -NoProfile -ExecutionPolicy Bypass -File D:\DSH\.dsh\tools\sync-skill.ps1 -Check`,然后应用:`powershell -NoProfile -ExecutionPolicy Bypass -File D:\DSH\.dsh\tools\sync-skill.ps1` | 目标 `%USERPROFILE%\.dsh\skills\dsh-remote-tailnet` 在**代理的工作区沙箱之外**(工作区是仓库根);往那里写需要你的授权 |
| **17.2** | 激活插件面板(批准一次) | 打开标题为 **"AgentTeams automatic task assignment…"** 的那个会话的 Run/批准卡并点勾:**单击勾 = 只这一个包,双击勾 = 同一个插件以后的版本** | 批准是 Web UI 的用户动作,而那张被搁置的卡属于**另一个会话** —— 见下面的警告 |
| **17.3** | 持久化安装(可选) | 先跑只读预检(`powershell -NoProfile -ExecutionPolicy Bypass -File panel/plugin-preflight.ps1`),备份 profile patch(README §15.2,一个代码块),然后照 `docs/install/plugin-package.md` §5(三步)启用,回滚照 §6(四步:先 `disabled: true`,再整文件还原) | 它编辑的是**你自己的** DSH profile 文件,位于工作区之外且需要显式授权;而且这个包带着 `disabled: true` 发布,**从未在真实 DSH 里装载过**(§15) |
| **17.4** | 发布决策 | 本文件顶部的 clone URL 已经带上了账号(`KomeijiHonnouKai`),而且**仓库名已经定下来** —— 那个 URL 是唯一出处;改名仍是每个文件一行的编辑 | 命名、归属与身份是维护者的决定;**许可也已经定下来**(MIT,`Copyright (c) 2026 KomeijiHonnouKai`) |
| **17.5** | 重测实时链路 | `powershell -NoProfile -ExecutionPolicy Bypass -File .dsh/skills/dsh-remote-tailnet/scripts/verify.ps1 -ServerIp <PEER_IP>` → 期望 `443 connected` / `135, 5357 timeout` / **EXIT 0**;再做 `… -Soak -Count 11 -IntervalSeconds 30`,并**连窗口一起**说明结论 | 15 秒检查与 **11 轮 soak 现在都已经实测**(见本节压缩说明与英文原文 §18.1)—— 但链路观测是「每台机器、每种环境」的事,所以重置、换客户端或换 tailnet 之后,这就又是操作者自己该跑的一遍 |
| **17.6** | **卸载 / 清理(完整且干净)** | 先干跑:`powershell -NoProfile -ExecutionPolicy Bypass -File tools/uninstall.ps1 -Plan` —— 它只打印清单、**什么都不写**;只有当你想真的执行回滚时才加 `-Apply`(它在第一次改动**之前**就备份好一切)。完整流程:**下面的 §21**,以及 **`docs/install/uninstall.md`** 里的长版说明(随发布集发布)。 | 三件事决定它**不会**碰什么:(1) 它只回滚 **journal 记录过、且当前值仍等于本工具 remediation 应产生值**的项 —— 之后被别人改过的一律只报告、不触碰;(2) Tailscale 安装本身、其它 DSH 插件、以及**你自己写的任何防火墙规则**都**默认保留**;(3) 备份**默认保留**,只有显式 `-PurgeBackup` 才会清掉。所以「干净卸载」从来不等于「静默删掉一切」 |

> **本节的压缩说明**(与顶部完整度声明一致):17.1 / 17.5 里的逐次时间线、逐轮毫秒数、以及 skill 两个副本逐文件对比的过程在上述表格里压成了结论。被压掉的细节在英文原文 **`README.md` §17.1 / §17.5 / §18.1**;结论本身就是:用户级 skill 副本已同步且 11/11 文件逐字节相同;`verify.ps1` 的三态实测为 `443 connected` / `135 timeout` / `5357 timeout`(**EXIT 0**);短 soak 在 15 秒窗口里 3/3 connected;11 轮 soak 在 305 秒窗口(2026-09-24 18:33:16–18:38:18)里 **11/11 connected、failed=0**,结论行 `VERDICT 全通:窗口内全部 connected`,**EXIT 0**。这三条都属于**窗口有限的观测**,不等于「链路稳定」。§17.2 的实测失败文本与 §17.6 的口径是**逐字**保留的,没有压缩。

### 17.1 skill 副本 —— 以及此刻生效的是哪一份

`D:\DSH\.dsh\tools\sync-skill.ps1`(已交付;幂等、逐文件 SHA256 比较、按文件打印 `SAME`/`UPDATED`、从不删除、先复制再逐字节复核、输出纯 ASCII;退出 `0` 同步,`1` 源缺失,`2` 校验不一致)。

**运行时效果,精确地说**(skill 发现的排序:`project-dsh` 100 优于 `user-dsh` 400,先出现者胜):

- `cwd` 是仓库根的会话读**工作区副本**,所以那里的 skill 修订**今天**就是生效的。
- `cwd` 是**其它任何路径**的会话读**用户级副本**,而那份副本**已经同步过**:同步打印了 `updated=2`,随后打印 `verify OK: all files byte-identical`,即全部 **11 个文件逐字节相同** —— 包括本任务改过的那两个文件 `references/verify.md` 与 `references/troubleshooting.md`。所以两份副本**今天在哪儿都生效**。
- 这条命令是幂等的(逐文件 SHA256 比较、从不删除、先复制再逐字节复核),所以只在 skill 又被编辑之后才需要重跑。

### 17.2 ⚠️ 被搁置的那张批准卡会失败

`panel-2` / `pkg-5` 的那张批准卡(一次返回 `awaiting-approval` 的 run)待在一个**团队成员会话**里,不在你自己的交互会话里。按 §14.1 与那里引的实测失败文本,从一个 subagent 持有的会话激活带 client 半边的包,结局是 `host-half-failed: session/agent-busy: session "<SUBAGENT_SESSION_ID>" is owned by subagent routing` —— 再点一次只会为同样的结果再花掉一次批准。

- **如果你看的卡在那个成员会话里**:别点。改在一个普通交互会话里,用 `panel/host-half.js` + `panel/client-half.js` 定义**一个新**插件(新的 3–6 字母 idPrefix),批准那一个。
- **实测的正面路径**(2026-09-24,默认工作区会话):用 `panel/host-half.js` + `panel/client-half.js` 定义**新**包(`rtgpnl-3` / `pkg-6`),调 `cordis_run(pluginId="rtgpnl-3", packageId="pkg-6", mode="run")` 返回 `awaiting-approval`;点勾之后这次 run 完成状态是 **completed**(run 6),分区出现在设置导航里。同样的这次点击若发生在成员会话那张被搁置的卡上,结局是 `host-half-failed: session/agent-busy` —— 差别就这一处。
- **成功长这样**(两条路径都一样):没有 `Failed to load plugins` 横幅,设置导航里多出 **`Remote access link (read-only posture)`**,并且面板上的四态计数与 `powershell -NoProfile -ExecutionPolicy Bypass -File src/collect.ps1 -CheckOnly -AsJson` 一致。
- **失败时的回滚**:`cordis_stop("panel-2")` —— 或者 `cordis_stop("<你刚创建的那个 id>")`,例如上面那次实测的 `cordis_stop("rtgpnl-3")`。

### 17.3 持久化安装(可选)

备份用 README §15.2,那一行与开关用 §15.3,文件级还原用 `docs/install/rollback.md` §2。本修订版**没有执行过**这里面的任何一步。

### 17.4 发布到 GitHub 之前

许可已定(MIT,`Copyright (c) 2026 KomeijiHonnouKai` —— 已反映在 `LICENSE`、`README.md`、`CHANGELOG.md` 里)。**仓库名也已定**:就是本文件顶部 clone URL 里的那个(改名仍是每个文件一行的编辑)。**账号也已填好**(`KomeijiHonnouKai`,见 clone URL)。仍然属于你的事:在 GitHub 上创建那个仓库并做第一次 `git push`。按政策不附任何二进制。

### 17.5 链路重测 —— 对端掉线后又回来了

结论 = 三个窗口、三类证据,分开记:

| 窗口 | 结果 | 证据类别 |
|---|---|---|
| 17:36 | 链路可用:`verify.ps1` 实测对端 `:443` = **connected(860 ms)** | 引用自任务 t7 |
| 17:44 起 | 对端 `:443` 持续 **timeout** | 引用自任务 t9 简报 |
| 18:25 | 本任务自己的 `[Net.Sockets.TcpClient]` 探测(5 秒):对端 `:443` = **timeout** | 本任务实测 |
| **18:30** | **对端恢复应答**:`verify.ps1` → `443 connected 189 ms`、`135 timeout`、`5357 timeout`、`VERDICT 全通`,**EXIT 0** | 本任务实测 |
| **18:30:36–18:30:47** | 短 soak,**3/3 connected**,全部落在那个 **15 秒窗口**内 | 本任务实测 |

本地一侧全程健康(tailnet 地址在位、普通出网正常、DNS 能解析),所以 17:44–18:25 那段是对端侧或 tailnet 侧的状况,不是本地的。**11 轮 / 5 分钟 soak**(`-Soak -Count 11 -IntervalSeconds 30`)已跑过并通过:窗口 **2026-09-24 18:33:16–18:38:18(305 秒)**,`SOAK total=11 connected=11 failed=0`,十一轮全部 `connected`,结论行 `VERDICT 全通:窗口内全部 connected`,**EXIT 0**(原始运行见 §18.1)。请把它读成**「一个窗口内的观测」而不是「链路稳定」**:它对那 305 秒以外的任何一秒都没有说任何话;而且链路观测是「每台机器、每种环境」的事,所以重置、换客户端或换 tailnet 之后,这就又是操作者自己该跑的一遍。如果重跑全是 timeout,先**在两端**重启 `tailscaled`,再动任何策略。离线套件(§20)从不依赖对端。

浏览器侧的健全性检查(客户端机器上的一次人工动作):打开 `https://<HOST>.<TAILNET_DOMAIN>/?token=<token>` 并**由你自己**粘贴 token —— 本工具从不读取、打印或外传它;那一次访问之后浏览器就持有那枚长期 cookie(skill 的 `references/client-setup.md` §3 讲它的绝对过期、续期路径与锁死情形)。

## 18. 证据链:本任务实测、引用自其它任务、仍未验证

三类,从不混用。「实测」= 本任务跑了那条命令并看到输出;「引用」= 原样复用另一个任务的结果,强度不超过那个任务的证据;「未验证」= 还没有人测过。

### 18.1 本任务(t9)实测

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .github/scripts/repo-hygiene.ps1 -Json
# verdict: CLEAN (0 blocking finding(s))
# {"root":"…","files":85,"blockedHits":0,"credValueHits":0,"wordHits":194,"encodingFailures":0,
#  "lineEndingNotes":1,"binaryFailures":0,"forbiddenCode":0,"forbiddenDoc":2,"missingIgnores":0,
#  "missingMarkers":0,"unclassified":0,"blockingTotal":0,"verdict":"clean"}   exit 0

powershell -NoProfile -ExecutionPolicy Bypass -File .dsh/skills/dsh-remote-tailnet/scripts/verify.ps1 -ServerIp <PEER_IP>
# 443 -> connected (189ms)   135 -> timeout (5006ms)   5357 -> timeout (5005ms)
# VERDICT 全通:443 connected,其余 2 个口均 timeout(ACL 隔离成立)      EXIT 0

powershell -NoProfile -ExecutionPolicy Bypass -File .dsh/skills/dsh-remote-tailnet/scripts/verify.ps1 -ServerIp <PEER_IP> -Soak -Count 3 -IntervalSeconds 5
# 18:30:36 #1 connected 194ms / #2 203ms / #3 194ms  ->  SOAK total=3 connected=3 failed=0
# VERDICT 全通:窗口内全部 connected                                   EXIT 0

powershell -NoProfile -ExecutionPolicy Bypass -File .dsh/skills/dsh-remote-tailnet/scripts/verify.ps1 -ServerIp <PEER_IP> -Soak -Count 11 -IntervalSeconds 30
# 11 rounds, window 2026-09-24 18:33:16–18:38:18 (305 s)
# connected 190 / 197 / 188 / 199 / 186 / 199 / 185 / 191 / 189 / 194 / 186 ms
# SOAK total=11 connected=11 failed=0
# VERDICT 全通:窗口内全部 connected                                   EXIT 0

powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-fixtures.ps1
# ALL PASS: 7 cases, 0 failed assertions                              EXIT 0
```

- 对端探测,5 秒超时,`[Net.Sockets.TcpClient]`:**18:25 timeout**、**18:30 connected**(两次都引在 §17.5)。
- 11 轮 soak,在短 soak 之后跑:**11/11 connected、failed=0**,窗口 **305 秒**(18:33:16–18:38:18),各轮 190 / 197 / 188 / 199 / 186 / 199 / 185 / 191 / 189 / 194 / 186 ms,`VERDICT 全通:窗口内全部 connected`,**EXIT 0**。与上面那次 15 秒运行一样,按**窗口有限的观测**引用 —— 两者都没有说链路「稳定」。
- 检查项清单:`src/collect.ps1` 里 `New-Check` 出现 **25** 次(24 个检查项 + 一个后处理分支),`panel/prereq-manifest.json` 的 `items` = **13**。
- 发布集清单:门禁的默认根覆盖代码目录(`src/`、`i18n/`、`tests/`、`panel/`、`tools/`、`plugin/`)加上已发布的文档与根文件;它会打印实时文件数,所以这一行不冻结任何一个数字。`plugin/package.json` **存在**(那就是常驻插件包,§15);而仓库**根**没有 `package.json`(测试路径上没有任何东西需要它 —— 见 §19)。
- §17.1 用到的 skill 文件状态(两份副本逐文件比 SHA256:11 对 11 个文件,9 个相同,本任务改过的 `references/verify.md`、`references/troubleshooting.md` 不同 ⇒ 正好是同步命令要补的缺口)。
- §17 时代的编辑之后重新解析了 skill 脚本:`verify.ps1` 与 `server-setup.ps1` 都报 `errors=0`(`Parser::ParseFile`)。

### 18.2 引用(其它任务的命令与结果)

按来源任务归并(英文原文 §18.2 是逐行对照表,这里合并同类项,任务号一个不落):

| 来源任务 | 被引用的结论 |
|---|---|
| t7 | 客户端侧端到端判定 **pass**(17:36 对端 `:443` connected 860 ms,命令 `verify.ps1 -ServerIp <PEER_IP>`) |
| t8 | 安全评审结论是 **needs_revision**(不是通过),并带 findings 清单 |
| t16(10/10)、t19(5/5)、t17 复审 | 上述 findings 修完之后的逐条处置表与复审结果 |
| t23 | 离线套件全绿:**52 cases / 52 passed / 0 failed / 0 xfail held / 0 xpass / ALL PASS**,exit 0 —— 这是 `xfail` **和** `xpass` 同时为 0 的第一次运行;同时刷新了 `SERVE_PRESENT` 语义(证据只来自可读的 `serve status` proxy target,读不出 ⇒ unknown) |
| t12(+ t24 把 `panel/`、+ t39 把 `tools/` 加进发布集) | 发布集卫生:`verdict: CLEAN`、0 阻断;t23 的两个扫描范围也一致 —— 门禁范围之外的每一处真实命中都是允许清单里的替换值或有记录的夹具,且两份小结都没有冻结文件数 |
| t24 | `panel/` 属于已发布发布集;许可已定(README §8/§12、`.gitignore` 取消排除、门禁默认根) |
| t25 | `docs/collect.md` 的 `SERVE_PRESENT` 文案刷新归它(代码/判定语义已经是 t23 的) |

### 18.3 未验证 / 在这里无法测量

- **一个实时的 Windows 11 客户端** —— 没有这样的机器,所以组合 B 与 D 沿用 Win10 客户端的代码路径而没有实时跑(见 §16)。
- **Win11 → Win11 端到端** —— 只有夹具覆盖(`tests/fixtures/win11-server.json`)。
- **一块被归到 `Public` profile 的网卡** —— 只能从规则的 `Profiles` 字段推导;它在 Public 机器上的静默失败后果**没有**实测,所以绝不能被报成「已验证」。
- **服务端侧的 HTTPS/证书判定** —— 受限环境里 schannel 不可用,所以 HTTPS 判定只存在于能跑 OpenSSL 探测的地方。
- ~~**一次成功的动态包激活**~~ —— **已移出本清单**:2026-09-24 在一个普通工作区级会话里实测(`rtgpnl-3` / `pkg-6` → `awaiting-approval` → 点勾 → run **completed**,面板出现在设置导航里;§14.1 与 §17.2 把这条正面路径与被实测的成员会话失败并排放在一起)。仍然未验证的只是它在**别的机器上**的失败形态。
- **常驻插件包** —— 已随 `plugin/` 发布,挂载行是 `disabled: true`,而且从未在真机上启用过(§15;未执行的清单见 `docs/install/plugin-package.md` §9)。

### 18.4 连通性:那次对端掉线影响了什么、没影响什么

17:44 到约 18:30 之间对端不可达,所以那个窗口里两项「双机」检查没法重测。**没有任何一项因此被判失败,也没有任何一项被糊过去**:对端不在时,离线那一层(拿夹具跑的 24 项采集器、13 项前置件检查器、`run-fixtures` 套件、卫生门禁)仍然完全可测 —— 这正是离线接缝的意义 —— 两项双机检查被如实记为 `timeout`,而不是记成某个判定。18:30 对端恢复应答,三态与一次短 soak 被直接实测(§18.1)。仍然开着的是:本机之外的机器上的客户端侧 MagicDNS/HTTPS 两项(§17.5、§18.3)。11 轮 soak 现在**不在**这个清单里了 —— 它已实测(§18.1)—— 但链路观测属于它被测的那台机器与那个环境,所以重置、换客户端或换 tailnet 都意味着操作者要重跑一遍(§17.5)。

## 19. 未决项与刻意的决定(请不要顺手「修」)

> **本节的压缩说明**:英文原文 §19.1 的七条判断在这里压成「一条一行」,判断本身、命令、路径与文件锚点全部保留;§19.2 的表(含「已关闭」注记)逐行保留。逐字的英文原文见 **`README.md` §19**。

### 19.1 夹具与运行时决定

- **以太网接口的默认网关落在它自己的 `10.20.0.0/16` 前缀之外。** 这是**忠实于原始抓包**(一种 VPN/点对点形态),刻意不平滑:不要去「修正」它。而 VPN 适配器自己的前缀、掩码与网关被收敛进了 RFC 5737 文档段(`198.51.100.11` 配一个匹配的 `/24` 前缀与网关),这样夹具里没有任何东西看起来像一台真机。
- **产品常量是刻意保留的**:`0.0.0.0`、`127.0.0.1`、`100.64.0.0/10`、Tailscale 的 IPv6 `/48` 产品前缀、各个掩码,以及 `192.0.2.20`。
- **净化替换值**(永远不要换成「看起来是真的」的值):本机侧 `100.64.0.11`,对端侧 `100.64.0.12`,私网段 `10.20.x` / `10.21.x` / `10.22.x`,主机替换值如 `<HOST_A>` / `<HOST_B>`。
- **发布集 vs 内部材料**:研究笔记、评审报告与验证记录由 **`.gitignore` 排除**、不发布 —— 那份文件的第 1 节是权威清单,排除清单不完整时卫生门禁会失败。(本文件刻意不重复它们的名字:把名字写在这里,正是「深链内部材料」的样子。)
- **已批准的面板包不是当前的仓库源码。** `panel-2` / `pkg-5` 是从 t6 修订版定义的,**不包含**后来加进 `panel/host-half.js` 的夹具路径允许清单。差别只限于那个可选的 `fixture` 调试参数 —— 正常路径完全一样。如果你要求「已批准 == 仓库源码」,就用 `cordis_define(kind=existing, pluginId="panel-2")` 重新定义并运行一个新包(会弹出一张新的批准卡)。
- **动态包没有持久生命**:`guard-1` 与 `panel-2` 属于定义它们的那个会话,不落盘,进程或会话消失它们就消失。面板对缺失的 `guard-1` 有一个兜底(它自己跑采集器,`source=direct`),而 `source=direct` **不是**故障。想继续用共享 Service,就重新定义并运行一次(`docs/install/install.md` §1)。
- **已知的框架缺陷(不要因此重做工作)**:当交付物位于 `.dsh/` 下时,AgentTeams 的 `changedPaths` 校验器会硬性排除它(`quality-gates.js:114-134`)。这就是任务 t4 只能以失败收尾、t18 不得不按 work-kind 任务关闭的原因;实测记录(含 BOM 丢失与对端不可达的时间线)在 `.dsh/notes/agentteams-changedpaths-dsh-exclusion.md`。

### 19.2 已跟踪但尚未关闭(归别人所有 —— 不算在本项目头上)

| 事项 | 归属 | 状态 |
|---|---|---|
| `docs/collect.md` 的 `SERVE_PRESENT` 文案刷新 | t25 | 代码/判定语义已经是 t23 的(见 §13.1 第 17 行);文档文本尚未刷新 |
| clone URL 里的 GitHub 账号 —— **已关闭** | 维护者 | 已完成:本文件顶部的 clone URL 带上了账号(`KomeijiHonnouKai`);剩下的是创建 GitHub 仓库与第一次 push(§17.4) |
| 两份卫生小结的文件数口径(本文件的默认根 vs t23 的扫描范围) | t24/t39 | 差别就在默认根范围(`panel/`,之后是 `tools/`、`plugin/`);两份都报 **0** 条非允许清单命中,且都没有冻结文件数 |
| 「设置 → 插件」页里的插件卡片座位(`settings.plugin.item`) | — | **本修订版没有实现**:这个包注册的座位只有设置页分区(见〈插件界面(GUI)〉一节);加卡片是另一件独立工作 |

**自本表初稿以来已关闭的项:** 过去出现在 §1/§5、`CONTRIBUTING.md` 与 `CHANGELOG.md` 里的过期用例数已刷新(t24 管 `CONTRIBUTING.md`,t28 管另外三处)。发布集里已经没有任何地方再引用一个冻结的通过数 —— 套件自己打印表头,而它的用例数就是 `tests/cases/` 下的目录数(2026-09-24 为 64,持有的 `xfail` 为 0)。请跑 §20 的命令并读表头,而不是读这一行。

## 20. 交付清单与陌生人需要的三条命令

| 项 | 路径 | 状态 |
|---|---|---|
| 离线回归入口 | `tests/run-tests.ps1`(64 用例) | 在位 |
| 离线夹具入口(确定性、无探测) | `tests/run-fixtures.ps1`(7 用例) | 在位,`ALL PASS / 0 failed / exit 0` |
| 离线冒烟入口(一条命令、一个退出码) | `tests/run-smoke.ps1` | 在位;退出 `0` 全绿、`1` degraded(有 SKIP 但无 FAIL)、`2` 坏了 |
| 采集器 | `src/collect.ps1`(24 项) | 在位 |
| 前置件检查器 + 清单 | `panel/prereq.ps1`、`panel/prereq-manifest.json`(13 项) | 在位 |
| 插件两个半边 | `src/host-half.js`、`panel/host-half.js`、`panel/client-half.js` | 在位 |
| 常驻插件包 | `plugin/package.json`、`plugin/cordis.patch.yml`、`plugin/lib/index.js`、`plugin/lib/client.js`、`plugin/lib/client/index.js` | 在位、随发布集发布;挂载行是 `disabled: true`,所以启用之前它是惰性的(§15) |
| 常驻包只读预检(0/1/2) | `panel/plugin-preflight.ps1` | 在位;实测 `checks: 51  passed: 51  failed: 0  skipped: 3`,exit 0 |
| 常驻包说明(启用 / 验证 / 回滚) | `docs/install/plugin-package.md` | 在位、随发布集发布 |
| CI | `.github/workflows/ci.yml` + `.github/scripts/repo-hygiene.ps1` + `.github/scripts/check-workflows.py` | 在位 |
| `LICENSE` / `README.md` / `README.zh-CN.md` / `SECURITY.md` / `CHANGELOG.md` / `CONTRIBUTING.md` | 仓库根 | 在位 |
| `.gitignore` / `.editorconfig` | 仓库根 | 在位 |
| 卸载器(唯一的可选写入组件) | `tools/uninstall.ps1` | 在位;默认干跑、必须 `-Apply`、第一次改动前先备份(§21) |
| 仓库根 `package.json` | — | **刻意缺失**(测试路径上没有任何东西需要它;常驻包自带 `plugin/package.json`) |

克隆 → 自证,三条命令:

```powershell
# 1) 确定性、离线、完全不做机器探测 —— 期望:ALL PASS: 7 cases, 0 failed assertions
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-fixtures.ps1

# 2) 完整的离线套件 —— 期望:64 cases, 64 passed, 0 failed, 0 xfail held, 0 xpass (exit 0)
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-tests.ps1

# 3) 发布集门禁 —— 期望:verdict: CLEAN (0 blocking finding(s)), unclassified=0 (exit 0)
powershell -NoProfile -ExecutionPolicy Bypass -File .github/scripts/repo-hygiene.ps1 -Json
```

然后,在一台你想真看的机器上(只读,哪儿都不写):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File src/collect.ps1 -CheckOnly
```

请把它的退出码读成**fail-closed 的判定**,不是命令失败:`0` 全部被证明,`1` 至少一项 degraded/unknown,`2` 至少一项 blocked(或采集器根本跑不起来)。本仓库里没有任何东西需要 token、cookie 或任何形式的凭据才能运行。

---

## 21. 卸载与残留 —— 完整、干净,且从不静默

`tools/uninstall.ps1` 是本仓库**唯一的可选写入组件**。它默认关闭:不带 `-Apply` 时它只观察、只打印,而且在第一次改动**之前**(而不是之后)写出备份。长版说明:[`docs/install/uninstall.md`](docs/install/uninstall.md) —— 同样的六个步骤,外加每一步该期待看到的观察结果。

### 21.1 六个步骤(第 1、3、4 步什么都不写)

| 步骤 | 命令 | 做什么 |
|---|---|---|
| 1. RecordBefore | `tools/uninstall.ps1 -RecordBefore` | 把这条链路的各个面(防火墙规则、`tailscale serve`、电源设置、DSH profile 行、插件行)快照进 journal |
| 2. remediation | *(你的命令,来自采集器的输出)* | 真正的修复由**你**执行;本工具从不替你执行修复 |
| 3. RecordAfter | `tools/uninstall.ps1 -RecordAfter` | 重新读同一批面,这样之后的回滚能分清「我们改的」与「本来就那样」 |
| 4. Plan | `tools/uninstall.ps1 -Plan` | 给每一条记录分类(见下表)并且什么都不写 |
| 5. Apply | `tools/uninstall.ps1 -Apply` | 写完备份之后,**只**执行 `revert` 那些行;`-RemoveFiles` 把它扩展到它自己写过的文件 |
| 6. residue + backups | `tools/uninstall.ps1 -CheckOnly` | 报告留下了什么、备份目录里还有什么;备份会一直留到 `-PurgeBackup` |

### 21.2 四种分类

| 分类 | 含义 | `-Apply` 会碰它吗? |
|---|---|---|
| `noop` | 那个面看起来已经是本工具 remediation 会留下的样子,而且 journal 记录过那次改动 | 无事可做 |
| `revert` | journal 记录过这次改动,**且**当前值仍恰好等于本工具 remediation 产生的结果 | **会** —— 被回滚,之前先写备份 |
| `left-alone` | journal 记录过一次改动,但当前值**不是**本工具产生的(后来有人编辑过) | **不会** —— 只报告,绝不覆盖 |
| `unknown` | 没有 journal 记录,或那个面读不出来(被拒、不可用、豁免) | **不会** —— 报成 `unknown`,而这正是退出码存在的意义 |

### 21.3 退出码

| 退出 | 含义 |
|---|---|
| `0` | 干净:没有东西需要回滚,也没有无法归属的东西 |
| `1` | fail-closed:有东西是 `left-alone`、`unknown` 或无法归属 —— 读报告并人工决定(一台没有 journal 的机器会回答 `attribution=unavailable`,绝不是绿灯) |
| `2` | 拒绝:参数非法、路径在已核实目录之外,或没有 `-Apply` 就用了 `-PurgeBackup` |

### 21.4 哪些东西保持不动,以及承诺边界

- **默认保留**:Tailscale 安装本身、其它 DSH 插件及其配置、以及**你自己写的每一条**防火墙规则。`-KeepTailscale` 只在计划内部表达这个意图;它的任何取值都不会卸载 Tailscale。
- **备份默认保留**在备份目录里,直到 `-PurgeBackup` 另有指示。
- **承诺边界**:采集器(`src/collect.ps1`)与前置件检查器(`panel/prereq.ps1`)仍然是**零写入路径** —— 它们只检测、只报告。`tools/uninstall.ps1` 是本仓库**唯一的可选写入**组件:默认干跑、必须 `-Apply`、第一次改动前先备份,而且每一条被回滚的项都能追溯到一条 journal 记录。
- 这个组件有两条有记录的局限(保留而不隐藏):它的系统级回滚命令与两处进程内文件编辑只做过**静态与分支**验证,**没有**在真机上执行过 —— 执行它们会改变本机的防火墙、电源设置、`tailscale serve` 状态与 DSH home 下的真实文件;而回滚的好坏只取决于它的 journal,所以「没有 journal」就意味着 `unknown` 加退出 `1`。

