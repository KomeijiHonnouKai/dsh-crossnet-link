# dsh-remote-tailnet(DSH skill)

> 最后更新:2026-09-24 17:04。本次修订的文件与命令见文末「本次修订」。

跨网远程控制另一台 DSH:本机浏览器直接操作另一台机器上的 DSH 界面。

## 它解决什么

两台机器**不在同一网络**(例:一台在校园宽带,一台在手机热点),需要从其中一台操作另一台的 DSH。
方案:Tailscale 组私有网 + 服务端 `tailscale serve --bg` 把 DSH 的 loopback 端口暴露到 tailnet + 窄 ACL 单向 443 + 客户端浏览器带 token 打开一次换 30 天 cookie。
**不引入任何第三方中转、不让 DSH 监听 0.0.0.0、不需要装 DSH 插件。**

## 怎么用(给用户)

1. 装到 skill 根目录(二选一,**注意两处的生效优先级**见下节):
   - 项目级:`<工作区>\.dsh\skills\dsh-remote-tailnet\`(本仓库把这份 skill 放在
     `docs/install/skill/dsh-remote-tailnet/`,**要复制到下面两个位置之一才会被 DSH 扫到**)
   - 用户级:`%USERPROFILE%\.dsh\skills\dsh-remote-tailnet\`(对所有工作区生效)
2. 在对话里说「用 dsh-remote-tailnet」或直接描述场景,DSH 会加载 `SKILL.md` 并按其中步骤执行。
3. 也可以人工照着读:`SKILL.md`(总览)→ `references/server-setup.md` / `client-setup.md`(两端操作)→ `references/browser-control.md`(打通后操控对端)→ `references/verify.md`(验收)。

## ⚠️ 两处安装位置与生效优先级(装错地方等于没装)

同名 skill 在两处各有一份时,DSH 的装载规则是「按 rank 升序,首见者胜」:

| 副本 | rank | 在 `cwd = <工作区根目录>` 的会话里 |
| --- | --- | --- |
| 项目级 `<工作区>\.dsh\skills\dsh-remote-tailnet\` | 100(更优先) | ✅ **生效的就是这一份** |
| 用户级 `%USERPROFILE%\.dsh\skills\dsh-remote-tailnet\` | 400 | ❌ 被遮蔽(日志会写 `ignored because a higher-priority skill already exists`) |

反之,**`cwd` 不在那个工作区里的会话,只有用户级那份生效**。所以:你若在机器上装了两处,改完一处记得对齐另一处,**否则两处的行为会分叉**。

比对命令(逐文件 SHA256,两边应完全一致;`<工作区>` 换成你自己的路径):

    $a='<工作区>\.dsh\skills\dsh-remote-tailnet'; $b="$env:USERPROFILE\.dsh\skills\dsh-remote-tailnet"
    $fa=Get-ChildItem -Recurse -File $a | ForEach-Object { $_.FullName.Substring($a.Length).TrimStart('\') + ' ' + (Get-FileHash $_.FullName -Algorithm SHA256).Hash }
    $fb=Get-ChildItem -Recurse -File $b | ForEach-Object { $_.FullName.Substring($b.Length).TrimStart('\') + ' ' + (Get-FileHash $_.FullName -Algorithm SHA256).Hash }
    if (Compare-Object $fa $fb) { 'DIFFERENT' } else { 'IDENTICAL' }

同步命令(**以你正在用的那份为准**;另一处若在工作区之外,需用户自己确认后执行):

    Copy-Item -Recurse -Force '<工作区>\.dsh\skills\dsh-remote-tailnet\*' "$env:USERPROFILE\.dsh\skills\dsh-remote-tailnet\"

> **本版形态(不得含糊)**:仓库里的这份是**发布形态** —— 路径已占位化,不含任何开发机的具体路径、
> 机器名或 tailnet 名。开发机上自用的两份副本是**自用形态**(保留本机真实路径),与发布形态**本就分叉,
> 也不需要逐字节一致**;拿「两份必须一样」来核对仓库副本会得到错误结论。
> 你在自己机器上装完之后,**如果你同时装了两处**,请按上面的比对/同步命令让**它们俩**对齐 ——
> **不要凭记忆宣称「已生效」**。

## 目录

    SKILL.md                        总览:何时用、10 步快速路径、安全底线、故障顺序
    references/server-setup.md      服务端安装/配置/回滚(逐条命令)
    references/client-setup.md      客户端安装/取 token/首次打开 + 30 天 cookie 的续期与锁死路径
    references/browser-control.md   打通之后:浏览器操控对端(browser_* 首选 / ego_* 轻量查询)+ Session 日志导出读取
    references/security.md          威胁模型、预防清单、凭据生命周期与撤销、加固漂移、回滚
    references/verify.md            探针能力表(按探针)+ 三态/退出码 + soak + 巡检清单
    references/troubleshooting.md   链路故障速查(固定顺序 + 两端条目)
    references/automation.md        幂等脚本与「全自动」的真实边界(逐条对齐脚本实际行为)
    references/facts-verified.md    外部事实核实(带 URL 与抓取日期)
    scripts/server-setup.ps1        只检查 + 只打印(不装、不下载、不写文件);不产生任何改动
    scripts/verify.ps1              三态 + soak(纯 .NET),退出码 0=全通 / 1=降级 / 2=阻断

> 两个脚本都不要裸跑:`.\verify.ps1` 在默认 ExecutionPolicy(Restricted)下会被拒。用
> `powershell -NoProfile -ExecutionPolicy Bypass -File <路径> …`(见 automation.md §0)。

## 三条最容易忽视、但最要命的

1. **能打开服务端 DSH = 能操作那台机器** ⇒ 服务端 DSH 默认权限必须是 workspace-write(不是 danger-full-access)、tailnet 只放需要的设备、ACL 收紧到单向 443。
2. **带 token 的 URL 是凭据** ⇒ 不进入任何对话/日志/传输通道,只由用户在自己机器地址栏粘贴一次;30 天 cookie 是**绝对期限、不续期**,撤销落点见 security.md §4。
3. **服务端 `serve --bg` 与 `dsh-desktop.port`(默认 43120)必须保持不变** ⇒ 否则 443 监听消失、ACL 静默失效(控制面不报错),巡检判据要用 `tailscale serve status` + 443 LISTENING。

## 发布/共享前:零硬编码扫描

这份 skill 会被复制到别的机器,文件里**不得留任何真实对端地址 / 机器名 / tailnet DNS 名 / 用户主目录绝对路径 / 凭据值**(含 `*.ps1` / `*.psm1` / `*.md` / `*.json` / `*.js`)。发布或共享前跑一次(模式用字符串拼接拼出,免得扫描命令**自匹配**自己;五类口径与仓库 `tests/run-tests.ps1` §7 的模式表一致):

    $root = Join-Path $env:USERPROFILE '.dsh\skills\dsh-remote-tailnet'   # 或 '<工作区>\.dsh\skills\dsh-remote-tailnet'
    $pat = @(
      ('100\.'+'\d{1,3}\.\d{1,3}\.\d{1,3}'),            # 对端 IP
      ('[A-Za-z]:'+'\\Users\\[^\\]+'),                   # 用户主目录绝对路径
      ('DESKTOP-'+'[A-Z0-9]+|LAPTOP-'+'[A-Z0-9]+'),      # 工作站 / 笔记本式主机名
      ('[A-Za-z0-9-]+\.'+'tail[a-z0-9]+\.ts\.net'),      # tailnet DNS 名
      ('tskey-'+'[A-Za-z0-9]+')                          # 凭据值形状
    )
    Get-ChildItem -Recurse -File $root -Include *.ps1,*.psm1,*.md,*.json,*.js |
      Select-String -Pattern $pat |
      Where-Object { $_.Line -notmatch '100\.64\.0\.0/10' } |
      ForEach-Object { '{0}:{1}: {2}' -f $_.Path, $_.LineNumber, $_.Line.Trim() }

期望:**命中 0 条**(`100.64.0.0/10` 是 Tailscale 文档化网段,已在上面的 `Where-Object` 里放行)。
本仓库里这份副本实测 = **0 条**(2026-09-26,五类模式各做过一次正控:埋一条样例都能抓到)。

## 本次修订(W4,P1–P4)

**改了什么**(9 个文件):

| 文件 | 改动 |
| --- | --- |
| `SKILL.md` | 快速路径补 `-ExecutionPolicy Bypass -File` 形态;安全底线补 30 天 cookie 绝对期限;trustedHosts 规范写法 |
| `references/automation.md` | 新增 §0(受限策略下的可粘贴形态);§1 能力表逐条对齐脚本**实际行为**(MSI/serve/trustedHosts 三项改为「只打印」);补 verify.ps1 退出码表 |
| `references/verify.md` | §0.1 探针能力表改为**按探针**分栏(含 Node 不在 PATH 的替代、`ego_*` 120s 超时标注、结构化探针假阴性);删掉重复的 `## 5`;补退出码表、`Tailscale-Process` 与网卡归属巡检项 |
| `references/security.md` | 编号改为连续 1–7(原 3→5→4);新增 §4 凭据生命周期与撤销精确落点、§6 `trustedHosts` 规范写法与裸 `host[:port]` 告警、§5.5 网卡归属静默失效 |
| `references/client-setup.md` | §3.1 绝对 30 天(附源码行号)、§3.2 未到期时的续期路径、§3.3 到期 + 服务端重启后的锁死路径(必须到服务端机器前) |
| `references/server-setup.md` | §5 改规范 trustedHosts 写法 + 裸 authority 告警;§6 明确「查哪条规则/网卡归属」;§3 补假阴性判读纪律;§7 补 powercfg 本地化坑 |
| `references/troubleshooting.md` | §2 新增「查不到 ≠ 不存在」「别用区域预判语言」「加固查对规则名」三条;§3 静默失效表补网卡归属行 |
| `references/facts-verified.md` | 发布前脱敏:去掉对端机器名(内容结论未改) |
| `scripts/verify.ps1` | 头部改为 `-File` 形态 + 去掉写死的真实对端 IP;新增 `-LinkPort`;退出码 0/1/2 + `VERDICT`/`EXIT` 行;修掉 `-File` 下 `[int[]] -Ports` 把 `135,5357` 绑成 `1355357` 的静默少探缺陷(改字符串切分 + 阻断);`-ServerIp` 不再用 Mandatory(避免漏参时弹交互提示) |
| `scripts/server-setup.ps1` | 头部改为 `-File` 形态;端口判定改「TcpClient 真连 + netstat 行结构」(不依赖 `LISTENING` 本地化文本);§5 改显式 profile 名/`DSH_HOME`/`-ProfileDir` 优先级链(去掉 `Select-Object -First 1`);§6 标题与项数一致(四件) |
| `README.md` | 本节 + 两处安装位置与生效优先级 + 比对/同步命令 + 本版形态声明 + 零硬编码扫描 |

