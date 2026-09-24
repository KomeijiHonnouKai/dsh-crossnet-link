<#
  remote-tailnet-guard - read-only preflight for the PERSISTENT plugin package (tasks t43 + t46).
  LAST UPDATED : 2026-09-25 (v0.3: the standalone settings-section seat is removed; the plugin is a
  standard plugins-page card only - the single-card assertions and the -SelfTest fault-injection proof).

  WHAT IT PROVES (all read-only, nothing is executed and nothing is written anywhere by a normal
  run - the only writer is -SelfTest, and it writes inside %TEMP% exclusively):
    (1) plugin/package.json parses as JSON, and plugin/cordis.patch.yml has the expected minimal
        structure. NOTE, measured: Windows PowerShell 5.1 ships no YAML engine, so the patch file is
        read by a documented minimal structural reader (one "- insert:" block, exactly one row of
        simple "key: value" pairs, no tabs). It is NOT a general YAML parser - the general parser is
        the Loader itself, which parses this file when a profile boots it.
    (2) every path package.json points at exists: `main`, `exports['.']`, `exports['./client']`,
        `exports['./package.json']` and `dsh.bundle.patch`.
    (3) module hygiene for the three JavaScript files:
          * the two ESM halves contain no `require(` call at all;
          * the browser bundle registers itself as the package row and calls `require` only for the
            platform seed `react` (every other specifier is a failure);
          * no JSX (elements are built with React.createElement), no TypeScript-only syntax;
          * ASCII only, no UTF-8 BOM, LF line endings;
          * the marked SHARED BODY region is byte-identical in lib/client.js and lib/client/index.js,
            so the runtime bundle cannot silently drift away from the ESM source;
          * if `node` happens to be on PATH, `node --check` must accept all three files. When node is
            absent this is printed as SKIP (never silently dropped) and does not change the verdict.
    (4) the inserted row is self-consistent and SAFE: exactly one row, `id` and `name` both equal
        package.json `name`, and `disabled: true` (the deliberate safety default).
    (5) the single card seat: `settings.plugin.item` is registered exactly once in BOTH client files
        (key == the settings namespace the host half declares == package name), and NO `settings.section`
        seat is registered anywhere. The host half must declare that namespace through
        a GUARDED runtime lookup and must not carry a static schema-library import (a static import
        that cannot resolve would break the whole host half on a `link:` install).
    (6) the inventory: which files an install/enable would touch, what to back up first, and the
        user-layer override row that turns the plugin on.

  EXIT CODES (contract):
    0 = every BLOCKING check passed. Registered SKIPs (e.g. the 3 `node --check` lines on a machine
        without node on PATH) never change the code - a skip is printed, never silent.
    1 = no blocking finding, but at least one ADVISORY finding (today: only docs/install/
        plugin-package.md missing). The plugin can still load; the deliverable is incomplete.
    2 = at least one BLOCKING finding, or a state the preflight cannot judge (unreadable or
        unparsable input, an unexpected exception): the entry is missing, an `exports` target points
        nowhere, the insert row's id/name is not the package name, the shared body drifted, the row
        was enabled, a seat registration disappeared, and so on. Nothing may be enabled from here.
    2 is also what a wrong root / missing plugin directory / unknown -Profile returns.

  -SelfTest injects every one of those faults into a throw-away copy under %TEMP% and asserts the
  exit code each one produces (this is the positive control for the table above). It exits 0 when
  every injected fault produced its expected code, and 2 otherwise.

  It never touches a user profile: without -Profile it only prints <DSH_HOME> placeholders; with
  -Profile <name> it still only READS (Test-Path) to say whether each target exists.
