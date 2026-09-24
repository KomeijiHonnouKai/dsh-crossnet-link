<#
  run-fixtures.ps1 - offline regression runner for collect.ps1.

  Runs the collector against every fixture with -NoNative (so no registry, no command
  execution and no network are touched at all) and asserts the verdicts. This is the test
  seam that makes the collector testable on any machine, including one without Tailscale.

  LAST UPDATED : 2026-09-24 (v0)
  COMMANDS USED (all read-only):
    powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/tests/run-fixtures.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/tests/run-fixtures.ps1 -Verbose

  Exit code: 0 = every case passed, 1 = at least one assertion failed.
#>
[CmdletBinding()]
param(
  [string]$Collector = '',
  [string]$FixtureDir = '',
  [switch]$ShowVerdicts
)

$ErrorActionPreference = 'Continue'
$here = $PSScriptRoot
if (-not $Collector) { $Collector = Join-Path $here '..\src\collect.ps1' }
if (-not $FixtureDir) { $FixtureDir = Join-Path $here 'fixtures' }
$Collector = (Resolve-Path -LiteralPath $Collector).Path
$FixtureDir = (Resolve-Path -LiteralPath $FixtureDir).Path

$psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

function Invoke-Collector {
  param([string[]]$ArgList)
  $arr = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$Collector,'-CheckOnly','-AsJson') + $ArgList
  $out = & $psExe @arr 2>&1 | Out-String
  $code = $LASTEXITCODE
  $obj = $null
  try { $obj = $out | ConvertFrom-Json } catch { }
  return [pscustomobject]@{ exitCode=$code; raw=$out; report=$obj }
}

function VerdictMap {
  param($Report)
  $h = @{}
  foreach ($c in @($Report.checks)) { $h[$c.id] = $c.verdict }
  return $h
}

function ReasonMap {
  param($Report)
  $h = @{}
  foreach ($c in @($Report.checks)) { $h[$c.id] = $c.reasonKey }
  return $h
}

$failures = New-Object System.Collections.ArrayList
$caseCount = 0

function Assert-True {
  param([string]$Case,[string]$What,[bool]$Ok,[string]$Detail)
  if ($Ok) { Write-Output ('  ok   ' + $What) }
  else {
    Write-Output ('  FAIL ' + $What + ' -> ' + $Detail)
    [void]$script:failures.Add($Case + ' :: ' + $What + ' -> ' + $Detail)
  }
}

Write-Output ('collector : ' + $Collector)
Write-Output ('fixtures  : ' + $FixtureDir)
Write-Output ''

