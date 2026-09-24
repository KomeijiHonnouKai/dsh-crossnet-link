<#
  run-tests.ps1 - cross-environment and fault-injection test suite for the
                 remote-tailnet-guard collector (remote-tailnet-plugin).

  LAST UPDATED : 2026-09-24 (v4 - t38: the write-verb filescan assertion is narrowed to the read-only
                 surface with an explicit allowFiles list naming tools/uninstall.ps1 (the repository's
                 only optional write component: dry-run by default, -Apply to write, backup first), and
                 a new kind=uninstall runs that component offline against a fixture and asserts on the
                 exit code, the -AsJson report, the backup file set, every MANIFEST sha256/byte count,
                 the surviving files and - for dry runs - a byte-identical case temp dir.
                 v3 - t32: filescan assertions accept an optional ifMissing field;
                 ifMissing:'skip' turns a deliberately-absent target into a printed, counted SKIP
                 instead of a failure, so the suite is green in a published clone that does not
                 contain internal material. Absence without that marker still fails exactly as
                 before. A new summary line reports the skipped count.
                 v2 - t23: scan hits are classified PER MATCH; approved neutral
                 placeholders (section 7.1) are counted separately and never as hits, and the
                 positive control now plants one of them to prove the allowlist is not a blindfold.
                 v1: one entry point, cases live in tests/cases/<id>/case.json)
  RUNS ON      : Windows PowerShell 5.1 (powershell.exe). NO external module, NO
                 Pester, NO node, NO network access required.

  COMMANDS USED (read-only; the suite creates temp dirs under %TEMP% and removes them):
    powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/tests/run-tests.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/tests/run-tests.ps1 -List
    powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/tests/run-tests.ps1 -Filter locale
    powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/tests/run-tests.ps1 -Only isolation
    powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/tests/run-tests.ps1 -KeepTemp -Verbose
  EXIT CODE    : 0 = every case passed; 1 = at least one case failed.

  WHY A HAND-WRITTEN RUNNER AND NOT PESTER
    This suite must be usable by a stranger who clones the repo: "one command, no install".
    The Windows PowerShell 5.1 image on the reference machine ships Pester 3.4.0 only, and
    Pester 3.4 has a different assertion/DSL surface from Pester 4/5 (no `Should -Be`, no
    `BeforeAll`, different discovery rules); Pester 5 is not available offline. Depending on
    any module would make the one-command promise false, so the runner carries its own
    ~200-line assertion core. Every failure prints: case id -> rule -> expected -> actual.

  WHAT THIS SUITE DOES NOT DO (isolation contract)
    * it never changes system configuration, never edits a DSH profile, never starts a
      listener, never spawns "tailscale serve", never reads a credential;
    * it never needs a live peer: every "peer online" case is a fixture;
    * fixtures replace external command OUTPUT only - the collector's judging logic always
      runs for real (a mocked judge would prove nothing);
    * suite-level gates at the end re-check the real machine: wildcard listener set
      unchanged, and the plugin tree byte-identical to the pre-run snapshot.

  CASE FORMAT (tests/cases/<id>/case.json) - see tests/cases/README.md for the table:
    id, title, titleZh, kind, why, inject, expectSummary
    kind=collector : args, env, base, layer, unset, tmp, expect
    kind=scan      : scan {root, extensions, patterns?, plant?, allowPatterns?, expectHits}
    kind=filescan  : filescan { asserts: [ {type, file, pattern?, ifMissing?} ] }   # ifMissing:'skip' = a missing target is a printed SKIP, never a failure
    kind=uninstall : uninstall { args, fixture?, tmpFiles?, stateFiles?, expectExit, jsonEq/jsonIn/jsonMatch/jsonNotMatch,
                                 orderingContains?, assertNoTmpWrites?, expectFilesPresentUnchanged?, expectFilesAbsent?,
                                 expectBackupFiles?, verifyBackupManifest? }   # t38: drives tools/uninstall.ps1 offline
    kind=canary    : canary { }   # t41: positive control for the tree-wide filescan assertion types
                                  # (literal-zero / literal-min / hits-confined-to). The handler owns the
                                  # whole scenario: plant a violation in a throw-away tree, run the real
                                  # engine, assert on its EXPECTED/ACTUAL record, and assert the clean twin
                                  # stays green. If those branches are ever muted again, this case fails.
    kind=isolation : tmp, args, expect
    kind=portability: base, layer, args, expect
    kind=prereq    : prereq {script, forbiddenParams, forbiddenText, expectExitIn}
    xfail          : {reason, severity}  -> case passes only while it still FAILS
#>
[CmdletBinding()]
param(
  [string]$RepoRoot = '',
  [string]$Collector = '',
  [string]$CasesDir = '',
  [string]$Filter = '',
  [string]$Only = '',
  [switch]$List,
  [switch]$Quiet,
  [switch]$KeepTemp,
  [int]$ChildTimeoutSec = 180
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

$script:Here = $PSScriptRoot
$script:PluginRoot = (Resolve-Path -LiteralPath (Join-Path $script:Here '..')).Path
if (-not $RepoRoot) { $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $script:PluginRoot '..')).Path }
$script:RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
if (-not $Collector) { $Collector = Join-Path $script:PluginRoot 'src\collect.ps1' }
$script:Collector = (Resolve-Path -LiteralPath $Collector).Path
if (-not $CasesDir) { $CasesDir = Join-Path $script:Here 'cases' }
$script:CasesDir = (Resolve-Path -LiteralPath $CasesDir).Path
$script:PsExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

$script:TempBase = Join-Path ([System.IO.Path]::GetTempPath()) ('rtg-tests-' + $PID)
$script:TempUsed = New-Object System.Collections.ArrayList

# ---------------------------------------------------------------------------
# section 1: tiny compatibility/JSON helpers
# ---------------------------------------------------------------------------

function Prop {
  param($Obj,[string]$Name)
  if ($null -eq $Obj) { return $null }
  $p = $Obj.PSObject.Properties[$Name]
  if ($null -eq $p) { return $null }
  return $p.Value
}

function Has-Prop {
  param($Obj,[string]$Name)
  if ($null -eq $Obj) { return $false }
  return ($null -ne $Obj.PSObject.Properties[$Name])
}

function Is-JsonObject {
  param($Obj)
  if ($null -eq $Obj) { return $false }
  return ($Obj.GetType().Name -eq 'PSCustomObject')
}

function Get-Nested {
  # dotted path inside a JSON object; a numeric segment indexes an array.
  # an absent segment returns $null.
  param($Obj,[string]$Path)
  $cur = $Obj
  foreach ($seg in @($Path -split '\.')) {
    if ($null -eq $cur) { return $null }
    if ($cur -is [System.Array]) {
      if ($seg -match '^\d+$') {
        $i = [int]$seg
        if ($i -ge $cur.Count) { return $null }
        $cur = $cur[$i]
      } else {
        return $null
      }
    } else {
      # A numeric segment is ambiguous: it can be an array index, or a real object key
      # (the collector keys its per-port results by the port number). A real key always wins,
      # because Prop would have returned it.
      $direct = Prop $cur $seg
      if ($null -ne $direct) { $cur = $direct }
      elseif ($seg -match '^\d+$' -and [int]$seg -eq 0) {
        # PowerShell unwraps a ONE-element array into its element when a function returns it,
        # so index 0 of such a list arrives here already dereferenced: keep the element.
        # Measured: without this, "inventory.0.port" resolved to nothing whenever the raw
        # list happened to hold exactly one row.
      } else {
        return $null
      }
    }
  }
  return $cur
}

function Merge-Json {
  # recursive merge: objects merge key-wise, everything else (scalar/array/null) replaces
  param($Base,$Layer)
  if ($null -eq $Layer) { return $Base }
  if ($null -eq $Base) { return $Layer }
  if ((Is-JsonObject $Base) -and (Is-JsonObject $Layer)) {
    $out = [ordered]@{}
    foreach ($p in $Base.PSObject.Properties) { $out[$p.Name] = $p.Value }
    foreach ($p in $Layer.PSObject.Properties) {
      if ($out.Contains($p.Name)) { $out[$p.Name] = Merge-Json $out[$p.Name] $p.Value }
      else { $out[$p.Name] = $p.Value }
    }
    return [pscustomobject]$out
  }
  return $Layer
}

function Remove-JsonPath {
  param($Obj,[string]$Path)
  $segs = @($Path -split '\.')
  $cur = $Obj
  for ($i = 0; $i -lt ($segs.Count - 1); $i++) {
    $cur = Prop $cur $segs[$i]
    if ($null -eq $cur) { return }
  }
  if ($null -eq $cur) { return }
  [void]$cur.PSObject.Properties.Remove($segs[$segs.Count - 1])
}

function Read-JsonFile {
  param([string]$Path)
  $txt = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
  return ($txt | ConvertFrom-Json)
}

function Write-TextFile {
  param([string]$Path,[string]$Text)
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Force -Path $dir) }
  [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
}

