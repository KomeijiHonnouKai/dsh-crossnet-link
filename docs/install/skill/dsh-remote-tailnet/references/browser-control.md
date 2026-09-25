# 浏览器操控对端(`browser_*` 首选 / `ego_*` 轻量查询)

> 最后更新:2026-09-26。素材:`D:\DSH\peer-channel-howto.md`(实测记录,只读引用)+ `D:\DSH\.dsh\notes\exports\ego-browser-facts.md`(ego-browser 插件真相调研,t1)。本文件已脱敏:不出现任何真实对端机器名 / `100.x` 地址 / tailnet 名。
> 前置:链路**已打通** —— 客户端浏览器能打开 `https://<机器名>.<tailnet>.ts.net/`,且那枚 cookie 没过期(打开方式与 30 天绝对期限见 [client-setup.md](client-setup.md) §3)。本文只讲「打开之后怎么操作对端」。

## 0. 两套工具,怎么选

| | `browser_*`(DSH 内置浏览器桥) | `ego_*`(ego-browser 插件,独立便携 Chromium) |
| --- | --- | --- |
| 驱动谁 | 经 **Chrome 扩展**驱动**你日常那个真实浏览器**,登录态 = 你本人的 | 插件**自管的 Chromium**(独立 profile),与日常浏览器**不共享 profile / 登录态** |
| 怎么接 | 宿主 webserver 上 token 鉴权的 **WebSocket `/ext/bridge`** | 插件内置 vendored runtime(非全局 `ego-browser` CLI) |
| 本文用途 | **跨网操控对端 DSH 的首选**:`browser_list_tabs → browser_follow_tab → browser_snapshot → browser_type / browser_click`,本次跨网实测全程无超时 | **只做轻量查询**(`ego_status` / `ego_doctor` / `ego_page_info` / `ego_snapshot` 类);`ego_script`(多步脚本)、`ego_navigate`(对端生成中 / 大页面首屏)这类重操作别用 |
| 上限 | 文档默认 `toolTimeoutMs = 90000 ms`、`snapshotMaxChars = 32000`、`maxInteractiveItems = 60`(证据类 C,见 §6);本次跨网链路**未触发过超时** | 单次 tool call 默认 **120 000 ms**(`TOOL_TIMEOUT_MS`);`ego_script` 可传 `timeoutMs` 覆写;`ego_status`/`ego_doctor` 25 s、`ego_login_import` 60 s、`ego_auth_flush` 10 s、`ego_help` 10 s(证据类 C) |
| 并发 | 未测到限制(证据类 D) | **全部 `ego_*` 经进程内互斥锁串行化 ⇒ 并发调用会排队,不是并行**(证据类 C) |
| 超时后怎么办 | 重新 `browser_snapshot` 取新索引再试 | **不要重试**;直接换 `browser_*`(重试只会再烧一个 120 s 上限) |

**优先序按本 skill 的用户口径写死:`browser_*` 首选(跨网),`ego_*` 只做轻量查询。** 这条不是插件自己的建议,理由与口径来源如下(证据类 C):

- ego-browser 包内对内置 `browser_*` 桥**零口径**:README.md / `dsh-plugin.json` / `cordis.patch.yml` / `lib/*.js` 全文检索 `browser_snapshot|browser_click|browser_type|browser bridge|dsh-bridge-browser|二选一` **零命中**;
- 唯一一句「优先用 ego-browser」写在**随包携带但本机没有被扫进技能目录**的 `SKILL.md:3` frontmatter 里,属**插件自身立场**,不是宿主口径;
- README.md:52-68 那张「对比表」比的是**另一个第三方插件**(`Da1dr1em/dsh-ego-browser`),**不是**内置 `browser_*` 桥 —— 引用时别误读;
- 本机事实:`browser_*` 来自另一个独立插件 `@yuxianglin/dsh-bridge-browser`,与 `dsh-ego-browser` **可同时装载(本机就是共存)**,**互不相通**。

> ⚠️ 「`ego_*` 一直 120 s 超时、用不了」是**过期结论** —— 那是当时环境未配好所致。现在:本机便携 Chrome 已配好(路径见用户全局 `AGENTS.md`),`ego_doctor` ✅ / `ego_status` ✅ 实测都跑得起来。正确口径 = **默认 120 s 上限 + 全串行 ⇒ 只做轻量查询;重操作归 `browser_*`**。

