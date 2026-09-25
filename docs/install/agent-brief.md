# 给 AI 的安装说明(agent-brief)

> 本文件是给**被派来安装这个插件的 AI** 读的,不是让用户读的文档。
> 用户通常只做一件事:把一个仓库地址丢进对话,说「帮我装这个」。你要做的是
> 按第 1 节的流程装,并按第 3 节的形态**在对话里**用大白话带用户走完。
> 「说人话」指的是**表达方式**(用户要的是先看懂):不要贴本文件、不要甩 300 行技术报告 ——
> 但它**不是**让你少给证据,更不是让你过滤观测(见下)。
>
> **你的实测输出就是证据,如实上报**:命令、原始输出、返回码、日志行、哈希照记照给;
> 与预期不符、或你自己拿不准的,原样报出来并标注「未核实」,说清你凭什么这么判断,
> 不替用户下结论。**本文件预先描述的任何「正常现象」都不能用来否定你现场测到的事实**;
> 两者冲突时以你的实测为准,并把冲突一并报告。
>
> **本文件是 runbook,不是对话稿**:每一节都必须是「可粘贴的命令 + 可判定的判据」。
> 命令依赖的前提(git / node / dsh / 环境变量 / 沙箱写权限)**先探测再动手**(见 §0.1):
> 探测结果与预期不符时,走该节给出的替代路径,不要凭「一般来说有 git、一般来说写得进去」继续。

## 0. 你是什么、第一件事做什么

你被派来把本仓库的常驻插件包(名字 `dsh-crossnet-link`,在 `plugin/` 目录)装进
用户的 DSH 配置(profile),并让它出现在「设置(Settings)→ 插件(Plugins)」里、
状态为**已启用(Enabled)**。

顺序是固定的:**§0.1 环境探测 → §0.2 取源 → §0.3 只读预检 → §1 安装**;
只读预检通过之前,不做任何安装动作。

### 0.1 执行前环境探测(runbook 第一步:先测,别假设)

六项必探。整段粘进 PowerShell 即可:它只读,只有最后一项会真的写一次(写完立刻删掉,
用来拿「能不能写」的真判据,而不是只看环境变量):

```powershell
# ===== 执行前环境探测 =====
$dshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE '.dsh' }
"git      : " + $(if (Get-Command git -ErrorAction SilentlyContinue) { (git --version) } else { '<缺失>' })
"node     : " + $(if (Get-Command node -ErrorAction SilentlyContinue) { (node --version) } else { '<缺失>' })
"dsh      : " + $(if (Get-Command dsh -ErrorAction SilentlyContinue) { (Get-Command dsh).Source } else { '<缺失>' })
"DSH_HOME : $dshHome  (env: " + $(if ($env:DSH_HOME) { 'DSH_HOME' } else { '未设置 -> 默认 ~\.dsh' }) + ")"
"WEB_URL  : " + $(if ($env:DSH_WEB_URL) { $env:DSH_WEB_URL } else { '<未设置 -> 端口按内置默认 43120,标注未实测>' })
"沙箱模式 : " + $(if ($env:DSH_PERMISSION_MODE) { $env:DSH_PERMISSION_MODE } else { '未设置 -> DSH 默认 workspace-write' })

# 工作区外写权限:判据是「真的写一次」
$probe = Join-Path $dshHome ('.dsh-write-probe-' + $PID)
try {
  [IO.File]::WriteAllText($probe, 'probe', (New-Object Text.UTF8Encoding($false)))
  Remove-Item -LiteralPath $probe -Force -ErrorAction Stop
  '写入探测 : 允许 —— 可以写 <DSH_HOME>,继续 §0.2 / §1'
} catch {
  '写入探测 : 被拒 —— ' + $_.Exception.Message
  '            <DSH_HOME> 在工作区外,默认沙箱(workspace-write)不让你写。'
  '            不要因此跳过备份直接装:把探测结果与第 1 节的命令交给用户,请他在自己的终端里执行。'
}
```

逐项判据、以及不符时怎么办:

