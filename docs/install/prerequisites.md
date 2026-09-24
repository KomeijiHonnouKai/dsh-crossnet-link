# 前置件清单与提醒(「OS × 角色」分支)

- **最后更新时间**: 2026-09-24(v1.2;t26:①新增**非侵入性**口径(本清单所有命令都是「**可选修复:由你执行**」,影响面与回滚见 `install.md` §0);②§3.7 补**影响面**(新增窄放行可能与既有规则重叠 / 不要改成放宽 profile 默认策略);③去掉对**内部资料**的引用(发布集文件不深链内部文档),改为就地复述。v1.1(t20):§3.10 的凭据撤销回滚改成 `rollback.md` §3 的三步版 —— 清客户端 cookie / 删服务端 credentials 的 `client-connection`+`browser-session` 记录 / 「仅重启 DSH 不会让已发出的 30 天 cookie 失效」。来源仍是 `panel/prereq-manifest.json` + `panel/prereq.ps1`)
- **本次使用的命令**(全部只读;无 `platform:"client"` 的 Inspect、无 `ego_*`、无长等待):
  1. `powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/panel/prereq.ps1 -CheckOnly`
  2. `powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/panel/prereq.ps1 -CheckOnly -Role client`
  3. `powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/panel/prereq.ps1 -CheckOnly -Role server -ShowInstallPlan`
  4. `powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/panel/prereq.ps1 -CheckOnly -AsJson`
  5. `powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/panel/prereq.ps1 -Describe`
  6. `Get-FileHash -LiteralPath 'C:\Program Files\Tailscale\tailscale.exe' -Algorithm SHA256`
  7. `Get-AuthenticodeSignature -LiteralPath 'C:\Program Files\Tailscale\tailscale.exe'`
  8. 交叉核对:`powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/src/collect.ps1 -CheckOnly -Role server`
- **克隆目录名**:本文件里所有 `dsh-crossnet-link/...` 路径都从工作区根写;克隆目录**必须**叫 `dsh-crossnet-link` —— 改了目录名,采集器就会找不到 `src/collect.ps1`(改报 `collector-missing`)。

> **单一来源**:清单本体是 `panel/prereq-manifest.json`(机器可读),`panel/prereq.ps1` 读取它并按角色逐项检测;
> 本文件是同一份数据的人读渲染。改一处即可,不会出现「文档与脚本各说一套」。
>
> ⚠️ **非侵入性(先读)**:本清单里的每条命令都是「**可选修复:由你执行**」—— 插件默认**只读**,不会改你的防火墙、profile、
> `cordis.patch.yml` 或其它插件配置;这些命令是**打印给你**的,不是替你跑的。改之前请读 `install.md` §0 的影响面表,尤其:
> 收窄 `Tailscale-Process` 的 Edge traversal 会影响**本机所有 Tailscale 功能**;新增窄放行可能与**既有规则重叠**;
> **持久化**安装这一行会影响该 profile 的**所有会话**(不确定就先别做,默认的动态包就够用)。

---

## 1. 先读这一节:角色语义与退出码(最容易误读的一点)

| 角色 | 含义 | 需要满足的项 |
| --- | --- | --- |
| `server` | **本机对外提供服务**(对端连过来) | serve / trustedHosts / 窄入向放行 / 电源策略 / tailnet ACL |
| `client` | **本机只是使用链路** | Tailscale 已装已登录 / MagicDNS 能解析 / 浏览器代理不劫持 / token 由人工粘贴 |
| `both`(**默认**) | 两套都校验 | 上面两组之和 |

⚠️ **默认 `both` 会同时校验服务端要求,所以「只做客户端」的机器默认必然非 0**——这不是坏了:

```
client-only 机器:  powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/panel/prereq.ps1 -CheckOnly -Role client
                     -> summary: total=8 pass=4 degraded=0 blocked=0 unknown=4   overall: degraded -> exit 1

同一台机器默认:      ... prereq.ps1 -CheckOnly
                     -> total=13 pass=6 degraded=0 blocked=1 unknown=6          overall: blocked -> exit 2
```