`ego_*` 的三条红线(证据类 C,随包 `SKILL.md` / `lib/index.js`,写在这里免得读者再去翻那份没被加载的文件):

1. **登录后必须显式 `ego_auth_flush`** —— Chrome 运行期的 cookie 只在**优雅关闭**时才落盘;不 flush 就等于「登录成功 ≠ 已持久化」;
2. **默认持久模式下只用/复用单个 space**(本机运行时 space 名实测 = `default`,**别照抄代码常量 `dsh-agent`**),**收尾不要 `ego_space_close`**、不要建 `#4`/`#5` 之类的编号 space;
3. **`user is controlling` 是硬停**,不可绕过:**不要**自行 `takeOverTaskSpace` 抢回控制权,只能问用户并等。

## 1. 动手前的两条前置检查

1. **受控标签页对不对**:`browser_list_tabs` 看受控/当前 tab 是不是 `https://<机器名>.<tailnet>.ts.net/`;不是(或丢了)就 `browser_follow_tab` 按 tabId 重挂 —— 受控标签页在截图之间可能失联(证据类 B)。
2. **桥有没有连上**:桥靠 Chrome 扩展连接,**没有活动扩展时所有 `browser_*` 直接失败**,实测原文:`no browser extension is connected to the bridge`(证据类 A,2026-09-26 本次撰写时复现)。这时**不要**换 ego_* 硬撑,先让用户在装了扩展的那个浏览器窗口里打开/重连(或按用户全局 `AGENTS.md` 的入口处理)。

> 桥「仅一个活动扩展连接(第二个窗口顶替第一个)」是它的文档已知限制(证据类 C),所以「换窗口」后要重新确认受控 tab。

## 2. 写入(给对端发消息):只能走 composer

1. `browser_snapshot`,找 `textbox "发消息或创建任务, / 调用指令, @ 文件或对话"`;
2. `browser_type` 写入文本 —— **剪贴板粘贴进不去,只能 type**(中文正常);
3. 点 `button "发送消息"`(composer 里已有排队文本时显示 `排队发送`,点它即入队);
4. 判据:按钮变成 **`停止生成`** = 消息已发出;回到 `发送消息` = 对端那一轮跑完了。

坑(证据类 B):

- **新建会话页面的输入框 type 后发送按钮仍 disabled**(那是启动器组件)⇒ 协商要在**已有会话**里做;
- 对端生成中时发第二条 → 显示「排队发送」,要等它当前轮结束才处理;
- 对端按 token 计费:**没有实质内容就别发消息**,不要寒暄式往返。

### 2.1 选会话:别靠正文文本找

要进的会话不在头几条时,**不要靠 `Main content` 里的文本找** —— 会话条目本身在 `Main content` 里**没有可点索引**:

1. 先在 composer 上方的**搜索框**输入关键字做过滤;
2. 再 `browser_snapshot`,从 **interactive 列表**里取目标会话那条 `treeitem` 的**索引**;
3. 用该索引 `browser_click`。

⚠️ 索引只在**当次** snapshot 里有效:列表一变(过滤、来新消息、页面重绘)就要**重新 snapshot 取新索引**再点。(`ego_*` 侧的同款规则是「`@N` 只在最近一次快照内有效」,证据类 C。)

## 3. 读取(拿对端的完整回复):页面读不全,走导出文件

**为什么不能直接读页面**(证据类 B,2026-09-24 首测、2026-09-25 复测结论一致):`browser_get_text` / `snapshot` **永远只返回页面文本的前 ~8.4 KB**,长会话的最新回复必然落在截断之外;侧边栏的消息预览同样被截断,只能当「她回了没有」的信号;`selector` 只给**第一个**匹配,`:has()` 这类写法定位不到「最后一条消息」。

量级参考(证据类 A):本次实测导出里最后一条 `assistant/message` 的 `text` 块**单块就有 26 509 字符**,另有 112 条 `tool/call` —— 这类回复**物理上不可能**从截断后的页面文本里拿到。

⇒ **读对端长回复只有一条可用通道:「更多操作 → 下载 Session 日志」**,没有纯自动的替代路径。

步骤:

1. 对端会话页 → `button "更多操作"`(⋯) → `menuitem "下载 Session 日志"`;
2. 浏览器下载到 `%USERPROFILE%\Downloads\dsh-session-session-<id>.zip`(文件名可能被加 `(1)`/`(2)`,**取之前先全列目录、比时间与大小,别只看前几个**);
3. 解压取 `session.v3.jsonl`(每行一个事件:`user/message`、`assistant/message`、`tool/call`、`tool/result`、`step/start`、`step/end`、`turn/end` …);
4. 用 §3.1 的命令解析。

