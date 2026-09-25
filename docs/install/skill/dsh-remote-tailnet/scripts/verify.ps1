<#
  verify.ps1 —— 三态验收 + soak 巡检(纯 .NET,不依赖 curl / CIM)
  最后更新:2026-09-24 17:04(W4)
  本次使用的命令(逐字执行过;<PEER_IP> = 对端 tailnet 100.x,本文件不写死任何真实对端地址):
    powershell -NoProfile -ExecutionPolicy Bypass -File .dsh/skills/dsh-remote-tailnet/scripts/verify.ps1 -ServerIp <PEER_IP>
    powershell -NoProfile -ExecutionPolicy Bypass -File .dsh/skills/dsh-remote-tailnet/scripts/verify.ps1 -ServerIp 127.0.0.1 -Soak -Count 3 -IntervalSeconds 5
    powershell -NoProfile -Command '$f=".dsh/skills/dsh-remote-tailnet/scripts/verify.ps1"; $b=[IO.File]::ReadAllBytes((Resolve-Path $f)); $e=$null; [void][Management.Automation.Language.Parser]::ParseFile((Resolve-Path $f),[ref]$null,[ref]$e); "bom=" + ($b[0..2] -join ",") + " errors=" + @($e).Count'

  用法(本机默认 ExecutionPolicy = Restricted:裸 `.\verify.ps1` 会被拒,报
  「cannot be loaded because running scripts is disabled on this system」⇒ 必须用 -File 形态):
    powershell -NoProfile -ExecutionPolicy Bypass -File <本文件> -ServerIp <PEER_IP>
    powershell -NoProfile -ExecutionPolicy Bypass -File <本文件> -ServerIp <PEER_IP> -Ports 443,135,5357
    powershell -NoProfile -ExecutionPolicy Bypass -File <本文件> -ServerIp <PEER_IP> -Soak -Count 11 -IntervalSeconds 30

  退出码(有语义,不再是恒 0):
    0 = 全通  —— 链路口 connected 且所有隔离口 timeout;soak 每一轮都 connected
    1 = 降级  —— 链路口 connected,但隔离不成立(非链路口也 connected ⇒ ACL/隔离没生效);soak 部分失败
    2 = 阻断  —— 链路口 refused/timeout/出错(serve 挂了或包被丢);soak 全失败;或参数非法
  参数:
    -LinkPort   判定「链路通不通」的那个口,默认 443(= 窄 ACL 写死的那个)
    -Ports      要探测的端口列表,默认 '443,135,5357'。**多值必须加引号或用逗号**:
                  · 正确:`-Ports 135,5357` ✓ / `-Ports '135 5357'` ✓
                  · 实测坑:写成 `-Ports 135 5357`(空格、无引号)时,第二个值会被绑到 `-LinkPort`,
                    于是 VERDICT 直接报「未探测 -LinkPort 5357」并 EXIT 2 —— **不会静默少探**;
                  · 为什么不用 [int[]]:实测 -File 下 `-Ports 135,5357` 会被绑成单个整数 1355357(逗号被吃掉),
                    故此参数按字符串接收后再自己切分。
  说明:
    · 只用 [Net.Sockets.TcpClient],不碰 CIM/WMI(受限沙箱里那些会被拒)
    · HTTPS/证书判定请另用 Node(Windows 的 curl/schannel 在受限环境做不了 TLS);
      本机 `node` 不在 PATH 时用:`$env:ELECTRON_RUN_AS_NODE=1` + '<APP_DIR>\DSH Desktop.exe' <script.js>
    · soak 的结论表述必须限定窗口
#>
param(
  [CmdletBinding(PositionalBinding=$false)]
  [string]$ServerIp = '',
  [string]$Ports = '443,135,5357',
  [int]$LinkPort = 443,
  [int]$TimeoutMs = 5000,
  [switch]$Soak,
  [int]$Count = 11,
  [int]$IntervalSeconds = 30
)

# ⚠️ -Ports 用 [string] 接收再自己切分,不用 [int[]]:
#    实测 `-File ... -Ports 135,5357` 在 PowerShell 5.1 下会被绑成一个数 1355357(逗号被吃掉),
#    于是「探测两个口」静默变成「探测一个口」⇒ 一律按字符串切分,兼容 `-Ports 135,5357` 与 `-Ports '135,5357'`。
$portList = @()
foreach ($piece in ($Ports -split '[,\s;]+')) {
  if ($piece -eq '') { continue }
  $n = 0
  if (-not [int]::TryParse($piece, [ref]$n) -or $n -lt 1 -or $n -gt 65535) {
    '参数非法:-Ports 含无法解析为 1..65535 的项: ' + $piece + ' ⇒ 退出码 2'
    exit 2
  }
  if (-not ($portList -contains $n)) { $portList += $n }
}
# 未绑定到任何参数的多余实参:最常见来源是 `-Ports 135 5357` 少写引号 ⇒ 实测会被静默丢弃、
# 于是「探测两个口」变成「只探一个口」。宁可阻断,也不静默少探。
# 注意:param() 里加了 [CmdletBinding(PositionalBinding=$false)],所以那种写法会在绑定期直接报错;
# 下面这条 $args 检查是第二道闸(同样走「阻断」而不是静默少探)。
if ($args.Count -gt 0) {
  '参数非法:有未绑定的多余参数 → ' + ($args -join ' ') + ' ⇒ 想让 -Ports 接多个值时加引号: -Ports ''135 5357''(或 -Ports 135,5357);退出码 2'
  exit 2
}