**退出码读法**(与 `src/collect.ps1` 同一套契约,可直接当门禁):

| 退出码 | 含义 |
| --- | --- |
| 0 | 该角色相关的前置件全部满足 |
| 1 | 存在降级或未知(未知不得当作通过) |
| 2 | 存在阻断(真的缺前置件),或清单本身不可用 |

> **exit 2 ≠ 命令失败**。它表示「按 fail-closed 语义,有确定的缺口或不可判定的项」。
> 只做客户端的机器请显式用 `-Role client`;要看得更细,用 `-AsJson` 读每项的 `verdict` / `reasonKey` / `raw`。

---

## 2. 前置件矩阵(13 项)

检测方式一栏是 `panel/prereq.ps1` 实际使用的 `detect.kind`;`—` 表示该项由人来判断(`manual`)或委派给 t5 采集器(`delegate`)。

| # | ID | 角色 | Win10 | Win11 | 检测方式 | 本机实测 verdict |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `TAILSCALE_INSTALLED` | 两端 | ✔ | ✔ | `command`: `tailscale.exe version` → exit 0 | **pass** |
| 2 | `TAILSCALE_CLI_LAYER` | 两端 | ✔ | ✔ | `command`: `tailscale.exe ip -4` → exit 0 | **unknown**(命名管道被拒 ⇒ 探针不可用,不是「未登录」) |
| 3 | `TAILSCALE_SIGNED_IN` | 两端 | ✔ | ✔ | `listener`: 存在 100.64.0.0/10 或 fd7a:115c:a1e0::/48 地址 | **pass** |
| 4 | `DSH_RUNNING_LOOPBACK` | 两端 | ✔ | ✔ | `listener`: loopback + `<DSH_PORT>` | **pass** |
| 5 | `SERVE_ON_TAILNET_443` | server | ✔ | ✔ | `listener`: tailnet 地址 + 443 | **blocked**(本机是客户端角色,未配 serve) |
| 6 | `TRUSTED_HOSTS_CONFIGURED` | server | ✔ | ✔ | `delegate` → `collect.ps1 -Role server`(见下方说明) | **unknown**(委派) |
| 7 | `NARROW_INBOUND_ALLOW` | server | ✔ | ✔ | `registry`: 规则库含 `Tailscale-Process` | **pass** |
| 8 | `SERVER_POWER_IDLE_SLEEP` | server | ✔ | ✔ | `command`: `powercfg /query … STANDBYIDLE` → exit 0 | **pass**(原始 AC/DC 由 t5 采集器判读) |
| 9 | `TAILNET_ACL_NARROW` | server | ✔ | ✔ | `manual`(控制台操作,本机不可验证) | **unknown** |
| 10 | `CLIENT_FIRST_OPEN_TOKEN` | client | ✔ | ✔ | `manual`(凭据类,禁止自动化) | **unknown** |
| 11 | `CLIENT_MAGICDNS` | client | ✔ | ✔ | `delegate` → `collect.ps1 -Role client -Peer … -PeerName …` | **unknown**(需操作者给对端) |
| 12 | `CLIENT_PROXY_BYPASS` | client | ✔ | ✔ | `registry`: `ProxyEnable`(期望 0;非 0 且绕过列表里没有 tailnet 名 / `100.64.0.0/10` ⇒ `registry_mismatch`) | **blocked**(本机实测:`ProxyEnable=1` 且无绕过;**只**覆盖客户端这一端,服务端见下面的说明) |
| 13 | `HOST_SERVICE_FOR_PANEL` | 两端 | ✔ | ✔ | `delegate`(可选:面板共享 t5 采集服务) | **unknown** |

**为什么 6 与 11 走委派**:判断这两项需要「扫整条实际加载的 patch 链」与「带超时的 DNS 解析 + 对端参数」,
`src/collect.ps1` 已经实现且是本团队唯一权威实现。**这里刻意不再写第二份弱实现** ——
清单的第一版只检查「文件里出现了 `trustedHosts` 这个词」,在本机(`app` 层是 `trustedHosts: []`)会给出**假通过**,
已改为委派并把这个教训写进 manifest 的 `detect.note`。

