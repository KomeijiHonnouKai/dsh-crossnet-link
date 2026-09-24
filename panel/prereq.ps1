<#
  prereq.ps1 - read-only PREREQUISITE checker for the cross-network remote-access link (t6).

  LAST UPDATED : 2026-09-24 (v1.1 - t26: removed an internal-document reference from a comment, because
                 publish-set files must not point at material that is not shipped; the comment now
                 states the locale-proof rule itself. v1 - t19: listener source is structured-first and
                 injectable; the netstat state token is a parameter; an unreadable row set is `unknown`,
                 never a pass)
  AUTHOR       : team dsh-crossnet-link-2 (as named at authoring time, after the plugin's then-current name; member "smith", task t6)
  RUNS ON      : Windows PowerShell 5.1 (powershell.exe). No pwsh 7, curl, CIM/WMI or node.

  COMMANDS USED WHILE BUILDING THIS REVISION (all read-only):
    powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/panel/prereq.ps1 -CheckOnly
    powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/panel/prereq.ps1 -CheckOnly -Role client
    powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/panel/prereq.ps1 -CheckOnly -Role server -ShowInstallPlan
    powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/panel/prereq.ps1 -CheckOnly -AsJson
    powershell -NoProfile -ExecutionPolicy Bypass -File dsh-crossnet-link/panel/prereq.ps1 -Describe
    # internal-document sweep: the four internal filenames must not appear in this file (expect 0)
    # non-intrusive check: -CheckOnly prints "Nothing was installed, elevated, signed in, written or changed by this run."

  WHAT IT DOES
    Reads panel/prereq-manifest.json and, for the selected role, runs each item's DETECTION
    (registry / service / listener-by-column / bounded command / file) and prints the verdict.

  THIS SCRIPT HAS NO EXECUTION PATH FOR INSTALLS
    Install commands, verification commands, sha256 policy and rollback commands are only ever
    PRINTED - they are strings from the manifest. There is no -Yes, no -Apply, no -Force here and
    no elevation, no runas, no scheduled task, no service change, no firewall change. The UAC
    prompt and the Tailscale browser sign-in are the operator's, always.

  EXIT CODES (same contract as src/collect.ps1 - useful as a gate)
    0 = every role-relevant prerequisite is satisfied
    1 = degraded and/or unknown (an unavailable probe is unknown, never a pass)
    2 = blocked (a real prerequisite is missing, or the manifest itself is unusable)

  ROLE SEMANTICS (why a client-only machine can see a non-zero exit)
    -Role both (default) validates the server AND client requirement sets. A machine that only
    uses the link is expected to be missing server items, so its verdict is non-zero by design:
    the exit code is a fail-closed verdict, NOT a command failure. Use -Role client to see only
    what a client machine must satisfy.

  READ-ONLY / CREDENTIAL DISCIPLINE
    Writes nothing, ever (there is no output-file switch). Never reads or prints a token, cookie,
    key file or the DSH credential store; the manifest's one token-shaped item is a MANUAL item
    whose text carries no real credential.
#>
[CmdletBinding()]
param(
  [string]$Manifest = '',
  [ValidateSet('server','client','both')][string]$Role = 'both',
  [switch]$CheckOnly,
  [switch]$AsJson,
  [switch]$ShowInstallPlan,
  [switch]$Describe,
  [ValidateSet('auto','zh','en')][string]$Lang = 'auto',
  [string]$DshHome = '',
  [string]$AppDir = '',
  [string]$Port = '',
  [string]$MsiPath = '',
  [int]$CommandTimeoutMs = 15000,
  # --- test-injection seam (t19 F5): replace the listener source, or localize the state token ---
  [string]$NetstatStdoutFixture = '',
  [string]$NetstatStatePattern = '(?i)LISTENING'
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

# ---------------------------------------------------------------------------
# language + label selection (labels come from the manifest itself)
# ---------------------------------------------------------------------------
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
$langUsed = Resolve-Lang $Lang

function Pick-Text {
  param($Node,[string]$Lang)
  if ($null -eq $Node) { return '' }
  $p = $Node.PSObject.Properties[$Lang]
  if ($null -ne $p -and [string]$p.Value) { return [string]$p.Value }
  $q = $Node.PSObject.Properties['en']
  if ($null -ne $q) { return [string]$q.Value }
  return ''
}

# ---------------------------------------------------------------------------
# runtime value resolution (no machine-specific value is ever hardcoded here)
# ---------------------------------------------------------------------------
$cfg = New-Object System.Collections.ArrayList
function Add-Cfg { param([string]$Name,$Value,[string]$Source)
  $v = ''
  if ($null -ne $Value) { $v = [string]$Value }
  [void]$cfg.Add([pscustomobject]@{ name=$Name; value=$v; source=$Source })
}

if ($DshHome) { $dshHomeVal = $DshHome; $dshHomeSrc = 'param' }
elseif ($env:DSH_HOME) { $dshHomeVal = $env:DSH_HOME; $dshHomeSrc = 'env:DSH_HOME' }
elseif ($env:USERPROFILE) { $dshHomeVal = Join-Path $env:USERPROFILE '.dsh'; $dshHomeSrc = 'auto(USERPROFILE/.dsh)' }
else { $dshHomeVal = ''; $dshHomeSrc = 'missing' }
Add-Cfg 'dshHome' $dshHomeVal $dshHomeSrc

if ($Port) { $portVal = $Port; $portSrc = 'param' }
elseif ($env:DSH_WEB_URL -and ($env:DSH_WEB_URL -match ':(?<p>[0-9]{2,5})(/|$)')) { $portVal = $Matches['p']; $portSrc = 'env:DSH_WEB_URL' }
else { $portVal = '43120'; $portSrc = 'builtin-default' }
Add-Cfg 'dshPort' $portVal $portSrc

if ($AppDir) { $appDirVal = $AppDir; $appDirSrc = 'param' }
elseif ($env:DSH_APP_DIR) { $appDirVal = $env:DSH_APP_DIR; $appDirSrc = 'env:DSH_APP_DIR' }
else {
  $appDirVal = ''
  foreach ($proc in @(Get-Process -ErrorAction SilentlyContinue)) {
    $pn = ''
    try { $pn = $proc.ProcessName } catch { $pn = '' }
    if ($pn -notmatch '^dsh') { continue }
    $pp = ''
    try { $pp = $proc.Path } catch { $pp = '' }
    if (-not $pp) { continue }
    $cand = Join-Path (Split-Path -Parent $pp) 'resources\app'
    if (Test-Path -LiteralPath $cand) { $appDirVal = $cand; $appDirSrc = 'auto(process image path)'; break }
  }
  if (-not $appDirVal) { $appDirSrc = 'missing' }
}
Add-Cfg 'appDir' $appDirVal $appDirSrc

$msiVal = $MsiPath
Add-Cfg 'msiPath' $msiVal $(if ($MsiPath) { 'param' } else { 'missing' })

function Resolve-Placeholders {
  param([string]$Text)
  $unresolved = New-Object System.Collections.ArrayList
  $out = [string]$Text
  if ($out -match '<DSH_HOME>') { if ($dshHomeVal) { $out = $out.Replace('<DSH_HOME>', $dshHomeVal) } else { [void]$unresolved.Add('<DSH_HOME>') } }
  if ($out -match '<APP_DIR>') { if ($appDirVal) { $out = $out.Replace('<APP_DIR>', $appDirVal) } else { [void]$unresolved.Add('<APP_DIR>') } }
  if ($out -match '<DSH_PORT>') { $out = $out.Replace('<DSH_PORT>', $portVal) }
  if ($out -match '<MSI_PATH>') { if ($msiVal) { $out = $out.Replace('<MSI_PATH>', $msiVal) } else { [void]$unresolved.Add('<MSI_PATH>') } }
  return [pscustomobject]@{ text=$out; unresolved=@($unresolved.ToArray()) }
}

# ---------------------------------------------------------------------------
# probes (bounded, read-only)
# ---------------------------------------------------------------------------
$script:TextEnc = $null
function Get-SystemTextEncoding {
  if ($null -ne $script:TextEnc) { return $script:TextEnc }
  $enc = $null
  $cp = 0
  try {
    $v = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage' -ErrorAction Stop).OEMCP
    if ($v) { [void][int]::TryParse([string]$v, [ref]$cp) }
  } catch { $cp = 0 }
  if ($cp -gt 0) { try { $enc = [System.Text.Encoding]::GetEncoding($cp) } catch { $enc = $null } }
  if ($null -eq $enc) { try { $enc = [Console]::OutputEncoding } catch { $enc = $null } }
  $script:TextEnc = $enc
  return $enc
}

function Invoke-Bounded {
  param([string]$Exe,[string[]]$ArgList,[int]$TimeoutMs)
  $res = [ordered]@{ available=$false; exitCode=$null; stdout=''; stderr=''; error='' }
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

function ConvertFrom-ListenerText {
  # Text path for netstat-style output. The state token is a PARAMETER (-NetstatStatePattern), so a
  # localized build or a wrapper that rewrites the column can be handled without editing this script,
  # and a row set that could not be read is reported as such instead of silently becoming empty.
  param([string]$Text)
  $rows = New-Object System.Collections.ArrayList
  $tcpRows = 0
  foreach ($ln in @($Text -split "`r?`n")) {
    $trimmed = $ln.Trim()
    if ($trimmed -eq '') { continue }
    $t = @(($trimmed -replace '\s+', ' ') -split ' ')
    if ($t.Count -lt 2 -or $t[0] -ne 'TCP') { continue }
    $tcpRows++
    if (-not ($trimmed -match $NetstatStatePattern)) { continue }
    $a = $t[1]
    $host_ = ''; $port_ = ''
    if ($a.StartsWith('[')) {
      $i = $a.IndexOf(']')
      if ($i -gt 0) { $host_ = $a.Substring(1, $i - 1); if ($a.Length -gt $i + 2) { $port_ = $a.Substring($i + 2) } }
    } else {
      $i = $a.LastIndexOf(':')
      if ($i -gt 0) { $host_ = $a.Substring(0, $i); $port_ = $a.Substring($i + 1) }
    }
    $owner = 0
    if ($t.Count -ge 5) { [void][int]::TryParse($t[4], [ref]$owner) }
    $name = ''
    if ($owner -gt 0) { try { $name = (Get-Process -Id $owner -ErrorAction Stop).ProcessName } catch { $name = '' } }
    [void]$rows.Add([pscustomobject]@{ local=$a; host=$host_; port=$port_; pid=$owner; process=$name })
  }
  return [pscustomobject]@{
    rows = $rows.ToArray()
    tcpRowCount = $tcpRows
    parsedRowCount = $rows.Count
    stateWordUnrecognized = (($tcpRows -gt 0) -and ($rows.Count -eq 0))
  }
}

function Get-ListenerRows {
  # Source order (locale-proof rule L3): structured .NET first, text second, both injectable.
  #   -NetstatStdoutFixture <file>  parse this raw `netstat -ano` text instead of running netstat
  #   -NetstatStatePattern <regex>  the state token the text path keys on
  # ok=$false means "the listener set could not be read" - the caller must turn that into `unknown`,
  # because an empty row set read as "nothing is listening" is exactly the false pass t19 fixes.
  $out = [ordered]@{
    ok = $false; rows = @(); source = ''; error = ''
    tcpRowCount = 0; parsedRowCount = 0
    statePattern = $NetstatStatePattern; stateWordUnrecognized = $false
  }

  if ($NetstatStdoutFixture) {
    if (-not (Test-Path -LiteralPath $NetstatStdoutFixture)) {
      $out.error = 'netstat fixture not found: ' + $NetstatStdoutFixture
      return [pscustomobject]$out
    }
    try { $text = [System.IO.File]::ReadAllText($NetstatStdoutFixture, [System.Text.Encoding]::UTF8) }
    catch { $out.error = 'netstat fixture unreadable: ' + $_.Exception.Message; return [pscustomobject]$out }
    $parsed = ConvertFrom-ListenerText $text
    $out.rows = $parsed.rows; $out.tcpRowCount = $parsed.tcpRowCount
    $out.parsedRowCount = $parsed.parsedRowCount; $out.stateWordUnrecognized = $parsed.stateWordUnrecognized
    $out.source = 'netstat-text(injected)'
    if ($parsed.stateWordUnrecognized) {
      $out.error = 'state token not recognized: raw TCP rows exist but none matched ' + $NetstatStatePattern
      return [pscustomobject]$out
    }
    if ($parsed.parsedRowCount -eq 0) { $out.error = 'the injected snapshot parsed zero rows'; return [pscustomobject]$out }
    $out.ok = $true
    return [pscustomobject]$out
  }

  try {
    $endpoints = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()
    $acc = New-Object System.Collections.ArrayList
    foreach ($ep in @($endpoints)) {
      $h = $ep.Address.ToString()
      $pt = [string]$ep.Port
      $local = $(if ($h.Contains(':')) { '[' + $h + ']:' + $pt } else { $h + ':' + $pt })
      [void]$acc.Add([pscustomobject]@{ local=$local; host=$h; port=$pt; pid=0; process='' })
    }
    if ($acc.Count -gt 0) {
      $out.ok = $true; $out.rows = $acc.ToArray(); $out.parsedRowCount = $acc.Count
      $out.source = 'dotnet(IPGlobalProperties.GetActiveTcpListeners)'
      return [pscustomobject]$out
    }
    $out.error = 'the structured listener API returned no rows'
  } catch {
    $out.error = 'structured listener API failed: ' + $_.Exception.Message
  }

  $netstat = ''
  if ($env:SystemRoot) { $cand = Join-Path $env:SystemRoot 'System32\netstat.exe'; if (Test-Path -LiteralPath $cand) { $netstat = $cand } }
  if (-not $netstat) { try { $netstat = (Get-Command netstat.exe -ErrorAction Stop).Source } catch { $netstat = '' } }
  $probe = Invoke-Bounded $netstat @('-ano') $CommandTimeoutMs
  if (-not $probe.available) {
    $out.error = 'netstat fallback unavailable: ' + $probe.error
    return [pscustomobject]$out
  }
  $parsed = ConvertFrom-ListenerText $probe.stdout
  $out.rows = $parsed.rows; $out.tcpRowCount = $parsed.tcpRowCount
  $out.parsedRowCount = $parsed.parsedRowCount; $out.stateWordUnrecognized = $parsed.stateWordUnrecognized
  $out.source = 'netstat-text'
  if ($parsed.stateWordUnrecognized) {
    $out.error = 'state token not recognized: raw TCP rows exist but none matched ' + $NetstatStatePattern
    return [pscustomobject]$out
  }
  if ($parsed.parsedRowCount -eq 0) { $out.error = 'the netstat snapshot parsed zero rows'; return [pscustomobject]$out }
  $out.ok = $true
  return [pscustomobject]$out
}

function Test-ListenerClass {
  param([string]$HostName,[string]$Class)
  if ($Class -eq 'loopback') { if ($HostName -eq '::1' -or $HostName -match '^127\.') { return $true }; return $false }
  if ($Class -eq 'wildcard') { if ($HostName -eq '0.0.0.0' -or $HostName -eq '::') { return $true }; return $false }
  if ($Class -eq 'tailnet') {
    if ($HostName -match '^100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.\d{1,3}\.\d{1,3}$') { return $true }
    if ($HostName -match '^fd7a:115c:a1e0:') { return $true }
    return $false
  }
  return $false
}

# ---------------------------------------------------------------------------
# manifest
# ---------------------------------------------------------------------------
$root = $PSScriptRoot
if (-not $Manifest) { $Manifest = Join-Path $root 'prereq-manifest.json' }
if (-not (Test-Path -LiteralPath $Manifest)) {
  Write-Output ('MANIFEST MISSING: ' + $Manifest)
  exit 2
}
$doc = $null
try {
  $doc = ([System.IO.File]::ReadAllText($Manifest, [System.Text.Encoding]::UTF8)) | ConvertFrom-Json
} catch {
  Write-Output ('MANIFEST PARSE FAILED: ' + $_.Exception.Message)
  exit 2
}

if ($Describe) {
  Write-Output '== prereq.ps1 -Describe =='
  Write-Output ('manifest : ' + $Manifest)
  Write-Output ('role     : ' + $Role + '   (both validates server AND client sets)')
  Write-Output 'exit     : 0 = all satisfied / 1 = degraded or unknown / 2 = blocked or unusable manifest'
  Write-Output 'writes   : none - there is no output-file switch and no install path in this script'
  Write-Output ''
  Write-Output 'role semantics:'
  foreach ($p in $doc.roleSemantics.PSObject.Properties) { Write-Output ('  ' + $p.Name + ': ' + [string]$p.Value) }
  Write-Output ''
  Write-Output 'automation boundary - allowed:'
  foreach ($line in @($doc.automationBoundary.allowed)) { Write-Output ('  + ' + [string]$line) }
  Write-Output 'automation boundary - never:'
  foreach ($line in @($doc.automationBoundary.never)) { Write-Output ('  x ' + [string]$line) }
  Write-Output ''
  Write-Output ('hash policy: ' + [string]$doc.hashPolicy.rule)
  Write-Output ('pinnedSha256: "' + [string]$doc.hashPolicy.pinnedSha256 + '"')
  Write-Output ('if not pinned: ' + [string]$doc.hashPolicy.ifNotPinned)
  Write-Output ''
  Write-Output ('items: ' + @($doc.items).Count)
  foreach ($it in @($doc.items)) { Write-Output ('  ' + $it.id + '  [' + (@($it.roles) -join ',') + ']  ' + [string]$it.title) }
  exit 0
}

# ---------------------------------------------------------------------------
# evaluate
# ---------------------------------------------------------------------------
$wantServer = ($Role -eq 'server' -or $Role -eq 'both')
$wantClient = ($Role -eq 'client' -or $Role -eq 'both')
$results = New-Object System.Collections.ArrayList
$listenerCache = $null

foreach ($item in @($doc.items)) {
  $roles = @($item.roles)
  $inRole = $false
  foreach ($r in $roles) {
    if ($r -eq 'server' -and $wantServer) { $inRole = $true }
    if ($r -eq 'client' -and $wantClient) { $inRole = $true }
    if ($r -eq 'both') { $inRole = $true }
  }
  if (-not $inRole) { continue }

  $verdict = 'unknown'
  $reasonKey = 'probe_unavailable'
  $raw = [ordered]@{}
  $detect = $item.detect
  $kind = [string]$detect.kind

  if ($kind -eq 'command') {
    $probe = Invoke-Bounded ([string]$detect.command) @($detect.args) $CommandTimeoutMs
    $raw.command = ([string]$detect.command + ' ' + (@($detect.args) -join ' '))
    $raw.available = $probe.available
    $raw.exitCode = $probe.exitCode
    $raw.stderr = [string](@(($probe.stderr -split "`r?`n") | Where-Object { $_.Trim() -ne '' }) | Select-Object -First 1)
    $want = ''
    if ($null -ne $detect.expect) { $want = [string]$detect.expect.exitCode }
    if (-not $probe.available) { $verdict = 'blocked'; $reasonKey = 'not_installed' }
    elseif ($probe.exitCode -eq [int]$want) { $verdict = 'pass'; $reasonKey = 'command_ok' }
    # Measured on the reference machine: the daemon-pipe refusal text is English even on a
    # zh-CN box, so this script stays ASCII-only and matches the English marker only.
    elseif ($probe.stderr -match 'ProtectedPrefix|Access is denied') { $verdict = 'unknown'; $reasonKey = 'probe_denied' }
    elseif ($probe.error) { $verdict = 'unknown'; $reasonKey = 'probe_timeout' }
    else { $verdict = 'blocked'; $reasonKey = 'command_failed' }
  } elseif ($kind -eq 'registry') {
    $rp = Resolve-Placeholders ([string]$detect.path)
    $raw.path = $rp.text
    if (@($rp.unresolved).Count -gt 0) { $verdict = 'unknown'; $reasonKey = 'placeholder_unresolved'; $raw.unresolved = @($rp.unresolved) }
    else {
      try {
        $props = Get-ItemProperty -Path $rp.text -ErrorAction Stop
        $raw.exists = $true
        if ($null -ne $detect.value) {
          $pv = $props.PSObject.Properties[[string]$detect.value]
          $raw.value = $(if ($null -ne $pv) { $pv.Value } else { $null })
          if ($null -eq $pv) { $verdict = 'unknown'; $reasonKey = 'value_absent' }
          elseif ($null -ne $detect.expect -and $null -ne $detect.expect.equals) {
            if ([string]$pv.Value -eq [string]$detect.expect.equals) { $verdict = 'pass'; $reasonKey = 'registry_ok' } else { $verdict = 'blocked'; $reasonKey = 'registry_mismatch' }
          } else { $verdict = 'pass'; $reasonKey = 'registry_ok' }
        } elseif ($null -ne $detect.contains) {
          $found = $false
          foreach ($pr in $props.PSObject.Properties) { if ($pr.Name -notlike 'PS*' -and ([string]$pr.Value) -match [regex]::Escape([string]$detect.contains)) { $found = $true; break } }
          $raw.contains = [string]$detect.contains
          $raw.containsFound = $found
          if ($found) { $verdict = 'pass'; $reasonKey = 'registry_ok' } else { $verdict = 'blocked'; $reasonKey = 'registry_missing' }
        } else { $verdict = 'pass'; $reasonKey = 'registry_ok' }
      } catch { $verdict = 'unknown'; $reasonKey = 'registry_unreadable'; $raw.error = $_.Exception.Message }
    }
  } elseif ($kind -eq 'listener') {
    if ($null -eq $listenerCache) { $listenerCache = Get-ListenerRows }
    $raw.source = $listenerCache.source
    $raw.statePattern = $listenerCache.statePattern
    $raw.tcpRowCount = $listenerCache.tcpRowCount
    $raw.parsedRowCount = $listenerCache.parsedRowCount
    $raw.stateWordUnrecognized = $listenerCache.stateWordUnrecognized
    if (-not $listenerCache.ok) {
      # t19 F5: an unreadable listener source must never read as "the port is not exposed".
      $verdict = 'unknown'; $reasonKey = 'listener_source_unreadable'; $raw.error = $listenerCache.error
    }
    else {
      $class = [string]$detect.addressClass
      $portWant = [string]$detect.port
      $portWant = (Resolve-Placeholders $portWant).text
      $hits = New-Object System.Collections.ArrayList
      foreach ($row in @($listenerCache.rows)) {
        if (-not (Test-ListenerClass $row.host $class)) { continue }
        if ($portWant -and $row.port -ne $portWant) { continue }
        [void]$hits.Add([ordered]@{ local=$row.local; pid=$row.pid; process=$row.process })
      }
      $raw.addressClass = $class
      $raw.port = $portWant
      $raw.hits = $hits.ToArray()
      if ($hits.Count -gt 0) { $verdict = 'pass'; $reasonKey = 'listener_ok' } else { $verdict = 'blocked'; $reasonKey = 'listener_missing' }
    }
  } elseif ($kind -eq 'file') {
    $fp = Resolve-Placeholders ([string]$detect.path)
    $raw.path = $fp.text
    if (@($fp.unresolved).Count -gt 0) { $verdict = 'unknown'; $reasonKey = 'placeholder_unresolved'; $raw.unresolved = @($fp.unresolved) }
    elseif (-not (Test-Path -LiteralPath $fp.text)) { $verdict = 'unknown'; $reasonKey = 'file_absent' }
    else {
      try {
        $text = [System.IO.File]::ReadAllText($fp.text, [System.Text.Encoding]::UTF8)
        $needle = [string]$detect.contains
        $raw.contains = $needle
        $raw.containsFound = ($text -match [regex]::Escape($needle))
        if ($raw.containsFound) { $verdict = 'pass'; $reasonKey = 'file_contains' } else { $verdict = 'blocked'; $reasonKey = 'file_lacks_key' }
      } catch { $verdict = 'unknown'; $reasonKey = 'file_unreadable'; $raw.error = $_.Exception.Message }
    }
  } elseif ($kind -eq 'delegate') {
    $verdict = 'unknown'
    $reasonKey = 'delegated'
    $raw.delegateCommand = (Resolve-Placeholders ([string]$detect.command)).text
  } elseif ($kind -eq 'manual') {
    $verdict = 'unknown'
    $reasonKey = 'manual_only'
  } else {
    $verdict = 'unknown'
    $reasonKey = 'unsupported_detect_kind'
    $raw.kind = $kind
  }

  $install = $item.install
  $installCmd = ''
  $installHuman = @()
  $rollback = ''
  $verifyLines = @()
  if ($null -ne $install) {
    if ($null -ne $install.command) { $installCmd = (Resolve-Placeholders ([string]$install.command)).text }
    if ($null -ne $install.humanSteps) { $installHuman = @($install.humanSteps) }
    if ($null -ne $install.verify) {
      foreach ($vline in @($install.verify)) { $verifyLines += (Resolve-Placeholders ([string]$vline)).text }
    }
    if ($null -ne $install.rollback) { $rollback = (Resolve-Placeholders ([string]$install.rollback)).text }
  } elseif ($null -ne $item.rollback) { $rollback = [string]$item.rollback }

  # Hash gate: shown ONLY for the MSI-style install step, and never satisfied by this script.
  $hashGate = $null
  if ($installCmd -match 'msiexec') {
    $pinned = [string]$doc.hashPolicy.pinnedSha256
    $gateVerdict = 'unknown'
    $gateReason = 'no_msi_path'
    $computed = ''
    $signature = ''
    if ($pinned) {
      if ($msiVal) {
        try {
          $computed = (Get-FileHash -LiteralPath $msiVal -Algorithm SHA256 -ErrorAction Stop).Hash
          if ($computed -eq $pinned) { $gateVerdict = 'pass'; $gateReason = 'hash_matches' }
          else { $gateVerdict = 'blocked'; $gateReason = 'hash_mismatch' }
        } catch { $gateVerdict = 'unknown'; $gateReason = 'hash_unreadable' }
        try {
          $sig = Get-AuthenticodeSignature -LiteralPath $msiVal -ErrorAction Stop
          $signer = ''
          if ($sig.SignerCertificate) { $signer = $sig.SignerCertificate.Subject }
          $signature = ([string]$sig.Status + ' | ' + $signer)
        } catch { $signature = '' }
      } else {
        $gateVerdict = 'unknown'
        $gateReason = 'no_msi_path'
      }
    } else {
      $gateVerdict = 'blocked'
      $gateReason = 'hash_not_pinned'
    }
    $hashGate = [ordered]@{
      rule = [string]$doc.hashPolicy.rule
      pinnedSha256 = $pinned
      computedSha256 = $computed
      msiPath = $msiVal
      signatureStatus = $signature
      gateVerdict = $gateVerdict
      gateReason = $gateReason
      confirmPhrase = [string]$doc.hashPolicy.confirmPhrase
      howToPin = @($doc.hashPolicy.howToPin)
      ifNotPinned = [string]$doc.hashPolicy.ifNotPinned
      executedByThisScript = $false
    }
  }

  [void]$results.Add([pscustomobject][ordered]@{
    id = [string]$item.id
    title = [string]$item.title
    roles = $roles
    detectKind = $kind
    verdict = $verdict
    reasonKey = $reasonKey
    missingMessage = (Pick-Text $item.whenMissing $langUsed)
    probeMessage = (Pick-Text $doc.probeUnavailable $langUsed)
    probeUnreadable = ($reasonKey -eq 'listener_source_unreadable')
    installCommand = $installCmd
    installHumanSteps = $installHuman
    verify = $verifyLines
    rollback = $rollback
    hashGate = $hashGate
    raw = $raw
  })
}

# ---------------------------------------------------------------------------
# report + exit code
# ---------------------------------------------------------------------------
$nPass = 0; $nDeg = 0; $nBlk = 0; $nUnk = 0
foreach ($r in $results) {
  switch ($r.verdict) {
    'pass' { $nPass++ }
    'degraded' { $nDeg++ }
    'blocked' { $nBlk++ }
    default { $nUnk++ }
  }
}
$exitCode = 0
if ($nBlk -gt 0) { $exitCode = 2 }
elseif ($nUnk -gt 0) { $exitCode = 1 }

$overall = 'pass'
if ($exitCode -eq 1) { $overall = 'degraded' }
if ($exitCode -eq 2) { $overall = 'blocked' }

$report = [pscustomobject][ordered]@{
  schema = 'dsh-crossnet-link/prereq-report/1'
  generatedAtLocal = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
  manifest = $Manifest
  role = $Role
  lang = $langUsed
  readOnly = $true
  ranAnyInstall = $false
  config = @($cfg)
  roleSemantics = $doc.roleSemantics
  automationBoundary = $doc.automationBoundary
  summary = [ordered]@{
    total = @($results).Count
    pass = $nPass
    degraded = $nDeg
    blocked = $nBlk
    unknown = $nUnk
    verdict = $overall
    exitCode = $exitCode
    failClosed = 'an unavailable probe is unknown, and any unknown forbids exit 0'
  }
  items = @($results)
}

if ($AsJson) {
  Write-Output ($report | ConvertTo-Json -Depth 12)
} else {
  Write-Output '== dsh-crossnet-link prerequisite check (read-only) =='
  Write-Output ('manifest=' + $Manifest + '  role=' + $Role + '  lang=' + $langUsed)
  Write-Output 'This script never runs an installer, never elevates and never signs in to anything.'
  Write-Output ''
  foreach ($r in $results) {
    Write-Output ('[' + $r.verdict.ToUpper() + '] ' + $r.id + ' - ' + $r.title + '  (' + $r.detectKind + '/' + $r.reasonKey + ')')
    if ($r.verdict -ne 'pass') {
      $whyText = $r.missingMessage
      if ($r.probeUnreadable -and $r.probeMessage) { $whyText = $r.probeMessage }
      if ($whyText) { Write-Output ('    why: ' + $whyText) }
      foreach ($step in @($r.installHumanSteps)) { Write-Output ('    do: ' + [string]$step) }
      if ($r.installCommand) { Write-Output ('    cmd (yours to run): ' + ($r.installCommand -replace "`r?`n", ' ; ')) }
      if ($r.hashGate) {
        Write-Output ('    hash gate: ' + $r.hashGate.gateVerdict + ' (' + $r.hashGate.gateReason + ')  pinned="' + $r.hashGate.pinnedSha256 + '"  computed="' + $r.hashGate.computedSha256 + '"')
        Write-Output ('    hash rule: ' + $r.hashGate.rule)
      }
      foreach ($vline in @($r.verify)) { Write-Output ('    verify: ' + $vline) }
      if ($r.rollback) { Write-Output ('    rollback: ' + ($r.rollback -replace "`r?`n", ' ; ')) }
    } elseif ($ShowInstallPlan) {
      if ($r.installCommand) { Write-Output ('    install: ' + ($r.installCommand -replace "`r?`n", ' ; ')) }
      foreach ($vline in @($r.verify)) { Write-Output ('    verify: ' + $vline) }
      if ($r.rollback) { Write-Output ('    rollback: ' + ($r.rollback -replace "`r?`n", ' ; ')) }
    }
  }
  Write-Output ''
  Write-Output ('summary: total=' + @($results).Count + ' pass=' + $nPass + ' degraded=' + $nDeg + ' blocked=' + $nBlk + ' unknown=' + $nUnk)
  Write-Output ('overall: ' + $overall + ' -> exit ' + $exitCode)
  Write-Output 'Reading the exit code: 0 = satisfied; 1 = degraded/unknown; 2 = blocked.'
  Write-Output 'A non-zero code is a fail-closed VERDICT, not a command failure.'
  Write-Output ('Role note: with -Role both (default) a client-only machine is expected to be missing server items -> non-zero. Use -Role client for a client-only machine.')
  Write-Output 'Nothing was installed, elevated, signed in, written or changed by this run.'
}

exit $exitCode
