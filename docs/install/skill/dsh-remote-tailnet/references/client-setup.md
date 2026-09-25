# 客户端:安装与首次打开

> 最后更新:2026-09-26。本次补:§1 装 Tailscale 的**可粘贴命令原文**、§2 取 token 的 **loopback 打开命令**(含裸 URL 会被 401 的源码依据)、§3.1 源码行号**逐行复核**、新增 §4「打通之后:浏览器操控对端」、§5 常见坑补两行。W4 的历史修订见 `README.md` 的「本次修订」。
> 客户端 = 用来操作服务端 DSH 的那台。**本文命令都在客户端机器上跑**,只有 §2 标了「服务端」的那几步例外。
> 与 server-setup.md 同一套形态纪律:`.ps1` 一律 `powershell -NoProfile -ExecutionPolicy Bypass -File <路径>`;`powercfg` / `netsh` / `tailscale.exe` 是系统命令、不走 `-File`;含中文的 `.ps1` 存成 UTF-8 with BOM。

## 1. 装 Tailscale 并登录(与服务端**同一个账号**)

安装同服务端第 1 步([server-setup.md](server-setup.md) §1:下载 → `.sha256` 校验 → 静默安装;回滚 `msiexec /x`),然后登录**同一个 Tailscale 账号**(同一个 tailnet)。

客户端侧可粘贴命令原文 —— **必须在用户自己的普通窗口跑**:

    & "$env:ProgramFiles\Tailscale\tailscale.exe" ip -4     # 记下自己的 100.x:后面 ACL 的 src 就是它
    & "$env:ProgramFiles\Tailscale\tailscale.exe" status    # 期望:自己那台 Online,且能看到服务端那台

⚠️ **agent 沙箱里这两条一定失败**,失败长这样:`exit=1` + `open \\.\pipe\ProtectedPrefix\Administrators\Tailscale\tailscaled: Access is denied.`(tailscaled 的 LocalAPI 走受保护的命名管道)。那是**探针不可用**,不要读成「未登录 / 没装」。更别拿 `tailscale version` 的 exit=0 去判「CLI 可用」—— 它读的是二进制自述、不碰守护进程(verify.md §0.1)。

## 2. 取 token(只在服务端机器上做,不要把值贴给任何人/任何对话)

服务端 DSH Desktop → 设置 → 桌面/Desktop → 「**浏览器访问地址**」那一栏,形如:

    http://127.0.0.1:43120/?token=AbCdEf...

只取 `?token=` **后面那串**。(若在服务端本地用「在浏览器中打开」打开过,也可以直接从地址栏复制。)

想在**服务端本机浏览器**里核对同一页,可粘贴(把 token 换成刚复制的那串):

    Start-Process 'http://127.0.0.1:43120/?token=<刚复制的那串>'

⚠️ **裸 `http://127.0.0.1:43120/`(不带 token)会被 401 拒**,原文:`dsh web authentication required; reopen the URL printed by dsh web.` —— 这不是故障。源码依据(本地 `dsh-client-connection/lib/index.js`):

- `authorizeIndex`:带 `?token=` 且命中本进程 token ⇒ **303 → `/`** 并 `set-cookie`(`:390-408`);无 token 且 cookie 无效 ⇒ **401** + 一行提示文本(`:419`、`:442-448`);
- 所以要用带 token 的地址,或从设置页点「在浏览器中打开」(它打开的正是 `authenticatedUrl(...)`,自带 token;`DSH Desktop/resources/app/lib/host-process-entry.js:146`)。

> 注意:那一栏显示的 loopback 地址只是**在哪里显示**的问题,`token=` 那串与入口域名无关 —— 换成 `https://<ts.net 域名>/` 一样用。
> 服务端本机用带 token 的地址开过一次之后(浏览器里有 cookie 了),裸 loopback 地址在 cookie 有效期内也能直接开。

## 3. 首次打开(客户端机器)