### t18 补充修订(2026-09-24,skill 侧 F1/F2)

| 文件 | 改动 |
| --- | --- |
| `references/security.md` | **F1**:§7 第 2 步把**不存在的 `off` 子命令**改为 `tailscale serve reset` 并写明语义;**F2**:新增 §4.1「撤销的实际操作顺序」(清客户端 cookie → 删服务端 `$DSH_HOME\.credentials.yaml` 里 `client-connection`/`browser-session` 记录 → 重启 DSH),并明确两条边界:`serve reset` 不碰凭据、**仅重启 DSH 不会让已发出的 cookie 失效** |
| `references/server-setup.md` | **F1**:§4 回滚命令 → `tailscale serve reset` + 语义 |
| `scripts/server-setup.ps1` | **F1**:§4「serve 未配置」分支回显的回滚命令 → `tailscale serve reset` + 语义 |

依据(本机实测,原始输出见 t18 记录):`tailscale serve --help`(exit=0)的 USAGE 只有 `<target>` / `status [--json]` / `reset`,**没有 `off`** —— 原来的回滚命令用了一个**并不存在的子命令**,真跑起来只会报错 ⇒ 那是一条**跑不通**的回滚命令。

**本次实际执行过的命令**(用于产出上述结论,可复现):

    # P1 证据:裸调用在默认策略下被拒
    powershell -NoProfile -Command "& .dsh\skills\dsh-remote-tailnet\scripts\verify.ps1 -ServerIp 127.0.0.1"
    # ⇒ cannot be loaded because running scripts is disabled on this system (PSSecurityException / UnauthorizedAccess)
    powershell -NoProfile -Command "Get-ExecutionPolicy -List"     # 五个 Scope 全 Undefined ⇒ 生效值 Restricted

    # 交付脚本的可跑形态与退出码(<PEER_IP> = 对端 tailnet 100.x;本 skill 文件里不写死真实地址)
    powershell -NoProfile -ExecutionPolicy Bypass -File .dsh/skills/dsh-remote-tailnet/scripts/verify.ps1 -ServerIp <PEER_IP>
    # 实测(2026-09-24,对端在线):443 connected 212–627ms;135 timeout ~5.0s;5357 timeout ~5.0s ⇒ VERDICT 全通 / EXIT 0
    powershell -NoProfile -ExecutionPolicy Bypass -File .dsh/skills/dsh-remote-tailnet/scripts/verify.ps1 -ServerIp 127.0.0.1                                      # ⇒ EXIT 2(443 refused)
    powershell -NoProfile -ExecutionPolicy Bypass -File .dsh/skills/dsh-remote-tailnet/scripts/verify.ps1 -ServerIp 127.0.0.1 -LinkPort 135 -Ports 135,5357          # ⇒ EXIT 1(隔离口也 connected)
    powershell -NoProfile -ExecutionPolicy Bypass -File .dsh/skills/dsh-remote-tailnet/scripts/verify.ps1 -ServerIp 127.0.0.1 -LinkPort 135 -Ports 135                # ⇒ EXIT 0(全通)
    powershell -NoProfile -ExecutionPolicy Bypass -File .dsh/skills/dsh-remote-tailnet/scripts/verify.ps1 -ServerIp 127.0.0.1 -LinkPort 43120 -Ports 43120 -Soak -Count 3 -IntervalSeconds 2   # ⇒ EXIT 0(3/3 connected)
    powershell -NoProfile -ExecutionPolicy Bypass -File .dsh/skills/dsh-remote-tailnet/scripts/verify.ps1 -ServerIp 127.0.0.1 -Ports 135 -Soak -Count 3 -IntervalSeconds 5                      # ⇒ EXIT 2(soak 全失败)
    powershell -NoProfile -ExecutionPolicy Bypass -File .dsh/skills/dsh-remote-tailnet/scripts/verify.ps1                                                            # ⇒ EXIT 2(-ServerIp 为空,不弹交互提示)
    powershell -NoProfile -ExecutionPolicy Bypass -File .dsh/skills/dsh-remote-tailnet/scripts/verify.ps1 -ServerIp 127.0.0.1 -Ports 135 5357
    # ⇒ 未加引号时第二个值被绑到 -LinkPort:VERDICT 报「未探测 -LinkPort 5357」/ EXIT 2(不静默少探;多值请写 -Ports 135,5357)

    # 编码与语法复验(两个 .ps1)
    powershell -NoProfile -Command '$f=".dsh/skills/dsh-remote-tailnet/scripts/verify.ps1"; $b=[IO.File]::ReadAllBytes((Resolve-Path $f)); $e=$null; [void][Management.Automation.Language.Parser]::ParseFile((Resolve-Path $f),[ref]$null,[ref]$e); "bom=" + ($b[0..2] -join ",") + " errors=" + @($e).Count'   # ⇒ bom=239,187,191 errors=0
    powershell -NoProfile -Command '(Select-String -Path ".dsh/skills/dsh-remote-tailnet/references/verify.md" -Pattern "^## 5\." | Measure-Object).Count'   # 修订前 2 → 修订后 1

    # 本机 Node 不在 PATH 时的 TLS 探针替代(实测可用)
    cmd /c "set ELECTRON_RUN_AS_NODE=1&& \"<APP_DIR>\DSH Desktop.exe\" -e \"console.log('node='+process.version+' zstd='+(typeof require('zlib').createZstdDecompress))\""   # ⇒ node=v24.18.1 zstd=function