#>
param(
  [string]$RepoRoot = '',
  [string]$Profile = '',
  [switch]$Json,
  [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'

# An unexpected exception means nothing could be judged: report it as a blocking finding with the
# contract's own code. Without this trap a throw would surface as an arbitrary process code.
trap {
  Write-Host '[FAIL] preflight.exception           the preflight itself threw before it could judge anything'
  Write-Host ('       detail: ' + [string]$_.Exception.Message)
  Write-Host 'exit code: 2  (blocking: nothing was proven)'
  exit 2
}

$script:Checks = New-Object System.Collections.ArrayList
$script:Skips = New-Object System.Collections.ArrayList

function Add-Check {
  param([string]$Id, [string]$Rule, $Expected, $Actual, [bool]$Ok, [string]$Severity = 'blocking')
  [void]$script:Checks.Add([pscustomobject]@{
    Id = $Id; Rule = $Rule; Expected = ([string]$Expected); Actual = ([string]$Actual); Ok = $Ok; Severity = $Severity
  })
}

function Add-Equal {
  param([string]$Id, [string]$Rule, $Expected, $Actual, [string]$Severity = 'blocking')
  Add-Check -Id $Id -Rule $Rule -Expected $Expected -Actual $Actual -Ok (([string]$Expected) -ceq ([string]$Actual)) -Severity $Severity
}

function Add-Skip {
  param([string]$Id, [string]$Rule, [string]$Detail)
  [void]$script:Skips.Add([pscustomobject]@{ Id = $Id; Rule = $Rule; Detail = $Detail })
}

function Read-Text {
  param([string]$Path)
  return [IO.File]::ReadAllText($Path, (New-Object Text.UTF8Encoding($false)))
}

# The ONLY writer in this script. It is reached exclusively from -SelfTest, whose roots all live
# under %TEMP%; a normal preflight run never calls it.
function Write-Text {
  param([string]$Path, [string]$Text)
  [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($false)))
}

function Test-AsciiOnly {
  param([string]$Path)
  $bytes = [IO.File]::ReadAllBytes($Path)
  $bad = 0
  foreach ($b in $bytes) { if ($b -gt 0x7F) { $bad++ } }
  return $bad
}

function Test-HasBom {
  param([string]$Path)
  $bytes = [IO.File]::ReadAllBytes($Path)
  return (($bytes.Length -ge 3) -and ($bytes[0] -eq 0xEF) -and ($bytes[1] -eq 0xBB) -and ($bytes[2] -eq 0xBF))
}

function Get-MatchCount {
  param([string]$Text, [string]$Pattern)
  return ([regex]::Matches($Text, $Pattern)).Count
}

function Get-SharedRegion {
  param([string]$Text, [string]$Begin, [string]$End)
  $b = $Text.IndexOf($Begin)
  $e = $Text.IndexOf($End)
  if ($b -lt 0 -or $e -lt 0 -or $e -lt $b) { return $null }
  return $Text.Substring($b, ($e - $b) + $End.Length)
}

function Get-Sha256 {
  param([string]$Text)
  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-', '')
  } finally {
    $sha.Dispose()
  }
}

function Test-TsSyntax {
  param([string]$Text)
  $patterns = @(
    '\binterface\s+[A-Za-z_$]',
    '\benum\s+[A-Za-z_$]',
    '\btype\s+[A-Za-z_$][\w$]*\s*=',
    '[A-Za-z_$][\w$]*\??\s*:\s*(string|number|boolean|void|any|unknown)\b',
    '(?m)^\s*(public|private|readonly)\s+'
  )
  $names = @('interface', 'enum', 'type alias', 'type annotation', 'member modifier')
  $hits = New-Object System.Collections.ArrayList
  for ($i = 0; $i -lt $patterns.Count; $i++) {
    if ((Get-MatchCount -Text $Text -Pattern $patterns[$i]) -gt 0) { [void]$hits.Add($names[$i]) }
  }
  return $hits
}

# ---------------------------------------------------------------------------
# minimal structural reader for a loader patch list (see the header for its limits)
# ---------------------------------------------------------------------------
function Read-PatchShape {
  param([string]$Text)
  $res = [pscustomobject]@{
    Ok = $true; Reason = ''; InsertBlocks = 0; Rows = (New-Object System.Collections.ArrayList)
  }
  if ($Text.IndexOf([char]9) -ge 0) {
    $res.Ok = $false
    $res.Reason = 'a TAB character is used for indentation'
    return $res
  }
  $lines = $Text -split "`r?`n"
  $inInsert = $false
  $row = $null
  for ($i = 0; $i -lt $lines.Count; $i++) {
    $raw = $lines[$i]
    $trim = $raw.Trim()
    if ($trim -eq '' -or $trim.StartsWith('#')) { continue }
    $indent = $raw.Length - $raw.TrimStart().Length
    if ($indent -eq 0) {
      if ($trim -ne '- insert:') {
        $res.Ok = $false
        $res.Reason = 'line ' + ($i + 1) + ' is a top-level entry that is not "- insert:": ' + $trim
        return $res
      }
      $res.InsertBlocks = $res.InsertBlocks + 1
      $inInsert = $true
      $row = $null
      continue
    }
    if (-not $inInsert) {
      $res.Ok = $false
      $res.Reason = 'line ' + ($i + 1) + ' is indented but no "- insert:" block is open'
      return $res
    }
    $pairText = $trim
    if ($trim.StartsWith('- ')) {
      $pairText = $trim.Substring(2)
      $row = @{ Line = ($i + 1); Keys = (New-Object System.Collections.ArrayList) }
      [void]$res.Rows.Add($row)
    } elseif ($null -eq $row) {
      $res.Ok = $false
      $res.Reason = 'line ' + ($i + 1) + ' is a key: value pair but the row has not started yet'
      return $res
    }
    if ($pairText -notmatch '^[A-Za-z_][A-Za-z0-9_-]*\s*:') {
      $res.Ok = $false
      $res.Reason = 'line ' + ($i + 1) + ' is neither a row nor a simple "key: value" pair: ' + $pairText
      return $res
    }
    $parts = $pairText -split ':', 2
    $key = $parts[0].Trim()
    $value = ''
    if ($parts.Count -gt 1) { $value = $parts[1].Trim() }
    if ($value.Length -ge 2) {
      $first = $value.Substring(0, 1)
      $last = $value.Substring($value.Length - 1, 1)
      if (($first -eq '"' -and $last -eq '"') -or ($first -eq "'" -and $last -eq "'")) {
        $value = $value.Substring(1, $value.Length - 2)
      }
    }
    [void]$row.Keys.Add([pscustomobject]@{ Key = $key; Value = $value; Line = ($i + 1) })
  }
  return $res
}