# --- case 1: real zh-CN capture, replayed offline -----------------------------------
$caseCount++
Write-Output '[case 1] zh.json - real zh-CN capture replayed with -NoNative'
$r1 = Invoke-Collector @('-Role','both','-FixturePath',(Join-Path $FixtureDir 'zh.json'),'-NoNative')
Assert-True 'zh' 'report is parseable JSON' ($null -ne $r1.report) ('exit=' + $r1.exitCode)
if ($null -ne $r1.report) {
  $v1 = VerdictMap $r1.report
  $k1 = ReasonMap $r1.report
  Assert-True 'zh' 'DSH_LOOPBACK_ONLY = pass' ($v1['DSH_LOOPBACK_ONLY'] -eq 'pass') ('' + $v1['DSH_LOOPBACK_ONLY'] + '/' + $k1['DSH_LOOPBACK_ONLY'])
  Assert-True 'zh' 'NIC_PROFILE_ATTRIBUTION = degraded (zh-CN netsh text is a low-confidence path)' (($v1['NIC_PROFILE_ATTRIBUTION'] -eq 'degraded') -and ($k1['NIC_PROFILE_ATTRIBUTION'] -eq 'nic_ok')) ('' + $v1['NIC_PROFILE_ATTRIBUTION'] + '/' + $k1['NIC_PROFILE_ATTRIBUTION'])
  $nic1 = @($r1.report.checks | Where-Object { $_.id -eq 'NIC_PROFILE_ATTRIBUTION' })
  Assert-True 'zh' 'that downgrade is visible in evidence.confidence/confidenceDowngrade' (($nic1[0].evidence.confidence -eq 'low') -and ($nic1[0].evidence.confidenceDowngrade -eq $true)) ('confidence=' + $nic1[0].evidence.confidence)
  Assert-True 'zh' 'TAILSCALE_PROCESS_EDGE_DB = pass (registry means Edge=TRUE)' ($v1['TAILSCALE_PROCESS_EDGE_DB'] -eq 'pass') ('' + $k1['TAILSCALE_PROCESS_EDGE_DB'])
  Assert-True 'zh' 'FIREWALL_PROFILES = pass' ($v1['FIREWALL_PROFILES'] -eq 'pass') ('' + $k1['FIREWALL_PROFILES'])
  Assert-True 'zh' 'TRUSTED_HOSTS_PATCH = blocked (patch has trustedHosts: [])' ($v1['TRUSTED_HOSTS_PATCH'] -eq 'blocked') ('' + $k1['TRUSTED_HOSTS_PATCH'])
  Assert-True 'zh' 'POWER_STANDBY_IDLE_AC_DC = pass (AC=DC=0x0)' ($v1['POWER_STANDBY_IDLE_AC_DC'] -eq 'pass') ('' + $k1['POWER_STANDBY_IDLE_AC_DC'])
  Assert-True 'zh' 'NO_NEW_WILDCARD_LISTENER = pass' ($v1['NO_NEW_WILDCARD_LISTENER'] -eq 'pass') ('' + $k1['NO_NEW_WILDCARD_LISTENER'])
  Assert-True 'zh' 'CREDENTIAL_DISCIPLINE = pass' ($v1['CREDENTIAL_DISCIPLINE'] -eq 'pass') ('' + $k1['CREDENTIAL_DISCIPLINE'])
  Assert-True 'zh' 'TAILSCALE_CLI_LAYER = unknown/ts_pipe_denied (sandbox, not "not configured")' (($v1['TAILSCALE_CLI_LAYER'] -eq 'unknown') -and ($k1['TAILSCALE_CLI_LAYER'] -eq 'ts_pipe_denied')) ('' + $v1['TAILSCALE_CLI_LAYER'] + '/' + $k1['TAILSCALE_CLI_LAYER'])
  Assert-True 'zh' 'unknown present => exit code is not 0' ($r1.exitCode -ne 0) ('exit=' + $r1.exitCode)
  Assert-True 'zh' 'blocked present => exit code is 2' ($r1.exitCode -eq 2) ('exit=' + $r1.exitCode)
  if ($ShowVerdicts) { $v1.GetEnumerator() | Sort-Object Name | ForEach-Object { Write-Output ('    ' + $_.Key + ' = ' + $_.Value) } }
}

# --- case 2: English variant must parse with English patterns ------------------------
$caseCount++
Write-Output ''
Write-Output '[case 2] en.json - same state, English tool output'
$r2 = Invoke-Collector @('-Role','both','-FixturePath',(Join-Path $FixtureDir 'en.json'),'-NoNative')
Assert-True 'en' 'report is parseable JSON' ($null -ne $r2.report) ('exit=' + $r2.exitCode)
if ($null -ne $r2.report) {
  $v2 = VerdictMap $r2.report
  $k2 = ReasonMap $r2.report
  Assert-True 'en' 'NIC_PROFILE_ATTRIBUTION = degraded via the English netsh pattern' (($v2['NIC_PROFILE_ATTRIBUTION'] -eq 'degraded') -and ($k2['NIC_PROFILE_ATTRIBUTION'] -eq 'nic_ok')) ('' + $v2['NIC_PROFILE_ATTRIBUTION'] + '/' + $k2['NIC_PROFILE_ATTRIBUTION'])
  Assert-True 'en' 'FIREWALL_PROFILES = pass (netsh fallback parsed 3 sections)' ($v2['FIREWALL_PROFILES'] -eq 'pass') ('' + $k2['FIREWALL_PROFILES'])
  Assert-True 'en' 'TAILSCALE_PROCESS_EDGE_DB = pass with the echoed value parsed' ($v2['TAILSCALE_PROCESS_EDGE_DB'] -eq 'pass') ('' + $k2['TAILSCALE_PROCESS_EDGE_DB'])
  Assert-True 'en' 'POWER_S0_CAPABILITY = degraded/low (structure parse of a localized powercfg /a)' (($v2['POWER_S0_CAPABILITY'] -eq 'degraded') -and ($k2['POWER_S0_CAPABILITY'] -eq 's0_ok')) ('' + $v2['POWER_S0_CAPABILITY'] + '/' + $k2['POWER_S0_CAPABILITY'])
  if ($null -ne $r1.report) {
    $v1 = VerdictMap $r1.report
    $diff = New-Object System.Collections.ArrayList
    foreach ($id in $v1.Keys) { if ($v2[$id] -ne $v1[$id]) { [void]$diff.Add($id + '(' + $v1[$id] + '->' + $v2[$id] + ')') } }
    Assert-True 'en' 'every verdict matches the zh-CN capture' ($diff.Count -eq 0) (($diff.ToArray()) -join ', ')
  }
}