**代理是「两端 × 四格」,不是一条单侧提示**:本清单第 12 项只看**客户端这一端**(`ProxyEnable=1` 且没有 tailnet 直连规则 ⇒ `blocked/registry_mismatch`);**服务端那一端**由采集器判(`SERVER_PROXY_STATE` / `TAILNET_ROUTE_PRESENT`),本清单**不**为它设项。四种组合(客户端关·服务端关 / 客户端开·服务端关 / 客户端关·服务端开 / 客户端开·服务端开)、每格的判据命令、两条修法与回滚,见根 `README.md` 的 §6.1「两台设备 × 开/关代理 = 四种情况」([链接](../../README.md#61-两台设备--开关代理--四种情况));三个易踩点(WinINET 的 `ProxyOverride` 不支持 CIDR、git 的代理与系统代理是两件事、TUN 模式只能落 `unknown`)也在那一节。

---

## 3. 逐项:缺失提示语 / 安装命令 + sha256 / 校验命令 / 回滚命令

> 下面的 `cmd` / `verify` / `rollback` 都是**给人执行**的字符串。`panel/prereq.ps1` 只打印它们,
> **脚本里没有任何执行安装的代码路径**(没有 `-Yes` / `-Apply` / `-Force`,不做 `runas`,不建计划任务,不改服务)。

### 3.1 `TAILSCALE_INSTALLED`(两端)

- **缺失提示**:「本机未安装 Tailscale。请自行从厂商下载页安装;本插件不会替你安装软件。」
- **安装(人工四步)**:① 自己从厂商下载页下 Windows `.msi`(**不写死版本号**);② 校验 sha256 + Authenticode;③ 运行安装包,**UAC 由你点**;④ 安装完在客户端里点登录(浏览器 OAuth)。
- **安装命令**:`msiexec /i "<MSI_PATH>" /passive /norestart`
- **sha256 校验值**:见 §4 —— **本仓库不内置厂商哈希**,默认是「未固定 ⇒ 阻断」;`<MSI_PATH>` 由你给。
- **校验命令**:

```powershell
powershell -NoProfile -Command "(Get-FileHash -Algorithm SHA256 -LiteralPath '<MSI_PATH>').Hash"
powershell -NoProfile -Command "Get-AuthenticodeSignature -LiteralPath '<MSI_PATH>' | Select-Object Status,@{n='Signer';e={$_.SignerCertificate.Subject}}"
powershell -NoProfile -Command "(Get-Command tailscale.exe).Source"
```

- **回滚**:`msiexec /x "<MSI_PATH>" /passive /norestart`(或 设置 → 应用 → Tailscale → 卸载)

### 3.2 `TAILSCALE_CLI_LAYER`(两端)

- **缺失提示**:「本会话里 tailscale CLI 连不到守护进程(命名管道被保护/拒绝访问)。请改在普通(非沙箱)窗口执行 tailscale 命令,或接受 CLI 类判定为未知。」
- **没有安装步骤**:这是权限/沙箱边界,不是缺软件。原文(实测):`open \\.\pipe\ProtectedPrefix\Administrators\Tailscale\tailscaled: Access is denied.`
- **回滚**:无需回滚

### 3.3 `TAILSCALE_SIGNED_IN`(两端)

- **缺失提示**:「没有找到 tailnet 地址。请在 Tailscale 里登录(浏览器 OAuth,人工操作)并确认接口已启用。」
- **安装**:**人工**。本插件绝不代输账号/密码/验证码,也不代点浏览器授权。
- **回滚**:托盘菜单 Disconnect(或普通窗口 `tailscale down`)

### 3.4 `DSH_RUNNING_LOOPBACK`(两端)

- **缺失提示**:「`127.0.0.1:<DSH_PORT>` 上没有监听。请先启动 DSH Desktop;若它绑在通配地址上,那是安全问题,不是前置件缺失。」
- **端口来源**:`-Port` > `$env:DSH_WEB_URL` > 文档化的内置默认 `43120`(输出里标注来源)。
- **回滚**:无(采集器从不启动/停止 DSH)

### 3.5 `SERVE_ON_TAILNET_443`(服务端)

- **缺失提示**:「tailnet 地址上没有 443 监听。请在普通窗口执行 `tailscale serve --bg <DSH_PORT>`。不加 `--bg` 时,重启或 `tailscale up/down` 后 serve 配置不会自动恢复。」
- **安装命令**:`tailscale serve --bg <DSH_PORT>`
- **校验**:`tailscale serve status`(期望一条 `https://<机器名>.<tailnet>.ts.net/` 且 proxy 目标 = `127.0.0.1:<DSH_PORT>`);`netstat -ano | Select-String ':443'`(期望 owner = `tailscaled`)
- **回滚**:`tailscale serve reset`(**清空本机全部 serve 配置**,不是只停某个端口;复核:`tailscale serve status` 不再显示该 proxy)
- **探针读不出来时**:本项判 **`unknown`**(不是 blocked)—— 见 `panel/prereq.ps1` 的 `listener_source_unreadable`:结构化 .NET(`GetActiveTcpListeners`)优先 → 退回 netstat 文本 → 两者都读不到就**未知**;本地化 netstat 可用 `-NetstatStatePattern` 指定状态词

### 3.6 `TRUSTED_HOSTS_CONFIGURED`(服务端)

- **缺失提示**:「trustedHosts 里没有 tailnet 主机名,远端界面能打开但 `/api` 会一直失败(表现为反复「自动重连中」)。请在活动 profile 的 patch 里加上,并用 DSH 自带的重启菜单重启。」
- **判据(权威)**:`collect.ps1 -CheckOnly -Role server` 的 `TRUSTED_HOSTS_PATCH`。本机实测 **blocked**:`app\cordis.patch.yml:28` → `trustedHosts: []`。
- **安装(人工)**:编辑活动 profile 的 patch,加入服务端 MagicDNS 名;然后**用 DSH 自带的重启菜单**重启(设置 → 桌面/Desktop → 重启 ▾)。**绝不杀宿主、绝不装重启类插件** —— 宿主是 Electron `utilityProcess.fork` 子进程,脱离 supervisor 直接抛错(`<DSH_APP>\lib\host-process-entry.js:202-203`)。**影响面**:这份 patch 会被该 profile 的**所有会话**读到,写错会连带影响你在该 profile 里的其它工作 ⇒ 这是**可选修复:由你执行**;改动前先按 `install.md` §4.2 备份。
- **回滚**:删掉你加的那几行 → 再次用自带菜单重启

### 3.7 `NARROW_INBOUND_ALLOW`(服务端)

- **缺失提示**:「Tailscale 自带规则缺失或覆盖不到本部署。请只加一条窄入向放行:tcp 443、远端地址 100.64.0.0/10、程序 tailscaled.exe。放宽 profile 默认策略不能作为替代。」
- **背景**:自带 `Tailscale-In` **只覆盖 `Domain,Private`**;若 Tailscale 网卡被归为 `Public`,这些规则**静默失效**(矩阵 F23)。
- **安装命令(需你自己提权执行)**:

```powershell
New-NetFirewallRule -DisplayName 'DSH via Tailscale serve (tcp 443)' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 443 -RemoteAddress 100.64.0.0/10 -Program "$env:ProgramFiles\Tailscale\tailscaled.exe" -Profile Any
```

- **影响面(改之前请读)**:新增这条规则可能与**既有规则重叠**(同端口多条规则并存,后续排查更乱);
  **不要**改成放宽 profile 默认策略 —— 影响面远大于本插件需求。**可选修复:由你执行**:不做它插件照样能跑,只是这一项报缺。
- **校验**:`netsh advfirewall monitor show currentprofile`(看 Tailscale 网卡落在哪一段)+ `collect.ps1 -Role server`
- **回滚**:`Remove-NetFirewallRule -DisplayName 'DSH via Tailscale serve (tcp 443)'`

### 3.8 `SERVER_POWER_IDLE_SLEEP`(服务端)

- **缺失提示**:「STANDBYIDLE 的 AC 或 DC 非 0,服务端会到点睡眠、链路必断。措辞要准:报出 DC 的秒数,不要笼统写「已设不休眠」。」
- **安装命令(你自己提权执行)**:`powercfg /change standby-timeout-ac 0` + `powercfg /change standby-timeout-dc 0`
- **回滚**:**先记录原值**再改:`powercfg /change standby-timeout-ac <原分钟数>`、`powercfg /change standby-timeout-dc <原分钟数>`
- **实测参照**:本机 Win10 台式机 AC=DC=`0x0`(永不);对端 Win11 笔记本 DC=`0x00000e10`=3600 s ⇒ 措辞必须是「市电中断 3600 秒后链路必断」。

### 3.9 `TAILNET_ACL_NARROW`(服务端,人工)

- **缺失提示**:「无法在本机验证。请在 tailnet 控制台只放行「客户端 → 服务端 tcp 443」。单向窄 ACL 会让反向 ping 不通,这是预期行为,不是故障。」
- **回滚**:把控制台里改之前的策略文本粘回去

### 3.10 `CLIENT_FIRST_OPEN_TOKEN`(客户端,人工)

- **缺失提示**:「请把一次性 URL(`https://<机器名>.<tailnet>.ts.net/?token=<TOKEN>`)自己粘进浏览器打开一次,它会换成 30 天 cookie。不要把它贴进聊天、文件或日志。」
- **为什么必须人工**:URL 里的 token 是凭据。本插件不读、不显示、不传输、不落盘它。**清单文本里没有任何真实 token**(只有 `<TOKEN>` 占位符)。
- **回滚**(三步,按顺序;细节见 `rollback.md` §3):①**清客户端该站点的 cookie**(浏览器 → 该站点 → 清除站点数据);②**仅当怀疑 cookie 已泄漏时**:删掉服务端 credentials 里的 `client-connection` / `browser-session` 记录,然后用 DSH 自带菜单重启;③**仅重启 DSH 不会让已发出的 30 天 cookie 失效** —— 重启只换每个进程新生成的 launch token,那张 cookie 在到期前一直有效。⇒ 撤销只有两个落点:客户端的 cookie、服务端 credentials 里的授权记录;**DSH 界面没有撤销入口**,不要指望某个界面动作替你撤销。

### 3.11 `CLIENT_MAGICDNS`(客户端,委派)

- **缺失提示**:「请提供 `-PeerName` 交给采集器判定。绝不猜测或写死 tailnet 名字。」
- **委派命令**:`powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/src/collect.ps1 -CheckOnly -AsJson -Role client -Peer <SERVER_IP> -PeerName <机器名>.<tailnet>.ts.net`
- **回滚**:无

### 3.12 `CLIENT_PROXY_BYPASS`(客户端)

- **角色与范围**:这一项**只覆盖客户端这一端**;服务端那一端的代理姿态是采集器的 `SERVER_PROXY_STATE` / `TAILNET_ROUTE_PRESENT`,不是本清单的一项(不为它设第二份实现)。
- **缺失提示**:「系统代理已启用且没有 tailnet 直连规则,即使 TCP 通,页面也可能打不开。请把 tailnet 名字 / 100.64.0.0/10 加入绕过列表,或使用链路时关闭代理。」
- **本机实测(写这一节时)**:`blocked`(`registry_mismatch`)—— `ProxyEnable=1`、`ProxyServer=127.0.0.1:7897`,而 `ProxyOverride` 里既没有 `ts.net` 也没有 `100.64.`。
- **判据命令**(两端各跑一次;第 3 条是采集器的权威判定):

```powershell
# 1) 这一端的 WinINET 代理
Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' |
  Select-Object ProxyEnable, ProxyServer, ProxyOverride

# 2) 本清单自己的判定(客户端角色)
powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/panel/prereq.ps1 -CheckOnly -Role client

# 3) 采集器的权威判定(客户端 / 服务端各一次)
powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/src/collect.ps1 -CheckOnly -Role client
powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/src/collect.ps1 -CheckOnly -Role server
```

- **服务端那一端**:WinINET 系统代理**不影响入站路径**,所以服务端开着它时客户端照常打得开;但 **TUN 模式**的代理会接管路由 ⇒ 采集器报 `TAILNET_ROUTE_PRESENT = blocked/route_tailnet_missing`(聚合路由不见了这一半可以证明,**是不是那个代理干的判不了**)与 `SERVER_PROXY_STATE = degraded/proxy_active_route_intact`(`confidence=low`)。
- **四格与两条路**:四种组合 = 客户端关·服务端关 / 客户端开·服务端关 / 客户端关·服务端开 / 客户端开·服务端开;每格「客户端会看到什么 / 服务端会看到什么 / 怎么判 / 怎么修 / 怎么回滚」见根 `README.md` §6.1([链接](../../README.md#61-两台设备--开关代理--四种情况))。两条路选一 —— **路 1(推荐,一次性)**:在代理软件自己的规则里把 `*.ts.net` 与 `100.64.0.0/10` 设为直连;只能改 Windows 系统代理那一栏时写 `*.ts.net;100.64.*`(**`ProxyOverride` 不支持 CIDR,写 `100.64.0.0/10` 不生效**)。**路 2(最省事)**:用链路时关掉系统代理,用完再开。
- **安装(人工)**:设置 → 网络和 Internet → 代理 → 「不对这些地址使用代理服务器」里加入 `*.ts.net;100.64.*`(或你代理软件里的直连规则)。
- **回滚**:删掉你加的绕过项,或把开关与 `ProxyEnable` / `ProxyServer` / `ProxyOverride` 按原值打回 —— **改之前先留着 `Get-ItemProperty …` 的输出**,那就是你的备份。本清单与采集器**都不改**任何代理设置,所以它们这边没有回滚动作。

### 3.13 `HOST_SERVICE_FOR_PANEL`(两端,可选)

- **说明**:t5 的 host 包提供 `remoteTailnetGuard` Service。有它时面板复用同一个采集服务(`source=service:remoteTailnetGuard`);没有时面板的 host 半边自己跑采集器(`source=direct`)。
- **回滚**:对该 pluginId 执行 `cordis_stop`(Service / 私有方法 / 工具一起消失)

---

## 4. sha256 策略(为什么本仓库**不**内置厂商哈希)

`panel/prereq-manifest.json` 的 `hashPolicy`:

```json
{
  "pinnedSha256": "",
  "rule": "An install step may only be shown as ready when pinnedSha256 is non-empty AND the operator has confirmed it, AND the local file hash matches AND the Authenticode signature is Valid.",
  "ifNotPinned": "prereq.ps1 prints the install command but marks the step 'blocked: hash not pinned'"
}
```

**理由**:写进仓库的厂商哈希会在下个版本失效 —— 要么挡住合法安装,要么让被篡改的包看起来「没问题」。
所以默认 **未固定 = 阻断**(实测:`hash gate: blocked (hash_not_pinned)`),由操作者自己固定:

```powershell
# 1) 自己下载 .msi(不要用仓库里的链接)
# 2) 算哈希并与厂商公布值比对
powershell -NoProfile -Command "(Get-FileHash -Algorithm SHA256 -LiteralPath '<MSI_PATH>').Hash"
# 3) 把该值粘进 panel/prereq-manifest.json 的 hashPolicy.pinnedSha256
# 4) 顺手确认签名
powershell -NoProfile -Command "Get-AuthenticodeSignature -LiteralPath '<MSI_PATH>' | Select-Object Status,@{n='Signer';e={$_.SignerCertificate.Subject}}"
```

**本机实测样例(仅作「怎么固定」的示范,不是厂商公布值)**:

| 项 | 实测值(2026-09-24,本机) |
| --- | --- |
| 文件 | `C:\Program Files\Tailscale\tailscale.exe` |
| sha256 | `B4F36FEAA73443D4A90C3B34254525727CCE6C0E9BC3498CB80275DE4FFFA6BF` |
| 大小 | `17,421,304` 字节 |
| 版本 | `1.102.4-t3caf7d9e7-g084ee3b64` |
| Authenticode | `Valid` / `CN=Tailscale Inc., O=Tailscale Inc., L=Toronto, S=Ontario, C=CA` |

> 这个哈希**只对本机这一个文件+这一个版本成立**。`.msi` 的哈希与它的 `.exe` 不同,必须在你的 `.msi` 上自己算。

---

## 5. 自动 / 半自动边界(写死)

**本插件允许做的**:
1. 跑**只读**检测(注册表 / 服务 / 按列解析 netstat / 有界子进程 / 文件读取)。
2. 打印检测结果与给人执行的命令。
3. 把「固定的哈希 / 实际算出的哈希 / Authenticode 状态」三样并排显示。

**本插件绝不做**(`panel/prereq-manifest.json` 的 `automationBoundary.never`,也是 `panel/prereq.ps1` 的代码事实):

| 绝不做 | 原因 |
| --- | --- |
| 运行安装包 / `runas` / `Start-Process -Verb RunAs` / 计划任务 | **UAC 只能由你点**;本插件不提权 |
| 代登录 Tailscale(浏览器 OAuth) | 账号操作必须人工 |
| 把 `ExecutionPolicy` / UAC 级别 / 防火墙默认策略 / Defender / `networkExposure` 放宽当作「安装前置」 | 降低安全设置不是前置件,是漏洞 |
| 安装/启用任何 DSH 重启类插件,或杀/拉起宿主进程 | 宿主是 Electron utilityProcess,必然失败且可能让 DSH 起不来 |
| 新增监听、路由或防火墙规则 | 违反本版硬约束 |
| 读/打印/传输 token、cookie、密钥文件、DSH 凭据库 | 凭据纪律 |

唯一被接受的自动/半自动形态就是那一条:**展示 sha256 → 等你显式确认 → 由你点 UAC**。

---

## 6. 怎么跑

```powershell
# 只读检测(默认 both;给门禁用的退出码 0/1/2)
powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/panel/prereq.ps1 -CheckOnly

# 只做客户端的机器
powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/panel/prereq.ps1 -CheckOnly -Role client

# 连「已满足项」的安装/校验/回滚命令一起看
powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/panel/prereq.ps1 -CheckOnly -Role server -ShowInstallPlan

# 机器可读
powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/panel/prereq.ps1 -CheckOnly -AsJson

# 配置面 / 角色语义 / 自动化边界 / 哈希策略
powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/panel/prereq.ps1 -Describe
```

覆盖项(`全在参数/环境,无写死`):`-Role`、`-Manifest`、`-DshHome`(> `$env:DSH_HOME` > `~\.dsh`)、`-AppDir`(> `$env:DSH_APP_DIR` > 运行中 DSH 进程镜像路径)、`-Port`(> `$env:DSH_WEB_URL` > 43120)、`-MsiPath`、`-Lang`、`-CommandTimeoutMs`。
JSON 里的 `config[]` 逐项标注来源;`<DSH_HOME>` / `<APP_DIR>` / `<DSH_PORT>` / `<MSI_PATH>` 在运行时解析,解析不到 ⇒ 该项 `unknown`(`placeholder_unresolved`),不猜。

**本机实测输出**(2026-09-24,非提权 agent 会话):

```
summary: total=13 pass=6 degraded=0 blocked=1 unknown=6      overall: blocked -> exit 2
```

各项 verdict 见 §2 表。这 1 blocked 是 `SERVE_ON_TAILNET_443`(本机当前是客户端角色,服务端项确实未满足),
5 个 unknown 全部计入不确定性(fail-closed),**没有任何一项被当作通过**。