| # | 必探项 | 判据 | 不符时怎么办 |
|---|---|---|---|
| 1 | `git` | `git --version` 打印 `git version …` | **没有 git 也能装**:走 §0.2 的替代取源路径;不要把「先装 git」当成前置条件塞给用户 |
| 2 | `node` | `node --version` 打印 `v…` | 影响很小:预检里 3 条 `node --check` 会打印 `[SKIP]`(计入 skipped、**不改退出码**);安装本身不需要 node,照常继续 |
| 3 | `dsh` | `Get-Command dsh` 打出路径 | 不在 PATH 时:让用户在**他自己的终端**里跑(用户 shell 里通常有),或用 DSH Desktop 自带的入口;别凭「`dsh` 应该能用」往下走 |
| 4 | `$env:DSH_HOME` | 有值就用它;空 ⇒ 退到 `$env:USERPROFILE\.dsh` | 全程用它解析 `<DSH_HOME>`,**不要写死**任何用户主目录路径 |
| 5 | `$env:DSH_WEB_URL` | 形如 `http://127.0.0.1:43120`;端口就是本机 DSH 端口 | 为空**不是故障**:退到内置默认 `43120`,并在给用户的结论里写明「用的是默认值、未实测」 |
| 6 | 沙箱模式 + 工作区外写权限 | `$env:DSH_PERMISSION_MODE`(空 ⇒ DSH 默认 `workspace-write`)**加上**写探测成功 | 写探测被拒 ⇒ 本轮**不要**自己执行第 1 节的写命令(备份 / 装包 / 追加启用行),改由用户执行;本会话允许审批时,为这一次操作申请授权升级 |

> 为什么必须真写一次:`$env:DSH_PERMISSION_MODE` 是**配置值**,为空时只能按默认推断;
> 而 `<DSH_HOME>` 在工作区外,`workspace-write` 下写它必然被拒。
> `Test-Path` 这类只读探测看得见文件,**代表不了写得进去**。

### 0.2 取源:有 git 用 clone,没有 git 走替代路径

目标目录名必须是 `dsh-crossnet-link`(采集器靠目录名回溯定位),且尽量落在**工作区内**(可写)。

**a) 有 git**(§0.1 第 1 项不是 `<缺失>`):

```powershell
git clone https://github.com/KomeijiHonnouKai/dsh-crossnet-link dsh-crossnet-link
cd dsh-crossnet-link
# 期望:克隆成功,进入目录
```

**b) 本机 / 对端已经有这份 checkout**:直接用现有目录(别处克隆过、或用户手上已有一份都算),
不必重复下载;用 `Test-Path <目录>\panel\plugin-preflight.ps1` 确认真的是仓库根。

**c) 用 HTTP 拉 ZIP(没有 git 时最通用的替代)**:

```powershell
# 下到工作区内(工作区内一定可写),解压,再把顶层目录改成仓库要求的名字
Invoke-WebRequest -Uri 'https://github.com/KomeijiHonnouKai/dsh-crossnet-link/archive/refs/heads/main.zip' -OutFile '.\dsh-crossnet-link.zip'
Expand-Archive -LiteralPath '.\dsh-crossnet-link.zip' -DestinationPath '.' -Force
Rename-Item -LiteralPath '.\dsh-crossnet-link-main' -NewName 'dsh-crossnet-link'
Test-Path '.\dsh-crossnet-link\panel\plugin-preflight.ps1'      # 期望:True
```

代价说清楚:这条路拿到的副本里**没有 git 元数据,不能 `git pull` 升级**,只能重新下一次。
(解压出来的顶层目录名跟着分支走:下的是 `main` 就是 `dsh-crossnet-link-main`;
换成别的分支/标签时,`Rename-Item` 的源名要相应改。)

**d) 以上都不可用**:请用户把仓库整个目录放进工作区(工作区内可写),**不要**把仓库写到工作区外再折腾权限。

**目录已存在时先改名保留,不要直接覆盖**:

```powershell
Rename-Item -LiteralPath '.\dsh-crossnet-link' -NewName ('dsh-crossnet-link.bak-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
```

覆盖会静默吞掉你或用户的旧副本(对端实测遇到过预存的同名目录)。

### 0.3 只读预检(preflight)

```powershell
# $repo = 克隆出来的 dsh-crossnet-link 目录(它下面有 panel\、plugin\、src\)
$repo = '<克隆出来的 dsh-crossnet-link 目录>'
powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'panel\plugin-preflight.ps1')
```

期望:打印 `checks: 66  passed: 66  failed: 0`,最后一行 `exit code: 0`。

- 退出 0:继续。
- 退出 1:只有告警(缺 `docs/install/plugin-package.md`),包仍可装;先向用户说明再继续。
- 退出 2:停下。把脚本里 `[FAIL]` 开头的行转述给用户,不要继续装,也不要擅自"修"仓库代码。