### 3.1 可粘贴命令原文

⚠️ 坑:`Expand-Archive` 对这个导出 zip 会报「**不支持给定路径的格式**」—— zip 里除 `session.v3.jsonl` 外还有 `media/sha256:<hex>.png` 这类**带冒号的条目名**,Windows 不接受。本次复现的完整错误原文(证据类 A):

    Type    : System.Management.Automation.MethodInvocationException
    Message : 使用“1”个参数调用“.ctor”时发生异常:“不支持给定路径的格式。”
    FQID    : ConstructorInvokedThrowException,Microsoft.PowerShell.Commands.NewObjectCommand

改用 .NET `System.IO.Compression.ZipFile`**只取需要的那个条目**。整段直接粘贴运行(纯 ASCII,不受编码影响):

```powershell
# Extract the newest exported session and triage its event types.
# Requires: PowerShell 5.1 or 7 (verified on 5.1.19041).
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression

$zip = (Get-ChildItem $env:USERPROFILE\Downloads -Filter 'dsh-session-session-*.zip' |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
"zip = $zip"

# Pick a WRITABLE destination; do not dump into the skill folder or the repo.
$dest = 'D:\DSH\peer-session-dump'
New-Item -ItemType Directory -Force -Path $dest | Out-Null
$out = Join-Path $dest 'session.v3.jsonl'

# Do NOT use Expand-Archive: entries named media/sha256:<hex>.png break it.
# Remove any previous copy first: otherwise a failed extract leaves a stale file
# behind and the next step silently parses the OLD session.
Remove-Item $out -Force -ErrorAction SilentlyContinue
$za = [System.IO.Compression.ZipFile]::OpenRead($zip)
try {
  # Match FullName, NOT Name: a zip exported from a session that used subagents
  # also carries subagents/<id>/session.v3.jsonl, whose .Name is the same string.
  # Matching .Name then returns 2 objects, and ExtractToFile() fails with
  # "Cannot find an overload for ExtractToFile and the argument count: 3"
  # because $entry is an array instead of a single entry.
  $entry = @($za.Entries | Where-Object { $_.FullName -eq 'session.v3.jsonl' })
  if ($entry.Count -ne 1) { throw "expected exactly 1 root session.v3.jsonl in $zip, found $($entry.Count)" }
  [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry[0], $out, $true)
} finally { $za.Dispose() }

$lines = [System.IO.File]::ReadAllLines($out, [System.Text.Encoding]::UTF8)
"lines = $($lines.Count) ; empty = $(($lines | Where-Object { $_ -eq '' }).Count)"

# Event triage: never index by line number, the tail is usually turn/end.
$types = @{}
foreach ($l in $lines) {
  if ($l -match '"type"\s*:\s*"([^"]+)"') {
    $t = $Matches[1]
    $types[$t] = 1 + $types[$t]
  }
}
$types.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 10 |
  ForEach-Object { "  {0}  x{1}" -f $_.Name, $_.Value }

# Blocks are typed: reasoning/thinking blocks must be filtered out, text only.
$am = $lines | Where-Object { $_ -match '"type"\s*:\s*"assistant/message"' } | Select-Object -Last 1
if ($am) {
  $o = $am | ConvertFrom-Json
  $blocks = $o.data.message.content
  "last assistant/message block types: " + (($blocks | ForEach-Object { $_.type }) -join ', ')
  ($blocks | Where-Object { $_.type -eq 'text' } | ForEach-Object { $_.text }) -join "`n"
}

