# 服务端:安装与配置(逐条命令,幂等)

> 最后更新:2026-09-26。本次补:§1 官方 `.sha256` 现取现比、§2 可粘贴登录命令、**§7 tailnet 控制台收紧 ACL(单向 443)—— 新增小节,原 §7/§8 顺延为 §8/§9**、§8 电源策略的**可粘贴设置命令**(原来只有核验命令)、§9 收尾核对加一条浏览器侧确认。t18 的历史修订(回滚命令从**不存在的 `off` 子命令**改为 `tailscale serve reset`)见 `README.md` 的「本次修订」。
> 服务端 = 被远程操作的那台(DSH 跑在它上面)。所有命令在**服务端**执行;标了【管理员】的要提权。
> 本文里的 `.ps1` 一律用 `powershell -NoProfile -ExecutionPolicy Bypass -File <路径> …` 跑(默认 Restricted 下裸 `.\xxx.ps1` 会被拒);`server-setup.ps1` **只检查、只打印,不改动任何东西**。
> **`powercfg` / `netsh` / `tailscale.exe` 是系统命令,不适用 `-File`** —— 直接调用(或 `& "…\tailscale.exe" …`),别写成 `-File tailscale.exe`。
> 若要自己把这些命令落成 `.ps1` 文件:含中文的 `.ps1` **必须存成 UTF-8 with BOM**(BOM 丢了 PowerShell 5.1 会按 ANSI/GBK 读,报成片**假**语法错 —— 本机实测一次 17 条)。