function Get-RowValue {
  param($Row, [string]$Key)
  foreach ($k in $Row.Keys) { if ($k.Key -ceq $Key) { return $k.Value } }
  return $null
}

# ---------------------------------------------------------------------------
# 0. resolve roots and preconditions
# ---------------------------------------------------------------------------
if ($RepoRoot -eq '') {
  $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
  $RepoRoot = Split-Path -Parent $scriptDir
}
if (-not (Test-Path -LiteralPath $RepoRoot)) {
  Write-Host ('plugin-preflight: repository root not found: ' + $RepoRoot)
  exit 2
}
$pluginDir = Join-Path $RepoRoot 'plugin'
if (-not (Test-Path -LiteralPath $pluginDir)) {
  Write-Host ('plugin-preflight: no plugin directory under ' + $RepoRoot)
  exit 2
}

$dshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE '.dsh' }
$profileDir = ''
if ($Profile -ne '') {
  $profileDir = Join-Path (Join-Path $dshHome 'profiles') $Profile
  if (-not (Test-Path -LiteralPath $profileDir)) {
    Write-Host ('plugin-preflight: profile not found: ' + $profileDir)
    exit 2
  }
}

$pkgPath = Join-Path $pluginDir 'package.json'
$patchPath = Join-Path $pluginDir 'cordis.patch.yml'
$hostPath = Join-Path $pluginDir 'lib\index.js'
$bundlePath = Join-Path $pluginDir 'lib\client.js'
$sourcePath = Join-Path $pluginDir 'lib\client\index.js'
$docPath = Join-Path $RepoRoot 'docs\install\plugin-package.md'

$SHARED_BEGIN = '// ==== SHARED BODY BEGIN'
$SHARED_END = '// ==== SHARED BODY END ===='
$SEED_WORDS = @('react', 'react/jsx-runtime', 'react-dom', 'react-dom/client', '@deepseek-ai/cordis',
  '@deepseek-ai/dsh-client-store', '@deepseek-ai/dsh-client-ui-slots',
  '@deepseek-ai/dsh-client-ui-primitives', '@deepseek-ai/dsh-client-ui-dockkit')

# ---------------------------------------------------------------------------
# -SelfTest: inject every documented fault into a throw-away copy under %TEMP% and assert the exit
# code each one produces. This is the positive control for the exit-code contract above and in
# docs/install/plugin-package.md. It writes ONLY inside its own %TEMP% tree and removes it again.
# ---------------------------------------------------------------------------
function Invoke-PreflightSelfTest {
  param([string]$ScriptPath, [string]$SourceRepo)

  $cases = @(
    [pscustomobject]@{ Id = 'baseline';          Expect = 0; Mutate = 'none' },
    [pscustomobject]@{ Id = 'entry-missing';     Expect = 2; Mutate = 'hide-host-half' },
    [pscustomobject]@{ Id = 'row-id-mismatch';   Expect = 2; Mutate = 'break-row-id' },
    [pscustomobject]@{ Id = 'row-enabled';       Expect = 2; Mutate = 'enable-row' },
    [pscustomobject]@{ Id = 'client-twin-drift'; Expect = 2; Mutate = 'break-shared-body' },
    [pscustomobject]@{ Id = 'card-seat-missing'; Expect = 2; Mutate = 'drop-card-seat' },
    [pscustomobject]@{ Id = 'doc-missing';       Expect = 1; Mutate = 'hide-doc' }
  )

  $tempBase = Join-Path $env:TEMP ('rtg-preflight-selftest-' + [string]$PID)
  Write-Host 'plugin-preflight -SelfTest: injected fault -> expected exit code'
  Write-Host ('temp root : ' + $tempBase)
  Write-Host ''
  if (Test-Path -LiteralPath $tempBase) { Remove-Item -LiteralPath $tempBase -Recurse -Force }
  [void](New-Item -ItemType Directory -Path $tempBase -Force)

  $mismatch = 0
  try {
    foreach ($case in $cases) {
      $root = Join-Path $tempBase $case.Id
      [void](New-Item -ItemType Directory -Path $root -Force)
      Copy-Item -LiteralPath (Join-Path $SourceRepo 'plugin') -Destination (Join-Path $root 'plugin') -Recurse -Force
      $docSource = Join-Path $SourceRepo 'docs\install\plugin-package.md'
      if (Test-Path -LiteralPath $docSource) {
        [void](New-Item -ItemType Directory -Path (Join-Path $root 'docs\install') -Force)
        Copy-Item -LiteralPath $docSource -Destination (Join-Path $root 'docs\install\plugin-package.md') -Force
      }

      $hostCopy = Join-Path $root 'plugin\lib\index.js'
      $srcCopy = Join-Path $root 'plugin\lib\client\index.js'
      $bundCopy = Join-Path $root 'plugin\lib\client.js'
      $patchCopy = Join-Path $root 'plugin\cordis.patch.yml'

      if ($case.Mutate -eq 'hide-host-half') { Remove-Item -LiteralPath $hostCopy -Force }
      if ($case.Mutate -eq 'break-row-id') {
        Write-Text -Path $patchCopy -Text ((Read-Text -Path $patchCopy) -replace '- id: remote-tailnet-guard', '- id: remote-tailnet-guard-WRONG')
      }
      if ($case.Mutate -eq 'enable-row') {
        Write-Text -Path $patchCopy -Text ((Read-Text -Path $patchCopy) -replace 'disabled: true', 'disabled: false')
      }
      if ($case.Mutate -eq 'break-shared-body') {
        Write-Text -Path $srcCopy -Text ((Read-Text -Path $srcCopy) -replace "const SETTINGS_NS = 'remote-tailnet-guard';", "const SETTINGS_NS = 'remote-tailnet-guard-DRIFTED';")
      }
      if ($case.Mutate -eq 'drop-card-seat') {
        Write-Text -Path $bundCopy -Text ((Read-Text -Path $bundCopy) -replace "'settings\.plugin\.item'", "'settings.plugin.item.dropped'")
        Write-Text -Path $srcCopy -Text ((Read-Text -Path $srcCopy) -replace "'settings\.plugin\.item'", "'settings.plugin.item.dropped'")
      }
      if ($case.Mutate -eq 'hide-doc') { Remove-Item -LiteralPath (Join-Path $root 'docs\install\plugin-package.md') -Force }

      $child = & powershell -NoProfile -ExecutionPolicy Bypass -File $ScriptPath -RepoRoot $root 2>&1
      $actual = $LASTEXITCODE
      $findings = @($child | Where-Object { $_ -match '^\[(FAIL|WARN)\]' } | ForEach-Object { ((([string]$_).Trim()) -replace '^\[(FAIL|WARN)\]\s+', '' -split '\s+')[0] })
      $ok = ($actual -eq $case.Expect)
      if (-not $ok) { $mismatch = $mismatch + 1 }
      $mark = if ($ok) { '[ok]  ' } else { '[FAIL]' }
      Write-Host ($mark + ' ' + $case.Id.PadRight(20) + ' expect ' + $case.Expect + '  actual ' + $actual +
        '  findings: ' + $(if ($findings.Count -gt 0) { $findings -join ', ' } else { '(none)' }))
    }
  } finally {
    if (Test-Path -LiteralPath $tempBase) { Remove-Item -LiteralPath $tempBase -Recurse -Force -ErrorAction SilentlyContinue }
  }

  Write-Host ''
  Write-Host ('self-test: ' + $cases.Count + ' cases  matched: ' + ($cases.Count - $mismatch) + '  mismatched: ' + $mismatch)
  if ($mismatch -gt 0) { return 2 }
  return 0
}

