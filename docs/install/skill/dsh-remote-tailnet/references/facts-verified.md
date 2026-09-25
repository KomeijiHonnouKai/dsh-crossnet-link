# 外部事实核实(写文档时不要凭记忆)

> 最后更新:2026-09-24 17:04(本机 DSH 会话,W4;本版只做了发布前脱敏:去掉对端机器名)。本次使用的命令见 `README.md` 的「本次修订」。

抓取日期:2026-09-23(如超过数月请重新核实)。

| 结论 | 出处 | 核实方式 |
| --- | --- | --- |
| `tailscale serve --bg` 持久:重启设备或用 `tailscale down/up` 重启后 **Serve 自动恢复**;不带 `--bg` 的必须手动重启 | https://tailscale.com/docs/reference/tailscale-cli/serve.md | 原文引用 |
| tailnet policy 的 selector 包含 **IP 地址 / CIDR**(除 users/groups/tags/autogroups 外),且在 `acls` 与 `grants` 的 `src`/`dst` 都允许 | https://tailscale.com/docs/reference/targets-and-selectors.md | 原文表格(IP address / CIDR 行 = Allowed: Yes) |
| `grants` 与 `acls` 可在同一 policy 文件中并存;`grants` 能做 `acls` 的一切 | https://tailscale.com/docs/reference/grants-vs-acls.md(由服务端 agent 经代理核实) | 抓取 |
| 当前 stable 版本仍为 **1.102.4**(本文档写作时) | https://pkgs.tailscale.com/stable/ | 页面版本串 |
| Tailscale 控制面不持有节点私钥、内容端到端加密;DERP 只转发密文 | https://tailscale.com/docs/concepts/can-tailscale-decrypt-traffic.md · https://tailscale.com/docs/reference/derp-servers.md | 原文引用 |
| 受损控制面理论上可换发密钥做中间人;对策 = Tailnet Lock | https://tailscale.com/docs/concepts/tailnet-lock-whitepaper.md | 原文引用 |

## 本文档自身实测(可复现,不是外部事实)

- Windows 上 `tailscale` CLI 在**普通用户窗口可跑**;受限的是 agent 沙箱(命名管道 `ProtectedPrefix\Administrators\...` 拒绝访问)⇒ 结论:不是「CLI 需要管理员」;
- `tailscale serve --bg 43120` 在 tailnet 侧监听 **443**,proxy 目标 `127.0.0.1:43120`;不新增 `0.0.0.0` 监听;
- DSH 的 `dsh-desktop.port` 默认 **43120**(schema 默认值;`settings.yaml` 里通常没有这个键 ⇒ 巡检要用实测监听,别读配置);
- 本链路在 DERP 中继下工作正常(实测 ~191–206ms);无直连不等于故障。

## 本轮新增实测(端到端,可复现)

- **`tailscale version` 能跑 ≠ CLI 可用**:同一个 exe,`version` 退出码 0(不需要守护进程),而 `ip -4` / `serve status` 退出码 1 并输出
  `Get "http://local-tailscaled.sock/localapi/v0/status": open \\.\pipe\ProtectedPrefix\Administrators\Tailscale\tailscaled: Access is denied.`
  ⇒ 脚本判定「CLI 可用性」**必须看 `ip`/`serve` 的退出码**,看 `version` 会误判成可用;而 CLI 被拒时的任何 TODO 都**不能**当成「未登录 / serve 未配置」。
- **监听面判据用实测,不读配置**:目标机 `netstat` 里 DSH 端口只出现在 `127.0.0.1:43120 LISTENING`,没有 `0.0.0.0:43120` ⇒ 与 `networkExposure: loopback` 一致。脚本用「精确匹配 `127.0.0.1:<port>` + 反查 `0.0.0.0`/`[::]`」两条一起判,比只匹配 `:<port>` 可靠(后者会被通配监听误命中)。
- **含中文的 `.ps1` 必须落盘为 UTF-8 with BOM**:BOM 丢失时 PowerShell 5.1 按 ANSI(GBK)读,`Parser::ParseFile` 会报出成片的**假**语法错(实测一次 17 条,而按 UTF-8 解码后 0 条)。修完脚本必做:`ReadAllBytes` 前三字节 = `239,187,191` 且 `ParseFile` 错误数 = 0。

## 服务端实测(对端机器:Win11 家庭版 25H2,2026-09-23;沙箱 workspace-write、非提权)

| 项 | 实测原文 | 判读 |
| --- | --- | --- |
| tailscale CLI 分层 | `version` → 首行 `1.102.4`,exit=0;`ip -4` → `open \\.\pipe\ProtectedPrefix\Administrators\Tailscale\tailscaled: Access is denied.`,exit=1 | `version` 读的是二进制自述、不碰守护进程 ⇒ **不能用来判 CLI 可用** |
| cmd 取退出码 | 同一条 `ip -4` 在 cmd 里 `%errorlevel%` = **0** | ⚠️ cmd 的 `%errorlevel%` 会被污染,**把失败读成成功**;判定请用 `$LASTEXITCODE` 或 `Start-Process -Wait -PassThru` 的 `.ExitCode` |
| 电源 STANDBYIDLE | AC `0x00000000`(永不)/ DC `0x00000e10` = 3600 s;`powercfg /a` 显示 S0 低电量待机「网络已断开连接」 | 交付措辞必须是**「市电中断 1 小时后链路必断」**,不能笼统写「已设不休眠」 |
| Tailscale-Process 规则 | `netsh advfirewall firewall show rule name=Tailscale-Process verbose` → Edge traversal: Yes;注册表原文 `Edge=TRUE` | 第 4 次独立复核一致;**核验判据必须是注册表出现 `Edge=FALSE`**,不可只看命令回显 |
| DSH 监听面 | `netstat -ano | findstr 43120` → `TCP 127.0.0.1:43120 … LISTENING 32388`;查 `0.0.0.0:43120` 无命中;**同刻入向连接 owner = PID 23488 = `tailscaled`** | loopback 独占成立;入向 owner=`tailscaled` 是「**serve 是唯一入口**」的活证据 |

**服务端做不了的三类(沙箱边界,不要猜结论)**:`tailscale serve status` / `ping`(命名管道隔离,与权限无关)、`powercfg /requests`(需管理员)、**任何 HTTPS/证书判定**(schannel `SEC_E_NO_CREDENTIALS`、`curl` 恒 `000`)⇒ **HTTPS 结论只能由客户端产出**。
