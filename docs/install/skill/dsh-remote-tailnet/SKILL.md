---
name: dsh-remote-tailnet
description: 把两台位于不同网络的电脑上的 DSH 连起来,让本机浏览器直接操作另一台的 DSH 界面。做法:装 Tailscale → 服务端 tailscale serve --bg 把本机 DSH 的 loopback 端口暴露到 tailnet → 窄 ACL 只放「客户端 → 服务端 tcp:443」→ 客户端浏览器带 token 打开一次换 30 天 cookie。含环境配置、软件安装、验收(三态 + soak)、安全威胁模型与预防、故障速查与幂等脚本。适用于「两台机器不在同一网络,其中一台需要被另一台的 DSH 远程操作」。**本文只写这一条已实测跑通的路径**,不做方案选型、不列其他做法。
---

# dsh-remote-tailnet —— 跨网远程控制另一台 DSH

> 最后更新:2026-09-26。本次补的是「插件前置关系 + 浏览器操控对端 + 服务端 ACL/电源的可粘贴命令」;W4/t18 的历史修订见 `README.md` 的「本次修订」,**本次改动不在 README 里**(README 只讲插件本身)。

## 前置:插件是「体检」,打通是「接线」 —— 先装插件,再打通

**先 clone 插件仓库 `dsh-crossnet-link` 并装好插件(见仓库 README),再照本文做打通。** 两件事的分工:

| | 归谁讲 | 覆盖内容 |
| --- | --- | --- |
| **插件侧** | **仓库 README** | clone → 装包(`link:` 形态)→ 启用(改的是 profile 的 `cordis.patch.yml`)→ 体检/面板 → 卸载 |
| **打通侧** | **本文 + `references/`** | 两端 Tailscale → 服务端 `serve --bg` → `trustedHosts` → 重启 → ACL → 电源 → 客户端带 token 换 cookie → 验收 → 浏览器操控 |

- 插件是**只读体检工具**,与能不能打通**没有依赖关系**(打通只用 Tailscale;不装任何 DSH 插件也能成);
- 但**推荐先装**:它会把端口、防火墙、代理、电源这类打通障碍一次性摆出来,省掉来回猜;
- 「装完显示未启用」是**插件的坑,读仓库 README**;打通过程中的坑看本文与 `references/troubleshooting.md`。

## 何时用

- 两台机器**不在同一网络**(如 A 在校园宽带、B 在手机热点),需要从 A 的 DSH/浏览器操作 B 的 DSH。
- 不想引入任何第三方中转插件、不想让服务端 DSH 监听 0.0.0.0。

## 适用边界(只覆盖这一条已跑通的路径)

- 全文只描述**实测打通的那一条链路**:Tailscale(两端同一 tailnet)+ 服务端 `tailscale serve --bg` 把 DSH 的 loopback 端口暴露到 tailnet + 窄 ACL 只放「客户端 → 服务端 tcp:443」+ 客户端浏览器带 token 打开一次换 30 天 cookie。**不写、也不讨论其他实现方式**。
- 服务端拿不到一次管理员 → 走不通(装 Tailscale MSI 必须提权一次)。
- 服务端不允许安装 Tailscale 客户端 → 走不通。

## 前置条件(硬性)

| 项 | 要求 |
| --- | --- |
| 客户端 | 能装 Tailscale(需一次 UAC)、能让浏览器打开外部地址 |
| 服务端 | Windows,tailscale 客户端可装(一次 UAC);DSH Desktop 桌面外壳模式 = **兼容模式**;`openBrowser` = true |
| 账号 | 两台登录**同一个 Tailscale 账号**(同一 tailnet) |
| 权限 | 服务端 DSH 的默认权限模式建议 **workspace-write**(不是 danger-full-access) |

## ⚠️ 跑脚本前:本机默认 ExecutionPolicy = Restricted

裸 `.\verify.ps1` / `.\server-setup.ps1` 会被拒(实测原文:`cannot be loaded because running scripts is disabled on this system`,PSSecurityException / UnauthorizedAccess)。一律用下面这种**不改任何机器策略、只对子进程生效**的形态:

    powershell -NoProfile -ExecutionPolicy Bypass -File .dsh/skills/dsh-remote-tailnet/scripts/verify.ps1 -ServerIp <对端 100.x>
    powershell -NoProfile -ExecutionPolicy Bypass -File .dsh/skills/dsh-remote-tailnet/scripts/server-setup.ps1 -CheckOnly

> 两个脚本都**只读**:`server-setup.ps1` 只检查 + 打印要人执行的命令(不下载、不装、不跑 serve、不写 profile);`verify.ps1` 只出网探测。细节见 [references/automation.md](references/automation.md)。

