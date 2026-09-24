# 给 AI 的安装说明(agent-brief)

> 本文件是给**被派来安装这个插件的 AI** 读的,不是让用户读的文档。
> 用户通常只做一件事:把一个仓库地址丢进对话,说「帮我装这个」。你要做的是
> 按第 1 节的流程装,并按第 3 节的模板**在对话里**用大白话带用户走完。
> 输出给用户的内容必须是第 3 节的形态 —— 不要贴本文件、不要贴 300 行技术报告。

## 0. 你是什么、第一件事做什么

你被派来把本仓库的常驻插件包(名字 `remote-tailnet-guard`,在 `plugin/` 目录)装进
用户的 DSH 配置(profile),并让它出现在「设置(Settings)→ 插件(Plugins)」里、
状态为**已启用(Enabled)**。

第一件事永远是**只读预检(preflight)**,通过之前不做任何安装动作:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <仓库>\panel\plugin-preflight.ps1
```

期望:打印 `checks: 66  passed: 66  failed: 0`,最后一行 `exit code: 0`。

- 退出 0:继续。
- 退出 1:只有告警(缺 `docs/install/plugin-package.md`),包仍可装;先向用户说明再继续。
- 退出 2:停下。把脚本里 `[FAIL]` 开头的行转述给用户,不要继续装,也不要擅自"修"仓库代码。

## 1. 装机流程:装 → 启用 → 重启 → 核对两格

包在仓库里默认是**禁用(disabled)**的,这是刻意的安全默认:禁用时它不会加载,
装上弄不坏任何东西。所以"安装"= 下面这几条命令,它们把**启用**一起做完,
用户不需要手工改任何文件。全程让用户在**他自己的终端**里执行,你逐条贴、逐条解释。

```powershell
# 0) 先问清楚:用户机器上 DSH 的 profile 名(绝大多数人只有默认的 desktop;有多个就问用户用哪个)
$p = Join-Path (if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE '.dsh' }) 'profiles\<profile>\cordis.patch.yml'

# 1) 备份 profile 的补丁文件(回滚就靠它,不能省)
Copy-Item -LiteralPath $p -Destination ($p + '.bak-' + (Get-Date -Format 'yyyyMMdd-HHmmss')) -Force
# 期望:命令无输出;再看一眼
Get-ChildItem -LiteralPath ($p + '.bak-*') | Sort-Object LastWriteTime | Select-Object -Last 1 Name
# 期望:列出刚生成的一个 .bak-<时间戳> 文件

# 2) 把包装进 profile(会写 profile 的 package.json / pnpm-lock.yaml / node_modules)
dsh plugin --profile <profile> add ('link:' + '<仓库路径>\plugin')
# 期望:pnpm 打印安装过程,最后没有报错

# 3) 把"启用覆盖行"追加到 profile 补丁文件末尾(这就是启用这一步)
[IO.File]::AppendAllText($p, "`n- id: remote-tailnet-guard`n  name: remote-tailnet-guard`n  disabled: false`n", (New-Object Text.UTF8Encoding($false)))
# 期望:无输出、不报错

