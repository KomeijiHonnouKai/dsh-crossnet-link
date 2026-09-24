# remote-tailnet-guard

**目的**：在 A 电脑的 DSH 里，通过浏览器插件驱动已登录的通道页面，
直接操作 B 电脑上运行的 DSH，两台 DSH 由此联动（agent 对 agent）。

**本仓库的角色**：只读体检、前置件检查、只读面板、完整卸载。
它只读、只报，不装任何东西，不改任何配置，不转发流量。
打通链路本身，看 skill `dsh-remote-tailnet`；本仓库不负责打通。

[English](README.en.md) · MIT

> 发布集门禁逐字检查下面的英文标记，请勿改动。
> Internal analysis and review material does not ship with the repository。
> 内部评审材料不随仓库发布。安全策略入口是 `SECURITY.md`；许可为 MIT。
> The plugin is read-only and report-only。插件只读、只报。

## 1　这是什么

四件交付物，共用一个检测内核：

| 交付物 | 入口 | 作用 |
| --- | --- | --- |
| 采集器 | `src/collect.ps1` | 检查链路姿态，四态判定，退出码 0/1/2 |
| 前置件检查器 | `panel/prereq.ps1` | 面向安装计划，只打印安装命令 |
| 插件(host 与面板) | `src/host-half.js` 等 | 只读面板，注册进设置页 |
| 卸载器 | `tools/uninstall.ps1` | 默认干跑，可完整干净回滚 |

兼容：Windows 10 或 11，Windows PowerShell 5.1。不需要 Node、Pester 或任何模块。
验证等级分三种，从不混用：实时端到端实测、离线夹具、静态预检。
哪些还没验证，见《6　已知局限》。

**术语速查**
- tailnet：Tailscale 私有网络。
- serve：`tailscale serve` 把 loopback 端口发布到 tailnet。
- ACL：tailnet 的访问策略。
- 夹具：注入的探测数据，让测试离线可跑。
- journal：卸载器记下的改动台账。
- remediation：工具给出的修复动作。
- profile：DSH 的配置集，补丁写在这里。
- 插件行：`cordis.patch.yml` 里的一行挂载配置。

## 2　快速开始

四条命令，全部只读，不用安装任何东西。

1. 克隆仓库。第二个参数是本地目录名，不能省。

```powershell
git clone https://github.com/KomeijiHonnouKai/dsh-crossnet-link remote-tailnet-plugin
cd remote-tailnet-plugin
```

期望：克隆成功，进入目录。

2. 离线冒烟，一条命令自证。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-smoke.ps1
```

期望：退出 0 全绿；1 表示有跳过但无失败，是干净机器上的正常结果；2 有失败。

3. 看本机姿态，只读。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File src\collect.ps1 -CheckOnly
```

期望：表头 total=26。没有对端地址时链路几项报 unknown；
本机 trustedHosts 未配置会报 blocked。
退出 0 全通、1 有降级、2 有阻断。
新机器上退出 2 很常见，这是 fail-closed 判定，不是命令失败。