# Tool-call arguments: key names vary per tool (write -> file_path/content; present -> files[]).
# Blank lines fed to ConvertFrom-Json throw "InputObject is null", so filter first.
$tc = $lines | Where-Object { $_ -match '"type"\s*:\s*"tool/call"' } | Select-Object -Last 1
if ($tc) {
  $c = $tc | ConvertFrom-Json
  $keys = (($c.data.arguments | ConvertFrom-Json).PSObject.Properties.Name) -join ', '
  "last tool/call: $($c.data.name) ; argument keys: $keys"
}
```

只要最后一条助手消息的正文时(自包含一段):

```powershell
$out = 'D:\DSH\peer-session-dump\session.v3.jsonl'
$lines = [System.IO.File]::ReadAllLines($out, [System.Text.Encoding]::UTF8)
$am = $lines | Where-Object { $_ -match '"type"\s*:\s*"assistant/message"' } | Select-Object -Last 1
($am | ConvertFrom-Json).data.message.content | Where-Object { $_.type -eq 'text' } | ForEach-Object { $_.text }
```

写盘路径要选**可写**的位置(上面的 `D:\DSH\peer-session-dump` 是本次实测用的),**不要写进 skill 目录、也不要落在仓库里**;导出里可能含凭据原文,按纪律**不得外传**。

> 受限环境提示(证据类 A):用户的 shell 若被限制在 `D:\DSH` 内可写,那么往 `$env:USERPROFILE\peer-session-dump` 这类**工作区外**路径写会报 `New-Item : 对路径“…”的访问被拒绝`(UnauthorizedAccess);此时把 `$dest` 换成工作区内的目录即可 —— 注意 `New-Item` 的失败**不会**中断脚本,后面 `ExtractToFile` 才会抛「未能找到路径…的一部分」,别把这两条读成「zip 坏了」。

## 4. 已知局限(别在这些方向上浪费轮次)

证据等级见 §6:**A** = 本次撰写时以命令复现、原文在本文; **B** = `peer-channel-howto.md` 实测记录; **C** = 插件/桥的代码或文档口径(带出处); **D** = 未实测(给核验办法)。

| 通道 | 现象 | 结论 | 等级 |
| --- | --- | --- | --- |
| 页面文本 `browser_get_text` / `snapshot` | 只返回**前 ~8.4 KB**(09-25 复测仍是 8.4 KB);`selector` 只取第一个匹配;`region` 参数实测未生效 | ❌ 读不到最新回复 | B |
| 侧边栏消息预览 | 同样被截断(只显示开头一段),只能判「她回没回」 | ⚠️ 不能当正文读 | B |
| 「更多操作 → 下载 Session 日志」 | 09-24 首次成功,之后 Chrome 把它扣成「未确认 `*.crdownload`」;09-25 首次即成功 | ✅ **唯一**能拿到完整长回复的通道;被拦时**请用户在下载条点一次「保留」**再重试 | B |
| zip 解压 `Expand-Archive` | 报「**不支持给定路径的格式**」;根因是条目 `media/sha256:<hex>.png` **名字带冒号**(本次已复现错误原文,见 §3.1) | ⚠️ 改用 .NET `ZipFile` 只取 `session.v3.jsonl` | A |
| zip 条目数 | 同一批 9 个导出里:有图的 2 条目(含冒号 png)、无图的 1–2 条目,`session.v3.jsonl` 恒在 | ℹ️ 「有没有 png」决定 `Expand-Archive` 会不会炸;**不要**假设每次都能用 `Expand-Archive` | A |
| zip 里的**同名根条目** | 用过 subagent 的会话导出会同时含 `session.v3.jsonl` 与 `subagents/<id>/session.v3.jsonl` —— 两者 `.Name` **相同**(本机 9 个导出里 **3 个**如此) | ❌ 按 `.Name` 选条目会拿到 **2 个对象**,`ExtractToFile` 报「找不到…重载,参数计数为 3」;✅ 一律按 **`.FullName -eq 'session.v3.jsonl'`** 并断言只命中 1 条(见 §3.1) | A |
| 最后一条 `assistant/message` 的 `content` | 块数组**会混有 thinking/reasoning 块**(本次实测块类型 `reasoning, text`) | ⚠️ 取文本必须 `Where-Object { $_.type -eq 'text' }` 过滤 | A |
| 空行 / 硬编行号 | 空行喂 `ConvertFrom-Json` 会报空值;第 N 行也不一定是 `tool/call`(**本次那份导出实测 586 行、0 空行、112 条 `tool/call`**,但尾部是 `turn/end` 类事件,前几份导出确有空行) | ⚠️ 一律 `Where-Object { $_ -match '"type"\s*:\s*"…"' }` 过滤后再解析,别按行号取 | A/B |
| `ConvertFrom-Json` 的保真度 | PS 5.1 会把 ISO8601 样式字符串转成 `DateTime`、把像数字的字符串转成数字 | ⚠️ 要**逐字原文**(时间戳/ID 的形状)时别走 `ConvertFrom-Json`,用 `Select-String` / 正则取原串 | C |
| 会话列表项 | 会话条目在 **Main content 里没有可点索引**,只有 snapshot **interactive 列表里的 `treeitem`** 才有 | ✅ 先用搜索框过滤,再取 `treeitem` 索引点击 | B |
| 消息「复制」按钮 + 剪贴板 | 点击返回成功,但剪贴板始终是旧值(CDP 点击不给文档焦点,`navigator.clipboard` 拒绝写入) | ❌ 别指望「点复制 + 读剪贴板」(PowerShell 侧 `Set-Clipboard`/`Get-Clipboard` 本身正常) | B |
| 「在新对话中分支」 | 分支会话照样从**头部**渲染历史,截断位置不变 | ❌ 治不了截断 | B |
| 「更多操作」菜单项 | 在 snapshot 的 interactive 列表里**可见且可点** | ✅ 唯一可靠的「操作对端 UI」入口 | B |
| 对端「打开文件」卡片 → 新标签页 | 只切换右侧边栏形态,**不产生新浏览器标签**,`browser_list_tabs` 仍只有一个 tab | ❌ 绕不开截断 | B |
| 桥的连接状态 | 没有活动扩展连接时,所有 `browser_*` 立即失败:`no browser extension is connected to the bridge` | ⚠️ 先恢复扩展连接,别改用 `ego_*` 硬撑 | A |
| 桥 `toolTimeoutMs`(文档 90 s) | 文档写的默认值与本次「跨网全程无超时」不冲突,但**没在跨网侧逼近过该上限** | ℹ️ 别把「无超时」读成「无限时」;要核验就压一次大页面快照 | C/D |
| `ego_*` 超时与并发 | 默认 120 s;`ego_script` 可 `timeoutMs` 覆写;全串行(并发排队) | ⚠️ 只做轻量查询;超时**不要重试**,直接换 `browser_*` | C |

**可用组合**:写入走 composer(稳定);读取**只能**走「下载 Session 日志」—— 页面文本与侧边栏预览都必然截断。被拦时先请用户在下载条点「保留」再重试;实在拿不到,就让对端把结论写成文件、由用户取回。

## 5. 收尾检查表

- [ ] 受控标签页 = `https://<机器名>.<tailnet>.ts.net/`(不是别的 tab;丢了先 `browser_follow_tab`);
- [ ] 桥有活动扩展连接(否则 `browser_*` 全失败);
- [ ] 发消息:`browser_type` 写 composer → 点「发送消息」→ 看到「停止生成」;
- [ ] 读回复:走「更多操作 → 下载 Session 日志」+ .NET `ZipFile`,**不用** `Expand-Archive`;
- [ ] 解析前先按 `type` 过滤 `content` 里的 `text` 块;不按行号取;
- [ ] `ego_*` 只做轻量查询;一旦超时立刻换 `browser_*`,不重试;
- [ ] 抛出的 `.ps1`/脚本不落在 skill 目录或仓库里;导出内容不外传。