> 调用方式也算契约:必须用 `-File`。用 `-Command "& '<脚本>'"` 或点源调用时,
> PowerShell 会把退出码改写成 1 —— 那时以脚本打印的 `exit code:` 那一行为准。

## 1. 装机流程:装 → 启用 → 重启 → 核对两格

包在仓库里默认是**禁用(disabled)**的,这是刻意的安全默认:禁用时它不会加载,
装上弄不坏任何东西。所以"安装"= 下面这几条命令,它们把**启用**一起做完,
用户不需要手工改任何文件。全程让用户在**他自己的终端**里执行,你逐条贴、逐条解释。

### 1.1 先拿到用户的安装同意(红线 1 落地的话术)

动手之前先问清三件事,**三件都有明确回答再继续**:

1. **装到哪个 profile** —— 默认 `desktop`;用户有多个 profile 时问用哪个;想完全不碰日常环境就提议先用一次性 profile(见 `plugin-package.md` §8)。
2. **装完要不要立刻启用** —— 不启用 = 装上了也不加载;启用 = 重启后生效。
3. **谁来执行写命令** —— 若 §0.1 的写探测被拒,就是「需要你在自己的终端里跑这几条」,而不是「我直接装」。

可直接改写的话术:

> 我要在你机器上装一个常驻插件(`dsh-crossnet-link`)。先说清楚它动什么,你点头我再动手:
> ① 装的位置:DSH 的 profile 目录(默认 `desktop`,即 `<DSH_HOME>\profiles\desktop`)。你有别的 profile 的话告诉我用哪个;想完全不动日常环境,我可以先用一次性 profile 试。
> ② 会改哪些文件:那个 profile 的 `cordis.patch.yml`(追加三行启用行;装之前整文件备份,回滚 = 删掉那三行)、`package.json` / `pnpm-lock.yaml` / `node_modules`(安装依赖),以及 `<DSH_HOME>\settings.yaml` 会多一段 `dsh-crossnet-link:`(插件首次加载的自动配置落点,属预期)。
> ③ 装完是否立刻启用:不启用就是「装上了也不加载」,什么都不做。
> ④ 如果你机器上不允许我写 `<DSH_HOME>`,我会把命令列出来,由你在自己的终端里跑。
> 随时可以让我停:回滚 = 删掉那三行 + `dsh plugin --profile <profile> remove dsh-crossnet-link`。

### 1.2 权限前置:本流程会写工作区外

- 会写 **`<DSH_HOME>`(工作区外)**:①备份 profile 的补丁文件;②`dsh plugin … add` 写 profile 的
  `package.json` / `pnpm-lock.yaml` / `node_modules`;③把启用覆盖行追加进补丁文件。
- `workspace-write` 沙箱下这些操作会被拒。**判据 = §0.1 第 6 项的写探测**,不是「大概能写」。
- 被拒时两条路:让用户在**非沙箱终端**里执行这几条;或(本会话允许审批时)为这一次操作申请授权升级。
- **被拒时绝不「跳过备份继续装」**:备份是整条流程里唯一的回滚点,没有它就没有退路。

### 1.3 四条命令:备份 → 装包 → 启用 → 验证