# <TOKEN> substitution for case arguments AND case environment values, so a case can point at
# its own temp area without hardcoding a path. MEASURED: emptying %ProgramFiles% is not enough
# to simulate "not installed" - Windows PowerShell 5.1 re-creates that variable inside the child
# process (len 16 measured), so a case must point it at an existing path that simply has no
# Tailscale in it.
$script:TokenMap = @{}
function Expand-CaseToken {
  param([string]$S)
  $out = [string]$S
  foreach ($k in @($script:TokenMap.Keys)) { $out = $out.Replace($k, [string]$script:TokenMap[$k]) }
  return $out
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

function New-TempDir {
  param([string]$Name)
  $p = Join-Path $script:TempBase $Name
  [void](New-Item -ItemType Directory -Force -Path $p)
  if (-not $script:TempUsed.Contains($p)) { [void]$script:TempUsed.Add($p) }
  return $p
}

# ---------------------------------------------------------------------------
# section 2: child process with an isolated environment
# ---------------------------------------------------------------------------

$script:EnvSaved = @{}

function Set-CaseEnvironment {
  param($EnvSpec,[bool]$ClearDsh)
  $script:EnvSaved = @{}
  $keys = New-Object System.Collections.ArrayList
  foreach ($k in @('DSH_HOME','DSH_WEB_URL','DSH_APP_DIR','DSH_PERMISSION_MODE','ProgramFiles','ProgramFiles(x86)','LOCALAPPDATA','PATH','USERPROFILE','SystemRoot')) {
    [void]$keys.Add($k)
  }
  if ($EnvSpec) { foreach ($p in $EnvSpec.PSObject.Properties) { if (-not $keys.Contains($p.Name)) { [void]$keys.Add($p.Name) } } }
  foreach ($k in $keys) {
    $script:EnvSaved[$k] = [System.Environment]::GetEnvironmentVariable($k, 'Process')
    $script:EnvSaved['__had_' + $k] = [System.Environment]::GetEnvironmentVariable($k, 'Process') -ne $null
  }
  if ($ClearDsh) {
    foreach ($k in @('DSH_HOME','DSH_WEB_URL','DSH_APP_DIR','DSH_PERMISSION_MODE')) {
      [System.Environment]::SetEnvironmentVariable($k, $null, 'Process')
    }
  }
  if ($EnvSpec) {
    foreach ($p in $EnvSpec.PSObject.Properties) {
      $v = $p.Value
      $v = Expand-CaseToken ([string]$v)
      Write-Verbose ('child env override: ' + $p.Name + ' = [' + [string]$v + ']')
      if ($null -eq $v) { [System.Environment]::SetEnvironmentVariable($p.Name, $null, 'Process') }
      else { [System.Environment]::SetEnvironmentVariable($p.Name, [string]$v, 'Process') }
    }
  }
}

function Restore-CaseEnvironment {
  foreach ($k in @($script:EnvSaved.Keys)) {
    if ($k -like '__had_*') { continue }
    $had = $script:EnvSaved['__had_' + $k]
    if ($had) { [System.Environment]::SetEnvironmentVariable($k, [string]$script:EnvSaved[$k], 'Process') }
    else { [System.Environment]::SetEnvironmentVariable($k, $null, 'Process') }
  }
  $script:EnvSaved = @{}
}

function Invoke-ChildProcess {
  param([string]$Exe,[string[]]$ArgList,[int]$TimeoutSec)
  $res = [ordered]@{ exitCode = $null; stdout = ''; stderr = ''; timedOut = $false; startError = '' }
  Write-Verbose ('run: ' + $Exe + ' ' + (ConvertTo-ArgString $ArgList))
  try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
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
    $ok = $p.WaitForExit($TimeoutSec * 1000)
    if (-not $ok) { $res.timedOut = $true; try { $p.Kill() } catch { } }
    try { $res.stdout = $soTask.Result } catch { }
    try { $res.stderr = $seTask.Result } catch { }
    if ($ok) { $res.exitCode = $p.ExitCode } else { $res.exitCode = -1 }
  } catch {
    $res.startError = $_.Exception.Message
    $res.exitCode = -2
  }
  return [pscustomobject]$res
}

function Invoke-CollectorProcess {
  param([string[]]$ArgList,[int]$TimeoutSec)
  return (Invoke-ChildProcess $script:PsExe (@('-NoProfile','-ExecutionPolicy','Bypass','-File',$script:Collector) + $ArgList) $TimeoutSec)
}

# ---------------------------------------------------------------------------
# section 3: assertion core (case-scoped failure list)
# ---------------------------------------------------------------------------

$script:Failures = New-Object System.Collections.ArrayList
$script:Skips = New-Object System.Collections.ArrayList
$script:NSkipped = 0
# t41: set by the canary case only; when non-empty the tree-wide filescan assertions scan that root
# instead of the repository, so the canary can plant a violation and watch the real engine fail.
$script:ScanRootOverride = ''
$script:CaseId = ''

function Add-Failure {
  param([string]$Rule,[string]$Expected,[string]$Actual)
  [void]$script:Failures.Add([pscustomobject]@{ rule=$Rule; expected=$Expected; actual=$Actual })
}

function Add-Skip {
  # A recorded skip: always printed, always counted, never silent and never a failure.
  # Used by assertions that carry ifMissing:'skip' - their target is deliberately absent from the
  # published set (internal material does not ship with the repository), while in the maintainer
  # workspace the very same assertion runs for real. See
  # tests/cases/filescan-pattern-table-matches-spec.
  param([string]$Rule,[string]$Text)
  [void]$script:Skips.Add([pscustomobject]@{ rule=$Rule; text=$Text })
  $script:NSkipped++
}

function Assert-Eq {
  param([string]$Rule,$Expected,$Actual)
  $e = if ($null -eq $Expected) { '<null>' } else { [string]$Expected }
  $a = if ($null -eq $Actual) { '<null>' } else { [string]$Actual }
  if ($e -ne $a) { Add-Failure $Rule $e $a }
}

function Assert-In {
  param([string]$Rule,$ExpectedList,$Actual)
  $a = if ($null -eq $Actual) { '' } else { [string]$Actual }
  $ok = $false
  foreach ($x in @($ExpectedList)) { if ([string]$x -eq $a) { $ok = $true } }
  if (-not $ok) { Add-Failure $Rule ('one of [' + (@($ExpectedList) -join ', ') + ']') $a }
}

function Assert-NotIn {
  param([string]$Rule,$ForbiddenList,$Actual)
  $a = if ($null -eq $Actual) { '' } else { [string]$Actual }
  foreach ($x in @($ForbiddenList)) {
    if ([string]$x -eq $a) { Add-Failure $Rule ('anything except [' + (@($ForbiddenList) -join ', ') + ']') $a ; return }
  }
}

function Assert-True {
  param([string]$Rule,[bool]$Condition,[string]$Detail)
  if (-not $Condition) { Add-Failure $Rule 'true' $Detail }
}

function Assert-Match {
  param([string]$Rule,[string]$Pattern,[string]$Text)
  $t = if ($null -eq $Text) { '' } else { [string]$Text }
  if (-not ($t -match $Pattern)) { Add-Failure $Rule ('match /' + $Pattern + '/') ('NOT FOUND in: ' + $t.Substring(0, [Math]::Min(300, $t.Length))) }
}

function Assert-NoMatch {
  param([string]$Rule,[string]$Pattern,[string]$Text)
  $t = if ($null -eq $Text) { '' } else { [string]$Text }
  if ($t -match $Pattern) { Add-Failure $Rule ('must not match /' + $Pattern + '/') ('FOUND in: ' + $t.Substring(0, [Math]::Min(300, $t.Length))) }
}

# ---------------------------------------------------------------------------
# section 4: report inspection
# ---------------------------------------------------------------------------

function Get-VerdictMap {
  param($Report)
  $h = @{}
  if ($null -eq $Report) { return $h }
  foreach ($c in @($Report.checks)) { $h[[string]$c.id] = [string]$c.verdict }
  return $h
}

function Get-CheckMap {
  param($Report)
  $h = @{}
  if ($null -eq $Report) { return $h }
  foreach ($c in @($Report.checks)) { $h[[string]$c.id] = $c }
  return $h
}

function Get-ConfigValue {
  param($Report,[string]$Name,[string]$Field)
  foreach ($e in @($Report.config)) {
    # NOTE: the name must be compared in a real expression. Writing
    #   if (Prop $e 'name' -eq $Name)
    # silently matches the FIRST entry, because a simple (non-advanced) PowerShell
    # function treats the unknown '-eq' token as just another positional argument.
    $n = Prop $e 'name'
    if ($n -eq $Name) { return (Prop $e $Field) }
  }
  return $null
}

$script:VerdictMaps = @{}

