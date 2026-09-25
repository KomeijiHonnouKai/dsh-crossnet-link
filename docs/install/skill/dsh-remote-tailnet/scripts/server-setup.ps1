<#
  server-setup.ps1 —— 服务端巡检(Tailscale 安装/登录/serve/loopback 端口/Host 信任/收尾)
  最后更新:2026-09-24(W4 + t18:回滚命令改为 tailscale serve reset)
  本脚本**只读**:只探测当前状态 + 打印「该由人执行的命令」。
  **不下载、不安装、不调用 msiexec、不跑 serve、不写任何 profile 文件** ⇒ 跑一百遍也不会产生不可逆改动。
  需要管理员的地方会提示;登录与 policy 收紧必须人工。
  本次使用的命令:
    powershell -NoProfile -ExecutionPolicy Bypass -File .dsh/skills/dsh-remote-tailnet/scripts/server-setup.ps1 -CheckOnly
    powershell -NoProfile -ExecutionPolicy Bypass -File .dsh/skills/dsh-remote-tailnet/scripts/server-setup.ps1 -CheckOnly -DshPort 43120
    # t18 复核 serve 子命令(只读,不需要守护进程):
    #   & "$env:ProgramFiles\Tailscale\tailscale.exe" serve --help    # ⇒ exit=0;USAGE 只有 <target> / status [--json] / reset,没有 off
  用法(本机默认 ExecutionPolicy = Restricted:裸 `.\server-setup.ps1` 会被拒 ⇒ 必须用 -File 形态):
    powershell -NoProfile -ExecutionPolicy Bypass -File <本文件> -CheckOnly
    powershell -NoProfile -ExecutionPolicy Bypass -File <本文件> -MsiPath "$env:USERPROFILE\Downloads\tailscale-setup-<版本>-amd64.msi"
    powershell -NoProfile -ExecutionPolicy Bypass -File <本文件> -TsNetHost <机器名>.<tailnet>.ts.net
  参数:
    -DshPort 43120        DSH 的 loopback 端口(= dsh-desktop.port,必须保持)
    -MsiPath              已下载的 MSI;给了只用来算 sha256 并打印(本脚本不装)
    -TsNetHost            形如 <机器名>.<tailnet>.ts.net(给了才检查/打印 trustedHosts)
    -ProfileName          DSH profile 名,默认 desktop
    -ProfileDir           显式指定 profile 目录(优先级最高;非默认 DSH_HOME 的机器用它)
    -CheckOnly            只检查,不改动(本脚本本来就不改动;此开关保留为兼容)
#>
param(
  [int]$DshPort = 43120,
  [string]$MsiPath = '',
  [string]$TsNetHost = '',
  [string]$ProfileName = 'desktop',
  [string]$ProfileDir = '',
  [string]$VerifyScriptPath = '',
  [switch]$CheckOnly
)
$ErrorActionPreference = 'Continue'
$ts = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
function Say($m) { Write-Host $m }
function Ok($m)  { Write-Host ('  [OK]   ' + $m) -ForegroundColor Green }
function Todo($m){ Write-Host ('  [TODO] ' + $m) -ForegroundColor Yellow }
function Unknown($m) { Write-Host ('  [无法判定] ' + $m) -ForegroundColor Magenta }
function Rb($m)  { Write-Host ('  [回滚] ' + $m) -ForegroundColor DarkGray }