# 4) 验证:组合后的配置里能看到这一行,且已启用
dsh --profile <profile> --dump-config | Select-String -SimpleMatch 'remote-tailnet-guard' -Context 0,4
# 期望:能看到 id/name 是 remote-tailnet-guard、disabled: false 的那一行
```

然后请用户**重启 DSH**(用 DSH 自带菜单:设置 → 桌面 → 重启;或退出应用再打开)。
这一步只有人能做。重启后按下面「两格」核对。

> 小坑(实测):刚初始化的新 profile 的补丁文件内容是一行 `[]`(空数组)。追加第 3 条之前,
> 如果文件里就这一行 `[]`,先把它删掉再追加,避免数组里多出一个空项。

### 1.1 装完看到什么(两格;不新增侧边栏条目)

本插件**只以一张标准插件卡片**出现(与别的插件一致),**不新增侧边栏/设置导航条目**:

| 格 | 位置 | 判据 |
|---|---|---|
| ① 插件清单 | 设置(Settings)→ 插件(Plugins),第一个标签页 | 清单里有 `remote-tailnet-guard`,状态显示**已启用(Enabled)**。装完但没启用时它也会在清单里(标"未启用"),所以这一格要认准"已启用"三个字 |
| ② 可配置插件卡片 | 设置 → 插件 → 「可配置插件」标签页 | 一张折叠卡片(标题「跨网链路姿态」,点开是中文只读面板)。卡片要 host 半边把空 schema 的设置命名空间注册成功才渲染,这一步要能在 profile 侧解析到 schema 库(实测:profile 里已有其它插件时通常解析得到,卡片就出现;解析不到时只打一条 warning、卡片不出现,第 ① 格不受影响)。**别把卡片缺席当故障**:① 出现就算装好,② 出现与否如实告诉用户即可 |

## 2. 装完看不到时,按顺序查这 3 条

1. **没重启**:改了配置不重启就没生效 → 让用户从 DSH 自带菜单重启一次。
2. **启用行没生效**:让用户跑
   `dsh --profile <profile> --dump-config | Select-String -SimpleMatch 'remote-tailnet-guard'`,
   看不到 `disabled: false` 就是第 1 节第 3 条没跑、或跑到了别的文件上。
3. **client 半边没加载**:设置 → 插件里连卡片都没有 → 让用户把 DSH 日志里
   `remote-tailnet-guard` 相关的行发给你(日志在 DSH 的日志目录,文件名形如 `dsh-YYYY-MM-DD.log`),再决定下一步。

## 3. 对话输出模板(四段;正文 ≤ 15 行,代码块另计)

你回复用户的**第一屏**必须是下面四段,顺序不许变:

1. **现在什么情况**(2 句):这个插件是什么(只读体检器:只读、只报告、不改任何配置);装或不装意味着什么。
2. **我要做什么**(编号步骤):每步一句人话 + 一条命令 + 一行期望结果(照第 1 节的四条)。
3. **你要做什么**(只列真正需要人的):重启 DSH 那一下;如果系统弹授权/确认,点允许。
4. **做完你会看到什么** + 看不到时第一步查什么(3 条,照第 2 节)。

示例(可照着改写):

> 这个插件服务于两台 DSH 的联动(agent 对 agent):在 A 电脑的 DSH 里驱动已登录的
> 通道页面,直接操作 B 电脑上运行的 DSH。它负责这条链路的事前只读体检、前置件检查、
> 只读面板与完整卸载,不负责打通;只读、只报、不改你的任何配置。
> 装 = 设置里多一张只读体检卡片;不装 = 什么都不会发生。
> 我带你做四步,每步一条命令,粘到 PowerShell 里回车:
> 1. 备份配置:…(命令)→ 期望:多出一个 .bak- 文件。
> 2. 装包:…(命令)→ 期望:安装结束、无报错。
> 3. 启用:…(命令)→ 期望:无输出。
> 4. 验证:…(命令)→ 期望:能看到 remote-tailnet-guard 且 disabled: false。
> 然后需要你做一件事:从 DSH 自带菜单重启 DSH。
> 做完你会看到:设置 → 插件 里 remote-tailnet-guard 显示已启用;「可配置插件」标签页里
> 多出一张折叠卡片「跨网链路姿态」,点开是中文只读面板。(卡片是有条件的:
> 解析得到 schema 库就出现,解析不到只打一条 warning、不出现,两种情况都不影响清单行。)
> 看不到就先查三样:① 重启过了吗;② 第 4 步的验证输出里 disabled 是 false 吗;
> ③ 日志里有没有 remote-tailnet-guard 相关的行。

## 4. 红线(违反任何一条就停下)

1. **没有用户明确点头,不追加启用行** —— 第 1 节第 3 条只在你已经向用户说明
   「它会改动 profile 的补丁文件、可随时删三行回滚」并且用户同意之后才执行。
2. 不改本仓库任何功能代码(`src/`、`panel/`、`plugin/lib/` 下的 .js / .ps1 一律不碰);
   不"顺手修"预检脚本或包结构。
3. 除第 1 节列出的 profile 文件(补丁文件、package.json、pnpm-lock.yaml、node_modules)外,
   不写用户机器上任何其它配置。
4. 不代用户输密码 / 验证码;重启、授权弹窗一律交给人。
5. 卸载 = 删掉追加的三行覆盖行(或 `dsh plugin --profile <profile> remove remote-tailnet-guard`)再重启;
   回滚优先:先把那三行改回 `disabled: true`,永远不要删用户的其它配置。