4. 卸载前的干跑，不写任何东西。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\uninstall.ps1 -Plan
```

期望：新克隆上会拒绝并报 journal_required，退出 2，这是设计不是出错。
完整流程见 `docs/install/uninstall.md`。

## 3　判定怎么读

每个检查项落到四个判定之一：

| 判定 | 含义 |
| --- | --- |
| `pass` | 该项被证明成立 |
| `degraded` | 部分成立，或证据走弱路径 |
| `blocked` | 被违反，或采集器跑不起来 |
| `unknown` | 没有探测能回答，绝不通过 |

判定是 fail-closed：不确定绝不当通过。严格模式下 unknown 抬升为退出码 2。
退出码：

| 退出码 | 含义 |
| --- | --- |
| `0` | 每项都通过 |
| `1` | 至少一项降级或未知 |
| `2` | 至少一项阻断，或无法运行 |

一律用 `-File` 调用这些脚本。它们用 exit N 设退出码，只有 `-File` 保留它；
`-Command` 与点源会把退出码 2 改写成 1，把真正的阻断藏起来。

## 4　都检查什么

采集器按六组展开：主机、链路、暴露面、Tailscale、Windows 电源与防火墙、自审计。
前置件检查器面向安装计划，逐项带角色与回滚。
完整判据见 `docs/collect.md` 与 `docs/install/prerequisites.md`。
每一项的权威措辞住在 `i18n/labels.zh.json` 与 `i18n/labels.en.json`；
每个故障的期望判定住在 `tests/cases/` 下的用例里。

## 5　安装、启用与移除

形态 1，默认：动态 Cordis 包，只活在进程内存，重启即消失，所以无需卸载。
入口是 `src/host-half.js`、`panel/host-half.js` 与 `panel/client-half.js`；
步骤见 `docs/install/install.md`。

形态 2：常驻插件包 `plugin/`。装它会写进你自己的 DSH profile，所以项目只写文档、从不代装。
唯一那一行挂载配置默认 `disabled: true`，装上弄不坏任何东西。「安装」＝三条可粘贴命令，
把启用一起做完：备份 profile 补丁 → `dsh plugin add link:` → 追加启用覆盖行；
跑完重启 DSH，设置 → 插件里即显示已启用。
装前先跑只读预检 `panel/plugin-preflight.ps1`；
三步与回滚见 `docs/install/plugin-package.md`；
给 AI 读的带人话版本见 `docs/install/agent-brief.md`。

- 插件清单里出现那一行：装进了 profile，禁用状态也在。
- 出现插件卡片（「可配置插件」标签页里一张折叠卡片「跨网链路姿态」）：
  host 侧代码注册了卡片所依赖的设置命名空间。
- 卡片是有条件的：profile 能解析到 schema 库就出现（实测本机出现）；
  解析不到只打 warning，清单行不受影响。
- 本插件只以这张标准卡片出现，不新增侧边栏/设置导航条目。

移除三步：把那一行改回 `disabled: true`，或删掉它，或用改动前的备份整文件还原。
先读备份再还原，备份可能是一份空补丁。长版见 `docs/install/uninstall.md`。

## 6　已知局限

| 未验证项 | 覆盖现状 |
| --- | --- |
| Win11 客户端实时链路 | 只有夹具与 Win10 路径 |
| Win11 对 Win11 端到端 | 仅夹具覆盖 |
| Public 网卡的静默后果 | 只能从规则推导 |
| 服务端 HTTPS 证书判定 | 依赖 Node 或 OpenSSL 探测 |
| 常驻包真机装载 | 真实 DSH 上装载一次（2026-09-25，两格全中，日志 info） |
| 面板卡片渲染 | 实测渲染前提成立（命名空间注册成功、卡片座位 active） |

以上条目都按未验证如实报告，绝不升级成已验证。

## 7　常见问题

**Q1** 为什么退出码是 2，还有一堆 unknown？
没有对端地址时链路项无法探测，沙箱窗口里 Tailscale CLI 也会被拒，这些都如实报 unknown。
trustedHosts 未配置会报 blocked。退出 2 是 fail-closed 的判定，不是命令失败。

**Q2** 为什么必须用 `-File` 调用？
脚本用 exit N 设退出码，只有 `-File` 保留它。`-Command` 与点源把退出码 2 改写成 1，
会掩盖真正的阻断。

**Q3** 脚本说通，浏览器却打不开？
TCP 通不等于 TLS 与 HTTP 通。最常见是系统代理劫持了 tailnet，
看采集器输出里的 `BROWSER_PROXY_TSNET`；
也可能是 cookie 过期被 401 拦，或服务端 trustedHosts 缺失被 403 拦。

**Q4** 两台机器的代理开与关，四种组合怎么判？
每一端只看自己一侧的代理姿态，从不猜对端。客户端看 `BROWSER_PROXY_TSNET`，
服务端看 `SERVER_PROXY_STATE` 与 `TAILNET_ROUTE_PRESENT`；
过程与修法见 `docs/install/prerequisites.md`。

**Q5** 纯客户端机器上前置件检查器非零退出正常吗？
正常。默认角色查两端，客户端机器必然缺服务端项。加 `-Role client` 只看这一侧。

**Q6** 卸载会不会删掉 Tailscale 和我的防火墙规则？
不会。它只回滚 journal 记录过、且当前值仍等于它自己产生的项。
Tailscale 本体、其它插件、你自己的规则默认保留，它没有卸载 Tailscale 的代码路径。

**Q7** 设置 → 插件里没有这张卡片？
形态 1 只活在进程内存，重启就消失，重新定义再运行即可。
形态 2 按三步启用并重启 DSH 才生效；卡片条件见上面清单。
失败形态见 `docs/install/plugin-package.md`。
以上都不匹配时，跑 `tests\run-smoke.ps1` 拿第一手证据，再按退出码读。

## 8　安全与隐私

- **P1** 不新增监听、路由、防火墙规则。
- **P2** 默认只读，唯一的写入组件是卸载器，且默认干跑。
- **P3** 不做自动写入，`-Apply` 被拒绝。
- **P4** 不读、不打印、不存储、不外传凭据。
- **P5** 无遥测、无回调、无自动更新。
- **P6** 无重启逻辑，不杀也不拉起 DSH host。
- **P7** 每个副作用挂在 ctx.effect 上，可完整移除。
- **P8** 面板是只读展示，没有写入按钮。

威胁模型两条结论，见 `docs/threat-model.md`：谁能打开那个 UI，谁就能操作那台机器；
loopback 按设计可信，本工具不改变也不扩大它。

安装包哈希策略：不预置厂商哈希，验证 Authenticode 签名，
可选由你自己算好填进 `panel/prereq-manifest.json` 的 `pinnedSha256`。
没钉之前如实报 blocked，检查器从不下载或运行任何东西。

## 9　文档索引

- `docs/collect.md` 采集器判据与实现说明。
- `docs/install/prerequisites.md` 前置件与代理四组合。
- `docs/install/install.md` 形态 1 动态包步骤。
- `docs/install/plugin-package.md` 形态 2 三步启用、验证、回滚。
- `docs/install/agent-brief.md` 给 AI 读的安装流程，含对话输出模板。
- `docs/install/uninstall.md` 卸载六步长版。
- `docs/install/rollback.md` 每类改动的回滚。
- `docs/threat-model.md` 谁能看到什么、能做什么。
- `docs/evidence.md` 证据链台账，实测、引用、未验证三分。
- `docs/decisions.md` 未决项与刻意的决定。
- `SECURITY.md` 安全承诺与逐条复核命令。

## 10　许可与贡献

许可：**MIT**。`LICENSE` 载有完整文本与版权行。
贡献前先读 `CONTRIBUTING.md`；安全问题走 `SECURITY.md`，不要开公开 issue。