## 快速路径(10 步)

1. 服务端:装 Tailscale([references/server-setup.md](references/server-setup.md) §1)、登录同一账号(§2),记下 `tailscale ip -4`。
2. 客户端:装 Tailscale 并登录同一账号([references/client-setup.md](references/client-setup.md) §1),记下自己的 `100.x`。
3. 服务端:确认 DSH Web 端口(默认 **43120**,`dsh-desktop.port`)与 `127.0.0.1:<port>` 在监听([references/server-setup.md](references/server-setup.md) §3)。
4. 服务端:`tailscale serve --bg 43120`(`--bg` 必须有,否则重启失效),`tailscale serve status` 记下 `https://<机器名>.<tailnet>.ts.net/`([references/server-setup.md](references/server-setup.md) §4)。
5. 服务端:profile 补丁追加 `connection.trustedHosts` —— **规范写法 `['<那个 ts.net 域名>', ...ctx.webRuntime.trustedHosts]`**(patch 是**整行 config 覆盖**语义,只写字面量会静默丢掉派生字面量;**entry 必须是裸 `host[:port]`,否则装载时直接抛错**)。**不加这行,远端 Web 的 `/api` 会 403**(目录选择器报错、客户端反复「自动重连中」)。命令见 [references/server-setup.md](references/server-setup.md) §5,写法依据见 [references/security.md](references/security.md) §6。
6. 服务端:重启 DSH(用自带入口 设置 → 桌面 → 重启)。**不要装第三方重启插件**([references/server-setup.md](references/server-setup.md) §5 末)。
7. tailnet 控制台:policy 收紧为单向 `{"acls":[{"action":"accept","src":["<客户端 100.x/32>"],"dst":["<服务端 100.x/32:443>"]}]}`;设备列表只保留这两台;账号开二次验证(MFA 要在身份提供方 IdP 侧开)。可整段粘贴的 policy 与副作用见 [references/server-setup.md](references/server-setup.md) §7。
8. 服务端:电源策略设为**不休眠/不合盖睡眠**(笔记本会因此整条断链);AC 与 DC 都要查。可粘贴命令与核验见 [references/server-setup.md](references/server-setup.md) §8。
9. 客户端:浏览器打开 `https://<ts.net 域名>/?token=<服务端 DSH 的 launch token>` **一次**,换 30 天 cookie。token 从服务端 DSH 设置页的「浏览器访问地址」里取(见 [references/client-setup.md](references/client-setup.md) §2);**30 天绝对期限与到期死路见 §3**。
10. 验收:三态探测 + soak(见 [references/verify.md](references/verify.md) §1/§3/§4,清单 §6);之后直接用 `https://<ts.net 域名>/` 打开。

    验收命令(默认策略下可直接跑通):

    powershell -NoProfile -ExecutionPolicy Bypass -File .dsh/skills/dsh-remote-tailnet/scripts/verify.ps1 -ServerIp <服务端 100.x>

    退出码:**0 = 全通**(443 connected 且隔离口 timeout)/ **1 = 降级**(隔离失效)/ **2 = 阻断**(443 不通)。

## 打通之后:浏览器操控对端(两套工具)

链路通 ≠ 能干活 —— 「打开之后怎么操作对端」单独一篇:**[references/browser-control.md](references/browser-control.md)**(选型、坑表、可粘贴命令原文都在那里)。这里只给索引:

| | `browser_*`(DSH 内置浏览器桥) | `ego_*`(ego-browser 插件,自管便携 Chromium) |
| --- | --- | --- |
| 定位 | **跨网操控对端的首选**:`browser_list_tabs` → `browser_follow_tab` → `browser_snapshot` → `browser_type` / `browser_click`;本次跨网实测全程无超时 | **只做轻量查询**(`ego_status` / `ego_doctor` / `ego_page_info`);`ego_script` / `ego_navigate` 这类重操作别用 |
| 上限 | 文档默认 `toolTimeoutMs = 90000 ms`、`snapshotMaxChars = 32000` | 单次 tool call 默认 **120 s**(`ego_status` / `ego_doctor` 25 s);且**全部 `ego_*` 串行**(进程内互斥锁,并发调用会排队) |
| 超时后 | 重新 `browser_snapshot` 取新索引再试 | **不要重试**(只会再烧一个 120 s 上限),直接换 `browser_*` |

> ⚠️ 「`ego_*` 一直 120 s 超时、用不了」是**过期结论**。真实约束 = 默认 120 s 上限 + 全串行 ⇒ 轻量查询够用,重操作归 `browser_*`。口径来源与证据等级见 [references/browser-control.md](references/browser-control.md) §0。

两条铁则(踩了就是白跑一轮):

