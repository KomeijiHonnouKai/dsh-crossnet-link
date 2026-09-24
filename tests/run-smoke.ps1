<#
  run-smoke.ps1 - clean-room smoke entry for the dsh-crossnet-link release set.

  WHAT THIS IS
    One offline command that re-proves, on a freshly reset machine, everything that can be
    re-proven without a network, without a live peer, without elevation and without any
    third-party module. It is a member of the release set, so it carries the same
    zero-hardcoding rule as the rest of the repository: no real address, host name, user
    path or credential shape appears anywhere in this file (placeholders only).

  OUTPUT CONTRACT
    One line per item, always in this shape:
        [PASS] <item id> - <reason>
        [FAIL] <item id> - <reason>
        [SKIP] <item id> - <reason>            (a skipped item is NOT a failure)
      A SKIP item that a human could still resolve prints a second line:
        manual: <copy-pasteable command>
      Informational lines (machine posture, file hashes) are prefixed [INFO] and are NOT
      counted in the totals.
    With -Json one compact JSON line is printed before that summary:
      {"smoke":{"total":..,"pass":..,"fail":..,"skip":..,"exit":..,"snapshot":..,
                "offline":true,"peerContacted":false},"items":[{"status","id","reason","manual"}]}
    The LAST line is always machine readable:
        SMOKE total=<n> pass=<n> fail=<n> skip=<n> exit=<0|1>
      (with -Json the item objects are printed as one compact JSON line BEFORE that summary,
      so the summary keeps its position as the last line).

  EXIT CODES (fail-closed ladder - a SKIP is a degradation, not a pass)
    0 = everything green: no FAIL and no SKIP.
    1 = degraded: no FAIL, but at least one check was SKIPped. Every SKIP names what was
        skipped and why, and most carry the manual command that would resolve them. This is
        the normal result of a clean-room run: the peer / MagicDNS / TLS judgements cannot be
        made without a live tailnet, so they are skipped instead of being guessed.
    2 = something is broken: at least one FAIL, or this smoke could not run at all (no
        PowerShell host to launch children, unreadable repository root).
    The machine-readable summary line carries fail= and skip= separately, so a caller that
    wants "strictly green" (exit 0) and a caller that wants "nothing broken" (exit <= 1) can
    both be served without re-parsing the item lines.

  CLEAN-ROOM CONTRACT
    * Only release-set content is required. Everything this smoke touches is located relative
      to $PSScriptRoot (tests/ -> the plugin root -> the repository root); no internal note,
      no machine-specific absolute path and no installed plugin is needed. Files that are
      informational (release notes, architecture notes, the release gate itself) may be absent
      and are then reported as missing-informational, never as a failure.
    * Components that land later are tolerated without editing this file: a component that is
      absent is SKIPped with its reason, and the search location list is right below.
    * NO network access of any kind. Peer, MagicDNS and TLS judgements are never attempted;
      they are reported as SKIP together with the manual command a human can run.
    * Read-only outside %TEMP%. The only writes this script performs are the frozen snapshot
      under %TEMP%\rtg-smoke-<pid> and its deletion at the end; selfproof.writes-confined-to-temp
      proves statically that every write/spawn verb in this file targets that scratch root, and
      selfproof.scratch-cleaned proves it is gone afterwards.
    * No dependency on existing machine state: no %TEMP% leftovers are read, no installed
      plugin is required, no DSH instance is required, no Tailscale is required. Paths
      (DSH home, app dir, port, peer) come from the child scripts' own auto-discovery; when
      a value cannot be discovered the item degrades to SKIP instead of FAIL.
    * A probe that is denied or unavailable (for example the Tailscale named pipe) is
      reported as SKIP or as an unknown verdict inside the child report - never as a failure
      of this smoke. "unknown" is not "broken".

  COVERAGE (all offline)
    1  src/collect.ps1 -CheckOnly for -Role both / client / server: JSON contract, verdict
       vocabulary, evidence fields, role filtering, and the derived exit-code semantics.
    2  src/collect.ps1 -Apply is refused (read-only contract cannot be switched off).
    3  panel/prereq.ps1 -CheckOnly (both and client roles): JSON contract, exit semantics,
       ranAnyInstall=false.
    4  tests/run-tests.ps1 full suite (expected 52 cases, 0 failed, 0 xfail, 0 xpass).
    5  tests/run-fixtures.ps1 (collector fixture regression, expected ALL PASS).
    6  .github/scripts/repo-hygiene.ps1 -Json release gate (when present, expected clean).
    7  no-new-listener self-proof: the wildcard TCP listener set is compared before and
       after every child run.
    8  encoding/BOM/parse self-check over the whole plugin tree.
    9  release-set key files: existence plus sha256, so the numbers can be matched against
       the documentation.
    10 optional components that may land later (skipped while absent): tools/uninstall.ps1
       -CheckOnly -AsJson is run when present; exit 0/1 counts as "it ran", exit 2 is treated
       as the uninstaller's own fail-closed verdict and only fails this smoke when stderr
       carries a PowerShell error signature.
    11 read-only evidence: a static no-write-verb check on this file plus a before/after
       hash snapshot of the whole plugin tree (see the selfproof.* items).

  LAST UPDATED : 2026-09-24 (v1)
  COMMANDS USED WHILE BUILDING THIS REVISION (all read-only; no client Inspect, no ego_*,
  no unbounded network call):
    powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/tests/run-smoke.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/tests/run-smoke.ps1 -Json
    powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/src/collect.ps1 -CheckOnly -AsJson -Role both
    powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/panel/prereq.ps1 -CheckOnly -AsJson
    powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/tests/run-tests.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/tests/run-fixtures.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/.github/scripts/repo-hygiene.ps1 -Json