```powershell
# 0) 先固定变量:仓库目录、profile 名、要动的那几个文件
$repo    = '<克隆出来的 dsh-crossnet-link 目录>'      # 它下面有 panel\、plugin\、src\
$profile = 'desktop'                                  # 默认 desktop;用户有多个就问用户用哪个
$dshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE '.dsh' }
$p       = Join-Path $dshHome "profiles\$profile\cordis.patch.yml"
$plugin  = Join-Path $repo 'plugin'

# 1) 备份 profile 的补丁文件(回滚就靠它,不能省)
#    判据不是「命令没输出」,而是「文件确实存在、字节数非 0、SHA256 与原文件一致」
$bak = $p + '.bak-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
Copy-Item -LiteralPath $p -Destination $bak -Force -ErrorAction Stop          # 关键:-ErrorAction Stop
$item = Get-Item -LiteralPath $bak -ErrorAction Stop
if ($null -eq $item -or $item.Length -le 0) { throw "备份失败:$bak 不存在或长度为 0 —— 停下,不要继续装" }
$srcHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash
$bakHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $bak).Hash
if ($srcHash -ne $bakHash) { throw "备份与原文件不一致 —— 停下:$bak" }
"备份 OK:$($item.FullName)  $($item.Length) 字节  SHA256 $bakHash"
# 期望:打印一行「备份 OK:<路径> <字节数> 字节 SHA256 <64 位十六进制>」;两个哈希必须相等

# 1b) 备份必须留下「三条都能证明成功」的证据(缺一条都不算备份成功)
Test-Path -LiteralPath $bak -PathType Leaf                                    # ① 文件确实存在
(Get-Item -LiteralPath $bak).Length -gt 0                                     # ② 字节数非 0
$newest = Get-ChildItem -Path ($p + '.bak-*') | Sort-Object CreationTime, Name | Select-Object -Last 1
$newest.Name                                                                  # ③ 能列出备份,且取到的是最新那次
if ($newest.Name -ne (Split-Path -Leaf $bak)) { throw "取到的最新备份不是刚写的那份:$($newest.Name)" }
# 期望:① True;② True;③ 打印刚生成的 .bak-<时间戳> 名字(与 $bak 同名);不同名就停下,以 $bak 为准
# ③ 的两个坑:通配只能用 -Path(-LiteralPath 不通配,结果永远是空);
#            排序键必须是 CreationTime(不能用 LastWriteTime,见下方坑注 ②)。

# 2) 把包装进 profile(会写 profile 的 package.json / pnpm-lock.yaml / node_modules)
dsh plugin --profile $profile add ('link:' + $plugin)
# 期望:pnpm 打印安装过程,最后没有报错;装完确认 bundles 列表里有它
(Get-Content -LiteralPath (Join-Path $dshHome "profiles\$profile\package.json") -Raw | ConvertFrom-Json).dsh.profile.bundles
# 期望:列表里出现 dsh-crossnet-link

# 3) 把"启用覆盖行"追加到 profile 补丁文件末尾(这就是启用这一步)
[IO.File]::AppendAllText($p, "`n- id: dsh-crossnet-link`n  name: dsh-crossnet-link`n  disabled: false`n", (New-Object Text.UTF8Encoding($false)))
# 判据不是「无输出」——「没报错」只说明这条命令本身没抛异常,证明不了那三行真的落进了**这个**文件
# (写到了别的文件、只写了一半、行名写错,都是"无输出");必须读回来核对:
$lines = @(Get-Content -LiteralPath $p)
$idx   = [array]::IndexOf($lines, '- id: dsh-crossnet-link')
$rowOk = $false
if ($idx -ge 0 -and $idx + 2 -lt $lines.Count) {
  $rowOk = ($lines[$idx+1].Trim() -eq 'name: dsh-crossnet-link') -and ($lines[$idx+2].Trim() -eq 'disabled: false')
}
if (-not $rowOk) { throw "启用三行没有落盘(命令无输出 != 成功)—— 停下,不要继续:$p" }
"启用行已落盘(读回核对):$p"
# 期望:打印「启用行已落盘(读回核对):<路径>」;没打印就停下,不要当成「已经启用过了」

# 4) 验证:组合后的配置里能看到这一行,且已启用(注意:这条命令不是只读的,见下)
dsh --profile $profile --dump-config | Select-String -SimpleMatch 'dsh-crossnet-link' -Context 0,4
# 期望:能看到 id/name 是 dsh-crossnet-link、disabled: false 的那一行
```

四条命令各自的坑,**每一条都必须知道**:

> **① `Copy-Item` 被拒是「非终止错误」,后面照常打印 ⇒ 假成功。**
> 备份失败在 PowerShell 里默认只往错误流写一行红字,**脚本不会停**:它后面的
> `Write-Output "backed up: …"` 照常执行 —— 于是你打印出「三行备份成功」,而**文件根本不存在**
> (对端实测踩到过:最后是随后的 `Get-Item` 才暴露出来)。
> 而且 `try/catch` **默认抓不到它**(非终止错误在 `try {} catch {}` 里直接走完,
> 不加 `-ErrorAction Stop` 不会被捕获)。所以判据只能落在事后检查上:
> **文件存在 + 字节数非 0 + SHA256 一致**(再加第 1b 步的「取到的是最新那次」),
> 任一不满足 = 没备份成功 = 停下。
>
> **② 取「最新备份」要 `-Path` + `CreationTime`,不能 `-LiteralPath` + 通配。**
> 这条命令上叠了两个坑:
> ·`-LiteralPath` **不做通配**(它按字面路径找):把带 `*` 的路径交给它,结果**永远是空**;
> 实测同一目录:用 `-LiteralPath` → **count = 0**,换成 `-Path` → **count = 2**。
> ·`Copy-Item` **保留源文件的 `LastWriteTime`**,同一源文件备份两次,这两个备份的
> `LastWriteTime` **完全相同** ⇒ 按 `LastWriteTime` 排序**分不出谁新**;实测:两个备份的
> LastWriteTime 去重后只剩 1 个值,而排序取「最新」拿到的是**更早**那一次(要的是 `-100100`,
> 它给的是 `-100000`)。
> 正确写法(通配用 `-Path`,排序键用 `CreationTime`,逗号后的 `Name` 兜秒级并列 ——
> 文件名里就是 `yyyyMMdd-HHmmss`):
> `Get-ChildItem -Path ($p + '.bak-*') | Sort-Object CreationTime, Name | Select-Object -Last 1`。
> 回滚时**认你自己刚记下的那个 `$bak` 路径和 SHA256**,不要靠「取最新」。
>
> **③ `dsh --profile <profile> --dump-config` 不是只读操作。** 它内部会 `writeFileSync`
> 到那个 profile 的 `cordis.yml`。在只读沙箱下它会失败,而且错误文本长这样:
> `failed to start packaged dsh: Error: EPERM: operation not permitted, open '…\cordis.yml'` ——
> **读起来像「配置坏了」,其实是权限问题**。别照这个方向去「修配置」:先按 §0.1 确认能不能写
> `<DSH_HOME>`,或把这条命令交给用户在非沙箱终端里跑;只读的替代判定见 §1.5 自查三条。
>
> **④ `link:` 会在 profile 里建 junction,目标路径从此固定。** `add 'link:<仓库路径>\plugin'`
> 记下的是**那个路径本身**:①不要装到临时目录再删 —— 目录一删,profile 里的 junction 立刻
> **悬空**,插件加载失败;②仓库目录在插件启用期间不要移动、改名、删除;③要换位置就先
> `dsh plugin --profile <profile> remove dsh-crossnet-link`,挪好再重新 `add`。

然后请用户**重启 DSH**(用 DSH 自带菜单:设置 → 桌面 → 重启;或退出应用再打开)。
这一步只有人能做。重启后按下面「两格」核对。

> 小坑(实测):刚初始化的新 profile 的补丁文件内容是一行 `[]`(空数组)。追加第 3 条之前,
> 如果文件里就这一行 `[]`,先把它删掉再追加,避免数组里多出一个空项。

### 1.4 装完看到什么(两格;侧边栏 tab 是新增的可选接入面)

本插件在**设置 → 插件**里**只贡献一张可配置卡片**（与别的插件一致），**不新增设置页左侧导航条目**（侧边栏 tab 是新增接入面：装了可选依赖 `dsh-better-sidebar` 才出现，未装时没有 tab、不报错、也不进 waiting）；两格如下：

