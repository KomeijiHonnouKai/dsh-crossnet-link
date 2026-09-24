<#
  collect.ps1 - read-only collector / judge for a cross-network remote-access link
                (Tailscale + "tailscale serve" fronting a loopback-only DSH port).

  LAST UPDATED : 2026-09-24 (v0.3 - t23: SERVE_PRESENT now judges ONLY the proxy TARGET port from a
                 readable "tailscale serve status" - target != measured DSH port => blocked /
                 serve_port_mismatch (with command + rollback); unreadable or no parsable target =>
                 unknown. The tailnet LISTENER SHAPE is explicitly NOT evidence; the t22 experiment
                 that disproved it is recorded in docs/defensive-spec.md section 7.1. Earlier: v0.2
                 for t5 (encoding/PROBE fixes, i18n pattern merge, fixture layer, -DumpFixture),
                 then t16/t19 added the injectable locale-proof state pattern and the fail-closed
                 guards.)
  AUTHOR       : team remote-tailnet-guard-2 (member "smith", task t5)
  RUNS ON      : Windows PowerShell 5.1 (powershell.exe). Does NOT require pwsh 7,
                 curl, CIM/WMI, node, or any third-party module.

  COMMANDS USED WHILE BUILDING THIS REVISION (all read-only; no writes anywhere):
    powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/src/collect.ps1 -CheckOnly
    powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/src/collect.ps1 -CheckOnly -AsJson
    powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/src/collect.ps1 -CheckOnly -Role server
    powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/src/collect.ps1 -CheckOnly -Role client
    powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/src/collect.ps1 -CheckOnly -ShowRaw
    powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/src/collect.ps1 -CheckOnly -Strictness strict
    powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/src/collect.ps1 -CheckOnly -AsJson -FixturePath remote-tailnet-plugin/tests/fixtures/zh.json -NoNative
    powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/src/collect.ps1 -CheckOnly -AsJson -FixturePath remote-tailnet-plugin/tests/fixtures/en.json -NoNative
    powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/src/collect.ps1 -CheckOnly -Role both -DumpFixture remote-tailnet-plugin/tests/fixtures/zh.json
    powershell -NoProfile -ExecutionPolicy Bypass -File remote-tailnet-plugin/tests/run-fixtures.ps1
    powershell -NoProfile -Command '$f="remote-tailnet-plugin/src/collect.ps1"; $b=[IO.File]::ReadAllBytes((Resolve-Path $f)); $e=$null; [void][Management.Automation.Language.Parser]::ParseFile((Resolve-Path $f),[ref]$null,[ref]$e); "bom=" + ($b[0..2] -join ",") + " errors=" + @($e).Count'
    powershell -NoProfile -Command '(netstat -ano | Select-String "(0\.0\.0\.0|\[::\]):43120").Count'
  Live probes that drove the implementation decisions (see docs/collect.md sections 6.1-6.6):
    netsh advfirewall monitor show currentprofile | firewall show rule name=Tailscale-Process verbose | show allprofiles
    powercfg /query SCHEME_CURRENT <SUB_SLEEP> <STANDBYIDLE|HIBERNATEIDLE> ; powercfg /a
    registry: Nls\CodePage (OEMCP), Nls\Language (InstallLanguage), FirewallRules,
              FirewallPolicy\*Profile\EnableFirewall, HKLM\...\CurrentVersion, Internet Settings
    Cordis host Inspect only (cordis_inspect_list / platform="host" Service queries) - never client Inspect

  EXIT CODE (gate semantics; this deliberately replaces the old "always exit 0" verify):
    0 = safe / pass    : every emitted judgement is "pass" - no unknown, no degraded,
                         no blocked. (fail-closed: any unknown forbids 0.)
    1 = degraded       : at least one degraded, and/or at least one unknown. The link may
                         work but something is unproven or reduced.
    2 = blocked / unusable : at least one blocked, or the collector itself could not run
                         (missing fixture, unusable probe set, refused -Apply).
    -Strictness strict raises "unknown" to 2 (unknown is never silently downgraded).

  READ-ONLY CONTRACT (violating it is a task failure):
    * Never writes system configuration, never edits a DSH profile, never adds a listener,
      never starts/stops/reconfigures a service, never spawns "tailscale serve".
    * Never reads, prints, stores or transmits any credential material. The collector never
      opens the credential store, the DSH bridge token file, or any browser cookie
      database. Check CREDENTIAL_DISCIPLINE re-audits every probe command string it
      executed and fails closed if a secret-store hint appears in one.
    * The only writes this script can ever perform are OPT-IN report/capture files, and only
      when the caller explicitly passes -OutFile <path> or -DumpFixture <path>.
      Default: zero bytes written.
    * -Apply is accepted but REFUSED on purpose: this revision has no write path. It prints
      the remediation and rollback commands for a human to run and exits 2.
    * Self-proof: a listener snapshot is taken before and after collection and compared;
      check NO_NEW_WILDCARD_LISTENER fails if any wildcard (0.0.0.0 / [::]) TCP listener
      appeared during the run.

  LOCALE-PROOFING (why this file is pure ASCII):
    Windows PowerShell 5.1 decodes a BOM-less script as ANSI, so a script containing
    non-ASCII text can turn into a wall of fake syntax errors on another machine. This
    script therefore contains ASCII only (no BOM needed, portable to any code page), and
    every human-readable label lives in i18n/labels.<lang>.json, read with an EXPLICIT
    UTF-8 decoder. Judgements never depend on localized text: OS build comes from the
    registry, firewall state from the registry (EnableFirewall) and from rule values whose
    keys are ASCII ("Edge=TRUE"), power values from raw "0x00000000" tokens, service state
    from Get-Service. The two places where Windows offers no non-localized source (the
    adapter-to-firewall-profile mapping and the sleep-state catalogue) are parsed
    structurally and are FIXTURE-INJECTABLE; if the structure does not match, the verdict
    is "unknown" with the raw output attached - the script never guesses.

  FIXTURE INJECTION (so this collector can be tested with no Tailscale, no elevation and
  no Windows at hand): every external command, registry read, file read, service query,
  TCP probe and DNS probe goes through one probe layer. Pass -FixturePath <json> to
  replace the inputs; add -NoNative to forbid real access entirely (every probe missing
  from the fixture then becomes "unknown", which is the fail-closed expectation).

  PORTABILITY SELF-ASSESSMENT ("can a stranger clone this and just run it?"):
    * No user name, no host name, no drive letter, no tailnet name, no peer address and no
      DSH path is hardcoded. DSH_HOME, the app directory, the DSH port, the peer, the
      timeouts and the trusted-host pattern are all resolved as
      param > environment > auto-discovery > documented builtin default, and the report
      prints which source supplied each value (report.config[]).
    * Long-lived OS constants are used where the OS defines them (subgroup/setting GUIDs
      for power, the firewall rule registry path, "Tailscale" as the product/service name).
      These are identical on every Windows box, not machine specifics.
    * Still environment-dependent (listed honestly, see docs/collect.md):
      - firewall rule names are Tailscale's own ("Tailscale-Process", "Tailscale-In");
        a renamed rule makes CREDENTIAL-free checks report "unknown"/"blocked" instead of
        guessing;
      - the adapter-to-profile mapping needs an English-ish section header from netsh
        (absent on a fully localized Windows) -> "unknown" + raw output for manual reading;
      - tailnet address discovery needs a 100.64.0.0/10 address to be present, i.e. a
        logged-in Tailscale;
      - non-elevated runs cannot use Get-NetFirewallRule/Get-NetConnectionProfile; the
        collector was designed around that and uses netsh + registry instead.