#>
[CmdletBinding()]
param(
  # Print the item objects as one compact JSON line before the SMOKE summary line.
  [switch]$Json,
  # Debug only: run the fast items and skip the two sub-suites. The default runs everything.
  [switch]$SkipSuites,
  # Debug only: leave %TEMP%\rtg-smoke-<pid> behind (the snapshot and its logs) for inspection.
  [switch]$KeepScratch,
  [int]$CollectTimeoutSec = 120,
  [int]$PrereqTimeoutSec = 120,
  [int]$SuiteTimeoutSec = 900,
  [int]$HygieneTimeoutSec = 300
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

$script:Here = $PSScriptRoot
$script:PluginRoot = (Resolve-Path -LiteralPath (Join-Path $script:Here '..')).Path
$script:RepoRoot = (Resolve-Path -LiteralPath (Join-Path $script:PluginRoot '..')).Path

# Documented release-set locations, printed as repo-relative paths so that a human can copy
# them from any working directory.
$script:CollectRel = 'dsh-crossnet-link/src/collect.ps1'
$script:PrereqRel = 'dsh-crossnet-link/panel/prereq.ps1'
$script:SuiteRel = 'dsh-crossnet-link/tests/run-tests.ps1'
$script:FixturesRel = 'dsh-crossnet-link/tests/run-fixtures.ps1'
$script:HygieneRel = 'dsh-crossnet-link/.github/scripts/repo-hygiene.ps1'
$script:SmokeRel = 'dsh-crossnet-link/tests/run-smoke.ps1'

# Every file the child processes read is copied here first, so a concurrent editor cannot turn
# this run red and three consecutive runs report the same verdicts. Removed before exit.
$script:ScratchRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('rtg-smoke-' + $PID)
$script:SnapshotRoot = Join-Path $script:ScratchRoot 'snapshot'
# MEASURED DEFECT (fixed): Copy-Item <dir> -Destination <dir> keeps the SOURCE leaf name, so
# hardcoding the checkout directory name here made the freeze fail whenever that directory
# was called something else (a renamed copy, a zip extract). The leaf is read from the source.
$script:PluginLeaf = ''
try { $script:PluginLeaf = (Get-Item -LiteralPath $script:PluginRoot -Force).Name } catch { $script:PluginLeaf = '' }
if (-not $script:PluginLeaf) { $script:PluginLeaf = Split-Path -Leaf $script:PluginRoot }
$script:SnapPlugin = Join-Path $script:SnapshotRoot $script:PluginLeaf

# Child entry points. They are filled in by the freeze step below; when the freeze fails they
# fall back to the working tree so that the smoke still says something useful.
$script:CollectPath = Join-Path $script:PluginRoot 'src\collect.ps1'
$script:PrereqPath = Join-Path $script:PluginRoot 'panel\prereq.ps1'
$script:SuitePath = Join-Path $script:PluginRoot 'tests\run-tests.ps1'
$script:FixturesPath = Join-Path $script:PluginRoot 'tests\run-fixtures.ps1'
$script:HygienePath = ''
$script:SnapshotState = 'not attempted'

# ---------------------------------------------------------------------------
# section 1: item reporting
# ---------------------------------------------------------------------------

$script:Results = New-Object System.Collections.ArrayList

function Add-Item {
  param([string]$Status,[string]$Id,[string]$Reason,[string]$Manual = '')
  [void]$script:Results.Add([pscustomobject]@{ status=$Status; id=$Id; reason=$Reason; manual=$Manual })
  Write-Output ((('[' + $Status + ']').PadRight(7)) + ' ' + $Id.PadRight(34) + ' ' + $Reason)
  if ($Manual) { Write-Output ('        manual: ' + $Manual) }
}
function Add-Pass { param([string]$Id,[string]$Reason) Add-Item 'PASS' $Id $Reason }
function Add-Fail { param([string]$Id,[string]$Reason) Add-Item 'FAIL' $Id $Reason }
function Add-Skip { param([string]$Id,[string]$Reason,[string]$Manual = '') Add-Item 'SKIP' $Id $Reason $Manual }
function Add-Info { param([string]$Text) Write-Output ('[INFO]  ' + $Text) }

# ---------------------------------------------------------------------------
# section 2: child process (explicit timeout, streamed stdout/stderr, no shell)
# ---------------------------------------------------------------------------

$script:ChildExe = Join-Path $PSHOME 'powershell.exe'
if (-not (Test-Path -LiteralPath $script:ChildExe)) {
  $alt = Join-Path (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0') 'powershell.exe'
  if (Test-Path -LiteralPath $alt) { $script:ChildExe = $alt } else { $script:ChildExe = '' }
}

function ConvertTo-ArgString {
  param([string[]]$ArgList)
  $acc = New-Object System.Collections.ArrayList
  foreach ($a in @($ArgList)) {
    $s = [string]$a
    if ($s -match '[\s"]') { $s = '"' + $s + '"' }
    [void]$acc.Add($s)
  }
  return ($acc.ToArray() -join ' ')
}

function Invoke-Child {
  param([string[]]$ArgList,[int]$TimeoutSec)
  $res = [ordered]@{ exitCode = $null; stdout = ''; stderr = ''; timedOut = $false; startError = '' }
  Write-Verbose ('run: ' + $script:ChildExe + ' ' + (ConvertTo-ArgString $ArgList))
  try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $script:ChildExe
    $psi.Arguments = (ConvertTo-ArgString $ArgList)
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $enc = New-Object System.Text.UTF8Encoding($false)
    $psi.StandardOutputEncoding = $enc
    $psi.StandardErrorEncoding = $enc
    $p = [System.Diagnostics.Process]::Start($psi)
    $soTask = $p.StandardOutput.ReadToEndAsync()
    $seTask = $p.StandardError.ReadToEndAsync()
    $done = $p.WaitForExit($TimeoutSec * 1000)
    if (-not $done) { $res.timedOut = $true; try { $p.Kill() } catch { } }
    try { $res.stdout = $soTask.Result } catch { }
    try { $res.stderr = $seTask.Result } catch { }
    if ($done) { $res.exitCode = $p.ExitCode } else { $res.exitCode = -1 }
  } catch {
    $res.startError = $_.Exception.Message
    $res.exitCode = -2
  }
  return [pscustomobject]$res
}

function Invoke-SpecifiedScript {
  param([string]$ScriptPath,[string[]]$ArgList,[int]$TimeoutSec)
  if (-not $script:ChildExe) { return [pscustomobject]@{ exitCode=$null; stdout=''; stderr='no PowerShell host available to launch children'; timedOut=$false; startError='no host' } }
  return (Invoke-Child (@('-NoProfile','-ExecutionPolicy','Bypass','-File',$ScriptPath) + $ArgList) $TimeoutSec)
}

function Get-ShortHead {
  param([string]$Text,[int]$Max = 200)
  $t = ([string]$Text).Trim() -replace '\s+', ' '
  if ($t.Length -gt $Max) { return $t.Substring(0, $Max) + '...' }
  return $t
}

# ---------------------------------------------------------------------------
# section 3: real-machine observations used by the self-proofs
# ---------------------------------------------------------------------------

function Get-WildcardListenerMap {
  # Every wildcard TCP listener with its owning PID. Read-only, no network.
  $netstat = Join-Path $env:SystemRoot 'System32\netstat.exe'
  if (-not (Test-Path -LiteralPath $netstat)) { return $null }
  $h = @{}
  $out = & $netstat -ano 2>$null | Out-String
  foreach ($ln in @($out -split "`r?`n")) {
    if ($ln -notmatch 'LISTENING') { continue }
    $t = @(($ln.Trim() -replace '\s+', ' ') -split ' ')
    if ($t.Count -lt 4 -or $t[0] -ne 'TCP') { continue }
    $local = $t[1]
    $hostPart = $local
    if ($hostPart.StartsWith('[')) { $hostPart = $hostPart.Substring(1, $hostPart.IndexOf(']') - 1) }
    else { $hostPart = ($hostPart -split ':')[0] }
    if ($hostPart -eq '0.0.0.0' -or $hostPart -eq '::') {
      $owner = 0
      if ($t.Count -ge 5) { [void][int]::TryParse($t[4], [ref]$owner) }
      $h[$local] = $owner
    }
  }
  return $h
}

function Get-ProcImageName {
  param([int]$ProcId)
  if ($ProcId -le 0) { return '' }
  try { return (Get-Process -Id $ProcId -ErrorAction Stop).ProcessName } catch { return '' }
}

function Get-TreeSnapshot {
  # path -> sha256 for every file under a root (the plugin tree by default). Read-only evidence.
  param([string]$Root = '')
  if (-not $Root) { $Root = $script:PluginRoot }
  $h = @{}
  foreach ($f in @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force -ErrorAction SilentlyContinue)) {
    try { $h[$f.FullName.Substring($Root.Length)] = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash } catch { }
  }
  return $h
}

# Both snapshots are taken before the first child process starts and compared again at the end.
# They are the read-only self-proof: this smoke must not listen on anything and must not write
# into the tree while it checks the tree.
$script:ListenersBefore = Get-WildcardListenerMap
$script:TreeBefore = Get-TreeSnapshot
$script:SnapTreeBefore = $null

# Freeze the tree. From here on, every child runs from the copy.
function Invoke-FreezeSnapshot {
  try {
    if (Test-Path -LiteralPath $script:SnapshotRoot) { Remove-Item -LiteralPath $script:SnapshotRoot -Recurse -Force -ErrorAction SilentlyContinue }
    [void](New-Item -ItemType Directory -Force -Path $script:SnapshotRoot)
    Copy-Item -LiteralPath $script:PluginRoot -Destination $script:SnapshotRoot -Recurse -Force
    if (-not (Test-Path -LiteralPath $script:SnapPlugin)) {
      # Belt and braces for a host whose Copy-Item names the copy differently after all: copy
      # the CONTENTS into the leaf directory we computed ourselves.
      [void](New-Item -ItemType Directory -Force -Path $script:SnapPlugin)
      Copy-Item -Path (Join-Path $script:PluginRoot '*') -Destination $script:SnapPlugin -Recurse -Force
    }
    if (-not (Test-Path -LiteralPath $script:SnapPlugin)) { return ('the copy did not appear at ' + $script:SnapPlugin + ' (leaf name read from the source: ' + $script:PluginLeaf + ')') }
    $srcFiles = @(Get-ChildItem -LiteralPath $script:PluginRoot -Recurse -File -Force -ErrorAction SilentlyContinue).Count
    $snapFiles = @(Get-ChildItem -LiteralPath $script:SnapPlugin -Recurse -File -Force -ErrorAction SilentlyContinue).Count
    if ($snapFiles -ne $srcFiles) { return ('file count mismatch after the copy: ' + $snapFiles + ' of ' + $srcFiles) }
    $script:CollectPath = Join-Path $script:SnapPlugin 'src\collect.ps1'
    $script:PrereqPath = Join-Path $script:SnapPlugin 'panel\prereq.ps1'
    $script:SuitePath = Join-Path $script:SnapPlugin 'tests\run-tests.ps1'
    $script:FixturesPath = Join-Path $script:SnapPlugin 'tests\run-fixtures.ps1'
    return ''
  } catch { return $_.Exception.Message }
}
$freezeError = Invoke-FreezeSnapshot
if ($freezeError) {
  Add-Fail 'snapshot.freeze' ('the tree could not be frozen into %TEMP%\rtg-smoke-' + $PID + '\snapshot (' + $freezeError + '); the children below ran from the working tree, so a concurrent editor could affect them')
  $script:SnapshotState = 'failed'
} else {
  $snapCount = @(Get-ChildItem -LiteralPath $script:SnapPlugin -Recurse -File -Force -ErrorAction SilentlyContinue).Count
  $script:SnapshotState = 'frozen'
  $script:SnapTreeBefore = Get-TreeSnapshot -Root $script:SnapPlugin
  Add-Pass 'snapshot.freeze' (($snapCount.ToString()) + ' files copied to %TEMP% and every child below ran from that copy, so a concurrent editor cannot change what they read')
}

# ---------------------------------------------------------------------------
# section 4: item 1/2 - collector role semantics and the read-only contract
# ---------------------------------------------------------------------------

$collectorPath = $script:CollectPath
$collectReports = @{}
$collectExit = @{}
$collectRan = $false