在客户端浏览器地址栏粘贴一次:

    https://<机器名>.<tailnet>.ts.net/?token=<上一步那串>

预期:303 → `/`,随后正常进入界面,**cookie 有效期 30 天**(绑定 `host:port`)。
证书:由 Tailscale 自动签发(公共可信),**不应有证书警告**;若有警告,说明访问的不是 serve 入口,停下来查。

### 3.1 这个 30 天是**绝对期限**,不因使用而续期

源码判据(`dsh-client-connection/lib/index.js`,本机 `...\resources\app\node_modules\@deepseek-ai\`;下面行号 **2026-09-26 在本机逐行复核过**):

| 事实 | 出处 |
| --- | --- |
| 默认 30 天:`cookieMaxAgeDays: z.natural().min(1).default(30)` | `:740`(兜底 `:753`) |
| cookie 只在**带 token 的那一次 `GET /`** 里签发,`expiresAt = issuedAt + 30 天`,响应是 **303 → `/` + `set-cookie`** | `:390-408`(`issuedAt` / `expiresAt` `:393-400`,303 `:401-406`) |
| 之后每个请求只**校验**,从不重签、从不带 `set-cookie` | `isAuthenticated` `:431-441`(纯读判断:只比 `issuedAt <= now < expiresAt`) |
| cookie 里绑了 `authority`(= 请求的 `host:port`),`payload.authority !== authority` 直接判失败 | `requestAuthority` `:252-261`、`:438` |

⇒ **天天用也不会延长**。到第 30 天,不管中间用了多少次,都会失效。

### 3.2 续期:趁**还没到期**、且**服务端还没重启**时,从仍有效的会话里重取当前 launch token

launch token 是**每进程随机**的(重启即换,见 security.md §4),所以「旧的 token 存着没用」—— 要拿的是**当前这个进程**的 token。趁 cookie 还有效(远端界面还能进)时做一次:

1. 在**客户端浏览器**里打开远端界面 → 设置 → 桌面/Desktop → 「浏览器访问地址」 → 复制 `?token=` 后面那串(**这就是当前进程的 token**);
2. 在同一浏览器地址栏再打开一次:

       https://<机器名>.<tailnet>.ts.net/?token=<刚取到的当前 token>

   预期 303 → `/`,**新的 30 天从这一刻重新起算**。

> 建议在到期前 1–3 天做一次(比如每 25 天)。做的时候服务端**不能**刚重启过 —— 刚重启过的话界面里显示的就是新 token,照抄即可,一样成立。

### 3.3 锁死路径:到期了 **且** 服务端自那次签发后重启过 ⇒ 必须到服务端机器前处理

同时满足这两条时,**远端已经没有任何可用凭据**:

- cookie 过期(或已被清掉)⇒ 远端界面进不去;
- 服务端在那之后重启过 ⇒ 你手里存着的 token 是**上一个进程**的,已作废;而新 token 只在服务端本机设置页(loopback)显示。

⇒ 处置(只能人工,没有远程捷径):

1. 到服务端机器前,打开 DSH Desktop → 设置 → 桌面/Desktop → 「**浏览器访问地址**」,取 `?token=<当前这串>`(想当场核一眼,就在服务端本机跑 `Start-Process 'http://127.0.0.1:43120/?token=<那串>'` —— **裸 loopback 地址会 401**,见 §2);
2. 回到客户端机器,粘一次 `https://<机器名>.<tailnet>.ts.net/?token=<那串>`。

> 这也是为什么别把「服务端重启」当成随手动作:每次重启都会让**已经贴给客户端的 token**作废。cookie 还在时无所谓;cookie 一到期,重启过就要跑一趟。

## 4. 打通之后:浏览器操控对端(连接方就是操控方)

链路通了不等于能干活 —— 「打开之后怎么操作对端」单独一篇:[references/browser-control.md](browser-control.md)。**动手前先过一遍它的 §1「两条前置检查」**(桥要靠 Chrome 扩展连着;没有活动扩展时所有 `browser_*` 会直接报 `no browser extension is connected to the bridge`)。最小流程(**全部在客户端这台机器上做,不用再去服务端机器前**):

1. **入口**:客户端浏览器打开 `https://<机器名>.<tailnet>.ts.net/`(cookie 没过期就不用再带 token)。先确认受控标签页就是它:`browser_list_tabs`;丢了就 `browser_follow_tab` 重挂;
2. **写入(给对端发消息)**:`browser_snapshot` 找 composer 的 `textbox` → `browser_type` 写入(**剪贴板粘贴进不去,只能 type**)→ 点 `button "发送消息"`。判据:按钮变成 **`停止生成`** = 已发出;回到 `发送消息` = 对端那一轮跑完;
3. **读取(拿完整回复)**:页面文本**永远只有前 ~8.4 KB**,长回复读不全 ⇒ 走 **「更多操作 → 下载 Session 日志」**,再按 [browser-control.md](browser-control.md) §3.1「可粘贴命令原文」用 .NET `ZipFile` 只解出 `session.v3.jsonl`(**别用 `Expand-Archive`** —— zip 里有名字带冒号的条目),最后按 `"type":"assistant/message"` 取最后一条、把 `content[]` 里 `type -eq 'text'` 的块拼出来(块数组会混 `reasoning`/thinking);
4. **工具选择**:操控对端用 DSH 自带的 `browser_*`(**首选**,本案实测全程无超时);`ego_*` 只做**轻量查询**(`ego_doctor` / `ego_status` / `ego_page_info`)—— `ego_script` / `ego_navigate` 这类重操作会撞 tool call 的 **120 s 上限**,超时后**不要重试**,直接换 `browser_*`。

> 写入与读取都在**客户端**完成(是「本机 DSH 的浏览器桥操作另一台 DSH 的界面」);对端按 token 计费,**没有实质内容就别发消息**。完整坑表见 [browser-control.md](browser-control.md) §4「已知局限」。

## 5. 常见坑

| 现象 | 原因 | 处置 |
| --- | --- | --- |
| 界面能开,但目录选择器报 403、客户端反复「自动重连中」 | 服务端缺 `connection.trustedHosts`(或写法不对) | 服务端按 server-setup.md 第 5 步 + security.md §6 补上并重启 DSH |
| 浏览器「响应时间过长」,但脚本探测是通的 | 浏览器走系统代理/TUN,`.ts.net` 未直连 | Clash 里加 `DOMAIN-SUFFIX,ts.net,DIRECT` + `IP-CIDR,100.64.0.0/10,DIRECT,no-resolve` |
| 401 | 正常:还没带 token(或 cookie 已过期) | 用 §3 带 token 打开一次;过期就走 §3.2 / §3.3 |
| 403 | Host 栅栏(或 ACL) | 先看服务端 trustedHosts(含 entry 是否裸 `host[:port]`),再看 ACL |
| 超时(全端口) | 见 troubleshooting.md,先重启两端 tailscaled | — |
| 用了 30 天左右忽然打不开,且服务端重启过 | cookie 绝对到期 + launch token 已换 | §3.3(必须到服务端机器前) |
| **读不到对端的回复**(或只读到开头一段) | 页面文本 `browser_get_text` / `snapshot` **只返回前 ~8.4 KB**,长会话的最新回复必然落在截断之外;侧边栏预览同样被截断 | 走「更多操作 → 下载 Session 日志」+ .NET `ZipFile` 解出 `session.v3.jsonl`(browser-control.md §3.1);别指望侧边栏预览或消息上的「复制」按钮 |
| `ego_*` 报 **120 s 超时** | `ego_*` 的 tool call 有 120 s 上限,`ego_script` / `ego_navigate` 这类重操作会撞上限 | **不要重试**:换 DSH 自带 `browser_*`;`ego_*` 只留给轻量查询(`ego_doctor` / `ego_status` / `ego_page_info`) |