function Probe([string]$ip, [int]$port, [int]$ms) {
  $c = New-Object Net.Sockets.TcpClient
  $t0 = Get-Date
  try {
    $task = $c.ConnectAsync($ip, $port)
    if (-not $task.Wait($ms)) { return @{ port = $port; result = 'timeout'; ms = [int]((Get-Date) - $t0).TotalMilliseconds } }
    return @{ port = $port; result = 'connected'; ms = [int]((Get-Date) - $t0).TotalMilliseconds }
  } catch {
    return @{ port = $port; result = ('refused/err: ' + $_.Exception.InnerException.SocketErrorCode); ms = [int]((Get-Date) - $t0).TotalMilliseconds }
  } finally { $c.Close() }
}

if ([string]::IsNullOrWhiteSpace($ServerIp)) {
  '参数非法:-ServerIp 为空 ⇒ 退出码 2'
  exit 2
}
if ($Count -lt 1) { '参数非法:-Count 必须 >= 1 ⇒ 退出码 2'; exit 2 }

if (-not $Soak) {
  $results = @()
  foreach ($p in $portList) {
    $r = Probe $ServerIp $p $TimeoutMs
    $results += $r
    '{0}:{1} -> {2} ({3}ms)' -f $ServerIp, $r.port, $r.result, $r.ms
  }
  ''

  $link = @($results | Where-Object { $_.port -eq $LinkPort }) | Select-Object -First 1
  $others = @($results | Where-Object { $_.port -ne $LinkPort })
  $leaked = @($others | Where-Object { $_.result -eq 'connected' })
  $code = 0
  $verdict = ''
  if ($null -eq $link) {
    $code = 2
    $verdict = ('未探测 -LinkPort ' + $LinkPort + '(不在 -Ports 里)⇒ 无法判定链路,退出码 2')
  } elseif ($link.result -ne 'connected') {
    $code = 2
    $verdict = ($LinkPort.ToString() + ' = ' + $link.result + ' ⇒ 阻断:serve 挂了(refused)或包被丢(timeout),见 troubleshooting.md')
  } elseif ($leaked.Count -gt 0) {
    $code = 1
    $verdict = ('降级:' + (($leaked | ForEach-Object { $_.port }) -join '/') + ' 也 connected ⇒ 隔离没生效(ACL 未收紧或端口没被拦),链路本身是通的')
  } else {
    $code = 0
    $verdict = ('全通:' + $LinkPort + ' connected,其余 ' + ($others.Count) + ' 个口均 timeout(ACL 隔离成立)')
  }
  '判读:' + $LinkPort + ' connected = 链路通(随后应能拿到 401/303/200);refused = 对端无监听(serve 挂了);timeout = 包被丢(见 troubleshooting.md)。'
  '非 ' + $LinkPort + ' 端口期望 timeout(ACL 隔离);若也 connected,说明 ACL 没生效。'
  'VERDICT ' + $verdict
  'EXIT ' + $code
  exit $code
}

$ok = 0; $lines = @()
for ($i = 1; $i -le $Count; $i++) {
  $r = Probe $ServerIp $LinkPort $TimeoutMs
  if ($r.result -eq 'connected') { $ok++ }
  $line = '{0} #{1} {2} {3}ms' -f (Get-Date -Format HH:mm:ss), $i, $r.result, $r.ms
  $lines += $line; $line
  if ($i -lt $Count) { Start-Sleep -Seconds $IntervalSeconds }
}
'SOAK total={0} connected={1} failed={2}' -f $Count, $ok, ($Count - $ok)
'结论模板:该 {0} 秒窗口内 {1}/{2} connected —— 表述必须限定窗口,不要写成「链路稳定」。' -f (($Count - 1) * $IntervalSeconds + $TimeoutMs / 1000), $ok, $Count
$code = 0
if ($ok -eq 0) { $code = 2 } elseif ($ok -lt $Count) { $code = 1 }
'VERDICT ' + (@('全通:窗口内全部 connected', '降级:窗口内部分失败', '阻断:窗口内全部失败')[$code])
'EXIT ' + $code
exit $code