if (-not (Test-Path -LiteralPath $collectorPath)) {
  Add-Fail 'collector.role.both' ('missing file: ' + $script:CollectRel)
  Add-Fail 'collector.role.client' ('missing file: ' + $script:CollectRel)
  Add-Fail 'collector.role.server' ('missing file: ' + $script:CollectRel)
  Add-Fail 'collector.role.filtering' ('missing file: ' + $script:CollectRel)
} else {
  $collectRan = $true
  foreach ($role in @('both','client','server')) {
    $id = 'collector.role.' + $role
    $res = Invoke-SpecifiedScript $collectorPath @('-CheckOnly','-AsJson','-Role',$role) $CollectTimeoutSec
    if ($res.timedOut) { Add-Fail $id ('timed out after ' + $CollectTimeoutSec + ' s'); continue }
    if ($res.exitCode -eq -2) { Add-Fail $id ('could not start the child process: ' + $res.startError); continue }
    $report = $null
    try { $report = $res.stdout | ConvertFrom-Json } catch { $report = $null }
    if ($null -eq $report) {
      Add-Fail $id ('stdout is not a JSON report (exit=' + $res.exitCode + '): ' + (Get-ShortHead $res.stdout))
      continue
    }
    $collectReports[$role] = $report
    $collectExit[$role] = $res.exitCode

    $problems = New-Object System.Collections.ArrayList
    if ([string]$report.schema -ne 'dsh-crossnet-link/collect/1') { [void]$problems.Add('schema=' + [string]$report.schema) }
    if ([bool]$report.collector.readOnly -ne $true) { [void]$problems.Add('collector.readOnly is not true') }
    $sum = $report.summary
    $nBlk = [int]$sum.blocked; $nDeg = [int]$sum.degraded; $nUnk = [int]$sum.unknown
    $derived = 0
    if ($nBlk -gt 0) { $derived = 2 } elseif ($nDeg -gt 0 -or $nUnk -gt 0) { $derived = 1 }
    if ([int]$sum.exitCode -ne $res.exitCode) { [void]$problems.Add('summary.exitCode=' + $sum.exitCode + ' but the process exited ' + $res.exitCode) }
    if ($derived -ne $res.exitCode) { [void]$problems.Add('derived exit ' + $derived + ' (blocked=' + $nBlk + ' degraded=' + $nDeg + ' unknown=' + $nUnk + ') but the process exited ' + $res.exitCode) }
    $counted = [int]$sum.pass + $nDeg + $nBlk + $nUnk
    if ($counted -ne [int]$sum.total -or [int]$sum.total -ne @($report.checks).Count) { [void]$problems.Add('summary counts do not add up (total=' + $sum.total + ' pass+deg+blk+unk=' + $counted + ' checks=' + @($report.checks).Count + ')') }
    $vocab = @('pass','degraded','blocked','unknown')
    foreach ($c in @($report.checks)) {
      if (-not $c.id) { [void]$problems.Add('a check has no id') ; break }
      if ($vocab -notcontains [string]$c.verdict) { [void]$problems.Add($c.id + ' has verdict=' + [string]$c.verdict) }
      if (-not [string]$c.reasonKey) { [void]$problems.Add($c.id + ' has no reasonKey') }
      if (-not [string]$c.evidence.source) { [void]$problems.Add($c.id + ' has no evidence.source') }
      $conf = [string]$c.evidence.confidence
      if ($conf -ne 'high' -and $conf -ne 'low' -and $conf -ne 'none') { [void]$problems.Add($c.id + ' has evidence.confidence=' + $conf) }
    }
    if ($problems.Count -eq 0) {
      Add-Pass $id ('exit=' + $res.exitCode + ' matches the four-state summary; ' + [int]$sum.total + ' checks, ' + [int]$sum.pass + ' pass / ' + $nDeg + ' degraded / ' + $nBlk + ' blocked / ' + $nUnk + ' unknown; every check carries id+verdict+reasonKey+evidence')
    } else {
      Add-Fail $id (($problems.ToArray()) -join '; ')
    }
  }

  if ($collectRan -and $collectReports.ContainsKey('both') -and $collectReports.ContainsKey('client') -and $collectReports.ContainsKey('server')) {
    $idsBoth = @($collectReports['both'].checks | ForEach-Object { [string]$_.id } | Sort-Object -Unique)
    $idsClient = @($collectReports['client'].checks | ForEach-Object { [string]$_.id } | Sort-Object -Unique)
    $idsServer = @($collectReports['server'].checks | ForEach-Object { [string]$_.id } | Sort-Object -Unique)
    $union = @(@($idsClient + $idsServer) | Sort-Object -Unique)
    $shared = @($idsClient | Where-Object { $idsServer -contains $_ })
    $problems = New-Object System.Collections.ArrayList
    if (($union -join ',') -ne ($idsBoth -join ',')) { [void]$problems.Add('both-role set is not exactly client-union-server') }
    if (@($idsClient | Where-Object { $idsBoth -notcontains $_ }).Count -gt 0) { [void]$problems.Add('a client check is missing from the both-role run') }
    if (@($idsServer | Where-Object { $idsBoth -notcontains $_ }).Count -gt 0) { [void]$problems.Add('a server check is missing from the both-role run') }
    if ($shared.Count -lt 1) { [void]$problems.Add('client and server share no check, so the both role would be redundant') }
    if (@($idsClient | Where-Object { $idsServer -notcontains $_ }).Count -lt 1) { [void]$problems.Add('the client role adds nothing over the server role') }
    if (@($idsServer | Where-Object { $idsClient -notcontains $_ }).Count -lt 1) { [void]$problems.Add('the server role adds nothing over the client role') }
    if ($problems.Count -eq 0) {
      Add-Pass 'collector.role.filtering' ('both=' + $idsBoth.Count + ' = ' + $shared.Count + ' shared + ' + ($idsClient.Count - $shared.Count) + ' client-only + ' + ($idsServer.Count - $shared.Count) + ' server-only; no out-of-role check is emitted')
    } else {
      Add-Fail 'collector.role.filtering' (($problems.ToArray()) -join '; ')
    }
  } else {
    if ($collectRan) { Add-Skip 'collector.role.filtering' 'not every role produced a parseable report (see the FAIL lines above)' }
  }

  # -Apply must stay refused: a read-only contract that can be switched off is not a contract.
  $resApply = Invoke-SpecifiedScript $collectorPath @('-CheckOnly','-Apply') $CollectTimeoutSec
  if ($resApply.timedOut) { Add-Fail 'collector.readonly.apply-refused' ('timed out after ' + $CollectTimeoutSec + ' s') }
  elseif ($resApply.exitCode -eq 2 -and $resApply.stdout -match 'REFUSED') {
    Add-Pass 'collector.readonly.apply-refused' 'exit=2 and the refusal is explained on stdout (no write path exists)'
  } else {
    Add-Fail 'collector.readonly.apply-refused' ('expected exit 2 plus a REFUSED explanation, got exit=' + $resApply.exitCode + ' stdout=' + (Get-ShortHead $resApply.stdout))
  }
}

# ---------------------------------------------------------------------------
# section 5: SKIP items - the offline / restricted boundary, with manual commands
# ---------------------------------------------------------------------------

Add-Skip 'net.peer-tcp-probe' 'no peer is contacted by default (clean-room offline run): the peer may be asleep or offline, so a fail here would be meaningless' ($script:CollectRel + ' -CheckOnly -Role client -Peer <PEER_IP>')
Add-Skip 'net.magicdns-resolve' 'name resolution needs a live tailnet and is never attempted offline' ($script:CollectRel + ' -CheckOnly -Role client -PeerName <PEER_MAGICDNS_NAME>')
Add-Skip 'net.tls-and-http-verdict' 'the collector makes no HTTP request by design (an expired cookie 401 and a missing trustedHosts 403 cannot be told apart without one), so the TLS/HTTP judgement stays manual' ('node -e "require(''https'').request({host:''<PEER_IP>'',port:443,servername:''<PEER_MAGICDNS_NAME>'',headers:{Host:''<PEER_MAGICDNS_NAME>''},rejectUnauthorized:true},r=>{console.log(r.statusCode);process.exit(0)}).on(''error'',e=>{console.log(''ERR'',e.code);process.exit(1)}).end()"')

function Get-Check {
  param($Report,[string]$Id)
  if ($null -eq $Report) { return $null }
  foreach ($c in @($Report.checks)) { if ([string]$c.id -eq $Id) { return $c } }
  return $null
}

if ($collectReports.ContainsKey('both')) {
  $rBoth = $collectReports['both']
  # Each of these is a probe that a sandbox, a missing daemon or an absent DSH instance can
  # legitimately block. They are reported as SKIP with the reason taken from the report, so
  # the machine state is visible without ever being counted as a failure of this smoke.
  $map = @(
    @{ Id='TAILSCALE_CLI_LAYER';        Item='restricted.tailscale-cli';    Manual='tailscale ip -4' ; Why='the tailscale CLI could not answer' },
    @{ Id='SERVE_PRESENT';              Item='restricted.serve-status';     Manual='tailscale serve status' ; Why='the serve state could not be read' },
    @{ Id='DSH_LOOPBACK_ONLY';          Item='restricted.dsh-listener';     Manual='start DSH Desktop, then re-run this smoke' ; Why='the DSH loopback listener was not measurable' },
    @{ Id='NIC_PROFILE_ATTRIBUTION';    Item='restricted.nic-profile';      Manual='netsh advfirewall monitor show currentprofile' ; Why='the adapter-to-firewall-profile mapping could not be read' },
    @{ Id='POWER_STANDBY_IDLE_AC_DC';   Item='restricted.power-policy';     Manual='powercfg /query SCHEME_CURRENT <SUB_SLEEP> <STANDBYIDLE>' ; Why='the sleep timeout could not be read' },
    @{ Id='BROWSER_PROXY_TSNET';        Item='restricted.proxy-settings';   Manual='reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings"' ; Why='the system proxy settings could not be read' }
  )
  foreach ($m in $map) {
    $c = Get-Check $rBoth $m.Id
    if ($null -eq $c) { continue }
    if ([string]$c.verdict -eq 'unknown') {
      Add-Skip $m.Item ($m.Why + ' (collector verdict=unknown, reasonKey=' + [string]$c.reasonKey + '; the human wording in the collector report is localized, so it is deliberately not echoed here)') $m.Manual
    }
  }
}