| 格 | 位置 | 判据 |
|---|---|---|
| ① 插件清单 | 设置(Settings)→ 插件(Plugins),第一个标签页 | 清单里有 `dsh-crossnet-link`,状态显示**已启用(Enabled)**。装完但没启用时它也会在清单里(标"未启用"),所以这一格要认准"已启用"三个字 |
| ② 可配置插件卡片 | 设置 → 插件 → 「可配置插件」标签页 | 一张折叠卡片:**标题 = 插件显示名 `dsh-crossnet-link`,副标题 = 这个插件的目的**(两台 DSH 联动、agent 对 agent —— 在 A 电脑的 DSH 里,通过浏览器插件驱动一个已登录的通道页面,直接操作 B 电脑上运行的 DSH);点开是**它自己的设置表单**(本机在这条链路里的位置 / 对端与 tailnet / 体检口径 / 高级,共 14 项,底部「保存 / 放弃」),**不是报告面板**。卡片要 host 半边把**带字段 schema** 的设置命名空间注册成功才渲染,这一步要能在 profile 侧解析到 schema 库(实测:profile 里已有其它插件时通常解析得到,卡片就出现;解析不到时只打一条 warning、卡片不出现(依据:卡片要渲染,得「host 注册命名空间」与「client 以同名字符串注册座位」同时成立,缺一条就不渲染;而 ① 的清单由平台自带,只认 profile 里有没有这一行,**与命名空间是否注册无关**)。卡片缺席是可能的降级路径,但它**既不等于「装好了」、也不等于「没事」**:把 ① 的清单状态、日志里那一行是 `[I]` 还是 `[W]`、`settings.yaml` 里有没有该段,**三样一起报出来**,并标明哪些是你实测的、哪些是推断的 |

安装后,本机会自动探测并填好 `port` / `profile` / `dshHome` / `appDir` 四项;对端两项(`peer` / `peerName`)与 `role` 仍需手填。

### 1.5 安装后自查三条(不看界面也能判定)

界面看不到、或者你不在那台机器前时,用下面三条**可复制的判据**代替「看一眼」:

```powershell
$dshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE '.dsh' }
$date = (Get-Date).ToString('yyyy-MM-dd')

# ---- ① 宿主日志里的插件行(注意层级:插件行在 host\ 子目录,见下) ----
# 日志根目录 = DSH 自己的日志目录(DSH Desktop 实测在 %APPDATA%\DSH Desktop\logs;
# CLI 形态可能在 <DSH_HOME>\logs)。当天会有两个同名文件,挑**最大的那个** —— 它就是 host\ 里的:
$logRoot = Join-Path $env:APPDATA 'DSH Desktop\logs'
if (-not (Test-Path -LiteralPath $logRoot)) { $logRoot = Join-Path $dshHome 'logs' }
Get-ChildItem -LiteralPath $logRoot -Recurse -Filter "dsh-$date.log" -ErrorAction SilentlyContinue |
  Sort-Object Length -Descending | Select-Object -First 3 FullName,Length
$hostLog = (Get-ChildItem -LiteralPath $logRoot -Recurse -Filter "dsh-$date.log" -ErrorAction SilentlyContinue |
  Sort-Object Length -Descending | Select-Object -First 1).FullName
if ($hostLog) { Select-String -LiteralPath $hostLog -SimpleMatch 'dsh-crossnet-link' | ForEach-Object { "$($_.LineNumber): $($_.Line)" } }

# ---- ② settings.yaml 里有没有这个插件的 section ----
Select-String -LiteralPath (Join-Path $dshHome 'settings.yaml') -SimpleMatch 'dsh-crossnet-link' -Context 0,6 -ErrorAction SilentlyContinue

# ---- ③ 直接调用插件路由(POST;首次会慢,它要拉起一个采集进程) ----
$port = if ($env:DSH_WEB_URL -match ':(?<p>[0-9]{2,5})') { $Matches['p'] } else { 43120 }
try {
  $r = Invoke-WebRequest -Uri "http://127.0.0.1:$port/dsh-crossnet-link/api/posture" -Method POST `
        -ContentType 'application/json' -Body '{}' -UseBasicParsing -TimeoutSec 120
  "HTTP $($r.StatusCode)  body=" + $r.Content
} catch {
  $resp = $_.Exception.Response
  if ($resp) { "HTTP $([int]$resp.StatusCode)(无/有响应体决定含义,见下表)" } else { "请求失败: " + $_.Exception.Message }
}
```

| # | 判据 | 期望看到 | 不符时的读法 |
|---|---|---|---|
| ① | 宿主日志(**在 `host\` 子目录里**) | `dsh-crossnet-link: read-only posture route ready at /dsh-crossnet-link/api` 是 **`[I]`**;`settings namespace "dsh-crossnet-link" registered …` 是 **`[I]`**;`auto-config wrote N machine setting(s) (…)` 是 **`[I]`** | 路由那行缺失 ⇒ 报「路由行没出现」,并把你查到的插件行状态与重启情况一起给出;命名空间那行若是 `[W]`(措辞含 `no schema library reachable` / `skipped`)⇒ 这说明 schema 库没解析到(机制见 §1.4),把**原始行**与你的判断一起报;`auto-config skipped` / `undetected, left blank` / `write failed` 是 `[W]` —— 原文照给并注明「自动配置没落全」这个事实;要不要处理、要不要回退这一步,按你手上的证据判断,**本表不预设它无害** |
| ② | `<DSH_HOME>\settings.yaml` 里出现 `dsh-crossnet-link:` 顶层 section | auto-config 会填 4 个机器可探测的键(`port` / `profile` / `dshHome` / `appDir`);对端两项与 `role` 由用户在卡片里填 | 完全没有这段:回头看 ① 的 auto-config 行,并把「没有这段」当成一条要报告的观测;有这段时,它属于 auto-config 的落点(依据见红线 3)—— 是否与预期副作用相符,按你实测到的证据判断,不确定就标「未核实」 |
| ③ | 直接 POST 插件路由 | `HTTP 200` + JSON(`ok: true` / `source: plugin:dsh-crossnet-link` / `summary` / `checks`) | `exitCode` 是 1 或 2 表示**采集器的判定**(有降级/阻断)—— 依据:handler 一律以 HTTP 200 返回结果,`exitCode` 来自被它拉起的采集器,所以它不代表路由失败;返回 `401` 或要 token ⇒ 这一版 DSH 的 web 认证先拦下了,改在已登录的 DSH 页面里 fetch 同一 URL |

> **③ 的特殊读法(这条容易误判)**:`405` 有两种完全不同的来源 ——
> ①**响应体是插件的 JSON**(`{"ok":false,"code":"method-not-allowed","message":"POST only"}`)⇒ 请求进到了
> 插件 handler,路由**在**(这正是本插件路由不经 DSH web 认证的旁证:对端实测 `GET /` 返回 401、而
> `GET` 这条路由直接由插件 handler 回答 405);
> ②**响应体是空的** 405 / 404 ⇒ 这台 DSH 的 web 服务器在说「这个路径没有处理器」,**路由根本没挂上**
> (本机实测:插件未启用时,对任意路径 `GET` 得 404、`POST` 得 405,响应体都是空的)。
> **所以必须看响应体,不能只看状态码。**
>
> ⚠ **日志层级别搞错**:外层 `logs\dsh-<日期>.log` 只有启动横幅(本机实测 756 字节),
> **插件相关行在 `logs\host\dsh-<日期>.log`**(本机实测 8 万+ 字节)。拿错文件会一无所获 ——
> 这正是「为什么我看不到卡片」排障时最常见的浪费。

## 2. 装完看不到时,按顺序查这 3 条

1. **没重启**:改了配置不重启就没生效 → 让用户从 DSH 自带菜单重启一次。
2. **启用行没生效**:让用户跑
   `dsh --profile <profile> --dump-config | Select-String -SimpleMatch 'dsh-crossnet-link'`,
   看不到 `disabled: false` 就是第 1 节第 3 条没跑、或跑到了别的文件上。
   (这条命令**会写** profile 的 `cordis.yml`,只读沙箱下报 `EPERM` —— 那是权限,不是配置坏。)
3. **client 半边 / 路由没起来**:按 **§1.5 自查三条**走一遍 —— 宿主日志里的插件那几行、
   `settings.yaml` 里的 `dsh-crossnet-link:` 段、直接 POST 一次路由。
   要用户把日志发给你时,**说清是 `logs\host\` 子目录里那个**:`dsh-crossnet-link` 相关的行在
   `logs\host\dsh-<日期>.log`,外层 `logs\dsh-<日期>.log` 只有启动横幅。

## 3. 对话输出模板(四段;正文 ≤ 15 行,代码块另计)

你回复用户的**第一屏**必须是下面四段,顺序不许变:

1. **现在什么情况**(2 句):先说**这个插件的目的**(在 A 电脑的 DSH 里驱动一个已登录的通道页面、直接操作 B 电脑上运行的 DSH,两台 DSH 联动、agent 对 agent),再说**本仓库这一半的角色**(这条链路的只读体检:只读、只报告、不改任何配置)—— 两层分开说,不要把角色句当目的;然后说装或不装意味着什么。
2. **我要做什么**(编号步骤):每步一句人话 + 一条命令 + 一行期望结果(照第 1 节的四条)。
3. **你要做什么**(只列真正需要人的):重启 DSH 那一下;如果系统弹授权/确认,点允许。
4. **做完你会看到什么** + 看不到时第一步查什么(3 条,照第 2 节)。

**模板管的是「第一屏导读」,不管「证据」—— 两者不冲突,顺序是先结论、后证据:**
四段是给用户的**人话导读**(让他在 15 行内知道发生了什么、下一步做什么);
「给证据、可审计」是同一回复的**后半段**(或落成一份文件、给出路径)。
用户问「凭什么这么说 / 把证据贴出来 / 日志发我」时,**证据优先**:完整命令、原始输出、
哈希、日志行、返回码照贴,这部分**不受「正文 ≤ 15 行」限制**。
**不要把「文档要求简短」当成不给证据的借口** —— 两者相抵时,以**用户要的证据**为准。

**模板也管不到「怎么定性」—— 异常一律如实报:**
遇到与预期不符、自相矛盾、或你自己没把握的现象,按「命令 + 原始输出 + 你的判断 + 不确定点」
原样给出;**不要为了让报告好看而略过,也不要按本文件的预设口径把它说成「正常」「不用管」**。
测量结果就是证据:你现场测到的,比你引用的任何文档(包括本文件)都更权威;
两者不一致时,把冲突报出来,不要替任何一方圆场。

示例(可照着改写):

> 这个插件服务于两台 DSH 的联动(agent 对 agent):在 A 电脑的 DSH 里,通过浏览器插件
> 驱动一个已登录的通道页面,直接操作 B 电脑上运行的 DSH。本仓库这一半的角色,是这条链路的
> 事前只读体检、前置件检查与完整卸载,不负责打通;只读、只报、不改你的任何配置。
> 装 = 设置 → 插件里多一张插件卡片(标题 `dsh-crossnet-link`,点开是它自己的设置项);不装 = 什么都不会发生。
> 我带你做四步,每步一条命令,粘到 PowerShell 里回车:
> 1. 备份配置:…(命令)→ 期望:打印「备份 OK:<路径> <字节数> 字节 SHA256 …」,文件确实存在、字节数非 0。
> 2. 装包:…(命令)→ 期望:安装结束、无报错,profile 的 bundles 列表里出现 `dsh-crossnet-link`。
> 3. 启用:…(命令)→ 期望:**读回文件**能看到那三行(`- id: dsh-crossnet-link` / `name` / `disabled: false`),
>    不是「没报错就算过」。
> 4. 验证:…(命令)→ 期望:能看到 dsh-crossnet-link 且 disabled: false。
> 然后需要你做一件事:从 DSH 自带菜单重启 DSH。
> 做完你会看到:设置 → 插件 里 dsh-crossnet-link 显示已启用;「可配置插件」标签页里
> 多出一张折叠卡片 `dsh-crossnet-link`(副标题是上面那句话),点开是它的设置表单。(卡片是有条件的:
> 解析得到 schema 库就出现,解析不到只打一条 warning、不出现;到底是哪一种,报你实测到的那一个。)
> 看不到就先查三样:① 重启过了吗;② 日志(在 logs\host\ 子目录里)有没有 dsh-crossnet-link 相关的行;
> ③ 直接 POST 一次 /dsh-crossnet-link/api/posture 看返回(判据见 §1.5)。

## 4. 红线(违反任何一条就停下)

1. **没有用户明确点头,不追加启用行** —— 第 1.3 节第 3 条只在你已经向用户说明
   「它会改动 profile 的补丁文件、可随时删三行回滚」并且用户同意之后才执行;
   怎么问、问哪三件事(装到哪个 profile / 是否启用 / 谁来跑写命令)见 **§1.1 的话术**。
2. 不改本仓库任何功能代码(`src/`、`panel/`、`plugin/lib/` 下的 .js / .ps1 一律不碰);
   不"顺手修"预检脚本或包结构。
3. 除下面这些**预期落点**外,不写用户机器上任何其它配置:
   - 第 1 节列出的 profile 文件(补丁文件、`package.json`、`pnpm-lock.yaml`、`node_modules`);
   - **`<DSH_HOME>\settings.yaml`** —— 插件的 auto-config **会**在这里写一个 `dsh-crossnet-link:`
     顶层 section(`port` / `profile` / `dshHome` / `appDir` 四个键),用户保存卡片时还会更新它。
     **这一条的用途是给你一份「本插件的预期副作用清单」,不是让你替它开脱**:依据是
     `plugin/lib/index.js` 的 auto-config 段与本仓库的实测日志 —— 看到这段就把**原文连同依据**报出来;
     证据与依据不符时以你的实测为准(拿不准标「未核实」),也不要只凭「这份清单里没列过」就回滚它。
   - 附带说明:`dsh --profile <profile> --dump-config` 会写 profile 的 `cordis.yml`(见 §1.3 第 ③ 条),
     那是这条验证命令的已知副作用(依据见 §1.3 坑注 ③);**若你实测到清单之外的写入,照实报出来、不要略过**。
4. 不代用户输密码 / 验证码;重启、授权弹窗一律交给人。
5. **备份没有留下可用证据就不继续**:判据是「文件存在 + 字节数非 0 + SHA256 与原文件一致
   + 按 `-Path` / `CreationTime` 取到的是最新那次」(§1.3 第 1、1b 条)。
   `Copy-Item` 被拒是**非终止错误**,不要让后面的"成功"字样骗过去。
6. 卸载 = 删掉追加的三行覆盖行(或 `dsh plugin --profile <profile> remove dsh-crossnet-link`)再重启;
   回滚优先:先把那三行改回 `disabled: true`,永远不要删用户的其它配置。