if ($SelfTest) {
  exit (Invoke-PreflightSelfTest -ScriptPath $PSCommandPath -SourceRepo $RepoRoot)
}

Write-Host 'remote-tailnet-guard - persistent plugin preflight (read-only)'
Write-Host ('repo root : ' + $RepoRoot)
Write-Host ('plugin dir: ' + $pluginDir)
Write-Host ('profile   : ' + $(if ($Profile -eq '') { '(not selected; paths are printed as placeholders)' } else { $profileDir }))
Write-Host ''

# ---------------------------------------------------------------------------
# (1) parse
# ---------------------------------------------------------------------------
$pkg = $null
if (-not (Test-Path -LiteralPath $pkgPath)) {
  Add-Check -Id 'pkg.file' -Rule 'plugin/package.json exists' -Expected 'exists' -Actual 'missing' -Ok $false
} else {
  Add-Check -Id 'pkg.file' -Rule 'plugin/package.json exists' -Expected 'exists' -Actual 'exists' -Ok $true
  try {
    $pkgText = Read-Text -Path $pkgPath
    $pkg = ConvertFrom-Json -InputObject $pkgText
    Add-Check -Id 'pkg.parse' -Rule 'plugin/package.json parses as JSON' -Expected 'parsed' -Actual 'parsed' -Ok $true
  } catch {
    Add-Check -Id 'pkg.parse' -Rule 'plugin/package.json parses as JSON' -Expected 'parsed' -Actual $_.Exception.Message -Ok $false
  }
}

$shape = $null
if (-not (Test-Path -LiteralPath $patchPath)) {
  Add-Check -Id 'patch.file' -Rule 'plugin/cordis.patch.yml exists' -Expected 'exists' -Actual 'missing' -Ok $false
} else {
  Add-Check -Id 'patch.file' -Rule 'plugin/cordis.patch.yml exists' -Expected 'exists' -Actual 'exists' -Ok $true
  $shape = Read-PatchShape -Text (Read-Text -Path $patchPath)
  Add-Check -Id 'patch.structure' -Rule 'cordis.patch.yml has the expected minimal structure' -Expected 'parsed' -Actual $(if ($shape.Ok) { 'parsed' } else { $shape.Reason }) -Ok $shape.Ok
}