#>
[CmdletBinding()]
param(
  # Read-only mode is the DEFAULT; -CheckOnly just states it explicitly and every
  # remediation is printed for a human instead of being executed.
  [switch]$CheckOnly,
  # Machine-readable report on stdout (nothing else is written to stdout in this mode).
  [switch]$AsJson,
  # Which perspective to collect: server candidate, client candidate, or both.
  [ValidateSet('server','client','both')][string]$Role = 'both',
  [ValidateSet('auto','zh','en')][string]$Lang = 'auto',
  [string]$LabelsDir = '',
  # DSH loopback HTTP port. Empty -> env DSH_WEB_URL -> builtin default (documented).
  [string]$Port = '',
  # Tailnet DNS suffix (e.g. tailXXXX.ts.net). When given it becomes the trusted-host
  # pattern; when omitted the built-in suffix pattern is used and labelled as such.
  [string]$TailnetDomain = '',
  # Which DSH profile to read patch files from. Required when several profiles exist:
  # the collector never silently picks the first one (defensive-spec section 7 case 9).
  [string]$Profile = '',
  # Peer (the other end of the link): IP or MagicDNS host name.
  [string]$Peer = '',
  # Peer MagicDNS name, when -Peer was given as an IP or when name resolution matters.
  [string]$PeerName = '',
  [string]$DshHome = '',
  [string]$AppDir = '',
  [string]$FixturePath = '',
  [switch]$NoNative,
  [ValidateSet('normal','strict')][string]$Strictness = 'normal',
  [int]$TcpTimeoutMs = 5000,
  [int]$DnsTimeoutMs = 4000,
  [int]$CommandTimeoutMs = 15000,
  # 0 = auto (registry NLS OEMCP). Override when the OEM code page mis-decodes a tool.
  [int]$OutputCodePage = 0,
  [hashtable]$ToolPath = @{},
  [string]$TrustedHostPattern = '\.ts\.net$',
  [string]$OutFile = '',
  # Print the configuration surface, the exit-code contract and the explicit
  # unsupported list, then exit 0 (no probing at all).
  [switch]$Describe,
  # Opt-in write #2: capture every probe result into a replayable fixture file, then exit 0.
  # This is how a fixture for another machine (or for t11) is produced honestly.
  [string]$DumpFixture = '',
  [switch]$ShowRaw,
  # Accepted so that a caller cannot "silently write". Always refused.
  [switch]$Apply
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

# Long-lived OS constants (identical on every Windows box - not machine specifics).
$SUB_SLEEP      = '238c9fa8-0aad-41ed-83f4-97be242c8f20'  # subgroup: sleep
$SET_STANDBY    = '29f6c1db-86da-48c5-9fdb-f2b67b1f44da'  # setting alias STANDBYIDLE
$SET_HIBERNATE  = '9d7815a6-7ee4-497e-8888-515a05f02364'  # setting alias HIBERNATEIDLE

$script:Now = Get-Date
$script:OutputCodePage = $OutputCodePage
$script:Checks = New-Object System.Collections.ArrayList
$script:Fixture = $null
$script:NoNative = [bool]$NoNative
$script:MissingLabels = New-Object System.Collections.ArrayList
$script:LabelKeysSeen = New-Object System.Collections.ArrayList
$script:CollectorFaults = New-Object System.Collections.ArrayList

# ---------------------------------------------------------------------------
# section 1: i18n label layer (ASCII script + external UTF-8 label files)
# ---------------------------------------------------------------------------
$script:Labels = $null
$script:LangUsed = 'en'
# Patterns are LOCALE DATA, not presentation: they are merged from every label file found,
# so a machine whose display language is English can still parse a Chinese netsh output
# (and a machine whose OS language is not en/zh can be supported by dropping in
# labels.<lang>.json with that locale's netsh field names).
$script:Patterns = @{}
$script:PatternSources = New-Object System.Collections.ArrayList

function Resolve-Lang {
  param([string]$Requested)
  if ($Requested -ne 'auto') { return $Requested }
  try {
    $c = [System.Globalization.CultureInfo]::CurrentUICulture
    if ($c -and $c.TwoLetterISOLanguageName -eq 'zh') { return 'zh' }
  } catch { }
  # A redirected/derived host process may run with a different UI culture than the OS
  # (measured: CurrentUICulture en-US on a zh-CN machine) - so also ask for the OS one.
  try {
    $c2 = [System.Globalization.CultureInfo]::InstalledUICulture
    if ($c2 -and $c2.TwoLetterISOLanguageName -eq 'zh') { return 'zh' }
  } catch { }
  # last resort: the installed language ID from the registry. It is a hex LCID whose low
  # byte is the primary language (0x04 = Chinese). NOTE: a regex like '^0*4' does NOT work
  # here - measured trap - the value is '0804' and the leading '8' stops the match.
  try {
    $nls = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language' -ErrorAction Stop
    foreach ($n in @('InstallLanguage','Default')) {
      $raw = [string]$nls.$n
      $lcid = 0
      if ([int]::TryParse($raw, [System.Globalization.NumberStyles]::HexNumber, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$lcid)) {
        if (($lcid -band 0xFF) -eq 0x04) { return 'zh' }
      }
    }
  } catch { }
  return 'en'
}

function Load-Labels {
  param([string]$Lang,[string]$Dir)
  $p = Join-Path $Dir ("labels." + $Lang + ".json")
  if (-not (Test-Path -LiteralPath $p)) { return $false }
  try {
    $txt = [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8)
    $script:Labels = $txt | ConvertFrom-Json
    return $true
  } catch { return $false }
}

function Merge-Patterns {
  param([string]$Dir)
  if (-not (Test-Path -LiteralPath $Dir)) { return }
  foreach ($fp in @(Get-ChildItem -LiteralPath $Dir -Filter 'labels.*.json' -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
    $loaded = $false
    try {
      $doc = ([System.IO.File]::ReadAllText($fp.FullName, [System.Text.Encoding]::UTF8)) | ConvertFrom-Json
      $ps = $doc.PSObject.Properties['patterns']
      if ($null -ne $ps) {
        foreach ($pr in $ps.Value.PSObject.Properties) { $script:Patterns[$pr.Name] = [string]$pr.Value }
        $loaded = $true
      }
    } catch { }
    if ($loaded -and -not $script:PatternSources.Contains($fp.Name)) { [void]$script:PatternSources.Add($fp.Name) }
  }
}

function L {
  param([string]$Section,[string]$Key)
  if ($null -eq $script:Labels) { return $null }
  $s = $script:Labels.PSObject.Properties[$Section]
  if ($null -eq $s) { return $null }
  $v = $s.Value.PSObject.Properties[$Key]
  if ($null -eq $v) { return $null }
  return [string]$v.Value
}

# label with missing-key accounting (full name is section-qualified)
# NOTE: the format argument is deliberately NOT named $Args - $Args is a PowerShell
# automatic variable and using it silently prevented {0} substitution (measured bug).
function LF {
  param([string]$Section,[string]$Key,[object[]]$FmtArgs)
  $full = $Section + '.' + $Key
  if (-not $script:LabelKeysSeen.Contains($full)) { [void]$script:LabelKeysSeen.Add($full) }
  $t = L $Section $Key
  if ($null -eq $t) {
    if (-not $script:MissingLabels.Contains($full)) { [void]$script:MissingLabels.Add($full) }
    return $null
  }
  if ($null -ne $FmtArgs -and $FmtArgs.Count -gt 0) {
    try { return ($t -f $FmtArgs) } catch { return $t }
  }
  return $t
}

# label with an explicit fallback (never returns null)
function LV {
  param([string]$Section,[string]$Key,[string]$Fallback)
  $t = LF $Section $Key @()
  if ($null -eq $t) { return $Fallback }
  return $t
}

# Localized TEXT PATTERNS live in the label files, never in this ASCII script.
# Measured: with stdout redirected, netsh prints localized field names even though the same
# command shows English field names in an interactive console. The localized spellings
# (zh-CN: edge-traversal / private-profile / state) therefore live in the label files as
# pattern strings, never inline here. A pattern that does not match yields "unknown" plus
# the raw output - this script never guesses from position.
function Get-Pattern {
  param([string]$Key,[string]$Fallback)
  if ($script:Patterns.ContainsKey($Key)) {
    $v = [string]$script:Patterns[$Key]
    if ($v) { return $v }
  }
  $full = 'patterns.' + $Key
  if (-not $script:MissingLabels.Contains($full)) { [void]$script:MissingLabels.Add($full) }
  return $Fallback
}

# localized yes/no/on/off values -> canonical Yes / No
function ConvertTo-YesNo {
  param([string]$V)
  if ($null -eq $V) { return '' }
  $t = $V.Trim()
  $yes = Get-Pattern 'value_yes' 'Yes|Enabled|On|TRUE'
  $no = Get-Pattern 'value_no' 'No|Disabled|Off|FALSE'
  if ($t -match ('(?i)^(?:' + $yes + ')$')) { return 'Yes' }
  if ($t -match ('(?i)^(?:' + $no + ')$')) { return 'No' }
  return $t
}

# one line of "netsh advfirewall monitor show currentprofile" -> canonical profile name
function Get-ProfileFromHeaderLine {
  param([string]$Line)
  if ($null -eq $Line) { return '' }
  $map = @(
    @{ name='Domain';  pat=(Get-Pattern 'netsh_profile_domain'  '(?i)^\s*Domain\s+Profile\s*:?\s*$') },
    @{ name='Private'; pat=(Get-Pattern 'netsh_profile_private' '(?i)^\s*Private\s+Profile\s*:?\s*$') },
    @{ name='Public';  pat=(Get-Pattern 'netsh_profile_public'  '(?i)^\s*Public\s+Profile\s*:?\s*$') }
  )
  foreach ($e in $map) {
    if ($Line -match $e.pat) { return $e.name }
  }
  return ''
}

function Normalize-ProfileName {
  param([string]$V)
  if ($null -eq $V) { return '' }
  if ($V -eq 'DomainAuthenticated') { return 'Domain' }
  if ($V -eq 'Domain' -or $V -eq 'Private' -or $V -eq 'Public') { return $V }
  return ''
}

# ---------------------------------------------------------------------------
# section 2: probe layer (single choke point for every external input)
# ---------------------------------------------------------------------------
function Get-FixtureProp {
  param([string]$Section,[string]$Key)
  if ($null -eq $script:Fixture) { return $null }
  $s = $script:Fixture.PSObject.Properties[$Section]
  if ($null -eq $s) { return $null }
  $v = $s.Value.PSObject.Properties[$Key]
  if ($null -eq $v) { return $null }
  return $v.Value
}

# Every probe result is recorded under "<section>.<key>" so that -DumpFixture can write a
# replayable fixture and t11 can test this collector with no Tailscale, no elevation and
# no network at all.
$script:ProbeLog = [ordered]@{}
function Add-ProbeLog {
  param([string]$Path,$Value)
  $script:ProbeLog[$Path] = $Value
}

# Decoding for captured native output.
# Windows command-line tools (netsh, powercfg) write in the system OEM code page -
# measured: with stdout redirected, netsh emits CP936 on a zh-CN box while
# [Console]::OutputEncoding reports utf-8, so the default decoding produces mojibake
# (and thus a false "unparsed" verdict). The OEM code page is read from the registry,
# which is locale-independent, and can be overridden with -OutputCodePage.
$script:TextEnc = $null
function Get-SystemTextEncoding {
  if ($null -ne $script:TextEnc) { return $script:TextEnc }
  $enc = $null
  $cp = 0
  if ($script:OutputCodePage -gt 0) { $cp = $script:OutputCodePage }
  if ($cp -le 0) {
    try {
      $v = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage' -ErrorAction Stop).OEMCP
      if ($v) { [void][int]::TryParse([string]$v, [ref]$cp) }
    } catch { $cp = 0 }
  }
  if ($cp -gt 0) { try { $enc = [System.Text.Encoding]::GetEncoding($cp) } catch { $enc = $null } }
  if ($null -eq $enc) { try { $enc = [Console]::OutputEncoding } catch { $enc = $null } }
  $script:TextEnc = $enc
  return $enc
}

function Test-FixtureUnavailable {
  param($Node)
  if ($null -eq $Node) { return $false }
  if ($Node -is [string]) { return $false }
  $p = $Node.PSObject.Properties['_available']
  if ($null -ne $p -and -not [bool]$p.Value) { return $true }
  return $false
}

function Get-FixtureError {
  param($Node)
  if ($null -eq $Node) { return '' }
  if ($Node -is [string]) { return '' }
  $p = $Node.PSObject.Properties['_error']
  if ($null -ne $p) { return [string]$p.Value }
  return ''
}

function Invoke-External {
  param([string]$Key,[string]$Exe,[string[]]$ArgList,[int]$TimeoutMs)
  $res = [ordered]@{ key=$Key; kind='external'; available=$false; exitCode=$null; stdout=''; stderr=''; source=''; error='' }
  $fx = Get-FixtureProp 'native' $Key
  if ($null -ne $fx) {
    $res.source = 'fixture'
    if (Test-FixtureUnavailable $fx) { $res.error = (Get-FixtureError $fx); return $res }
    $res.available = $true
    $ec = $fx.PSObject.Properties['exitCode']
    if ($null -ne $ec) { $res.exitCode = $ec.Value } else { $res.exitCode = 0 }
    $so = $fx.PSObject.Properties['stdout']; if ($null -ne $so) { $res.stdout = [string]$so.Value }
    $se = $fx.PSObject.Properties['stderr']; if ($null -ne $se) { $res.stderr = [string]$se.Value }
    return $res
  }
  if ($script:NoNative) { $res.source = 'fixture-missing'; $res.error = 'probe absent from fixture and native access disabled'; return $res }
  if (-not $Exe -or -not (Test-Path -LiteralPath $Exe)) { $res.error = 'executable not resolvable'; return $res }
  try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
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
    $res.source = 'native'
    if ($finished) { $res.exitCode = $p.ExitCode } else { $res.error = ("timeout after " + $TimeoutMs + " ms (process killed)") }
  } catch { $res.error = $_.Exception.Message }
  if ($res.available) {
    Add-ProbeLog ('native.' + $Key) ([ordered]@{ exitCode=$res.exitCode; stdout=$res.stdout; stderr=$res.stderr })
  } else {
    Add-ProbeLog ('native.' + $Key) ([ordered]@{ _available=$false; _error=$res.error })
  }
  return $res
}

function Get-RegProbe {
  param([string]$Key,[string]$Path,[string[]]$Names)
  $res = [ordered]@{ key=$Key; kind='registry'; available=$false; path=$Path; values=@{}; source=''; error='' }
  $fx = Get-FixtureProp 'registry' $Key
  if ($null -ne $fx) {
    $res.source = 'fixture'
    if (Test-FixtureUnavailable $fx) { $res.error = (Get-FixtureError $fx); return $res }
    $res.available = $true
    foreach ($pr in $fx.PSObject.Properties) { if ($pr.Name -notlike '_*') { $res.values[$pr.Name] = $pr.Value } }
    return $res
  }
  if ($script:NoNative) { $res.source = 'fixture-missing'; $res.error = 'probe absent from fixture and native access disabled'; return $res }
  try {
    $item = Get-ItemProperty -Path $Path -ErrorAction Stop
    $res.available = $true
    $res.source = 'native'
    if ($Names -and $Names.Count -gt 0) {
      foreach ($n in $Names) {
        $pv = $item.PSObject.Properties[$n]
        if ($null -ne $pv) { $res.values[$n] = $pv.Value } else { $res.values[$n] = $null }
      }
    } else {
      foreach ($pr in $item.PSObject.Properties) { if ($pr.Name -notlike 'PS*') { $res.values[$pr.Name] = $pr.Value } }
    }
  } catch { $res.error = $_.Exception.Message }
  if ($res.available) { Add-ProbeLog ('registry.' + $Key) ($res.values) }
  else { Add-ProbeLog ('registry.' + $Key) ([ordered]@{ _available=$false; _error=$res.error }) }
  return $res
}

function Get-FileProbe {
  param([string]$Key,[string]$Path)
  $res = [ordered]@{ key=$Key; kind='file'; available=$false; path=$Path; text=''; source=''; error='' }
  $fx = Get-FixtureProp 'files' $Key
  if ($null -ne $fx) {
    $res.source = 'fixture'
    if (Test-FixtureUnavailable $fx) { $res.error = (Get-FixtureError $fx); return $res }
    $res.available = $true
    $res.text = [string]$fx
    return $res
  }
  if ($script:NoNative) { $res.source = 'fixture-missing'; $res.error = 'probe absent from fixture and native access disabled'; return $res }
  if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { $res.error = 'file not found'; return $res }
  try {
    $res.text = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    $res.available = $true
    $res.source = 'native'
  } catch { $res.error = $_.Exception.Message }
  if ($res.available) { Add-ProbeLog ('files.' + $Key) ($res.text) }
  else { Add-ProbeLog ('files.' + $Key) ([ordered]@{ _available=$false; _error=$res.error }) }
  return $res
}

function Get-FileListProbe {
  param([string]$Key,[string[]]$Paths)
  $res = [ordered]@{ key=$Key; kind='filelist'; available=$false; files=@(); source=''; error='' }
  $fx = Get-FixtureProp 'fileLists' $Key
  if ($null -ne $fx) {
    $res.source = 'fixture'
    if (Test-FixtureUnavailable $fx) { $res.error = (Get-FixtureError $fx); return $res }
    $acc = New-Object System.Collections.ArrayList
    foreach ($f in @($fx)) {
      $pth = ''; $txt = ''
      $pp = $f.PSObject.Properties['path']; if ($null -ne $pp) { $pth = [string]$pp.Value }
      $tp = $f.PSObject.Properties['text']; if ($null -ne $tp) { $txt = [string]$tp.Value }
      [void]$acc.Add([pscustomobject]@{ path=$pth; text=$txt })
    }
    $res.files = $acc.ToArray(); $res.available = $true
    return $res
  }
  if ($script:NoNative) { $res.source = 'fixture-missing'; $res.error = 'probe absent from fixture and native access disabled'; return $res }
  $acc = New-Object System.Collections.ArrayList
  foreach ($p in @($Paths)) {
    if ($p -and (Test-Path -LiteralPath $p)) {
      try {
        $t = [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8)
        [void]$acc.Add([pscustomobject]@{ path=$p; text=$t })
      } catch { }
    }
  }
  $res.files = $acc.ToArray(); $res.available = $true; $res.source = 'native'
  Add-ProbeLog ('fileLists.' + $Key) (@($acc.ToArray() | ForEach-Object { [ordered]@{ path=$_.path; text=$_.text } }))
  return $res
}

function Get-NetProfileProbe {
  # Get-NetConnectionProfile returns a locale-independent enum (Public/Private/
  # DomainAuthenticated) but is ADMIN-ONLY (measured: access denied when non-elevated).
  # It is used as one of several sources; never as the only one.
  $res = [ordered]@{ kind='netprofile'; available=$false; profiles=@(); source=''; error='' }
  $fx = Get-FixtureProp 'cmdlets' 'net_connection_profile'
  if ($null -ne $fx) {
    $res.source = 'fixture'
    if (Test-FixtureUnavailable $fx) { $res.error = (Get-FixtureError $fx); return $res }
    $acc = New-Object System.Collections.ArrayList
    foreach ($p in @($fx)) {
      $alias = ''; $cat = ''
      $ap = $p.PSObject.Properties['interfaceAlias']; if ($null -ne $ap) { $alias = [string]$ap.Value }
      $cp2 = $p.PSObject.Properties['networkCategory']; if ($null -ne $cp2) { $cat = [string]$cp2.Value }
      [void]$acc.Add([pscustomobject]@{ interfaceAlias=$alias; networkCategory=$cat })
    }
    $res.profiles = $acc.ToArray(); $res.available = $true
    return $res
  }
  if ($script:NoNative) { $res.source = 'fixture-missing'; $res.error = 'probe absent from fixture and native access disabled'; return $res }
  try {
    $acc = New-Object System.Collections.ArrayList
    foreach ($p in @(Get-NetConnectionProfile -ErrorAction Stop)) {
      $alias = ''
      try { $alias = [string]$p.InterfaceAlias } catch { $alias = '' }
      $cat = ''
      try { $cat = [string]$p.NetworkCategory } catch { $cat = '' }
      [void]$acc.Add([pscustomobject]@{ interfaceAlias=$alias; networkCategory=$cat })
    }
    $res.profiles = $acc.ToArray(); $res.available = $true; $res.source = 'native'
  } catch { $res.error = $_.Exception.Message }
  if ($res.available) { Add-ProbeLog 'cmdlets.net_connection_profile' (@($res.profiles | ForEach-Object { [ordered]@{ interfaceAlias=$_.interfaceAlias; networkCategory=$_.networkCategory } })) }
  else { Add-ProbeLog 'cmdlets.net_connection_profile' ([ordered]@{ _available=$false; _error=$res.error }) }
  return $res
}

function Get-ServiceProbe {  param([string]$Name)
  $res = [ordered]@{ name=$Name; kind='service'; available=$false; status=''; startType=''; source=''; error='' }
  $fx = Get-FixtureProp 'services' $Name
  if ($null -ne $fx) {
    $res.source = 'fixture'
    if (Test-FixtureUnavailable $fx) { $res.error = (Get-FixtureError $fx); return $res }
    $res.available = $true
    $sp = $fx.PSObject.Properties['status']; if ($null -ne $sp) { $res.status = [string]$sp.Value }
    $tp = $fx.PSObject.Properties['startType']; if ($null -ne $tp) { $res.startType = [string]$tp.Value }
    return $res
  }
  if ($script:NoNative) { $res.source = 'fixture-missing'; $res.error = 'probe absent from fixture and native access disabled'; return $res }
  try {
    $s = Get-Service -Name $Name -ErrorAction Stop
    $res.available = $true; $res.source = 'native'
    $res.status = [string]$s.Status; $res.startType = [string]$s.StartType
  } catch { $res.error = $_.Exception.Message }
  if ($res.available) { Add-ProbeLog ('services.' + $Name) ([ordered]@{ status=$res.status; startType=$res.startType }) }
  else { Add-ProbeLog ('services.' + $Name) ([ordered]@{ _available=$false; _error=$res.error }) }
  return $res
}

function Invoke-TcpProbe {
  param([string]$HostStr,[int]$PortNum,[int]$TimeoutMs)
  $res = [ordered]@{ kind='tcp'; target=($HostStr + ':' + $PortNum); result=''; ms=0; error=''; source='' }
  $key = 'tcp/' + $HostStr + '/' + $PortNum
  $fx = Get-FixtureProp 'network' $key
  if ($null -ne $fx) {
    $res.source = 'fixture'
    if (Test-FixtureUnavailable $fx) { $res.result = 'unavailable'; $res.error = (Get-FixtureError $fx); return $res }
    $rp = $fx.PSObject.Properties['result']; if ($null -ne $rp) { $res.result = [string]$rp.Value }
    $mp = $fx.PSObject.Properties['ms']; if ($null -ne $mp) { $res.ms = [int]$mp.Value }
    return $res
  }
  if ($script:NoNative) { $res.source = 'fixture-missing'; $res.result = 'unavailable'; $res.error = 'probe absent from fixture and native access disabled'; return $res }
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $c = New-Object System.Net.Sockets.TcpClient
  try {
    $iar = $c.BeginConnect($HostStr, $PortNum, $null, $null)
    if (-not $iar.AsyncWaitHandle.WaitOne($TimeoutMs)) { $sw.Stop(); $res.result = 'timeout'; $res.ms = $sw.ElapsedMilliseconds; $res.source = 'native'; return $res }
    $c.EndConnect($iar)
    $sw.Stop(); $res.result = 'connected'; $res.ms = $sw.ElapsedMilliseconds; $res.source = 'native'
  } catch {
    $sw.Stop(); $res.result = 'refused'; $res.ms = $sw.ElapsedMilliseconds; $res.source = 'native'
    $res.error = $_.Exception.Message
  } finally { $c.Close() }
  Add-ProbeLog ('network.' + $key) ([ordered]@{ result=$res.result; ms=$res.ms })
  return $res
}

function Invoke-DnsProbe {
  param([string]$Name,[int]$TimeoutMs)
  $res = [ordered]@{ kind='dns'; name=$Name; result=''; addresses=@(); error=''; socketError=''; source='' }
  $key = 'dns/' + $Name
  $fx = Get-FixtureProp 'network' $key
  if ($null -ne $fx) {
    $res.source = 'fixture'
    if (Test-FixtureUnavailable $fx) { $res.result = 'unavailable'; $res.error = (Get-FixtureError $fx); return $res }
    $rp = $fx.PSObject.Properties['result']; if ($null -ne $rp) { $res.result = [string]$rp.Value }
    $ap = $fx.PSObject.Properties['addresses']; if ($null -ne $ap) { $res.addresses = @($ap.Value) }
    $sp = $fx.PSObject.Properties['socketError']; if ($null -ne $sp) { $res.socketError = [string]$sp.Value }
    return $res
  }
  if ($script:NoNative) { $res.source = 'fixture-missing'; $res.result = 'unavailable'; $res.error = 'probe absent from fixture and native access disabled'; return $res }
  try {
    $iar = [System.Net.Dns]::BeginGetHostAddresses($Name, $null, $null)
    if (-not $iar.AsyncWaitHandle.WaitOne($TimeoutMs)) { $res.result = 'timeout'; $res.source = 'native'; return $res }
    $addrs = [System.Net.Dns]::EndGetHostAddresses($iar)
    $lst = New-Object System.Collections.ArrayList
    foreach ($a in $addrs) { [void]$lst.Add($a.IPAddressToString) }
    $res.addresses = $lst.ToArray(); $res.result = 'ok'; $res.source = 'native'
  } catch {
    $res.result = 'error'; $res.source = 'native'; $res.error = $_.Exception.Message
    # locale-independent: walk the inner-exception chain for the socket error code
    $ex = $_.Exception
    $depth = 0
    while ($null -ne $ex -and $depth -lt 6) {
      if ($ex -is [System.Net.Sockets.SocketException]) { $res.socketError = [string]$ex.SocketErrorCode; break }
      $ex = $ex.InnerException
      $depth++
    }
  }
  Add-ProbeLog ('network.' + $key) ([ordered]@{ result=$res.result; addresses=@($res.addresses); socketError=$res.socketError })
  return $res
}

# ---------------------------------------------------------------------------
# section 3: small helpers (addressing, processes, checks)
# ---------------------------------------------------------------------------
function Split-Addr {
  param([string]$A)
  $h = ''; $p = ''
  if ($null -eq $A) { return @{ host=''; port='' } }
  if ($A.StartsWith('[')) {
    $i = $A.IndexOf(']')
    if ($i -gt 0) {
      $h = $A.Substring(1, $i - 1)
      if ($A.Length -gt $i + 2) { $p = $A.Substring($i + 2) }
    }
  } else {
    $i = $A.LastIndexOf(':')
    if ($i -gt 0) { $h = $A.Substring(0, $i); $p = $A.Substring($i + 1) }
  }
  return @{ host=$h; port=$p }
}

function Test-LoopbackHost {
  param([string]$H)
  if ($H -eq '::1' -or $H -eq '[::1]' -or $H -eq '0:0:0:0:0:0:0:1') { return $true }
  if ($H -match '^127\.') { return $true }
  return $false
}

function Test-WildcardHost {
  param([string]$H)
  if ($H -eq '0.0.0.0' -or $H -eq '::' -or $H -eq '[::]') { return $true }
  return $false
}

function Test-CgnatV4 {
  param([string]$H)
  if ($H -match '^100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.\d{1,3}\.\d{1,3}$') { return $true }
  return $false
}

function Test-TailscaleV6 {
  param([string]$H)
  if ($H -match '^fd7a:115c:a1e0:') { return $true }
  return $false
}

$script:ProcNameCache = @{}
function Get-ProcName {
  param([int]$ProcId)
  if ($script:ProcNameCache.ContainsKey($ProcId)) { return $script:ProcNameCache[$ProcId] }
  $n = ''
  # fixture-injectable too: without this, a captured fixture could not prove the
  # listener-owner checks (served by tailscaled vs something else) offline.
  $fx = Get-FixtureProp 'processes' ([string]$ProcId)
  if ($null -ne $fx) {
    $n = [string]$fx
    $script:ProcNameCache[$ProcId] = $n
    return $n
  }
  if (-not $script:NoNative -and $ProcId -gt 0) {
    try { $n = (Get-Process -Id $ProcId -ErrorAction Stop).ProcessName } catch { $n = '' }
  }
  $script:ProcNameCache[$ProcId] = $n
  return $n
}

function Test-IsDshProcessName {
  param([string]$N)
  if (-not $N) { return $false }
  if ($N -match '^dsh') { return $true }
  return $false
}

function ConvertFrom-NetstatLines {
  # The row parser used to key on the literal state token 'LISTENING' (hard match). On a machine
  # whose netstat translates that token every row was silently dropped, and an empty row set then
  # read as "nothing to report" - a FALSE PASS on a security check (review finding F5). The token
  # is now a pattern (injectable through the label files, English default) and the parse reports
  # enough statistics for callers to fail closed instead of guessing.
  param([string[]]$Lines)
  $acc = New-Object System.Collections.ArrayList
  $tcpRows = 0
  $statePattern = Get-Pattern 'netstat_listening' '(?i)LISTENING'
  foreach ($ln in @($Lines)) {
    if ($null -eq $ln) { continue }
    $trimmed = $ln.Trim()
    if ($trimmed -eq '') { continue }
    $t = @(($trimmed -replace '\s+', ' ') -split ' ')
    if ($t.Count -lt 2) { continue }
    if ($t[0] -ne 'TCP') { continue }
    $tcpRows++
    if (-not ($trimmed -match $statePattern)) { continue }
    if ($t.Count -lt 4) { continue }
    $a = Split-Addr $t[1]
    $own = 0
    if ($t.Count -ge 5) { [void][int]::TryParse($t[4], [ref]$own) }
    $pn = ''
    if ($own -gt 0) { $pn = Get-ProcName $own }
    [void]$acc.Add([pscustomobject]@{ proto=$t[0]; local=$t[1]; host=$a.host; port=$a.port; pid=$own; process=$pn })
  }
  return [pscustomobject]@{
    rows = $acc.ToArray()
    statePattern = $statePattern
    tcpRowCount = $tcpRows
    parsedRowCount = $acc.Count
    stateWordUnrecognized = (($tcpRows -gt 0) -and ($acc.Count -eq 0))
  }
}

function New-Check {
  param([string]$Id,[string]$CheckRole,[string]$TitleKey)
  $t = LF 'title' $TitleKey @()
  if ($null -eq $t) { $t = $TitleKey }
  return [pscustomobject]@{
    id = $Id
    role = $CheckRole
    title = $t
    titleKey = $TitleKey
    verdict = 'unknown'
    reasonKey = ''
    reason = ''
    commands = (New-Object System.Collections.ArrayList)
    raw = [ordered]@{}
    remediation = $null
    manualReview = $false
    manualQuestion = ''
    informational = $false
    evidence = [ordered]@{ window='current-run'; source='local' }
  }
}

function Add-Check { param($C) [void]$script:Checks.Add($C) }

function Add-Cmd { param($C,[string]$Text) [void]$C.commands.Add($Text) }

function Set-Verdict {
  param($C,[string]$V,[string]$ReasonKey,[object[]]$FmtArgs)
  $C.verdict = $V
  $C.reasonKey = $ReasonKey
  $r = $null
  if ($null -ne $FmtArgs -and $FmtArgs.Count -gt 0) { $r = LF 'reason' $ReasonKey $FmtArgs } else { $r = LF 'reason' $ReasonKey @() }
  if ($null -eq $r) { $r = $ReasonKey }
  $C.reason = $r
}

function Set-Remediation {
  param($C,[string]$ActionKey,[string]$Command,[string]$Rollback,[bool]$NeedsElevation)
  $a = LF 'reason' $ActionKey @()
  if ($null -eq $a) { $a = $ActionKey }
  $C.remediation = [ordered]@{ action=$a; actionKey=$ActionKey; command=$Command; rollback=$Rollback; needsElevation=$NeedsElevation; applied=$false }
}

function Get-Severity { param([string]$V)
  if ($V -eq 'blocked') { return 3 }
  if ($V -eq 'unknown') { return 2 }
  if ($V -eq 'degraded') { return 1 }
  return 0
}

function Resolve-Tool {
  param([string]$Name,[object[]]$Candidates,[string]$Override)
  $cfg = [ordered]@{ name=$Name; path=''; source=''; tried=@() }
  if ($Override) {
    if (Test-Path -LiteralPath $Override) { $cfg.path = (Resolve-Path -LiteralPath $Override).Path; $cfg.source = 'param'; return $cfg }
    $cfg.tried += ('param:' + $Override)
  }
  foreach ($c in @($Candidates)) {
    if ($null -eq $c -or -not $c.P) { continue }
    if (Test-Path -LiteralPath $c.P) { $cfg.path = (Resolve-Path -LiteralPath $c.P).Path; $cfg.source = $c.S; return $cfg }
    $cfg.tried += ($c.S + ':' + $c.P)
  }
  $cfg.source = 'missing'
  return $cfg
}

# ---------------------------------------------------------------------------
# section 4: configuration resolution (every value carries its source)
# ---------------------------------------------------------------------------
$script:Config = New-Object System.Collections.ArrayList
function Add-Cfg { param([string]$Name,$Value,[string]$Source,[string]$Note)
  $v = ''
  if ($null -ne $Value) { $v = [string]$Value }
  [void]$script:Config.Add([pscustomobject][ordered]@{ name=$Name; value=$v; source=$Source; note=$Note })
}

# label language
$script:LangUsed = Resolve-Lang $Lang
if (-not $LabelsDir) {
  $LabelsDir = Join-Path $PSScriptRoot '..\i18n'
}
$labelsLoaded = Load-Labels $script:LangUsed $LabelsDir
if (-not $labelsLoaded -and $script:LangUsed -ne 'en') {
  $labelsLoaded = Load-Labels 'en' $LabelsDir
  if ($labelsLoaded) { Add-Cfg 'lang.fallback' 'en' 'builtin-default' 'requested labels file missing; fell back to en' }
}
Merge-Patterns $LabelsDir

# fixture
if ($FixturePath) {
  if (-not (Test-Path -LiteralPath $FixturePath)) {
    [void]$script:CollectorFaults.Add('fixture not found: ' + $FixturePath)
  } else {
    try {
      $script:Fixture = ([System.IO.File]::ReadAllText($FixturePath, [System.Text.Encoding]::UTF8)) | ConvertFrom-Json
      Add-Cfg 'fixture' $FixturePath 'param' 'all external inputs come from this file'
    } catch { [void]$script:CollectorFaults.Add('fixture parse error: ' + $_.Exception.Message) }
  }
}

# DSH home
$dshHomeVal = ''; $dshHomeSrc = ''
if ($DshHome) { $dshHomeVal = $DshHome; $dshHomeSrc = 'param' }
elseif ($env:DSH_HOME) { $dshHomeVal = $env:DSH_HOME; $dshHomeSrc = 'env:DSH_HOME' }
elseif ($env:USERPROFILE) { $dshHomeVal = Join-Path $env:USERPROFILE '.dsh'; $dshHomeSrc = 'auto(USERPROFILE/.dsh)' }
else { $dshHomeSrc = 'missing' }
Add-Cfg 'dshHome' $dshHomeVal $dshHomeSrc ''
$dshHomeExists = $false
if ($dshHomeVal) { $dshHomeExists = Test-Path -LiteralPath $dshHomeVal }
Add-Cfg 'dshHome.exists' ([string]$dshHomeExists) 'auto' 'false means no DSH profile is present on this machine'

# DSH port
$portVal = ''; $portSrc = ''
if ($Port) { $portVal = $Port; $portSrc = 'param' }
elseif ($env:DSH_WEB_URL -and ($env:DSH_WEB_URL -match ':(?<p>[0-9]{2,5})(/|$)')) { $portVal = $Matches['p']; $portSrc = 'env:DSH_WEB_URL' }
else { $portVal = '43120'; $portSrc = 'builtin-default' }
$portNum = 0
$portNumeric = [int]::TryParse($portVal, [ref]$portNum)
if (-not $portNumeric) {
  # A non-numeric -Port is rejected by construction: silently judging against port 0 would turn a
  # typo into a confusing "no listener" verdict. Fall back to the discovery chain and say so.
  Add-Cfg 'dshPort.invalidParam' $portVal 'param' 'ignored: not a number; fell back to the discovery chain'
  if ($env:DSH_WEB_URL -and ($env:DSH_WEB_URL -match ':(?<p2>[0-9]{2,5})(/|$)')) { $portVal = $Matches['p2']; $portSrc = 'env:DSH_WEB_URL(after invalid -Port)' }
  else { $portVal = '43120'; $portSrc = 'builtin-default(after invalid -Port)' }
  [void][int]::TryParse($portVal, [ref]$portNum)
}
Add-Cfg 'dshPort' $portVal $portSrc 'documented DSH schema default is 43120; the port is measured, never read back from config'

# peer
$peerSrc = 'missing'
if ($Peer) { $peerSrc = 'param' }
Add-Cfg 'peer' $Peer $peerSrc 'needed only for client-role link probes'
$peerNameVal = $PeerName
if (-not $peerNameVal -and $Peer) {
  $tmpIp = $null
  if (-not [System.Net.IPAddress]::TryParse($Peer, [ref]$tmpIp)) { $peerNameVal = $Peer }
}
Add-Cfg 'peerName' $peerNameVal $peerSrc 'DNS name used by the MagicDNS check'

Add-Cfg 'trustedHostPattern' $TrustedHostPattern 'param(default)' 'authority pattern that must appear in the loaded patch'
if ($TailnetDomain) {
  $TrustedHostPattern = ([regex]::Escape($TailnetDomain)).TrimEnd('\') + '$'
  Add-Cfg 'trustedHostPattern' $TrustedHostPattern 'param(-TailnetDomain)' 'derived from the supplied tailnet DNS suffix'
}
$tdSrc = 'missing'
if ($TailnetDomain) { $tdSrc = 'param' }
Add-Cfg 'tailnetDomain' $TailnetDomain $tdSrc 'never defaulted to a machine-specific name'
$profSrc = 'auto(all found)'
if ($Profile) { $profSrc = 'param' }
Add-Cfg 'profile' $Profile $profSrc ''
Add-Cfg 'tcpTimeoutMs' $TcpTimeoutMs 'param(default)' 'no network probe without an explicit timeout'
Add-Cfg 'dnsTimeoutMs' $DnsTimeoutMs 'param(default)' ''
Add-Cfg 'commandTimeoutMs' $CommandTimeoutMs 'param(default)' ''
Add-Cfg 'role' $Role 'param(default)' ''
Add-Cfg 'strictness' $Strictness 'param(default)' ''

# tool resolution
$toolCandidates = @{}
$toolCandidates['netstat'] = @(
  @{ P=(Join-Path $env:SystemRoot 'System32\netstat.exe'); S='auto(SystemRoot)' }
)
$toolCandidates['netsh'] = @(
  @{ P=(Join-Path $env:SystemRoot 'System32\netsh.exe'); S='auto(SystemRoot)' }
)
$toolCandidates['powercfg'] = @(
  @{ P=(Join-Path $env:SystemRoot 'System32\powercfg.exe'); S='auto(SystemRoot)' }
)
# tailscale: registry install location first, then conventional product folders, then PATH
$tsReg = Get-RegProbe 'tailscale_ipn' 'HKLM:\SOFTWARE\Tailscale IPN' @('InstallDir','UninstallString','DisplayIcon')
$tsCands = New-Object System.Collections.ArrayList
if ($tsReg.available) {
  foreach ($k in @('InstallDir','UninstallString','DisplayIcon')) {
    $v = $tsReg.values[$k]
    if ($v) {
      $d = [string]$v
      if ($d -match '^"([^"]+)"') { $d = $Matches[1] }
      $d = ($d -replace ',\d+$', '').Trim()
      if ($d -match '\.exe$') { $d = Split-Path -Parent $d }
      if ($d) { [void]$tsCands.Add(@{ P=(Join-Path $d 'tailscale.exe'); S=('auto(registry:' + $k + ')') }) }
    }
  }
}
if ($env:ProgramFiles) { [void]$tsCands.Add(@{ P=(Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'); S='auto(ProgramFiles)' }) }
$pf86 = ${env:ProgramFiles(x86)}
if ($pf86) { [void]$tsCands.Add(@{ P=(Join-Path $pf86 'Tailscale\tailscale.exe'); S='auto(ProgramFiles(x86))' }) }
if ($env:LOCALAPPDATA) { [void]$tsCands.Add(@{ P=(Join-Path $env:LOCALAPPDATA 'Tailscale\tailscale.exe'); S='auto(LOCALAPPDATA)' }) }
$tsOnPath = ''
try { $tsOnPath = (Get-Command tailscale.exe -ErrorAction Stop).Source } catch { }
if ($tsOnPath) { [void]$tsCands.Add(@{ P=$tsOnPath; S='auto(PATH)' }) }
$toolCandidates['tailscale'] = $tsCands.ToArray()

$script:Tools = @{}
foreach ($tn in @('netstat','netsh','powercfg','tailscale')) {
  # Fixture hook (t16): a fixture may declare `tools.<name>` so "the tool is not installed" is
  # testable offline. Environment redirection CANNOT express that on Windows PowerShell 5.1: the
  # child process re-creates %ProgramFiles% from the registry, so a redirected parent environment
  # is invisible to the collector (measured: with ProgramFiles/LOCALAPPDATA/PATH all pointed at
  # empty temp dirs, tool.tailscale still resolved to the real install path).
  if ($null -ne $script:Fixture) {
    $fxTool = Get-FixtureProp 'tools' $tn
    if ($null -ne $fxTool) {
      $fxPath = ''
      if (-not (Test-FixtureUnavailable $fxTool)) {
        if ($fxTool -is [string]) { $fxPath = [string]$fxTool }
        else {
          $fxPathProp = $fxTool.PSObject.Properties['path']
          if ($null -ne $fxPathProp) { $fxPath = [string]$fxPathProp.Value }
        }
      }
      $script:Tools[$tn] = $fxPath
      if ($fxPath) { Add-Cfg ('tool.' + $tn) $fxPath 'fixture' 'declared by the fixture' }
      else { Add-Cfg ('tool.' + $tn) '' 'missing' 'the fixture declares this tool absent' }
      continue
    }
  }
  $ovr = ''
  if ($ToolPath -and $ToolPath.ContainsKey($tn)) { $ovr = [string]$ToolPath[$tn] }
  $r = Resolve-Tool $tn $toolCandidates[$tn] $ovr
  $script:Tools[$tn] = $r.path
  Add-Cfg ('tool.' + $tn) $r.path $r.source 'empty = not resolvable'
}

# app directory (for the loaded cordis patch chain)
$appDirVal = ''; $appDirSrc = 'missing'
if ($AppDir) { $appDirVal = $AppDir; $appDirSrc = 'param' }
elseif ($env:DSH_APP_DIR) { $appDirVal = $env:DSH_APP_DIR; $appDirSrc = 'env:DSH_APP_DIR' }
else {
  foreach ($proc in @(Get-Process -ErrorAction SilentlyContinue)) {
    $pn = ''
    try { $pn = $proc.ProcessName } catch { $pn = '' }
    if (-not (Test-IsDshProcessName $pn)) { continue }
    $pp = ''
    try { $pp = $proc.Path } catch { $pp = '' }
    if (-not $pp) { continue }
    $cand = Join-Path (Split-Path -Parent $pp) 'resources\app'
    if (Test-Path -LiteralPath $cand) { $appDirVal = $cand; $appDirSrc = 'auto(process image path)'; break }
  }
}
Add-Cfg 'appDir' $appDirVal $appDirSrc 'root of the running DSH app, used to read the loaded patch chain'

# profile patch files
$patchPaths = New-Object System.Collections.ArrayList
if ($appDirVal) { [void]$patchPaths.Add((Join-Path $appDirVal 'cordis.patch.yml')) }
if ($dshHomeVal) {
  $profRoot = Join-Path $dshHomeVal 'profiles'
  if (Test-Path -LiteralPath $profRoot) {
    foreach ($pd in @(Get-ChildItem -LiteralPath $profRoot -Directory -ErrorAction SilentlyContinue)) {
      foreach ($fn in @('cordis.patch.yml','cordis.yml')) {
        $fp = Join-Path $pd.FullName $fn
        if (Test-Path -LiteralPath $fp) { [void]$patchPaths.Add($fp) }
      }
    }
  }
  foreach ($sub in @('@deepseek-ai','')) {
    $base = Join-Path $dshHomeVal ('profiles\node_modules\' + $sub)
    if (Test-Path -LiteralPath $base) {
      foreach ($d in @(Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue)) {
        $fp = Join-Path $d.FullName 'cordis.patch.yml'
        if (Test-Path -LiteralPath $fp) { [void]$patchPaths.Add($fp) }
      }
    }
  }
}
if ($appDirVal) {
  $nm = Join-Path $appDirVal 'node_modules'
  foreach ($sub in @('@deepseek-ai','dsh-plugin-desktop')) {
    $base = Join-Path $nm $sub
    if (Test-Path -LiteralPath $base) {
      foreach ($d in @(Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue)) {
        $fp = Join-Path $d.FullName 'cordis.patch.yml'
        if (Test-Path -LiteralPath $fp) { [void]$patchPaths.Add($fp) }
      }
      $fp2 = Join-Path $base 'cordis.patch.yml'
      if (Test-Path -LiteralPath $fp2) { [void]$patchPaths.Add($fp2) }
    }
  }
}
$patchPaths = @($patchPaths | Select-Object -Unique)
$profileDirs = New-Object System.Collections.ArrayList
if ($dshHomeVal) {
  $profRoot = Join-Path $dshHomeVal 'profiles'
  if (Test-Path -LiteralPath $profRoot) {
    foreach ($pd in @(Get-ChildItem -LiteralPath $profRoot -Directory -ErrorAction SilentlyContinue)) {
      foreach ($fn in @('cordis.patch.yml','cordis.yml')) {
        if (Test-Path -LiteralPath (Join-Path $pd.FullName $fn)) { [void]$profileDirs.Add($pd.Name); break }
      }
    }
  }
}
$profileList = @($profileDirs.ToArray() | Sort-Object -Unique)
# -Profile narrows only the PROFILE layer. The app-level and package-level patch layers are
# always loaded, so dropping them would change the answer (measured: without this guard a
# -Profile run lost the app patch that carries trustedHosts: [] and turned a real blocked
# finding into unknown).
if ($Profile -and $dshHomeVal) {
  $profRootN = Join-Path $dshHomeVal 'profiles'
  $patchPaths = @($patchPaths | Where-Object {
    if ($_ -notlike ($profRootN + '\*')) { return $true }
    return ($_ -like ('*\' + $Profile + '\*'))
  })
}
$multipleProfilesUnresolved = (($profileList.Count -gt 1) -and (-not $Profile))
Add-Cfg 'patchFiles' ([string]$patchPaths.Count) 'auto' 'number of cordis patch files considered as "actually loaded"'
Add-Cfg 'profilesFound' ($profileList -join ',') 'auto' 'more than one profile plus no -Profile means the trustedHosts check refuses to guess'
$encUsed = Get-SystemTextEncoding
$encName = ''
if ($null -ne $encUsed) { $encName = $encUsed.WebName }
Add-Cfg 'nativeOutputDecoding' $encName (('param' * [int]($OutputCodePage -gt 0)) + 'auto(registry NLS OEMCP)') 'native tools write in the OEM code page; the default .NET decoding corrupts non-ASCII output'

# -Describe: print the configuration surface and the explicit unsupported list, no probing.
if ($Describe) {
  Write-Output '== collect.ps1 -Describe (read-only) =='
  Write-Output 'readOnly            : true - writes happen only with -OutFile or -DumpFixture (explicit opt-in)'
  Write-Output 'exit code contract  : 0 = pass/safe; 1 = degraded and/or unknown; 2 = blocked or collector unusable'
  Write-Output '                      fail-closed: any unknown forbids exit 0; -Strictness strict raises unknown to 2'
  Write-Output 'roles               : server | client | both (default both; out-of-role checks are not emitted)'
  Write-Output 'checks              : 24 (both-role 9 / server-only 10 / client-only 5)'
  Write-Output 'language            : -Lang auto|zh|en (auto: CurrentUICulture -> InstalledUICulture -> registry LCID)'
  Write-Output 'localized patterns  : merged from every i18n/labels.*.json; a new locale needs only a new patterns block'
  Write-Output 'resolution order    : parameter > environment > auto-discovery > documented builtin default'
  Write-Output '  dshHome           : -DshHome > $env:DSH_HOME > $env:USERPROFILE\.dsh'
  Write-Output '  dshPort           : -Port > $env:DSH_WEB_URL > builtin 43120 (reported as a default, not as measured)'
  Write-Output '  appDir            : -AppDir > $env:DSH_APP_DIR > the running DSH process image path + \resources\app'
  Write-Output '  profile           : -Profile > all profiles found (more than one without -Profile => trustedHosts is unknown)'
  Write-Output '  tailscale.exe     : -ToolPath > registry install dir > ProgramFiles > ProgramFiles(x86) > LOCALAPPDATA > PATH'
  Write-Output '  peer              : -Peer / -PeerName (no discovery; without them the client checks stay unknown)'
  Write-Output '  trust pattern     : -TailnetDomain > builtin suffix pattern (labelled as a default)'
  Write-Output '  native decoding   : -OutputCodePage > registry NLS OEMCP (redirected netsh speaks the OEM code page)'
  Write-Output 'fixture injection   : -FixturePath <json> [-NoNative]  (every probe can be replaced; missing probes become unknown)'
  Write-Output 'capture a fixture   : -DumpFixture <path>  (records every probe result, including the PID -> image map)'
  Write-Output 'regression suite    : tests/run-fixtures.ps1 (7 cases, offline, asserts verdicts and exit codes)'
  Write-Output 'NOT supported       : HTTPS/certificate verdicts (client-side Node/OpenSSL only)'
  Write-Output '                    : powercfg /requests (admin only)'
  Write-Output '                    : Get-NetFirewallRule / Get-NetConnectionProfile when not elevated'
  Write-Output '                    : tailscale CLI while the named pipe is protected (reported as unknown, not as unconfigured)'
  Write-Output '                    : netsh text in a locale other than en/zh unless i18n/labels.<lang>.json is supplied'
  Write-Output '                    : any write action (-Apply is refused on purpose)'
  exit 0
}

# -Apply is refused on purpose (this revision has no write path)
if ($Apply) {
  Write-Output 'REFUSED: -Apply. This collector is read-only; no write path exists.'
  Write-Output 'Nothing was changed. Re-run without -Apply and execute the printed remediation commands yourself.'
  exit 2
}

# pre-run listener snapshot (read-only self-proof)
$netstatProbe = Invoke-External 'netstat' $script:Tools['netstat'] @('-ano') $CommandTimeoutMs
$preParse = ConvertFrom-NetstatLines @($netstatProbe.stdout -split "`r?`n")
$preRows = @($preParse.rows)

# ---------------------------------------------------------------------------
# section 5: checks
# ---------------------------------------------------------------------------
$wantServer = ($Role -eq 'server' -or $Role -eq 'both')
$wantClient = ($Role -eq 'client' -or $Role -eq 'both')

# --- both roles -------------------------------------------------------------
$c = New-Check 'OS_BUILD' 'both' 'os_build'
Add-Cmd $c 'registry HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion (ProductName, CurrentBuild, UBR, EditionID)'
$osReg = Get-RegProbe 'os_version' 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' @('ProductName','DisplayVersion','ReleaseId','CurrentBuild','UBR','EditionID','InstallationType','BuildLabEx')
if (-not $osReg.available) {
  $c.raw.error = $osReg.error
  Set-Verdict $c 'unknown' 'reg_unavailable' @('os_version', $osReg.error)
} else {
  $buildStr = [string]$osReg.values['CurrentBuild']
  $ubr = $osReg.values['UBR']
  $branch = 'unknown'
  $bnum = 0
  if ([int]::TryParse($buildStr, [ref]$bnum)) {
    if ($bnum -ge 22000) { $branch = 'win11' } else { $branch = 'win10' }
  }
  $c.raw.productName = [string]$osReg.values['ProductName']
  $c.raw.displayVersion = [string]$osReg.values['DisplayVersion']
  $c.raw.currentBuild = $buildStr
  $c.raw.ubr = $ubr
  $c.raw.editionId = [string]$osReg.values['EditionID']
  $c.raw.installationType = [string]$osReg.values['InstallationType']
  $c.raw.branch = $branch
  $c.raw.branchRule = 'CurrentBuild >= 22000 => win11 (ProductName is unreliable on Win11)'
  Set-Verdict $c 'pass' 'os_ok' @($branch, $buildStr, $ubr)
}
Add-Check $c

$c = New-Check 'HOST_PS_ENV' 'both' 'host_ps_env'
Add-Cmd $c '$PSVersionTable; Get-ExecutionPolicy; Get-Command pwsh.exe, node'
$psv = ''
try { $psv = [string]$PSVersionTable.PSVersion } catch { $psv = '' }
$edition = ''
try { $edition = [string]$PSVersionTable.PSEdition } catch { $edition = '' }
$execPol = ''
try { $execPol = [string](Get-ExecutionPolicy) } catch { $execPol = '' }
$pwshPath = ''
try { $pwshPath = (Get-Command pwsh.exe -ErrorAction Stop).Source } catch { }
$nodePath = ''
try { $nodePath = (Get-Command node -ErrorAction Stop).Source } catch { }
$c.raw.psVersion = $psv
$c.raw.psEdition = $edition
$c.raw.executionPolicy = $execPol
$c.raw.executionPolicyScope = 'process: this value belongs to THIS child process (the collector is launched with -ExecutionPolicy Bypass). It is NOT the machine or user default - compare executionPolicyScopes.'
$c.raw.executionPolicyScopes = @(Get-ExecutionPolicy -List | ForEach-Object { ([string]$_.Scope + '=' + [string]$_.ExecutionPolicy) })
$c.raw.pwsh = $pwshPath
$c.raw.node = $nodePath
$c.raw.note = 'pwsh/node empty => PS7-only syntax and node-based HTTPS checks are unavailable on this host'
$psMajorOk = $true
if ($psv -match '^(\d+)\.') { if ([int]$Matches[1] -lt 5) { $psMajorOk = $false } }
if ($psMajorOk) { Set-Verdict $c 'pass' 'ps_ok' @($psv, $execPol) } else { Set-Verdict $c 'degraded' 'ps_old' @($psv) }
Add-Check $c

$c = New-Check 'PRIVILEGE_LEVEL' 'both' 'privilege_level'
Add-Cmd $c 'WindowsIdentity/WindowsPrincipal IsInRole(Administrator)'
$elevated = $false
try {
  $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
  $pr = New-Object System.Security.Principal.WindowsPrincipal($id)
  $elevated = $pr.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
} catch { }
$c.raw.elevated = $elevated
$c.raw.note = 'non-elevated runs cannot use Get-NetFirewallRule/Get-NetConnectionProfile/powercfg /requests; this collector never needs them'
$c.informational = $true
Set-Verdict $c 'pass' 'priv_ok' @($elevated)
Add-Check $c

# tailnet address discovery (used by several checks below)
$ipAddrProbe = Invoke-External 'ip_addresses' $script:Tools['netsh'] @('interface','ip','show','addresses') $CommandTimeoutMs
$c = New-Check 'TAILNET_ADDRESS' 'both' 'tailnet_address'
Add-Cmd $c 'netsh interface ip show addresses  (IPv4 addresses in 100.64.0.0/10 are extracted by regex only)'
Add-Cmd $c 'netstat -ano  (LISTENING rows whose local address is in 100.64.0.0/10 or fd7a:115c:a1e0::/48)'
$tailnetIps = New-Object System.Collections.ArrayList
$adapterName = ''
if ($ipAddrProbe.available) {
  $blocks = @($ipAddrProbe.stdout -split "`r?`n")
  $curName = ''
  foreach ($ln in $blocks) {
    $qm = [regex]::Match($ln, '"([^"]+)"')
    if ($qm.Success) { $curName = $qm.Groups[1].Value }
    foreach ($m in [regex]::Matches($ln, '\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b')) {
      if (Test-CgnatV4 $m.Value) {
        if (-not $tailnetIps.Contains($m.Value)) { [void]$tailnetIps.Add($m.Value) }
        if (-not $adapterName -and $curName) { $adapterName = $curName }
      }
    }
  }
}
foreach ($r in $preRows) {
  if (Test-CgnatV4 $r.host) { if (-not $tailnetIps.Contains($r.host)) { [void]$tailnetIps.Add($r.host) } }
  if (Test-TailscaleV6 $r.host) { if (-not $tailnetIps.Contains($r.host)) { [void]$tailnetIps.Add($r.host) } }
}
$tailnetIpList = $tailnetIps.ToArray()
$c.raw.ipAddressesProbe = [ordered]@{ available=$ipAddrProbe.available; source=$ipAddrProbe.source; error=$ipAddrProbe.error }
$c.raw.tailnetAddresses = $tailnetIpList
$c.raw.tailnetAdapterName = $adapterName
$c.raw.addressRanges = '100.64.0.0/10 (CGNAT, used by Tailscale) and fd7a:115c:a1e0::/48 (Tailscale IPv6)'
if ($tailnetIpList.Count -gt 0) { Set-Verdict $c 'pass' 'tailnet_ok' @(($tailnetIpList -join ', ')) }
else { Set-Verdict $c 'unknown' 'tailnet_unknown' @() }
Add-Check $c

# DSH loopback exclusivity
$c = New-Check 'DSH_LOOPBACK_ONLY' 'server' 'dsh_loopback_only'
Add-Cmd $c ('netstat.exe -ano  (TCP LISTENING rows, parsed by column; port ' + $portVal + ')')
$dshRows = @($preRows | Where-Object { $_.port -eq $portVal })
$dshListen = @($dshRows | Where-Object { $true })
$ownerPid = 0
$ownerName = ''
if ($dshListen.Count -gt 0) { $ownerPid = $dshListen[0].pid; $ownerName = $dshListen[0].process }
$discoveredPort = ''
if ($dshListen.Count -eq 0) {
  # auto-discovery: a loopback listener owned by a DSH process
  foreach ($r in $preRows) {
    if ((Test-LoopbackHost $r.host) -and (Test-IsDshProcessName $r.process)) { $discoveredPort = $r.port; $ownerPid = $r.pid; $ownerName = $r.process; break }
  }
}
$c.raw.port = $portVal
$c.raw.portSource = $portSrc
$c.raw.discoveredPort = $discoveredPort
$c.raw.listeningRows = @($dshListen | ForEach-Object { [ordered]@{ local=$_.local; host=$_.host; pid=$_.pid; process=$_.process } })
$c.raw.rowCountNote = 'row counts fluctuate with TIME_WAIT and are never used as a criterion'
$c.raw.ownerPid = $ownerPid
$c.raw.ownerProcess = $ownerName
$c.raw.netstatProbe = [ordered]@{ available=$netstatProbe.available; source=$netstatProbe.source; error=$netstatProbe.error }
if (-not $netstatProbe.available) {
  Set-Verdict $c 'unknown' 'netstat_unavailable' @($netstatProbe.error)
} elseif ($dshListen.Count -eq 0 -and -not $discoveredPort) {
  Set-Verdict $c 'unknown' 'dsh_no_listener' @($portVal)
} else {
  $judged = $dshListen
  if ($dshListen.Count -eq 0 -and $discoveredPort) {
    $judged = @($preRows | Where-Object { $_.port -eq $discoveredPort })
  }
  $bad = @($judged | Where-Object { -not (Test-LoopbackHost $_.host) })
  $c.raw.judgedPort = $(if ($discoveredPort) { $discoveredPort } else { $portVal })
  $c.raw.nonLoopbackHits = @($bad | ForEach-Object { $_.local })
  $c.raw.wildcardHits = @($judged | Where-Object { Test-WildcardHost $_.host } | ForEach-Object { $_.local })
  if ($bad.Count -gt 0) {
    Set-Verdict $c 'blocked' 'dsh_exposed' @((($bad | ForEach-Object { $_.local }) -join ', '))
    Set-Remediation $c 'rem_dsh_exposed' 'netstat.exe -ano | findstr <port>   # find the process that widened the bind, then reconfigure that process itself' 'n/a - this collector changes nothing' $false
  } else {
    Set-Verdict $c 'pass' 'dsh_loopback_ok' @($c.raw.judgedPort, $judged.Count)
  }
}
Add-Check $c

# non-loopback listener inventory (kept separate from the DSH port statement)
$c = New-Check 'WILDCARD_LISTENER_INVENTORY' 'both' 'wildcard_listener_inventory'
Add-Cmd $c 'netstat.exe -ano  (TCP LISTENING rows whose local address is not loopback; classified, not string-matched)'
$inventory = New-Object System.Collections.ArrayList
$dshOwnedExternal = New-Object System.Collections.ArrayList
foreach ($r in $preRows) {
  if (Test-LoopbackHost $r.host) { continue }
  $cls = 'interface-specific'
  if (Test-WildcardHost $r.host) { $cls = 'wildcard' }
  elseif (Test-CgnatV4 $r.host) { $cls = 'tailnet' }
  elseif (Test-TailscaleV6 $r.host) { $cls = 'tailnet-v6' }
  [void]$inventory.Add([ordered]@{ local=$r.local; host=$r.host; port=$r.port; pid=$r.pid; process=$r.process; class=$cls })
  if (Test-IsDshProcessName $r.process) { [void]$dshOwnedExternal.Add($r.local) }
}
$c.raw.inventory = $inventory.ToArray()
$c.raw.inventoryCount = $inventory.Count
$c.raw.wildcardCount = @($inventory | Where-Object { $_.class -eq 'wildcard' }).Count
$c.raw.tailnetCount = @($inventory | Where-Object { $_.class -eq 'tailnet' -or $_.class -eq 'tailnet-v6' }).Count
$c.raw.statement = 'this list is about OTHER services on this machine; it does not change the DSH-port judgement above'
$c.raw.note = 'BUG AVOIDANCE: parsing is per column, never per line - the remote-address column of a valid row is literally 0.0.0.0:0'
$c.raw.statePattern = $preParse.statePattern
$c.raw.tcpRowCount = $preParse.tcpRowCount
$c.raw.parsedRowCount = $preParse.parsedRowCount
$c.raw.stateWordUnrecognized = $preParse.stateWordUnrecognized
# FAIL-CLOSED GUARD (t16 F5, review findings F5 + cases xfail-netstat-dead-probe-wildcard-inventory
# and xfail-netstat-unreadable-wildcard-inventory): an inventory that parsed nothing must never
# report "no wildcard listener". Silence is not a pass.
if (-not $netstatProbe.available) {
  Set-Verdict $c 'unknown' 'netstat_unavailable' @($netstatProbe.error)
} elseif ($preParse.stateWordUnrecognized) {
  Set-Verdict $c 'unknown' 'netstat_unavailable' @('state token not recognized: raw TCP rows exist but none matched ' + $preParse.statePattern)
} elseif ($preRows.Count -eq 0) {
  Set-Verdict $c 'unknown' 'netstat_unavailable' @('the netstat snapshot parsed zero rows')
} elseif ($dshOwnedExternal.Count -gt 0) {
  Set-Verdict $c 'blocked' 'inv_dsh_exposed' @(($dshOwnedExternal -join ', '))
} else {
  Set-Verdict $c 'pass' 'inv_ok' @($inventory.Count, (@($inventory | Where-Object { $_.class -eq 'wildcard' }).Count))
}
Add-Check $c

# tailscale CLI layering
$c = New-Check 'TAILSCALE_CLI_LAYER' 'both' 'tailscale_cli_layer'
Add-Cmd $c 'tailscale.exe version / ip -4 / serve status   (each exit code captured from the process, never from cmd %errorlevel%)'
$tsExe = $script:Tools['tailscale']
$tsVersion = Invoke-External 'tailscale_version' $tsExe @('version') $CommandTimeoutMs
$tsIp = Invoke-External 'tailscale_ip4' $tsExe @('ip','-4') $CommandTimeoutMs
$tsServe = Invoke-External 'tailscale_servestatus' $tsExe @('serve','status') $CommandTimeoutMs
$c.raw.executable = $tsExe
$c.raw.version = [ordered]@{ exitCode=$tsVersion.exitCode; available=$tsVersion.available; firstLine=(@(($tsVersion.stdout -split "`r?`n") | Where-Object { $_.Trim() -ne '' })[0]) }
$c.raw.ip4 = [ordered]@{ exitCode=$tsIp.exitCode; available=$tsIp.available; stderr=(@(($tsIp.stderr -split "`r?`n") | Where-Object { $_.Trim() -ne '' }) -join ' | ') }
$c.raw.serveStatus = [ordered]@{ exitCode=$tsServe.exitCode; available=$tsServe.available; stderr=(@(($tsServe.stderr -split "`r?`n") | Where-Object { $_.Trim() -ne '' }) -join ' | ') }
$c.raw.rule = 'CLI availability = exit code of ip/serve status. version exit 0 proves only that the binary self-reports.'
if (-not $tsExe) {
  Set-Verdict $c 'blocked' 'ts_not_installed' @()
  Set-Remediation $c 'rem_ts_install' 'Install Tailscale yourself (interactive MSI + browser sign-in); do not automate account sign-in' 'Uninstall via Settings > Apps' $true
} elseif (-not $tsIp.available) {
  Set-Verdict $c 'unknown' 'ts_probe_failed' @($tsIp.error)
} elseif ($tsIp.exitCode -eq 0) {
  Set-Verdict $c 'pass' 'ts_cli_ok' @($tsVersion.exitCode, $tsServe.exitCode)
} else {
  $errText = $tsIp.stderr
  if ($errText -match 'ProtectedPrefix' -or $errText -match 'Access is denied') {
    Set-Verdict $c 'unknown' 'ts_pipe_denied' @($tsIp.exitCode)
  } elseif ($errText -match '(?i)not logged in|Logged out|not running') {
    Set-Verdict $c 'unknown' 'ts_not_logged_in' @($errText)
  } else {
    Set-Verdict $c 'unknown' 'ts_probe_failed' @($tsIp.exitCode)
  }
}
Add-Check $c

# tailscale service
$c = New-Check 'TAILSCALE_SERVICE' 'both' 'tailscale_service'
Add-Cmd $c 'Get-Service Tailscale  (product service name)'
$svc = Get-ServiceProbe 'Tailscale'
$c.raw.status = $svc.status
$c.raw.startType = $svc.startType
$c.raw.probe = [ordered]@{ available=$svc.available; source=$svc.source; error=$svc.error }
if (-not $svc.available) {
  Set-Verdict $c 'blocked' 'ts_service_missing' @()
} elseif ($svc.status -eq 'Running') {
  Set-Verdict $c 'pass' 'ts_service_running' @($svc.startType)
} else {
  Set-Verdict $c 'blocked' 'ts_service_stopped' @($svc.status)
}
Add-Check $c

# firewall rules from the registry (locale-proof source of truth for Edge)
$fwRulesPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\FirewallRules'
$fwRulesProbe = Get-RegProbe 'firewall_rules' $fwRulesPath @()
$fwRules = New-Object System.Collections.ArrayList
if ($fwRulesProbe.available) {
  foreach ($pr in $fwRulesProbe.values.GetEnumerator()) {
    $raw = [string]$pr.Value
    if (-not $raw) { continue }
    $obj = [ordered]@{ id=$pr.Name; raw=$raw; name=''; edge=''; dir=''; action=''; active=''; protocol=''; app=''; profiles=@(); la4=''; la6='' }
    foreach ($part in @($raw -split '\|')) {
      if ($part -match '^([A-Za-z0-9]+)=(.*)$') {
        $k = $Matches[1]; $v = $Matches[2]
        switch ($k) {
          'Name'    { $obj.name = $v }
          'Edge'    { $obj.edge = $v }
          'Dir'     { $obj.dir = $v }
          'Action'  { $obj.action = $v }
          'Active'  { $obj.active = $v }
          'Protocol'{ $obj.protocol = $v }
          'App'     { $obj.app = $v }
          'Profile' { $obj.profiles = @($obj.profiles) + @($v) }
          'LA4'     { $obj.la4 = $v }
          'LA6'     { $obj.la6 = $v }
        }
      }
    }
    [void]$fwRules.Add([pscustomobject]$obj)
  }
}
$rulesByName = @{}
foreach ($r in $fwRules) {
  if (-not $r.name) { continue }
  if (-not $rulesByName.ContainsKey($r.name)) { $rulesByName[$r.name] = New-Object System.Collections.ArrayList }
  [void]$rulesByName[$r.name].Add($r)
}

# Edge traversal: must be read from the PROCESS rule, and from the stored value
$c = New-Check 'TAILSCALE_PROCESS_EDGE_DB' 'server' 'tailscale_process_edge_db'
Add-Cmd $c ('registry ' + $fwRulesPath + '  (stored value is authoritative: Name=Tailscale-Process ... Edge=TRUE/FALSE)')
Add-Cmd $c 'netsh advfirewall firewall show rule name=Tailscale-Process verbose   (secondary, echoed value)'
$netshEdge = Invoke-External 'netsh_rule_process_verbose' $script:Tools['netsh'] @('advfirewall','firewall','show','rule','name=Tailscale-Process','verbose') $CommandTimeoutMs
$edgeRules = @()
if ($rulesByName.ContainsKey('Tailscale-Process')) { $edgeRules = @($rulesByName['Tailscale-Process']) }
$edgeStored = ''
if ($edgeRules.Count -gt 0) { $edgeStored = [string]$edgeRules[0].edge }
$edgeEcho = ''
$edgePat = Get-Pattern 'netsh_edge_traversal' '(?im)^\s*Edge\s+traversal\s*:\s*(.+?)\s*$'
if ($netshEdge.available) {
  $m = [regex]::Match($netshEdge.stdout, $edgePat)
  if ($m.Success) { $edgeEcho = ConvertTo-YesNo $m.Groups[1].Value }
}
$c.raw.registryAvailable = $fwRulesProbe.available
$c.raw.rulesSeen = @($rulesByName.Keys | Sort-Object)
$c.raw.tailscaleNamedRules = @($fwRules | Where-Object { $_.name -match 'Tailscale' } | ForEach-Object { [ordered]@{ name=$_.name; edge=$_.edge; dir=$_.dir; profiles=@($_.profiles); la4=$_.la4; la6=$_.la6; app=$_.app } })
$c.raw.storedEdge = $edgeStored
$c.raw.echoedEdge = $edgeEcho
$c.raw.ruleToInspect = 'Tailscale-Process (process rule). Tailscale-In is a different pair of rules and is EXPECTED to be Edge=No - reading those would wrongly conclude "no drift".'
if (-not $fwRulesProbe.available) {
  Set-Verdict $c 'unknown' 'edge_registry_unavailable' @($fwRulesProbe.error)
} elseif ($edgeRules.Count -eq 0) {
  Set-Verdict $c 'blocked' 'edge_rule_missing' @()
} elseif ($edgeStored -eq 'TRUE') {
  Set-Verdict $c 'pass' 'edge_ok' @($edgeEcho)
} elseif ($edgeStored -eq 'FALSE') {
  Set-Verdict $c 'blocked' 'edge_false' @()
  Set-Remediation $c 'rem_edge_restore' 'Restore the Tailscale-Process rule (reinstall/repair Tailscale, or re-apply the vendor rule) - then re-run this check' 'record the previous rule value before changing anything' $true
} else {
  Set-Verdict $c 'unknown' 'edge_value_unrecognized' @($edgeStored)
}
Add-Check $c

# Tailscale-In rules (built-in inbound allows; coverage depends on the adapter profile)
$c = New-Check 'TAILSCALE_IN_RULES' 'server' 'tailscale_in_rules'
Add-Cmd $c ('registry ' + $fwRulesPath + '  (rules named Tailscale-In)')
$tsIn = @()
if ($rulesByName.ContainsKey('Tailscale-In')) { $tsIn = @($rulesByName['Tailscale-In']) }
$c.raw.count = $tsIn.Count
$c.raw.rules = @($tsIn | ForEach-Object { [ordered]@{ edge=$_.edge; profiles=@($_.profiles); la4=$_.la4; la6=$_.la6; protocol=$_.protocol; action=$_.action; active=$_.active } })
$hasV4 = $false; $hasV6 = $false; $hasPrivateOrDomain = $false
foreach ($r in $tsIn) {
  if ($r.la4) { $hasV4 = $true }
  if ($r.la6) { $hasV6 = $true }
  foreach ($p in @($r.profiles)) { if ($p -eq 'Domain' -or $p -eq 'Private') { $hasPrivateOrDomain = $true } }
}
$c.raw.hasV4 = $hasV4
$c.raw.hasV6 = $hasV6
$c.raw.coversDomainOrPrivate = $hasPrivateOrDomain
$c.raw.note = 'these rules only cover the Domain and Private profiles; a Public-classified Tailscale adapter silently makes them ineffective'
if (-not $fwRulesProbe.available) {
  Set-Verdict $c 'unknown' 'fw_registry_unavailable' @($fwRulesProbe.error)
} elseif ($tsIn.Count -eq 0) {
  Set-Verdict $c 'degraded' 'ts_in_missing' @()
} elseif (-not ($hasV4 -and $hasV6)) {
  Set-Verdict $c 'degraded' 'ts_in_partial' @($hasV4, $hasV6)
} elseif (-not $hasPrivateOrDomain) {
  Set-Verdict $c 'degraded' 'ts_in_profile_narrow' @((@($tsIn[0].profiles) -join ','))
} else {
  Set-Verdict $c 'pass' 'ts_in_ok' @($tsIn.Count)
}
Add-Check $c

# adapter to firewall profile attribution (three sources, first usable one wins)
$c = New-Check 'NIC_PROFILE_ATTRIBUTION' 'server' 'nic_profile_attribution'
Add-Cmd $c 'netsh advfirewall monitor show currentprofile   (localized header patterns come from the label file; no match => unknown + raw output, never a guess)'
Add-Cmd $c 'netsh interface ip show addresses   (the adapter name that carries the tailnet address)'
Add-Cmd $c 'Get-NetConnectionProfile   (locale-independent enum, admin-only; used when it is available)'
$nicProbe = Invoke-External 'netsh_currentprofile' $script:Tools['netsh'] @('advfirewall','monitor','show','currentprofile') $CommandTimeoutMs
$parsed = New-Object System.Collections.ArrayList
$parseOk = $false
if ($nicProbe.available) {
  $cur = ''
  $curLines = New-Object System.Collections.ArrayList
  foreach ($ln in @($nicProbe.stdout -split "`r?`n")) {
    $pf = Get-ProfileFromHeaderLine $ln
    if ($pf) {
      if ($cur) { [void]$parsed.Add([pscustomobject]@{ profile=$cur; adapters=@($curLines.ToArray()) }) }
      $cur = $pf
      $curLines = New-Object System.Collections.ArrayList
      $parseOk = $true
      continue
    }
    if ($cur) {
      $t = $ln.Trim()
      if ($t -ne '' -and $t -notmatch (Get-Pattern 'netsh_ok_line' '(?i)^\s*Ok\.?\s*$') -and $t -notmatch '^-{5,}$') { [void]$curLines.Add($t) }
    }
  }
  if ($cur) { [void]$parsed.Add([pscustomobject]@{ profile=$cur; adapters=@($curLines.ToArray()) }) }
}
$np = Get-NetProfileProbe
$foundProfile = ''
$matchMethod = ''
if ($np.available) {
  foreach ($p in @($np.profiles)) {
    $alias = $p.interfaceAlias
    if (-not $alias) { continue }
    $hit = $false
    if ($adapterName -and $alias -eq $adapterName) { $hit = $true }
    elseif ($alias -match 'tailscale') { $hit = $true }
    if ($hit) {
      $npv = Normalize-ProfileName $p.networkCategory
      if ($npv) { $foundProfile = $npv; $matchMethod = 'Get-NetConnectionProfile' }
      break
    }
  }
}
if (-not $foundProfile -and $parseOk) {
  if ($adapterName) {
    foreach ($sec in $parsed) { foreach ($a in $sec.adapters) { if ($a -eq $adapterName) { $foundProfile = $sec.profile; $matchMethod = 'netsh-adapter-name' } } }
  }
  if (-not $foundProfile) {
    foreach ($sec in $parsed) { foreach ($a in $sec.adapters) { if ($a -match 'tailscale') { $foundProfile = $sec.profile; $matchMethod = 'netsh-adapter-name-contains-tailscale' } } }
  }
}
$c.raw.netshProbe = [ordered]@{ available=$nicProbe.available; source=$nicProbe.source; error=$nicProbe.error }
$c.raw.netConnectionProfileProbe = [ordered]@{ available=$np.available; source=$np.source; error=$np.error; profiles=@($np.profiles) }
$c.raw.structureParsed = $parseOk
$c.raw.sections = @($parsed | ForEach-Object { [ordered]@{ profile=$_.profile; adapters=@($_.adapters) } })
$c.raw.netshRawOutput = @(($nicProbe.stdout -split "`r?`n") | Where-Object { $_.Trim() -ne '' })
$c.raw.matchedAdapter = $adapterName
$c.raw.matchMethod = $matchMethod
$c.raw.tailscaleProfile = $foundProfile
$c.raw.whyItMatters = 'the built-in Tailscale-In rules cover only Domain and Private; if the Tailscale adapter lands in Public those allows do not apply and the failure is completely silent'
$c.raw.manualFallback = 'if no pattern matched, read netshRawOutput by hand: the adapter list under each profile heading shows where the Tailscale adapter sits'
if (-not $nicProbe.available -and -not $np.available) {
  Set-Verdict $c 'unknown' 'nic_probe_failed' @($nicProbe.error)
} elseif (-not $foundProfile) {
  Set-Verdict $c 'unknown' 'nic_unparsed' @($parseOk, $np.available)
} elseif ($foundProfile -eq 'Public') {
  Set-Verdict $c 'blocked' 'nic_public' @($matchMethod)
  Set-Remediation $c 'rem_nic_private' 'Set the Tailscale network category to Private, or add a narrow inbound allow for the tailnet' 'revert the category change, or remove the rule you added' $true
} else {
  Set-Verdict $c 'pass' 'nic_ok' @($foundProfile, $matchMethod)
}
Add-Check $c

# whole-machine firewall profile state (registry primary, netsh secondary)
$c = New-Check 'FIREWALL_PROFILES' 'server' 'firewall_profiles'
Add-Cmd $c 'registry FirewallPolicy\{DomainProfile,StandardProfile,PublicProfile}\EnableFirewall   (locale-proof)'
Add-Cmd $c 'netsh advfirewall show allprofiles   (secondary, ASCII header parse)'
$fwDom = Get-RegProbe 'fw_domain' 'HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\DomainProfile' @('EnableFirewall')
$fwStd = Get-RegProbe 'fw_standard' 'HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\StandardProfile' @('EnableFirewall')
$fwPub = Get-RegProbe 'fw_public' 'HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\PublicProfile' @('EnableFirewall')
$fwAllProf = Invoke-External 'netsh_show_allprofiles' $script:Tools['netsh'] @('advfirewall','show','allprofiles') $CommandTimeoutMs
$netshStates = [ordered]@{}
if ($fwAllProf.available) {
  $profPats = @(
    @{ name='Domain';  pat=(Get-Pattern 'netsh_allprofiles_domain'  '(?i)^\s*Domain\s+Profile\s+Settings\s*:?\s*$') },
    @{ name='Private'; pat=(Get-Pattern 'netsh_allprofiles_private' '(?i)^\s*Private\s+Profile\s+Settings\s*:?\s*$') },
    @{ name='Public';  pat=(Get-Pattern 'netsh_allprofiles_public'  '(?i)^\s*Public\s+Profile\s+Settings\s*:?\s*$') }
  )
  $statePat = Get-Pattern 'netsh_state_line' '(?i)^\s*State\s+(\S+)\s*$'
  $sec = ''
  foreach ($ln in @($fwAllProf.stdout -split "`r?`n")) {
    $hit = ''
    foreach ($e in $profPats) { if ($ln -match $e.pat) { $hit = $e.name } }
    if ($hit) { $sec = $hit; continue }
    if ($sec) {
      $ms = [regex]::Match($ln, $statePat)
      if ($ms.Success) { $netshStates[$sec] = ConvertTo-YesNo $ms.Groups[1].Value }
    }
  }
}
$c.raw.registry = [ordered]@{
  domain = [ordered]@{ available=$fwDom.available; enableFirewall=$fwDom.values['EnableFirewall']; error=$fwDom.error }
  standard = [ordered]@{ available=$fwStd.available; enableFirewall=$fwStd.values['EnableFirewall']; error=$fwStd.error }
  public = [ordered]@{ available=$fwPub.available; enableFirewall=$fwPub.values['EnableFirewall']; error=$fwPub.error }
}
$c.raw.netshStates = $netshStates
$c.raw.note = 'State ON in all profiles is the expected baseline; EnableFirewall=1 is the same fact from the registry'
$regOk = ($fwDom.available -and $fwStd.available -and $fwPub.available)
if ($regOk) {
  $off = New-Object System.Collections.ArrayList
  if ([int]$fwDom.values['EnableFirewall'] -eq 0) { [void]$off.Add('Domain') }
  if ([int]$fwStd.values['EnableFirewall'] -eq 0) { [void]$off.Add('Private') }
  if ([int]$fwPub.values['EnableFirewall'] -eq 0) { [void]$off.Add('Public') }
  $c.raw.profilesOff = $off.ToArray()
  if ($off.Count -gt 0) {
    Set-Verdict $c 'degraded' 'fw_partial_off' @(($off.ToArray() -join ', '))
    Set-Remediation $c 'rem_fw_on' 'Turn the Windows Firewall back on for every profile (netsh advfirewall set allprofiles state on)' 'netsh advfirewall set allprofiles state off  # only if it was off before' $true
  } else {
    Set-Verdict $c 'pass' 'fw_ok' @($netshStates.Count)
  }
} elseif ($netshStates.Count -gt 0) {
  $c.raw.fallback = 'registry unreadable; netsh parse used as primary'
  $offN = @()
  foreach ($k in @('Domain','Private','Public')) { if ($netshStates.Contains($k) -and $netshStates[$k] -ne 'ON') { $offN += $k } }
  if ($offN.Count -gt 0) { Set-Verdict $c 'degraded' 'fw_partial_off' @(($offN -join ', ')) }
  else { Set-Verdict $c 'pass' 'fw_ok' @($netshStates.Count) }
} else {
  Set-Verdict $c 'unknown' 'fw_unavailable' @($fwDom.error)
}
Add-Check $c

# power: idle sleep indices (raw hex, structural parse of the last two index lines)
function Read-PowerIndices {
  param($Probe,[string]$Alias)
  $out = [ordered]@{ ok=$false; acHex=''; dcHex=''; strategy=''; allHex=@(); crossChecked=$false; note=''; lines=@() }
  if (-not $Probe.available) { $out.note = $Probe.error; return $out }
  $hexRe = '0x[0-9a-fA-F]{8}'
  $lines = @(($Probe.stdout -split "`r?`n") | Where-Object { $_.Trim() -ne '' })
  $out.lines = @($lines | Select-Object -First 14)
  if ($lines.Count -ge 2) {
    $l1 = $lines[$lines.Count - 2]; $l2 = $lines[$lines.Count - 1]
    $m1 = @([regex]::Matches($l1, $hexRe)); $m2 = @([regex]::Matches($l2, $hexRe))
    if ($m1.Count -eq 1 -and $m2.Count -eq 1) {
      $out.acHex = $m1[0].Value; $out.dcHex = $m2[0].Value; $out.ok = $true
      $out.strategy = 'last-two-nonempty-lines-each-with-one-hex (the AC index line precedes the DC index line)'
    }
  }
  $all = New-Object System.Collections.ArrayList
  foreach ($m in [regex]::Matches($Probe.stdout, $hexRe)) { [void]$all.Add($m.Value) }
  $out.allHex = $all.ToArray()
  $aliasIdx = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match [regex]::Escape($Alias)) { $aliasIdx = $i } }
  $crossAc = ''; $crossDc = ''
  if ($aliasIdx -ge 0) {
    $tailHex = New-Object System.Collections.ArrayList
    for ($i = $aliasIdx; $i -lt $lines.Count; $i++) { foreach ($m in [regex]::Matches($lines[$i], $hexRe)) { [void]$tailHex.Add($m.Value) } }
    if ($tailHex.Count -ge 2) {
      $crossAc = $tailHex[$tailHex.Count - 2]; $crossDc = $tailHex[$tailHex.Count - 1]
      $out.crossChecked = $true
      if ($out.ok -and ($crossAc -ne $out.acHex -or $crossDc -ne $out.dcHex)) {
        $out.ok = $false
        $out.note = 'structural parse and alias cross-check disagree; refusing to guess'
      } elseif ($out.ok) {
        $out.strategy = $out.strategy + ' + alias-cross-check'
      }
    }
  }
  if (-not $out.ok -and -not $out.note) { $out.note = 'output structure does not match the known template' }
  return $out
}

$c = New-Check 'POWER_STANDBY_IDLE_AC_DC' 'server' 'power_standby_idle'
Add-Cmd $c ('powercfg /query SCHEME_CURRENT ' + $SUB_SLEEP + ' ' + $SET_STANDBY + '   (raw 0x indices; localized labels are never parsed)')
Add-Cmd $c ('powercfg /query SCHEME_CURRENT ' + $SUB_SLEEP + ' ' + $SET_HIBERNATE)
$standbyProbe = Invoke-External 'powercfg_query_standby' $script:Tools['powercfg'] @('/query','SCHEME_CURRENT',$SUB_SLEEP,$SET_STANDBY) $CommandTimeoutMs
$hibProbe = Invoke-External 'powercfg_query_hibernate' $script:Tools['powercfg'] @('/query','SCHEME_CURRENT',$SUB_SLEEP,$SET_HIBERNATE) $CommandTimeoutMs
$sb = Read-PowerIndices $standbyProbe 'STANDBYIDLE'
$hb = Read-PowerIndices $hibProbe 'HIBERNATEIDLE'
$c.raw.standby = [ordered]@{ ok=$sb.ok; acHex=$sb.acHex; dcHex=$sb.dcHex; strategy=$sb.strategy; crossChecked=$sb.crossChecked; allHex=@($sb.allHex); note=$sb.note }
$c.raw.hibernate = [ordered]@{ ok=$hb.ok; acHex=$hb.acHex; dcHex=$hb.dcHex; strategy=$hb.strategy; note=$hb.note }
$c.raw.meaningOfZero = 'for STANDBYIDLE/HIBERNATEIDLE the value 0 means NEVER; the same literal 0 means OFF/DISABLED for HYBRIDSLEEP/RTCWAKE and SLEEP for UIBUTTON_ACTION - never read a bare 0 without its alias'
$c.raw.linkRelevance = 'only STANDBYIDLE and HIBERNATEIDLE can kill the link; VIDEOIDLE (screen off) is irrelevant'
function Convert-HexSeconds { param([string]$H)
  $v = 0
  if ($H -match '^0x([0-9a-fA-F]{8})$') { $v = [Convert]::ToInt64($Matches[1], 16) }
  return $v
}
if (-not $sb.ok) {
  Set-Verdict $c 'unknown' 'power_unparsed' @('STANDBYIDLE')
} else {
  $acS = Convert-HexSeconds $sb.acHex
  $dcS = Convert-HexSeconds $sb.dcHex
  $c.raw.acSeconds = $acS
  $c.raw.dcSeconds = $dcS
  if ($acS -eq 0 -and $dcS -eq 0) {
    Set-Verdict $c 'pass' 'power_ok' @($sb.acHex, $sb.dcHex)
  } elseif ($acS -eq 0 -and $dcS -gt 0) {
    Set-Verdict $c 'degraded' 'power_dc_only' @($dcS, $sb.dcHex)
    Set-Remediation $c 'rem_power_dc' ('powercfg /change standby-timeout-dc 0   # keep the machine awake on battery too; current DC value is ' + $dcS + ' s') 'powercfg /change standby-timeout-dc <previous value in minutes>  # record it before the change' $true
  } elseif ($acS -gt 0) {
    Set-Verdict $c 'blocked' 'power_ac_nonzero' @($acS, $sb.acHex)
    Set-Remediation $c 'rem_power_ac' ('powercfg /change standby-timeout-ac 0   # a server that sleeps on mains power kills the link; current AC value is ' + $acS + ' s') 'powercfg /change standby-timeout-ac <previous value in minutes>' $true
  } else {
    Set-Verdict $c 'unknown' 'power_unparsed' @('STANDBYIDLE')
  }
}
Add-Check $c

# power: sleep-state catalogue (structure parse + explicit manual review)
$c = New-Check 'POWER_S0_CAPABILITY' 'server' 'power_s0_capability'
Add-Cmd $c 'powercfg /a   (blocks are located by ": "-terminated header lines; the S0 line is reported verbatim)'
$pwA = Invoke-External 'powercfg_a' $script:Tools['powercfg'] @('/a') $CommandTimeoutMs
$s0Available = ''
$s0Line = ''
$headerIdxs = New-Object System.Collections.ArrayList
$nonEmpty = @()
if ($pwA.available) {
  $nonEmpty = @(($pwA.stdout -split "`r?`n") | Where-Object { $_.Trim() -ne '' })
  for ($i = 0; $i -lt $nonEmpty.Count; $i++) {
    $t = $nonEmpty[$i].Trim()
    if ($t.EndsWith(':') -or $t.EndsWith([char]0xFF1A)) { [void]$headerIdxs.Add($i) }
  }
  for ($i = 0; $i -lt $nonEmpty.Count; $i++) {
    if ($nonEmpty[$i] -match 'S0') { $s0Line = $nonEmpty[$i].Trim(); if ($headerIdxs.Count -ge 2) { if ($i -lt $headerIdxs[1]) { $s0Available = 'yes' } else { $s0Available = 'no' } }; break }
  }
}
$c.raw.probe = [ordered]@{ available=$pwA.available; error=$pwA.error }
$c.raw.structureHeaderCount = $headerIdxs.Count
$c.raw.s0Present = ($s0Line -ne '')
$c.raw.s0Available = $s0Available
$c.raw.s0RawLine = $s0Line
$c.raw.rawOutput = @($nonEmpty)
$c.raw.rule = 'sleep capability comes from firmware/platform, never from the OS major version; the first block lists AVAILABLE states, the second lists unavailable ones'
$c.manualReview = $true
$c.manualQuestion = 'manual_s0_network'
if (-not $pwA.available) {
  Set-Verdict $c 'unknown' 'power_unparsed' @('powercfg /a')
} elseif ($s0Line -eq '' -or $headerIdxs.Count -lt 2) {
  Set-Verdict $c 'unknown' 's0_unparsed' @($headerIdxs.Count)
} else {
  Set-Verdict $c 'pass' 's0_ok' @($s0Available)
}
Add-Check $c

# DSH network exposure setting (read from the actually loaded settings file)
$c = New-Check 'DSH_NETWORK_EXPOSURE' 'server' 'network_exposure_config'
Add-Cmd $c 'file: <DSH_HOME>\settings.yaml   (networkExposure / mode, read as explicit UTF-8)'
$settingsPath = ''
if ($dshHomeVal) { $settingsPath = Join-Path $dshHomeVal 'settings.yaml' }
$setProbe = Get-FileProbe 'settings_yaml' $settingsPath
$exposure = ''
$mode = ''
if ($setProbe.available) {
  $m = [regex]::Match($setProbe.text, '(?im)^\s*networkExposure\s*:\s*(\S+)\s*$')
  if ($m.Success) { $exposure = $m.Groups[1].Value }
  $m2 = [regex]::Match($setProbe.text, '(?im)^\s*mode\s*:\s*(\S+)\s*$')
  if ($m2.Success) { $mode = $m2.Groups[1].Value }
}
$c.raw.file = $settingsPath
$c.raw.probe = [ordered]@{ available=$setProbe.available; source=$setProbe.source; error=$setProbe.error }
$c.raw.networkExposure = $exposure
$c.raw.mode = $mode
$c.raw.note = 'the DSH desktop web server host is hard-wired to 127.0.0.1 regardless of this value; it selects the HTTPS edge intent only'
if (-not $setProbe.available) {
  Set-Verdict $c 'unknown' 'exposure_unavailable' @($setProbe.error)
} elseif (-not $exposure) {
  Set-Verdict $c 'unknown' 'exposure_key_absent' @()
} elseif ($exposure -eq 'loopback') {
  Set-Verdict $c 'pass' 'exposure_ok' @($mode)
} else {
  $c.raw.level = 'blocked (t16 F6: the delivered spec grades this blocked; a widened exposure intent is a security finding, not a degradation - implementation, panel and docs now agree)'
  Set-Verdict $c 'blocked' 'exposure_lan' @($exposure)
  Set-Remediation $c 'rem_exposure_loopback' 'If you did not intend LAN exposure, set dsh-desktop.networkExposure back to loopback and restart DSH from its own Restart menu' 'set it back to the previous value and restart DSH from its own menu' $false
}
Add-Check $c

# trustedHosts in the actually loaded patch chain
$c = New-Check 'TRUSTED_HOSTS_PATCH' 'server' 'trusted_hosts_patch'
Add-Cmd $c 'files: cordis.patch.yml / cordis.yml from the app bundle and the active profile (trustedHosts keys and their values)'
$patchProbe = Get-FileListProbe 'patch_files' $patchPaths
$thMatches = New-Object System.Collections.ArrayList
$thGood = New-Object System.Collections.ArrayList
foreach ($f in @($patchProbe.files)) {
  $lines = @($f.text -split "`r?`n")
  for ($i = 0; $i -lt $lines.Count; $i++) {
    $m = [regex]::Match($lines[$i], '(?m)^\s*-?\s*trustedHosts\s*:\s*(.*)$')
    if (-not $m.Success) { continue }
    $inline = $m.Groups[1].Value.Trim()
    $vals = New-Object System.Collections.ArrayList
    if ($inline -ne '') {
      if ($inline -match '^\[') {
        foreach ($vm in [regex]::Matches($inline, "'([^']*)'|""([^""]*)""|([^\[\],\s]+)")) {
          $s = $vm.Groups[1].Value + $vm.Groups[2].Value + $vm.Groups[3].Value
          if ($s -and $s -ne '[]' -and $s -ne ']' -and $s -ne '[') { [void]$vals.Add($s) }
        }
      } else { [void]$vals.Add($inline) }
    } else {
      for ($j = $i + 1; $j -lt $lines.Count; $j++) {
        $lt = $lines[$j]
        if ($lt -match '^\s*-\s+(.+?)\s*$') { [void]$vals.Add($Matches[1]) } else { if ($lt.Trim() -ne '') { break } }
      }
    }
    [void]$thMatches.Add([ordered]@{ path=$f.path; line=($i + 1); inline=$inline; values=@($vals.ToArray()) })
    foreach ($v in @($vals.ToArray())) { if ($v -match $TrustedHostPattern) { [void]$thGood.Add($v) } }
  }
}
$c.raw.filesConsidered = $patchProbe.files.Count
$c.raw.files = @($patchProbe.files | ForEach-Object { $_.path })
$c.raw.trustedHostsEntries = $thMatches.ToArray()
$c.raw.matchesPattern = @($thGood.ToArray())
$c.raw.pattern = $TrustedHostPattern
$c.raw.whyItMatters = 'without a matching trusted host the remote UI opens but every /api call is fenced with 403 and the client loops on "reconnecting"'
$c.raw.restartDiscipline = 'after changing this, restart DSH only from its own Restart menu; never kill the host process'
if (-not $patchProbe.available) {
  Set-Verdict $c 'unknown' 'th_unavailable' @($patchProbe.error)
} elseif ($multipleProfilesUnresolved) {
  $c.raw.profilesFound = $profileList
  Set-Verdict $c 'unknown' 'th_multi_profile' @(($profileList -join ', '))
} elseif ($thGood.Count -gt 0) {
  Set-Verdict $c 'pass' 'th_ok' @(($thGood.ToArray() -join ', '))
} elseif ($thMatches.Count -gt 0) {
  Set-Verdict $c 'blocked' 'th_blocked' @($thMatches.Count)
  Set-Remediation $c 'rem_th_add' 'Add the server MagicDNS name to connection.trustedHosts in the active profile patch, then restart DSH from its own menu' 'delete the added trustedHosts line and restart DSH from its own menu' $false
} else {
  Set-Verdict $c 'unknown' 'th_key_absent' @($patchProbe.files.Count)
}
Add-Check $c

# serve presence on the tailnet side
$c = New-Check 'SERVE_PRESENT' 'server' 'serve_present'
Add-Cmd $c 'netstat.exe -ano  (tailnet-address LISTENING rows, owner resolved by PID) - CORROBORATION ONLY: a healthy node always has tailscaled-owned tailnet listeners, so this shape is NOT evidence of a moved serve'
Add-Cmd $c 'tailscale.exe serve status   (the proxy TARGET port is the evidence; unreadable when the named pipe is protected - that is not a configuration answer)'
$tailnetRows = @($preRows | Where-Object { (Test-CgnatV4 $_.host) -or (Test-TailscaleV6 $_.host) })
$serveRows = @($tailnetRows | Where-Object { $_.port -eq '443' })
# rows = EVERY tailnet-address listener, not only the 443 subset: t11 case fault-serve-moved-port-8443
# requires that the evidence a human needs (port + classification + owner) survives even when serve
# has moved off 443, because the collector must not report a false pass there.
$c.raw.rows = @($tailnetRows | ForEach-Object { [ordered]@{ local=$_.local; port=$_.port; host=$_.host; pid=$_.pid; process=$_.process } })
$c.raw.serveRows = @($serveRows | ForEach-Object { [ordered]@{ local=$_.local; port=$_.port; pid=$_.pid; process=$_.process } })
$c.raw.rowsNote = 'rows = every tailnet-address listener (corroboration only); serveRows = the 443 subset; the verdict itself comes from the readable serve status target port'
$c.raw.serveStatusExitCode = $tsServe.exitCode
$c.raw.serveStatusStderr = @(($tsServe.stderr -split "`r?`n") | Where-Object { $_.Trim() -ne '' })
$c.raw.alternatives = 'a missing Windows-side listener does not prove "serve is not configured": tailscaled may terminate TLS outside the Windows TCP stack, and the CLI may be sandboxed away'
$c.manualReview = $true
$c.manualQuestion = 'manual_serve_status'
# t23 (after the t22 experiment): the tailnet LISTENER SHAPE is NOT evidence of a moved serve.
# A healthy, connected node always carries tailscaled-owned tailnet listeners (peerapi / WireGuard
# side) - measured on the reference machine: <PEER_IP>:33588 and the <ULA_IP>:56868 endpoint,
# both owned by tailscaled, with nothing published on 443. Judging "blocked" from that shape alone
# misreports every connected node. The only evidence about where serve points is the proxy TARGET
# port inside a readable 'tailscale serve status'. See docs/defensive-spec.md section 7 case 10.
$serveTargetPattern = Get-Pattern 'serve_proxy_target' 'proxy\s+http://127\.0\.0\.1:(\d+)'
$targetPorts = New-Object System.Collections.ArrayList
if ($tsServe.exitCode -eq 0) {
  foreach ($m in [regex]::Matches([string]$tsServe.stdout, $serveTargetPattern)) {
    if ($m.Groups.Count -gt 1 -and $m.Groups[1].Success) {
      $tp = ([string]$m.Groups[1].Value).Trim()
      if ($tp -ne '') { [void]$targetPorts.Add($tp) }
    }
  }
}
$c.raw.serveStatusReadable = ($tsServe.exitCode -eq 0)
$c.raw.serveTargetPattern = $serveTargetPattern
$c.raw.serveTargetPorts = @($targetPorts.ToArray())
$c.raw.dshPortMeasured = $portNum
$c.raw.listenerShapeNote = 'the tailnet listener shape is NOT evidence of a moved serve: every connected node carries tailscaled-owned tailnet listeners (peerapi / WireGuard side). Evidence = the proxy target port in a readable serve status.'
$wrongTargets = @($targetPorts.ToArray() | Where-Object { $_ -ne [string]$portNum })
if ($tsServe.exitCode -ne 0 -or $targetPorts.Count -eq 0) {
  Set-Verdict $c 'unknown' 'serve_unknown' @($tsServe.exitCode)
} elseif ($wrongTargets.Count -gt 0) {
  Set-Verdict $c 'blocked' 'serve_port_mismatch' @(($wrongTargets -join ', '), $portNum)
  Set-Remediation $c 'rem_serve_443' ('republish the DSH port so serve proxies to it: tailscale serve --bg ' + $portNum + '   # serve must proxy to 127.0.0.1:' + $portNum + ', not ' + ($wrongTargets -join ', ')) 'tailscale serve reset   # clears the WHOLE serve configuration on this machine (not just one port); record the current config first (tailscale serve status)' $false
} elseif ($serveRows.Count -gt 0) {
  $ownNames = @($serveRows | ForEach-Object { $_.process } | Sort-Object -Unique)
  if ($ownNames -contains 'tailscaled') {
    Set-Verdict $c 'pass' 'serve_ok' @($serveRows.Count)
  } else {
    Set-Verdict $c 'degraded' 'serve_owner_other' @(($ownNames -join ', '))
  }
} else {
  Set-Verdict $c 'unknown' 'serve_unknown' @($tsServe.exitCode)
}
Add-Check $c

# --- client role ------------------------------------------------------------
$c = New-Check 'PEER_TCP_443' 'client' 'peer_tcp_443'
Add-Cmd $c '.NET TcpClient BeginConnect + WaitOne(N ms) against <peer>:443   (TCP handshake only; no TLS, no HTTP)'
if (-not $Peer) {
  $c.raw.peer = ''
  Set-Verdict $c 'unknown' 'peer_not_provided' @()
} else {
  $pr = Invoke-TcpProbe $Peer 443 $TcpTimeoutMs
  $c.raw.peer = $Peer
  $c.raw.probe = [ordered]@{ result=$pr.result; ms=$pr.ms; source=$pr.source; error=$pr.error }
  if ($pr.result -eq 'connected') { Set-Verdict $c 'pass' 'peer_443_ok' @($pr.ms) }
  elseif ($pr.result -eq 'refused') { Set-Verdict $c 'blocked' 'peer_443_refused' @($pr.ms) }
  elseif ($pr.result -eq 'timeout') { Set-Verdict $c 'blocked' 'peer_443_timeout' @($TcpTimeoutMs) }
  else { Set-Verdict $c 'unknown' 'peer_probe_unavailable' @($pr.error) }
}
Add-Check $c

$c = New-Check 'PEER_ISOLATION_PROBES' 'client' 'peer_isolation_probes'
Add-Cmd $c '.NET TcpClient probe against <peer>:135, <peer>:5357, <peer>:<dshPort>   (expect NOT reachable; a reachable DSH port means the loopback bind is broken)'
if (-not $Peer) {
  Set-Verdict $c 'unknown' 'peer_not_provided' @()
} else {
  $probePorts = @(135, 5357, $portNum)
  $results = [ordered]@{}
  $dshReachable = $false
  $otherReachable = New-Object System.Collections.ArrayList
  foreach ($pp in $probePorts) {
    $pr = Invoke-TcpProbe $Peer $pp $TcpTimeoutMs
    $results[[string]$pp] = [ordered]@{ result=$pr.result; ms=$pr.ms; source=$pr.source }
    if ($pp -eq $portNum -and $pr.result -eq 'connected') { $dshReachable = $true }
    if ($pp -ne $portNum -and $pr.result -eq 'connected') { [void]$otherReachable.Add($pp) }
  }
  $c.raw.peer = $Peer
  $c.raw.results = $results
  $c.raw.dshPort = $portNum
  if ($dshReachable) {
    Set-Verdict $c 'blocked' 'peer_iso_dsh_open' @($portNum)
  } elseif ($otherReachable.Count -gt 0) {
    Set-Verdict $c 'degraded' 'peer_iso_too_open' @(($otherReachable.ToArray() -join ', '))
  } else {
    Set-Verdict $c 'pass' 'peer_iso_ok' @()
  }
}
Add-Check $c

$c = New-Check 'MAGICDNS_RESOLVE' 'client' 'magicdns_resolve'
Add-Cmd $c '.NET Dns BeginGetHostAddresses + WaitOne(N ms) for the peer MagicDNS name'
if (-not $peerNameVal) {
  Set-Verdict $c 'unknown' 'peer_not_provided' @()
} else {
  $dr = Invoke-DnsProbe $peerNameVal $DnsTimeoutMs
  $c.raw.name = $peerNameVal
  $c.raw.probe = [ordered]@{ result=$dr.result; addresses=@($dr.addresses); socketError=$dr.socketError; source=$dr.source; error=$dr.error }
  $inTailnet = $false
  foreach ($a in @($dr.addresses)) { if ((Test-CgnatV4 $a) -or (Test-TailscaleV6 $a)) { $inTailnet = $true } }
  $c.raw.resolvedIntoTailnetRange = $inTailnet
  if ($dr.result -eq 'ok' -and $inTailnet) { Set-Verdict $c 'pass' 'dns_ok' @($peerNameVal, (@($dr.addresses) -join ', ')) }
  elseif ($dr.result -eq 'ok') { Set-Verdict $c 'degraded' 'dns_off_tailnet' @($peerNameVal, (@($dr.addresses) -join ', ')) }
  elseif ($dr.socketError -eq 'HostNotFound') { Set-Verdict $c 'blocked' 'dns_hostnotfound' @($peerNameVal) }
  elseif ($dr.result -eq 'error' -and $dr.error -match 'HostNotFound|No such host') { Set-Verdict $c 'blocked' 'dns_hostnotfound' @($peerNameVal) }
  else { Set-Verdict $c 'unknown' 'dns_failed' @($dr.result, $dr.error) }
}
Add-Check $c

$c = New-Check 'BROWSER_PROXY_TSNET' 'client' 'browser_proxy_tsnet'
Add-Cmd $c 'registry HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings (ProxyEnable, ProxyServer, ProxyOverride)'
$proxyReg = Get-RegProbe 'internet_settings' 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' @('ProxyEnable','ProxyServer','ProxyOverride','ProxyHttp1.1')
$c.raw.proxyEnable = $proxyReg.values['ProxyEnable']
$c.raw.proxyServer = [string]$proxyReg.values['ProxyServer']
$c.raw.proxyOverride = [string]$proxyReg.values['ProxyOverride']
$c.raw.probe = [ordered]@{ available=$proxyReg.available; source=$proxyReg.source; error=$proxyReg.error }
if (-not $proxyReg.available) {
  Set-Verdict $c 'unknown' 'proxy_unavailable' @($proxyReg.error)
} elseif ([int]$proxyReg.values['ProxyEnable'] -eq 0) {
  Set-Verdict $c 'pass' 'proxy_ok' @('disabled')
} else {
  $ov = [string]$proxyReg.values['ProxyOverride']
  $bypassOk = $false
  if ($ov -match '(?i)ts\.net' -or $ov -match '100\.64\.' -or ($peerNameVal -and $ov -match [regex]::Escape($peerNameVal)) -or ($Peer -and $ov -match [regex]::Escape($Peer))) { $bypassOk = $true }
  if ($bypassOk) { Set-Verdict $c 'pass' 'proxy_ok' @('bypassed') }
  else {
    Set-Verdict $c 'degraded' 'proxy_hijack' @('ts.net')
    Set-Remediation $c 'rem_proxy_bypass' 'Add the tailnet name/range to the proxy bypass list, or disable the system proxy while using the link' 'remove the bypass entry you added' $false
  }
}
Add-Check $c

$c = New-Check 'HTTPS_CLIENT_ONLY' 'client' 'https_client_only'
Add-Cmd $c 'capability declaration only: no TLS/HTTP request is made by this collector'
$nodeOk = ($nodePath -ne '')
$c.raw.node = $nodePath
$c.raw.openssl = ''
$c.raw.reason = 'an HTTPS/certificate verdict needs a client that can present SNI, and curl.exe under schannel returns 000 even when the server is healthy'
$hint = 'node -e "require(''https'').request({host:''<peer>'',port:443,servername:''<peerName>'',headers:{Host:''<peerName>''},rejectUnauthorized:true},r=>{console.log(r.statusCode);process.exit(0)}).on(''error'',e=>{console.log(''ERR'',e.code);process.exit(1)}).end()"'
if ($peerNameVal) { $hint = $hint.Replace('<peerName>', $peerNameVal) } else { $hint = $hint.Replace('<peerName>', '<peerMagicDnsName>') }
if ($Peer) { $hint = $hint.Replace('<peer>', $Peer) } else { $hint = $hint.Replace('<peer>', '<peerAddress>') }
$c.raw.nodeAvailable = $nodeOk
$c.raw.manualCommand = $hint
$c.manualReview = $true
$c.manualQuestion = 'manual_https'
Set-Verdict $c 'unknown' 'https_client_only' @()
Add-Check $c

# --- read-only self-proof (runs last; needs the post snapshot) ---------------
$c = New-Check 'CREDENTIAL_DISCIPLINE' 'both' 'credential_discipline'
Add-Cmd $c 'static self-audit of every probe command string executed in this run'
Add-Cmd $c 'declared never-touched stores: DSH secret store, DSH bridge file, browser profile databases'
$violations = New-Object System.Collections.ArrayList
foreach ($chk in $script:Checks) {
  foreach ($cmdText in @($chk.commands)) {
    if ($cmdText -match '(?i)credential|cookie|password|secret|token') { [void]$violations.Add($chk.id + ': ' + $cmdText) }
  }
}
$probedPaths = New-Object System.Collections.ArrayList
foreach ($p in @($settingsPath)) { if ($p) { [void]$probedPaths.Add($p) } }
foreach ($f in @($patchProbe.files)) { [void]$probedPaths.Add($f.path) }
foreach ($p in @($probedPaths)) { if ($p -match '(?i)credential|cookie|\.token') { [void]$violations.Add('path: ' + $p) } }
$c.raw.declaredNotRead = @('.dsh\.credentials.yaml','ext-bridge-token','browser cookie databases','any session log')
$c.raw.pathsRead = $probedPaths.ToArray()
$c.raw.sourceBytesRead = 0
$c.raw.violations = $violations.ToArray()
$c.raw.note = 'the collector reads no secret material; this check fails closed if a probe command string ever mentions one'
if ($violations.Count -eq 0) { Set-Verdict $c 'pass' 'cred_ok' @($probedPaths.Count) }
else { Set-Verdict $c 'blocked' 'cred_violation' @($violations.Count) }
Add-Check $c

$postProbe = Invoke-External 'netstat_post' $script:Tools['netstat'] @('-ano') $CommandTimeoutMs
$postParse = ConvertFrom-NetstatLines @($postProbe.stdout -split "`r?`n")
$postRows = @($postParse.rows)
$c = New-Check 'NO_NEW_WILDCARD_LISTENER' 'both' 'no_new_wildcard_listener'
Add-Cmd $c 'netstat.exe -ano  (LISTENING rows; snapshot taken before and after collection, wildcard entries diffed)'
$preWild = @{}
foreach ($r in $preRows) { if (Test-WildcardHost $r.host) { $preWild[($r.host + ':' + $r.port + '|' + $r.pid)] = $r } }
$postWild = @{}
foreach ($r in $postRows) { if (Test-WildcardHost $r.host) { $postWild[($r.host + ':' + $r.port + '|' + $r.pid)] = $r } }
$newWild = New-Object System.Collections.ArrayList
foreach ($k in $postWild.Keys) { if (-not $preWild.ContainsKey($k)) { [void]$newWild.Add($k) } }
$c.raw.preWildcard = @($preWild.Keys | Sort-Object)
$c.raw.postWildcard = @($postWild.Keys | Sort-Object)
$c.raw.newWildcard = $newWild.ToArray()
$c.raw.rowCounts = [ordered]@{ pre=$preRows.Count; post=$postRows.Count; note='counts fluctuate (TIME_WAIT) and are never a criterion' }
$c.raw.probe = [ordered]@{ pre=$netstatProbe.source; post=$postProbe.source; postAvailable=$postProbe.available; error=$postProbe.error }
$c.raw.stateWordUnrecognized = [ordered]@{ pre=$preParse.stateWordUnrecognized; post=$postParse.stateWordUnrecognized }
$c.raw.statePattern = $preParse.statePattern
if (-not $netstatProbe.available -or -not $postProbe.available) {
  Set-Verdict $c 'unknown' 'ro_probe_unavailable' @()
} elseif ($preRows.Count -eq 0 -or $postRows.Count -eq 0) {
  # t16 F5: two empty snapshots diff to "no new listener", which would be a false self-proof.
  Set-Verdict $c 'unknown' 'ro_probe_unavailable' @()
} elseif ($newWild.Count -gt 0) {
  Set-Verdict $c 'blocked' 'ro_new_wildcard' @(($newWild.ToArray() -join ', '))
} else {
  Set-Verdict $c 'pass' 'ro_no_new_wildcard' @($preWild.Count, $postWild.Count)
}
Add-Check $c

# ---------------------------------------------------------------------------
# section 6: report, render, exit code
# ---------------------------------------------------------------------------
if ($DumpFixture) {
  $fxOut = [ordered]@{
    schema = 'remote-tailnet-guard/fixture/1'
    name = ('capture ' + $script:Now.ToString('yyyy-MM-dd HH:mm:ss'))
    locale = ''
    role = $Role
    note = 'every value here is a probe result recorded by collect.ps1 -DumpFixture; replay it with -FixturePath <this file> [-NoNative]'
  }
  try { $fxOut.locale = [System.Globalization.CultureInfo]::CurrentUICulture.Name } catch { $fxOut.locale = '' }
  foreach ($grp in @('native','registry','files','fileLists','services','cmdlets','network')) {
    $node = [ordered]@{}
    foreach ($k in @($script:ProbeLog.Keys)) {
      $prefix = $grp + '.'
      if ($k.StartsWith($prefix)) { $node[$k.Substring($prefix.Length)] = $script:ProbeLog[$k] }
    }
    if ($node.Count -gt 0) { $fxOut[$grp] = $node }
  }
  $procNode = [ordered]@{}
  foreach ($pidKey in @($script:ProcNameCache.Keys)) {
    $nm = [string]$script:ProcNameCache[$pidKey]
    if ($nm) { $procNode[[string]$pidKey] = $nm }
  }
  if ($procNode.Count -gt 0) { $fxOut['processes'] = $procNode }
  try {
    [System.IO.File]::WriteAllText($DumpFixture, ($fxOut | ConvertTo-Json -Depth 12), (New-Object System.Text.UTF8Encoding($false)))
    Write-Output ('fixture written: ' + $DumpFixture)
  } catch { Write-Output ('DUMPFIXTURE FAILED: ' + $_.Exception.Message) }
  exit 0
}

$checksOut = @()
foreach ($chk in $script:Checks) {
  if ($chk.role -eq 'server' -and -not $wantServer) { continue }
  if ($chk.role -eq 'client' -and -not $wantClient) { continue }
  $vl = LV 'verdict' $chk.verdict $chk.verdict
  if ($chk.manualQuestion) { $mq = LV 'manual' $chk.manualQuestion $chk.manualQuestion } else { $mq = '' }
  # defensive-spec 4.1/4.3(d): every judgement carries status + evidence and, when the
  # verdict had to lean on localized text, an explicit low confidence.
  $conf = 'high'
  if ($chk.verdict -eq 'unknown') { $conf = 'none' }
  if ($chk.id -eq 'NIC_PROFILE_ATTRIBUTION' -and ([string]$chk.raw.matchMethod) -like 'netsh*') { $conf = 'low' }
  if ($chk.id -eq 'FIREWALL_PROFILES' -and -not [bool]$chk.raw.registry.domain.available) { $conf = 'low' }
  if ($chk.id -eq 'POWER_S0_CAPABILITY' -and $chk.verdict -eq 'pass') { $conf = 'low' }
  if ($chk.id -eq 'TAILSCALE_PROCESS_EDGE_DB' -and -not [bool]$chk.raw.registryAvailable) { $conf = 'low' }
  if ($chk.informational) { $conf = 'high' }
  # defensive-spec 4.1: a verdict that had to lean on localized text is a low-confidence
  # path, so a "pass" there is reported as degraded instead of being presented as proven.
  $downgraded = $false
  if ($conf -eq 'low' -and $chk.verdict -eq 'pass') { $chk.verdict = 'degraded'; $downgraded = $true; $vl = LV 'verdict' $chk.verdict $chk.verdict }
  $probeExit = $null
  foreach ($k in @('exitCode','version','serveStatusExitCode')) {
    if ($null -ne $chk.raw[$k]) {
      if ($k -eq 'exitCode' -and $null -ne $chk.raw[$k]) { $probeExit = $chk.raw[$k]; break }
      if ($k -eq 'version' -and $null -ne $chk.raw[$k].exitCode) { $probeExit = $chk.raw[$k].exitCode; break }
      if ($k -eq 'serveStatusExitCode') { $probeExit = $chk.raw[$k]; break }
    }
  }
  $cmdList = @($chk.commands)
  $firstCmd = ''
  if ($cmdList.Count -gt 0) { $firstCmd = [string]$cmdList[0] }
  $srcKind = 'native'
  if ($null -ne $script:Fixture) { $srcKind = 'fixture' }
  $checksOut += [pscustomobject][ordered]@{
    id = $chk.id
    role = $chk.role
    title = $chk.title
    titleKey = $chk.titleKey
    status = $chk.verdict
    verdict = $chk.verdict
    verdictLabel = $vl
    severity = (Get-Severity $chk.verdict)
    informational = $chk.informational
    reasonKey = $chk.reasonKey
    reason = $chk.reason
    commands = $cmdList
    evidence = [ordered]@{ command=$firstCmd; commands=$cmdList; exitCode=$probeExit; source=$srcKind; confidence=$conf; window='current-run'; confidenceDowngrade=$downgraded; confidenceNote=('text-parse-only path: reported as degraded by policy' * [int]$downgraded) }
    raw = $chk.raw
    remediation = $chk.remediation
    manualReview = $chk.manualReview
    manualQuestion = $mq
  }
}

$nPass = 0; $nDeg = 0; $nBlk = 0; $nUnk = 0
foreach ($o in $checksOut) {
  switch ($o.verdict) {
    'pass' { $nPass++ }
    'degraded' { $nDeg++ }
    'blocked' { $nBlk++ }
    default { $nUnk++ }
  }
}
$exitCode = 0
if ($nBlk -gt 0) { $exitCode = 2 }
elseif ($nUnk -gt 0) { if ($Strictness -eq 'strict') { $exitCode = 2 } else { $exitCode = 1 } }
elseif ($nDeg -gt 0) { $exitCode = 1 }
if ($script:CollectorFaults.Count -gt 0) { $exitCode = 2 }

$verdictOverall = 'pass'
if ($exitCode -eq 1) { $verdictOverall = 'degraded' }
if ($exitCode -eq 2) { $verdictOverall = 'blocked' }
$overallLabel = LV 'verdict' $verdictOverall $verdictOverall
$exitMeaningKey = 'exit_' + [string]$exitCode
$exitMeaning = LV 'exit' $exitMeaningKey $exitMeaningKey

$report = [pscustomobject][ordered]@{
  schema = 'remote-tailnet-guard/collect/1'
  collector = [ordered]@{
    version = 'v0.2'
    lastUpdated = '2026-09-24'
    generatedAtLocal = $script:Now.ToString('yyyy-MM-dd HH:mm:ss')
    generatedAtUtc = $script:Now.ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ssZ')
    host = $env:COMPUTERNAME
    user = $env:USERNAME
    psVersion = $psv
    psEdition = $edition
    elevated = $elevated
    readOnly = $true
    role = $Role
    strictness = $Strictness
  }
  config = @($script:Config)
  labels = [ordered]@{ lang = $script:LangUsed; dir = $LabelsDir; loaded = $labelsLoaded; patternSources = @($script:PatternSources.ToArray()); patternCount = $script:Patterns.Count; missingKeys = @($script:MissingLabels.ToArray()) }
  fixture = [ordered]@{ path = $FixturePath; loaded = ($null -ne $script:Fixture); noNative = $script:NoNative }
  collectorFaults = @($script:CollectorFaults.ToArray())
  summary = [ordered]@{
    total = $checksOut.Count
    pass = $nPass
    degraded = $nDeg
    blocked = $nBlk
    unknown = $nUnk
    verdict = $verdictOverall
    verdictLabel = $overallLabel
    exitCode = $exitCode
    exitMeaningKey = $exitMeaningKey
    exitMeaning = $exitMeaning
    failClosed = 'any unknown forbids exit 0'
  }
  checks = $checksOut
  portability = [ordered]@{
    hardcodedMachineSpecific = @()
    envDependent = @(
      'Tailscale rule names Tailscale-Process / Tailscale-In (product names; a renamed rule yields unknown/blocked, never a guess)',
      'adapter-to-profile section headers from netsh (English on en-US and zh-CN; a fully localized netsh yields unknown + raw output)',
      'tailnet address discovery needs a 100.64.0.0/10 address present (i.e. Tailscale signed in)',
      'appDir discovery prefers -AppDir / DSH_APP_DIR, then the running DSH process image path'
    )
    howToRunElsewhere = 'powershell -NoProfile -ExecutionPolicy Bypass -File src/collect.ps1 -CheckOnly -AsJson'
  }
}

$json = $report | ConvertTo-Json -Depth 14

if ($OutFile) {
  try {
    [System.IO.File]::WriteAllText($OutFile, $json, (New-Object System.Text.UTF8Encoding($false)))
    Write-Output ('report written: ' + $OutFile)
  } catch { Write-Output ('OUTFILE FAILED: ' + $_.Exception.Message) }
}

if ($AsJson) {
  Write-Output $json
} else {
  Write-Output '== remote-tailnet-guard collector (read-only) =='
  Write-Output ('host=' + $env:COMPUTERNAME + ' ps=' + $psv + ' role=' + $Role + ' strictness=' + $Strictness + ' lang=' + $script:LangUsed)
  if ($FixturePath) { Write-Output ('fixture=' + $FixturePath + ' noNative=' + $script:NoNative) }
  if ($script:CollectorFaults.Count -gt 0) { Write-Output ('COLLECTOR FAULT: ' + (@($script:CollectorFaults) -join '; ')) }
  Write-Output ''
  foreach ($o in $checksOut) {
    Write-Output ('[' + $o.verdict.ToUpper() + '] ' + $o.id + ' (' + $o.role + ') - ' + $o.title)
    Write-Output ('    ' + $o.reason)
    if ($o.remediation) {
      Write-Output ('    fix: ' + $o.remediation.action)
      if ($o.remediation.command) { Write-Output ('    cmd: ' + $o.remediation.command) }
      if ($o.remediation.rollback) { Write-Output ('    rollback: ' + $o.remediation.rollback) }
    }
    if ($o.manualReview) { Write-Output ('    manual: ' + $o.manualQuestion) }
    if ($ShowRaw) { Write-Output ('    raw: ' + ($o.raw | ConvertTo-Json -Compress -Depth 8)) }
  }
  Write-Output ''
  Write-Output ('summary: total=' + $checksOut.Count + ' pass=' + $nPass + ' degraded=' + $nDeg + ' blocked=' + $nBlk + ' unknown=' + $nUnk)
  Write-Output ('overall: ' + $verdictOverall + ' -> exit ' + $exitCode + '  (' + $report.summary.exitMeaning + ')')
  Write-Output 'read-only: yes (no system configuration was modified; the pre/post wildcard-listener diff is reported as NO_NEW_WILDCARD_LISTENER)'
}

exit $exitCode