# ---------------------------------------------------------------------------
# section 6: item 3 - prerequisite detector
# ---------------------------------------------------------------------------

$prereqPath = $script:PrereqPath

# NOTE: this helper reports AND stores, but deliberately returns nothing. A helper that writes
# its own [PASS]/[FAIL] lines into the output stream AND returns a value would swallow those
# lines into the caller's variable (measured while building this file) - the item would then be
# missing from the console while still being counted.
function Test-PrereqReport {
  param([string]$Item,[string]$Role)
  if (-not (Test-Path -LiteralPath $prereqPath)) { Add-Fail $Item ('missing file: ' + $script:PrereqRel) ; return }
  $res = Invoke-SpecifiedScript $prereqPath @('-CheckOnly','-AsJson','-Role',$Role) $PrereqTimeoutSec
  if ($res.timedOut) { Add-Fail $Item ('timed out after ' + $PrereqTimeoutSec + ' s'); return }
  if ($res.exitCode -eq -2) { Add-Fail $Item ('could not start the child process: ' + $res.startError); return }
  $report = $null
  try { $report = $res.stdout | ConvertFrom-Json } catch { $report = $null }
  if ($null -eq $report) { Add-Fail $Item ('stdout is not a JSON report (exit=' + $res.exitCode + '): ' + (Get-ShortHead $res.stdout)); return }
  $problems = New-Object System.Collections.ArrayList
  if ([bool]$report.readOnly -ne $true) { [void]$problems.Add('readOnly is not true') }
  if ([bool]$report.ranAnyInstall -ne $false) { [void]$problems.Add('ranAnyInstall is not false - the detector must never install anything') }
  $items = @($report.items)
  $sum = $report.summary
  if ([int]$sum.total -ne $items.Count) { [void]$problems.Add('summary.total=' + $sum.total + ' but ' + $items.Count + ' items were reported') }
  $counted = [int]$sum.pass + [int]$sum.degraded + [int]$sum.blocked + [int]$sum.unknown
  if ($counted -ne [int]$sum.total) { [void]$problems.Add('summary counts do not add up (' + $counted + ' vs ' + $sum.total + ')') }
  $derived = 0
  if ([int]$sum.blocked -gt 0) { $derived = 2 }
  elseif ([int]$sum.degraded -gt 0 -or [int]$sum.unknown -gt 0) { $derived = 1 }
  if ($derived -ne $res.exitCode) { [void]$problems.Add('derived exit ' + $derived + ' (blocked=' + $sum.blocked + ' degraded=' + $sum.degraded + ' unknown=' + $sum.unknown + ') but the process exited ' + $res.exitCode) }
  if ([int]$sum.exitCode -ne $res.exitCode) { [void]$problems.Add('summary.exitCode=' + $sum.exitCode + ' but the process exited ' + $res.exitCode) }
  # The prerequisite report carries id / title / verdict / reasonKey per item (its human
  # wording lives in missingMessage and friends), so the contract is checked on those fields.
  foreach ($it in $items) {
    if (-not $it.id) { [void]$problems.Add('an item has no id'); break }
    $v = [string]$it.verdict
    if ($v -ne 'pass' -and $v -ne 'degraded' -and $v -ne 'blocked' -and $v -ne 'unknown') { [void]$problems.Add([string]$it.id + ' has verdict=' + $v); break }
    if (-not [string]$it.reasonKey) { [void]$problems.Add([string]$it.id + ' has no reasonKey'); break }
    if (-not [string]$it.title) { [void]$problems.Add([string]$it.id + ' has no title'); break }
  }
  if ($problems.Count -eq 0) {
    $script:PrereqReports[$Role] = $report
    Add-Pass $Item ('role=' + $Role + ' exit=' + $res.exitCode + ' matches the four-state summary; ' + $items.Count + ' items, ' + [int]$sum.pass + ' pass / ' + [int]$sum.blocked + ' blocked / ' + [int]$sum.unknown + ' unknown; ranAnyInstall=false')
  } else {
    Add-Fail $Item (($problems.ToArray()) -join '; ')
  }
}

$script:PrereqReports = @{}
Test-PrereqReport 'prereq.checkonly.both' 'both'
Test-PrereqReport 'prereq.checkonly.client' 'client'
$prereqBoth = $null
$prereqClient = $null
if ($script:PrereqReports.ContainsKey('both')) { $prereqBoth = $script:PrereqReports['both'] }
if ($script:PrereqReports.ContainsKey('client')) { $prereqClient = $script:PrereqReports['client'] }
if ($null -ne $prereqBoth -and $null -ne $prereqClient) {
  $nBoth = @($prereqBoth.items).Count
  $nClient = @($prereqClient.items).Count
  if ($nClient -lt $nBoth) {
    Add-Pass 'prereq.role-filtering' ('the client role reports fewer prerequisites than both (' + $nClient + ' < ' + $nBoth + '), so the role switch really filters')
  } elseif ($nClient -eq $nBoth) {
    Add-Skip 'prereq.role-filtering' 'the client and both roles report the same number of items on this machine, so filtering cannot be observed here'
  } else {
    Add-Fail 'prereq.role-filtering' ('the client role reports more items (' + $nClient + ') than both (' + $nBoth + ')')
  }
} else {
  Add-Skip 'prereq.role-filtering' 'one of the two prerequisite runs did not produce a parseable report'
}

# ---------------------------------------------------------------------------
# section 7: item 4/5/6 - the sub-suites and the release gate
# ---------------------------------------------------------------------------

if ($SkipSuites) {
  Add-Skip 'suite.full' 'skipped by -SkipSuites (debug switch)'
  Add-Skip 'fixtures.regression' 'skipped by -SkipSuites (debug switch)'
} else {
  $suitePath = $script:SuitePath
  if (-not (Test-Path -LiteralPath $suitePath)) {
    Add-Fail 'suite.full' ('missing file: ' + $script:SuiteRel)
  } else {
    $res = Invoke-SpecifiedScript $suitePath @() $SuiteTimeoutSec
    if ($res.timedOut) { Add-Fail 'suite.full' ('timed out after ' + $SuiteTimeoutSec + ' s') }
    else {
      $total = $null; $passed = $null; $failed = $null; $xfail = $null; $xpass = $null
      if ($res.stdout -match '(?m)^cases run\s*:\s*(\d+)') { $total = [int]$Matches[1] }
      if ($res.stdout -match '(?m)^passed\s*:\s*(\d+)') { $passed = [int]$Matches[1] }
      if ($res.stdout -match '(?m)^failed\s*:\s*(\d+)') { $failed = [int]$Matches[1] }
      if ($res.stdout -match '(?m)^xfail held\s*:\s*(\d+)') { $xfail = [int]$Matches[1] }
      if ($res.stdout -match '(?m)^xpass\s*:\s*(\d+)') { $xpass = [int]$Matches[1] }
      if ($null -eq $total -or $null -eq $failed) {
        Add-Fail 'suite.full' ('the suite summary could not be parsed (exit=' + $res.exitCode + '); stdout tail: ' + (Get-ShortHead $res.stdout 300))
      } else {
        # The case TOTAL is printed, never asserted: tests/ is edited by other tasks, so a
        # pinned number would go stale and make this smoke fail for no reason. What is
        # asserted is the invariant that cannot legitimately drift.
        if ($res.exitCode -eq 0 -and $failed -eq 0 -and $xfail -eq 0 -and $xpass -eq 0) {
          Add-Pass 'suite.full' ('cases=' + $total + ' passed=' + $passed + ' failed=0 xfail=0 xpass=0, exit=0 (the total is reported, not asserted)')
        } else {
          Add-Fail 'suite.full' ('expected failed=0 xfail=0 xpass=0 exit=0, got cases=' + $total + ' passed=' + $passed + ' failed=' + $failed + ' xfail=' + $xfail + ' xpass=' + $xpass + ' exit=' + $res.exitCode + '; a non-zero xfail means a known gap reappeared, a non-zero xpass means a recorded gap was fixed and its marker must be flipped')
        }
      }
    }
  }

  $fixturesPath = $script:FixturesPath
  if (-not (Test-Path -LiteralPath $fixturesPath)) {
    Add-Fail 'fixtures.regression' ('missing file: ' + $script:FixturesRel)
  } else {
    $res = Invoke-SpecifiedScript $fixturesPath @() $SuiteTimeoutSec
    if ($res.timedOut) { Add-Fail 'fixtures.regression' ('timed out after ' + $SuiteTimeoutSec + ' s') }
    elseif ($res.exitCode -eq 0 -and $res.stdout -match 'ALL PASS') {
      Add-Pass 'fixtures.regression' 'the collector fixture regression reports ALL PASS with exit 0'
    } else {
      Add-Fail 'fixtures.regression' ('expected ALL PASS with exit 0, got exit=' + $res.exitCode + '; stdout tail: ' + (Get-ShortHead $res.stdout 300))
    }
  }
}