## 6. 证据与核验

### 6.1 证据等级定义

| 等级 | 含义 |
| --- | --- |
| **A** | 本次撰写(2026-09-26)在**本机**用命令复现,原文已写进本文(§3.1、§0、§4 右侧标注处) |
| **B** | `peer-channel-howto.md` 的实测记录(2026-09-24 首测 / 2026-09-25 复测) |
| **C** | ego-browser 插件 / `@yuxianglin/dsh-bridge-browser` 桥的**代码或文档口径**,出处见 §6.2 |
| **D** | **未实测**:给了核验命令/方向,别当结论用 |

### 6.2 关键事实出处

| 事实 | 出处 |
| --- | --- |
| `ego_*` 共 **33** 个工具;README 自称 33/32/30+ 三处不一致,以代码为准 | `dsh-ego-browser\lib\index.js`(`name: "ego_*"` 33 条),`README.md:42/52/56/145`,`package.json:4` |
| 默认单次预算 120 000 ms;`ego_script` 可 `timeoutMs` 覆写;doctor/status 25 s、login_import 60 s、auth_flush 10 s、help 10 s;grace 15 s;输出上限 4 MiB | `lib/index.js:2627`、`:4270-4273`、`:3245`、`:4200`、`:3405`、`:3311`、`:4161`、`:2626`、`:2625` |
| 所有 `ego_*` 经进程内互斥锁串行化(并发排队) | `lib/index.js:2660-2670`(`withEgoLock`) |
| 持久 profile 模式默认开;state dir `%LOCALAPPDATA%\ego-lite-linux`;profile = `<state>\profile` | `lib/index.js:1410`、`:1599`、`:243-246`;`runtime/ego-linux/src/paths.mjs:8-17` |
| Chrome 运行期 cookie 只在优雅关闭落盘 ⇒ 必须 `ego_auth_flush` | `lib/index.js:3293`,插件 `README.md:205` |
| 持久模式下只用/复用单个 space、收尾**不要** `ego_space_close` | `lib/index.js:3460`、`:3474`;随包 `runtime/skills/ego-browser/SKILL.md:65-71` |
| `user is controlling` 是硬停,**不许**自行 `takeOverTaskSpace` | 随包 `SKILL.md:99-109` |
| 随包 SKILL.md 在本机**没被扫进技能目录**,插件不注册 skill ⇒ 别假设读者能 `skill ego-browser` | 本会话技能清单;`lib/index.js` 全文无 `skills`/`SKILL` 引用;该文件绝对路径 `%USERPROFILE%\.dsh\profiles\desktop\node_modules\dsh-ego-browser\runtime\skills\ego-browser\SKILL.md` |
| 包内对内置 `browser_*` 桥**零口径**;唯一自我推荐句在随包 `SKILL.md:3`;README:52-68 的对比表比的是另一个第三方插件 | 全包检索零命中;`SKILL.md:3`;`README.md:52-68` |
| `browser_*` 来自独立插件 `@yuxianglin/dsh-bridge-browser`(token 鉴权 WS `/ext/bridge` + Chrome 扩展),与 ego-browser **可共存、不共享 profile** | `%USERPROFILE%\.dsh\profiles\desktop\package.json:6/:10/:20-21`;该包 `README.zh.md:5/:69-72/:88` |
| 桥的 `toolTimeoutMs` 默认 90 000 ms / `snapshotMaxChars` 32 000 / `maxInteractiveItems` 60 / 仅一个活动扩展连接 | 同包 `README.zh.md:14/:15/:16/:88` |
| 页面文本 ~8.4 KB 截断、侧边栏预览截断、composer/选会话/下载日志/复制按钮/分支会话/打开文件 等实操坑 | `peer-channel-howto.md:28-30`、`:104-118` |

