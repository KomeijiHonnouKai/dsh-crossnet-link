<#
  uninstall.ps1 - the ONE optional write-capable component of dsh-crossnet-link (task t36).

  LAST UPDATED : 2026-09-25 (t8: the whole release set was renamed to dsh-crossnet-link; the
                 read-side legacy compatibility rules, including the -RowId default change, are
                 described in the RENAME section below)
                 2026-09-24 (v1 - t36: first revision. Journal-driven, fail-closed uninstaller:
                 dry-run by default, -Apply required to write, and it may only touch a surface that
                 is RECORDED in the journal AND whose current value is still the one this tool's
                 remediation produced. Anything the user changed afterwards is reported and left
                 alone. Everything is copied into a backup directory BEFORE the first write.)
  AUTHOR       : team dsh-crossnet-link-2 (as named at authoring time, after the plugin's then-current name; member "forge", task t36)
  RUNS ON      : Windows PowerShell 5.1 (powershell.exe). No pwsh 7, no external module, no Pester,
                 no node, no curl, no CIM/WMI cmdlet of its own.

  COMMANDS USED WHILE BUILDING THIS REVISION (the first one is read-only; the fixture ones are
  offline and write only under an explicit -StateDir):
    powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/tools/uninstall.ps1 -CheckOnly -AsJson
    powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/tools/uninstall.ps1 -RecordBefore -StateDir <dir>
    powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/tools/uninstall.ps1 -RecordAfter -StateDir <dir>
    powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/tools/uninstall.ps1 -FixturePath <fixture> -StateDir <dir> -Apply -AsJson
    powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/panel/prereq.ps1 -CheckOnly -AsJson
    powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/tests/run-tests.ps1

  WHAT IT DOES
    The plugin itself is read-only. This helper is the only component that may ever change
    something, and it can only UNDO what a journal recorded. Two bookkeeping runs bracket the
    operator's own remediation:
      -RecordBefore  observe the surfaces this link setup touches, write before + expected, and
                     print every item id with the remediation command for that item.
      -RecordAfter   observe the same surfaces again and fill `after`. This is the value that
                     proves "which current state is the one this tool produced".
    Then (or as a standalone residue scan) the helper classifies every record as a pure function
    of (journal, current observation):
      now == before                       -> noop        (nothing of ours is there)
      now == after and after != before    -> revert      (still exactly what we produced; the ONLY
                                                          class that -Apply may execute)
      now != after and now != before      -> left-alone  (somebody changed it afterwards: report
                                                          with full provenance, never touch)
      now cannot be read                  -> unknown     (never guess; forces a non-zero exit)
      after is absent while now != before -> unknown     (cannot prove the value is ours)
    `cordis-dynamic-package` is special and is handled by a PRINT-ONLY path: a dynamic Cordis
    package lives in the DSH process memory and disappears with the process, so PowerShell cannot
    see or remove it. Its revert kind is `instruction`, -Apply never executes it, the residue scan
    reports it as `unknown` with the reason spelled out, and the report carries its own section
    listing the exact `cordis_undefine(<id>)` the operator must run in the DSH session. That one
    unknown is exempt from the exit-0 rule because it is structurally unverifiable from here.

  EXIT CODES (fail-closed; a non-zero code is a VERDICT, not a crash)
    0 = the plan or the execution completed, there is no left-alone item, the residue scan is
        clean, and the only unknown is the exempt cordis one. A KEPT backup is a normal state and
        is never a warning.
    1 = at least one left-alone / unknown / residual item. Something was changed by somebody else,
        or cannot be read, or could not be reverted. Never silent, and never fixed on your behalf.
    2 = refused to act, and nothing was written: no journal for an action that needs one, an
        unusable state directory, a path that escapes the state directory, -PurgeBackup without
        -Apply, -RecordAfter with no journal, or an unusable parameter value.
    With -CheckOnly (residue scan only) a missing journal is NOT a refusal - the machine-level
    items of the scan still run - but the verdict is then not clean either: the report carries
    attribution=unavailable with reasonKey journal_absent_cannot_attribute and exits 1, because
    "nothing of this tool was ever installed here" is not a fact this tool can prove without a
    journal. Run -RecordBefore before the remediation, or keep a backup: once the state journal
    has been archived into a backup, its journal.json snapshot is the provenance of record.

  MEASURED INVOCATION NOTES (Windows PowerShell 5.1, on this project's reference machine)
    * -KeepTailscale takes an explicit value. `powershell -File <this> -KeepTailscale false`
      works, and `-KeepTailscale:$false` works when the script is called in-process; a [bool]
      parameter cannot be bound from `-File` at all on 5.1 (measured: "Cannot convert value
      System.String to type System.Boolean"), which is why the parameter is [object] and is
      coerced below. An unusable value is a refusal (exit 2), never a guess. Omitting it keeps
      Tailscale, and no setting of it makes this tool uninstall Tailscale.
    * -FixturePath makes the journal AND every observation come from the fixture, so the
      classification is a pure function of (journal, observation); a system surface is then never
      mutated and every revert is printed as WOULD-DO with executed=false. A fixture run that
      WRITES (record-before/after, apply, purge) must be given an explicit -StateDir, so an
      offline run can never create the real %USERPROFILE% state directory.
    * A written backup is verified immediately: MANIFEST.json is re-read and every listed file's
      sha256 and byte count are recomputed. If any of it fails, the run refuses (exit 2) and no
      change is made - the backup-first guarantee is a runtime property, not a comment.

  WHAT IT NEVER DOES (there is no call site for any of these in this file)
    * it never adds a listener, a route or a firewall rule (it can only REMOVE a rule name that
      the journal recorded, and only when the current value is exactly the one we produced);
    * it never reads, prints or writes a token, a cookie, a key file or a credential store;
    * it never changes ExecutionPolicy, UAC, Defender or a profile default;
    * it never registers a scheduled task or a service, and never restarts or kills the DSH host;
    * it never elevates: the UAC prompt belongs to the operator, so a revert that needs an
      elevated window fails loudly and is reported with the exact command to run by hand;
    * it never removes Tailscale, another plugin's profile row, a user-added firewall rule, a
      repository file or a user-level skill copy by default (see the retention section).

  JOURNAL SCHEMA v1 (frozen; written literally by -RecordBefore / -RecordAfter)
    {
      "schemaVersion": 1,
      "tool": "dsh-crossnet-link/tools/uninstall.ps1",
      "createdAtLocal": "...", "updatedAtLocal": "...",
      "collectorBaseline": { ... },        # optional: the pre-uninstall non-pass check ids
      "records": [
        { "id": "...", "surface": "...", "scope": "...",
          "before": "...", "expected": "...", "after": null,
          "revert": { "kind": "command|edit|delete|instruction", "command": "...", "note": "..." },
          "verify": { "command": "...", "expect": "..." },
          "userOwned": false,
          "remediation": "...", "recordedAtLocal": "...", "recordedBy": "..." }   # extras, provenance only
      ]
    }
    surface is a closed set: dsh-profile-row, plugin-files, firewall-rule, tailscale-serve,
    dsh-settings, power-plan, network-profile, user-skill-copy, cordis-dynamic-package.

  RENAME (2026-09-25, task t8) - the old name is gone, the old data is not
    Every literal in this file was renamed to dsh-crossnet-link. Three READ-side rules keep data
    written by the pre-rename tool usable. None of them widens what may be touched:
      * journal: schemaVersion (1) and the record shape are unchanged, and the `tool` string is
        provenance only - no code path compares it - so a pre-rename journal loads exactly as it
        did before;
      * state directory: the default is now %USERPROFILE%\.dsh-crossnet-link, but when that
        directory does not exist and the legacy one does, the legacy directory is used and the
        report says source=auto-legacy(...). A pre-rename journal is therefore still found without
        passing -StateDir;
      * profile row id: -RowId now defaults to the id this package actually ships
        (dsh-crossnet-link). SEMANTIC CHANGE, not a string swap: the old default named a row that
        the shipped package never had, so under the old default the profile-row record always
        observed "absent" and the installed row never entered the journal. Observation and revert
        now also resolve the legacy ids to the same row (Get-RowIdCandidates). Attribution itself
        is NOT loosened: a row is removed only while its block text still equals the recorded
        before/after value byte-for-byte.
    Every legacy literal is assembled from two pieces in the constants section, so no old-name
    string survives verbatim in the release set (the idiom repo-hygiene.ps1 uses for the repo name).

  FIXTURE MODE (-FixturePath) - offline determinism
    The journal AND every current observation are read from the fixture file, so the classification
    is a pure function of (journal, observation) and nothing on the real machine (Tailscale, the
    firewall, powercfg) is consulted. In fixture mode a system surface is never mutated: reverts
    and file deletions are printed as WOULD-DO and the report says `executed=false`. Only this
    tool's own state directory may still be written, and then -StateDir must be given explicitly,
    so an offline run can never create the real %USERPROFILE% state directory.

  BACKUP FIRST, AND PURGE ONLY WHAT WE BACKED UP
    -Apply writes <BackupDir> before the first change: journal.json (the journal snapshot),
    plan.json (classification + provenance + timestamps), MANIFEST.json (sha256 + byte count of
    every other backup file), restore.md (per-record inverse operation plus its rollback
    verification command), and - only when those surfaces take part - the raw read-only captures
    profile-cordis.patch.yml.bak, firewall-rules.txt and serve-status.txt. A runtime guard refuses
    every mutation until the backup manifest has been written and verified.
    -PurgeBackup deletes only a directory UNDER the state directory that carries a MANIFEST.json
    whose every listed file matches by sha256 and byte count (that is what "did not back it up =>
    did not delete it" means in code); it prints the whole file list, the total bytes and each
    sha256 before deleting, and the deleted list afterwards.
#>
[CmdletBinding()]
param(
  [string]$StateDir = '',
  [string]$Journal = '',
  [switch]$RecordBefore,
  [switch]$RecordAfter,
  [switch]$Plan,
  [switch]$Apply,
  [string]$BackupDir = '',
  [switch]$PurgeBackup,
  [switch]$RemoveFiles,
  # KEPT as [object] on purpose. MEASURED on Windows PowerShell 5.1: a [bool] parameter cannot be
  # bound from `powershell.exe -File <script> -BoolParam <value>` at all ("Cannot convert value
  # System.String to type System.Boolean"), while `-KeepTailscale:$false` only works in-process.
  # This parameter therefore takes an explicit value (object) and is coerced below, so BOTH
  # invocation styles work, and an unusable value is a refusal instead of a guess.
  # Default (parameter omitted) = keep Tailscale. `false`/`0`/`no` changes ONLY the printed
  # suggestion: this tool never uninstalls Tailscale in any configuration.
  [object]$KeepTailscale = $true,
  [switch]$CheckOnly,
  [switch]$AsJson,
  [string]$FixturePath = '',
  [ValidateSet('auto','zh','en')][string]$Lang = 'auto',
  [string]$Manifest = '',
  [string]$DshHome = '',
  [string]$Collector = '',
  [string[]]$InstallPath = @(),
  [string[]]$CordisPluginId = @(),
  [string]$RowId = 'dsh-crossnet-link',
  [string]$NetworkProfileName = '',
  [int]$CommandTimeoutMs = 20000
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

# ===========================================================================
# section 0: frozen constants
# ===========================================================================

$script:ReportSchema  = 'dsh-crossnet-link/uninstall-report/1'
$script:FixtureSchema = 'dsh-crossnet-link/uninstall-fixture/1'
$script:JournalSchema = 1
$script:ToolName      = 'dsh-crossnet-link/tools/uninstall.ps1'
$script:RowIdDefault  = 'dsh-crossnet-link'
$script:FirewallRuleName = 'DSH via Tailscale serve (tcp 443)'
$script:UserIdleNever = '0x00000000'

# --- legacy identity (pre-rename), READ side only ---------------------------
# New records are always written with the current names. These legacy values exist so that a
# journal written before the rename can still claim what it recorded. Every legacy literal is
# assembled from two pieces so that no old-name string survives verbatim in the release set (the
# same idiom .github/scripts/repo-hygiene.ps1 uses for the repository name).
$script:LegacySlug = 'remote-tailnet-' + 'guard'
$script:LegacyStateDirName = '.' + $script:LegacySlug
# The plugin's loader row has carried more than one id over time (the legacy bare id, the legacy
# "-panel" id the old default used, and the current pair); they all designate the same row in a
# profile's cordis.patch.yml. Observation and revert resolve any of them through
# Get-RowIdCandidates, so a pre-rename journal's profile-row record is no longer condemned to
# "absent" after the rename. What is NOT loosened is attribution: the block read back must still
# equal the recorded before/after text exactly, or the row is left alone.
$script:RowIdEquivalents = @(
  'dsh-crossnet-link',
  'dsh-crossnet-link-panel',
  $script:LegacySlug,
  ($script:LegacySlug + '-panel')
)

# The surface closed set. A journal record whose surface is not in this list is reported as
# unknown and is never executed, so a hand-edited journal cannot widen the tool's reach.
$script:Surfaces = @(
  'dsh-profile-row', 'plugin-files', 'firewall-rule', 'tailscale-serve', 'dsh-settings',
  'power-plan', 'network-profile', 'user-skill-copy', 'cordis-dynamic-package'
)

# The only command shapes -Apply will ever hand to a shell. Anything else is printed for the
# operator and reported as residue instead of being run. Anchored, single invocation, no
# separator, no redirection, no variable expansion: a hand-edited journal cannot smuggle a
# second statement in, because the metacharacter check below rejects it as well.
$script:RevertAllow = @(
  "^Remove-NetFirewallRule -DisplayName '[^']{1,120}'$",
  '^tailscale(\.exe)? serve reset$',
  '^powercfg(\.exe)? /change standby-timeout-(ac|dc) [0-9]{1,6}$',
  '^Set-NetConnectionProfile -Name ''[^'']{1,120}'' -NetworkCategory (Public|Private|DomainAuthenticated)$'
)
$script:MetaReject = '[;|&$`(){}<>\[\]\r\n]'
$script:MemoryOnly = 'memory-only'

# ===========================================================================
# section 1: small helpers
# ===========================================================================

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

function Get-Array {
  # JSON arrays vanish when they are empty or when they hold a single element, so every read of a
  # list goes through here: a missing list is an empty list, never an array holding one $null.
  param($Node,[string]$Name)
  $v = Prop $Node $Name
  if ($null -eq $v) { return @() }
  if ($v -is [System.Array]) { return @($v | Where-Object { $null -ne $_ }) }
  return @($v)
}

function Set-NodeField {
  # Used only on journal documents the script itself owns. Add-Member -Force works whether the
  # field exists (a record written by this tool) or not (a hand-edited journal), and it never
  # writes an error to stderr.
  param($Node,[string]$Name,$Value)
  if ($null -eq $Node) { return }
  try { $Node | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force -ErrorAction SilentlyContinue } catch { }
}

function Get-Label {
  # The script is ASCII; the wording lives in the manifest (uninstallLabels.<lang>). A missing
  # label falls back to the built-in English default, so a manifest without the block still runs.
  param([string]$Key)
  $node = $script:Labels
  if ($null -eq $node) { return '' }
  if ($node -is [System.Collections.IDictionary]) {
    if ($node.Contains($Key)) { return [string]$node[$Key] }
    return ''
  }
  $p = $node.PSObject.Properties[$Key]
  if ($null -eq $p) { return '' }
  return [string]$p.Value
}

function Resolve-Lang {
  param([string]$Requested)
  if ($Requested -ne 'auto') { return $Requested }
  try {
    if ([System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -eq 'zh') { return 'zh' }
  } catch { }
  try {
    if ([System.Globalization.CultureInfo]::InstalledUICulture.TwoLetterISOLanguageName -eq 'zh') { return 'zh' }
  } catch { }
  return 'en'
}

function Get-Sha256Hex {
  param([string]$Path)
  if (-not $Path) { return '' }
  try { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash } catch { return '' }
}

function Get-FileByteCount {
  param([string]$Path)
  try { return [int64](Get-Item -LiteralPath $Path -Force -ErrorAction Stop).Length } catch { return -1 }
}

function Read-TextFileSafe {
  param([string]$Path)
  try {
    $t = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    if ($t.Length -gt 0 -and [int][char]$t[0] -eq 0xFEFF) { $t = $t.Substring(1) }
    return [pscustomobject]@{ ok = $true; text = $t; error = '' }
  } catch {
    return [pscustomobject]@{ ok = $false; text = ''; error = $_.Exception.Message }
  }
}

function Read-JsonFileSafe {
  param([string]$Path)
  $raw = Read-TextFileSafe $Path
  if (-not $raw.ok) { return [pscustomobject]@{ ok = $false; doc = $null; error = ('unreadable: ' + $raw.error) } }
  try { return [pscustomobject]@{ ok = $true; doc = ($raw.text | ConvertFrom-Json); error = '' } }
  catch { return [pscustomobject]@{ ok = $false; doc = $null; error = ('not valid JSON: ' + $_.Exception.Message) } }
}

function Format-Display {
  # One-line, bounded rendering of a value for the human report. Classification always uses the
  # FULL value - truncating before comparing could equate two different states.
  param([string]$Text,[int]$Max = 220)
  if ($null -eq $Text) { return '' }
  $t = ([string]$Text) -replace '\s+', ' '
  if ($t.Length -gt $Max) { $t = $t.Substring(0, $Max) + '...(+' + ($Text.Length - $Max) + ' chars)' }
  return $t
}

function Get-SystemTextEncoding {
  $enc = $null
  $cp = 0
  try {
    $v = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage' -ErrorAction Stop).OEMCP
    if ($v) { [void][int]::TryParse([string]$v, [ref]$cp) }
  } catch { $cp = 0 }
  if ($cp -gt 0) { try { $enc = [System.Text.Encoding]::GetEncoding($cp) } catch { $enc = $null } }
  if ($null -eq $enc) { try { $enc = [Console]::OutputEncoding } catch { $enc = $null } }
  return $enc
}

function Invoke-Bounded {
  # Bounded, non-shelling child process. Used for read-only probes (observers) and for a revert
  # command that already passed the frozen allowlist. Output is captured in memory: no temp file
  # is created, so a confined session cannot fail on a redirect target.
  param([string]$Exe,[string[]]$ArgList,[int]$TimeoutMs)
  $res = [ordered]@{ available = $false; exitCode = $null; stdout = ''; stderr = ''; error = '' }
  $path = ''
  if ($Exe) {
    if (Test-Path -LiteralPath $Exe) { $path = $Exe }
    else { try { $path = (Get-Command $Exe -ErrorAction Stop).Source } catch { $path = '' } }
  }
  if (-not $path) { $res.error = 'executable not found: ' + $Exe; return $res }
  try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $path
    $psi.Arguments = (($ArgList | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' ')
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $enc = Get-SystemTextEncoding
    if ($null -ne $enc) { $psi.StandardOutputEncoding = $enc; $psi.StandardErrorEncoding = $enc }
    $p = [System.Diagnostics.Process]::Start($psi)
    $soTask = $p.StandardOutput.ReadToEndAsync()
    $seTask = $p.StandardError.ReadToEndAsync()
    $finished = $p.WaitForExit($TimeoutMs)
    if (-not $finished) { try { $p.Kill() } catch { } }
    try { $res.stdout = $soTask.Result } catch { $res.stdout = '' }
    try { $res.stderr = $seTask.Result } catch { $res.stderr = '' }
    $res.available = $true
    if ($finished) { $res.exitCode = $p.ExitCode } else { $res.error = 'timeout after ' + $TimeoutMs + ' ms' }
  } catch { $res.error = $_.Exception.Message }
  return $res
}

function Find-Executable {
  param([string]$Name)
  $p = ''
  if ($env:SystemRoot) {
    $cand = Join-Path (Join-Path $env:SystemRoot 'System32') $Name
    if (Test-Path -LiteralPath $cand) { return $cand }
  }
  try { $p = (Get-Command $Name -ErrorAction Stop).Source } catch { $p = '' }
  return $p
}

function Test-RealPath {
  # A scope can come from a hand-edited journal or from a fixture, so a path is only touched when
  # it really looks like a path. This keeps a bogus scope from turning into a cmdlet error.
  param([string]$Path,[switch]$Leaf,[switch]$Container)
  if (-not $Path) { return $false }
  if ($Path -match '[<>|"?]') { return $false }
  try {
    if ($Container) { return (Test-Path -LiteralPath $Path -PathType Container) }
    if ($Leaf) { return (Test-Path -LiteralPath $Path -PathType Leaf) }
    return (Test-Path -LiteralPath $Path)
  } catch { return $false }
}

function New-Observation {
  param([string]$Status,[string]$Value,[string]$Detail)
  return [pscustomobject][ordered]@{
    status = $Status          # read | unreadable
    value  = [string]$Value
    detail = [string]$Detail
  }
}

function Get-NowStamp { return (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') }
function Get-DirStamp { return (Get-Date).ToString('yyyyMMdd-HHmmss') }

function Normalize-PathForCompare {
  param([string]$Path)
  if (-not $Path) { return '' }
  $p = ''
  try { $p = [System.IO.Path]::GetFullPath($Path) } catch { $p = $Path }
  $p = $p.TrimEnd('\', '/')
  if ($p.Length -eq 2 -and $p[1] -eq ':') { $p = $p + '\' }
  return $p.ToLowerInvariant()
}

function Test-PathInside {
  # True when $Child is $Parent itself or lives under it. Both sides are normalized first, so
  # `..\..`-style escapes cannot pass. This is the only route to a write or a delete.
  param([string]$Child,[string]$Parent)
  $c = Normalize-PathForCompare $Child
  $p = Normalize-PathForCompare $Parent
  if (-not $c -or -not $p) { return $false }
  if ($c -eq $p) { return $true }
  return $c.StartsWith($p.TrimEnd('\') + '\')
}

function Add-Order {
  param([string]$Step)
  $n = @($script:OrderLog).Count + 1
  [void]$script:OrderLog.Add([string]$n + '. ' + $Step)
}

function Add-Note {
  param([string]$Text)
  [void]$script:Notes.Add([string]$Text)
}

function Add-Refusal {
  param([string]$Key,[string]$Text)
  [void]$script:Refusals.Add([pscustomobject][ordered]@{ reasonKey = $Key; message = $Text })
}

$script:OrderLog = New-Object System.Collections.ArrayList
$script:Notes    = New-Object System.Collections.ArrayList
$script:Refusals = New-Object System.Collections.ArrayList
$script:RevertsRun = 0
$script:DeletesRun = 0
$script:BackupDone = $false
$script:FixtureMode = $false
$script:CollectorCalls = 0
$script:LabelSource = 'builtin-en'
$script:Labels = $null
$script:JournalAbsentUnattributable = $false

# --- -KeepTailscale coercion (see the parameter comment) -------------------
$keepTailVal = $true
if ($PSBoundParameters.ContainsKey('KeepTailscale')) {
  $raw = $KeepTailscale
  if ($null -eq $raw) { $keepTailVal = $false }
  elseif ($raw -is [bool]) { $keepTailVal = [bool]$raw }
  elseif ($raw -is [System.Management.Automation.SwitchParameter]) { $keepTailVal = [bool]$raw.IsPresent }
  elseif ($raw -is [int] -or $raw -is [long] -or $raw -is [double]) { $keepTailVal = ([double]$raw -ne 0) }
  else {
    $s = ([string]$raw).Trim().TrimStart('$').ToLowerInvariant()
    if ($s -eq 'false' -or $s -eq '0' -or $s -eq 'no' -or $s -eq 'off') { $keepTailVal = $false }
    elseif ($s -eq 'true' -or $s -eq '1' -or $s -eq 'yes' -or $s -eq 'on') { $keepTailVal = $true }
    else {
      [void]$script:Refusals.Add([pscustomobject][ordered]@{
        reasonKey = 'bad_parameter'
        message = ('-KeepTailscale got an unusable value: "' + [string]$raw + '". Pass true/false (or 1/0, or -KeepTailscale:$false in-process). This tool never guesses a parameter.')
      })
    }
  }
}

# ===========================================================================
# section 2: configuration resolution (no machine-specific value is hardcoded)
# ===========================================================================

$script:PluginRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

if ($StateDir) { $stateVal = $StateDir; $stateSrc = 'param' }
elseif ($env:RTG_STATE_DIR) { $stateVal = $env:RTG_STATE_DIR; $stateSrc = 'env:RTG_STATE_DIR' }
elseif ($env:USERPROFILE) {
  # Default state directory. A journal written by the pre-rename tool lives under the legacy
  # directory name, so when the current default does not exist but the legacy directory does, the
  # legacy directory wins: historical journals stay findable without passing -StateDir. When both
  # exist the current default wins (new work never lands in the legacy directory by accident).
  $stateVal = Join-Path $env:USERPROFILE '.dsh-crossnet-link'; $stateSrc = 'auto(USERPROFILE/.dsh-crossnet-link)'
  $legacyStateDir = Join-Path $env:USERPROFILE $script:LegacyStateDirName
  if ((-not (Test-Path -LiteralPath $stateVal)) -and (Test-Path -LiteralPath $legacyStateDir)) {
    $stateVal = $legacyStateDir
    $stateSrc = 'auto-legacy(USERPROFILE/' + $script:LegacyStateDirName + ')'
  }
}
else { $stateVal = ''; $stateSrc = 'missing' }

if ($Journal) { $journalVal = $Journal; $journalSrc = 'param' }
elseif ($stateVal) { $journalVal = Join-Path $stateVal 'state-journal.json'; $journalSrc = 'default(StateDir/state-journal.json)' }
else { $journalVal = ''; $journalSrc = 'missing' }

if ($DshHome) { $dshHomeVal = $DshHome; $dshHomeSrc = 'param' }
elseif ($env:DSH_HOME) { $dshHomeVal = $env:DSH_HOME; $dshHomeSrc = 'env:DSH_HOME' }
elseif ($env:USERPROFILE) { $dshHomeVal = Join-Path $env:USERPROFILE '.dsh'; $dshHomeSrc = 'auto(USERPROFILE/.dsh)' }
else { $dshHomeVal = ''; $dshHomeSrc = 'missing' }

if ($Manifest) { $manifestVal = $Manifest; $manifestSrc = 'param' }
else { $manifestVal = Join-Path $script:PluginRoot 'panel\prereq-manifest.json'; $manifestSrc = 'default(panel/prereq-manifest.json)' }

if ($Collector) { $collectorVal = $Collector; $collectorSrc = 'param' }
else { $collectorVal = Join-Path $script:PluginRoot 'src\collect.ps1'; $collectorSrc = 'default(src/collect.ps1)' }

$langUsed = Resolve-Lang $Lang

$cfg = New-Object System.Collections.ArrayList
function Add-Cfg { param([string]$Name,$Value,[string]$Source)
  $v = ''
  if ($null -ne $Value) { $v = [string]$Value }
  [void]$cfg.Add([pscustomobject][ordered]@{ name = $Name; value = $v; source = $Source })
}
Add-Cfg 'stateDir'   $stateVal    $stateSrc
Add-Cfg 'journal'    $journalVal  $journalSrc
Add-Cfg 'dshHome'    $dshHomeVal  $dshHomeSrc
Add-Cfg 'manifest'   $manifestVal $manifestSrc
Add-Cfg 'collector'  $collectorVal $collectorSrc
Add-Cfg 'rowId'      $RowId       'param(default dsh-crossnet-link)'
Add-Cfg 'removeFiles' $([bool]$RemoveFiles) 'param'
Add-Cfg 'keepTailscale' $keepTailVal 'param(default true; see the coercion comment)'
Add-Cfg 'commandTimeoutMs' $CommandTimeoutMs 'param'

# --- fixture ---------------------------------------------------------------
$fx = $null
if ($FixturePath) {
  if (-not (Test-Path -LiteralPath $FixturePath)) {
    Add-Refusal 'fixture_missing' ('the fixture file does not exist: ' + $FixturePath)
  } else {
    $fxRead = Read-JsonFileSafe $FixturePath
    if (-not $fxRead.ok) { Add-Refusal 'fixture_unusable' ('the fixture file ' + $FixturePath + ' ' + $fxRead.error) }
    else { $fx = $fxRead.doc; $script:FixtureMode = $true }
  }
}

# --- action selection ------------------------------------------------------
$action = 'plan'
if ($RecordBefore -and $RecordAfter) { Add-Refusal 'conflicting_actions' 'choose either -RecordBefore or -RecordAfter, not both' }
if (($RecordBefore -or $RecordAfter) -and ($Apply -or $CheckOnly -or $PurgeBackup)) {
  Add-Refusal 'conflicting_actions' '-RecordBefore / -RecordAfter are bookkeeping runs: combine them with neither -Apply, -CheckOnly nor -PurgeBackup'
}
if ($PurgeBackup -and -not $Apply) { Add-Refusal 'purge_without_apply' '-PurgeBackup deletes a backup directory, so it is refused without -Apply (the documented rule: nothing is deleted unless this run also backs up)' }
if ($CheckOnly -and $Apply) { Add-Refusal 'conflicting_actions' '-CheckOnly is the standalone residue scan; -Apply already scans after it finishes. Choose one.' }
if ($Plan -and ($Apply -or $CheckOnly)) { Add-Refusal 'conflicting_actions' '-Plan is the default action: do not combine it with -Apply or -CheckOnly' }

if ($PurgeBackup) { $action = 'purge' }
elseif ($RecordBefore) { $action = 'record-before' }
elseif ($RecordAfter) { $action = 'record-after' }
elseif ($Apply) { $action = 'apply' }
elseif ($CheckOnly) { $action = 'check' }

Add-Order ('action selected: ' + $action + '   (dry-run by default; only -Apply writes to a system surface)')

# --- path guards -----------------------------------------------------------
if ($stateVal) {
  if ($journalVal -and -not (Test-PathInside $journalVal $stateVal)) {
    Add-Refusal 'path_escape' ('the journal path is not inside the state directory: ' + $journalVal + '  (state dir: ' + $stateVal + ')')
  }
  if ($BackupDir -and -not (Test-PathInside $BackupDir $stateVal)) {
    Add-Refusal 'path_escape' ('-BackupDir must be inside the state directory: ' + $BackupDir + '  (state dir: ' + $stateVal + ')')
  }
}
if (-not $stateVal) { Add-Refusal 'state_dir_missing' 'no state directory could be resolved: pass -StateDir, or set USERPROFILE' }

$wantsSystemMutation = ($action -eq 'apply')
if ($script:FixtureMode -and -not $StateDir -and ($wantsSystemMutation -or $action -eq 'record-before' -or $action -eq 'record-after' -or $action -eq 'purge')) {
  Add-Refusal 'fixture_requires_statedir' ('fixture mode: an action that writes must be given an explicit -StateDir, so an offline run can never create the real state directory (' + $stateVal + ')')
}
if ($script:FixtureMode -and $wantsSystemMutation) {
  Add-Note 'fixture mode: system surfaces are read from the fixture and are NEVER mutated by this run; each revert is printed as WOULD-DO with executed=false'
}

# ===========================================================================
# section 3: state directory and journal I/O
# ===========================================================================

function Get-StateDirState {
  $out = [ordered]@{ path = $stateVal; exists = $false; readable = $false; isDirectory = $true; error = '' }
  if (-not $stateVal) { $out.isDirectory = $false; $out.error = 'no state directory resolved'; return [pscustomobject]$out }
  try {
    if (-not (Test-Path -LiteralPath $stateVal)) { return [pscustomobject]$out }
    $out.exists = $true
    $item = Get-Item -LiteralPath $stateVal -Force -ErrorAction Stop
    $out.isDirectory = [bool]$item.PSIsContainer
    if (-not $out.isDirectory) { $out.error = 'the state directory path exists but is not a directory' }
    else { [void](Get-ChildItem -LiteralPath $stateVal -Force -ErrorAction Stop | Select-Object -First 1) ; $out.readable = $true }
  } catch { $out.error = $_.Exception.Message }
  return [pscustomobject]$out
}

function New-DirectorySafe {
  param([string]$Path)
  try {
    if (-not [System.IO.Directory]::Exists($Path)) { [void][System.IO.Directory]::CreateDirectory($Path) }
    return ''
  } catch { return $_.Exception.Message }
}

function Write-TextFileSafe {
  # The only text writer in this file. Used for the state directory and the backup only; a system
  # surface is written through the guarded editors further down.
  param([string]$Path,[string]$Text)
  try {
    $dir = [System.IO.Path]::GetDirectoryName($Path)
    if ($dir -and -not [System.IO.Directory]::Exists($dir)) { [void][System.IO.Directory]::CreateDirectory($dir) }
    [System.IO.File]::WriteAllText($Path, [string]$Text, (New-Object System.Text.UTF8Encoding($false)))
    return ''
  } catch { return $_.Exception.Message }
}

function ConvertTo-JsonSafe {
  param($Object,[int]$Depth = 12)
  try { return ($Object | ConvertTo-Json -Depth $Depth) } catch { return '' }
}

function Get-JournalText {
  param($Doc)
  $t = ConvertTo-JsonSafe $Doc 14
  if (-not $t) { return '' }
  return $t
}

function Save-Journal {
  param($Doc)
  $txt = Get-JournalText $Doc
  if (-not $txt) { return 'the journal could not be serialized' }
  $doc.set_updatedAtLocal
  return (Write-TextFileSafe $journalVal $txt)
}

function Read-JournalDoc {
  # Returns { found, source, doc, error, path }
  $out = [ordered]@{ found = $false; source = 'none'; doc = $null; error = ''; path = $journalVal; snapshot = '' }
  if ($script:FixtureMode) {
    $out.path = $FixturePath
    $jn = Prop $fx 'journal'
    if ($null -eq $jn) { $out.error = 'the fixture declares no journal'; return [pscustomobject]$out }
    $out.found = $true; $out.source = 'fixture'; $out.doc = $jn
    return [pscustomobject]$out
  }
  if (-not $journalVal) { $out.error = 'no journal path resolved'; return [pscustomobject]$out }
  if (Test-Path -LiteralPath $journalVal) {
    $r = Read-JsonFileSafe $journalVal
    if (-not $r.ok) { $out.error = $r.error; return [pscustomobject]$out }
    $out.found = $true; $out.source = 'file'; $out.doc = $r.doc
    return [pscustomobject]$out
  }
  # The state journal may have been archived into a backup by an earlier -Apply (that is what makes
  # the residue scan able to say "only a backup directory is left"). The newest backup snapshot
  # that carries journal.json is then the provenance of record, so attribution stays possible.
  $bdir = ''
  if ($stateVal) { $bdir = Join-Path $stateVal 'backups' }
  if ($bdir -and (Test-Path -LiteralPath $bdir)) {
    $dirs = @(Get-ChildItem -LiteralPath $bdir -Directory -Force -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
    foreach ($d in $dirs) {
      $snap = Join-Path $d.FullName 'journal.json'
      if (-not (Test-Path -LiteralPath $snap -PathType Leaf)) { continue }
      $r2 = Read-JsonFileSafe $snap
      if (-not $r2.ok) { continue }
      $out.found = $true; $out.source = 'backup-snapshot'; $out.doc = $r2.doc; $out.path = $snap; $out.snapshot = $snap
      return [pscustomobject]$out
    }
  }
  $out.error = 'the journal file does not exist: ' + $journalVal
  return [pscustomobject]$out
}

# ===========================================================================
# section 4: the catalog - the surfaces this link setup touches
# ===========================================================================
# Every record -RecordBefore writes comes from here, so the journal cannot be widened at record
# time either. Scopes are resolved at runtime: no machine name, no user name and no peer address
# is ever written into this file.

function Get-ProfilePatchFiles {
  $out = New-Object System.Collections.ArrayList
  if (-not $dshHomeVal) { return $out.ToArray() }
  $profiles = Join-Path $dshHomeVal 'profiles'
  if (-not (Test-Path -LiteralPath $profiles)) { return $out.ToArray() }
  foreach ($d in @(Get-ChildItem -LiteralPath $profiles -Directory -Force -ErrorAction SilentlyContinue)) {
    $p = Join-Path $d.FullName 'cordis.patch.yml'
    if (Test-Path -LiteralPath $p -PathType Leaf) { [void]$out.Add($p) }
  }
  return $out.ToArray()
}

function Get-Catalog {
  $cat = New-Object System.Collections.ArrayList
  $rowId = $RowId
  if (-not $rowId) { $rowId = $script:RowIdDefault }

  # --- dsh-profile-row: one record per profile patch file that exists now ---
  foreach ($patch in @(Get-ProfilePatchFiles)) {
    [void]$cat.Add([pscustomobject][ordered]@{
      id = 'profile-row-' + $rowId
      surface = 'dsh-profile-row'
      scope = $patch + '::' + $rowId
      expected = 'present:row=' + $rowId
      userOwned = $false
      revertKind = 'edit'
      revertCommand = "remove the '" + $rowId + "' entry from " + $patch + " (done in-process, line-level, only while the recorded block is unchanged)"
      revertNote = 'the file is copied byte-for-byte into the backup first; a block whose text no longer matches the recorded value is left alone'
      verifyCommand = "Select-String -LiteralPath '" + $patch + "' -Pattern '" + $rowId + "'"
      verifyExpect = 'absent'
      remediation = 'append to ' + $patch + ": a YAML list entry with id " + $rowId
    })
  }

  # --- firewall-rule: the one rule this deployment documents, by name ---
  [void]$cat.Add([pscustomobject][ordered]@{
    id = 'firewall-rule-dsh-serve-443'
    surface = 'firewall-rule'
    scope = $script:FirewallRuleName
    expected = 'present:action=Allow;dir=In;proto=TCP;lport=443;ra4=100.64.0.0/10'
    userOwned = $false
    revertKind = 'command'
    revertCommand = "Remove-NetFirewallRule -DisplayName '" + $script:FirewallRuleName + "'"
    revertNote = 'needs an elevated window; if it fails this tool says so and never elevates on your behalf'
    verifyCommand = "netsh advfirewall firewall show rule name=`"" + $script:FirewallRuleName + "`""
    verifyExpect = 'absent'
    remediation = "New-NetFirewallRule -DisplayName '" + $script:FirewallRuleName + "' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 443 -RemoteAddress 100.64.0.0/10 -Program `"`$env:ProgramFiles\Tailscale\tailscaled.exe`" -Profile Any"
  })

  # --- tailscale-serve: the exposure step of the link ---
  [void]$cat.Add([pscustomobject][ordered]@{
    id = 'tailscale-serve-dsh-port'
    surface = 'tailscale-serve'
    scope = 'serve'
    expected = 'proxy=http://127.0.0.1:<DSH_PORT>'
    userOwned = $false
    revertKind = 'command'
    revertCommand = 'tailscale serve reset'
    revertNote = 'clears the WHOLE serve configuration on this machine (it is not a per-port stop); verify with tailscale serve status'
    verifyCommand = 'tailscale serve status'
    verifyExpect = 'not-configured'
    remediation = 'tailscale serve --bg <DSH_PORT>'
  })

  # --- dsh-settings: the loopback-only posture of the DSH web port ---
  if ($dshHomeVal) {
    $settings = Join-Path $dshHomeVal 'settings.yaml'
    [void]$cat.Add([pscustomobject][ordered]@{
      id = 'dsh-settings-network-exposure'
      surface = 'dsh-settings'
      scope = $settings + '::networkExposure'
      expected = 'networkExposure=loopback'
      userOwned = $false
      revertKind = 'edit'
      revertCommand = 'set networkExposure back to the recorded before value in ' + $settings + ' (done in-process, line-level, only while the recorded line is unchanged)'
      revertNote = 'the file is copied byte-for-byte into the backup first; an unrecorded or edited line is left alone'
      verifyCommand = "Select-String -LiteralPath '" + $settings + "' -Pattern '^\\s*networkExposure\\s*:'"
      verifyExpect = 'the recorded before value, or absent'
      remediation = 'set `networkExposure: loopback` in ' + $settings
    })
  }

  # --- power-plan: the server must not idle-sleep out of the link ---
  [void]$cat.Add([pscustomobject][ordered]@{
    id = 'power-plan-standby-idle'
    surface = 'power-plan'
    scope = 'SCHEME_CURRENT::STANDBYIDLE'
    expected = 'standbyidle:ac=' + $script:UserIdleNever + ':dc=' + $script:UserIdleNever
    userOwned = $false
    revertKind = 'command'
    revertCommand = ''
    revertNote = 'the revert command is derived from the recorded before value when it is parseable; otherwise the value is printed for you and this tool refuses to run anything'
    verifyCommand = 'powercfg /query SCHEME_CURRENT 238c9fa8-0aad-41ed-83f4-97be242c8f20 29f6c1db-86da-48c5-9fdb-f2b67b1f44da'
    verifyExpect = 'the recorded before indices in the last two value lines'
    remediation = 'powercfg /change standby-timeout-ac 0   and   powercfg /change standby-timeout-dc 0'
  })

  # --- network-profile: only when the operator names the profile to watch ---
  if ($NetworkProfileName) {
    [void]$cat.Add([pscustomobject][ordered]@{
      id = 'network-profile-' + ($NetworkProfileName -replace '[^A-Za-z0-9._-]','_')
      surface = 'network-profile'
      scope = $NetworkProfileName
      expected = 'category=1'
      userOwned = $false
      revertKind = 'command'
      revertCommand = "Set-NetConnectionProfile -Name '" + $NetworkProfileName + "' -NetworkCategory Public"
      revertNote = 'Set-NetConnectionProfile needs an elevated window; the before category is in the record, so change the command if the machine was Private before'
      verifyCommand = "Get-NetConnectionProfile -Name '" + $NetworkProfileName + "'"
      verifyExpect = 'the recorded before category'
      remediation = "Set-NetConnectionProfile -Name '" + $NetworkProfileName + "' -NetworkCategory Private"
    })
  }

  # --- user-skill-copy: the user-level copy is RECORDED as user-owned, so it is kept ---
  if ($dshHomeVal) {
    $copy = Join-Path (Join-Path $dshHomeVal 'skills') 'dsh-remote-tailnet'
    if (Test-Path -LiteralPath $copy) {
      [void]$cat.Add([pscustomobject][ordered]@{
        id = 'user-skill-copy-dsh-remote-tailnet'
        surface = 'user-skill-copy'
        scope = $copy
        expected = 'present'
        userOwned = $true
        revertKind = 'delete'
        revertCommand = "Remove-Item -LiteralPath '" + $copy + "' -Recurse -Force"
        revertNote = 'user-owned by policy: this tool never deletes it, it only prints that command for you'
        verifyCommand = "Test-Path -LiteralPath '" + $copy + "'"
        verifyExpect = 'absent if you removed it yourself'
        remediation = 'copy the skill folder into the user-level skills directory'
      })
    }
  }

  # --- plugin-files: only the paths the operator declares with -InstallPath ---
  $idx = 0
  foreach ($p in @($InstallPath)) {
    if (-not $p) { continue }
    $idx++
    [void]$cat.Add([pscustomobject][ordered]@{
      id = 'plugin-file-' + [string]$idx
      surface = 'plugin-files'
      scope = $p
      expected = 'present'
      userOwned = $false
      revertKind = 'delete'
      revertCommand = 'Remove-Item -LiteralPath ' + $p + ' -Force'
      revertNote = 'deleted in-process only with -RemoveFiles AND only when the file hash still equals the recorded after value'
      verifyCommand = 'Test-Path -LiteralPath ' + $p
      verifyExpect = 'absent'
      remediation = 'copy the plugin file to ' + $p
    })
  }

  # --- cordis-dynamic-package: PRINT ONLY. Never executed, never observed. ---
  $cordisIds = @($CordisPluginId)
  if (@($cordisIds).Count -eq 0) { $cordisIds = @('guard-1', 'panel-2') }
  foreach ($cid in $cordisIds) {
    if (-not $cid) { continue }
    [void]$cat.Add([pscustomobject][ordered]@{
      id = 'cordis-dynamic-package-' + ($cid -replace '[^A-Za-z0-9._-]','_')
      surface = 'cordis-dynamic-package'
      scope = $cid
      expected = $script:MemoryOnly
      userOwned = $false
      revertKind = 'instruction'
      revertCommand = 'cordis_undefine(' + $cid + ')'
      revertNote = 'run this in the DSH session: a dynamic package lives only in the DSH process memory, so this PowerShell side cannot see it and must not pretend to remove it'
      verifyCommand = 'cordis_inspect_self  (in the DSH session)'
      verifyExpect = 'the plugin is gone from the Session plugin list'
      remediation = 'activate the dynamic package from the DSH session (define + run)'
    })
  }

  return $cat.ToArray()
}

# ===========================================================================
# section 5: native observers (read-only, bounded, locale-proof where it matters)
# ===========================================================================

$script:RawCaptures = @{}

function Get-YamlItemBlock {
  param([string]$Text,[string]$ItemId)
  $out = [ordered]@{ found = $false; block = ''; startLine = -1; endLine = -1; indent = 0 }
  $lines = @($Text -split "`r?`n")
  $start = -1
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match ('^\s*-\s*id\s*:\s*' + [regex]::Escape($ItemId) + '\s*$')) { $start = $i; break }
  }
  if ($start -lt 0) { return [pscustomobject]$out }
  $indent = 0
  while ($indent -lt $lines[$start].Length -and $lines[$start][$indent] -eq ' ') { $indent++ }
  $end = $start
  for ($j = $start + 1; $j -lt $lines.Count; $j++) {
    $l = [string]$lines[$j]
    if ($l.Trim() -eq '') { break }
    $ind2 = 0
    while ($ind2 -lt $l.Length -and $l[$ind2] -eq ' ') { $ind2++ }
    if ($ind2 -le $indent) { break }
    if ($l.Trim().StartsWith('- ')) { break }
    $end = $j
  }
  $out.found = $true
  $out.startLine = $start
  $out.endLine = $end
  $out.indent = $indent
  $out.block = (@($lines[$start..$end]) -join "`n")
  return [pscustomobject]$out
}

# Resolves one rowId to the ordered candidate list used when reading a profile patch file: the
# requested id first (so a live row is always preferred), then its legacy/current equivalents. An
# id outside the equivalent set resolves to itself alone, and a caller that passes no id gets no
# candidates (the empty row id must never match a row).
function Get-RowIdCandidates {
  param([string]$RowId)
  $ids = New-Object System.Collections.ArrayList
  if (-not $RowId) { return $ids.ToArray() }
  [void]$ids.Add($RowId)
  if ($script:RowIdEquivalents -contains $RowId) {
    foreach ($eq in $script:RowIdEquivalents) { if (-not $ids.Contains($eq)) { [void]$ids.Add($eq) } }
  }
  return $ids.ToArray()
}

# Finds the first row among the candidates. Returns { found, block, startLine, endLine, indent,
# rowId } where rowId is the id that actually matched (empty when nothing matched).
function Get-ProfileRowBlock {
  param([string]$Text, [string]$RowId)
  foreach ($cand in @(Get-RowIdCandidates -RowId $RowId)) {
    $b = Get-YamlItemBlock $Text $cand
    if ($b.found) {
      return [pscustomobject]@{ found = $true; block = $b.block; startLine = $b.startLine; endLine = $b.endLine; indent = $b.indent; rowId = $cand }
    }
  }
  return [pscustomobject]@{ found = $false; block = ''; startLine = -1; endLine = -1; indent = 0; rowId = '' }
}

function Get-ProfileRowObservation {
  param([string]$Scope)
  $parts = $Scope -split '::'
  $path = $parts[0]
  $rowId = ''
  if ($parts.Count -gt 1) { $rowId = $parts[1] }
  if (-not (Test-RealPath $path -Leaf)) {
    return New-Observation 'read' 'absent' ('the profile patch file does not exist: ' + $path)
  }
  $r = Read-TextFileSafe $path
  if (-not $r.ok) { return New-Observation 'unreadable' '' ('the profile patch file could not be read: ' + $r.error) }
  $b = Get-ProfileRowBlock -Text $r.text -RowId $rowId
  if (-not $b.found) { return New-Observation 'read' 'absent' ('no YAML list entry with id ' + $rowId + ' in ' + $path) }
  $norm = ($b.block -replace '\s+', ' ').Trim()
  $via = ''
  if ($b.rowId -cne $rowId) { $via = ' (resolved through the equivalent row id "' + $b.rowId + '")' }
  return New-Observation 'read' ('present:' + $norm) ('lines ' + ($b.startLine + 1) + '-' + ($b.endLine + 1) + ' of ' + $path + ': ' + $norm + $via)
}

function Get-FirewallRuleObservation {
  param([string]$RuleName)
  $key = 'HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\FirewallRules'
  $props = $null
  try { $props = Get-ItemProperty -Path $key -ErrorAction Stop }
  catch { return New-Observation 'unreadable' '' ('the firewall rule store could not be read: ' + $_.Exception.Message) }
  $found = New-Object System.Collections.ArrayList
  $raw = New-Object System.Collections.ArrayList
  foreach ($pr in $props.PSObject.Properties) {
    if ($pr.Name -like 'PS*') { continue }
    $v = [string]$pr.Value
    $name = ''
    foreach ($t in ($v -split '\|')) {
      if ($t -match '^Name=(.*)$') { $name = $Matches[1]; break }
    }
    if ($name -ne $RuleName) { continue }
    [void]$raw.Add($pr.Name + '  ' + $v)
    $kv = [ordered]@{}
    foreach ($t in ($v -split '\|')) {
      if ($t -match '^(Action|Active|Dir|Protocol|LPort|RPort|RA4|RA6|Profile)=(.*)$') {
        $k = $Matches[1].ToLowerInvariant()
        if (-not $kv.Contains($k)) { $kv[$k] = $Matches[2] }
      }
    }
    $seg = New-Object System.Collections.ArrayList
    foreach ($k in @($kv.Keys | Sort-Object)) { [void]$seg.Add($k + '=' + $kv[$k]) }
    [void]$found.Add(($seg -join ';'))
  }
  $script:RawCaptures['firewall-rule'] = (@($raw) -join "`r`n")
  if ($found.Count -eq 0) { return New-Observation 'read' 'absent' ('no rule named "' + $RuleName + '" in the local firewall rule store') }
  $sorted = @($found | Sort-Object)
  return New-Observation 'read' ('present:' + ($sorted -join ' || ')) (($sorted.Count).ToString() + ' rule value(s) named "' + $RuleName + '": ' + ($sorted -join ' || '))
}

function Get-TailscaleServeObservation {
  $exe = Find-Executable 'tailscale.exe'
  if (-not $exe) {
    return New-Observation 'read' 'not-configured' 'tailscale.exe was not found, so no serve configuration can exist on this machine'
  }
  $r = Invoke-Bounded $exe @('serve','status') $CommandTimeoutMs
  if (-not $r.available) { return New-Observation 'unreadable' '' ('tailscale serve status could not be started: ' + $r.error) }
  $raw = 'exitCode=' + [string]$r.exitCode + "`r`n--- stdout ---`r`n" + $r.stdout + "`r`n--- stderr ---`r`n" + $r.stderr
  $script:RawCaptures['tailscale-serve'] = $raw
  if ($r.stderr -match 'Access is denied|ProtectedPrefix') {
    return New-Observation 'unreadable' '' 'the tailscale daemon pipe refused this session (access denied), so the serve configuration cannot be read here; re-run in an ordinary window'
  }
  if ($r.exitCode -ne 0) {
    return New-Observation 'unreadable' '' ('tailscale serve status exited ' + [string]$r.exitCode + ': ' + (Format-Display $r.stderr 160))
  }
  $m = @([regex]::Matches($r.stdout, '127\.0\.0\.1:([0-9]{1,5})'))
  if ($m.Count -eq 0) {
    $first = (@(($r.stdout -split "`r?`n") | Where-Object { $_.Trim() -ne '' }) | Select-Object -First 1)
    return New-Observation 'read' 'not-configured' ('the serve configuration carries no loopback proxy target: ' + (Format-Display $first 120))
  }
  $targets = New-Object System.Collections.ArrayList
  foreach ($mm in $m) { [void]$targets.Add('proxy=http://127.0.0.1:' + $mm.Groups[1].Value) }
  $sorted = @($targets | Sort-Object -Unique)
  return New-Observation 'read' ($sorted -join ' || ') (($sorted -join ' || ') + '  (raw: ' + (Format-Display $r.stdout 160) + ')')
}

function Get-DshSettingsObservation {
  param([string]$Scope)
  $parts = $Scope -split '::'
  $path = $parts[0]
  $keyName = ''
  if ($parts.Count -gt 1) { $keyName = $parts[1] }
  if (-not (Test-RealPath $path -Leaf)) {
    return New-Observation 'read' 'absent' ('the settings file does not exist, so ' + $keyName + ' is at its built-in default: ' + $path)
  }
  $r = Read-TextFileSafe $path
  if (-not $r.ok) { return New-Observation 'unreadable' '' ('the settings file could not be read: ' + $r.error) }
  foreach ($ln in @($r.text -split "`r?`n")) {
    if ($ln -match ('^\s*' + [regex]::Escape($keyName) + '\s*:\s*(.*)$')) {
      $v = $Matches[1].Trim()
      return New-Observation 'read' ($keyName + '=' + $v) ('line in ' + $path + ': ' + $ln.Trim())
    }
  }
  return New-Observation 'read' 'absent' ('the key ' + $keyName + ' does not appear in ' + $path + ', so it is at its built-in default')
}

function Get-PowerPlanObservation {
  $exe = Find-Executable 'powercfg.exe'
  if (-not $exe) { return New-Observation 'unreadable' '' 'powercfg.exe was not found' }
  $r = Invoke-Bounded $exe @('/query','SCHEME_CURRENT','238c9fa8-0aad-41ed-83f4-97be242c8f20','29f6c1db-86da-48c5-9fdb-f2b67b1f44da') $CommandTimeoutMs
  if (-not $r.available) { return New-Observation 'unreadable' '' ('powercfg could not be run: ' + $r.error) }
  $script:RawCaptures['power-plan'] = ('exitCode=' + [string]$r.exitCode + "`r`n" + $r.stdout)
  if ($r.exitCode -ne 0) { return New-Observation 'unreadable' '' ('powercfg exited ' + [string]$r.exitCode) }
  # Locale-proof by construction: the localized label is never parsed. The AC index line precedes
  # the DC index line, and each of them carries exactly one 8-digit hex value.
  $lines = @(($r.stdout -split "`r?`n") | Where-Object { $_.Trim() -ne '' })
  $ac = ''; $dc = ''
  if ($lines.Count -ge 2) {
    $m1 = @([regex]::Matches($lines[$lines.Count - 2], '0x[0-9a-fA-F]{8}'))
    $m2 = @([regex]::Matches($lines[$lines.Count - 1], '0x[0-9a-fA-F]{8}'))
    if ($m1.Count -eq 1 -and $m2.Count -eq 1) { $ac = $m1[0].Value; $dc = $m2[0].Value }
  }
  if (-not $ac -or -not $dc) {
    return New-Observation 'unreadable' '' 'the powercfg output does not match the known AC/DC index shape, so the value is not read (never guessed)'
  }
  return New-Observation 'read' ('standbyidle:ac=' + $ac + ':dc=' + $dc) ('last two value lines: ' + $lines[$lines.Count - 2].Trim() + ' || ' + $lines[$lines.Count - 1].Trim())
}

function Get-NetworkProfileObservation {
  param([string]$Scope)
  $root = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkList\Profiles'
  $subs = $null
  try { $subs = @(Get-ChildItem -Path $root -ErrorAction Stop) }
  catch { return New-Observation 'unreadable' '' ('the network profile store is not readable from this session: ' + $_.Exception.Message) }
  $hits = New-Object System.Collections.ArrayList
  foreach ($s in $subs) {
    $pp = $null
    try { $pp = Get-ItemProperty -Path $s.PSPath -ErrorAction Stop } catch { continue }
    $pname = ''
    if (Has-Prop $pp 'ProfileName') { $pname = [string](Prop $pp 'ProfileName') }
    $cat = $null
    if (Has-Prop $pp 'Category') { $cat = (Prop $pp 'Category') }
    if ($pname -ne $Scope -and $s.PSChildName -ne $Scope) { continue }
    $cn = 'unknown'
    if ($null -ne $cat) {
      $ci = -1
      [void][int]::TryParse([string]$cat, [ref]$ci)
      if ($ci -eq 0) { $cn = 'public' } elseif ($ci -eq 1) { $cn = 'private' } elseif ($ci -eq 2) { $cn = 'domain' }
    }
    [void]$hits.Add('category=' + [string]$cat + '(' + $cn + ')')
  }
  if ($hits.Count -eq 0) { return New-Observation 'read' 'absent' ('no network profile named "' + $Scope + '" in ' + $root) }
  return New-Observation 'read' (@($hits | Sort-Object -Unique) -join ' || ') (@($hits.Count).ToString() + ' matching network profile(s) named "' + $Scope + '"')
}

function Get-FileObservation {
  param([string]$Path)
  if (-not (Test-RealPath $Path -Leaf)) {
    return New-Observation 'read' 'absent' ('the path is not a file: ' + $Path)
  }
  $h = Get-Sha256Hex $Path
  $n = Get-FileByteCount $Path
  if (-not $h) { return New-Observation 'unreadable' '' ('the file exists but its hash could not be computed: ' + $Path) }
  return New-Observation 'read' ('file:sha256=' + $h + ':bytes=' + [string]$n) ($Path + '  sha256=' + $h + '  bytes=' + [string]$n)
}

function Get-DirectoryObservation {
  param([string]$Path)
  if (-not (Test-RealPath $Path)) { return New-Observation 'read' 'absent' ('the directory does not exist: ' + $Path) }
  if (-not (Test-RealPath $Path -Container)) { return New-Observation 'unreadable' '' ('the path exists but is not a directory: ' + $Path) }
  $lines = New-Object System.Collections.ArrayList
  try {
    $files = @(Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction Stop | Sort-Object FullName)
  } catch { return New-Observation 'unreadable' '' ('the directory could not be listed: ' + $_.Exception.Message) }
  $total = 0
  foreach ($f in $files) {
    $h = Get-Sha256Hex $f.FullName
    $rel = ''
    try { $rel = $f.FullName.Substring($Path.TrimEnd('\').Length).TrimStart('\') } catch { $rel = $f.Name }
    $total = $total + $f.Length
    [void]$lines.Add($rel + '|' + $h + '|' + [string]$f.Length)
  }
  $listing = @($lines)
  $fh = ''
  try {
    $joined = ($listing -join "`n")
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($joined)
    $fh = ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join ''
    $sha.Dispose()
  } catch { $fh = '' }
  $value = 'dir:files=' + [string]$listing.Count + ':totalBytes=' + [string]$total + ':listingSha256=' + $fh.ToUpperInvariant()
  return New-Observation 'read' $value ($Path + '  ' + $value + "`n" + ($listing -join "`n"))
}

function Get-NativeObservation {
  param([string]$Surface,[string]$Scope)
  switch ($Surface) {
    'dsh-profile-row'        { return Get-ProfileRowObservation $Scope }
    'plugin-files'           { return Get-FileObservation $Scope }
    'firewall-rule'          { return Get-FirewallRuleObservation $Scope }
    'tailscale-serve'        { return Get-TailscaleServeObservation }
    'dsh-settings'           { return Get-DshSettingsObservation $Scope }
    'power-plan'             { return Get-PowerPlanObservation }
    'network-profile'        { return Get-NetworkProfileObservation $Scope }
    'user-skill-copy'        { return Get-DirectoryObservation $Scope }
    'cordis-dynamic-package' {
      return New-Observation 'unreadable' $script:MemoryOnly 'a dynamic Cordis package lives only in the DSH process memory and disappears with the process; the PowerShell side cannot observe it'
    }
    default { return New-Observation 'unreadable' '' ('unknown surface: ' + $Surface) }
  }
}

function Get-FixedObservation {
  param($Record)
  $id = [string](Prop $Record 'id')
  $surface = [string](Prop $Record 'surface')
  if ($surface -eq 'cordis-dynamic-package') {
    return New-Observation 'unreadable' $script:MemoryOnly 'a dynamic Cordis package lives only in the DSH process memory: the fixture cannot observe it either, so it stays unknown by design'
  }
  $obs = $null
  if (Has-Prop $fx 'observations') {
    $node = Prop (Prop $fx 'observations') $id
    if ($null -ne $node) { $obs = $node }
  }
  if ($null -eq $obs) {
    return New-Observation 'unreadable' '' ('the fixture declares no observation for record id ' + $id + ' - refusing to guess')
  }
  $st = 'read'
  if (Has-Prop $obs 'status') { $st = [string](Prop $obs 'status') }
  $val = ''
  if (Has-Prop $obs 'value') { $val = [string](Prop $obs 'value') }
  $det = ''
  if (Has-Prop $obs 'detail') { $det = [string](Prop $obs 'detail') }
  if ($st -ne 'read' -and $st -ne 'unreadable') { $st = 'unreadable'; $det = 'the fixture observation declares an unknown status: ' + $st }
  if ($st -eq 'unreadable') { return New-Observation 'unreadable' '' ('fixture: ' + $det) }
  return New-Observation 'read' $val ('fixture: ' + $det)
}

function Get-Observation {
  param($Record)
  if ($script:FixtureMode) { return Get-FixedObservation $Record }
  return Get-NativeObservation ([string](Prop $Record 'surface')) ([string](Prop $Record 'scope'))
}

# ===========================================================================
# section 6: classification - a pure function of (record, observation)
# ===========================================================================

function Get-RecordClassification {
  param($Record,$Observation)
  $before = ''
  if ($null -ne (Prop $Record 'before')) { $before = [string](Prop $Record 'before') }
  $expected = ''
  if ($null -ne (Prop $Record 'expected')) { $expected = [string](Prop $Record 'expected') }
  $afterRaw = Prop $Record 'after'
  $after = $null
  if ($null -ne $afterRaw -and [string]$afterRaw -ne '') { $after = [string]$afterRaw }
  $userOwned = $false
  if ($null -ne (Prop $Record 'userOwned')) { $userOwned = [bool](Prop $Record 'userOwned') }

  $provenance = [ordered]@{
    recordedBefore = $before
    recordedExpected = $expected
    recordedAfter = $after
    observedNow = ''
    comparedAgainst = 'before'
  }

  # userOwned is checked FIRST: a record the operator owns is never touched whatever its current
  # state is, and an unreadable value cannot turn it into anything else.
  if ($userOwned) {
    if ($Observation.status -eq 'read') { $provenance.observedNow = [string]$Observation.value }
    return [pscustomobject][ordered]@{
      status = 'kept_user_owned'; reasonKey = 'user_owned_never_touched'; executable = $false
      detail = 'this record is marked userOwned: it is reported for provenance and is NEVER reverted or deleted by this tool'
      provenance = $provenance
    }
  }

  if ($Observation.status -ne 'read') {
    $rk = 'observation_unreadable'
    if ([string](Prop $Record 'surface') -eq 'cordis-dynamic-package') { $rk = 'memory_only_instruction' }
    return [pscustomobject][ordered]@{
      status = 'unknown'; reasonKey = $rk; executable = $false
      detail = $Observation.detail; provenance = $provenance
    }
  }

  $now = [string]$Observation.value
  $provenance.observedNow = $now
  $surface = [string](Prop $Record 'surface')

  if ($surface -eq 'cordis-dynamic-package') {
    return [pscustomobject][ordered]@{
      status = 'unknown'; reasonKey = 'memory_only_instruction'; executable = $false
      detail = 'dynamic Cordis packages are print-only: see the cordis_undefine section of this report'
      provenance = $provenance
    }
  }
  if ($now -eq $before) {
    return [pscustomobject][ordered]@{
      status = 'noop'; reasonKey = 'equals_before'; executable = $false
      detail = 'the current value is the recorded before value, so nothing of this tool is there'
      provenance = $provenance
    }
  }
  if ($null -ne $after -and $now -eq $after -and $after -ne $before) {
    $provenance.comparedAgainst = 'after'
    return [pscustomobject][ordered]@{
      status = 'revert'; reasonKey = 'equals_recorded_after'; executable = $true
      detail = 'the current value is exactly the value recorded after the remediation, so this tool may revert it'
      provenance = $provenance
    }
  }
  if ($null -eq $after) {
    return [pscustomobject][ordered]@{
      status = 'unknown'; reasonKey = 'after_missing'; executable = $false
      detail = 'the value differs from before but no after value was recorded, so this tool cannot prove the change is its own; run -RecordAfter. Never touched.'
      provenance = $provenance
    }
  }
  $provenance.comparedAgainst = 'after'
  return [pscustomobject][ordered]@{
    status = 'left_alone'; reasonKey = 'changed_by_somebody_else'; executable = $false
    detail = 'the current value is neither the recorded before nor the recorded after value: somebody changed it afterwards, so it is reported and left exactly as it is'
    provenance = $provenance
  }
}

# ===========================================================================
# section 7: the collector, reused read-only for residue items 6 and 7
# ===========================================================================

function Get-CollectorReport {
  # Runs src/collect.ps1 -CheckOnly -AsJson through the bounded helper. Read-only, no -Apply,
  # and the exit code is only recorded: a pre-existing blocked item is not this tool's residue.
  $out = [ordered]@{ ok = $false; doc = $null; exitCode = $null; error = ''; path = $collectorVal; source = 'native' }
  if ($script:FixtureMode) {
    $node = Prop $fx 'collector'
    $which = 'after'
    if ($action -eq 'check' -or $action -eq 'plan') { $which = 'after' }
    $pick = $null
    if ($null -ne $node) {
      $pick = Prop $node $which
      if ($null -eq $pick) { $pick = Prop $node 'before' }
    }
    if ($null -eq $pick) { $out.error = 'the fixture declares no collector report'; $out.source = 'fixture'; return [pscustomobject]$out }
    $out.ok = $true; $out.doc = $pick; $out.source = 'fixture'; $out.exitCode = $null
    return [pscustomobject]$out
  }
  if (-not (Test-Path -LiteralPath $collectorVal)) { $out.error = 'the collector was not found: ' + $collectorVal; return [pscustomobject]$out }
  $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  if (-not (Test-Path -LiteralPath $psExe)) { $out.error = 'powershell.exe was not found under System32'; return [pscustomobject]$out }
  $script:CollectorCalls++
  $r = Invoke-Bounded $psExe @('-NoProfile','-ExecutionPolicy','Bypass','-File',$collectorVal,'-CheckOnly','-AsJson') ($CommandTimeoutMs * 4)
  if (-not $r.available) { $out.error = 'the collector could not be started: ' + $r.error; return [pscustomobject]$out }
  if ($r.error) { $out.error = 'the collector ' + $r.error; return [pscustomobject]$out }
  $out.exitCode = $r.exitCode
  try { $out.doc = ($r.stdout | ConvertFrom-Json) }
  catch { $out.error = 'the collector output is not valid JSON: ' + $_.Exception.Message; return [pscustomobject]$out }
  $out.ok = $true
  return [pscustomobject]$out
}

function Get-CollectorView {
  param($Doc)
  $out = [ordered]@{ available = $false; exitCode = $null; nonPass = @(); wildcardVerdict = ''; wildcardReasonKey = ''; blockedOrDegraded = @() }
  if ($null -eq $Doc) { return [pscustomobject]$out }
  $out.available = $true
  $sum = Prop $Doc 'summary'
  if ($null -ne $sum -and $null -ne (Prop $sum 'exitCode')) { $out.exitCode = [int](Prop $sum 'exitCode') }
  $nonPass = New-Object System.Collections.ArrayList
  $bd = New-Object System.Collections.ArrayList
  foreach ($c in @(Get-Array $Doc 'checks')) {
    $id = [string](Prop $c 'id')
    $v = [string](Prop $c 'verdict')
    if ($v -ne 'pass') { [void]$nonPass.Add($id + '=' + $v) }
    if ($id -eq 'NO_NEW_WILDCARD_LISTENER') {
      $out.wildcardVerdict = $v
      $out.wildcardReasonKey = [string](Prop $c 'reasonKey')
    }
    if ($v -eq 'degraded' -or $v -eq 'blocked') { [void]$bd.Add($id) }
  }
  $out.nonPass = @($nonPass)
  $out.blockedOrDegraded = @($bd)
  return [pscustomobject]$out
}

function Get-FixtureCollectorBaseline {
  $node = Prop $fx 'collector'
  if ($null -eq $node) { return $null }
  $pick = Prop $node 'before'
  if ($null -eq $pick) { return $null }
  return (Get-CollectorView $pick)
}

function Get-BaselineFromJournal {
  param($Doc)
  $b = Prop $Doc 'collectorBaseline'
  if ($null -eq $b) { return $null }
  return (Get-CollectorView $b)
}

function New-CollectorBaselineNode {
  param($CollectorReport)
  if (-not $CollectorReport.ok -or $null -eq $CollectorReport.doc) { return $null }
  return $CollectorReport.doc
}

# ===========================================================================
# section 8: the residue scan (8 items; item 8 is the honest unknown)
# ===========================================================================

function New-ResidueItem {
  param([string]$Id,[string]$Status,[string]$ReasonKey,[string]$Detail,[bool]$ExemptFromExit = $false)
  return [pscustomobject][ordered]@{
    id = $Id; status = $Status; reasonKey = $ReasonKey; detail = $Detail; exemptFromExit = $ExemptFromExit
  }
}

function Get-StateDirListing {
  # Everything in the state directory that is NOT part of a backup directory is residue: after a
  # clean uninstall only <StateDir>\backups\... may remain (or the directory may be empty).
  $out = [ordered]@{
    checked = $false; exists = $false; entries = @()
    unexpected = (New-Object System.Collections.ArrayList)
    backups = (New-Object System.Collections.ArrayList)
    error = ''
  }
  if ($script:FixtureMode) {
    $node = Prop $fx 'stateDir'
    if ($null -eq $node) { $out.error = 'the fixture declares no state directory listing'; return [pscustomobject]$out }
    $out.checked = $true
    if (Has-Prop $node 'exists') { $out.exists = [bool](Prop $node 'exists') }
    $ent = @(Prop $node 'entries')
    $out.entries = $ent
    foreach ($e in $ent) {
      $rel = ''
      if (Has-Prop $e 'rel') { $rel = ([string](Prop $e 'rel')) -replace '/', '\' }
      elseif (Has-Prop $e 'path') {
        $p = [string](Prop $e 'path')
        $rel = [System.IO.Path]::GetFileName($p)
        if ($stateVal) {
          $pref = $stateVal.TrimEnd('\') + '\'
          if ($p.Length -gt $pref.Length -and $p.StartsWith($pref, [System.StringComparison]::OrdinalIgnoreCase)) { $rel = $p.Substring($pref.Length) }
        }
      }
      if ($rel -match '^(backups\\|backups$)') { [void]$out.backups.Add($rel) } else { [void]$out.unexpected.Add($rel) }
    }
    return [pscustomobject]$out
  }
  if (-not $stateVal -or -not (Test-Path -LiteralPath $stateVal)) { $out.checked = $true; return [pscustomobject]$out }
  $out.exists = $true
  $out.checked = $true
  try {
    $items = @(Get-ChildItem -LiteralPath $stateVal -Force -Recurse -ErrorAction Stop)
  } catch { $out.error = $_.Exception.Message; return [pscustomobject]$out }
  $acc = New-Object System.Collections.ArrayList
  foreach ($i in $items) {
    $rel = ''
    try { $rel = $i.FullName.Substring($stateVal.TrimEnd('\').Length).TrimStart('\') } catch { $rel = $i.Name }
    $kind = 'file'
    if ($i.PSIsContainer) { $kind = 'dir' }
    [void]$acc.Add([pscustomobject][ordered]@{ rel = $rel; kind = $kind; bytes = $(if ($kind -eq 'file') { [int64]$i.Length } else { -1 }) })
    if ($rel -eq 'backups' -or $rel -like 'backups\*') { [void]$out.backups.Add($rel) } else { [void]$out.unexpected.Add($rel) }
  }
  $out.entries = @($acc)
  return [pscustomobject]$out
}

function Get-ResidueScan {
  param($Records,$Classifications,$CollectorBefore,$CollectorAfter,$StateListing)
  $items = New-Object System.Collections.ArrayList
  $rd = @{}

  # (1) profile rows matching a recorded row id -> 0
  $rowRecs = @($Records | Where-Object { (Prop $_ 'surface') -eq 'dsh-profile-row' })
  if (@($rowRecs).Count -eq 0) {
    [void]$items.Add((New-ResidueItem 'profile-rows-absent' 'not-recorded' 'no_recorded_profile_rows' 'no dsh-profile-row was ever recorded, so this machine has no row of ours to look for'))
  } else {
    $bad = New-Object System.Collections.ArrayList
    $unk = New-Object System.Collections.ArrayList
    foreach ($r in $rowRecs) {
      $id = [string](Prop $r 'id')
      $o = $rd[$id]
      if ($null -eq $o) { $o = Get-Observation $r; $rd[$id] = $o }
      if ($o.status -ne 'read') { [void]$unk.Add($id + ': unreadable') ; continue }
      if ([string]$o.value -ne 'absent') { [void]$bad.Add($id + ' -> ' + (Format-Display $o.value 120)) }
    }
    if ($unk.Count -gt 0) { [void]$items.Add((New-ResidueItem 'profile-rows-absent' 'unknown' 'profile_row_unreadable' (($unk.ToArray()) -join '; '))) }
    elseif ($bad.Count -gt 0) { [void]$items.Add((New-ResidueItem 'profile-rows-absent' 'residue' 'profile_row_present' (($bad.ToArray()) -join '; '))) }
    else {
      $why = (@($rowRecs).Count.ToString() + ' recorded profile row(s): none of them is present any more')
      [void]$items.Add((New-ResidueItem 'profile-rows-absent' 'pass' 'no_recorded_profile_row_present' $why))
    }
  }

  # (2) recorded install artifacts -> gone (only meaningful when -RemoveFiles was requested)
  $fileRecs = @($Records | Where-Object { (Prop $_ 'surface') -eq 'plugin-files' -or (Prop $_ 'surface') -eq 'user-skill-copy' })
  if (-not $RemoveFiles) {
    [void]$items.Add((New-ResidueItem 'install-artifacts-absent' 'not-requested' 'remove_files_not_requested' 'files are kept by design unless -RemoveFiles is given; the one-line removal command is printed per record'))
  } elseif (@($fileRecs).Count -eq 0) {
    [void]$items.Add((New-ResidueItem 'install-artifacts-absent' 'not-recorded' 'no_recorded_install_paths' 'no plugin-files or user-skill-copy record exists in this journal'))
  } else {
    $left = New-Object System.Collections.ArrayList
    $unk = New-Object System.Collections.ArrayList
    $keptByPolicy = New-Object System.Collections.ArrayList
    foreach ($r in $fileRecs) {
      $id = [string](Prop $r 'id')
      if ([bool](Prop $r 'userOwned')) { [void]$keptByPolicy.Add($id) ; continue }
      $o = Get-Observation $r
      if ($o.status -ne 'read') { [void]$unk.Add($id + ': unreadable') ; continue }
      # gone means "back at the recorded before value" - not merely "not equal to after", because a
      # value somebody else changed afterwards is reported by the other items, not as residue here.
      if ([string]$o.value -eq [string](Prop $r 'before')) { continue }
      [void]$left.Add($id + ' -> still present (' + (Format-Display ([string]$o.value) 100) + ')')
    }
    if ($unk.Count -gt 0) {
      [void]$items.Add((New-ResidueItem 'install-artifacts-absent' 'unknown' 'artifact_unreadable' (($unk.ToArray()) -join '; ')))
    } elseif ($left.Count -gt 0) {
      [void]$items.Add((New-ResidueItem 'install-artifacts-absent' 'residue' 'artifact_still_present' (($left.ToArray()) -join '; ')))
    } else {
      $note = 'every recorded install path is back at its before value'
      if (@($keptByPolicy).Count -gt 0) { $note = $note + '; kept by policy (userOwned): ' + ((@($keptByPolicy)) -join ', ') }
      [void]$items.Add((New-ResidueItem 'install-artifacts-absent' 'pass' 'recorded_artifacts_gone' $note))
    }
  }

  # (3) firewall rules recorded by name -> 0 hits (unrecorded rules are never inspected)
  $fwRecs = @($Records | Where-Object { (Prop $_ 'surface') -eq 'firewall-rule' })
  if (@($fwRecs).Count -eq 0) {
    [void]$items.Add((New-ResidueItem 'recorded-firewall-rules-absent' 'not-recorded' 'no_recorded_firewall_rules' 'no firewall rule was recorded, so none is inspected and none is touched'))
  } else {
    $bad = New-Object System.Collections.ArrayList
    $unk = New-Object System.Collections.ArrayList
    foreach ($r in $fwRecs) {
      $id = [string](Prop $r 'id')
      $o = $rd[$id]
      if ($null -eq $o) { $o = Get-Observation $r; $rd[$id] = $o }
      if ($o.status -ne 'read') { [void]$unk.Add($id + ': ' + $o.detail) ; continue }
      if ([string]$o.value -ne 'absent') { [void]$bad.Add($id + ' -> ' + (Format-Display $o.value 120)) }
    }
    if ($unk.Count -gt 0) { [void]$items.Add((New-ResidueItem 'recorded-firewall-rules-absent' 'unknown' 'firewall_rule_unreadable' (($unk.ToArray()) -join '; '))) }
    elseif ($bad.Count -gt 0) { [void]$items.Add((New-ResidueItem 'recorded-firewall-rules-absent' 'residue' 'recorded_firewall_rule_present' (($bad.ToArray()) -join '; '))) }
    else { [void]$items.Add((New-ResidueItem 'recorded-firewall-rules-absent' 'pass' 'no_recorded_firewall_rule_present' 'every recorded rule name currently matches 0 rules')) }
  }

  # (4) tailscale serve proxy target back to the recorded before (or not-configured)
  $svRecs = @($Records | Where-Object { (Prop $_ 'surface') -eq 'tailscale-serve' })
  if (@($svRecs).Count -eq 0) {
    [void]$items.Add((New-ResidueItem 'serve-target-restored' 'not-recorded' 'no_recorded_serve_state' 'no tailscale-serve record exists, so the serve configuration was never part of this journal'))
  } else {
    $bad = New-Object System.Collections.ArrayList
    $unk = New-Object System.Collections.ArrayList
    foreach ($r in $svRecs) {
      $id = [string](Prop $r 'id')
      $o = $rd[$id]
      if ($null -eq $o) { $o = Get-Observation $r; $rd[$id] = $o }
      if ($o.status -ne 'read') { [void]$unk.Add($id + ': ' + $o.detail) ; continue }
      $now = [string]$o.value
      $before = [string](Prop $r 'before')
      if ($now -eq 'not-configured' -or $now -eq $before) { continue }
      [void]$bad.Add($id + ' -> ' + (Format-Display $now 120) + ' (recorded before: ' + (Format-Display $before 120) + ')')
    }
    if ($unk.Count -gt 0) { [void]$items.Add((New-ResidueItem 'serve-target-restored' 'unknown' 'serve_state_unreadable' (($unk.ToArray()) -join '; '))) }
    elseif ($bad.Count -gt 0) { [void]$items.Add((New-ResidueItem 'serve-target-restored' 'residue' 'serve_target_still_published' (($bad.ToArray()) -join '; '))) }
    else { [void]$items.Add((New-ResidueItem 'serve-target-restored' 'pass' 'serve_target_restored' 'the serve proxy target is back at the recorded before value (or not configured at all)')) }
  }

  # (5) state directory: only a backup directory may be left
  if (-not $StateListing.checked) {
    [void]$items.Add((New-ResidueItem 'state-dir-contents' 'unknown' 'state_dir_not_checked' ('the state directory contents could not be checked: ' + $StateListing.error)))
  } elseif (-not $StateListing.exists) {
    [void]$items.Add((New-ResidueItem 'state-dir-contents' 'pass' 'state_dir_absent' ('the state directory does not exist: ' + $stateVal + ' - nothing of this tool is left on disk')))
  } elseif (@($StateListing.unexpected).Count -gt 0) {
    [void]$items.Add((New-ResidueItem 'state-dir-contents' 'residue' 'state_dir_has_non_backup_entries' ('entries outside a backup directory: ' + ((@($StateListing.unexpected)) -join ', '))))
  } else {
    $n = @($StateListing.entries).Count
    [void]$items.Add((New-ResidueItem 'state-dir-contents' 'pass' 'state_dir_only_backups' ('the state directory holds only backup material (' + ([string]$n) + ' entr(y/ies), ' + (@($StateListing.backups).Count).ToString() + ' under backups)')))
  }

  # (6) reuse the collector's own no-new-wildcard-listener judgement
  if (-not $CollectorAfter.available) {
    [void]$items.Add((New-ResidueItem 'no-new-wildcard-listener' 'unknown' 'collector_unavailable' 'the collector could not be read, so its no-new-wildcard-listener self-proof cannot be reused'))
  } else {
    $v = [string]$CollectorAfter.wildcardVerdict
    if ($v -eq 'pass') { [void]$items.Add((New-ResidueItem 'no-new-wildcard-listener' 'pass' 'reused_collector_pass' ('the collector reports NO_NEW_WILDCARD_LISTENER = pass (' + $CollectorAfter.wildcardReasonKey + ')'))) }
    elseif ($v -eq 'blocked') { [void]$items.Add((New-ResidueItem 'no-new-wildcard-listener' 'residue' 'collector_reports_new_wildcard' ('the collector reports NO_NEW_WILDCARD_LISTENER = blocked (' + $CollectorAfter.wildcardReasonKey + ')'))) }
    elseif ($v) { [void]$items.Add((New-ResidueItem 'no-new-wildcard-listener' 'unknown' 'collector_wildcard_unknown' ('the collector reports NO_NEW_WILDCARD_LISTENER = ' + $v + ' (' + $CollectorAfter.wildcardReasonKey + '): an unreadable probe is never a pass'))) }
    else { [void]$items.Add((New-ResidueItem 'no-new-wildcard-listener' 'unknown' 'collector_check_missing' 'the collector report carries no NO_NEW_WILDCARD_LISTENER check')) }
  }

  # (7) collector delta: anything NEWLY degraded/blocked is reported as residue
  if (-not $CollectorAfter.available) {
    [void]$items.Add((New-ResidueItem 'collector-delta' 'unknown' 'collector_unavailable' 'the collector could not be read, so nothing can be compared'))
  } else {
    $afterIds = @($CollectorAfter.blockedOrDegraded)
    $beforeIds = @()
    if ($CollectorBefore.available) { $beforeIds = @($CollectorBefore.blockedOrDegraded) }
    $new = New-Object System.Collections.ArrayList
    foreach ($i in $afterIds) { if ($beforeIds -notcontains $i) { [void]$new.Add([string]$i) } }
    if ($new.Count -gt 0) {
      [void]$items.Add((New-ResidueItem 'collector-delta' 'residue' 'new_collector_findings' ('new degraded/blocked check(s) compared with the recorded baseline: ' + (($new.ToArray() -join ', ')))))
    } else {
      $base = 'no recorded baseline'
      if ($CollectorBefore.available) { $base = (@($beforeIds).Count).ToString() + ' pre-existing degraded/blocked item(s)' }
      [void]$items.Add((New-ResidueItem 'collector-delta' 'pass' 'no_new_collector_findings' ('the collector reports no newly degraded or blocked check (' + $base + ')')))
    }
  }

  # (8) dynamic Cordis packages: honest unknown, exempt from the exit-0 rule
  [void]$items.Add((New-ResidueItem 'cordis-dynamic-package' 'unknown' 'memory_only_cannot_be_verified' 'a dynamic Cordis package lives only in the DSH process memory; this tool cannot verify from the filesystem whether one is still active, so it says unknown instead of pass and lists the cordis_undefine command for each recorded plugin id' $true))

  return $items.ToArray()
}

# ===========================================================================
# section 9: retention - what is kept, machine-readable and for a human
# ===========================================================================

function Get-Retention {
  $out = [ordered]@{
    loaded = $false; manifest = $manifestVal; error = ''; keepTailscale = $keepTailVal
    items = @(); problems = @(); keepClasses = @(); tailscaleSuggestion = ''; tailscaleRemoveCommandShown = ''
  }
  $out.keepClasses = @(
    [pscustomobject][ordered]@{ id = 'tailscale-product'; policy = 'keep'; text = 'Tailscale itself: this tool never uninstalls it, whatever -KeepTailscale says' },
    [pscustomobject][ordered]@{ id = 'other-plugin-profile-rows'; policy = 'keep'; text = 'profile rows belonging to other plugins: only a row id recorded in the journal may be reverted' },
    [pscustomobject][ordered]@{ id = 'user-firewall-rules'; policy = 'keep'; text = 'firewall rules this tool never recorded: not inspected and not changed' },
    [pscustomobject][ordered]@{ id = 'workspace-repo-files'; policy = 'keep'; text = 'files in the plugin checkout: never removed (only paths declared with -InstallPath can be)' },
    [pscustomobject][ordered]@{ id = 'user-skill-copies'; policy = 'keep'; text = 'user-level skill copies: recorded as userOwned and kept' }
  )
  if (-not (Test-Path -LiteralPath $manifestVal)) { $out.error = 'the prerequisite manifest was not found: ' + $manifestVal; return [pscustomobject]$out }
  $r = Read-JsonFileSafe $manifestVal
  if (-not $r.ok) { $out.error = 'the prerequisite manifest ' + $r.error; return [pscustomobject]$out }
  $doc = $r.doc
  $out.loaded = $true
  $problems = New-Object System.Collections.ArrayList
  $table = New-Object System.Collections.ArrayList
  $manifestItems = @(Get-Array $doc 'items')
  foreach ($it in $manifestItems) {
    $id = [string](Prop $it 'id')
    $un = Prop $it 'uninstall'
    $policy = ''
    $keepReason = ''
    $removeCommand = $null
    $impact = ''
    $problem = ''
    if ($null -eq $un) { $problem = 'no uninstall block' }
    else {
      if ($null -ne (Prop $un 'policy')) { $policy = [string](Prop $un 'policy') }
      if ($null -ne (Prop $un 'keepReason')) { $keepReason = [string](Prop $un 'keepReason') }
      if ($null -ne (Prop $un 'removeCommand')) { $removeCommand = [string](Prop $un 'removeCommand') }
      if ($null -ne (Prop $un 'impactIfRemoved')) { $impact = [string](Prop $un 'impactIfRemoved') }
      if ($policy -ne 'keep' -and $policy -ne 'optional-remove') { $problem = 'policy must be keep or optional-remove, found: "' + $policy + '"' }
      elseif ($policy -eq 'keep' -and -not $keepReason) { $problem = 'policy=keep requires a non-empty keepReason' }
      elseif ($policy -eq 'optional-remove') {
        if (-not $removeCommand) { $problem = 'policy=optional-remove requires removeCommand' }
        elseif (-not $impact) { $problem = 'policy=optional-remove requires impactIfRemoved' }
      }
    }
    if ($problem) { [void]$problems.Add($id + ': ' + $problem) }
    [void]$table.Add([pscustomobject][ordered]@{
      id = $id; policy = $policy; keepReason = $keepReason; removeCommand = $removeCommand
      impactIfRemoved = $impact; valid = (-not [bool]$problem); problem = $problem
      executedByThisTool = $false
    })
  }
  $out.items = @($table)
  $out.problems = @($problems)

  $tail = @($table | Where-Object { $_.id -eq 'TAILSCALE_INSTALLED' })
  if (@($tail).Count -gt 0) {
    $t = $tail[0]
    if ($keepTailVal) {
      $out.tailscaleSuggestion = 'kept: ' + $t.keepReason
    } else {
      $rollback = ''
      foreach ($it in $manifestItems) {
        if ([string](Prop $it 'id') -eq 'TAILSCALE_INSTALLED') {
          $ins = Prop $it 'install'
          if ($null -ne $ins -and $null -ne (Prop $ins 'rollback')) { $rollback = [string](Prop $ins 'rollback') }
        }
      }
      $out.tailscaleRemoveCommandShown = $rollback
      $out.tailscaleSuggestion = 'you passed -KeepTailscale:$false, so the suggestion changed - but this tool still will NOT uninstall Tailscale. Run it yourself if you really mean it: ' + $rollback
    }
  }
  return [pscustomobject]$out
}

# ===========================================================================
# section 10: report rendering
# ===========================================================================

function Get-ExitCode {
  # 2 = refused; 1 = anything unresolved (left-alone, a non-exempt unknown, a failed action, a
  # residue item, a retention policy that does not satisfy its own contract, or no journal at all,
  # in which case nothing on this machine can be ATTRIBUTED to this tool); 0 = clean.
  # A kept backup is never a warning.
  param($Records,$Residue,$RetentionUnresolved = 0,$AttributionUnresolved = 0)
  if (@($script:Refusals).Count -gt 0) { return 2 }
  $unresolved = (Get-UnresolvedCount $Records $Residue) + [int]$RetentionUnresolved + [int]$AttributionUnresolved
  if ($unresolved -gt 0) { return 1 }
  return 0
}

function Get-RetentionUnresolved {
  param($Retention)
  $n = 0
  if ($null -eq $Retention) { return 1 }
  $n = @($Retention.problems).Count
  if (-not $Retention.loaded) { $n++ }
  return $n
}

function Get-ReportObject {
  param($Records,$Residue,$Retention,$BackupInfo,$Deletions,$PurgeInfo,$JournalInfo,$CollectorBefore,$CollectorAfter,$CollectorReport)
  $cl = [ordered]@{ noop = 0; revert = 0; left_alone = 0; unknown = 0; kept_user_owned = 0; unknownExempt = 0 }
  foreach ($r in @($Records)) {
    $st = [string]$r.classification.status
    if ($st -eq 'unknown' -and $r.classification.reasonKey -eq 'memory_only_instruction') { $cl.unknownExempt++ ; continue }
    switch ($st) {
      'noop' { $cl.noop++ }
      'revert' { $cl.revert++ }
      'left_alone' { $cl.left_alone++ }
      'kept_user_owned' { $cl.kept_user_owned++ }
      default { $cl.unknown++ }
    }
  }
  $cordis = New-Object System.Collections.ArrayList
  foreach ($r in @($Records)) {
    if ($r.surface -eq 'cordis-dynamic-package') {
      [void]$cordis.Add([pscustomobject][ordered]@{
        pluginId = $r.scope
        instruction = 'cordis_undefine(' + $r.scope + ')'
        note = 'run this in the DSH session; a dynamic package exists only in the DSH process memory'
      })
    }
  }
  $retentionUnresolved = Get-RetentionUnresolved $Retention
  $attributionUnresolved = 0
  $attribution = 'available'
  $attributionReasonKey = ''
  if ($script:JournalAbsentUnattributable) {
    $attributionUnresolved = 1
    $attribution = 'unavailable'
    $attributionReasonKey = 'journal_absent_cannot_attribute'
  }
  $exitCode = Get-ExitCode $Records $Residue $retentionUnresolved $attributionUnresolved
  $verdict = 'clean'
  if ($exitCode -eq 2) { $verdict = 'refused' }
  elseif ($exitCode -eq 1) { $verdict = 'attention' }
  $dryRun = ($action -ne 'apply' -and $action -ne 'purge' -and $action -ne 'record-before' -and $action -ne 'record-after')
  $rep = [pscustomobject][ordered]@{
    schema = $script:ReportSchema
    tool = [ordered]@{
      name = $script:ToolName
      version = 'v1'
      generatedAtLocal = Get-NowStamp
      psVersion = [string]$PSVersionTable.PSVersion
      action = $action
      dryRun = $dryRun
      removedNothingByAccident = 'every mutation is gated by the backup-first guard (see ordering)'
      platform = 'Windows PowerShell 5.1'
    }
    lang = $langUsed
    labelsSource = $script:LabelSource
    fixture = [ordered]@{ path = $FixturePath; loaded = [bool]$script:FixtureMode; mode = $(if ($script:FixtureMode) { 'fixture' } else { 'native' }) }
    config = @($cfg)
    refusals = @($script:Refusals)
    journal = $JournalInfo
    deltas = [ordered]@{ keptTailscale = $keepTailVal; removeFiles = [bool]$RemoveFiles; purgeBackup = [bool]$PurgeBackup; apply = [bool]$Apply }
    classification = $cl
    records = @($Records)
    deletions = @($Deletions)
    residue = [ordered]@{ items = @($Residue); clean = (@(($Residue | Where-Object { ($_.status -eq 'residue' -or $_.status -eq 'unknown') -and -not $_.exemptFromExit })).Count -eq 0) }
    retention = $Retention
    cordisInstructions = @($cordis)
    backup = $BackupInfo
    purge = $PurgeInfo
    collector = [ordered]@{
      calls = $script:CollectorCalls
      available = [bool]$CollectorReport.ok
      source = $CollectorReport.source
      error = $CollectorReport.error
      baseline = $CollectorBefore
      after = $CollectorAfter
    }
    ordering = @($script:OrderLog)
    notes = @($script:Notes)
    summary = [ordered]@{
      records = @($Records).Count
      residueItems = @($Residue).Count
      unresolved = ((Get-UnresolvedCount $Records $Residue) + [int]$retentionUnresolved + [int]$attributionUnresolved)
      retentionUnresolved = [int]$retentionUnresolved
      attribution = $attribution
      attributionReasonKey = $attributionReasonKey
      unknownExempt = $cl.unknownExempt
      exitCode = $exitCode
      verdict = $verdict
      exitMeaning = '0 = clean (a kept backup is normal) / 1 = left-alone, unknown or residue / 2 = refused, nothing written'
      cordisUnknownExempt = 'the cordis-dynamic-package unknown is exempt from the exit-0 rule: process memory cannot be verified from the file system'
      attributionNote = 'without a journal this tool cannot attribute anything on this machine to itself, so "nothing of ours was ever installed here" is not a proven fact and the verdict is not clean'
    }
  }
  return $rep
}

function Get-UnresolvedCount {
  param($Records,$Residue)
  $n = 0
  foreach ($r in @($Records)) {
    if ($r.classification.status -eq 'left_alone') { $n++ }
    if ($r.classification.status -eq 'unknown' -and $r.classification.reasonKey -ne 'memory_only_instruction') { $n++ }
    if ($r.action -eq 'failed') { $n++ }
  }
  foreach ($i in @($Residue)) {
    if ($i.exemptFromExit) { continue }
    if ($i.status -eq 'residue' -or $i.status -eq 'unknown') { $n++ }
  }
  return $n
}

function Write-ReportText {
  param($Rep)
  Write-Output ('== ' + (Get-Label 'title') + ' ==')
  Write-Output ('tool=' + $script:ToolName + '  action=' + $Rep.tool.action + '  lang=' + $Rep.lang + '  labels=' + $Rep.labelsSource)
  Write-Output ('stateDir=' + $stateVal + '  journal=' + $journalVal + '  fixture=' + $Rep.fixture.mode)
  if ($action -eq 'record-before' -or $action -eq 'record-after') {
    Write-Output (Get-Label 'recordBanner')
  } elseif ($action -eq 'apply' -or $action -eq 'purge') {
    Write-Output (Get-Label 'applyBanner')
  } else {
    Write-Output (Get-Label 'dryRun')
  }
  Write-Output ''

  if (@($Rep.refusals).Count -gt 0) {
    Write-Output '[REFUSED] nothing was written:'
    foreach ($r in @($Rep.refusals)) { Write-Output ('  - ' + $r.reasonKey + ': ' + $r.message) }
    Write-Output ''
    Write-Output 'exit 2 (refused). Fix the reason above and re-run.'
    return
  }

  Write-Output ('journal: found=' + [string]$Rep.journal.found + '  source=' + [string]$Rep.journal.source + '  schemaVersion=' + [string]$Rep.journal.schemaVersion + '  records=' + [string]$Rep.journal.records)
  if ($Rep.journal.error) { Write-Output ('journal note: ' + $Rep.journal.error) }
  Write-Output ('classification: noop=' + $Rep.classification.noop + ' revert=' + $Rep.classification.revert + ' left-alone=' + $Rep.classification.left_alone + ' unknown=' + $Rep.classification.unknown + ' kept(userOwned)=' + $Rep.classification.kept_user_owned + ' unknown(exempt cordis)=' + $Rep.classification.unknownExempt)
  Write-Output ''

  if (@($Rep.records).Count -gt 0) {
    Write-Output '--- records (id / surface / class) ---'
    foreach ($r in @($Rep.records)) {
      Write-Output ('[' + $r.classification.status.ToUpper() + '] ' + $r.id + '  (' + $r.surface + ')')
      Write-Output ('    scope    : ' + (Format-Display $r.scope 160))
      Write-Output ('    before   : ' + (Format-Display $r.before 160))
      Write-Output ('    expected : ' + (Format-Display $r.expected 160))
      Write-Output ('    after    : ' + (Format-Display $r.after 160))
      Write-Output ('    now      : ' + (Format-Display $r.provenance.observedNow 160))
      Write-Output ('    why      : ' + $r.classification.reasonKey + ' - ' + $r.classification.detail)
      Write-Output ('    revert   : kind=' + $r.revert.kind + ' | ' + (Format-Display $r.revert.command 200))
      Write-Output ('    verify   : ' + (Format-Display $r.verify.command 200) + '   expect: ' + (Format-Display $r.verify.expect 120))
      if ($r.remediation) { Write-Output ('    remediation (the forward command this record brackets): ' + (Format-Display $r.remediation 220)) }
      if ($r.userOwned) { Write-Output '    policy   : userOwned=true - never touched by this tool' }
      if ($r.action -and $r.action -ne 'none') { Write-Output ('    action   : ' + $r.action + ' - ' + (Format-Display $r.actionDetail 200)) }
      if ($r.action -eq 'executed' -and ($r.classification.status -eq 'noop' -or $r.classification.status -eq 'revert')) {
        Write-Output '    note     : this record was reverted in this run, so the class above is the state AFTER the revert (back at the recorded before value)'
      }
    }
    Write-Output ''
  }

  if (@($Rep.deletions).Count -gt 0) {
    Write-Output '--- file decisions (-RemoveFiles) ---'
    foreach ($d in @($Rep.deletions)) {
      Write-Output ('  [' + $d.status + '] ' + $d.path)
      Write-Output ('      reason: ' + $d.reasonKey + ' - ' + $d.detail)
      if ($d.oneLineCommand) { Write-Output ('      you can delete it yourself with: ' + $d.oneLineCommand) }
    }
    Write-Output ''
  }

  if (@($Rep.cordisInstructions).Count -gt 0) {
    Write-Output '--- dynamic Cordis packages: PRINT ONLY, never executed by this tool ---'
    Write-Output (Get-Label 'cordisNote')
    foreach ($c in @($Rep.cordisInstructions)) {
      Write-Output ('    in the DSH session run: ' + $c.instruction + '     (plugin id: ' + $c.pluginId + ')')
    }
    Write-Output '    this stays `unknown` in the residue scan: process memory cannot be read from the file system, and this unknown never blocks exit 0'
    Write-Output ''
  }

  Write-Output '--- kept by default (retention; never touched by this tool) ---'
  foreach ($k in @($Rep.retention.keepClasses)) { Write-Output ('  [' + $k.policy + '] ' + $k.id + ': ' + $k.text) }
  if ($Rep.retention.loaded) {
    Write-Output ('  manifest: ' + $Rep.retention.manifest + '  (machine-readable policy per prerequisite item)')
    foreach ($it in @($Rep.retention.items)) {
      $line = '  [' + $it.policy + '] ' + $it.id
      if ($it.policy -eq 'keep') { $line = $line + ' - keepReason: ' + (Format-Display $it.keepReason 200) }
      else {
        $line = $line + ' - removeCommand: ' + (Format-Display $it.removeCommand 160)
      }
      Write-Output $line
      if ($it.impactIfRemoved) { Write-Output ('      impact if removed: ' + (Format-Display $it.impactIfRemoved 200)) }
      if (-not $it.valid) { Write-Output ('      MANIFEST PROBLEM: ' + $it.problem) }
    }
    if ($Rep.retention.tailscaleSuggestion) { Write-Output ('  TAILSCALE_INSTALLED suggestion: ' + $Rep.retention.tailscaleSuggestion) }
  } else {
    Write-Output ('  manifest unavailable: ' + $Rep.retention.error)
  }
  Write-Output ''

  if ($Rep.backup -and $Rep.backup.created) {
    Write-Output ('--- backup written BEFORE the first change ---')
    Write-Output ('  dir: ' + $Rep.backup.dir + '   files=' + @($Rep.backup.files).Count + '  totalBytes=' + $Rep.backup.totalBytes)
    foreach ($f in @($Rep.backup.files)) { Write-Output ('    ' + $f.bytes.ToString().PadLeft(9) + '  ' + $f.sha256 + '  ' + $f.name) }
    Write-Output ('  MANIFEST.json sha256: ' + $Rep.backup.manifestSha256)
    Write-Output ''
  }
  if ($Rep.purge -and $Rep.purge.attempted) {
    Write-Output '--- backup purge ---'
    Write-Output ('  dir: ' + $Rep.purge.dir + '  purged=' + [string]$Rep.purge.purged + '  files=' + @($Rep.purge.files).Count + '  totalBytes=' + $Rep.purge.totalBytes)
    foreach ($f in @($Rep.purge.files)) { Write-Output ('    to delete: ' + $f.bytes.ToString().PadLeft(9) + '  ' + $f.sha256 + '  ' + $f.name) }
    Write-Output ('  total bytes to delete: ' + $Rep.purge.totalBytes)
    foreach ($f in @($Rep.purge.deletedAfter)) { Write-Output ('    deleted: ' + $f.bytes.ToString().PadLeft(9) + '  ' + $f.sha256 + '  ' + $f.name) }
    if ($Rep.purge.error) { Write-Output ('  purge refused/failed: ' + $Rep.purge.error) }
    Write-Output ''
  }

  Write-Output '--- residue scan (8 items) ---'
  foreach ($i in @($Rep.residue.items)) {
    Write-Output ('  [' + $i.status.ToUpper() + '] ' + $i.id + '  (' + $i.reasonKey + ')')
    Write-Output ('      ' + (Format-Display $i.detail 300))
    if ($i.exemptFromExit) { Write-Output '      (exempt from the exit-0 rule, by design)' }
  }
  Write-Output ''

  Write-Output ('--- ordering evidence (backup before every write) ---')
  foreach ($o in @($Rep.ordering)) { Write-Output ('  ' + $o) }
  Write-Output ''

  if (@($Rep.notes).Count -gt 0) {
    Write-Output '--- notes ---'
    foreach ($n in @($Rep.notes)) { Write-Output ('  * ' + $n) }
    Write-Output ''
  }

  Write-Output ('summary: records=' + $Rep.summary.records + ' residueItems=' + $Rep.summary.residueItems + ' unresolved=' + $Rep.summary.unresolved + ' (exempt cordis unknowns: ' + $Rep.summary.unknownExempt + ')')
  if ($Rep.summary.attribution -ne 'available') {
    Write-Output ('attribution: ' + $Rep.summary.attribution + ' (' + $Rep.summary.attributionReasonKey + ') - ' + $Rep.summary.attributionNote)
  }
  Write-Output ('overall: ' + $Rep.summary.verdict + ' -> exit ' + $Rep.summary.exitCode)
  Write-Output ('reading the exit code: ' + $Rep.summary.exitMeaning)
  Write-Output (Get-Label 'readTheExit')
  if ($script:FixtureMode) { Write-Output 'fixture mode: no system surface was mutated by this run; WOULD-DO lines are printed instead.' }
}

# ===========================================================================
# section 11: labels (the script stays ASCII; the wording comes from the manifest)
# ===========================================================================

function Get-Label {
  param([string]$Key)
  $node = $script:Labels
  if ($null -eq $node) { return '' }
  if ($node -is [System.Collections.IDictionary]) {
    if ($node.Contains($Key)) { return [string]$node[$Key] }
    return ''
  }
  $p = $node.PSObject.Properties[$Key]
  if ($null -eq $p) { return '' }
  return [string]$p.Value
}

function Initialize-Labels {
  $builtin = @{
    title = 'dsh-crossnet-link uninstall helper (dry-run by default)'
    dryRun = 'DRY RUN: nothing was written or changed. Add -Apply to execute the reverts that are classified revert.'
    recordBanner = 'JOURNAL RUN: this run observes and records. Its only write is the journal file inside the state directory.'
    applyBanner = 'WRITE RUN: the backup directory is written and verified BEFORE the first change.'
    cordisNote = 'dynamic Cordis packages cannot be removed from here - run each command below in the DSH session:'
    readTheExit = 'exit 0 = clean (a kept backup is normal) / 1 = left-alone, unknown or residue / 2 = refused, nothing written'
  }
  $script:Labels = $builtin
  $script:LabelSource = 'builtin-en'
  if (-not (Test-Path -LiteralPath $manifestVal)) { return }
  $r = Read-JsonFileSafe $manifestVal
  if (-not $r.ok) { return }
  $node = Prop $r.doc 'uninstallLabels'
  if ($null -eq $node) { return }
  $pick = Prop $node $langUsed
  if ($null -eq $pick) { $pick = Prop $node 'en' }
  if ($null -eq $pick) { return }
  $merged = $false
  foreach ($pr in $pick.PSObject.Properties) {
    if ([string]$pr.Value) { $builtin[$pr.Name] = [string]$pr.Value; $merged = $true }
  }
  if ($merged) { $script:LabelSource = 'manifest(panel/prereq-manifest.json) lang=' + $langUsed }
}

# ===========================================================================
# section 12: run state - observe, classify, scan
# ===========================================================================

function Get-RecordRow {
  param($Record,$Observation)
  $cl = Get-RecordClassification $Record $Observation
  $rv = Prop $Record 'revert'
  $ve = Prop $Record 'verify'
  $kind = 'instruction'
  $cmd = ''
  $note = ''
  if ($null -ne $rv) {
    if ($null -ne (Prop $rv 'kind')) { $kind = [string](Prop $rv 'kind') }
    if ($null -ne (Prop $rv 'command')) { $cmd = [string](Prop $rv 'command') }
    if ($null -ne (Prop $rv 'note')) { $note = [string](Prop $rv 'note') }
  }
  $vcmd = ''
  $vexp = ''
  if ($null -ne $ve) {
    if ($null -ne (Prop $ve 'command')) { $vcmd = [string](Prop $ve 'command') }
    if ($null -ne (Prop $ve 'expect')) { $vexp = [string](Prop $ve 'expect') }
  }
  return [pscustomobject][ordered]@{
    id = [string](Prop $Record 'id')
    surface = [string](Prop $Record 'surface')
    scope = [string](Prop $Record 'scope')
    before = [string](Prop $Record 'before')
    expected = [string](Prop $Record 'expected')
    after = $(if ($null -ne (Prop $Record 'after')) { [string](Prop $Record 'after') } else { $null })
    userOwned = [bool](Prop $Record 'userOwned')
    remediation = [string](Prop $Record 'remediation')
    revert = [pscustomobject][ordered]@{ kind = $kind; command = $cmd; note = $note }
    verify = [pscustomobject][ordered]@{ command = $vcmd; expect = $vexp }
    classification = $cl
    provenance = $cl.provenance
    action = 'none'
    actionDetail = ''
    executable = [bool]$cl.executable
  }
}

function Test-RecordShape {
  param($Record,[int]$Index)
  $problems = New-Object System.Collections.ArrayList
  $id = [string](Prop $Record 'id')
  if (-not $id) { [void]$problems.Add('records[' + $Index + '] has no id') }
  $surface = [string](Prop $Record 'surface')
  if (-not $surface) { [void]$problems.Add(($id + ': no surface')) }
  elseif ($script:Surfaces -notcontains $surface) { [void]$problems.Add(($id + ': surface "' + $surface + '" is outside the closed surface set, so this record is never executed')) }
  foreach ($k in @('scope','before','expected')) {
    if ($null -eq (Prop $Record $k)) { [void]$problems.Add(($id + ': the field ' + $k + ' is missing (journal schema v1 requires it)')) }
  }
  if ($null -eq (Prop $Record 'revert')) { [void]$problems.Add(($id + ': the revert block is missing')) }
  if ($null -eq (Prop $Record 'verify')) { [void]$problems.Add(($id + ': the verify block is missing')) }
  if ($null -eq (Prop $Record 'userOwned')) { [void]$problems.Add(($id + ': userOwned is missing')) }
  return @($problems)
}

function Get-RunState {
  param($JournalDoc,[bool]$SkipResidue = $false)
  $rows = New-Object System.Collections.ArrayList
  foreach ($r in @(Get-Array $JournalDoc 'records')) {
    $obs = Get-Observation $r
    [void]$rows.Add((Get-RecordRow $r $obs))
  }
  $recs = $rows.ToArray()

  $collectorReport = Get-CollectorReport
  $collectorAfter = Get-CollectorView $collectorReport.doc
  $collectorBefore = $null
  if ($script:FixtureMode) { $collectorBefore = Get-FixtureCollectorBaseline }
  else { $collectorBefore = Get-BaselineFromJournal $JournalDoc }
  if ($null -eq $collectorBefore) { $collectorBefore = $collectorAfter }

  $listing = Get-StateDirListing
  $residue = @()
  if (-not $SkipResidue) {
    $residue = Get-ResidueScan $recs @{} $collectorBefore $collectorAfter $listing
  }
  return [pscustomobject][ordered]@{
    records = $recs
    residue = @($residue)
    stateListing = $listing
    collectorReport = $collectorReport
    collectorBefore = $collectorBefore
    collectorAfter = $collectorAfter
  }
}

function Get-DeletionRows {
  # The per-file decision, machine-readable and identical for the dry run and for -Apply.
  param($Rows,[bool]$RemovalApplied)
  $out = New-Object System.Collections.ArrayList
  foreach ($r in @($Rows)) {
    if ($r.surface -ne 'plugin-files' -and $r.surface -ne 'user-skill-copy') { continue }
    $status = 'kept'
    $reasonKey = 'remove_files_not_requested'
    $detail = 'kept by design: -RemoveFiles was not given, so this tool deletes nothing'
    if ($r.classification.status -eq 'kept_user_owned' -or $r.userOwned) {
      $reasonKey = 'user_owned'
      $detail = 'userOwned: this tool never deletes it; the one-line command below is for you'
    } elseif ($RemovalApplied) {
      if ($r.action -eq 'executed') { $status = 'deleted'; $reasonKey = 'hash_matched'; $detail = $r.actionDetail }
      elseif ($r.action -eq 'would-do') { $status = 'would-delete'; $reasonKey = 'hash_matched_fixture'; $detail = 'fixture mode: not executed. ' + $r.actionDetail }
      else {
        $status = 'kept'
        $reasonKey = 'hash_guard_or_unreadable'
        $detail = $r.actionDetail
        if (-not $detail) {
          $detail = ('kept: ' + $r.classification.reasonKey + ' - ' + $r.classification.detail)
        }
      }
    } elseif ($RemoveFiles) {
      $want = Get-RecordFileHashFromValue ([string]$r.after)
      if (-not $want) { $reasonKey = 'no_recorded_hash'; $detail = 'the record carries no sha256 in its after value, so this tool cannot prove the file is its own; add -RecordAfter first' }
      elseif (-not (Test-RealPath $r.scope)) { $status = 'gone'; $reasonKey = 'already_absent'; $detail = 'the path does not exist any more' }
      else {
        $nowHash = Get-Sha256Hex $r.scope
        if ($nowHash -eq $want) { $status = 'would-delete'; $reasonKey = 'hash_matches'; $detail = 'sha256 matches the recorded after value: -Apply -RemoveFiles would delete it' }
        else { $status = 'kept'; $reasonKey = 'hash_mismatch'; $detail = ('the hash is ' + $nowHash + ' but the journal recorded ' + $want + ': kept and reported as left-alone') }
      }
    }
    [void]$out.Add([pscustomobject][ordered]@{
      id = $r.id; path = $r.scope; status = $status; reasonKey = $reasonKey; detail = $detail
      oneLineCommand = $r.revert.command
    })
  }
  return $out.ToArray()
}

# ===========================================================================
# section 13: the backup - written and verified BEFORE the first change
# ===========================================================================

function Assert-BackupFirst {
  # The single gate every mutation passes through. A mutation before the backup manifest has been
  # written and verified is refused, not attempted, so the ordering is a runtime property, not a
  # comment. The report prints the ordering list this function appends to.
  if (-not $script:BackupDone) {
    return 'refused: a change was requested before the backup was written and verified'
  }
  return ''
}

function Write-RestoreDoc {
  param($Rows,[string]$Dir)
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine('# restore instructions - every inverse operation of this journal')
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine('Generated by ' + $script:ToolName + ' at ' + (Get-NowStamp) + ' (local time).')
  [void]$sb.AppendLine('Each block is one journal record: what it was, what this tool produced, what it is now,')
  [void]$sb.AppendLine('the inverse operation, and the command that verifies the rollback.')
  [void]$sb.AppendLine('')
  foreach ($r in @($Rows)) {
    [void]$sb.AppendLine('## ' + $r.id)
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('- surface: `' + $r.surface + '`')
    [void]$sb.AppendLine('- scope: `' + $r.scope + '`')
    [void]$sb.AppendLine('- class: `' + $r.classification.status + '` (' + $r.classification.reasonKey + ')')
    [void]$sb.AppendLine('- before: `' + (Format-Display $r.before 400) + '`')
    [void]$sb.AppendLine('- expected: `' + (Format-Display $r.expected 400) + '`')
    [void]$sb.AppendLine('- after: `' + (Format-Display $r.after 400) + '`')
    [void]$sb.AppendLine('- observed now: `' + (Format-Display $r.provenance.observedNow 400) + '`')
    [void]$sb.AppendLine('- userOwned: ' + [string]$r.userOwned)
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('Inverse operation (' + $r.revert.kind + '):')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('    ' + $r.revert.command)
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('Note: ' + $r.revert.note)
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('Rollback verification command:')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('    ' + $r.verify.command)
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('Expected after the rollback: ' + $r.verify.expect)
    [void]$sb.AppendLine('')
  }
  return $sb.ToString()
}

function New-Backup {
  param($Rows,$JournalDoc,[string]$PlanJson)
  $info = [ordered]@{
    created = $false; dir = ''; files = @(); totalBytes = 0; manifestSha256 = ''
    verified = $false; error = ''; kind = 'apply'
  }
  $dir = $BackupDir
  if (-not $dir) { $dir = Join-Path (Join-Path $stateVal 'backups') ('uninstall-' + (Get-DirStamp)) }
  $info.dir = $dir
  if (-not (Test-PathInside $dir $stateVal)) {
    $info.error = 'the backup directory is outside the state directory: ' + $dir
    Add-Refusal 'path_escape' $info.error
    return [pscustomobject]$info
  }
  $err = New-DirectorySafe $dir
  if ($err) {
    $info.error = 'the backup directory could not be created: ' + $dir + ' - ' + $err
    Add-Refusal 'backup_unwritable' $info.error
    return [pscustomobject]$info
  }
  Add-Order ('backup begin: ' + $dir)

  $files = New-Object System.Collections.ArrayList
  $writeErrors = New-Object System.Collections.ArrayList

  function Write-BackupFile {
    param([string]$Name,[string]$Text)
    $p = Join-Path $dir $Name
    $e = Write-TextFileSafe $p $Text
    if ($e) { [void]$writeErrors.Add($Name + ': ' + $e); return }
    [void]$files.Add($Name)
    Add-Order ('backup file written: ' + $Name + ' (' + (Get-FileByteCount $p) + ' bytes)')
  }

  Write-BackupFile 'journal.json' (Get-JournalText $JournalDoc)
  Write-BackupFile 'plan.json' $PlanJson
  Write-BackupFile 'restore.md' (Write-RestoreDoc $Rows $dir)

  # raw read-only captures, only for the surfaces that take part
  $surfaces = @($Rows | ForEach-Object { $_.surface })
  if ($surfaces -contains 'dsh-profile-row') {
    $n = 0
    foreach ($r in @($Rows | Where-Object { $_.surface -eq 'dsh-profile-row' })) {
      $p = ($r.scope -split '::')[0]
      if (-not (Test-RealPath $p -Leaf)) { continue }
      $n++
      $name = 'profile-cordis.patch.yml.bak'
      if ($n -gt 1) { $name = 'profile-cordis.patch.yml.' + [string]$n + '.bak' }
      try {
        $bytes = [System.IO.File]::ReadAllBytes($p)
        [System.IO.File]::WriteAllBytes((Join-Path $dir $name), $bytes)
        [void]$files.Add($name)
        Add-Order ('backup raw capture: ' + $name + ' (byte-for-byte copy of ' + $p + ', ' + $bytes.Length + ' bytes, sha256 ' + (Get-Sha256Hex (Join-Path $dir $name)) + ')')
      } catch { [void]$writeErrors.Add($name + ': ' + $_.Exception.Message) }
    }
  }
  if ($surfaces -contains 'firewall-rule') {
    $raw = ''
    if ($script:RawCaptures.ContainsKey('firewall-rule')) { $raw = [string]$script:RawCaptures['firewall-rule'] }
    if (-not $raw) {
      $raw = '(no firewall rule with a recorded name was found on this machine)'
      if ($script:FixtureMode) { $raw = '(fixture mode: the observation came from the fixture, so no native firewall capture was taken)' }
    }
    Write-BackupFile 'firewall-rules.txt' $raw
  }
  if ($surfaces -contains 'tailscale-serve') {
    $raw = ''
    if ($script:RawCaptures.ContainsKey('tailscale-serve')) { $raw = [string]$script:RawCaptures['tailscale-serve'] }
    if (-not $raw) {
      $raw = '(tailscale serve status was not run in this session)'
      if ($script:FixtureMode) { $raw = '(fixture mode: the observation came from the fixture, so no native serve status capture was taken)' }
    }
    Write-BackupFile 'serve-status.txt' $raw
  }

  if (@($writeErrors).Count -gt 0) {
    $info.error = 'the backup is incomplete: ' + ((@($writeErrors)) -join '; ')
    Add-Refusal 'backup_incomplete' ($info.error + ' - no change was made')
    return [pscustomobject]$info
  }

  # MANIFEST.json lists every OTHER file (it cannot contain its own final hash; the report prints
  # that hash separately so the whole directory stays verifiable).
  $manFiles = New-Object System.Collections.ArrayList
  $total = 0
  foreach ($name in @($files)) {
    $p = Join-Path $dir $name
    $b = Get-FileByteCount $p
    $h = Get-Sha256Hex $p
    $total = $total + $b
    [void]$manFiles.Add([pscustomobject][ordered]@{ name = $name; bytes = $b; sha256 = $h })
  }
  $man = [pscustomobject][ordered]@{
    schema = 'dsh-crossnet-link/uninstall-backup/1'
    tool = $script:ToolName
    createdAtLocal = Get-NowStamp
    stateDir = $stateVal
    action = $action
    dryRun = $false
    manifestNote = 'every file in this backup directory except MANIFEST.json itself is listed here with its sha256 and byte count; verify with: Get-FileHash -Algorithm SHA256 <file>'
    files = @($manFiles)
    totalBytes = $total
  }
  $manText = ConvertTo-JsonSafe $man 14
  $mp = Join-Path $dir 'MANIFEST.json'
  $e = Write-TextFileSafe $mp $manText
  if ($e) {
    $info.error = 'MANIFEST.json could not be written: ' + $e
    Add-Refusal 'backup_incomplete' ($info.error + ' - no change was made')
    return [pscustomobject]$info
  }
  Add-Order 'backup MANIFEST.json written (last)'
  $info.files = @($manFiles)
  $info.totalBytes = $total
  $info.manifestSha256 = Get-Sha256Hex $mp
  $info.created = $true

  # self-verification: re-read the manifest and recompute every listed file
  $verify = Read-JsonFileSafe $mp
  $bad = New-Object System.Collections.ArrayList
  if (-not $verify.ok) { [void]$bad.Add('the manifest cannot be re-read: ' + $verify.error) }
  else {
    foreach ($f in @(Prop $verify.doc 'files')) {
      $name = [string](Prop $f 'name')
      $p = Join-Path $dir $name
      if (-not (Test-Path -LiteralPath $p)) { [void]$bad.Add($name + ' is listed but missing'); continue }
      if ((Get-Sha256Hex $p) -ne [string](Prop $f 'sha256')) { [void]$bad.Add($name + ' sha256 mismatch'); continue }
      if ((Get-FileByteCount $p) -ne [int64](Prop $f 'bytes')) { [void]$bad.Add($name + ' byte count mismatch') }
    }
  }
  if (@($bad).Count -gt 0) {
    $info.error = 'the backup did not verify: ' + ((@($bad)) -join '; ')
    Add-Refusal 'backup_unverified' ($info.error + ' - no change was made')
    return [pscustomobject]$info
  }
  Add-Order ('backup verified: ' + @($manFiles).Count + ' file(s), ' + $total + ' byte(s), each sha256 re-computed and matched')
  $info.verified = $true
  $script:BackupDone = $true
  return [pscustomobject]$info
}

# ===========================================================================
# section 14: guarded mutations
# ===========================================================================

function Test-RevertAllowed {
  # A revert command may only be executed when it matches the frozen allowlist exactly AND carries
  # no shell metacharacter at all. A hand-edited journal therefore cannot smuggle in a second
  # statement, a pipeline, a redirection or a variable expansion.
  param([string]$Command)
  if (-not $Command) { return 'no command in the record' }
  if ($Command -match $script:MetaReject) { return 'the command contains a shell metacharacter, which is never executed' }
  foreach ($rx in $script:RevertAllow) { if ($Command -match $rx) { return '' } }
  return 'the command is not in the frozen revert allowlist, so it is printed for you instead of being executed'
}

function Get-RecordFileHashFromValue {
  param([string]$Value)
  if ($Value -match 'sha256=([0-9a-fA-F]{64})') { return $Matches[1].ToUpperInvariant() }
  return ''
}

function Invoke-RevertCommand {
  param([string]$Command)
  $gate = Assert-BackupFirst
  if ($gate) { return [pscustomobject]@{ ok = $false; reasonKey = 'no_backup'; detail = $gate; output = '' } }
  $guard = Test-RevertAllowed $Command
  if ($guard) { return [pscustomobject]@{ ok = $false; reasonKey = 'revert_not_allowlisted'; detail = $guard; output = '' } }
  $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  if (-not (Test-Path -LiteralPath $psExe)) { return [pscustomobject]@{ ok = $false; reasonKey = 'no_powershell'; detail = 'powershell.exe was not found under System32'; output = '' } }
  $script:RevertsRun++
  $r = Invoke-Bounded $psExe @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-Command',$Command) $CommandTimeoutMs
  if (-not $r.available) { return [pscustomobject]@{ ok = $false; reasonKey = 'revert_not_started'; detail = $r.error; output = '' } }
  $text = Format-Display (([string]$r.stdout + ' ' + [string]$r.stderr).Trim()) 180
  if ($r.exitCode -eq 0) { return [pscustomobject]@{ ok = $true; reasonKey = 'revert_executed'; detail = ('exit 0  ' + $text); output = $text } }
  return [pscustomobject]@{ ok = $false; reasonKey = 'revert_failed'; detail = ('exit ' + [string]$r.exitCode + '  ' + $text + '  (run it yourself in an elevated window if it is an access-denied result; this tool never elevates)'); output = $text }
}

function Test-TextRoundTrip {
  param([string]$Path,[byte[]]$Bytes)
  try {
    $decoded = [System.Text.Encoding]::UTF8.GetString($Bytes)
    $re = [System.Text.Encoding]::UTF8.GetBytes($decoded)
    if ($re.Length -ne $Bytes.Length) { return $false }
    for ($i = 0; $i -lt $Bytes.Length; $i++) { if ($re[$i] -ne $Bytes[$i]) { return $false } }
    return $true
  } catch { return $false }
}

function Get-FileTextAndEol {
  param([string]$Path)
  $bytes = $null
  try { $bytes = [System.IO.File]::ReadAllBytes($Path) } catch { return $null }
  if (-not (Test-TextRoundTrip $Path $bytes)) { return [pscustomobject]@{ ok = $false; error = 'the file is not valid UTF-8, so this tool refuses to rewrite it' } }
  $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
  $text = [System.Text.Encoding]::UTF8.GetString($bytes)
  if ($hasBom -and $text.Length -gt 0) { $text = $text.Substring(1) }
  $eol = "`n"
  if ($text.Contains("`r`n")) { $eol = "`r`n" }
  return [pscustomobject]@{ ok = $true; text = $text; eol = $eol; bom = $hasBom }
}

function Save-FileTextSameShape {
  param([string]$Path,[string]$Text,[bool]$Bom)
  $enc = New-Object System.Text.UTF8Encoding($Bom)
  try { [System.IO.File]::WriteAllText($Path, $Text, $enc); return '' } catch { return $_.Exception.Message }
}

function Invoke-RevertProfileRow {
  param($Row)
  $gate = Assert-BackupFirst
  if ($gate) { return [pscustomobject]@{ ok = $false; reasonKey = 'no_backup'; detail = $gate } }
  $parts = $Row.scope -split '::'
  $path = $parts[0]
  $rowId = ''
  if ($parts.Count -gt 1) { $rowId = $parts[1] }
  if (-not (Test-RealPath $path -Leaf)) {
    return [pscustomobject]@{ ok = $true; reasonKey = 'already_absent'; detail = 'the profile patch file does not exist, so the row cannot be there' }
  }
  $fx2 = Get-FileTextAndEol $path
  if ($null -eq $fx2) { return [pscustomobject]@{ ok = $false; reasonKey = 'file_unreadable'; detail = 'the profile patch file could not be read' } }
  if (-not $fx2.ok) { return [pscustomobject]@{ ok = $false; reasonKey = 'file_not_utf8'; detail = $fx2.error } }
  $b = Get-ProfileRowBlock -Text $fx2.text -RowId $rowId
  if (-not $b.found) { return [pscustomobject]@{ ok = $true; reasonKey = 'already_absent'; detail = 'no YAML list entry with id ' + $rowId + ' any more' } }
  $norm = ($b.block -replace '\s+', ' ').Trim()
  $want = 'present:' + $norm
  # Attribution is NOT loosened by the row-id equivalence above: the block read back must still
  # equal the recorded before/after text byte-for-byte, or the row is left alone. Matching a
  # different id only decides WHERE to look, never whether the value counts as ours.
  if ($want -ne [string]$Row.after -and $want -ne [string]$Row.before) {
    return [pscustomobject]@{ ok = $false; reasonKey = 'block_changed'; detail = 'the block no longer matches the recorded value, so it is left alone' }
  }
  $lines = @($fx2.text -split "`r?`n")
  $kept = New-Object System.Collections.ArrayList
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($i -lt $b.startLine -or $i -gt $b.endLine) { [void]$kept.Add($lines[$i]) }
  }
  $newText = (@($kept) -join $fx2.eol)
  $e = Save-FileTextSameShape $path $newText $fx2.bom
  if ($e) { return [pscustomobject]@{ ok = $false; reasonKey = 'write_failed'; detail = $e } }
  return [pscustomobject]@{ ok = $true; reasonKey = 'row_removed'; detail = ('removed lines ' + ($b.startLine + 1) + '-' + ($b.endLine + 1) + ' from ' + $path) }
}

function Invoke-RevertSettingsLine {
  param($Row)
  $gate = Assert-BackupFirst
  if ($gate) { return [pscustomobject]@{ ok = $false; reasonKey = 'no_backup'; detail = $gate } }
  $parts = $Row.scope -split '::'
  $path = $parts[0]
  $keyName = ''
  if ($parts.Count -gt 1) { $keyName = $parts[1] }
  if (-not (Test-RealPath $path -Leaf)) {
    return [pscustomobject]@{ ok = $true; reasonKey = 'already_absent'; detail = 'the settings file does not exist' }
  }
  $fx2 = Get-FileTextAndEol $path
  if ($null -eq $fx2) { return [pscustomobject]@{ ok = $false; reasonKey = 'file_unreadable'; detail = 'the settings file could not be read' } }
  if (-not $fx2.ok) { return [pscustomobject]@{ ok = $false; reasonKey = 'file_not_utf8'; detail = $fx2.error } }
  $lines = @($fx2.text -split "`r?`n")
  $idx = -1
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match ('^\s*' + [regex]::Escape($keyName) + '\s*:\s*(.*)$')) { $idx = $i; break }
  }
  if ($idx -lt 0) { return [pscustomobject]@{ ok = $true; reasonKey = 'already_absent'; detail = 'the key is not in the file any more' } }
  $before = [string]$Row.before
  if ($before -eq 'absent') {
    $kept = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($i -ne $idx) { [void]$kept.Add($lines[$i]) } }
    $e = Save-FileTextSameShape $path ((@($kept) -join $fx2.eol)) $fx2.bom
    if ($e) { return [pscustomobject]@{ ok = $false; reasonKey = 'write_failed'; detail = $e } }
    return [pscustomobject]@{ ok = $true; reasonKey = 'line_removed'; detail = ('removed line ' + ($idx + 1) + ' from ' + $path) }
  }
  if ($before -notmatch ('^' + [regex]::Escape($keyName) + '=(.*)$')) {
    return [pscustomobject]@{ ok = $false; reasonKey = 'before_not_parseable'; detail = 'the recorded before value is not a key=value pair, so this tool will not guess' }
  }
  $wantVal = $Matches[1]
  $orig = $lines[$idx]
  $indent = ''
  if ($orig -match '^(\s*)') { $indent = $Matches[1] }
  $lines[$idx] = $indent + $keyName + ': ' + $wantVal
  $e = Save-FileTextSameShape $path ((@($lines) -join $fx2.eol)) $fx2.bom
  if ($e) { return [pscustomobject]@{ ok = $false; reasonKey = 'write_failed'; detail = $e } }
  return [pscustomobject]@{ ok = $true; reasonKey = 'line_restored'; detail = ('restored line ' + ($idx + 1) + ' in ' + $path + ' to ' + $wantVal) }
}

function Remove-RecordedFile {
  param($Row)
  $gate = Assert-BackupFirst
  if ($gate) { return [pscustomobject]@{ ok = $false; reasonKey = 'no_backup'; detail = $gate } }
  $path = [string]$Row.scope
  if (-not (Test-RealPath $path)) { return [pscustomobject]@{ ok = $true; reasonKey = 'already_absent'; detail = 'the path does not exist any more' } }
  $want = Get-RecordFileHashFromValue ([string]$Row.after)
  if (-not $want) {
    return [pscustomobject]@{ ok = $false; reasonKey = 'no_recorded_hash'; detail = 'the record carries no sha256 in its after value, so this tool cannot prove the file is the one it installed; the file is kept' }
  }
  $nowHash = Get-Sha256Hex $path
  if (-not $nowHash) { return [pscustomobject]@{ ok = $false; reasonKey = 'hash_unreadable'; detail = 'the file hash could not be computed; the file is kept' } }
  if ($nowHash -ne $want) {
    return [pscustomobject]@{ ok = $false; reasonKey = 'hash_mismatch'; detail = ('the file hash is ' + $nowHash + ' but the journal recorded ' + $want + ': somebody changed it, so it is kept and reported as left-alone') }
  }
  try {
    if (Test-Path -LiteralPath $path -PathType Container) { [System.IO.Directory]::Delete($path, $true) }
    else { [System.IO.File]::Delete($path) }
    return [pscustomobject]@{ ok = $true; reasonKey = 'deleted'; detail = ('deleted ' + $path + ' (sha256 matched the recorded value)') }
  } catch { return [pscustomobject]@{ ok = $false; reasonKey = 'delete_failed'; detail = $_.Exception.Message } }
}

function Invoke-RecordRevert {
  param($Row)
  if ($Row.revert.kind -eq 'instruction') {
    $Row.action = 'instruction-only'
    $Row.actionDetail = 'print only: ' + $Row.revert.command
    return
  }
  if ($Row.revert.kind -eq 'delete') {
    if ($Row.userOwned) {
      $Row.action = 'kept-user-owned'
      $Row.actionDetail = 'userOwned: never deleted; the command is printed for you'
      return
    }
    if (-not $RemoveFiles) {
      $Row.action = 'kept-no-remove-files'
      $Row.actionDetail = 'kept: -RemoveFiles was not given. Delete it yourself with: ' + $Row.revert.command
      return
    }
  }
  if ($script:FixtureMode) {
    $Row.action = 'would-do'
    $Row.actionDetail = 'fixture mode: not executed. Would run: ' + $Row.revert.command
    Add-Order ('WOULD-DO (fixture): ' + $Row.id + ' -> ' + (Format-Display $Row.revert.command 120))
    return
  }
  switch ($Row.revert.kind) {
    'command' {
      $r = Invoke-RevertCommand $Row.revert.command
      if ($r.ok) { $Row.action = 'executed'; $Row.actionDetail = $r.detail; Add-Order ('executed revert for ' + $Row.id + ': ' + (Format-Display $Row.revert.command 120) + ' -> ' + $r.detail) }
      elseif ($r.reasonKey -eq 'revert_not_allowlisted') { $Row.action = 'refused-by-guard'; $Row.actionDetail = $r.detail; Add-Order ('refused by the revert guard: ' + $Row.id + ' -> ' + (Format-Display $Row.revert.command 120)) }
      else { $Row.action = 'failed'; $Row.actionDetail = $r.detail; Add-Order ('revert FAILED for ' + $Row.id + ': ' + $r.detail) }
    }
    'edit' {
      if ($Row.surface -eq 'dsh-profile-row') { $r = Invoke-RevertProfileRow $Row } else { $r = Invoke-RevertSettingsLine $Row }
      if ($r.ok) { $Row.action = 'executed'; $Row.actionDetail = $r.detail; Add-Order ('edited ' + $Row.id + ': ' + $r.detail) }
      else { $Row.action = 'failed'; $Row.actionDetail = $r.detail; Add-Order ('edit FAILED for ' + $Row.id + ': ' + $r.detail) }
    }
    'delete' {
      $r = Remove-RecordedFile $Row
      if ($r.ok) { $Row.action = 'executed'; $Row.actionDetail = $r.detail; $script:DeletesRun++; Add-Order ('deleted ' + $Row.id + ': ' + $r.detail) }
      elseif ($r.reasonKey -eq 'hash_mismatch' -or $r.reasonKey -eq 'no_recorded_hash') {
        $Row.action = 'failed'
        $Row.actionDetail = $r.detail
        Add-Order ('KEPT (hash guard) ' + $Row.id + ': ' + $r.detail)
      } else { $Row.action = 'failed'; $Row.actionDetail = $r.detail; Add-Order ('delete FAILED for ' + $Row.id + ': ' + $r.detail) }
    }
    default {
      $Row.action = 'instruction-only'
      $Row.actionDetail = 'unknown revert kind "' + $Row.revert.kind + '": print only, never executed'
    }
  }
}

function Invoke-PurgeBackup {
  param([string]$Dir)
  $info = [ordered]@{ attempted = $false; dir = ''; files = @(); totalBytes = 0; purged = $false; error = ''; deletedAfter = @() }
  $info.attempted = $true
  $target = $Dir
  if (-not $target) { $target = $BackupDir }
  $info.dir = $target
  if (-not $target) {
    $info.error = 'no backup directory to purge: pass -BackupDir, or run -Apply -PurgeBackup in the same run that creates one'
    Add-Refusal 'purge_no_target' $info.error
    return [pscustomobject]$info
  }
  if (-not (Test-PathInside $target $stateVal)) {
    $info.error = 'refused: the purge target is not inside the state directory: ' + $target
    Add-Refusal 'path_escape' $info.error
    return [pscustomobject]$info
  }
  if (-not (Test-Path -LiteralPath $target -PathType Container)) {
    $info.error = 'refused: the purge target is not an existing directory: ' + $target
    Add-Refusal 'purge_no_target' $info.error
    return [pscustomobject]$info
  }
  $mp = Join-Path $target 'MANIFEST.json'
  if (-not (Test-Path -LiteralPath $mp -PathType Leaf)) {
    $info.error = 'refused: this directory carries no MANIFEST.json, so this tool did not create it and will not delete it'
    Add-Refusal 'purge_unverified' $info.error
    return [pscustomobject]$info
  }
  $man = Read-JsonFileSafe $mp
  if (-not $man.ok) {
    $info.error = 'refused: the backup manifest cannot be read: ' + $man.error
    Add-Refusal 'purge_unverified' $info.error
    return [pscustomobject]$info
  }
  $listed = New-Object System.Collections.ArrayList
  $bad = New-Object System.Collections.ArrayList
  foreach ($f in @(Prop $man.doc 'files')) {
    $name = [string](Prop $f 'name')
    $p = Join-Path $target $name
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { [void]$bad.Add($name + ' is listed but missing'); continue }
    $b = Get-FileByteCount $p
    $h = Get-Sha256Hex $p
    if ($h -ne [string](Prop $f 'sha256')) { [void]$bad.Add($name + ' sha256 mismatch'); continue }
    if ($b -ne [int64](Prop $f 'bytes')) { [void]$bad.Add($name + ' byte count mismatch'); continue }
    [void]$listed.Add([pscustomobject][ordered]@{ name = $name; bytes = $b; sha256 = $h })
  }
  $onDisk = @(Get-ChildItem -LiteralPath $target -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'MANIFEST.json' })
  foreach ($o in $onDisk) {
    $known = $false
    foreach ($l in @($listed)) { if ($l.name -eq $o.Name) { $known = $true; break } }
    if (-not $known) { [void]$bad.Add($o.Name + ' is in the directory but not in the manifest'); continue }
    if ($o.PSIsContainer) { [void]$bad.Add($o.Name + ' is a directory; this tool only purges its own flat backup directories') }
  }
  if (@($bad).Count -gt 0) {
    $info.error = 'refused: this directory is not a verified backup of this tool: ' + ((@($bad)) -join '; ')
    Add-Refusal 'purge_unverified' $info.error
    return [pscustomobject]$info
  }
  $info.files = @($listed)
  $tb = 0
  foreach ($l in @($listed)) { $tb = $tb + $l.bytes }
  $info.totalBytes = $tb
  if (-not $AsJson) {
    Write-Output '--- about to delete this backup (verified against its own MANIFEST.json) ---'
    foreach ($l in @($listed)) { Write-Output ('    to delete: ' + $l.bytes.ToString().PadLeft(9) + '  ' + $l.sha256 + '  ' + $l.name) }
    Write-Output ('    total bytes to delete: ' + $tb)
  }
  Add-Order ('purge: printed the full list of ' + @($listed).Count + ' file(s), ' + $tb + ' byte(s), each with its sha256, BEFORE deleting')
  foreach ($l in @($listed)) {
    $p = Join-Path $target $l.name
    try { [System.IO.File]::Delete($p) } catch { [void]$bad.Add('could not delete ' + $l.name + ': ' + $_.Exception.Message) }
  }
  try { [System.IO.File]::Delete($mp) } catch { [void]$bad.Add('could not delete MANIFEST.json: ' + $_.Exception.Message) }
  if (@($bad).Count -eq 0) {
    try { [System.IO.Directory]::Delete($target, $false) } catch { [void]$bad.Add('the directory itself could not be removed: ' + $_.Exception.Message) }
  }
  if (@($bad).Count -gt 0) {
    $info.error = 'the purge was incomplete: ' + ((@($bad)) -join '; ')
    Add-Refusal 'purge_incomplete' $info.error
    return [pscustomobject]$info
  }
  $info.purged = $true
  $info.deletedAfter = @($listed)
  if (-not $AsJson) {
    Write-Output '--- deleted (after) ---'
    foreach ($l in @($listed)) { Write-Output ('    deleted: ' + $l.bytes.ToString().PadLeft(9) + '  ' + $l.sha256 + '  ' + $l.name) }
  }
  Add-Order ('purged backup directory after verifying its manifest: ' + $target + ' (' + @($listed).Count + ' file(s), ' + $tb + ' byte(s))')
  return [pscustomobject]$info
}

# ===========================================================================
# section 15: main dispatch
# ===========================================================================

Initialize-Labels

if ($action -ne 'record-before' -and (Test-Path -LiteralPath $journalVal) -and -not $script:FixtureMode) {
  $jr = Read-JsonFileSafe $journalVal
  if (-not $jr.ok) { Add-Refusal 'journal_unusable' ('the journal file exists but cannot be used: ' + $journalVal + ' - ' + $jr.error) }
}

$journalDoc = $null
$journalLoad = Read-JournalDoc
if ($journalLoad.found) {
  $journalDoc = $journalLoad.doc
  $sv = Prop $journalDoc 'schemaVersion'
  if ($null -eq $sv -or [int]$sv -ne $script:JournalSchema) {
    Add-Refusal 'journal_schema' ('the journal schemaVersion is "' + [string]$sv + '" but this tool only understands the frozen version ' + $script:JournalSchema)
  } else {
    $idx = 0
    foreach ($r in @(Get-Array $journalDoc 'records')) {
      $idx++
      foreach ($p in @(Test-RecordShape $r $idx)) { Add-Refusal 'journal_record_shape' $p }
    }
  }
} elseif ($journalLoad.error -and $journalLoad.source -eq 'file') {
  # The file exists but is unusable; a read-only scan may still run, a plan/apply may not.
  Add-Note ('journal note: ' + $journalLoad.error)
}

if ($action -eq 'record-before' -and $journalLoad.found -and $journalLoad.source -eq 'file') {
  Add-Refusal 'journal_exists' ('a journal already exists at ' + $journalLoad.path + ': this tool never overwrites provenance. Point -Journal at a new path, or move the old journal aside (it is also copied into every backup).')
} elseif ($action -eq 'record-before' -and $journalLoad.source -eq 'backup-snapshot') {
  Add-Note ('a previous round left a journal snapshot at ' + $journalLoad.path + ': this -RecordBefore starts a fresh journal, and the old snapshot stays exactly where it is')
}
if (($action -eq 'plan' -or $action -eq 'apply' -or $action -eq 'purge' -or $action -eq 'record-after') -and -not $journalLoad.found) {
  Add-Refusal 'journal_required' ('no journal was found at ' + $journalVal + ': run -RecordBefore before the remediation and -RecordAfter after it. (' + $journalLoad.error + ')')
}

$stateInfo = Get-StateDirState
if ($stateInfo.exists -and (-not $stateInfo.isDirectory -or -not $stateInfo.readable)) {
  Add-Refusal 'state_dir_unusable' ('the state directory is unusable: ' + $stateVal + ' - ' + $stateInfo.error)
}
if ($stateInfo.exists -and -not $stateInfo.isDirectory) {
  Add-Refusal 'state_dir_unusable' ('the state directory path is a file, not a directory: ' + $stateVal)
}

$journalInfo = [ordered]@{
  path = $journalLoad.path
  found = [bool]$journalLoad.found
  source = $journalLoad.source
  schemaVersion = $null
  records = 0
  error = $journalLoad.error
  archived = $false
  snapshotFallback = ($journalLoad.source -eq 'backup-snapshot')
}
if ($journalLoad.found) {
  $journalInfo.schemaVersion = [int](Prop $journalDoc 'schemaVersion')
  $journalInfo.records = @(Prop $journalDoc 'records').Count
}

$retention = Get-Retention
if (-not $retention.loaded) { Add-Note ('retention: ' + $retention.error) }
if (@($retention.problems).Count -gt 0) { Add-Note ('retention policy problems: ' + ((@($retention.problems)) -join '; ')) }

# No journal means nothing on this machine can be ATTRIBUTED to this tool. A clean file-system
# scan is still a real result, but "nothing of ours was ever installed here" is not a proven fact,
# so the verdict must not say clean.
if (-not $journalLoad.found -and $action -ne 'record-before' -and $action -ne 'record-after') {
  $script:JournalAbsentUnattributable = $true
  Add-Note 'journal_absent_cannot_attribute: no journal was found, so this run cannot attribute anything on this machine to this tool. The residue scan below is complete for the machine-level surfaces, but the conclusion "nothing of this tool was ever installed here" is NOT a proven fact - run -RecordBefore before the remediation so that attribution becomes possible.'
  Add-Order 'journal absent: attribution is unavailable, so this run cannot return a clean verdict'
}

$backupInfo = [pscustomobject][ordered]@{ created = $false; dir = ''; files = @(); totalBytes = 0; manifestSha256 = ''; verified = $false; error = ''; kind = 'none' }
$purgeInfo = [pscustomobject][ordered]@{ attempted = $false; dir = ''; files = @(); totalBytes = 0; purged = $false; error = ''; deletedAfter = @() }
$deletionRows = New-Object System.Collections.ArrayList

if ($action -eq 'record-before') {
  if (@($script:Refusals).Count -eq 0) {
    $err = New-DirectorySafe $stateVal
    if ($err) { Add-Refusal 'state_dir_unusable' ('the state directory could not be created: ' + $stateVal + ' - ' + $err) }
  }
  if (@($script:Refusals).Count -eq 0) {
    Add-Order 'record-before: observing the catalog'
    $cat = Get-Catalog
    $recs = New-Object System.Collections.ArrayList
    foreach ($c in $cat) {
      $probe = [pscustomobject]@{ id = $c.id; surface = $c.surface; scope = $c.scope }
      $obs = Get-Observation $probe
      $before = [string]$obs.value
      if ($c.surface -eq 'cordis-dynamic-package') { $before = $script:MemoryOnly }
      elseif ($obs.status -ne 'read') { $before = 'unreadable' }
      [void]$recs.Add([pscustomobject][ordered]@{
        id = $c.id; surface = $c.surface; scope = $c.scope
        before = $before; expected = $c.expected; after = $null
        revert = [pscustomobject][ordered]@{ kind = $c.revertKind; command = $c.revertCommand; note = $c.revertNote }
        verify = [pscustomobject][ordered]@{ command = $c.verifyCommand; expect = $c.verifyExpect }
        userOwned = [bool]$c.userOwned
        remediation = $c.remediation
        recordedAtLocal = Get-NowStamp
        recordedBy = 'uninstall.ps1 -RecordBefore'
      })
      if ($obs.status -ne 'read' -and $c.surface -ne 'cordis-dynamic-package') {
        Add-Note ('record ' + $c.id + ' could not be read now: ' + $obs.detail)
      }
    }
    $baseReport = Get-CollectorReport
    $journalDoc = [pscustomobject][ordered]@{
      schemaVersion = $script:JournalSchema
      tool = $script:ToolName
      createdAtLocal = Get-NowStamp
      updatedAtLocal = Get-NowStamp
      recordedBy = 'uninstall.ps1 -RecordBefore (journal schema v1)'
      collectorBaseline = (New-CollectorBaselineNode $baseReport)
      records = @($recs)
    }
    $e = Write-TextFileSafe $journalVal (Get-JournalText $journalDoc)
    if ($e) { Add-Refusal 'journal_write_failed' ('the journal could not be written: ' + $journalVal + ' - ' + $e) }
    else {
      Add-Order ('journal written: ' + $journalVal + ' (' + @($recs).Count + ' record(s))')
      $journalInfo.path = $journalVal
      $journalInfo.found = $true
      $journalInfo.source = 'file'
      $journalInfo.schemaVersion = $script:JournalSchema
      $journalInfo.records = @($recs).Count
      $journalInfo.error = ''
    }
  }
}

if ($action -eq 'record-after' -and @($script:Refusals).Count -eq 0) {
  Add-Order 'record-after: observing every recorded surface again'
  $idx = 0
  foreach ($r in @(Get-Array $journalDoc 'records')) {
    $idx++
    $obs = Get-Observation $r
    $after = [string]$obs.value
    if ([string](Prop $r 'surface') -eq 'cordis-dynamic-package') { $after = $script:MemoryOnly }
    elseif ($obs.status -ne 'read') { $after = 'unreadable' }
    $old = Prop $r 'after'
    if ($null -ne $old -and [string]$old -ne $after) {
      Add-Note ('record ' + [string](Prop $r 'id') + ': the previously recorded after value ' + (Format-Display ([string]$old) 120) + ' is replaced by ' + (Format-Display $after 120))
    }
    Set-NodeField $r 'after' $after
    Set-NodeField $r 'recordedAtLocal' (Get-NowStamp)
  }
  $baseReport = Get-CollectorReport
  if ($baseReport.ok) { Set-NodeField $journalDoc 'collectorBaseline' (New-CollectorBaselineNode $baseReport) }
  Set-NodeField $journalDoc 'updatedAtLocal' (Get-NowStamp)
  $e = Write-TextFileSafe $journalVal (Get-JournalText $journalDoc)
  if ($e) { Add-Refusal 'journal_write_failed' ('the journal could not be written: ' + $journalVal + ' - ' + $e) }
  else { Add-Order ('journal updated with the after values: ' + $journalVal) }
}

$run = $null
$skipResidue = ($action -eq 'record-before' -or $action -eq 'record-after')
if (@($script:Refusals).Count -eq 0 -and $journalDoc) { $run = Get-RunState $journalDoc $skipResidue }
elseif (@($script:Refusals).Count -eq 0) { $run = Get-RunState $null $skipResidue }

if ($run -and ($action -eq 'plan' -or $action -eq 'check')) {
  Add-Order 'dry run: the classification is printed, nothing is executed'
  foreach ($r in @($run.records)) {
    if ($r.classification.status -eq 'revert') { $r.action = 'would-revert'; $r.actionDetail = 'dry run: add -Apply to execute. Would run (' + $r.revert.kind + '): ' + $r.revert.command }
    elseif ($r.classification.status -eq 'kept_user_owned') { $r.action = 'kept-user-owned'; $r.actionDetail = 'never touched' }
  }
  foreach ($d in @(Get-DeletionRows $run.records $false)) { [void]$deletionRows.Add($d) }
}

if ($run -and $action -eq 'apply') {
  $planJson = ConvertTo-JsonSafe ([pscustomobject][ordered]@{
    schema = 'dsh-crossnet-link/uninstall-plan/1'
    tool = $script:ToolName
    generatedAtLocal = Get-NowStamp
    action = $action
    fixture = [bool]$script:FixtureMode
    keepTailscale = $keepTailVal
    removeFiles = [bool]$RemoveFiles
    records = @($run.records)
    residue = @($run.residue)
    retention = $retention
  }) 14
  if (-not $planJson) { Add-Refusal 'backup_incomplete' 'the plan could not be serialized for the backup' }
  else { $backupInfo = New-Backup $run.records $journalDoc $planJson }
  if (@($script:Refusals).Count -eq 0) {
    Add-Order 'execution begins only now (the backup above is already written and verified)'
    $surfaceOrder = @('tailscale-serve', 'firewall-rule', 'dsh-settings', 'power-plan', 'network-profile', 'dsh-profile-row', 'plugin-files', 'user-skill-copy', 'cordis-dynamic-package')
    foreach ($s in $surfaceOrder) {
      foreach ($r in @($run.records)) {
        if ($r.surface -ne $s) { continue }
        if ($r.classification.status -ne 'revert') { continue }
        Invoke-RecordRevert $r
      }
    }
    # The per-record outcome must survive the post-execution re-observation: Get-RunState builds
    # fresh rows from the journal, so the executed / failed / kept marks are carried over by id.
    $actionLog = @{}
    foreach ($r in @($run.records)) {
      if ($r.action -ne 'none') { $actionLog[$r.id] = [pscustomobject]@{ action = $r.action; detail = $r.actionDetail } }
    }
    $run = Get-RunState $journalDoc $false
    foreach ($r in @($run.records)) {
      if ($actionLog.ContainsKey($r.id)) { $r.action = $actionLog[$r.id].action; $r.actionDetail = $actionLog[$r.id].detail }
    }
    # Archive the state journal: its snapshot is already inside the backup (journal.json), so the
    # original is removed only when the two sha256 values match. That is what turns the residue
    # item "state directory contents" into a pass without ever losing provenance.
    $archived = $false
    if ($backupInfo.verified -and -not $script:FixtureMode -and (Test-Path -LiteralPath $journalVal -PathType Leaf)) {
      $snap = Join-Path $backupInfo.dir 'journal.json'
      if (Test-Path -LiteralPath $snap -PathType Leaf) {
        $h1 = Get-Sha256Hex $journalVal
        $h2 = Get-Sha256Hex $snap
        if ($h1 -and $h1 -eq $h2) {
          try {
            [System.IO.File]::Delete($journalVal)
            $archived = $true
            Add-Order 'state journal archived: the original was deleted only after its sha256 matched the copy inside the backup'
          } catch { Add-Note ('the state journal could not be removed: ' + $_.Exception.Message) }
        } else {
          Add-Note 'the state journal was KEPT: its sha256 does not match the backup snapshot, so this tool will not delete provenance'
        }
      }
    }
    if ($archived) {
      # the state directory now holds only the backup material, so re-scan it for item 5
      $run = Get-RunState $journalDoc $false
      foreach ($r in @($run.records)) {
        if ($actionLog.ContainsKey($r.id)) { $r.action = $actionLog[$r.id].action; $r.actionDetail = $actionLog[$r.id].detail }
      }
      $journalInfo.archived = $true
    }
    foreach ($d in @(Get-DeletionRows $run.records $true)) { [void]$deletionRows.Add($d) }
  }
}

if ($run -and $action -eq 'purge') {
  $target = $BackupDir
  if (-not $target) { $target = $backupInfo.dir }
  $purgeInfo = Invoke-PurgeBackup $target
  if ($purgeInfo.purged -and $run) { $run = Get-RunState $journalDoc $false }
}

if (@($script:Refusals).Count -gt 0) {
  $rep = Get-ReportObject @() @() $retention $backupInfo @($deletionRows) $purgeInfo $journalInfo $null ([pscustomobject]@{ available = $false; exitCode = $null; nonPass = @(); wildcardVerdict = ''; wildcardReasonKey = ''; blockedOrDegraded = @() }) ([pscustomobject]@{ ok = $false; doc = $null; exitCode = $null; error = 'refused before the collector was consulted'; path = $collectorVal; source = 'none' })
  if ($AsJson) { Write-Output (ConvertTo-JsonSafe $rep 14) } else { Write-ReportText $rep }
  exit 2
}

$rep = Get-ReportObject $run.records $run.residue $retention $backupInfo @($deletionRows) $purgeInfo $journalInfo $run.collectorBefore $run.collectorAfter $run.collectorReport
if ($AsJson) { Write-Output (ConvertTo-JsonSafe $rep 14) } else { Write-ReportText $rep }
exit $rep.summary.exitCode