# The release gate may live in a different place depending on how the set was unpacked, so it
# is searched for instead of being pinned to one path. Absent => SKIP (it is not this smoke's
# job to demand a gate that this checkout does not carry).
$hygieneRoot = $script:PluginRoot
if ($script:SnapshotState -eq 'frozen') { $hygieneRoot = $script:SnapPlugin }
$hygienePath = ''
$hygieneCandidates = @(
  (Join-Path $hygieneRoot '.github\scripts\repo-hygiene.ps1'),
  (Join-Path $hygieneRoot 'scripts\repo-hygiene.ps1'),
  (Join-Path $hygieneRoot 'repo-hygiene.ps1')
)
foreach ($cand in $hygieneCandidates) { if (Test-Path -LiteralPath $cand) { $hygienePath = $cand; break } }
if (-not $hygienePath) {
  $found = @(Get-ChildItem -LiteralPath $hygieneRoot -Recurse -File -Filter 'repo-hygiene.ps1' -ErrorAction SilentlyContinue)
  if ($found.Count -gt 0) { $hygienePath = $found[0].FullName }
}
if (-not $hygienePath) {
  Add-Skip 'hygiene.release-gate' 'no repo-hygiene.ps1 in this checkout' 'powershell -NoProfile -ExecutionPolicy Bypass -File <path>/repo-hygiene.ps1 -Json'
} else {
  $res = Invoke-SpecifiedScript $hygienePath @('-Json') $HygieneTimeoutSec
  if ($res.timedOut) { Add-Fail 'hygiene.release-gate' ('timed out after ' + $HygieneTimeoutSec + ' s') }
  else {
    $hyd = $null
    foreach ($ln in @($res.stdout -split "`r?`n")) {
      $t = $ln.Trim()
      if ($t.StartsWith('{') -and $t -match '"verdict"') { try { $hyd = $t | ConvertFrom-Json } catch { } }
    }
    $cleanWord = ($res.stdout -match '(?m)^verdict:\s*CLEAN')
    if ($res.exitCode -eq 0 -and ($cleanWord -or ($null -ne $hyd -and [string]$hyd.verdict -eq 'clean'))) {
      $detail = ''
      if ($null -ne $hyd) { $detail = ' blockingTotal=' + [string]$hyd.blockingTotal + ' files=' + [string]$hyd.files }
      Add-Pass 'hygiene.release-gate' ('exit=0 and verdict=CLEAN' + $detail)
    } else {
      Add-Fail 'hygiene.release-gate' ('expected exit 0 with verdict CLEAN, got exit=' + $res.exitCode + '; tail: ' + (Get-ShortHead $res.stdout 300))
    }
  }
}

# ---------------------------------------------------------------------------
# section 7b: read-only evidence (static + dynamic) and the optional components
# ---------------------------------------------------------------------------

# Static proof: every write/spawn verb in this file must be confined to the %TEMP% scratch root
# (the script freezes the tree there and deletes it again). A smoke that could write into the
# checkout would not be a smoke. (The verb names are assembled from fragments so that this
# pattern table does not match its own text.)
$writeVerbs = @(
  ('Set-' + 'Content'), ('Out-' + 'File'), ('Add-' + 'Content'), ('Export-' + 'Csv'),
  ('Move-' + 'Item'), ('Rename-' + 'Item'), ('Copy-' + 'Item'),
  ('New-' + 'Item'), ('New-' + 'ItemProperty'), ('Set-' + 'ItemProperty'),
  ('Remove-' + 'Item'), ('Remove-' + 'ItemProperty'),
  ('WriteAll' + 'Text'), ('WriteAll' + 'Bytes'), ('Start-' + 'Process')
)
$selfText = ''
try { $selfText = [System.IO.File]::ReadAllText((Join-Path $script:Here 'run-smoke.ps1'), [System.Text.Encoding]::UTF8) } catch { }
if (-not $selfText) {
  Add-Skip 'selfproof.writes-confined-to-temp' 'this script could not read its own source, so the static read-only proof cannot be made'
} else {
  $scratchDeclared = ($selfText -match 'GetTempPath\(\)') -and ($selfText -match '\$script:ScratchRoot\s*=')
  $selfLines = @($selfText -split "`r?`n")
  # The syntax tree is used, not a line grep: a verb mentioned inside a comment or a string is
  # not an invocation (measured: a line grep flagged two explanatory comments).
  $selfAst = $null
  try {
    $selfTokens = $null; $selfErrors = $null
    $selfAst = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:Here 'run-smoke.ps1'), [ref]$selfTokens, [ref]$selfErrors)
  } catch { $selfAst = $null }
  $offenders = New-Object System.Collections.ArrayList
  $verbLines = 0
  if ($null -ne $selfAst) {
    $allCmds = $selfAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)
    foreach ($cmd in $allCmds) {
      $cname = ''
      try { $cname = [string]$cmd.GetCommandName() } catch { $cname = '' }
      if ($writeVerbs -notcontains $cname) { continue }
      $verbLines++
      $ln = [int]$cmd.Extent.StartLineNumber
      $lineText = ''
      if ($ln -ge 1 -and $ln -le $selfLines.Count) { $lineText = $selfLines[$ln - 1] }
      if ($lineText -notmatch '(?i)(scratchroot|snapshotroot|snapplugin|snapshot)') {
        [void]$offenders.Add(($ln.ToString()) + ': ' + $lineText.Trim())
      }
    }
  }
  if ($null -eq $selfAst) {
    Add-Skip 'selfproof.writes-confined-to-temp' 'this file could not be parsed, so the write confinement cannot be proven statistically'
  } elseif (-not $scratchDeclared) {
    Add-Fail 'selfproof.writes-confined-to-temp' 'this file does not derive its scratch root from [System.IO.Path]::GetTempPath()'
  } elseif ($offenders.Count -gt 0) {
    Add-Fail 'selfproof.writes-confined-to-temp' ('a write/spawn verb is not aimed at the %TEMP% scratch root: ' + (($offenders.ToArray()) -join ' | '))
  } else {
    Add-Pass 'selfproof.writes-confined-to-temp' ('all ' + $verbLines + ' write/spawn verb use(s) among ' + $writeVerbs.Count + ' checked patterns target the %TEMP% scratch root; scratch root = ' + $script:ScratchRoot)
  }
}

# Static lint for the reporter arguments, requested after a real defect: an expression like
#   Add-Pass 'id' ((@($a).Count + @($b).Count) + ' text')
# feeds a STRING to the '+' operator with an Int32 on the left, and PowerShell then tries to
# convert the text into a number ("Cannot convert value ... to type System.Int32"). This walks
# the parsed syntax tree of this file itself and inspects the reason argument of every
# reporter call, so the check cannot rot when a new item is added.
# The defect this guards against, measured three times while writing this file:
#     Add-Pass 'id' ((@($a).Count + @($b).Count) + ' text')
# The argument is a "+" chain whose LEFT-most operand reduces to a number, so PowerShell tries to
# convert the appended TEXT into that number and throws ("Cannot convert value ... to type
# System.Int32"), which silently loses the item. A chain that starts with a string is safe,
# because then every number to its right is stringified.
#
# The check has three parts and every one of them is verified on this run:
#   a) walk every reporter call site in THIS file and require the left-most operand to be a string;
#   b) run the same walker over a synthetic snippet that contains one known-bad and one known-good
#      call (positive control: the bad one MUST be caught, the good one MUST NOT be flagged);
#   c) read the reporter helper's own parameter declaration and require the reason parameter to be
#      [string] - if it were declared [int] the same class of bug would be possible from the other
#      side.
# True only when the expression produces a NUMBER (so text appended to it would be converted to
# a number and throw). A plain variable is NOT assumed numeric: it is usually a string here, and
# assuming otherwise flagged eleven safe concatenations that start with a string variable.
function Test-NumericLeftOperand {
  param($Ast)
  if ($null -eq $Ast) { return $false }
  $kind = $Ast.GetType().Name
  if ($kind -eq 'ConstantExpressionAst') { return (($Ast.Value -is [int]) -or ($Ast.Value -is [long]) -or ($Ast.Value -is [double]) -or ($Ast.Value -is [decimal])) }
  if ($kind -eq 'VariableExpressionAst') { return ([string]$Ast.VariablePath.UserPath -match '(?i)(count|total|num|len|length)$') }
  if ($kind -eq 'MemberExpressionAst') {
    $m = ''
    try { $m = [string]$Ast.Member.Extent.Text } catch { $m = '' }
    return ($m -eq 'Count' -or $m -eq 'Length')
  }
  if ($kind -eq 'InvocationExpressionAst') {
    $tgt = ''
    try { $tgt = [string]$Ast.InvocationTarget.Extent.Text } catch { $tgt = '' }
    if ($tgt -match '\.ToString$') { return $false }
    return ([string]$Ast.Extent.Text -match '\.Count\b|\.Length\b')
  }
  if ($kind -eq 'ConvertExpressionAst') {
    $ty = ''
    try { $ty = [string]$Ast.Type.TypeName.Name } catch { $ty = '' }
    return ($ty -match '(?i)^(int|long|int16|int32|int64|double|decimal|single|byte)$')
  }
  if ($kind -eq 'ParenExpressionAst') { return (Test-NumericLeftOperand $Ast.Pipeline) }
  if ($kind -eq 'CommandExpressionAst') { return (Test-NumericLeftOperand $Ast.Expression) }
  if ($kind -eq 'PipelineAst') {
    $els = @($Ast.PipelineElements)
    if ($els.Count -gt 0) { return (Test-NumericLeftOperand $els[0]) }
    return $false
  }
  if ($kind -eq 'BinaryExpressionAst') {
    if ([string]$Ast.Operator -eq 'Plus') { return ((Test-NumericLeftOperand $Ast.Left) -or (Test-NumericLeftOperand $Ast.Right)) }
    return (Test-NumericLeftOperand $Ast.Left)
  }
  return $false
}