# --- case 3: unmatched localization must fail closed, never guess --------------------
$caseCount++
Write-Output ''
Write-Output '[case 3] localized-unmatched.json - German-style field names, nothing matched'
$r3 = Invoke-Collector @('-Role','both','-FixturePath',(Join-Path $FixtureDir 'localized-unmatched.json'),'-NoNative')
Assert-True 'unmatched' 'report is parseable JSON' ($null -ne $r3.report) ('exit=' + $r3.exitCode)
if ($null -ne $r3.report) {
  $v3 = VerdictMap $r3.report
  $k3 = ReasonMap $r3.report
  Assert-True 'unmatched' 'NIC_PROFILE_ATTRIBUTION = unknown (never guessed)' ($v3['NIC_PROFILE_ATTRIBUTION'] -eq 'unknown') ('' + $v3['NIC_PROFILE_ATTRIBUTION'] + '/' + $k3['NIC_PROFILE_ATTRIBUTION'])
  Assert-True 'unmatched' 'TAILSCALE_PROCESS_EDGE_DB = unknown (no registry store in this fixture)' ($v3['TAILSCALE_PROCESS_EDGE_DB'] -eq 'unknown') ('' + $k3['TAILSCALE_PROCESS_EDGE_DB'])
  Assert-True 'unmatched' 'raw netsh text is preserved for a human' (($null -ne $r3.report.checks) -and (@(($r3.report.checks | Where-Object { $_.id -eq 'NIC_PROFILE_ATTRIBUTION' }).raw.netshRawOutput).Count -gt 0)) 'netshRawOutput empty'
  Assert-True 'unmatched' 'unknown present => exit code is not 0' ($r3.exitCode -ne 0) ('exit=' + $r3.exitCode)
}

# --- case 4: Edge drift regression ---------------------------------------------------
$caseCount++
Write-Output ''
Write-Output '[case 4] edge-false.json - Tailscale-Process Edge=FALSE must be caught'
$r4 = Invoke-Collector @('-Role','server','-FixturePath',(Join-Path $FixtureDir 'edge-false.json'),'-NoNative')
Assert-True 'edge' 'report is parseable JSON' ($null -ne $r4.report) ('exit=' + $r4.exitCode)
if ($null -ne $r4.report) {
  $v4 = VerdictMap $r4.report
  $k4 = ReasonMap $r4.report
  Assert-True 'edge' 'TAILSCALE_PROCESS_EDGE_DB = blocked/edge_false' (($v4['TAILSCALE_PROCESS_EDGE_DB'] -eq 'blocked') -and ($k4['TAILSCALE_PROCESS_EDGE_DB'] -eq 'edge_false')) ('' + $v4['TAILSCALE_PROCESS_EDGE_DB'] + '/' + $k4['TAILSCALE_PROCESS_EDGE_DB'])
  Assert-True 'edge' 'TAILSCALE_IN_RULES stays pass (Edge=No there is normal)' ($v4['TAILSCALE_IN_RULES'] -eq 'pass') ('' + $k4['TAILSCALE_IN_RULES'])
  Assert-True 'edge' 'a blocked finding => exit 2' ($r4.exitCode -eq 2) ('exit=' + $r4.exitCode)
  $edgeCheck = @($r4.report.checks | Where-Object { $_.id -eq 'TAILSCALE_PROCESS_EDGE_DB' })
  Assert-True 'edge' 'a remediation plus rollback text is attached' (($edgeCheck.Count -eq 1) -and ($null -ne $edgeCheck[0].remediation) -and ([string]$edgeCheck[0].remediation.rollback).Length -gt 0) 'remediation/rollback missing'
  Assert-True 'edge' 'remediation is not auto-applied' ($edgeCheck[0].remediation.applied -eq $false) 'applied=true'
}