function Test-CollectorExpectation {
  param($Case,$Res)
  $exp = Prop $Case 'expect'
  $json = $null
  if ($Res.timedOut) { Add-Failure 'child process' ('completes within the timeout') ('timed out after ' + $ChildTimeoutSec + ' s') ; return }
  if ($Res.startError) { Add-Failure 'child process' 'starts' $Res.startError ; return }
  if (Has-Prop $exp 'exitCode') { Assert-Eq 'exit code' (Prop $exp 'exitCode') $Res.exitCode }
  if (Has-Prop $exp 'exitCodeNot') { Assert-NotIn 'exit code' @((Prop $exp 'exitCodeNot')) $Res.exitCode }
  if (Has-Prop $exp 'exitCodeIn') { Assert-In 'exit code' (Prop $exp 'exitCodeIn') $Res.exitCode }
  if ($null -eq $json) {
    try { $json = $Res.stdout | ConvertFrom-Json } catch { $json = $null }
  }
  if ($null -eq $json) {
    if ((Has-Prop $exp 'verdicts') -or (Has-Prop $exp 'reasons') -or (Has-Prop $exp 'raw') -or (Has-Prop $exp 'summary') -or (Has-Prop $exp 'config') -or (Has-Prop $exp 'info')) {
      Add-Failure 'report parses as JSON' 'a JSON report on stdout' ('stdout head: ' + $Res.stdout.Substring(0, [Math]::Min(300, $Res.stdout.Length)) + ' | stderr head: ' + $Res.stderr.Substring(0, [Math]::Min(200, $Res.stderr.Length)))
    }
    if (Has-Prop $exp 'stdoutMatch') { foreach ($m in @(Prop $exp 'stdoutMatch')) { Assert-Match 'stdout' $m $Res.stdout } }
    if (Has-Prop $exp 'stdoutNotMatch') { foreach ($m in @(Prop $exp 'stdoutNotMatch')) { Assert-NoMatch 'stdout' $m $Res.stdout } }
    return
  }

  $vmap = Get-VerdictMap $json
  $cmap = Get-CheckMap $json

  if (Has-Prop $exp 'verdicts') {
    foreach ($p in (Prop $exp 'verdicts').PSObject.Properties) {
      $rule = 'verdict ' + $p.Name
      if (-not $cmap.ContainsKey($p.Name)) { Add-Failure $rule ([string]$p.Value) 'check was not emitted at all' }
      else { Assert-Eq $rule ([string]$p.Value) $cmap[$p.Name].verdict }
    }
  }
  if (Has-Prop $exp 'notVerdicts') {
    foreach ($p in (Prop $exp 'notVerdicts').PSObject.Properties) {
      $rule = 'verdict ' + $p.Name
      if (-not $cmap.ContainsKey($p.Name)) { Add-Failure $rule 'check emitted' 'check was not emitted at all' }
      else { Assert-NotIn $rule @($p.Value) $cmap[$p.Name].verdict }
    }
  }
  if (Has-Prop $exp 'reasons') {
    foreach ($p in (Prop $exp 'reasons').PSObject.Properties) {
      $rule = 'reason ' + $p.Name
      if (-not $cmap.ContainsKey($p.Name)) { Add-Failure $rule ([string]$p.Value) 'check was not emitted at all' }
      else { Assert-Eq $rule ([string]$p.Value) $cmap[$p.Name].reasonKey }
    }
  }
  if (Has-Prop $exp 'reasonNot') {
    foreach ($p in (Prop $exp 'reasonNot').PSObject.Properties) {
      $rule = 'reason ' + $p.Name
      if (-not $cmap.ContainsKey($p.Name)) { Add-Failure $rule 'check emitted' 'check was not emitted at all' }
      else { Assert-NotIn $rule @($p.Value) $cmap[$p.Name].reasonKey }
    }
  }
  if (Has-Prop $exp 'confidence') {
    foreach ($p in (Prop $exp 'confidence').PSObject.Properties) {
      $rule = 'evidence.confidence ' + $p.Name
      if (-not $cmap.ContainsKey($p.Name)) { Add-Failure $rule ([string]$p.Value) 'check was not emitted at all' }
      else { Assert-Eq $rule ([string]$p.Value) $cmap[$p.Name].evidence.confidence }
    }
  }
  if (Has-Prop $exp 'confidenceDowngrade') {
    foreach ($p in (Prop $exp 'confidenceDowngrade').PSObject.Properties) {
      $rule = 'evidence.confidenceDowngrade ' + $p.Name
      if (-not $cmap.ContainsKey($p.Name)) { Add-Failure $rule ([string]$p.Value) 'check was not emitted at all' }
      else { Assert-Eq $rule ([string]$p.Value) $cmap[$p.Name].evidence.confidenceDowngrade }
    }
  }
  if (Has-Prop $exp 'absent') {
    foreach ($id in @(Prop $exp 'absent')) { Assert-True ('check ' + $id + ' is not emitted for this role') (-not $cmap.ContainsKey([string]$id)) 'was emitted' }
  }
  if (Has-Prop $exp 'present') {
    foreach ($id in @(Prop $exp 'present')) { Assert-True ('check ' + $id + ' is emitted') ($cmap.ContainsKey([string]$id)) 'was not emitted' }
  }
  if (Has-Prop $exp 'manualReview') {
    foreach ($id in @(Prop $exp 'manualReview')) {
      $rule = 'manualReview ' + $id
      if (-not $cmap.ContainsKey([string]$id)) { Add-Failure $rule 'true' 'check was not emitted at all' }
      else { Assert-Eq $rule $true $cmap[[string]$id].manualReview }
    }
  }
  if (Has-Prop $exp 'raw') {
    foreach ($p in (Prop $exp 'raw').PSObject.Properties) {
      if (-not $cmap.ContainsKey($p.Name)) { Add-Failure ('raw ' + $p.Name) 'check emitted' 'check was not emitted at all'; continue }
      foreach ($q in $p.Value.PSObject.Properties) {
        $actual = Get-Nested $cmap[$p.Name].raw $q.Name
        Assert-Eq ('raw.' + $q.Name + ' of ' + $p.Name) ([string]$q.Value) ([string]$actual)
      }
    }
  }
  if (Has-Prop $exp 'remediation') {
    foreach ($p in (Prop $exp 'remediation').PSObject.Properties) {
      if (-not $cmap.ContainsKey($p.Name)) { Add-Failure ('remediation ' + $p.Name) 'check emitted' 'check was not emitted at all'; continue }
      $rem = $cmap[$p.Name].remediation
      foreach ($q in $p.Value.PSObject.Properties) {
        if ($q.Name -eq 'needsNonEmptyRollback') {
          if ([bool]$q.Value) {
            $rb = ''
            if ($null -ne $rem) { $rb = [string]$rem.rollback }
            Assert-True ('remediation.rollback of ' + $p.Name) ($rb.Length -gt 0) 'empty rollback text'
          }
        } elseif ($q.Name -eq 'needsNonEmptyCommand') {
          $cmd = ''
          if ($null -ne $rem) { $cmd = [string]$rem.command }
          Assert-True ('remediation.command of ' + $p.Name) ($cmd.Length -gt 0) 'empty command text'
        } else {
          $actual = $null
          if ($null -ne $rem) { $actual = Get-Nested $rem $q.Name }
          Assert-Eq ('remediation.' + $q.Name + ' of ' + $p.Name) ([string]$q.Value) ([string]$actual)
        }
      }
    }
  }
  if (Has-Prop $exp 'config') {
    foreach ($p in (Prop $exp 'config').PSObject.Properties) {
      foreach ($q in $p.Value.PSObject.Properties) {
        $actual = Get-ConfigValue $json $p.Name $q.Name
        Assert-Eq ('config ' + $p.Name + '.' + $q.Name) ([string]$q.Value) ([string]$actual)
      }
    }
  }
  if (Has-Prop $exp 'summary') {
    foreach ($p in (Prop $exp 'summary').PSObject.Properties) {
      Assert-Eq ('summary.' + $p.Name) ([string]$p.Value) ([string](Get-Nested $json.summary $p.Name))
    }
  }
  if (Has-Prop $exp 'info') {
    foreach ($p in (Prop $exp 'info').PSObject.Properties) {
      if ($p.Name -eq 'collectorFaultsCount') { Assert-Eq 'collectorFaults' ([string]$p.Value) ([string]@($json.collectorFaults).Count) ; continue }
      Assert-Eq ('report.' + $p.Name) ([string]$p.Value) ([string](Get-Nested $json $p.Name))
    }
  }
  if (Has-Prop $exp 'sameVerdictsAs') {
    $ref = [string](Prop $exp 'sameVerdictsAs')
    if (-not $script:VerdictMaps.ContainsKey($ref)) { Add-Failure 'verdict equivalence' ('a stored verdict map for ' + $ref) 'that case did not run before this one' }
    else {
      $refMap = $script:VerdictMaps[$ref]
      $diff = New-Object System.Collections.ArrayList
      foreach ($k in $refMap.Keys) { if ($vmap[$k] -ne $refMap[$k]) { [void]$diff.Add($k + '(' + $refMap[$k] + '->' + $vmap[$k] + ')') } }
      foreach ($k in $vmap.Keys) { if (-not $refMap.ContainsKey($k)) { [void]$diff.Add($k + '(absent->' + $vmap[$k] + ')') } }
      Assert-True ('every verdict equals case ' + $ref) ($diff.Count -eq 0) (($diff.ToArray()) -join ', ')
    }
  }
  if (Has-Prop $exp 'stdoutMatch') { foreach ($m in @(Prop $exp 'stdoutMatch')) { Assert-Match 'stdout' $m $Res.stdout } }
  if (Has-Prop $exp 'stdoutNotMatch') { foreach ($m in @(Prop $exp 'stdoutNotMatch')) { Assert-NoMatch 'stdout' $m $Res.stdout } }
  if (Has-Prop $exp 'stderrEmpty') {
    if ([bool](Prop $exp 'stderrEmpty')) { Assert-Eq 'stderr is empty' '' $Res.stderr.Trim() }
  }
  $script:VerdictMaps[$script:CaseId] = $vmap
}

# ---------------------------------------------------------------------------
# section 5: fixture assembly
# ---------------------------------------------------------------------------

function Build-CaseFixture {
  param($Case,[string]$CaseDir,[string]$TmpDir)
  $fx = $null
  $base = Prop $Case 'base'
  if ($base) {
    $bp = Join-Path $script:CasesDir ([string]$base)
    if (-not (Test-Path -LiteralPath $bp)) { $bp = Join-Path $CaseDir ([string]$base) }
    if (-not (Test-Path -LiteralPath $bp)) { throw ('base fixture not found: ' + $base) }
    $fx = Read-JsonFile $bp
  }
  $inline = Prop $Case 'fixture'
  if ($inline) { $fx = Merge-Json $fx $inline }
  $layer = Prop $Case 'layer'
  if ($layer) { $fx = Merge-Json $fx $layer }
  if ($null -eq $fx) { return '' }
  $unset = Prop $Case 'unset'
  if ($unset) { foreach ($u in @($unset)) { Remove-JsonPath $fx ([string]$u) } }
  if (-not $TmpDir) { $TmpDir = New-TempDir $script:CaseId }
  $fp = Join-Path $TmpDir 'fixture.json'
  Write-TextFile $fp ($fx | ConvertTo-Json -Depth 20)
  return $fp
}

function Resolve-CaseArgs {
  param($Case,[string]$CaseDir,[string]$Fixture,[string]$TmpDir,[string]$CopyRoot)
  $out = New-Object System.Collections.ArrayList
  # -CheckOnly -AsJson -NoNative is the default invocation shape; -NoNative is what makes a
  # case deterministic on ANY machine: without it every probe that the fixture does not carry
  # silently falls back to REAL system access (measured: the netstat-unavailable case then
  # found the real DSH listener through auto-discovery and reported pass).
  $checkOnly = $true
  if ((Has-Prop $Case 'checkOnly') -and (-not [bool](Prop $Case 'checkOnly'))) { $checkOnly = $false }
  if ($checkOnly) { [void]$out.Add('-CheckOnly') ; [void]$out.Add('-AsJson') }
  $noNative = $true
  if ((Has-Prop $Case 'noNative') -and (-not [bool](Prop $Case 'noNative'))) { $noNative = $false }
  if ($noNative) { [void]$out.Add('-NoNative') }
  $raw = @()
  if (Has-Prop $Case 'args') { $raw = @(Prop $Case 'args') }
  foreach ($a in $raw) {
    $s = Expand-CaseToken ([string]$a)
    [void]$out.Add($s)
  }
  $hasFixture = $false
  foreach ($a in $out) { if ($a -eq '-FixturePath') { $hasFixture = $true } }
  if ($Fixture -and -not $hasFixture) { [void]$out.Add('-FixturePath') ; [void]$out.Add($Fixture) }
  $hasHome = $false
  foreach ($a in $out) { if ($a -eq '-DshHome') { $hasHome = $true } }
  if (-not $hasHome) { [void]$out.Add('-DshHome') ; [void]$out.Add((Join-Path $script:TempBase 'absent-home')) }
  $hasApp = $false
  foreach ($a in $out) { if ($a -eq '-AppDir') { $hasApp = $true } }
  if (-not $hasApp) { [void]$out.Add('-AppDir') ; [void]$out.Add((Join-Path $script:TempBase 'absent-app')) }
  return $out.ToArray()
}

# ---------------------------------------------------------------------------
# section 6: graders
# ---------------------------------------------------------------------------