### 6.3 未实测项与核验办法(D)

| 未实测 | 核验办法 |
| --- | --- |
| 桥 `toolTimeoutMs = 90 s` 在跨网侧的真实余量 | 对一个大页面(长会话列表)跑 `browser_snapshot`,记开始/结束时间;逼近 90 s 即会失败 |
| 桥是否对 `browser_*` 做并发串行化 | 同一轮里连发两个 `browser_list_tabs`,看是否排队(与 `ego_*` 的互斥锁对照) |
| `ego_*` 在**跨网操作对端**场景下能否不超时 | 只拿 `ego_page_info` 这种纯读探针试一次;超时即按 §0 结论换 `browser_*`,**不要重试** |
| 没有下载条可点(纯无头/无人)时怎么拿长回复 | `D` 级:目前只有「让对端把结论写成文件、由用户取回」这条,不要在文档里编自动替代 |

> 引用纪律:本文件里凡 `ego_*` 的行为,一律按上表出处引用;`peer-channel-howto.md` 与本文件是**同一批实测的两份记录**,冲突时以**更晚的复测**和**代码口径(C)**为准。

## 7. 内联命令 vs 落成 `.ps1`(必须 `-File`)

- §3.1 的代码块是**内联命令**(整段粘进一个 PowerShell 会话就能跑),不存在 `-File` 问题;
- **若要落成 `.ps1` 文件再跑,必须用 `powershell -NoProfile -ExecutionPolicy Bypass -File <路径>` 形态** —— 本机实测 `Get-ExecutionPolicy` = **Restricted**(证据类 A),裸 `.\x.ps1` 会被拒(`PSSecurityException` / `UnauthorizedAccess`,见 [verify.md](verify.md) §0);
- **含中文的 `.ps1` 必须存成 UTF-8 with BOM**:PS 5.1 无 BOM 时按 ANSI 读,会把中文注释/字符串读坏,报成片的**假**语法错。本文件 §3.1 的代码块刻意写成**纯 ASCII**,就是为了让粘贴/落盘两种走法都不踩这个坑(本文自身是 UTF-8 无 BOM `.md`,不受此影响);
- 本文 §3.1 的命令已在本机 **PS 5.1.19041** 上通过语法解析(0 错误)并**端到端跑通**(清单/解出 `session.v3.jsonl`/块类型过滤/`tool/call` 参数键,证据类 A)。