Say '=== 1. Tailscale 是否已安装 ==='
if (Test-Path $ts) {
  Ok ('已安装: ' + $ts)
  $svc = Get-Service Tailscale -ErrorAction SilentlyContinue
  if ($svc) { Ok ('服务: ' + $svc.Status + ' / ' + $svc.StartType) } else { Todo '未见 Tailscale 服务' }
} else {
  Todo '未安装'
  if ($MsiPath -ne '' -and (Test-Path $MsiPath)) {
    Say ('  sha256 = ' + (Get-FileHash $MsiPath -Algorithm SHA256).Hash + '  ← 请与官方/预期值比对后再装')
    Say '  安装(会弹 UAC;本脚本不代执行,请核对 hash 后自己粘贴):'
    Say ('    Start-Process msiexec.exe -Verb RunAs -ArgumentList ''/i'',''' + $MsiPath + ''',''/qn'',''/norestart'' -Wait')
    Rb ('msiexec /x "' + $MsiPath + '" /qn')
  } else {
    Say '  请先下载 MSI 并核对 sha256,再带 -MsiPath 重跑(本脚本只算 hash,不下载、不安装);或手动双击安装。'
  }
}

Say '=== 2. 登录状态(人工) ==='
# 判定必须看 ip 命令自身的退出码:
#   tailscale version 不需要守护进程 ⇒ 受限沙箱里也能 exit 0,不能用来判断 CLI 是否可用;
#   ip / status / serve 要走 \\.\pipe\ProtectedPrefix\Administrators\Tailscale\tailscaled ⇒ 沙箱里 Access is denied。
#   被拒 = unknown(此处无法判定),**不得**读成「未登录」。
if (-not (Test-Path $ts)) { Todo '未安装,跳过' }
else {
  $ipRaw = (& $ts ip -4 2>&1 | Out-String)
  if ($LASTEXITCODE -ne 0) {
    if ($ipRaw -match 'Access is denied|拒绝访问') { Unknown 'CLI 在当前上下文被拒(命名管道)→ 请在【用户自己的普通窗口】跑 tailscale ip -4;这里的失败不代表未登录' }
    else { Unknown ('调用失败: ' + (($ipRaw.Trim() -split '\r?\n')[0])) }
  } elseif ($ipRaw.Trim() -match '^\d+\.\d+\.\d+\.\d+') { Ok ('tailnet IP = ' + (($ipRaw.Trim() -split '\s+') -join ',')) }
  else { Todo '还没登录:托盘 Tailscale → Log in(与客户端同一账号)' }
}

Say '=== 3. DSH loopback 端口(结构化探针优先,不依赖 netstat 的本地化文本) ==='
# 判据优先级:
#   a) 真连一次 127.0.0.1:<port>(TcpClient)—— 语言无关,成功即在监听;
#   b) netstat 行结构:远端列是 0.0.0.0:0 / [::]:0 才是监听行(不依赖状态词是否被本地化);
#   c) 有该端口的行、但既不是 (a) 也不是 (b) ⇒ 「无法判定」,并把原行打出来。
# 注意:Get-NetTCPConnection 存在但在非提权下对本端口实测返回 0 行 ⇒ 不可用,不能读成「没监听」。
$listenOk = $false
try {
  $c = New-Object Net.Sockets.TcpClient
  $t = $c.ConnectAsync('127.0.0.1', $DshPort)
  $listenOk = $t.Wait(1500)
  $c.Close()
} catch { $listenOk = $false }
$nsRaw = @(netstat -ano 2>$null)
$ns = @(Select-String -InputObject $nsRaw -Pattern ('^\s*TCP\s+127\.0\.0\.1:' + $DshPort + '\s'))
if ($LASTEXITCODE -ne 0 -or $nsRaw.Count -eq 0) {
  Unknown 'netstat 调用失败/无输出 ⇒ 无法判定(不要当成没监听)'
} elseif ($listenOk) {
  Ok ('127.0.0.1:' + $DshPort + ' 可连(TcpClient 实测 connect 成功)⇒ 在监听')
} else {
  $rxListen = ('^\s*TCP\s+127\.0\.0\.1:' + $DshPort + '\s+(0\.0\.0\.0:0|\[::\]:0)\s')
  $listener = @(Select-String -InputObject $nsRaw -Pattern $rxListen)
  if ($listener.Count -gt 0) { Unknown ('connect 失败但 netstat 有监听行(状态词或防火墙原因)→ 原行: ' + $listener[0].ToString().Trim()) }
  elseif ($ns.Count -gt 0) { Unknown ('netstat 有 127.0.0.1:' + $DshPort + ' 的行,但没有「远端=0.0.0.0:0」的监听行 → 原行: ' + $ns[0].ToString().Trim()) }
  else { Todo ('没看到 127.0.0.1:' + $DshPort + ';确认 dsh-desktop.port(默认 43120)与 DSH 是否在跑') }
}
$wide = @(Select-String -InputObject $nsRaw -Pattern ('^\s*TCP\s+(0\.0\.0\.0|\[::\]):' + $DshPort + '\s+(0\.0\.0\.0:0|\[::\]:0)\s'))
if ($wide.Count -gt 0) {
  Todo ('检测到非 loopback 监听 ⇒ networkExposure 可能已变成 lan,本方案不需要:')
  ($wide | Select-Object -First 3) | ForEach-Object { Say ('    ' + $_.ToString().Trim()) }
  Rb '设置 → 桌面 → 网络暴露 改回「仅本机 / loopback」'
}

Say '=== 4. serve ==='
if (-not (Test-Path $ts)) { Todo '未安装,跳过' }
else {
  $ssRaw = (& $ts serve status 2>&1 | Out-String)
  $ssExit = $LASTEXITCODE
  if ($ssExit -ne 0) { Unknown 'CLI 在当前上下文被拒(命名管道 Access is denied)⇒ 请在【用户普通窗口】跑 tailscale serve status;此处无法判定' }
  elseif ($ssRaw -match ('proxy http://127\.0\.0\.1:' + $DshPort)) { Ok 'serve 已指向本机 DSH'; ($ssRaw.Trim() -split '\r?\n') | ForEach-Object { Say ('    ' + $_) } }
  elseif ($ssRaw -match 'proxy http://127\.0\.0\.1:(\d+)') {
    Todo ('serve 指向的是本机 ' + $Matches[1] + ',不是 DSH 端口 ' + $DshPort + ' ⇒ 窄 ACL 写死的端口会失效')
    ($ssRaw.Trim() -split '\r?\n') | ForEach-Object { Say ('    ' + $_) }
  }
  else { Say ('  需要执行(必须带 --bg):  & "' + $ts + '" serve --bg ' + $DshPort); Rb ('tailscale serve reset   # 语义=清空本机全部 serve 配置(不只是这个端口);实测 tailscale serve --help 只有 <target>/status/reset,没有 off') }
}

Say '=== 5. Host 信任(cordis.patch.yml) ==='
# profile 目录解析优先级(不猜):-ProfileDir > $env:DSH_HOME\profiles > $env:USERPROFILE\.dsh\profiles
# 实测本机 DSH_HOME = %USERPROFILE%\.dsh ⇒ profiles = %USERPROFILE%\.dsh\profiles
$profRoots = @()
if ($ProfileDir -ne '') { $profRoots += $ProfileDir }
if ($env:DSH_HOME) { $profRoots += (Join-Path $env:DSH_HOME 'profiles') }
if ($env:USERPROFILE) { $profRoots += (Join-Path (Join-Path $env:USERPROFILE '.dsh') 'profiles') }
$patch = ''
$candidates = @()
foreach ($root in $profRoots) {
  if (-not (Test-Path $root)) { continue }
  $named = Join-Path (Join-Path $root $ProfileName) 'cordis.patch.yml'
  if (Test-Path $named) { $patch = $named; break }
  $candidates += @(Get-ChildItem $root -Directory -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.FullName 'cordis.patch.yml' } | Where-Object { Test-Path $_ })
}
if ($patch -eq '' -and $candidates.Count -eq 1) { $patch = $candidates[0] }
if ($patch -eq '' -and $candidates.Count -gt 1) {
  Unknown ('找到多个 profile,无法判断该改哪一个 ⇒ 请带 -ProfileName 或 -ProfileDir 明确指定(不猜):')
  $candidates | ForEach-Object { Say ('    ' + $_) }
} elseif ($patch -eq '') {
  Unknown ('没找到 profile 的 cordis.patch.yml(查过: ' + ($profRoots -join ' ; ') + ') ⇒ 用 -ProfileDir 明确指定')
} else {
  Ok ('patch 文件 = ' + $patch)
  if ($TsNetHost -eq '') { Todo '未提供 -TsNetHost,跳过(远端 /api 会 403)' }
  elseif (Select-String -Path $patch -Pattern $TsNetHost -SimpleMatch -Quiet) {
    Ok ('已包含 ' + $TsNetHost)
    if (Select-String -Path $patch -Pattern ('trustedHosts:.*' + [regex]::Escape('[' + "'" + $TsNetHost + "'")) -Quiet) {
      Todo '形态检查:看起来只写了字面量。**规范写法必须带上派生的 LAN 字面量**:trustedHosts: [''<host>'', ...ctx.webRuntime.trustedHosts]'
    }
  } else {
    Todo ('需要追加到 ' + $patch + '(整行 config 覆盖语义,别只写字面量):')
    Say '    - id: connection'; Say "      name: '@deepseek-ai/dsh-client-connection'"; Say '      config:'; Say '        trustedHosts:'
    Say ("          - '" + $TsNetHost + "'            # ⚠️ 必须是裸 host[:port];带路径/user@/端口零填充/非规范拼写会被 assertTrustedAuthority 直接抛错")
    Say "          合并写法(推荐): trustedHosts: ['" + $TsNetHost + "', ...ctx.webRuntime.trustedHosts]"
    Rb '删掉该条目后用自带入口重启 DSH'
  }
}

Say '=== 6. 必须人工完成的四件 ==='
Say '  a) 登录 Tailscale(同一账号)';
Say '  b) tailnet 控制台:设备仅保留需要的两台、开账号二次验证、ACL 收紧为单向 tcp:443';
Say '  c) 用 DSH 自带入口重启一次(设置 → 桌面 → 重启),让 trustedHosts 生效';
Say '  d) 电源策略(AC 与 DC 都要查;笔记本只改 AC 会留下断链隐患):';
Say '       AC: 闲置睡眠=0、合盖=不操作';
Say '       DC: 电池下同样要设 —— 市电一断,一小时后自动睡眠 ⇒ 整条链路消失';
Say '       一并确认:合盖动作、快速启动、散热与供电不中断';

Say '=== 7. 验收 ==='
$vs = if ($VerifyScriptPath -ne '') { $VerifyScriptPath } else { Join-Path (Split-Path -Parent $PSCommandPath) 'verify.ps1' }
Say ('  在客户端跑(默认策略下必须带 -File;裸 .\verify.ps1 会被拒):')
Say ('    powershell -NoProfile -ExecutionPolicy Bypass -File ' + $vs + ' -ServerIp <本机 100.x>')
Say '  退出码:0 = 全通(443 connected 且隔离口 timeout);1 = 降级(隔离失效);2 = 阻断。'