1. **写入只能走 composer**:`browser_snapshot` 找 composer 的 `textbox` → `browser_type` 写入(**剪贴板粘贴进不去,只能 type**)→ 点 `button "发送消息"`(**按钮变成 `停止生成` = 已发出**;回到 `发送消息` = 对端那一轮跑完)。对端按 token 计费,**没有实质内容就别发消息**。
2. **读取只能走「下载 Session 日志」**:页面文本(`browser_get_text` / snapshot)只回**前 ~8.4 KB**,长会话的最新回复必然落在截断之外 ⇒ 对端会话页 →「更多操作」→ **下载 Session 日志** → 解出 `session.v3.jsonl`(**别用 `Expand-Archive`**,zip 里有名字带冒号的条目)。可粘贴的整段命令原文见 [references/browser-control.md](references/browser-control.md) §3.1。

> 动手前先过 [references/browser-control.md](references/browser-control.md) §1 的两条前置检查:受控 tab 是不是对端那个地址、桥有没有 Chrome 扩展连着 —— 没有活动扩展时所有 `browser_*` 会直接失败(实测原文 `no browser extension is connected to the bridge`)。

## 必读:安全底线(细节见 [references/security.md](references/security.md))

1. **能打开服务端 DSH 界面 = 能以该 DSH 的权限操作那台机器**;所以服务端默认权限模式必须是 workspace-write,不能是 danger-full-access。
2. tailnet 里**只放需要的设备**;ACL 用 IP 级单向 443;账号开二次验证(默认 ACL 是全通)。
3. 带 token 的 URL 是凭据:**不进入任何对话、日志、聊天、工单**;只由用户在自己机器的地址栏粘贴一次。
4. **30 天 cookie 是绝对期限,不因使用而续期**(cookie 只在带 token 那一次签发,之后只校验、从不重签);**到期前**可以从仍有效的会话里重取当前 launch token 再换一次;**到期且服务端重启过**(launch token 每进程随机、重启即换)时,远端只剩死路 —— 必须到**服务端机器前**用 loopback 页面取新 token。撤销/续期的精确落点与源码行号见 [references/client-setup.md](references/client-setup.md) §3 与 [references/security.md](references/security.md) §4。
5. 不要开 `networkExposure: lan`(本方案不需要);serve 只绑 `100.x` 与 tailscaled,不新增 `0.0.0.0` 监听。
6. 服务端本机既有暴露面(SMB 139/445、既有的整机远程控制工具)要显式登记与收窄;加固项会漂移,查的是 `Tailscale-Process` 的 `Edge=` 落库值(不是 `Tailscale-In`),并复核网卡归属 profile。

## 故障时(不要凭直觉查)

固定顺序:**① 打真实端口拿三态 → ② 重启两端 tailscaled → ③ 读服务端实际装载的 PacketFilter → ④ 服务端 OS 防火墙/网卡 profile → ⑤ 最后才怀疑中继**。
最常见的真因:**一端 tailscaled 会话状态失效**(症状:客户端全端口 timeout,服务端 netstat 完全看不到包)。完整速查见 [references/troubleshooting.md](references/troubleshooting.md)。

> 判读纪律:探针「被拒 / 返回 0 行 / 报语言本地化文本」一律落 **unknown**,**不得**读成「未登录 / 没监听 / 无规则」。分栏的探针能力表见 [references/verify.md](references/verify.md) §0.1。

## 文件索引

- `references/server-setup.md` —— 服务端安装/配置/回滚(逐条可粘贴命令;含 tailnet 控制台 ACL 收窄 §7、电源 AC/DC 的可粘贴设置与核验 §8)
- `references/client-setup.md` —— 客户端安装/取 token/首次打开 + 30 天 cookie 的绝对期限、续期与锁死路径 + 打通后的浏览器操控入口(§4)
- `references/browser-control.md` —— 打通之后怎么操作对端:`browser_*` 首选 / `ego_*` 只做轻量查询、composer 写入、下载 Session 日志读取、已知局限与证据等级
- `references/security.md` —— 威胁模型、预防清单、凭据生命周期与撤销、加固漂移、回滚
- `references/verify.md` —— 探针能力表(按探针)+ 三态验收 + soak 巡检 + 判定模板
- `references/troubleshooting.md` —— 链路故障速查(两端视角)
- `references/facts-verified.md` —— 外部事实核实(带 URL 与抓取日期;写文档前先查,别凭记忆)
- `references/automation.md` —— 脚本的真实边界(哪些只打印、哪些必须人工)
- `scripts/server-setup.ps1` / `scripts/verify.ps1` —— 只读巡检脚本(用 `-File` 形态跑)