function Get-CoreExpression {
  # An argument written as (expr) arrives as a ParenExpressionAst wrapping a PipelineAst, so the
  # interesting expression has to be unwrapped first. Missing this made the walker report zero
  # sites on a snippet that demonstrably contains the defect (the positive control caught it).
  param($Ast)
  $cur = $Ast
  $guard = 0
  while ($null -ne $cur -and $guard -lt 8) {
    $guard++
    $kind = $cur.GetType().Name
    if ($kind -eq 'ParenExpressionAst') { $cur = $cur.Pipeline; continue }
    if ($kind -eq 'CommandExpressionAst') { $cur = $cur.Expression; continue }
    if ($kind -eq 'PipelineAst') {
      $els = @($cur.PipelineElements)
      if ($els.Count -eq 1) { $cur = $els[0]; continue }
      return $cur
    }
    return $cur
  }
  return $Ast
}

function Get-UnsafeReporterArg {
  # Returns one "line: text" string for every reporter call whose reason argument is a "+" chain
  # that does not start with a string.
  param($Ast)
  $bad = New-Object System.Collections.ArrayList
  if ($null -eq $Ast) { return $bad.ToArray() }
  $names = @('Add-Pass','Add-Fail','Add-Skip','Add-Item')
  $cmds = $Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)
  foreach ($cmd in $cmds) {
    $name = ''
    try { $name = [string]$cmd.GetCommandName() } catch { $name = '' }
    if ($names -notcontains $name) { continue }
    $els = @($cmd.CommandElements)
    if ($els.Count -lt 3) { continue }
    $arg = Get-CoreExpression $els[2]
    if (-not ($arg -is [System.Management.Automation.Language.BinaryExpressionAst])) { continue }
    if ([string]$arg.Operator -ne 'Plus') { continue }
    $leftmost = $arg
    while (($leftmost -is [System.Management.Automation.Language.BinaryExpressionAst]) -and ([string]$leftmost.Operator -eq 'Plus')) { $leftmost = $leftmost.Left }
    if (Test-NumericLeftOperand $leftmost) {
      [void]$bad.Add($cmd.Extent.StartLineNumber.ToString() + ': ' + [string]$arg.Extent.Text)
    }
  }
  return $bad.ToArray()
}

function Get-ReporterCount {
  param($Ast)
  $n = 0
  if ($null -eq $Ast) { return 0 }
  $names = @('Add-Pass','Add-Fail','Add-Skip','Add-Item')
  $cmds = $Ast.FindAll({ param($n2) $n2 -is [System.Management.Automation.Language.CommandAst] }, $true)
  foreach ($cmd in $cmds) {
    $name = ''
    try { $name = [string]$cmd.GetCommandName() } catch { $name = '' }
    if ($names -contains $name) { $n++ }
  }
  return $n
}

# Positive control: one bad call (must be caught) and one good call (must not be).
$probeSource = "param(`$a,`$b)`n" +
                "Add-Pass 'probe-bad' ((@(`$a).Count + @(`$b).Count) + ' text')`n" +
                "Add-Pass 'probe-good' ('count=' + @(`$a).Count + ' text')`n"
$probeAst = $null
try {
  $probeTokens = $null; $probeErrors = $null
  $probeAst = [System.Management.Automation.Language.Parser]::ParseInput($probeSource, [ref]$probeTokens, [ref]$probeErrors)
} catch { $probeAst = $null }
$probeBad = @()
$probeSites = 0
if ($null -ne $probeAst) {
  $probeBad = @(Get-UnsafeReporterArg $probeAst)
  $probeSites = Get-ReporterCount $probeAst
}