# ---------------------------------------------------------------------------
# (2) the paths package.json declares must exist
# ---------------------------------------------------------------------------
function Resolve-DeclaredPath {
  param([string]$Relative)
  if ([string]::IsNullOrEmpty($Relative)) { return '' }
  return (Join-Path $pluginDir ($Relative -replace '/', '\'))
}

if ($null -ne $pkg) {
  $declared = New-Object System.Collections.ArrayList
  if ($pkg.main) { [void]$declared.Add([pscustomobject]@{ Key = 'main'; Rel = [string]$pkg.main }) }
  if ($pkg.exports) {
    if ($pkg.exports.'.') { [void]$declared.Add([pscustomobject]@{ Key = "exports['.']"; Rel = [string]$pkg.exports.'.' }) }
    if ($pkg.exports.'./client') { [void]$declared.Add([pscustomobject]@{ Key = "exports['./client']"; Rel = [string]$pkg.exports.'./client' }) }
    if ($pkg.exports.'./package.json') { [void]$declared.Add([pscustomobject]@{ Key = "exports['./package.json']"; Rel = [string]$pkg.exports.'./package.json' }) }
  }
  if ($pkg.dsh -and $pkg.dsh.bundle -and $pkg.dsh.bundle.patch) {
    [void]$declared.Add([pscustomobject]@{ Key = 'dsh.bundle.patch'; Rel = [string]$pkg.dsh.bundle.patch })
  }
  foreach ($entry in $declared) {
    $full = Resolve-DeclaredPath -Relative $entry.Rel
    $ok = ($full -ne '') -and (Test-Path -LiteralPath $full)
    Add-Check -Id ('path.' + $entry.Key) -Rule ($entry.Key + ' -> ' + $entry.Rel + ' exists') -Expected 'exists' -Actual $(if ($ok) { 'exists' } else { 'missing' }) -Ok $ok
  }
  Add-Check -Id 'path.client-source' -Rule 'lib/client/index.js (ESM source of the same half) exists' -Expected 'exists' -Actual $(if (Test-Path -LiteralPath $sourcePath) { 'exists' } else { 'missing' }) -Ok (Test-Path -LiteralPath $sourcePath)
  Add-Check -Id 'doc.plugin-package' -Rule 'docs/install/plugin-package.md exists (advisory: the package loads without it)' -Expected 'exists' -Actual $(if (Test-Path -LiteralPath $docPath) { 'exists' } else { 'missing' }) -Ok (Test-Path -LiteralPath $docPath) -Severity advisory
}

# ---------------------------------------------------------------------------
# (3) module hygiene
# ---------------------------------------------------------------------------
foreach ($pair in @(
  [pscustomobject]@{ Id = 'lib/index.js'; Path = $hostPath; Kind = 'esm' },
  [pscustomobject]@{ Id = 'lib/client/index.js'; Path = $sourcePath; Kind = 'esm' },
  [pscustomobject]@{ Id = 'lib/client.js'; Path = $bundlePath; Kind = 'bundle' }
)) {
  $name = $pair.Id
  $path = $pair.Path
  if (-not (Test-Path -LiteralPath $path)) {
    Add-Check -Id ('js.' + $name) -Rule ($name + ' exists') -Expected 'exists' -Actual 'missing' -Ok $false
    continue
  }
  Add-Check -Id ('js.' + $name) -Rule ($name + ' exists') -Expected 'exists' -Actual 'exists' -Ok $true
  $text = Read-Text -Path $path
  $bom = Test-HasBom -Path $path
  Add-Check -Id ('js.' + $name + '.bom') -Rule ($name + ' has no UTF-8 BOM') -Expected 'False' -Actual ([string]$bom) -Ok (-not $bom)
  $nonAscii = Test-AsciiOnly -Path $path
  Add-Equal -Id ('js.' + $name + '.ascii') -Rule ($name + ' non-ASCII byte count') -Expected 0 -Actual $nonAscii
  $crlf = $text.IndexOf("`r`n") -ge 0
  Add-Check -Id ('js.' + $name + '.lf') -Rule ($name + ' uses LF line endings only') -Expected 'False' -Actual ([string]$crlf) -Ok (-not $crlf)
  Add-Equal -Id ('js.' + $name + '.jsx-close') -Rule ($name + ' JSX closing tags (elements are built with React.createElement)') -Expected 0 -Actual (Get-MatchCount -Text $text -Pattern '</[A-Za-z]')
  Add-Equal -Id ('js.' + $name + '.jsx-return') -Rule ($name + ' JSX returned from a function body') -Expected 0 -Actual (Get-MatchCount -Text $text -Pattern 'return\s*\(\s*<[A-Za-z]')
  $ts = Test-TsSyntax -Text $text
  Add-Equal -Id ('js.' + $name + '.ts') -Rule ($name + ' TypeScript-only syntax markers (' + ($ts -join ',') + ')') -Expected 0 -Actual $ts.Count
  $requires = Get-MatchCount -Text $text -Pattern 'require\s*\('
  if ($pair.Kind -eq 'esm') {
    Add-Equal -Id ('js.' + $name + '.require') -Rule ($name + ' is a real ESM module: require( calls') -Expected 0 -Actual $requires
    Add-Check -Id ('js.' + $name + '.export') -Rule ($name + ' exports the plugin face (apply)') -Expected 'True' -Actual ([string]($text -match '(?m)^export\s')) -Ok ($text -match '(?m)^export\s')
  } else {
    $registration = 'window.__ModuleLoader__.load({ id: "' + $pkg.name + '"'
    $registered = $text.IndexOf($registration, [StringComparison]::Ordinal) -ge 0
    Add-Check -Id ('js.' + $name + '.register') -Rule ('bundle registers itself as row "' + $pkg.name + '" via window.__ModuleLoader__.load') -Expected 'True' -Actual ([string]$registered) -Ok $registered
    $specifiers = New-Object System.Collections.ArrayList
    foreach ($m in [regex]::Matches($text, 'require\(\s*["'']([^"'']+)["'']\s*\)')) { [void]$specifiers.Add($m.Groups[1].Value) }
    Add-Equal -Id ('js.' + $name + '.require-count') -Rule 'bundle require( call count' -Expected $specifiers.Count -Actual $requires
    $foreign = @()
    foreach ($s in $specifiers) { if ($SEED_WORDS -notcontains $s) { $foreign += $s } }
    Add-Equal -Id ('js.' + $name + '.require-seeds') -Rule 'bundle requires platform seeds only (react, ...)' -Expected 0 -Actual $foreign.Count
    Add-Equal -Id ('js.' + $name + '.no-esm-keyword') -Rule 'bundle is a classic script: import/export statements' -Expected 0 -Actual (Get-MatchCount -Text $text -Pattern '(?m)^\s*(import|export)\s')
  }
  $nodeExe = Get-Command node -ErrorAction SilentlyContinue
  if ($null -eq $nodeExe) {
    Add-Skip -Id ('js.' + $name + '.node-check') -Rule 'node --check accepts the file' -Detail 'node is not on PATH on this machine'
  } else {
    $nodeOut = & $nodeExe.Source --check $path 2>&1
    $nodeCode = $LASTEXITCODE
    Add-Check -Id ('js.' + $name + '.node-check') -Rule 'node --check accepts the file' -Expected 'exit 0' -Actual ('exit ' + $nodeCode + ' ' + (@($nodeOut) -join ' ')) -Ok ($nodeCode -eq 0)
  }
}

if ((Test-Path -LiteralPath $bundlePath) -and (Test-Path -LiteralPath $sourcePath)) {
  $bundleText = Read-Text -Path $bundlePath
  $sourceText = Read-Text -Path $sourcePath
  $bundleRegion = Get-SharedRegion -Text $bundleText -Begin $SHARED_BEGIN -End $SHARED_END
  $sourceRegion = Get-SharedRegion -Text $sourceText -Begin $SHARED_BEGIN -End $SHARED_END
  $same = ($null -ne $bundleRegion) -and ($null -ne $sourceRegion) -and ($bundleRegion -ceq $sourceRegion)
  $detail = 'markers missing'
  if ($same) { $detail = 'sha256 ' + (Get-Sha256 -Text $bundleRegion).Substring(0, 16) }
  Add-Check -Id 'js.shared-body' -Rule 'the marked SHARED BODY region is byte-identical in lib/client.js and lib/client/index.js' -Expected 'identical' -Actual $detail -Ok $same
}

# ---------------------------------------------------------------------------
# (3b) the single card seat in BOTH client files (no settings.section), plus the host-side namespace it needs
# ---------------------------------------------------------------------------
function Get-SeatReport {
  param([string]$Text)
  $sectionCount = Get-MatchCount -Text $Text -Pattern "ctx\.slots\.inject\('settings\.section'"
  $cardCount = Get-MatchCount -Text $Text -Pattern "ctx\.slots\.inject\('settings\.plugin\.item'"
  $sectionId = Get-MatchCount -Text $Text -Pattern "id: SECTION_ID"
  $cardKey = Get-MatchCount -Text $Text -Pattern "key: SETTINGS_NS"
  return [pscustomobject]@{ Section = $sectionCount; Card = $cardCount; SectionId = $sectionId; CardKey = $cardKey }
}

if ((Test-Path -LiteralPath $bundlePath) -and (Test-Path -LiteralPath $sourcePath)) {
  foreach ($seatFile in @(
    [pscustomobject]@{ Id = 'lib/client.js'; Text = (Read-Text -Path $bundlePath) },
    [pscustomobject]@{ Id = 'lib/client/index.js'; Text = (Read-Text -Path $sourcePath) }
  )) {
    $report = Get-SeatReport -Text $seatFile.Text
    Add-Equal -Id ('seat.' + $seatFile.Id + '.section') -Rule ($seatFile.Id + ' registers NO standalone settings-page seat (settings.section) - the plugin is a standard plugins-page card only') -Expected 0 -Actual $report.Section
    Add-Equal -Id ('seat.' + $seatFile.Id + '.card') -Rule ($seatFile.Id + ' registers the plugins-page card seat (settings.plugin.item) exactly once') -Expected 1 -Actual $report.Card
    Add-Equal -Id ('seat.' + $seatFile.Id + '.section-id') -Rule ($seatFile.Id + ' leaves no SECTION_ID seat id (the section seat was removed)') -Expected 0 -Actual $report.SectionId
    Add-Equal -Id ('seat.' + $seatFile.Id + '.card-key') -Rule ($seatFile.Id + ' keys the card by SETTINGS_NS (== the host settings namespace)') -Expected 1 -Actual $report.CardKey
    $nsLiteral = "const SETTINGS_NS = '" + [string]$pkg.name + "';"
    $hasLiteral = $seatFile.Text.IndexOf($nsLiteral, [StringComparison]::Ordinal) -ge 0
    Add-Check -Id ('seat.' + $seatFile.Id + '.card-key-ns') -Rule ($seatFile.Id + ' declares ' + $nsLiteral + ' (card key == package name == host namespace)') -Expected 'True' -Actual ([string]$hasLiteral) -Ok $hasLiteral
  }
}

if (Test-Path -LiteralPath $hostPath) {
  $hostText = Read-Text -Path $hostPath
  $staticSchemaImport = Get-MatchCount -Text $hostText -Pattern '(?m)^\s*import\s+[^\r\n]*schemastery'
  Add-Equal -Id 'ns.static-import' -Rule 'host half carries NO static schema-library import (a failed static import would kill the whole host half on a link: install)' -Expected 0 -Actual $staticSchemaImport
  $nsRegistration = Get-MatchCount -Text $hostText -Pattern 'settings\.register\(SETTINGS_NS'
  Add-Equal -Id 'ns.register' -Rule 'host half declares the settings namespace the card is keyed by (settings.register(SETTINGS_NS, schema, ...))' -Expected 1 -Actual $nsRegistration
  $nsLiteralHost = "const SETTINGS_NS = '" + [string]$pkg.name + "';"
  $hostLiteral = $hostText.IndexOf($nsLiteralHost, [StringComparison]::Ordinal) -ge 0
  Add-Check -Id 'ns.literal' -Rule ('host half declares ' + $nsLiteralHost) -Expected 'True' -Actual ([string]$hostLiteral) -Ok $hostLiteral
  $guarded = (Get-MatchCount -Text $hostText -Pattern 'await import\(specifier\)') -ge 1
  Add-Check -Id 'ns.guarded-import' -Rule 'the schema library is resolved through a guarded dynamic import (await import(specifier) inside try/catch)' -Expected 'True' -Actual ([string]$guarded) -Ok $guarded
  $emptySchema = Get-MatchCount -Text $hostText -Pattern 'schemaFactory\.object\(\{\}\)'
  Add-Equal -Id 'ns.empty-schema' -Rule 'the namespace schema has no fields (nothing about this plugin becomes configurable)' -Expected 1 -Actual $emptySchema
}

# ---------------------------------------------------------------------------
# (4) the inserted row: one row, id and name equal the package name, disabled
# ---------------------------------------------------------------------------
if ($null -ne $shape -and $shape.Ok -and $null -ne $pkg) {
  Add-Equal -Id 'row.insert-blocks' -Rule 'cordis.patch.yml has exactly one "- insert:" block' -Expected 1 -Actual $shape.InsertBlocks
  Add-Equal -Id 'row.count' -Rule 'the insert block holds exactly one row' -Expected 1 -Actual $shape.Rows.Count
  if ($shape.Rows.Count -eq 1) {
    $row = $shape.Rows[0]
    $allowed = @('id', 'name', 'disabled', 'config')
    $unknown = @()
    foreach ($k in $row.Keys) { if ($allowed -notcontains $k.Key) { $unknown += $k.Key } }
    Add-Equal -Id 'row.keys' -Rule 'the row uses only id/name/disabled/config' -Expected 0 -Actual $unknown.Count
    Add-Equal -Id 'row.id' -Rule 'row id equals package.json name' -Expected ([string]$pkg.name) -Actual ([string](Get-RowValue -Row $row -Key 'id'))
    Add-Equal -Id 'row.name' -Rule 'row name equals package.json name (the loader specifier)' -Expected ([string]$pkg.name) -Actual ([string](Get-RowValue -Row $row -Key 'name'))
    Add-Equal -Id 'row.disabled' -Rule 'the row ships disabled on purpose (nothing can load before you say so)' -Expected 'true' -Actual ([string](Get-RowValue -Row $row -Key 'disabled'))
  }
  Add-Equal -Id 'pkg.name' -Rule 'package.json name' -Expected 'remote-tailnet-guard' -Actual ([string]$pkg.name)
  Add-Equal -Id 'pkg.type' -Rule 'package.json type is module' -Expected 'module' -Actual ([string]$pkg.type)
  Add-Equal -Id 'pkg.main' -Rule 'package.json main' -Expected './lib/index.js' -Actual ([string]$pkg.main)
  if ($pkg.dsh -and $pkg.dsh.client) {
    Add-Equal -Id 'pkg.client.platform' -Rule 'dsh.client.platform' -Expected 'web' -Actual ([string]$pkg.dsh.client.platform)
  } else {
    Add-Check -Id 'pkg.client.platform' -Rule 'dsh.client.platform' -Expected 'web' -Actual 'dsh.client missing' -Ok $false
  }
}

# ---------------------------------------------------------------------------
# (5) inventory: what an install/enable would touch, and what to back up
# ---------------------------------------------------------------------------
$homeLabel = '<DSH_HOME>'
if ($Profile -ne '') { $homeLabel = $dshHome }
$profLabel = if ($Profile -eq '') { '<profile>' } else { $Profile }
$targets = @(
  [pscustomobject]@{ File = (Join-Path (Join-Path $homeLabel 'profiles') (Join-Path $profLabel 'package.json')); Why = 'dependencies + dsh.profile.bundles, reconciled by "dsh plugin add"' },
  [pscustomobject]@{ File = (Join-Path (Join-Path $homeLabel 'profiles') (Join-Path $profLabel 'pnpm-lock.yaml')); Why = 'the same pnpm install' },
  [pscustomobject]@{ File = (Join-Path (Join-Path $homeLabel 'profiles') (Join-Path $profLabel 'node_modules')); Why = 'the linked package lands here' },
  [pscustomobject]@{ File = (Join-Path (Join-Path $homeLabel 'profiles') (Join-Path $profLabel 'cordis.patch.yml')); Why = 'ONLY when you add the user-layer override row that turns the plugin on' }
)

Write-Host '--- (5) inventory: an install/enable would touch these files (this script touches nothing) ---'
foreach ($t in $targets) {
  $exists = 'n/a (placeholder)'
  if ($Profile -ne '') { $exists = if (Test-Path -LiteralPath $t.File) { 'exists' } else { 'missing' } }
  Write-Host ('  ' + $t.File)
  Write-Host ('      why : ' + $t.Why)
  Write-Host ('      now : ' + $exists)
}
Write-Host '--- back up BEFORE the first change (whole files, byte copies) ---'
Write-Host ('  1. ' + (Join-Path (Join-Path $homeLabel 'profiles') (Join-Path $profLabel 'cordis.patch.yml')) + '   <- the file that leaves the GUI in recovery mode when a client entry is wrong')
Write-Host ('  2. ' + (Join-Path (Join-Path $homeLabel 'profiles') (Join-Path $profLabel 'package.json')))
Write-Host ('  3. ' + (Join-Path (Join-Path $homeLabel 'profiles') (Join-Path $profLabel 'pnpm-lock.yaml')))
Write-Host '--- the user-layer override row that enables the plugin (see docs/install/plugin-package.md) ---'
Write-Host '- id: remote-tailnet-guard'
Write-Host '  name: remote-tailnet-guard'
Write-Host '  disabled: false'
Write-Host ''

# ---------------------------------------------------------------------------
# summary + exit-code contract (see the help block at the top of this file)
# ---------------------------------------------------------------------------
$failed = @($script:Checks | Where-Object { -not $_.Ok })
$blocking = @($failed | Where-Object { $_.Severity -eq 'blocking' })
$advisory = @($failed | Where-Object { $_.Severity -eq 'advisory' })
$exitCode = if ($blocking.Count -gt 0) { 2 } elseif ($advisory.Count -gt 0) { 1 } else { 0 }

foreach ($c in $script:Checks) {
  $mark = if ($c.Ok) { '[ok]  ' } elseif ($c.Severity -eq 'advisory') { '[WARN]' } else { '[FAIL]' }
  Write-Host ($mark + ' ' + $c.Id.PadRight(28) + ' ' + $c.Rule)
  if (-not $c.Ok) {
    $impact = if ($c.Severity -eq 'advisory') { 'advisory' } else { 'blocking' }
    Write-Host ('       expected: ' + $c.Expected + '   actual: ' + $c.Actual + '   [' + $impact + ']')
  }
}
foreach ($s in $script:Skips) {
  Write-Host ('[SKIP] ' + $s.Id.PadRight(28) + ' ' + $s.Rule + ' :: ' + $s.Detail)
}
Write-Host ''
Write-Host ('checks: ' + $script:Checks.Count + '  passed: ' + ($script:Checks.Count - $failed.Count) + '  failed: ' + $failed.Count +
  ' (blocking: ' + $blocking.Count + ', advisory: ' + $advisory.Count + ')  skipped: ' + $script:Skips.Count)
Write-Host ('exit code: ' + $exitCode + '   contract: 0 = all blocking checks passed (skips allowed) | 1 = advisory findings only | 2 = blocking finding or nothing judged')
if ($blocking.Count -gt 0) { Write-Host 'nothing may be enabled from this state.' }
if ($exitCode -eq 0) { Write-Host 'the package is shaped like something a profile can load; this is NOT proof that it loaded - see docs/install/plugin-package.md section 9.' }

if ($Json) {
  $payload = [pscustomobject]@{
    verdict = $(if ($exitCode -eq 0) { 'PASS' } elseif ($exitCode -eq 1) { 'WARN' } else { 'FAIL' })
    exitCode = $exitCode
    checks = $script:Checks
    skips = $script:Skips
    failed = $failed.Count
    blocking = $blocking.Count
    advisory = $advisory.Count
    passed = ($script:Checks.Count - $failed.Count)
  }
  Write-Host (ConvertTo-Json -InputObject $payload -Depth 5 -Compress)
}

exit $exitCode