# --- case 5: role selection and peer-argument fail-closed behaviour ------------------
$caseCount++
Write-Output ''
Write-Output '[case 5] role filtering and missing -Peer are fail-closed'
$r5 = Invoke-Collector @('-Role','client','-FixturePath',(Join-Path $FixtureDir 'zh.json'),'-NoNative')
Assert-True 'client' 'report is parseable JSON' ($null -ne $r5.report) ('exit=' + $r5.exitCode)
if ($null -ne $r5.report) {
  $ids5 = @($r5.report.checks | ForEach-Object { $_.id })
  Assert-True 'client' 'no server-only check is emitted under -Role client' (@($ids5 | Where-Object { $_ -in @('SERVE_PRESENT','TRUSTED_HOSTS_PATCH','NIC_PROFILE_ATTRIBUTION','POWER_STANDBY_IDLE_AC_DC') }).Count -eq 0) (($ids5 | Where-Object { $_ -in @('SERVE_PRESENT','TRUSTED_HOSTS_PATCH') }) -join ',')
  $v5 = VerdictMap $r5.report
  $k5 = ReasonMap $r5.report
  Assert-True 'client' 'PEER_TCP_443 = unknown/peer_not_provided without -Peer' (($v5['PEER_TCP_443'] -eq 'unknown') -and ($k5['PEER_TCP_443'] -eq 'peer_not_provided')) ('' + $v5['PEER_TCP_443'] + '/' + $k5['PEER_TCP_443'])
  Assert-True 'client' 'unknown present => exit code is not 0' ($r5.exitCode -ne 0) ('exit=' + $r5.exitCode)
}