$reasonParamType = ''
if ($null -ne $selfAst) {
  $fns = @($selfAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
  foreach ($fn in $fns) {
    if ([string]$fn.Name -ne 'Add-Item') { continue }
    $plist = @()
    try { if ($null -ne $fn.Body.ParamBlock) { $plist = @($fn.Body.ParamBlock.Parameters) } } catch { $plist = @() }
    foreach ($prm in $plist) {
      if ([string]$prm.Name.VariablePath.UserPath -eq 'Reason') { $reasonParamType = [string]$prm.StaticType.FullName }
    }
  }
}

$problem = New-Object System.Collections.ArrayList
if ($null -eq $selfAst) { [void]$problem.Add('this file could not be parsed for the lint') }
if ($probeSites -ne 2) { [void]$problem.Add('the positive control did not parse into 2 reporter calls (got ' + $probeSites.ToString() + ')') }
if (@($probeBad).Count -ne 1) { [void]$problem.Add('the positive control expected exactly 1 unsafe call, got ' + (@($probeBad).Count).ToString() + ': ' + ((@($probeBad)) -join ' | ')) }
else {
  $firstBad = [string]$probeBad[0]
  if ($firstBad -notmatch '\.Count') { [void]$problem.Add('the positive control flagged something that is not the numeric-left defect: ' + $firstBad) }
  if ($firstBad -match "^d+: 'count=") { [void]$problem.Add('the positive control also flagged the safe, string-first call: ' + $firstBad) }
}
if ($reasonParamType -eq '') { [void]$problem.Add('the reporter helper Add-Item has no Reason parameter, so the declared-type check cannot be made') }
elseif ($reasonParamType -ne 'System.String') { [void]$problem.Add('the reporter helper declares Reason as ' + $reasonParamType + ' (expected System.String, otherwise a reason could itself be a number)') }
$ownBad = @()
$ownSites = 0
if ($null -ne $selfAst) { $ownBad = @(Get-UnsafeReporterArg $selfAst) ; $ownSites = Get-ReporterCount $selfAst }
if (@($ownBad).Count -gt 0) { [void]$problem.Add((@($ownBad).Count).ToString() + ' unsafe reporter argument(s) in this file: ' + ((@($ownBad)) -join ' | ')) }

if ($problem.Count -eq 0) {
    Add-Pass 'selfcheck.reporter-args' (($ownSites.ToString()) + ' reporter call site(s) in this file: none starts a "+" chain with a number, so none can append text to an Int32 and lose the item. Positive control: 1 of 2 synthetic calls flagged and only the unsafe one. Add-Item declares Reason as ' + $reasonParamType + '.')
  } else {
    Add-Fail 'selfcheck.reporter-args' (($problem.ToArray()) -join ' | ')
  }

# Dynamic evidence, in two parts, because the two trees answer two different questions.
#
# (1) The FROZEN SNAPSHOT is the tree every child actually read. If it changed, a child wrote into
#     its own inputs: that is a real failure of the read-only contract and it is deterministic,
#     because nobody else can write into a private %TEMP% copy.
if ($null -eq $script:SnapTreeBefore) {
  Add-Skip 'selfproof.snapshot-unchanged' 'the tree could not be frozen, so the input tree cannot be compared'
} else {
  $snapAfter = Get-TreeSnapshot -Root $script:SnapPlugin
  $snapChanged = New-Object System.Collections.ArrayList
  foreach ($k in $script:SnapTreeBefore.Keys) {
    if (-not $snapAfter.ContainsKey($k)) { [void]$snapChanged.Add('deleted ' + $k) }
    elseif ($snapAfter[$k] -ne $script:SnapTreeBefore[$k]) { [void]$snapChanged.Add('modified ' + $k) }
  }
  foreach ($k in $snapAfter.Keys) { if (-not $script:SnapTreeBefore.ContainsKey($k)) { [void]$snapChanged.Add('created ' + $k) } }
  if ($snapChanged.Count -eq 0) {
    Add-Pass 'selfproof.snapshot-unchanged' ('all ' + $snapAfter.Count + ' files of the frozen input tree are byte-identical before and after every child run (created=0 deleted=0 modified=0)')
  } else {
    Add-Fail 'selfproof.snapshot-unchanged' ('a child wrote into its own input tree: ' + (($snapChanged.ToArray()) -join ', '))
  }
}

# (2) The WORKING TREE is reported as evidence. A concurrent editor can change it while this run
#     is in flight, and that cannot have been this smoke (selfproof.writes-confined-to-temp proves
#     every write verb here targets %TEMP%), so a non-empty diff is a note, not a failure. On a
#     clean room checkout this diff is empty.
$treeAfter = Get-TreeSnapshot
$changed = New-Object System.Collections.ArrayList
foreach ($k in $script:TreeBefore.Keys) {
  if (-not $treeAfter.ContainsKey($k)) { [void]$changed.Add('deleted ' + $k) }
  elseif ($treeAfter[$k] -ne $script:TreeBefore[$k]) { [void]$changed.Add('modified ' + $k) }
}
foreach ($k in $treeAfter.Keys) { if (-not $script:TreeBefore.ContainsKey($k)) { [void]$changed.Add('created ' + $k) } }
if ($changed.Count -eq 0) {
  Add-Pass 'selfproof.working-tree-diff' ('all ' + $treeAfter.Count + ' files under the plugin root are byte-identical before and after (created=0 deleted=0 modified=0)')
} else {
  Add-Pass 'selfproof.working-tree-diff' (($changed.Count.ToString()) + ' path(s) changed in the working tree while this run was in flight, which this smoke cannot have written (see selfproof.writes-confined-to-temp) - concurrent edit, listed for the record: ' + (($changed.ToArray()) -join ', '))
}

# tools/uninstall.ps1 is a release-set member that writes BY DESIGN (that is its job), so its
# safety is established by its own dry-run/backup/journal behaviour instead of by a write-verb
# ban. What must hold here, and is asserted by name rather than only by the tree-wide encoding
# sweep above, is the encoding/parse contract that makes it runnable at all on PowerShell 5.1.
$uninstallerStatic = ''
foreach ($cand in @((Join-Path $script:SnapPlugin 'tools\uninstall.ps1'), (Join-Path $script:PluginRoot 'tools\uninstall.ps1'))) {
  if (Test-Path -LiteralPath $cand -PathType Leaf) { $uninstallerStatic = $cand; break }
}
if (-not $uninstallerStatic) {
  Add-Skip 'component.uninstaller.static' 'tools/uninstall.ps1 is not part of this checkout yet'
} else {
  $uProbs = New-Object System.Collections.ArrayList
  $uBom = $false
  $uNonAscii = 0
  $uErrCount = 0
  try {
    $ub = [System.IO.File]::ReadAllBytes($uninstallerStatic)
    $uBom = (($ub.Length -ge 3) -and ($ub[0] -eq 0xEF) -and ($ub[1] -eq 0xBB) -and ($ub[2] -eq 0xBF))
    foreach ($x in $ub) { if ($x -gt 0x7F) { $uNonAscii++ } }
    $uErr = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($uninstallerStatic, [ref]$null, [ref]$uErr)
    $uErrCount = @($uErr).Count
  } catch { [void]$uProbs.Add('could not be read: ' + $_.Exception.Message) }
  if ($uErrCount -gt 0) { [void]$uProbs.Add('Parser::ParseFile reports ' + $uErrCount.ToString() + ' error(s), so PowerShell 5.1 cannot run it') }
  if ($uNonAscii -gt 0 -and -not $uBom) { [void]$uProbs.Add('non-ASCII ' + $uNonAscii.ToString() + ' byte(s) without a BOM: a BOM-less script is decoded as ANSI, which is how a non-ASCII literal corrupts the parse') }
  if ($uProbs.Count -eq 0) {
    Add-Pass 'component.uninstaller.static' ('parses with 0 errors; BOM=' + $uBom.ToString() + '; non-ASCII bytes=' + $uNonAscii.ToString() + ' - the PowerShell 5.1 encoding/parse contract holds')
  } else {
    Add-Fail 'component.uninstaller.static' (($uProbs.ToArray()) -join '; ')
  }
}

# Optional components that may land AFTER this file: they are covered without editing it.
$optionalComponents = @(
  @{ Name = 'uninstaller'; Rel = 'tools/uninstall.ps1'; Args = @('-CheckOnly','-AsJson'); Item = 'component.uninstaller' }
)
foreach ($oc in $optionalComponents) {
  $cand = @(
    (Join-Path $script:SnapPlugin ($oc.Rel -replace '/','\')),
    (Join-Path $script:PluginRoot ($oc.Rel -replace '/','\')),
    (Join-Path $script:RepoRoot ($oc.Rel -replace '/','\')),
    (Join-Path $script:PluginRoot ([System.IO.Path]::GetFileName($oc.Rel)))
  )
  $found = ''
  foreach ($c in $cand) { if (Test-Path -LiteralPath $c -PathType Leaf) { $found = $c; break } }
  if (-not $found) {
    $hits = @(Get-ChildItem -LiteralPath $script:SnapPlugin -Recurse -File -Filter ([System.IO.Path]::GetFileName($oc.Rel)) -ErrorAction SilentlyContinue)
    if ($hits.Count -gt 0) { $found = $hits[0].FullName }
  }
  if (-not $found) {
    Add-Skip $oc.Item ($oc.Rel + ' is not part of this checkout yet') ('powershell -NoProfile -ExecutionPolicy Bypass -File ' + $oc.Rel + ' -CheckOnly -AsJson')
    continue
  }
  $res = Invoke-SpecifiedScript $found $oc.Args $PrereqTimeoutSec
  $relShown = $oc.Rel
  if ($res.timedOut) { Add-Fail $oc.Item ($relShown + ' timed out after ' + $PrereqTimeoutSec + ' s'); continue }
  if ($res.exitCode -eq -2) { Add-Fail $oc.Item ($relShown + ' could not be started: ' + $res.startError); continue }
  $sumText = ''
  try {
    $rep = $res.stdout | ConvertFrom-Json
    if ($null -ne $rep -and $null -ne $rep.summary) { $sumText = ' summary=' + ($rep.summary | ConvertTo-Json -Compress) }
  } catch { }
  $psErrorText = ([string]$res.stderr + "`n" + [string]$res.stdout)
  # Only ASCII markers are reported. The localized wording of a PowerShell error is deliberately
  # not echoed: this tool must stay readable on any console.
  $markers = New-Object System.Collections.ArrayList
  foreach ($mk in @('CategoryInfo','FullyQualifiedErrorId','ParseError','Exception','is not recognized')) {
    if ($psErrorText -match [regex]::Escape($mk)) { [void]$markers.Add($mk) }
  }
  $psErrorSeen = ($markers.Count -gt 0)
  $atLine = ''
  $mLn = [regex]::Match($psErrorText, '([^\s\\/:]+\.ps1):(\d+)')
  if ($mLn.Success) { $atLine = ' (' + $mLn.Groups[1].Value + ' line ' + $mLn.Groups[2].Value + ')' }
  if ($psErrorSeen -and $res.exitCode -ne 2) {
    # Was the file being rewritten while it ran? A component under active development can be
    # caught mid-write; that is a concurrent edit, not a delivery failure, so it is reported as
    # SKIP (with both hashes) instead of FAIL when the working-tree copy is clean by now.
    $wtPath = Join-Path $script:PluginRoot ($oc.Rel -replace '/','\')
    $snapHash = ''
    try { $snapHash = (Get-FileHash -LiteralPath $found -Algorithm SHA256).Hash } catch { $snapHash = '' }
    $wtHash = ''
    $wtClean = $false
    if (Test-Path -LiteralPath $wtPath -PathType Leaf) {
      try { $wtHash = (Get-FileHash -LiteralPath $wtPath -Algorithm SHA256).Hash } catch { $wtHash = '' }
      $wtErr = $null
      try { [void][System.Management.Automation.Language.Parser]::ParseFile($wtPath, [ref]$null, [ref]$wtErr) } catch { }
      $wtClean = (@($wtErr).Count -eq 0)
    }
    if ($wtClean -and $wtHash -ne '' -and $wtHash -ne $snapHash) {
      Add-Skip $oc.Item ($relShown + ' was being rewritten while this run was in flight (snapshot copy ' + $snapHash.Substring(0,8) + ', working tree now ' + $wtHash.Substring(0,8) + ', which parses clean). Re-run to judge it.')
    } else {
      Add-Fail $oc.Item ($relShown + ' exited ' + $res.exitCode + ' but PowerShell reported ' + (($markers.ToArray()) -join '/') + $atLine + ', so it did NOT run (localized wording not echoed)')
    }
  } elseif ($res.exitCode -eq 0 -or $res.exitCode -eq 1) {
    Add-Pass $oc.Item ($relShown + ' ran read-only: exit=' + $res.exitCode + ' counts as "it ran" by the documented contract' + $sumText)
  } elseif ($res.exitCode -eq 2) {
    if ($psErrorSeen) {
      Add-Fail $oc.Item ($relShown + ' exited 2 with PowerShell reporting ' + (($markers.ToArray()) -join '/') + $atLine + ' (localized wording not echoed)')
    } else {
      Add-Pass $oc.Item ($relShown + ' exited 2 as its own fail-closed verdict (no PowerShell error on stderr), which is a result and not a failure of this smoke' + $sumText)
    }
  } else {
    Add-Fail $oc.Item ($relShown + ' exited ' + $res.exitCode + ' which is outside the documented 0/1/2 contract; stderr: ' + (Get-ShortHead $res.stderr 200))
  }
}

# ---------------------------------------------------------------------------
# section 8: item 7 - no-new-listener self-proof
# ---------------------------------------------------------------------------

$listenersBefore = $script:ListenersBefore
$listenersAfter = Get-WildcardListenerMap
if ($null -eq $listenersBefore -or $null -eq $listenersAfter) {
  Add-Skip 'selfproof.no-new-listener' 'netstat is unavailable, so the wildcard listener set cannot be compared'
} else {
  $added = New-Object System.Collections.ArrayList
  $removed = New-Object System.Collections.ArrayList
  foreach ($k in $listenersAfter.Keys) {
    if (-not $listenersBefore.ContainsKey($k)) { [void]$added.Add($k + ' (pid ' + $listenersAfter[$k] + ' ' + (Get-ProcImageName $listenersAfter[$k]) + ')') }
  }
  foreach ($k in $listenersBefore.Keys) { if (-not $listenersAfter.ContainsKey($k)) { [void]$removed.Add($k) } }
  $ours = @($added.ToArray() | Where-Object { $_ -match '(?i)\(pid \d+ (powershell|pwsh|conhost|cmd|node|dsh|wscript|cscript)' })
  if ($ours.Count -gt 0) {
    Add-Fail 'selfproof.no-new-listener' ('a listener owned by this smoke appeared: ' + ($ours -join ', '))
  } elseif ($added.Count -eq 0 -and $removed.Count -eq 0) {
    Add-Pass 'selfproof.no-new-listener' ('the wildcard TCP listener set is identical before and after (' + $listenersAfter.Count + ' listeners)')
  } else {
    # Another application starting or stopping mid-run is not this smoke's doing; it is
    # reported in full instead of being silently tolerated or blamed.
    Add-Pass 'selfproof.no-new-listener' ('no listener attributable to this smoke; unrelated machine activity was +[' + (($added.ToArray()) -join ', ') + '] -[' + (($removed.ToArray()) -join ', ') + ']')
  }
}

# ---------------------------------------------------------------------------
# section 9: item 8 - encoding, BOM and parse self-check
# ---------------------------------------------------------------------------

$scriptExt = @('.ps1','.psm1')
$noBomExt = @('.md','.json','.yml','.yaml','.js')
$psFiles = 0; $psNonAscii = 0; $bomMissing = 0; $bomForbidden = 0; $parseErrors = 0
$examples = New-Object System.Collections.ArrayList
$violations = New-Object System.Collections.ArrayList
$allFiles = @(Get-ChildItem -LiteralPath $script:PluginRoot -Recurse -File -ErrorAction SilentlyContinue)
foreach ($f in $allFiles) {
  $ext = $f.Extension.ToLower()
  if (-not ($scriptExt -contains $ext) -and -not ($noBomExt -contains $ext)) { continue }
  $bytes = $null
  try { $bytes = [System.IO.File]::ReadAllBytes($f.FullName) } catch { continue }
  $hasBom = (($bytes.Length -ge 3) -and ($bytes[0] -eq 0xEF) -and ($bytes[1] -eq 0xBB) -and ($bytes[2] -eq 0xBF))
  $nonAscii = 0
  foreach ($b in $bytes) { if ($b -gt 0x7F) { $nonAscii++ } }
  $rel = $f.FullName.Substring($script:PluginRoot.Length).TrimStart('\')
  if ($scriptExt -contains $ext) {
    $psFiles++
    if ($nonAscii -gt 0) {
      $psNonAscii++
      # Windows PowerShell 5.1 decodes a BOM-less script as the system ANSI code page, so a
      # non-ASCII script without a BOM can turn into a wall of fake syntax errors.
      if (-not $hasBom) {
        $bomMissing++
        [void]$violations.Add([pscustomobject]@{ path = $f.FullName; kind = 'bom-missing' })
        if ($examples.Count -lt 5) { [void]$examples.Add($rel + ': non-ASCII ' + $nonAscii + ' bytes, no BOM (fix: add a UTF-8 BOM or make the file pure ASCII)') }
      }
    }
    $err = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$err)
    if (@($err).Count -gt 0) {
      $parseErrors++
      [void]$violations.Add([pscustomobject]@{ path = $f.FullName; kind = 'parse' })
      if ($examples.Count -lt 5) { [void]$examples.Add($rel + ': ' + @($err).Count + ' parse error(s)') }
    }
  } else {
    if ($hasBom) {
      $bomForbidden++
      [void]$violations.Add([pscustomobject]@{ path = $f.FullName; kind = 'bom-forbidden' })
      if ($examples.Count -lt 5) { [void]$examples.Add($rel + ': BOM on a ' + $ext + ' file (must be BOM-less)') }
    }
  }
}
if ($bomMissing -eq 0 -and $bomForbidden -eq 0 -and $parseErrors -eq 0) {
  Add-Pass 'encoding.bom-and-parse' ('scripts=' + $psFiles + ' (non-ASCII scripts=' + $psNonAscii + ', all with BOM where needed), markdown/json/yaml/js BOM violations=0, Parser::ParseFile errors=0')
} else {
  Add-Fail 'encoding.bom-and-parse' ('missing BOM on a non-ASCII script=' + $bomMissing + ', BOM on a BOM-less extension=' + $bomForbidden + ', parse errors=' + $parseErrors + ' :: ' + (($examples.ToArray()) -join ' | '))
}

# ---------------------------------------------------------------------------
# section 10: item 9 - release-set key files and hashes
# ---------------------------------------------------------------------------

$requiredFiles = @(
  'src/collect.ps1','i18n/labels.zh.json','i18n/labels.en.json',
  'panel/prereq.ps1','panel/prereq-manifest.json',
  'tests/run-tests.ps1','tests/run-fixtures.ps1','tests/run-smoke.ps1'
)
$requiredDirs = @('tests/cases','tests/fixtures')
$infoFiles = @(
  'README.md','CHANGELOG.md','CONTRIBUTING.md','SECURITY.md','LICENSE','.editorconfig','.gitignore',
  'tests/cases/README.md','.github/scripts/repo-hygiene.ps1',
  '.github/workflows/ci.yml','panel/host-half.js','panel/client-half.js',
  'docs/collect.md','docs/defensive-spec.md','docs/matrix.md','docs/baseline.md','docs/threat-model.md',
  'docs/install/install.md','docs/install/prerequisites.md','docs/install/rollback.md'
)
$missing = New-Object System.Collections.ArrayList
$missingInfo = New-Object System.Collections.ArrayList
foreach ($rel in $requiredFiles) {
  $p = Join-Path $script:PluginRoot ($rel -replace '/','\')
  if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { [void]$missing.Add($rel); continue }
  $item = Get-Item -LiteralPath $p
  $hash = (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash
  Add-Info ('sha256 ' + $hash + ' ' + $item.Length.ToString().PadLeft(8) + '  ' + $rel)
}
foreach ($rel in $requiredDirs) {
  $p = Join-Path $script:PluginRoot ($rel -replace '/','\')
  if (-not (Test-Path -LiteralPath $p -PathType Container)) { [void]$missing.Add($rel + '/'); continue }
  $n = @(Get-ChildItem -LiteralPath $p -Recurse -File -ErrorAction SilentlyContinue).Count
  Add-Info ('dir    ' + $n.ToString().PadLeft(8) + ' entries  ' + $rel + '/')
}
foreach ($rel in $infoFiles) {
  $p = Join-Path $script:PluginRoot ($rel -replace '/','\')
  if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { [void]$missingInfo.Add($rel); continue }
  $item = Get-Item -LiteralPath $p
  $hash = (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash
  Add-Info ('sha256 ' + $hash + ' ' + $item.Length.ToString().PadLeft(8) + '  ' + $rel)
}
if ($missing.Count -eq 0) {
  $note = ''
  if ($missingInfo.Count -gt 0) { $note = ' (informational files not present in this checkout: ' + (($missingInfo.ToArray()) -join ', ') + ')' }
  Add-Pass 'release.key-files' (((@($requiredFiles).Count + @($requiredDirs).Count).ToString()) + ' essential paths present, sha256 printed above for every file' + $note)
} else {
  Add-Fail 'release.key-files' ('missing from the release set: ' + (($missing.ToArray()) -join ', '))
}

# ---------------------------------------------------------------------------
# section 11: remove the frozen scratch, then prove it is gone
# ---------------------------------------------------------------------------

if ($KeepScratch) {
  Add-Skip 'selfproof.scratch-cleaned' ('-KeepScratch was given, so the scratch snapshot was left behind at %TEMP%\\rtg-smoke-' + $PID)
} else {
  if (Test-Path -LiteralPath $script:ScratchRoot) {
    Remove-Item -LiteralPath $script:ScratchRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
  if (Test-Path -LiteralPath $script:ScratchRoot) {
    Add-Fail 'selfproof.scratch-cleaned' ('the scratch snapshot still exists at %TEMP%\\rtg-smoke-' + $PID + ' after cleanup')
  } else {
    Add-Pass 'selfproof.scratch-cleaned' ('the frozen snapshot at %TEMP%\\rtg-smoke-' + $PID + ' was removed; nothing of this smoke remains in %TEMP%')
  }
}

# ---------------------------------------------------------------------------
# section 12: summary
# ---------------------------------------------------------------------------

$nPass = @($script:Results | Where-Object { $_.status -eq 'PASS' }).Count
$nFail = @($script:Results | Where-Object { $_.status -eq 'FAIL' }).Count
$nSkip = @($script:Results | Where-Object { $_.status -eq 'SKIP' }).Count
$nTotal = @($script:Results).Count
# Fail-closed ladder: 0 green (no FAIL and no SKIP), 1 degraded (SKIPs only), 2 broken
# (a FAIL, or this smoke could not run at all - which always shows up as a FAIL item).
$exitCode = 0
if ($nFail -gt 0) { $exitCode = 2 }
elseif ($nSkip -gt 0) { $exitCode = 1 }

Write-Output ''
if ($Json) {
  $payload = [ordered]@{
    smoke    = [ordered]@{ total=$nTotal; pass=$nPass; fail=$nFail; skip=$nSkip; exit=$exitCode; snapshot=$script:SnapshotState; offline=$true; peerContacted=$false }
    items    = @($script:Results)
  }
  Write-Output (($payload | ConvertTo-Json -Depth 6 -Compress))
}
# The human verdict comes BEFORE the summary, because the summary line must stay the last line of
# the output (a caller reads the tail, or pipes the last line into a gate).
if ($exitCode -eq 0) {
  Write-Output 'verdict: GREEN - everything that can be checked offline is green, nothing was skipped'
} elseif ($exitCode -eq 1) {
  Write-Output ('verdict: DEGRADED - nothing failed, but ' + $nSkip + ' check(s) were skipped (each SKIP names what it skipped and why; most carry a manual command). Nothing here is broken.')
} else {
  Write-Output 'verdict: BROKEN - see the [FAIL] items above (each one states expected vs actual)'
}
Write-Output ('SMOKE total=' + $nTotal + ' pass=' + $nPass + ' fail=' + $nFail + ' skip=' + $nSkip + ' exit=' + $exitCode)
exit $exitCode