## 0. 记录现状(回滚点,只读)

    $out = "$env:USERPROFILE\Desktop\dsh-remote-baseline.txt"
    '== IPv4 ==' | Out-File $out -Encoding utf8
    [Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() | ? { $_.OperationalStatus -eq 'Up' } | % { $_.Name + ' | ' + (($_.GetIPProperties().UnicastAddresses | ? { $_.Address.AddressFamily -eq 'InterNetwork' } | % { $_.Address.IPAddressToString }) -join ',') } | Out-File $out -Append -Encoding utf8
    '== profiles ==' | Out-File $out -Append -Encoding utf8
    netsh advfirewall show allprofiles state | Out-File $out -Append -Encoding utf8
    '== 43120 listener ==' | Out-File $out -Append -Encoding utf8
    netstat -ano | Select-String '127.0.0.1:43120' | Out-File $out -Append -Encoding utf8
    $out

## 1. 装 Tailscale

    # 下载(地址与期望 hash 写死,便于审计)
    $url = 'https://pkgs.tailscale.com/stable/tailscale-setup-1.102.4-amd64.msi'
    $expect = '80EB007E39DFEBE17299FA1A09C79A8E1D934F76E0246C0817EBE3AF675B7EF6'
    $msi = "$env:USERPROFILE\Downloads\tailscale-setup-1.102.4-amd64.msi"
    Invoke-WebRequest -Uri $url -OutFile $msi
    if ((Get-FileHash $msi -Algorithm SHA256).Hash -ne $expect) { throw 'sha256 校验失败,停止安装' }
    # 静默安装(会弹一次 UAC)
    Start-Process msiexec.exe -Verb RunAs -ArgumentList '/i',"$msi",'/qn','/norestart' -Wait
    Test-Path "$env:ProgramFiles\Tailscale\tailscale.exe"   # 期望 True
    Get-Service Tailscale | Select-Object Status,StartType      # 期望 Running / Automatic
    回滚:msiexec /x "$msi" /qn

核对 hash 的**官方途径**(不想只凭写死值审计时):包服务器自己写明「给文件 URL 追加 `.sha256` 即得校验值」,所以可以现取现比:

    (Invoke-WebRequest -Uri "$url.sha256").Content.Trim()
    # 实测(2026-09-26 抓 https://pkgs.tailscale.com/stable/tailscale-setup-1.102.4-amd64.msi.sha256)
    #   ⇒ 80eb007e39dfebe17299fa1a09c79a8e1d934f76e0246c0817ebe3af675b7ef6(= 上面 $expect 的小写,比对时大小写无关)

⚠️ `$url` / `$expect` 是**版本钉死**的:1.102.4 是抓取当日 https://pkgs.tailscale.com/stable/ 上的 stable。该版本下架后这条下载会 404 —— 到那个页面取当前版本与文件名,**同时**更新 `$url` 与 `$expect`(从 `.sha256` 现取),**不要**拿旧 hash 去配新文件。

## 2. 登录(人工,不可代做)

托盘 Tailscale 图标 → Log in → 浏览器用**与客户端同一个账号**完成登录。
    & "$env:ProgramFiles\Tailscale\tailscale.exe" ip -4   # 期望 100.x.x.x(ACL 里要写它)
    & "$env:ProgramFiles\Tailscale\tailscale.exe" status

上面两条要在**用户自己的普通窗口**跑:agent 沙箱里 `tailscale` CLI 会被命名管道拒绝(`Access is denied`,exit=1),那是**探针不可用**,不是「未登录」;而 `tailscale version` 会 exit=0(它不碰守护进程),**不能**用来判「CLI 能不能用」(分栏判据见 verify.md §0.1)。

## 3. 确认 DSH 的 loopback 端口

    netstat -ano | Select-String '127.0.0.1:' | Select-String 'LISTENING'   # 找 43120 及其 owner PID
端口默认取 `dsh-desktop.port` = **43120**;**这个值必须保持**,改了 serve 会指向空气。

判读纪律(实测过的假阴性,别读成结论):

- `Get-NetTCPConnection -LocalPort 43120` **cmdlet 存在但不报错地返回 0 行**(非提权;同刻 `netstat` 有监听行)⇒ 不能据此说「没监听」。判「在监听」用 `[Net.Sockets.TcpClient]` 真连一次,或看 `netstat` 的**行结构**(远端列 = `0.0.0.0:0` 才是监听行,不依赖状态词);
- 中文系统上 `netstat` 文本可能被本地化 ⇒ 匹配状态词要**同时接受中英两种**,匹配失败走「无法判定」而不是「没监听」;别用 `Get-Culture` 预判工具输出的语言(本机 `en-US` 而 `powercfg` 输出中文)。

## 4. 起 serve(--bg 必须有)

    & "$env:ProgramFiles\Tailscale\tailscale.exe" serve --bg 43120
    & "$env:ProgramFiles\Tailscale\tailscale.exe" serve status   # 记下 https://<机器名>.<tailnet>.ts.net/
要点:`serve --bg` 会在机器重启/`tailscale up/down` 后**自动恢复**;不带 `--bg` 的不会。
回滚:`tailscale serve reset` —— **语义 = 清空这台机器上全部 serve 配置**(不是只撤这一个端口;本机实测 `tailscale serve --help` 的 USAGE 只有 `<target>` / `status [--json]` / `reset`,**没有 `off`**)

## 5. 追加 Host 信任(不加则远端 /api 403)

文件:`%USERPROFILE%\.dsh\profiles\<profile>\cordis.patch.yml`(默认 profile 名 `desktop`;**若设了 `DSH_HOME`,则 profile 根是 `%DSH_HOME%\profiles`**;也可用 `-ProfileDir` 显式指定),在**末尾追加**:

    - id: connection
      name: '@deepseek-ai/dsh-client-connection'
      config:
        trustedHosts: ['<机器名>.<tailnet>.ts.net', ...ctx.webRuntime.trustedHosts]

⚠️ 两个硬要求(不满足会**当场报错或静默丢东西**,详见 security.md §6):

1. patch 的 config 是**整行覆盖**语义 ⇒ 必须带 `...ctx.webRuntime.trustedHosts`,否则运行时派生的 LAN 字面量被静默丢掉(今天本机还能开,是因为 loopback 在 `isTrustedApiRequest` 里被内建短路放行,不是因为写法对);
2. 每个 entry 必须是**裸 `host[:port]`**:带路径、`user@host`、首尾空白、悬空冒号、零填充端口、非规范拼写都会让 `assertTrustedAuthority` 在装载时抛 `is not a bare host[:port] authority`。

为什么:DSH 对 `/api` 有 Host 信任栅栏(只信任 loopback + 本机局域网 IP + 声明的 `trustedHosts`)。不加这行,远端界面能开但目录选择器等 `/api` 功能 403。
然后把 DSH 用**自带入口**重启:设置 → 桌面/Desktop → 「重启 ▾」→ 重启。**不要装第三方重启插件**。
回滚:删掉这一项再重启。

巡检脚本对应动作(只检查 + 打印,不写文件):

    powershell -NoProfile -ExecutionPolicy Bypass -File .dsh/skills/dsh-remote-tailnet/scripts/server-setup.ps1 -TsNetHost <机器名>.<tailnet>.ts.net -ProfileName desktop

## 6. 防火墙(按需)

`tailscale serve` 只绑 `100.x`(不新增 `0.0.0.0`)。若 Tailscale 网卡所在 profile 的防火墙是开启状态,需要一条窄放行:

    New-NetFirewallRule -DisplayName 'DSH via Tailscale serve (tcp 443)' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 443 -RemoteAddress 100.64.0.0/10 -Program "$env:ProgramFiles\Tailscale\tailscaled.exe" -Profile Any
    回滚:Remove-NetFirewallRule -DisplayName 'DSH via Tailscale serve (tcp 443)'

**排查时先分清「查哪条规则」「网卡归哪个 profile」**:

- Tailscale 自己带两条 `Tailscale-In`(`Profiles=Domain,Private`、`Edge=No`;本机实测)+ 一条 `Tailscale-Process`(进程级,本机实测 `Edge=TRUE`)。**要收 Edge traversal 的是 `Tailscale-Process`**;只查 `Tailscale-In` 会得出「没有漂移」的错结论;
- 判据用**落库值**(非提权可读):`reg query "HKLM\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\FirewallRules" /s | Select-String Edge=`;
- 网卡归属:`netsh advfirewall monitor show currentprofile`(exit=0,非提权)。**[实测]** 本机 Tailscale 网卡 = Private;**[仅配置可推导]** 若被归为 Public,`Tailscale-In` 那两条不生效 ⇒ 静默失效(未在 Public 机器上实测,报告里不得写成「已验证」);
- ⚠️ `Get-NetFirewallRule` / `Get-NetFirewallProfile` 在非提权下**拒绝访问** ⇒ 那是 `unknown`,不是「无规则/没开防火墙」。

## 7. tailnet 控制台:收紧 ACL(只放「客户端 → 服务端 tcp:443」)

**默认 policy 是全通**(等价于 `src` 全放、`dst` 全端口),也就是「能进这个 tailnet 的设备都能打服务端 DSH 的端口」。这一步把它改成**单向、单端口**。

1. 打开控制台(2026 现行入口):

       https://console.tailscale.com/admin/acls

   旧文档里的 `login.tailscale.com/admin/acls` 若已换掉,按页面里的 **Access controls** 进即可。改 policy 需要 **Owner / Admin / Network admin** 角色。

2. 把整个 policy 文件替换成下面这段(**两个占位符换成真实 100.x,`/32` 保留**)—— 这就是可整段粘贴的原文:

       {
         "acls": [
           {
             "action": "accept",
             "src": ["<客户端 100.x>/32"],
             "dst": ["<服务端 100.x>/32:443"]
           }
         ]
       }

   语法要点(依据官方 tailnet policy 语法文档,2026-04-08 版):

   - `src` 每个元素可以是 **Tailscale IP 或 CIDR**;**设备名不能当 selector**(见 security.md §2 第 3 条);
   - `dst` 每个元素**必须写成 `<host>:<ports>`** —— 端口不能省,省了就不是「窄」ACL;
   - `action` 只有 `accept`(Tailscale 是默认拒绝);`proto` 可省(省了 = TCP+UDP 都适用,本方案够用);
   - 控制台现在有 **Convert to grants** 按钮、官方也改推 `grants` 写法 —— **本方案不点它**:只保留这条已实测跑通的 `acls` 形态,不把验证过的写法换成没验证过的;
   - 保存时控制台会校验;报 `src` / `dst` 语法错就按提示逐行改,别凭记忆改。

3. **设备只留两台**:控制台 → Machines(`https://console.tailscale.com/admin/machines`)→ 把不需要的设备 **Remove**。判据 = 列表里只剩客户端与服务端。⚠️ 移除**不可逆**(那台设备要重新 `tailscale up` 登录才会回来)—— 动手前先确认它不是你此刻正在用的机器。

4. **账号开二次验证**:Tailscale **没有**自己的密码体系,它**继承身份提供方(IdP)的 MFA** —— 到你的登录方式(Google / Microsoft / Apple / Okta / OneLogin …)那边打开多因素认证(官方文档「Enable two-factor and multifactor authentication」)。理由:账号被拿走 = 攻击者能把新设备加进 tailnet,这条窄 ACL 就白设了。

5. **副作用(预期,不是故障)**:

   - tailnet 内**除这一条以外**的流量全部被拒:其它端口、其它方向、其它设备之间都不通;
   - **别拿 ping 当链路证据**:官方文档写明「某一对 IP 之间只要有任何规则放行,**ICMP 也会被放行**」⇒ **客户端能 ping 通服务端 ≠ 443 通**;而反向(服务端 → 客户端)没有任何规则,**ping 不通是预期**。判定一律用 `<服务端 100.x>:443` 的 TCP 三态(`scripts/verify.ps1`);
   - TCP 是**有状态**的,回程包不需要单独开规则 —— 本案实测就是只放单向 443 跑通的;
   - 若这个 tailnet 里还有别的设备/子网路由/exit node,这条 policy 会**一并**把它们切断(整个文件被替换了)。改之前先看现有文件;改坏了用控制台 Configuration logs(`https://console.tailscale.com/admin/logs`)按时间点还原。

6. 收窄后**必须**重跑一次客户端侧验收(443 connected、隔离口 timeout),并确认客户端浏览器仍能打开 `https://<机器名>.<tailnet>.ts.net/`。若客户端解析不出该域名:先查控制台 DNS 页的 MagicDNS(本案实测窄 ACL 后照样能解析并打开)。

   ⚠️ 这条 ACL **钉死在 443**:一旦有人把 serve 换成别的端口(§4),443 监听就没了、ACL 不再匹配任何东西,**控制面不会报错**(security.md §5.2)。所以改端口时必须同步改 ACL。

7. 可选核对:读**设备实际收到的**过滤规则(不是读控制台回显):

       & "$env:ProgramFiles\Tailscale\tailscale.exe" debug netmap | Select-String -Pattern 'PacketFilter'

   - **须在用户自己的普通窗口跑**:agent 沙箱里实测 exit=1 + `error Post "http://local-tailscaled.sock/localapi/v0/debug?action=current-netmap": context deadline exceeded` —— 那是**探针不可用**,不是「没有规则」;
   - 命令本身有据可查:`tailscale debug --help` 里列有 `netmap  Print the current network map`,`tailscale debug netmap -h` 的 USAGE 就是 `tailscale debug netmap`(无参数);CLI 自己声明 **debug 不是稳定接口**,字段名会随版本变(`PacketFilter` / `PacketFilters`);
   - 判读:里面应出现你那对 100.x 与 `DstPorts` 的 `443`;出现 `*` / 通配端口 = 没收紧;
   - 证据等级:`netmap` 这个子命令 **【实测存在】**(本机 `debug --help` 与 `debug netmap -h` 均 exit=0);「从输出里读到 PacketFilter 内容」**【本机未执行】**(沙箱被拒,须普通窗口)。

## 8. 电源策略(笔记本必做)

设置 → 系统 → 电源:接通电源时「合盖不休眠」、闲置不睡眠。

**只设 AC 不够——必须 AC 与 DC 分开查**:实测该机 `STANDBYIDLE` `AC=0x0`(永不)/ `DC=0xe10`(3600 s),而 `powercfg /a` 对 S0 低电量待机的描述是「**网络已断开连接**」⇒ **市电一断,1 小时后链路必断**(症状 = 对端所有端口一起超时)。

### 8.1 可粘贴的设置命令【要在管理员窗口跑】

    # 方案索引 / 子组 / 设置三项都接受系统别名(本机 powercfg /aliases 实测有 SUB_SLEEP / STANDBYIDLE / SUB_BUTTONS / HIBERNATEIDLE)
    powercfg /setacvalueindex SCHEME_CURRENT SUB_SLEEP STANDBYIDLE 0      # 接通电源:闲置永不睡眠
    powercfg /setdcvalueindex SCHEME_CURRENT SUB_SLEEP STANDBYIDLE 0      # 电池:闲置永不睡眠
    powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0      # 接通电源:合盖 = 不采取任何操作
    powercfg /setdcvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0      # 电池:合盖 = 不采取任何操作
    powercfg /setactive SCHEME_CURRENT                                   # 让改动对当前方案生效(少这条不生效)

    # 可选(标准子组,本机未执行):连休眠一起关,免得 HIBERNATEIDLE 到点进休眠
    powercfg /setacvalueindex SCHEME_CURRENT SUB_SLEEP HIBERNATEIDLE 0
    powercfg /setdcvalueindex SCHEME_CURRENT SUB_SLEEP HIBERNATEIDLE 0
    powercfg /setactive SCHEME_CURRENT

    # 回滚:把 0 换回 §8.2 记下的原值(改之前先记),再跑一次 /setactive

`0` 的语义:`STANDBYIDLE` 单位是秒,`0` = 永不;`LIDACTION` 是枚举,`0` = 不采取任何操作。

### 8.2 核验(取原值,不读回显;改前改后各跑一次)

```powershell
powercfg /query SCHEME_CURRENT SUB_SLEEP STANDBYIDLE
powercfg /query SCHEME_CURRENT SUB_BUTTONS LIDACTION
powercfg /a
```

(第一条与裸 GUID 写法等价:`238c9fa8-…` = `SUB_SLEEP`、`29f6c1db-…` = `STANDBYIDLE`,本机 `powercfg /aliases` 实测一一对应。)

判据:

- `STANDBYIDLE` 那段里「**当前交流电源设置索引**」与「**当前直流电源设置索引**」都应为 `0x00000000`;
- `LIDACTION` 那段同样两行都应为 `0x00000000`;**只打印方案头、没有这两行 = 这台机器没有该设置,不算通过**(见 §8.3);
- 交付措辞写「**市电中断 1 小时后链路必断**」,不要写成「已设置不休眠」—— 除非上面两条索引都实测为 0。

### 8.3 证据等级(别混着说)

- **【实测】** `powercfg /query SCHEME_CURRENT SUB_SLEEP STANDBYIDLE` 与 `powercfg /aliases` 在本机 exit=0,四个别名(`SUB_SLEEP` / `STANDBYIDLE` / `SUB_BUTTONS` / `HIBERNATEIDLE`)确实存在;`powercfg /a` 写明 S0 低电量待机「网络已断开连接」;对端(服务端)机器的 `STANDBYIDLE` `AC=0x0` / `DC=0xe10`(3600 s)⇒ **市电一断,1 小时后链路必断**;
- **【Windows 标准子组 / 设置,本机未执行过】** §8.1 里那些 `powercfg /set…valueindex` 与 `LIDACTION` 的**写入**效果:本机只跑过 `/query`、没跑过 `/set…`;且本机是**无盖台式**机 —— `powercfg /aliases` 里**没有 `LIDACTION`**。合盖动作是笔记本(Win10/11 的标准电源子组)的设置;**首次执行后必须**按 §8.2 核验,别直接写「已设置不休眠」;
- **【判读陷阱,实测】** 无盖机器上 `powercfg /query SCHEME_CURRENT SUB_BUTTONS LIDACTION` 会**只打印方案头就 exit=0**(实测输出仅 2 行:`电源方案 GUID: …` / `GUID 别名: SCHEME_MIN`)—— 这是「这台机器没有该设置」,**不是**「已设为 0」。核验前可先跑 `powercfg /aliases | Select-String LIDACTION` 确认别名存在。

⚠️ 解析 `powercfg` 输出时**别用区域预判语言**:本机 `Get-Culture = en-US`,但 `powercfg /getactivescheme` 实测输出**中文**(「电源方案 GUID: … (高性能)」)。优先取 `powercfg /query` 里的十六进制索引值(结构化),文本匹配失败就走「无法判定」。

## 9. 收尾核对

- [ ] `tailscale ip -4` 有 100.x;`serve status` 有那条 https;
- [ ] `netstat` 里 `100.x:443` LISTENING(owner = tailscaled);
- [ ] cordis.patch.yml 含 trustedHosts(**规范写法**:带 `...ctx.webRuntime.trustedHosts`;entry 是裸 `host[:port]`);DSH 已用**自带入口**重启;
- [ ] 控制台 policy 已收紧(§7):只剩「客户端 → 服务端 tcp:443」这一条;**设备只剩两台**;账号的 IdP 侧 MFA 已开;
- [ ] ACL 收紧**之后**又跑过一次验收:客户端侧 `<服务端 100.x>:443` = connected、隔离口(135/5357)= timeout(verify.md §1/§3);
- [ ] **浏览器侧确认**:客户端浏览器能打开 `https://<机器名>.<tailnet>.ts.net/`(cookie 没过期),且界面里目录选择器等 `/api` 功能不报 403;
- [ ] 电源策略已改(§8.1),**AC 与 DC 都查过**(§8.2 两条索引均应为 0x0);基线文件(§0)已存;
- [ ] 加固项复核:`Tailscale-Process` 的 `Edge=` 落库值 + `netsh advfirewall monitor show currentprofile` 里 Tailscale 网卡非 Public;
- [ ] 若这份 skill 要发布/共享:先跑 README「发布/共享前:零硬编码扫描」(真实 100.x 对端地址不得留在文件里)。