# --- case 6: Win11 server candidate - the degraded step of the ladder ----------------
$caseCount++
Write-Output ''
Write-Output '[case 6] win11-server.json - healthy Win11 server, only the battery power policy is a hazard'
$r6 = Invoke-Collector @('-Role','server','-FixturePath',(Join-Path $FixtureDir 'win11-server.json'),'-NoNative')
Assert-True 'win11' 'report is parseable JSON' ($null -ne $r6.report) ('exit=' + $r6.exitCode)
if ($null -ne $r6.report) {
  $v6 = VerdictMap $r6.report
  $k6 = ReasonMap $r6.report
  $osCheck = @($r6.report.checks | Where-Object { $_.id -eq 'OS_BUILD' })
  Assert-True 'win11' 'OS_BUILD = pass with branch=win11' (($v6['OS_BUILD'] -eq 'pass') -and ($osCheck[0].raw.branch -eq 'win11')) ('branch=' + $osCheck[0].raw.branch)
  Assert-True 'win11' 'POWER_STANDBY_IDLE_AC_DC = degraded/power_dc_only (DC 0xe10 = 3600 s)' (($v6['POWER_STANDBY_IDLE_AC_DC'] -eq 'degraded') -and ($k6['POWER_STANDBY_IDLE_AC_DC'] -eq 'power_dc_only')) ('' + $v6['POWER_STANDBY_IDLE_AC_DC'] + '/' + $k6['POWER_STANDBY_IDLE_AC_DC'])
  $pCheck = @($r6.report.checks | Where-Object { $_.id -eq 'POWER_STANDBY_IDLE_AC_DC' })
  Assert-True 'win11' 'the DC value is reported as 3600 seconds' ($pCheck[0].raw.dcSeconds -eq 3600) ('dcSeconds=' + $pCheck[0].raw.dcSeconds)
  Assert-True 'win11' 'POWER_S0_CAPABILITY reports S0 as present (degraded: structure parse)' (($v6['POWER_S0_CAPABILITY'] -eq 'degraded') -and ($pCheck.Count -eq 1)) ('' + $v6['POWER_S0_CAPABILITY'])
  $s0Check = @($r6.report.checks | Where-Object { $_.id -eq 'POWER_S0_CAPABILITY' })
  Assert-True 'win11' 'the S0 raw line is preserved for the human' ($s0Check[0].raw.s0Available -eq 'yes') ('s0Available=' + $s0Check[0].raw.s0Available)
  Assert-True 'win11' 'SERVE_PRESENT = pass (443 owned by tailscaled)' ($v6['SERVE_PRESENT'] -eq 'pass') ('' + $v6['SERVE_PRESENT'] + '/' + $k6['SERVE_PRESENT'])
  Assert-True 'win11' 'NIC_PROFILE_ATTRIBUTION = pass via the Get-NetConnectionProfile enum' (($v6['NIC_PROFILE_ATTRIBUTION'] -eq 'pass') -and ($k6['NIC_PROFILE_ATTRIBUTION'] -eq 'nic_ok')) ('' + $k6['NIC_PROFILE_ATTRIBUTION'])
  $nicCheck = @($r6.report.checks | Where-Object { $_.id -eq 'NIC_PROFILE_ATTRIBUTION' })
  Assert-True 'win11' 'the profile came from the enum source' ($nicCheck[0].raw.matchMethod -eq 'Get-NetConnectionProfile') ('method=' + $nicCheck[0].raw.matchMethod)
  Assert-True 'win11' 'that pass stays pass with confidence=high (no text parsing involved)' (($nicCheck[0].evidence.confidence -eq 'high') -and ($nicCheck[0].evidence.confidenceDowngrade -eq $false)) ('confidence=' + $nicCheck[0].evidence.confidence)
  Assert-True 'win11' 'TAILSCALE_CLI_LAYER = pass (ip -4 exit 0)' ($v6['TAILSCALE_CLI_LAYER'] -eq 'pass') ('' + $v6['TAILSCALE_CLI_LAYER'] + '/' + $k6['TAILSCALE_CLI_LAYER'])
  Assert-True 'win11' 'TRUSTED_HOSTS_PATCH = pass (patch carries a ts.net authority)' ($v6['TRUSTED_HOSTS_PATCH'] -eq 'pass') ('' + $v6['TRUSTED_HOSTS_PATCH'] + '/' + $k6['TRUSTED_HOSTS_PATCH'])
  Assert-True 'win11' 'no blocked item' ($v6.Values -notcontains 'blocked') ((@($v6.Keys | Where-Object { $v6[$_] -eq 'blocked' })) -join ',')
  Assert-True 'win11' 'no unknown item (every probe answered)' ($v6.Values -notcontains 'unknown') ((@($v6.Keys | Where-Object { $v6[$_] -eq 'unknown' })) -join ',')
  Assert-True 'win11' 'degraded only => exit 1 (the middle step of the ladder)' ($r6.exitCode -eq 1) ('exit=' + $r6.exitCode)
  if ($ShowVerdicts) { $v6.GetEnumerator() | Sort-Object Name | ForEach-Object { Write-Output ('    ' + $_.Key + ' = ' + $_.Value) } }
}

# --- case 7: -Apply must be refused ---------------------------------------------------
$caseCount++
Write-Output ''
Write-Output '[case 7] -Apply is refused (no write path exists)'
$arr6 = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$Collector,'-CheckOnly','-Apply')
$out6 = & $psExe @arr6 2>&1 | Out-String
Assert-True 'apply' '-Apply refuses and exits 2' ($LASTEXITCODE -eq 2) ('exit=' + $LASTEXITCODE)
Assert-True 'apply' 'refusal is explained on stdout' ($out6 -match 'REFUSED') $out6

Write-Output ''
if ($failures.Count -eq 0) {
  Write-Output ('ALL PASS: ' + $caseCount + ' cases, 0 failed assertions')
  exit 0
}
Write-Output ('FAILED assertions: ' + $failures.Count)
foreach ($f in $failures) { Write-Output ('  - ' + $f) }
exit 1