function Invoke-CollectorCase {
  param($Case,[string]$CaseDir)
  $tmp = ''
  $tmpSpec = Prop $Case 'tmp'
  if ($tmpSpec) {
    $tmp = New-TempDir $script:CaseId
    $homeSpec = Prop $tmpSpec 'home'
    if ($homeSpec) {
      $hp = Join-Path $tmp 'home'
      [void](New-Item -ItemType Directory -Force -Path $hp)
      $settings = Prop $homeSpec 'settings'
      if ($settings) { Write-TextFile (Join-Path $hp 'settings.yaml') ([string]$settings) }
      $profPatch = Prop $homeSpec 'profilePatch'
      if (-not $profPatch) { $profPatch = "networkExposure: loopback`n" }
      foreach ($pn in @(Prop $homeSpec 'profiles')) {
        $pd = Join-Path $hp ('profiles\' + [string]$pn)
        [void](New-Item -ItemType Directory -Force -Path $pd)
        Write-TextFile (Join-Path $pd 'cordis.patch.yml') ([string]$profPatch)
      }
    }
  }
  $fx = Build-CaseFixture $Case $CaseDir $tmp
  $args = Resolve-CaseArgs $Case $CaseDir $fx $tmp ''
  $res = Invoke-CollectorProcess $args $ChildTimeoutSec
  Test-CollectorExpectation $Case $res
}

function Invoke-ScanCase {
  param($Case,[string]$CaseDir)
  $spec = Prop $Case 'scan'
  $pats = $script:HardcodePatterns
  $exts = @()
  if (Has-Prop $spec 'extensions') { $exts = @(Prop $spec 'extensions') }
  $root = ''
  if ([string](Prop $spec 'root') -eq 'planted') {
    $root = New-TempDir ($script:CaseId + '\planted')
    foreach ($f in @(Prop $spec 'plant')) {
      $p = Join-Path $root ([string](Prop $f 'path'))
      # Planted violations are materialized from TOKENS so that the case file itself stays clean
      # under the very scan it is testing (otherwise the positive control would be a hit of its
      # own, and the scan would have to allowlist itself).
      $txt = [string](Prop $f 'text')
      $txt = $txt.Replace('{PLANT-PEER-IP}', ('100' + '.99' + '.1.1'))
      $txt = $txt.Replace('{PLANT-HOSTNAME}', ('LAPTOP-' + 'ABCD1234'))
      $txt = $txt.Replace('{PLANT-USERPATH}', ('C:' + [char]92 + 'Users' + [char]92 + 'somebody' + [char]92 + 'log.txt'))
      Write-TextFile $p $txt
    }
  } else {
    $root = $script:PluginRoot
  }
  $allow = @()
  if (Has-Prop $spec 'allowPatterns') { $allow = @(Prop $spec 'allowPatterns') }
  $hits = New-Object System.Collections.ArrayList
  $approved = New-Object System.Collections.ArrayList
  $perExt = @{}
  foreach ($f in @(Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue)) {
    $ext = $f.Extension.ToLower()
    if ($exts.Count -gt 0 -and -not ($exts -contains $ext)) { continue }
    $rel = $f.FullName.Substring($root.Length).TrimStart('\').Replace('\', '/')
    $skip = $false
    foreach ($ap in $allow) { if ($rel -match [string]$ap) { $skip = $true } }
    foreach ($k in $pats.Keys) {
      $m = @(Select-String -LiteralPath $f.FullName -Pattern $pats[$k] -AllMatches -ErrorAction SilentlyContinue)
      foreach ($mm in $m) {
        foreach ($mv in @($mm.Matches)) {
          # t23: classify EVERY match, not the whole line. A match whose own text is an approved
          # neutral placeholder (section 7.1) is recorded as approved and never counts as a hit;
          # a real identifier on the same line still counts. This is what keeps the positive
          # control honest while the captain's placeholder ruling is respected.
          $value = [string]$mv.Value
          $isApproved = $false
          foreach ($pl in $script:ApprovedPlaceholders) { if ($value -match $pl) { $isApproved = $true } }
          if ($isApproved) {
            [void]$approved.Add([pscustomobject]@{ path=$rel; line=$mm.LineNumber; pattern=$k; value=$value })
            continue
          }
          [void]$hits.Add([pscustomobject]@{ path=$rel; line=$mm.LineNumber; pattern=$k; text=$mm.Line.Trim() })
          if ($skip) { continue }
          $ek = $ext + '/' + $k
          if (-not $perExt.ContainsKey($ek)) { $perExt[$ek] = 0 }
          $perExt[$ek] = $perExt[$ek] + 1
        }
      }
    }
  }
  $allowed = @($hits | Where-Object { $r = $_.path ; $keep = $false ; foreach ($ap in $allow) { if ($r -match [string]$ap) { $keep = $true } } ; -not $keep })
  $expHits = 0
  if (Has-Prop $spec 'expectHits') { $expHits = [int](Prop $spec 'expectHits') }
  $detail = ''
  if ($allowed.Count -gt 0) { $detail = (@($allowed | ForEach-Object { $_.path + ':' + $_.line + ' [' + $_.pattern + '] ' + $_.text }) -join ' ;; ') }
  Assert-Eq ('scan hits (extensions ' + ($exts -join ',') + ')') $expHits $allowed.Count
  if ($allowed.Count -ne $expHits) { Add-Failure 'scan detail' ('' + $expHits + ' hit(s)') $detail }
  if (Has-Prop $spec 'expectHitsPerExtension') {
    foreach ($p in (Prop $spec 'expectHitsPerExtension').PSObject.Properties) {
      $have = 0
      if ($perExt.ContainsKey($p.Name)) { $have = $perExt[$p.Name] }
      Assert-True ('scan hit coverage ' + $p.Name) ($have -ge [int]$p.Value) ('found ' + $have + ', expected at least ' + [int]$p.Value)
    }
  }
  if (Has-Prop $spec 'allowHits') {
    # informational: the number of hits that ARE allowed (documented records), asserted
    # so that the allowlist cannot silently grow or shrink unnoticed.
    $sum = 0
    foreach ($p in (Prop $spec 'allowHits').PSObject.Properties) { $sum = $sum + [int]$p.Value }
    Assert-Eq 'allowlisted hits (informational total)' $sum $hits.Count
  }
  if (Has-Prop $spec 'expectApprovedHits') {
    # informational: how many matches were approved neutral placeholders (section 7.1). Asserted
    # where it is the point of the case, so the approved list cannot swallow a real value unnoticed.
    Assert-Eq 'approved placeholder matches (informational)' ([int](Prop $spec 'expectApprovedHits')) $approved.Count
  }
}

function Invoke-FileScanCase {
  param($Case,[string]$CaseDir)
  foreach ($a in @(Prop (Prop $Case 'filescan') 'asserts')) {
    $t = [string](Prop $a 'type')
    $file = [string](Prop $a 'file')
    $path = Join-Path $script:PluginRoot $file
    # The three tree-wide assertion types take their file set from 'extensions'. It is applied as an
    # explicit post-filter (t38): `-Include` is silently ignored when it is combined with a wildcard-free
    # -LiteralPath directory, which made those assertions scan every file in the repository - markdown,
    # JSON fixtures and the case definition included - so they could never pass honestly.
    $exts = @(@(Prop $a 'extensions') | ForEach-Object { ([string]$_).TrimStart('*') })
    # t41: the tree-wide types normally scan the repository, but the canary case points them at a
    # throw-away tree so that a normal suite run can prove planting a violation really produces the
    # EXPECTED/ACTUAL failure. Without that proof a future `continue` could mute them again and every
    # run would stay green - which is exactly what happened between t32 and t38.
    $scanRoot = $script:PluginRoot
    if ($script:ScanRootOverride) { $scanRoot = [string]$script:ScanRootOverride }
    if ($t -eq 'parses') {
      $err = $null
      [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$err)
      Assert-True ('PowerShell parses ' + $file) (@($err).Count -eq 0) (($err | ForEach-Object { $_.Message }) -join ' | ')
      continue
    }
    # literal-zero / literal-min / hits-confined-to scan the whole tree themselves, so the
    # single-file existence check below does not apply to them. They must NOT be skipped here:
    # skipping them (this line used to be a bare `continue`) made every one of those assertions
    # dead code - found by t38 while narrowing the write-verb rule, and fixed in the same edit.
    $scansWholeTree = ($t -eq 'literal-zero' -or $t -eq 'literal-min' -or $t -eq 'hits-confined-to')
    if (-not $scansWholeTree) {
    if (-not (Test-Path -LiteralPath $path)) {
      # ifMissing:'skip' (t32): the target is internal material that does not ship, so its absence in
      # a published clone is expected. It is reported as a SKIP line with the concrete file name and
      # counted in the summary - never silently dropped, and never a failure.
      # Any other assertion keeps the original hard behaviour (Add-Failure 'file exists ...').
      if ([string](Prop $a 'ifMissing') -eq 'skip') {
        Add-Skip ('file exists ' + $file) ($file + ' is absent, and this assertion declares ifMissing=skip (internal material is not part of the published set)')
        continue
      }
      Add-Failure ('file exists ' + $file) 'exists' 'missing'
      continue
    }
    $bytes = [System.IO.File]::ReadAllBytes($path)
    $text = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    if ($t -eq 'no-bom') {
      $bom = (($bytes.Length -ge 3) -and ($bytes[0] -eq 0xEF) -and ($bytes[1] -eq 0xBB) -and ($bytes[2] -eq 0xBF))
      Assert-True ($file + ' has no UTF-8 BOM') (-not $bom) 'BOM present'
      continue
    }
    if ($t -eq 'ascii-only') {
      $bad = 0
      foreach ($b in $bytes) { if ($b -gt 0x7F) { $bad++ } }
      Assert-Eq ($file + ' non-ASCII byte count') 0 $bad
      continue
    }
    if ($t -eq 'contains') {
      Assert-Match ($file + ' contains /' + [string](Prop $a 'pattern') + '/') ([string](Prop $a 'pattern')) $text
      continue
    }
    }   # end of the single-file assertions (parses / no-bom / ascii-only / contains)
    if ($t -eq 'literal-zero') {
      # -CaseSensitive on purpose (t38): the pattern names literal verbs/tokens, and the default
      # case-insensitive match let the "move an item" alternative match the "delete an item" verb
      # (its spelling ends with those letters), which silently widened this rule to every
      # scratch-dir cleanup in the repository. The named set is what the case documents; banning the
      # delete verb outright (and allow-listing the %TEMP% cleanups) is a separate policy question.
      $hits = @(Get-ChildItem -LiteralPath $scanRoot -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $exts -contains $_.Extension } |
        Select-String -Pattern ([string](Prop $a 'pattern')) -CaseSensitive -ErrorAction SilentlyContinue)
      $excl = [string](Prop $a 'excludePattern')
      if ($excl) { $hits = @($hits | Where-Object { $_.Path -notmatch $excl }) }
      $allow = @()
      if (Has-Prop $a 'allowFiles') { $allow = @(Prop $a 'allowFiles') }
      $kept = @($hits | Where-Object { $p = $_.Path ; $k = $true ; foreach ($af in $allow) { if ($p -like ('*' + ([string]$af).Replace('/','\'))) { $k = $false } } ; $k })
      Assert-Eq ('literal /' + [string](Prop $a 'pattern') + '/ hit count') 0 $kept.Count
      if ($kept.Count -gt 0) { Add-Failure 'literal detail' 'no hits' ((@($kept | ForEach-Object { $_.Filename + ':' + $_.LineNumber + ' ' + $_.Line.Trim() })) -join ' ;; ') }
      continue
    }
    if ($t -eq 'literal-min') {
      $hits = @(Get-ChildItem -LiteralPath $scanRoot -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $exts -contains $_.Extension } |
        Select-String -Pattern ([string](Prop $a 'pattern')) -ErrorAction SilentlyContinue)
      Assert-True ('literal /' + [string](Prop $a 'pattern') + '/ appears at least ' + [string](Prop $a 'minCount') + ' times') ($hits.Count -ge [int](Prop $a 'minCount')) ('found ' + $hits.Count)
      continue
    }
    if ($t -eq 'hits-confined-to') {
      $hits = @(Get-ChildItem -LiteralPath $scanRoot -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $exts -contains $_.Extension } |
        Select-String -Pattern ([string](Prop $a 'pattern')) -ErrorAction SilentlyContinue)
      $allowRe = [string](Prop $a 'allowPattern')
      $outside = @($hits | Where-Object { $_.Path.Substring($scanRoot.Length).TrimStart('\').Replace('\','/') -notmatch $allowRe })
      Assert-Eq ('all /' + [string](Prop $a 'pattern') + '/ hits inside /' + $allowRe + '/') 0 $outside.Count
      if ($outside.Count -gt 0) { Add-Failure 'outside detail' ('only under ' + $allowRe) ((@($outside | ForEach-Object { $_.Filename + ':' + $_.LineNumber })) -join ', ') }
      continue
    }
    Add-Failure 'filescan assert type' 'a known type' $t
  }
}

function Invoke-IsolationCase {
  param($Case,[string]$CaseDir)
  $tmp = New-TempDir $script:CaseId
  $homeSpec = Prop (Prop $Case 'tmp') 'home'
  $hp = Join-Path $tmp 'home'
  [void](New-Item -ItemType Directory -Force -Path $hp)
  $settings = 'networkExposure: loopback'
  if ($homeSpec -and (Has-Prop $homeSpec 'settings')) { $settings = [string](Prop $homeSpec 'settings') }
  Write-TextFile (Join-Path $hp 'settings.yaml') $settings
  Write-TextFile (Join-Path $hp '.credentials.yaml') "placeholder: not-a-real-credential`n"
  foreach ($pn in @('Alpha','Beta')) {
    $pd = Join-Path $hp ('profiles\' + $pn)
    [void](New-Item -ItemType Directory -Force -Path $pd)
    Write-TextFile (Join-Path $pd 'cordis.patch.yml') "networkExposure: loopback`n"
  }
  $before = Get-TreeSnapshot $hp
  $fx = Build-CaseFixture $Case $CaseDir $tmp
  $a = Resolve-CaseArgs $Case $CaseDir $fx $tmp ''
  $a = @($a | Where-Object { $_ -ne '<ABSENT_HOME>' })
  # replace the default absent home with the real temp home
  $newArgs = New-Object System.Collections.ArrayList
  for ($i = 0; $i -lt $a.Count; $i++) {
    if ($a[$i] -eq '-DshHome') { [void]$newArgs.Add($a[$i]) ; [void]$newArgs.Add($hp) ; $i++ ; continue }
    [void]$newArgs.Add($a[$i])
  }
  $res = Invoke-CollectorProcess ($newArgs.ToArray()) $ChildTimeoutSec
  $after = Get-TreeSnapshot $hp
  Test-CollectorExpectation $Case $res
  # no file in the temp home may appear, disappear or change content
  foreach ($k in $before.Keys) {
    Assert-True ('temp DSH_HOME file untouched: ' + $k) ($after.ContainsKey($k)) 'file disappeared'
    if ($after.ContainsKey($k)) { Assert-Eq ('temp DSH_HOME hash of ' + $k) $before[$k] $after[$k] }
  }
  foreach ($k in $after.Keys) {
    Assert-True ('no new file in the temp DSH_HOME: ' + $k) ($before.ContainsKey($k)) 'file appeared'
  }
  $all = @(Get-ChildItem -LiteralPath $hp -Recurse -File | ForEach-Object { $_.FullName.Substring($hp.Length) })
  Assert-Eq 'file count under the temp DSH_HOME' $before.Count $all.Count
}

function Get-TreeSnapshot {
  param([string]$Root)
  $h = @{}
  foreach ($f in @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force -ErrorAction SilentlyContinue)) {
    $rel = $f.FullName.Substring($Root.Length)
    $h[$rel] = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
  }
  return $h
}

function Get-JsonPathValue {
  # Minimal path reader for case assertions: 'summary.exitCode', 'records[2].classification.status'.
  param($Doc,[string]$Path)
  $cur = $Doc
  foreach ($seg in ($Path -split '\.')) {
    if ($null -eq $cur) { return $null }
    $m = [regex]::Match($seg, '^([^\[]+)(?:\[(\d+)\])?$')
    if (-not $m.Success) { return $null }
    $cur = Prop $cur $m.Groups[1].Value
    $idx = $m.Groups[2].Value
    if ($idx -ne '') {
      $arr = @($cur)
      $i = [int]$idx
      if ($i -ge $arr.Count) { return $null }
      $cur = $arr[$i]
    }
  }
  return $cur
}

function Invoke-UninstallCase {
  # t38: fixture-driven, offline, repeatable cases for the only optional write component
  # (tools/uninstall.ps1). The runner writes the fixture and the pre-existing files into the case
  # temp dir, runs the tool with an explicit -StateDir (so an offline run can never touch the real
  # state directory), and then asserts on: the exit code, the -AsJson report, the backup file set,
  # every MANIFEST entry (sha256 + byte count recomputed), which files survived, and - for the
  # dry-run cases - that the case temp dir is byte-identical afterwards.
  param($Case,[string]$CaseDir)
  $spec = Prop $Case 'uninstall'
  if ($null -eq $spec) { Add-Failure 'uninstall block' 'a uninstall spec' 'missing'; return }
  $tool = Join-Path $script:PluginRoot 'tools\uninstall.ps1'
  if (-not (Test-Path -LiteralPath $tool)) { Add-Failure 'uninstaller exists' 'tools/uninstall.ps1' 'missing'; return }
  $tmp = New-TempDir $script:CaseId
  $state = Join-Path $tmp 'state'
  $fxp = Join-Path $tmp 'fixture.json'
  if (Has-Prop $spec 'tmpFiles') {
    foreach ($p in (Prop $spec 'tmpFiles').PSObject.Properties) { Write-TextFile (Join-Path $tmp $p.Name) (Expand-CaseToken ([string]$p.Value)) }
  }
  if (Has-Prop $spec 'stateFiles') {
    [void](New-Item -ItemType Directory -Force -Path $state)
    foreach ($p in (Prop $spec 'stateFiles').PSObject.Properties) { Write-TextFile (Join-Path $state $p.Name) (Expand-CaseToken ([string]$p.Value)) }
  }
  $withFixture = $false
  if (Has-Prop $spec 'fixture') {
    Write-TextFile $fxp (Expand-CaseToken ((Prop $spec 'fixture') | ConvertTo-Json -Depth 14))
    $withFixture = $true
  }
  $argList = New-Object System.Collections.ArrayList
  foreach ($a in @('-NoProfile','-ExecutionPolicy','Bypass','-File',$tool,'-StateDir',$state)) { [void]$argList.Add($a) }
  if ($withFixture) { [void]$argList.Add('-FixturePath'); [void]$argList.Add($fxp) }
  $wantJson = $false
  foreach ($a in @(Prop $spec 'args')) {
    $s = Expand-CaseToken ([string]$a)
    if ($s -eq '-AsJson') { $wantJson = $true }
    [void]$argList.Add($s)
  }
  $before = Get-TreeSnapshot $tmp
  $r = Invoke-ChildProcess $script:PsExe $argList.ToArray() 180
  if ($r.startError) { Add-Failure 'uninstaller starts' 'no start error' $r.startError; return }
  if ($r.timedOut) { Add-Failure 'uninstaller finishes' 'within 180 s' 'timed out'; return }
  $expExit = 0
  if (Has-Prop $spec 'expectExit') { $expExit = [int](Prop $spec 'expectExit') }
  Assert-Eq 'uninstaller exit code' $expExit ([int]$r.exitCode)

  $doc = $null
  if ($wantJson) {
    try { $doc = ($r.stdout | ConvertFrom-Json) } catch {
      Add-Failure 'report parses as JSON' 'a -AsJson report' (($r.stdout.Substring(0, [Math]::Min(400, $r.stdout.Length))) + ' :: ' + $_.Exception.Message)
      return
    }
  }
  foreach ($e in @(@(Prop $spec 'jsonEq') | Where-Object { $null -ne $_ -and (Has-Prop $_ 'path') })) {
    $pth = [string](Prop $e 'path')
    Assert-Eq ('json ' + $pth) ([string](Prop $e 'eq')) ([string](Get-JsonPathValue $doc $pth))
  }
  foreach ($e in @(@(Prop $spec 'jsonIn') | Where-Object { $null -ne $_ -and (Has-Prop $_ 'path') })) {
    $pth = [string](Prop $e 'path')
    $list = @(@(Prop $e 'in') | ForEach-Object { [string]$_ })
    $got = [string](Get-JsonPathValue $doc $pth)
    Assert-True ('json ' + $pth + ' is one of [' + ($list -join ' | ') + ']') ($list -contains $got) ('got: ' + $got)
  }
  foreach ($e in @(@(Prop $spec 'jsonMatch') | Where-Object { $null -ne $_ -and (Has-Prop $_ 'path') })) {
    $pth = [string](Prop $e 'path')
    Assert-Match ('json ' + $pth + ' matches /' + [string](Prop $e 'match') + '/') ([string](Prop $e 'match')) ([string](Get-JsonPathValue $doc $pth))
  }
  foreach ($e in @(@(Prop $spec 'jsonNotMatch') | Where-Object { $null -ne $_ -and (Has-Prop $_ 'path') })) {
    $pth = [string](Prop $e 'path')
    Assert-NoMatch ('json ' + $pth + ' does not match /' + [string](Prop $e 'notMatch') + '/') ([string](Prop $e 'notMatch')) ([string](Get-JsonPathValue $doc $pth))
  }
  foreach ($s in @(@(Prop $spec 'orderingContains') | Where-Object { $null -ne $_ -and [string]$_ -ne '' })) {
    $joined = (@(Get-JsonPathValue $doc 'ordering') | ForEach-Object { [string]$_ }) -join ' | '
    Assert-Match ('ordering mentions /' + [string]$s + '/') ([string]$s) $joined
  }

  $after = Get-TreeSnapshot $tmp
  if ($true -eq (Prop $spec 'assertNoTmpWrites')) {
    $changed = New-Object System.Collections.ArrayList
    foreach ($k in @($before.Keys)) {
      if (-not $after.ContainsKey($k)) { [void]$changed.Add('deleted:' + $k) }
      elseif ($after[$k] -ne $before[$k]) { [void]$changed.Add('modified:' + $k) }
    }
    foreach ($k in @($after.Keys)) { if (-not $before.ContainsKey($k)) { [void]$changed.Add('created:' + $k) } }
    Assert-Eq 'dry run creates, modifies and deletes nothing under the case temp dir' 0 $changed.Count
    if ($changed.Count -gt 0) { Add-Failure 'temp dir changes' 'no change' (@($changed) -join ', ') }
  }
  foreach ($n in @(@(Prop $spec 'expectFilesPresentUnchanged') | Where-Object { $null -ne $_ -and [string]$_ -ne '' })) {
    $p = Join-Path $tmp ([string]$n)
    Assert-True ('file is still present: ' + $n) (Test-Path -LiteralPath $p) 'absent'
    $rel = $p.Substring($tmp.Length)
    if ($before.ContainsKey($rel) -and $after.ContainsKey($rel)) { Assert-Eq ('file bytes unchanged: ' + $n) $before[$rel] $after[$rel] }
  }
  foreach ($n in @(@(Prop $spec 'expectFilesAbsent') | Where-Object { $null -ne $_ -and [string]$_ -ne '' })) {
    Assert-True ('file is gone: ' + $n) (-not (Test-Path -LiteralPath (Join-Path $tmp ([string]$n)))) 'still present'
  }
  if (Has-Prop $spec 'expectBackupFiles') {
    $broot = Join-Path $state 'backups'
    $dirs = @(Get-ChildItem -LiteralPath $broot -Directory -Force -ErrorAction SilentlyContinue)
    Assert-Eq 'exactly one backup directory' 1 $dirs.Count
    if ($dirs.Count -eq 1) {
      $names = @(Get-ChildItem -LiteralPath $dirs[0].FullName -File -Force | ForEach-Object { $_.Name } | Sort-Object)
      $want = @(@(Prop $spec 'expectBackupFiles') | ForEach-Object { [string]$_ } | Sort-Object)
      Assert-Eq 'backup file set' ($want -join ', ') ($names -join ', ')
    }
  }
  if ($true -eq (Prop $spec 'verifyBackupManifest')) {
    $broot = Join-Path $state 'backups'
    $man = @(Get-ChildItem -LiteralPath $broot -Recurse -File -Filter 'MANIFEST.json' -Force -ErrorAction SilentlyContinue | Select-Object -First 1)
    Assert-Eq 'a MANIFEST.json was written' 1 $man.Count
    if ($man.Count -eq 1) {
      $mj = $null
      try { $mj = (Get-Content -LiteralPath $man[0].FullName -Raw -Encoding UTF8 | ConvertFrom-Json) }
      catch { Add-Failure 'MANIFEST.json parses' 'JSON' $_.Exception.Message }
      if ($null -ne $mj) {
        $entries = @(Prop $mj 'files')
        Assert-True 'MANIFEST.json lists at least one file' ($entries.Count -ge 1) ('entries: ' + $entries.Count)
        $bad = 0
        foreach ($e in $entries) {
          $n = [string](Prop $e 'name')
          $sh = [string](Prop $e 'sha256')
          $by = [int64](Prop $e 'bytes')
          $fp = Join-Path $man[0].Directory.FullName $n
          if (-not (Test-Path -LiteralPath $fp)) { $bad++; Add-Failure ('MANIFEST entry exists: ' + $n) 'present' 'missing'; continue }
          $real = (Get-FileHash -LiteralPath $fp -Algorithm SHA256).Hash
          $rlen = (Get-Item -LiteralPath $fp).Length
          if ($real -ne $sh -or $rlen -ne $by) { $bad++; Add-Failure ('MANIFEST entry verifies: ' + $n) ($sh + ' / ' + $by + ' bytes') ($real + ' / ' + $rlen + ' bytes') }
        }
        Assert-Eq 'every MANIFEST entry verifies (sha256 + byte count)' 0 $bad
      }
    }
  }
}

function Get-WouldBeFailures {
  # t41: run the REAL filescan assertion engine against an arbitrary root and return the failures it
  # produced, without letting them escape into the case under test. This is the positive control's
  # measuring instrument - same code path a normal filescan case goes through, no re-implementation.
  param($Spec,[string]$Root)
  $savedRoot = $script:ScanRootOverride
  $savedFailures = $script:Failures
  $script:ScanRootOverride = $Root
  $script:Failures = New-Object System.Collections.ArrayList
  try {
    $probe = [pscustomobject]@{ filescan = [pscustomobject]@{ asserts = @($Spec) } }
    Invoke-FileScanCase $probe $Root
    return @($script:Failures)
  } finally {
    $script:Failures = $savedFailures
    $script:ScanRootOverride = $savedRoot
  }
}

function New-CanaryFile {
  param([string]$Dir,[string]$Name,[string]$Text)
  [void](New-Item -ItemType Directory -Force -Path $Dir)
  Write-TextFile (Join-Path $Dir $Name) $Text
}

function Show-CanaryEvidence {
  param([string]$Label,$F)
  # Informational: the acceptance wants the raw EXPECTED/ACTUAL text in the log. The pass/fail of
  # this case is decided by the Assert-* calls around each call, never by this line.
  if (@($F).Count -gt 0) {
    Write-Output ('        CANARY evidence ' + $Label + ': rule=' + [string]$F[0].rule + ' :: EXPECTED ' + [string]$F[0].expected + ' / ACTUAL ' + [string]$F[0].actual)
  } else {
    Write-Output ('        CANARY evidence ' + $Label + ': 0 engine failures')
  }
}

function Invoke-CanaryCase {
  # t41 positive control for the three tree-wide filescan assertion types. Between t32 and t38 a bare
  # `continue` made every one of them dead code, so two filescan cases passed vacuously and nobody
  # noticed. This case is the antidote: it plants a violation in a throw-away tree, runs the real
  # engine over it, and asserts on the failure record - so reintroducing that `continue` (or any other
  # mute) turns THIS case red in the same run. Each type gets a planted and a clean twin.
  param($Case,[string]$CaseDir)
  $root = New-TempDir $script:CaseId

  # --- literal-zero: a planted write verb must be reported, a clean tree must not
  # The violating verb is assembled from fragments ON PURPOSE: this file is itself scanned by the
  # rule under test (tests/cases/filescan-no-repo-write-paths), so writing the verb literally here
  # would make the suite fail on its own canary. Same reason repo-hygiene.ps1 fragments its blocklist.
  $zeroVerb = 'Set' + '-Content'
  $p1 = Join-Path $root 'zero-planted'
  New-CanaryFile $p1 'bad.ps1' ($zeroVerb + " -LiteralPath x.txt -Value y`n")
  New-CanaryFile $p1 'clean.ps1' ("Write-Output 'nothing to see here'`n")
  $a1 = [pscustomobject]@{ type = 'literal-zero'; extensions = @('*.ps1'); pattern = $zeroVerb }
  $f1 = @(Get-WouldBeFailures $a1 $root)
  Show-CanaryEvidence 'literal-zero(planted)' $f1
  $c1 = @($f1 | Where-Object { $_.rule -match 'hit count' })
  Assert-Eq 'canary/literal-zero: the planted violation produces the hit-count assertion failure' 1 $c1.Count
  if ($c1.Count -eq 1) {
    Assert-Eq 'canary/literal-zero: engine EXPECTED is 0' '0' ([string]$c1[0].expected)
    Assert-Eq 'canary/literal-zero: engine ACTUAL is 1' '1' ([string]$c1[0].actual)
  }
  Assert-Eq 'canary/literal-zero: the planted violation also yields the raw detail line' 1 @($f1 | Where-Object { $_.rule -eq 'literal detail' }).Count
  Assert-True 'canary/literal-zero: a planted tree is never reported as clean' ($f1.Count -ge 1) ('failures: ' + $f1.Count)
  $p2 = Join-Path $root 'zero-clean'
  New-CanaryFile $p2 'clean.ps1' ("Write-Output 'nothing to see here'`n")
  $f2 = @(Get-WouldBeFailures $a1 $p2)
  Show-CanaryEvidence 'literal-zero(clean)' $f2
  Assert-Eq 'canary/literal-zero: the clean twin yields no engine failure' 0 $f2.Count

  # --- literal-min: one occurrence against minCount 3 must fail; three must pass
  $p3 = Join-Path $root 'min-short'
  New-CanaryFile $p3 'one.ps1' ("Get-Pattern 'netsh_canary'`n")
  $a2 = [pscustomobject]@{ type = 'literal-min'; extensions = @('*.ps1'); pattern = "Get-Pattern 'netsh_"; minCount = 3 }
  $f3 = @(Get-WouldBeFailures $a2 $p3)
  Show-CanaryEvidence 'literal-min(short)' $f3
  Assert-Eq 'canary/literal-min: below minCount yields exactly one engine failure' 1 $f3.Count
  if ($f3.Count -eq 1) {
    Assert-Match 'canary/literal-min: engine rule text names the minimum' 'at least 3 times' ([string]$f3[0].rule)
    Assert-Eq 'canary/literal-min: engine ACTUAL reports the found count' 'found 1' ([string]$f3[0].actual)
  }
  $p4 = Join-Path $root 'min-enough'
  New-CanaryFile $p4 'three.ps1' ("Get-Pattern 'netsh_a'`nGet-Pattern 'netsh_b'`nGet-Pattern 'netsh_c'`n")
  $f4 = @(Get-WouldBeFailures $a2 $p4)
  Show-CanaryEvidence 'literal-min(enough)' $f4
  Assert-Eq 'canary/literal-min: at minCount yields no engine failure' 0 $f4.Count

  # --- hits-confined-to: a hit outside allowPattern must fail; one inside must pass
  $p5 = Join-Path $root 'confined-bad'
  New-CanaryFile $p5 'outside.ps1' ("# T41CANARY`n")
  $a3 = [pscustomobject]@{ type = 'hits-confined-to'; extensions = @('*.ps1'); pattern = 'T41CANARY'; allowPattern = '^allowed/' }
  $f5 = @(Get-WouldBeFailures $a3 $p5)
  Show-CanaryEvidence 'hits-confined-to(outside)' $f5
  $c5 = @($f5 | Where-Object { $_.rule -match 'hits inside' })
  Assert-Eq 'canary/hits-confined-to: the planted outside hit produces the confinement failure' 1 $c5.Count
  if ($c5.Count -eq 1) {
    Assert-Eq 'canary/hits-confined-to: engine EXPECTED is 0' '0' ([string]$c5[0].expected)
    Assert-Eq 'canary/hits-confined-to: engine ACTUAL is 1' '1' ([string]$c5[0].actual)
  }
  Assert-Eq 'canary/hits-confined-to: the planted outside hit also yields the raw detail line' 1 @($f5 | Where-Object { $_.rule -eq 'outside detail' }).Count
  $p6 = Join-Path $root 'confined-ok'
  New-CanaryFile (Join-Path $p6 'allowed') 'inside.ps1' ("# T41CANARY`n")
  $f6 = @(Get-WouldBeFailures $a3 $p6)
  Show-CanaryEvidence 'hits-confined-to(inside)' $f6
  Assert-Eq 'canary/hits-confined-to: a hit inside allowPattern yields no engine failure' 0 $f6.Count
}


function Invoke-PortabilityCase {
  param($Case,[string]$CaseDir)
  $tmp = New-TempDir $script:CaseId
  # A real Chinese directory name with a space, built from code points so that THIS FILE
  # stays pure ASCII. Measured trap: Windows PowerShell 5.1 decodes a BOM-less script as the
  # system ANSI code page, where a UTF-8 non-ASCII sequence can absorb the following quote
  # byte and produce a wall of fake syntax errors (that is exactly what happened while
  # writing this suite). The collector itself is ASCII-only for the same reason; this case
  # proves a Chinese/space install path still works.
  $cnDir = ([char]0x63D2) + ([char]0x4EF6) + ([char]0x76EE) + ([char]0x5F55) + ' ' + ([char]0x5E26) + ([char]0x7A7A) + ([char]0x683C)
  $copyRoot = Join-Path $tmp $cnDir
  $copySrc = Join-Path $copyRoot 'src'
  [void](New-Item -ItemType Directory -Force -Path $copySrc)
  [void](New-Item -ItemType Directory -Force -Path (Join-Path $copyRoot 'i18n'))
  Copy-Item -LiteralPath $script:Collector -Destination (Join-Path $copySrc 'collect.ps1') -Force
  foreach ($lf in @(Get-ChildItem -LiteralPath (Join-Path $script:PluginRoot 'i18n') -File)) {
    Copy-Item -LiteralPath $lf.FullName -Destination (Join-Path (Join-Path $copyRoot 'i18n') $lf.Name) -Force
  }
  $srcHash = (Get-FileHash -LiteralPath (Join-Path $copySrc 'collect.ps1') -Algorithm SHA256).Hash
  $origHash = (Get-FileHash -LiteralPath $script:Collector -Algorithm SHA256).Hash
  Assert-Eq 'the copied collector is byte-identical to the tested one' $origHash $srcHash
  # build the fixture, place it under the copy root, and run the COPY
  $savedCollector = $script:Collector
  $fxTmp = New-TempDir ($script:CaseId + '\fx')
  $fx = Build-CaseFixture $Case $CaseDir $fxTmp
  $fxCopy = Join-Path $copyRoot 'fixture.json'
  Copy-Item -LiteralPath $fx -Destination $fxCopy -Force
  $script:Collector = Join-Path $copySrc 'collect.ps1'
  $a = Resolve-CaseArgs $Case $CaseDir $fxCopy $tmp $copyRoot
  $resCopy = Invoke-CollectorProcess $a $ChildTimeoutSec
  $script:Collector = $savedCollector
  Test-CollectorExpectation $Case $resCopy
  # the same fixture through the original path must give the same verdict map
  $a2 = Resolve-CaseArgs $Case $CaseDir $fx $tmp ''
  $resOrig = Invoke-CollectorProcess $a2 $ChildTimeoutSec
  $m1 = $null ; $m2 = $null
  try { $m1 = Get-VerdictMap ($resCopy.stdout | ConvertFrom-Json) } catch { }
  try { $m2 = Get-VerdictMap ($resOrig.stdout | ConvertFrom-Json) } catch { }
  if ($null -eq $m1 -or $null -eq $m2) { Add-Failure 'verdict equivalence across the path change' 'both runs parse' 'one of them did not' }
  else {
    $diff = New-Object System.Collections.ArrayList
    foreach ($k in $m2.Keys) { if ($m1[$k] -ne $m2[$k]) { [void]$diff.Add($k + '(' + $m2[$k] + '->' + $m1[$k] + ')') } }
    Assert-True 'verdicts are identical from a Chinese/space path' ($diff.Count -eq 0) (($diff.ToArray()) -join ', ')
  }
  Assert-Eq 'exit code is identical from a Chinese/space path' $resOrig.exitCode $resCopy.exitCode
}

function Invoke-PrereqCase {
  param($Case,[string]$CaseDir)
  $spec = Prop $Case 'prereq'
  $sp = Join-Path $script:PluginRoot ([string](Prop $spec 'script'))
  if (-not (Test-Path -LiteralPath $sp)) { Add-Failure 'prereq script exists' ([string](Prop $spec 'script')) 'missing' ; return }
  $text = [System.IO.File]::ReadAllText($sp, [System.Text.Encoding]::UTF8)
  foreach ($fp in @(Prop $spec 'forbiddenParams')) {
    # a real parameter would be declared as [switch]$Name or in the param block
    Assert-NoMatch ('no ' + [string]$fp + ' parameter is declared in ' + [string](Prop $spec 'script')) ('(?im)^\s*\[\s*switch\s*\]\s*\$' + [regex]::Escape(([string]$fp).TrimStart('-')) + '\b') $text
  }
  foreach ($ft in @(Prop $spec 'forbiddenText')) {
    Assert-NoMatch ('no "' + [string]$ft + '" call path in the prereq script') ([regex]::Escape([string]$ft)) $text
  }
  $a = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$sp)
  if (Has-Prop $spec 'args') { $a = $a + @(Prop $spec 'args') }
  $res = Invoke-ChildProcess $script:PsExe $a $ChildTimeoutSec
  if (Has-Prop $spec 'expectExitIn') { Assert-In 'prereq exit code' (Prop $spec 'expectExitIn') $res.exitCode }
  $json = $null
  try { $json = $res.stdout | ConvertFrom-Json } catch { }
  if (Has-Prop $spec 'stdoutMatch') { foreach ($m in @(Prop $spec 'stdoutMatch')) { Assert-Match 'prereq stdout' $m $res.stdout } }
  if (Has-Prop $spec 'expectProps') {
    if ($null -eq $json) { Add-Failure 'prereq JSON parses' 'JSON on stdout' ('head: ' + $res.stdout.Substring(0, [Math]::Min(200, $res.stdout.Length))) }
    else {
      foreach ($p in (Prop $spec 'expectProps').PSObject.Properties) {
        Assert-Eq ('prereq ' + $p.Name) ([string]$p.Value) ([string](Get-Nested $json $p.Name))
      }
    }
  }
}

# ---------------------------------------------------------------------------
# section 7: hardcoded-value pattern table (defensive-spec section 2.1)
# ---------------------------------------------------------------------------

$script:HardcodePatterns = [ordered]@{
  'abs-user-path'   = '[A-Za-z]:\\Users\\[^\\]+'
  # Assembled from fragments on purpose: the contiguous literal would be a hit of this very
  # scan (the scanner's own table is source code too). The resulting pattern is unchanged.
  'username'        = ('\' + '\' + 'admin' + '\' + '\')
  'hostname'        = 'DESKTOP-[A-Z0-9]+|LAPTOP-[A-Z0-9]+'
  'fixed-peer-ip'   = '\b100\.(?!64\.0\.0/10)\d{1,3}\.\d{1,3}\.\d{1,3}\b'
  'fixed-tailnet'   = '[A-Za-z0-9-]+\.tail[a-z0-9]+\.ts\.net'
  'credential-like' = 'tskey-[A-Za-z0-9]+|eyJ[A-Za-z0-9._-]{20,}|\?token=[A-Za-z0-9]{8,}'
}

# ---------------------------------------------------------------------------
# section 7.1: approved neutral placeholders (t23, captain ruling)
# ---------------------------------------------------------------------------
# The captain ruled that these values ARE allowed in prose and fixtures: they are the sanitized
# placeholders this project standardised on in t13-t15, plus the protocol constants and the
# RFC 5737 documentation ranges. They are not real identifiers, so a scan that cannot tell them
# apart from a real host or address produces false failures - measured in the t21 review (R3-2):
# the release-layer docs and the hygiene gate wrote them to TEACH this rule, and the old rule
# failed on exactly that.
# Positive control (this file therefore never quotes the planted values - the scanner's own source
# is code too): scan-positive-control-catches-each-extension plants a peer address outside the
# CGNAT constant, a workstation-style host name and a user-profile path, plus one approved
# placeholder; the three real ones must still be counted and the approved one must not.
$script:ApprovedPlaceholders = @(
  '100\.64\.0\.0/10',                        # CGNAT protocol constant
  'fd7a:115c:a1e0::/48',                     # Tailscale IPv6 product prefix (constant)
  'fd7a:115c:a1e0::1000:[0-9a-fA-F]+',       # tailnet IPv6 node placeholder (t14)
  '100\.64\.0\.(?:11|12)\b',                 # tailnet IPv4 placeholders (t13)
  '\b10\.(?:20|21|22)\.\d{1,3}\.\d{1,3}\b',  # neutralised RFC1918 placeholders (t14/t15)
  '\b198\.51\.100\.\d{1,3}\b',               # RFC 5737 documentation range
  '\b203\.0\.113\.\d{1,3}\b'                 # RFC 5737 documentation range
)

# ---------------------------------------------------------------------------
# section 8: suite-level gates
# ---------------------------------------------------------------------------

function Get-WildcardListenerMap {
  # real, read-only machine measurement used by the suite-level gate: every wildcard TCP
  # listener with its owning PID. Returns $null when netstat is not usable.
  $netstat = Join-Path $env:SystemRoot 'System32\netstat.exe'
  if (-not (Test-Path -LiteralPath $netstat)) { return $null }
  $h = @{}
  $out = & $netstat -ano 2>$null | Out-String
  foreach ($ln in @($out -split "`r?`n")) {
    if ($ln -notmatch 'LISTENING') { continue }
    $t = @(($ln.Trim() -replace '\s+', ' ') -split ' ')
    if ($t.Count -lt 4 -or $t[0] -ne 'TCP') { continue }
    $local = $t[1]
    $host_ = $local
    if ($host_.StartsWith('[')) { $host_ = $host_.Substring(1, $host_.IndexOf(']') - 1) } else { $host_ = ($host_ -split ':')[0] }
    if ($host_ -eq '0.0.0.0' -or $host_ -eq '::') {
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

function Get-SuiteTreeSnapshot {
  $h = @{}
  foreach ($f in @(Get-ChildItem -LiteralPath $script:PluginRoot -Recurse -File -Force -ErrorAction SilentlyContinue)) {
    $h[$f.FullName.Substring($script:PluginRoot.Length)] = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
  }
  return $h
}

# ---------------------------------------------------------------------------
# section 9: driver
# ---------------------------------------------------------------------------

function Get-CaseList {
  $acc = New-Object System.Collections.ArrayList
  foreach ($d in @(Get-ChildItem -LiteralPath $script:CasesDir -Directory -ErrorAction SilentlyContinue | Sort-Object Name)) {
    if ($d.Name -eq '_base') { continue }
    $cf = Join-Path $d.FullName 'case.json'
    if (-not (Test-Path -LiteralPath $cf)) { continue }
    $c = $null
    try { $c = Read-JsonFile $cf } catch { Write-Output ('CASE LOAD ERROR ' + $d.Name + ': ' + $_.Exception.Message) ; continue }
    [void]$acc.Add([pscustomobject]@{ dir=$d.FullName; name=$d.Name; case=$c })
  }
  return $acc.ToArray()
}

if ($List) {
  Write-Output '# generated by: powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/tests/run-tests.ps1 -List'
  Write-Output ''
  Write-Output '| case id | kind | injected input | expected judgement + exit code |'
  Write-Output '|---|---|---|---|'
  foreach ($item in Get-CaseList) {
    $c = $item.case
    $xf = ''
    if (Has-Prop $c 'xfail') { $xf = ' **xfail**' }
    Write-Output ('| `' + [string](Prop $c 'id') + '` | ' + [string](Prop $c 'kind') + ' | ' + ([string](Prop $c 'inject')).Replace('|', '\|') + ' | ' + ([string](Prop $c 'expectSummary')).Replace('|', '\|') + $xf + ' |')
  }
  exit 0
}

$script:TempBase = New-TempDir 'base'
$collectorStartHash = (Get-FileHash -LiteralPath $script:Collector -Algorithm SHA256).Hash
$before = Get-SuiteTreeSnapshot
$wildBefore = Get-WildcardListenerMap

$items = Get-CaseList
$nRun = 0; $nPass = 0; $nFail = 0; $nXfail = 0; $nXpass = 0
$failDetail = New-Object System.Collections.ArrayList

Write-Output ('collector : ' + $script:Collector)
Write-Output ('cases     : ' + $script:CasesDir)
Write-Output ('powershell: ' + $PSVersionTable.PSVersion + ' ' + $PSVersionTable.PSEdition + '  (child: ' + $script:PsExe + ')')
Write-Output ''

try {
  foreach ($item in $items) {
    $c = $item.case
    $id = [string](Prop $c 'id')
    $kind = [string](Prop $c 'kind')
    if ($Filter -and ($id -notmatch $Filter)) { continue }
    if ($Only -and ($kind -ne $Only)) { continue }
    $nRun++
    $script:CaseId = $id
    $script:Failures = New-Object System.Collections.ArrayList
    $script:Skips = New-Object System.Collections.ArrayList
    $script:TokenMap = @{
      '<CASEDIR>'     = $item.dir
      '<TMP>'         = (Join-Path $script:TempBase $id)
      '<ABSENT_HOME>' = (Join-Path $script:TempBase 'absent-home')
      '<ABSENT_APP>'  = (Join-Path $script:TempBase 'absent-app')
    }
    Set-CaseEnvironment (Prop $c 'env') $true
    try {
      switch ($kind) {
        'collector'   { Invoke-CollectorCase $c $item.dir }
        'scan'        { Invoke-ScanCase $c $item.dir }
        'filescan'    { Invoke-FileScanCase $c $item.dir }
        'uninstall'   { Invoke-UninstallCase $c $item.dir }
        'canary'      { Invoke-CanaryCase $c $item.dir }
        'isolation'   { Invoke-IsolationCase $c $item.dir }
        'portability' { Invoke-PortabilityCase $c $item.dir }
        'prereq'      { Invoke-PrereqCase $c $item.dir }
        default       { Add-Failure 'case kind' 'one of collector/scan/filescan/uninstall/isolation/portability/prereq' $kind }
      }
    } catch {
      Add-Failure 'case execution' 'the case runs to completion' $_.Exception.Message
    } finally {
      Restore-CaseEnvironment
    }
    $isXfail = Has-Prop $c 'xfail'
    $ok = ($script:Failures.Count -eq 0)
    $tag = ''
    if ($ok) { $tag = 'PASS' ; $nPass++ } else { $tag = 'FAIL' ; $nFail++ }
    if ($isXfail) {
      # xfail: the case documents a KNOWN gap and passes only while the gap still exists.
      # If it starts passing, that is reported as XPASS and fails the suite, so the marker
      # gets flipped instead of rotting.
      if (-not $ok) { $tag = 'XFAIL' ; $nFail-- ; $nXfail++ }
      else { $tag = 'XPASS' ; $nPass-- ; $nFail++ ; $nXpass++ }
    }
    $line = ('[' + $nRun.ToString().PadLeft(2) + '] ' + $tag.PadRight(5) + ' ' + $id.PadRight(38) + ' ' + [string](Prop $c 'expectSummary'))
    Write-Output $line
    foreach ($s in $script:Skips) {
      # declared skips are printed under their case, with the concrete file name - never hidden
      Write-Output ('        SKIP  ' + $s.rule + ' - ' + $s.text)
    }
    if (-not $ok -and -not $isXfail) {
      foreach ($f in $script:Failures) {
        Write-Output ('        - ' + $f.rule + ': EXPECTED ' + $f.expected + ' / ACTUAL ' + $f.actual)
        [void]$failDetail.Add($id + ' :: ' + $f.rule + ' :: expected=' + $f.expected + ' :: actual=' + $f.actual)
      }
    } elseif ($isXfail -and -not $ok) {
      Write-Output ('        xfail held: ' + [string](Prop (Prop $c 'xfail') 'reason'))
    } elseif ($isXfail -and $ok) {
      Write-Output ('        XPASS - this known gap now passes; flip the xfail marker in tests/cases/' + $item.name + '/case.json')
      if (Has-Prop (Prop $c 'xfail') 'reason') { [void]$failDetail.Add($id + ' :: unexpected pass :: ' + [string](Prop (Prop $c 'xfail') 'reason')) }
    }
  }

  Write-Output ''
  Write-Output '--- suite-level gates (real machine, measured outside the fixtures) ---'
  $after = Get-SuiteTreeSnapshot
  $created = New-Object System.Collections.ArrayList
  $deleted = New-Object System.Collections.ArrayList
  $modified = New-Object System.Collections.ArrayList
  foreach ($k in $before.Keys) {
    if (-not $after.ContainsKey($k)) { [void]$deleted.Add($k) }
    elseif ($after[$k] -ne $before[$k]) { [void]$modified.Add($k) }
  }
  foreach ($k in $after.Keys) { if (-not $before.ContainsKey($k)) { [void]$created.Add($k) } }
  $colNow = (Get-FileHash -LiteralPath $script:Collector -Algorithm SHA256).Hash
  # G1a: the suite's own territory must be frozen. A case file that rewrote itself would mean
  # the run was judged by data it had already changed. On a frozen checkout this gate also
  # covers the rest of the tree, because nothing else changes either.
  $inTests = New-Object System.Collections.ArrayList
  foreach ($k in @($created.ToArray()) + @($deleted.ToArray()) + @($modified.ToArray())) { if ($k -like '*\tests\*') { [void]$inTests.Add($k) } }
  if ($inTests.Count -eq 0) {
    Write-Output 'G1a no file under tests/ was created, deleted or modified: OK'
  } else {
    Write-Output ('G1a tests/ CHANGED during the run: ' + (($inTests.ToArray()) -join ', '))
    $nFail++
    [void]$failDetail.Add('G1a :: tests/ changed during the run :: ' + (($inTests.ToArray()) -join ', '))
  }
  # G1b: if the collector under test was itself rewritten mid-run, the verdicts above are not
  # all attributable to one revision. That is a hard failure - the numbers would be unusable.
  if ($colNow -eq $collectorStartHash) {
    Write-Output ('G1b the collector under test is unchanged for the whole run: OK (' + $colNow.Substring(0, 16) + '...)')
  } else {
    Write-Output ('G1b the collector under test CHANGED during the run: ' + $collectorStartHash.Substring(0, 16) + '... -> ' + $colNow.Substring(0, 16) + '...')
    $nFail++
    [void]$failDetail.Add('G1b :: collector changed mid-run :: ' + $collectorStartHash + ' -> ' + $colNow)
  }
  # G1c: everything else. This suite writes only under %TEMP%, so a change here belongs to
  # whatever else is editing the checkout; it is reported (never hidden) but must not fail a
  # run that is otherwise proven read-only. The static proof that all write verbs target
  # %TEMP% lives in tests/cases/filescan-no-repo-write-paths/.
  $other = New-Object System.Collections.ArrayList
  foreach ($k in @($created.ToArray()) + @($deleted.ToArray()) + @($modified.ToArray())) { if ($k -notlike '*\tests\*') { [void]$other.Add($k) } }
  if ($other.Count -eq 0) {
    Write-Output 'G1c no file outside tests/ changed during the run: OK'
  } else {
    Write-Output ('G1c NOTE - files outside tests/ changed while the suite ran (concurrent editor, not this suite): ' + (($other.ToArray()) -join ', '))
  }
  Write-Output ('tested collector sha256: ' + $collectorStartHash)
  $wildAfter = Get-WildcardListenerMap
  if ($null -eq $wildBefore -or $null -eq $wildAfter) { Write-Output 'G2  wildcard listener set: NOT MEASURABLE (netstat unavailable)' }
  else {
    $newWild = New-Object System.Collections.ArrayList
    $goneWild = New-Object System.Collections.ArrayList
    foreach ($k in $wildAfter.Keys) {
      if (-not $wildBefore.ContainsKey($k)) { [void]$newWild.Add($k + ' (pid ' + $wildAfter[$k] + ' ' + (Get-ProcImageName $wildAfter[$k]) + ')') }
    }
    foreach ($k in $wildBefore.Keys) { if (-not $wildAfter.ContainsKey($k)) { [void]$goneWild.Add($k) } }
    # Only a listener owned by a process the suite could have spawned counts as a failure.
    # Anything else (another application starting during the run) is reported, not blamed:
    # the machine is shared and the suite must not fail because of unrelated software.
    $ours = @($newWild.ToArray() | Where-Object { $_ -match '(?i)\(pid \d+ (powershell|pwsh|conhost|cmd|dsh|node|wscript|cscript)' })
    if ($ours.Count -gt 0) {
      Write-Output ('G2  NEW wildcard listener owned by the suite: ' + ($ours -join ', '))
      $nFail++
      [void]$failDetail.Add('G2 :: wildcard listener opened by the suite :: ' + ($ours -join ', '))
    } elseif ($newWild.Count -eq 0 -and $goneWild.Count -eq 0) {
      Write-Output ('G2  wildcard listener set unchanged: OK (' + $wildAfter.Count + ' listeners)')
    } else {
      Write-Output ('G2  no listener attributable to the suite: OK; unrelated machine activity +[' + (($newWild.ToArray()) -join ', ') + '] -[' + (($goneWild.ToArray()) -join ', ') + ']')
    }
  }
  $left = @()
  if (-not $KeepTemp) {
    if (Test-Path -LiteralPath $script:TempBase) { Remove-Item -LiteralPath $script:TempBase -Recurse -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $script:TempBase) { $left = @(Get-ChildItem -LiteralPath $script:TempBase -Recurse -Force) }
  }
  if ($left.Count -eq 0) { Write-Output 'G3  temp dirs removed (no leftovers): OK' }
  else { Write-Output ('G3  temp leftovers: ' + $left.Count + ' entries under ' + $script:TempBase) ; $nFail++ }
} finally {
  Restore-CaseEnvironment
}

Write-Output ''
Write-Output ('cases run     : ' + $nRun)
Write-Output ('passed        : ' + $nPass)
Write-Output ('failed        : ' + $nFail)
Write-Output ('xfail held    : ' + $nXfail + ' (known gaps that still exist - they do not fail the suite)')
Write-Output ('xpass         : ' + $nXpass + ' (a known gap disappeared - the suite fails until the marker is flipped)')
Write-Output ('skipped       : ' + $script:NSkipped + ' (assertions whose target is deliberately unpublished and declares ifMissing=skip; a skip never fails the run)')
if ($nFail -eq 0) { Write-Output 'ALL PASS'; exit 0 }
Write-Output 'FAILURES:'
foreach ($f in $failDetail) { Write-Output ('  - ' + $f) }
exit 1
