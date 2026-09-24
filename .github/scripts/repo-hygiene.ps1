<#
  repo-hygiene.ps1 - release-set hygiene gate for remote-tailnet-guard (repository layer)

  LAST UPDATED  : 2026-09-24 (task t44 - plugin/ (the persistent plugin package) joined the release
                  set, so the shipped package is scanned by default too; task t39 - tools/ joined the
                  release set, so the optional write component is scanned by default too; task t24
                  made panel/ a default root)
  AUTHOR        : team remote-tailnet-guard-2 (member "packager", tasks t12 + t24 + t39)
  RUNS ON       : Windows PowerShell 5.1 (powershell.exe). No module, no network, no node.

  WHAT IT PROVES (release set = what a clone of the published repository contains:
    src/, i18n/, tests/, panel/, tools/, plugin/, docs/collect.md, docs/install/,
    docs/threat-model.md, SECURITY.md, LICENSE, README.md, README.en.md, CHANGELOG.md,
    CONTRIBUTING.md, .gitignore, .editorconfig, .github/**. The plugin's other half - the
    prerequisite checker, its manifest and both panel halves - the uninstaller and the
    persistent plugin package therefore sit inside the scanned surface, not beside it):
    1. blocked identifiers     : 0 hits for the real tailnet addresses / host names / user
                                 paths of the machines this project was developed on
    2. private / node suffixes : 0 hits for the private /24 prefixes held in the blocklist and
                                 for a ULA node address outside the documented prefix
    3. credential VALUE shapes : 0 hits (a secret with an actual value: tskey-*, a JWT, or
                                 "token = <12+ chars of value>"); see 4 for the word inventory
    4. credential word list    : reported, NOT fatal - the five words occur as field names,
                                 as the *declaration of what is never read*, and as test
                                 fixture vocabulary. Only a value shape fails the gate.
    5. allow-listed tokens     : constants and sanitized placeholders are classified as
                                 ALLOWED by token, and any token that matches no rule is
                                 reported as UNCLASSIFIED and fails (no silent pass)
    6. encodings               : .md/.json/.js/.yml/.gitignore/.editorconfig/LICENSE carry no
                                 BOM and decode as strict UTF-8; *.ps1 follows the two-branch
                                 rule from .editorconfig (ASCII => no BOM, non-ASCII => BOM).
                                 Line endings: LF is the convention; the two captured-output
                                 fixtures under tests/fixtures/ keep CRLF (the tool emitted it),
                                 and any OTHER CRLF file is reported as a note - add
                                 -StrictLineEndings to make it blocking instead.
    7. binary products         : no *.exe/.dll/.msi/.zip/... and no NUL byte anywhere
    8. forbidden runtime ref   : 0 *code* references to the removed client-runtime package.
                                 A mention inside *.md is reported as DOCUMENTED and does not
                                 fail: the docs quote the ban and the check command on purpose.
    9. internal material       : every internal doc is listed in .gitignore
   10. release-set docs        : the document markers README/CHANGELOG/LICENSE must carry
                                 (compared with whitespace runs collapsed, so a marker phrase
                                 may wrap across two lines in Markdown)
   11. license finality        : README/CHANGELOG/LICENSE state the MIT license and the confirmed
                                 copyright line, and contain NONE of the provisional wordings
                                 ("pending", "proposed default", the Chinese equivalent)
   12. repository name         : stated exactly once in README/CHANGELOG/CONTRIBUTING, so a
                                 rename is one edit per file

  WHY THE BLOCKED LITERALS ARE ASSEMBLED FROM FRAGMENTS
    This file is itself inside the release set. If it contained a blocked identifier as
    literal text, scanning the release set would report the gate as a violation and the
    report could never reach 0. Every blocked literal is therefore built from string parts
    at run time (and [regex]::Escape()d); grep for the fragments below to audit the list.

  EXIT CODE
    0 = the release set is clean
    1 = at least one blocking finding (identifiers, credential value, encoding, binary,
        forbidden reference, internal-material or document marker)
    2 = the gate itself could not run (bad -ScanRoot, unreadable file)

  COMMANDS USED WHILE BUILDING THIS REVISION (all read-only; -SelfTest writes only under
  %TEMP% and removes what it created):
    powershell -NoProfile -ExecutionPolicy Bypass -File .github/scripts/repo-hygiene.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File .github/scripts/repo-hygiene.ps1 -SelfTest
    powershell -NoProfile -ExecutionPolicy Bypass -File .github/scripts/repo-hygiene.ps1 -Json
    powershell -NoProfile -ExecutionPolicy Bypass -File .github/scripts/repo-hygiene.ps1 -ScanRoot <dir>
#>
[CmdletBinding()]
param(
  # Scan a different tree (used by -SelfTest and to prove the gate turns green once a
  # pending fix lands). Default: the repository this script lives in.
  [string]$ScanRoot = '',
  # Scan extra roots on top of the release set (panel/ is already a default root since t24;
  # an extra root is only for an ad-hoc directory). The default scope is exactly the release
  # set; the report prints the composition either way.
  [string[]]$ExtraRoots = @(),
  # Positive/negative control: plant every violation class in %TEMP% and assert the gate
  # reports each one, then plant a clean tree and assert 0 findings.
  [switch]$SelfTest,
  # Keep the %TEMP% tree created by -SelfTest (default: it is removed).
  [switch]$KeepTemp,
  # Promote a CRLF line ending (outside the documented fixture exception) to a blocking
  # failure. Default: it is reported as a note, because one documentation file outside this
  # task's scope is still CRLF.
  [switch]$StrictLineEndings,
  # Emit the machine-readable summary as the last stdout line.
  [switch]$Json
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# 0. constants, release set, pattern tables
# ---------------------------------------------------------------------------
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRootDefault = Split-Path -Parent (Split-Path -Parent $ScriptDir)

# The release set: exactly what a published clone contains. panel/ is a member (the plugin's
# prerequisite checker and both panel halves ship with the repository), so is tools/ (the
# uninstaller - the one optional write component) and so is plugin/ (the persistent plugin
# package: package.json, cordis.patch.yml, lib/ and its client twin), so all three are scanned
# by default and must not be hidden behind an -ExtraRoots argument.
$PublishRoots = @(
  'src', 'i18n', 'tests', 'panel', 'tools', 'plugin',
  'docs\collect.md', 'docs\install', 'docs\threat-model.md',
  'SECURITY.md', 'LICENSE', 'README.md', 'README.en.md', 'CHANGELOG.md', 'CONTRIBUTING.md',
  '.gitignore', '.editorconfig', '.gitattributes', '.github'
)

# Internal material: present in the working tree, excluded from the repository.
$InternalMaterial = @(
  'docs\baseline.md', 'docs\matrix.md', 'docs\harness-contract.md',
  'docs\defensive-spec.md', 'docs\security-review.md',
  'docs\security-review-r2.md', 'docs\security-review-r3.md', 'docs\verify-t7.md'
)

$BS = [char]92   # backslash, kept out of literals on purpose (see header)

# Blocked identifiers, assembled from fragments so this file never contains one.
$BlockedFragments = @(
  ('100.' + '72.' + '9.' + '124'),
  ('100.' + '79.' + '243.' + '35'),
  ('26.' + '134.' + '188.' + '244'),
  ('DESKTOP-' + 'BOK9S0Q'),
  ('LAPTOP-' + 'DQKM4AAT'),
  ('C:' + $BS + 'Users' + $BS + 'admin'),
  ('D:' + $BS + 'DSH' + $BS + 'DSH ' + 'Desktop'),
  ('10.' + '69.'),
  ('10.' + '113.'),
  ('10.' + '169.')
)
$RxBlocked = (($BlockedFragments | ForEach-Object { [regex]::Escape($_) }) -join '|')

# The documented ULA prefix, again assembled so the literal never appears here.
$UlaPrefix = 'fd7a:115c:a1e0' + ':' + ':'
$RxUlaBroad = [regex]::Escape($UlaPrefix) + '[0-9a-f:/]*'
$RxUlaBlocked = [regex]::Escape($UlaPrefix) + '(?!1000)(?!/48)'

# Broad token scans, so the report can classify hits instead of only counting them.
$RxBroadIp = '\b100\.\d{1,3}\.\d{1,3}\.\d{1,3}\b|\b10\.\d{1,3}\.\d{1,3}\.\d{1,3}\b|' + $RxUlaBroad

# Allow list (each entry documents *why* the token may be published).
#
# PROVENANCE OF THIS LIST (single shared source of truth - do not restate it elsewhere):
#   * docs/defensive-spec.md section 2.1/2.3 pattern table (internal design doc), and
#   * the review ruling of 2026-09-24 (task t21 round 3): approved placeholders may appear
#     in prose and in fixtures. Approved: product constants (0.0.0.0, 127.0.0.1, 100.64.0.0/10,
#     the documented ULA prefix + /48, netmasks), the RFC 5737 documentation ranges, the
#     RFC 3849 prefix, and the sanitized placeholders this project already uses.
#   CONTRIBUTING.md section 4 states the same rule for contributors and points here; if the two
#   ever disagree, this table wins.
# A token that matches no rule is reported as UNCLASSIFIED and fails the gate - there is no
# silent pass and no per-file exemption.
$AllowRules = @(
  @{ label = 'product constant: unspecified / loopback bind address'; rx = '^(0\.0\.0\.0|127\.0\.0\.1|\[::\]|::1)$' },
  @{ label = 'product constant: CGNAT (tailnet) range';              rx = '^100\.64\.0\.0(/10)?$' },
  @{ label = 'product constant: documented ULA prefix';              rx = '^' + [regex]::Escape($UlaPrefix) + '/48$' },
  @{ label = 'product constant: documented example node suffix';     rx = '^' + [regex]::Escape($UlaPrefix) + '1000(:[0-9a-f]*)?$' },
  @{ label = 'netmask';                                             rx = '^255(\.\d{1,3}){3}$' },
  @{ label = 'RFC 5737 documentation range';                        rx = '^(192\.0\.2|198\.51\.100|203\.0\.113)\.' },
  @{ label = 'RFC 3849 documentation prefix';                       rx = '^2001:db8' },
  @{ label = 'sanitized placeholder used by this repository';       rx = '^100\.64\.0\.(11|12)$' },
  @{ label = 'sanitized placeholder used by this repository';       rx = '^10\.(20|21|22)\.' },
  @{ label = 'sanitized placeholder used by this repository';       rx = '^<[A-Za-z_]+>$' }
)

# Credential value shapes: a secret WITH a value. Fragmented for the same reason.
$RxCredValue = '(?i)(tskey-[A-Za-z0-9]{6,}|eyJ[A-Za-z0-9._-]{20,}|(?<![A-Za-z0-9_])(token|secret|password|passwd|api[_-]?key|cookie)["'']?\s*[:=]\s*["'']?[A-Za-z0-9+/_.-]{12,})'
$RxCredWord = '(?i)(token|secret|password|cookie|apikey)'

# Forbidden runtime reference (the package was removed from the 0.1.5 line; a client entry
# that requires it turns the whole GUI into "Failed to load plugins").
$ForbiddenRef = '@' + 'deepseek-ai/' + 'dsh-client-' + 'runtime'

$BinaryExtensions = @('.exe', '.dll', '.msi', '.msix', '.zip', '.7z', '.cab', '.pdb', '.nupkg', '.png', '.jpg', '.jpeg', '.gif', '.pdf', '.bin', '.ico')
$CodeExtensions = @('.js', '.mjs', '.cjs', '.ps1', '.psm1', '.json', '.yml', '.yaml', '.py')
$NoBomExtensions = @('.md', '.json', '.js', '.yml', '.yaml', '.txt')
$NoBomNames = @('.gitignore', '.editorconfig', 'LICENSE')
$PsExtensions = @('.ps1', '.psm1')

# Document markers the release layer must carry (ASCII only, so they can be checked here).
# The license is FINAL (t24): the marker is the license name itself, and the checks further down
# also assert that no provisional wording survives anywhere in the license statements.
$InternalMaterialSentence = 'Internal analysis and review material does not ship with the repository'
$LicenseHolder = 'Copyright (c) 2026 KomeijiHonnouKai'
$DocMarkers = @(
  @{ file = 'README.md';    marker = $InternalMaterialSentence; why = 'README must state that internal material is not published' },
  @{ file = 'README.md';    marker = 'SECURITY.md';             why = 'README must link the security policy' },
  @{ file = 'README.md';    marker = 'MIT';                     why = 'README must state the MIT license' },
  @{ file = 'README.md';    marker = 'read-only and report-only'; why = 'README must state the plugin stance: read-only, report-only, no firewall/profile/plugin change, no DSH restart' },
  @{ file = 'CHANGELOG.md'; marker = 'MIT';                     why = 'CHANGELOG must state the MIT license' },
  @{ file = 'LICENSE';      marker = 'MIT License';             why = 'LICENSE must carry the standard MIT text' }
)

# License finality (t24): the three files that state the license may not keep provisional wording.
# The Chinese phrase is assembled from [char] codes so this script stays pure ASCII.
$ForbiddenDocWording = @(
  'pending',
  'proposed default',
  ([string][char]0x5F85 + [char]0x786E + [char]0x8BA4)
)
$LicenseWordingFiles = @('README.md', 'CHANGELOG.md', 'LICENSE')

# Repository name (t24): stated exactly once per file, so a rename is a one-line edit each. The
# name is assembled from fragments for the same reason as the blocklist - the count check must not
# be able to count its own definition. Named for the FUNCTION (cross-network DSH link), not for a
# security property: the security posture belongs in the docs and in SECURITY.md, not in the name.
$RepoName = 'dsh-crossnet-' + 'link'
$RepoNameFiles = @('README.md', 'CHANGELOG.md', 'CONTRIBUTING.md')

# ---------------------------------------------------------------------------
# 1. helpers
# ---------------------------------------------------------------------------
function Get-PublishFiles {
  param([string]$Root, [string[]]$Roots)
  $out = New-Object System.Collections.ArrayList
  foreach ($r in $Roots) {
    $p = Join-Path $Root $r
    if (-not (Test-Path -LiteralPath $p)) { continue }
    $item = Get-Item -LiteralPath $p -Force
    if ($item.PSIsContainer) {
      foreach ($f in (Get-ChildItem -LiteralPath $p -Recurse -File -Force)) { [void]$out.Add($f) }
    } else {
      [void]$out.Add($item)
    }
  }
  return $out
}

function Get-FileText {
  param([string]$Path)
  $bytes = [IO.File]::ReadAllBytes($Path)
  $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
  $text = ''
  try {
    $strict = New-Object System.Text.UTF8Encoding($false, $true)
    $text = $strict.GetString($bytes)
    $validUtf8 = $true
  } catch {
    $validUtf8 = $false
    $text = [Text.Encoding]::GetEncoding(1252).GetString($bytes)
  }
  $nonAscii = 0
  foreach ($b in $bytes) { if ($b -gt 127) { $nonAscii++ } }
  $nul = $false
  foreach ($b in $bytes) { if ($b -eq 0) { $nul = $true; break } }
  $crlf = $false
  for ($i = 0; $i -lt ($bytes.Length - 1); $i++) { if ($bytes[$i] -eq 13 -and $bytes[$i + 1] -eq 10) { $crlf = $true; break } }
  return [pscustomobject]@{
    Bytes    = $bytes
    HasBom   = $hasBom
    Text     = $text
    ValidUtf8 = $validUtf8
    NonAscii = $nonAscii
    HasNul   = $nul
    HasCrlf  = $crlf
    Size     = $bytes.Length
  }
}

function Get-RelPath {
  param([string]$Root, [string]$Full)
  $r = $Root.TrimEnd($BS)
  if ($Full.StartsWith($r, [StringComparison]::OrdinalIgnoreCase)) {
    return $Full.Substring($r.Length).TrimStart($BS)
  }
  return $Full
}

function Classify-Token {
  param([string]$Token)
  if ($Token -match $RxBlocked) { return 'BLOCKED' }
  foreach ($rule in $AllowRules) { if ($Token -match $rule.rx) { return 'ALLOWED' } }
  if ($Token -match $RxUlaBlocked) { return 'BLOCKED' }
  return 'UNCLASSIFIED'
}

# ---------------------------------------------------------------------------
# 2. the scan engine (shared by the default run and by -SelfTest)
# ---------------------------------------------------------------------------
function Invoke-HygieneScan {
  param([string]$Root, [switch]$SkipDocMarkers, [string[]]$ExtraRoots = @(), [switch]$StrictLineEndings)

  if (-not (Test-Path -LiteralPath $Root)) { throw ('scan root does not exist: ' + $Root) }
  $Root = (Get-Item -LiteralPath $Root).FullName

  $roots = @($PublishRoots)
  if ($ExtraRoots.Count -gt 0) { $roots = @($roots + $ExtraRoots) }
  $files = Get-PublishFiles -Root $Root -Roots $roots
  $res = [pscustomobject]@{
    Root             = $Root
    Roots            = (($roots | Sort-Object) -join ', ')
    FileCount        = $files.Count
    BlockedHits      = (New-Object System.Collections.ArrayList)
    UlaHits          = (New-Object System.Collections.ArrayList)
    CredValueHits    = (New-Object System.Collections.ArrayList)
    WordInventory    = (New-Object System.Collections.ArrayList)
    TokenClass       = @{}
    EncodingFailures = (New-Object System.Collections.ArrayList)
    CrlfFiles        = (New-Object System.Collections.ArrayList)
    LineEndingNotes  = (New-Object System.Collections.ArrayList)
    BinaryFailures   = (New-Object System.Collections.ArrayList)
    ForbiddenHits    = (New-Object System.Collections.ArrayList)
    MissingIgnores   = (New-Object System.Collections.ArrayList)
    MissingMarkers   = (New-Object System.Collections.ArrayList)
    ExistingMarkers  = (New-Object System.Collections.ArrayList)
    EncSummary       = ''
    InternalSummary  = ''
  }

  foreach ($f in $files) {
    $rel = Get-RelPath -Root $Root -Full $f.FullName
    $info = Get-FileText -Path $f.FullName
    $ext = [IO.Path]::GetExtension($f.Name).ToLowerInvariant()
    $name = $f.Name

    # --- 1/2/5: identifiers, ULA and the token classification table
    foreach ($m in [regex]::Matches($info.Text, '\b100\.\d{1,3}\.\d{1,3}\.\d{1,3}\b|\b10\.\d{1,3}\.\d{1,3}\.\d{1,3}\b|' + $RxUlaBroad)) {
      $tok = $m.Value
      $cls = Classify-Token -Token $tok
      if (-not $res.TokenClass.ContainsKey($tok)) { $res.TokenClass[$tok] = @{ Class = $cls; Count = 0; Files = @{} } }
      $res.TokenClass[$tok].Count = $res.TokenClass[$tok].Count + 1
      if (-not $res.TokenClass[$tok].Files.ContainsKey($rel)) { $res.TokenClass[$tok].Files[$rel] = 0 }
      $res.TokenClass[$tok].Files[$rel] = $res.TokenClass[$tok].Files[$rel] + 1
      # A BLOCKED token is reported by the line-based identifier / ULA scan below, which also
      # carries the line number; this loop only builds the classification table.
    }

    # --- 1: blocked identifiers, line by line (raw, for the report)
    $lines = $info.Text -split "`r?`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
      $line = $lines[$i]
      $hit = [regex]::Match($line, $RxBlocked)
      if ($hit.Success) {
        [void]$res.BlockedHits.Add([pscustomobject]@{
          File = $rel; Line = ($i + 1); Match = $hit.Value; Text = $line.Trim()
        })
      }
      $hitU = [regex]::Match($line, $RxUlaBlocked)
      if ($hitU.Success) {
        [void]$res.UlaHits.Add([pscustomobject]@{ File = $rel; Line = ($i + 1); Token = $hitU.Value })
      }
      # --- 3/4: credential value shapes and the word inventory
      if ($line -match $RxCredWord) {
        $isValue = ($line -match $RxCredValue)
        [void]$res.WordInventory.Add([pscustomobject]@{
          File = $rel; Line = ($i + 1); Class = $(if ($isValue) { 'VALUE_SHAPE' } else { 'WORD_ONLY' }); Text = $line.Trim()
        })
        if ($isValue) {
          [void]$res.CredValueHits.Add([pscustomobject]@{ File = $rel; Line = ($i + 1); Text = $line.Trim() })
        }
      }
    }

    # --- 6: encodings and line endings
    # Line endings: convention is LF, with one accepted exception - the captured console-output
    # fixtures under tests/fixtures/, which keep CRLF because that is what the tool emitted.
    # Any other CRLF file is REPORTED (a note), not fatal by default: today one documentation
    # file outside this task's scope is still CRLF. Pass -StrictLineEndings to make a CRLF file
    # a blocking failure once that is fixed.
    if ($info.HasCrlf) {
      [void]$res.CrlfFiles.Add($rel)
      $relPosix = $rel.Replace($BS, '/')
      if ($relPosix -notlike 'tests/fixtures/*') {
        [void]$res.LineEndingNotes.Add([pscustomobject]@{ File = $rel; Why = 'CRLF line endings (convention is LF; only tests/fixtures/*.json is allowed to keep CRLF)' })
        if ($StrictLineEndings) {
          [void]$res.EncodingFailures.Add([pscustomobject]@{ File = $rel; Why = 'CRLF line endings (-StrictLineEndings)' })
        }
      }
    }
    if ($BinaryExtensions -contains $ext) {
      [void]$res.BinaryFailures.Add([pscustomobject]@{ File = $rel; Why = ('binary product extension ' + $ext) })
    }
    if ($info.HasNul) {
      [void]$res.BinaryFailures.Add([pscustomobject]@{ File = $rel; Why = 'contains a NUL byte (not a text file)' })
    }
    if ($PsExtensions -contains $ext) {
      if ($info.NonAscii -gt 0 -and -not $info.HasBom) {
        [void]$res.EncodingFailures.Add([pscustomobject]@{ File = $rel; Why = 'non-ASCII .ps1 without a UTF-8 BOM (PowerShell 5.1 would read it as ANSI)' })
      }
      if ($info.NonAscii -eq 0 -and $info.HasBom) {
        [void]$res.EncodingFailures.Add([pscustomobject]@{ File = $rel; Why = 'ASCII-only .ps1 carries a BOM (must ship BOM-less)' })
      }
      if (-not $info.ValidUtf8) {
        [void]$res.EncodingFailures.Add([pscustomobject]@{ File = $rel; Why = 'not valid UTF-8' })
      }
    } elseif (($NoBomExtensions -contains $ext) -or ($NoBomNames -contains $name)) {
      if ($info.HasBom) {
        [void]$res.EncodingFailures.Add([pscustomobject]@{ File = $rel; Why = 'UTF-8 BOM present (must be BOM-less)' })
      }
      if (-not $info.ValidUtf8) {
        [void]$res.EncodingFailures.Add([pscustomobject]@{ File = $rel; Why = 'not valid UTF-8' })
      }
    }

    # --- 8: forbidden runtime reference (blocking in code, reported in docs)
    if ($info.Text.IndexOf($ForbiddenRef, [StringComparison]::Ordinal) -ge 0) {
      if ($CodeExtensions -contains $ext) {
        [void]$res.ForbiddenHits.Add([pscustomobject]@{ File = $rel; Class = 'CODE_REFERENCE'; Why = ('code reference to the removed package ' + $ForbiddenRef) })
      } else {
        [void]$res.ForbiddenHits.Add([pscustomobject]@{ File = $rel; Class = 'DOCUMENTED'; Why = 'the docs quote the ban and the check command on purpose' })
      }
    }
  }

  # --- 6b: encoding summary
  $mdCount = ($files | Where-Object { $_.Extension -eq '.md' }).Count
  $psCount = ($files | Where-Object { $PsExtensions -contains $_.Extension.ToLowerInvariant() }).Count
  $res.EncSummary = ('md=' + $mdCount + ' (BOM-less), ps1=' + $psCount + ' (ASCII-only + BOM-less), crlf=' + $res.CrlfFiles.Count + ' file(s)')

  # --- 9: internal material must be excluded by .gitignore
  $ignoreFile = Join-Path $Root '.gitignore'
  if (Test-Path -LiteralPath $ignoreFile) {
    $ignoreText = (Get-Content -LiteralPath $ignoreFile -Raw -Encoding UTF8)
    $listed = New-Object System.Collections.ArrayList
    foreach ($doc in $InternalMaterial) {
      $norm = $doc.Replace($BS, '/')
      if ($ignoreText.IndexOf($norm, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
        [void]$res.MissingIgnores.Add([pscustomobject]@{ File = $doc; Why = 'internal material is not listed in .gitignore' })
      } else {
        [void]$listed.Add($norm)
      }
    }
    $res.InternalSummary = (($listed | Sort-Object) -join ', ')
  } else {
    [void]$res.MissingIgnores.Add([pscustomobject]@{ File = '.gitignore'; Why = '.gitignore is missing' })
  }

  # --- 10: document markers
  if (-not $SkipDocMarkers) {
    foreach ($m in $DocMarkers) {
      $p = Join-Path $Root $m.file
      if (-not (Test-Path -LiteralPath $p)) {
        [void]$res.MissingMarkers.Add([pscustomobject]@{ File = $m.file; Marker = $m.marker; Why = ($m.file + ' is missing') })
        continue
      }
      $t = Get-Content -LiteralPath $p -Raw -Encoding UTF8
      $flat = ($t -replace '\s+', ' ')
      $markerFlat = ($m.marker -replace '\s+', ' ')
      if ($flat.IndexOf($markerFlat, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
        [void]$res.MissingMarkers.Add([pscustomobject]@{ File = $m.file; Marker = $m.marker; Why = $m.why })
      } else {
        [void]$res.ExistingMarkers.Add([pscustomobject]@{ File = $m.file; Marker = $m.marker })
      }
    }

    # --- 11: license finality (t24): no provisional wording may survive
    foreach ($file in $LicenseWordingFiles) {
      $lic = Join-Path $Root $file
      if (-not (Test-Path -LiteralPath $lic)) { continue }
      $flags = ((Get-Content -LiteralPath $lic -Raw -Encoding UTF8) -replace '\s+', ' ')
      foreach ($word in $ForbiddenDocWording) {
        if ($flags.IndexOf($word, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
          [void]$res.MissingMarkers.Add([pscustomobject]@{ File = $file; Marker = ('no "' + $word + '"'); Why = 'the license is final: provisional wording must not remain in a license statement' })
        } else {
          [void]$res.ExistingMarkers.Add([pscustomobject]@{ File = $file; Marker = ('no "' + $word + '"') })
        }
      }
      if ($file -eq 'LICENSE' -and $flags.IndexOf($LicenseHolder, [StringComparison]::Ordinal) -lt 0) {
        [void]$res.MissingMarkers.Add([pscustomobject]@{ File = 'LICENSE'; Marker = $LicenseHolder; Why = 'LICENSE must carry the confirmed copyright line' })
      } elseif ($file -eq 'LICENSE') {
        [void]$res.ExistingMarkers.Add([pscustomobject]@{ File = 'LICENSE'; Marker = $LicenseHolder })
      }
    }

    # --- 12: repository name appears exactly once per file (t24)
    foreach ($file in $RepoNameFiles) {
      $p = Join-Path $Root $file
      if (-not (Test-Path -LiteralPath $p)) { continue }
      $text = Get-Content -LiteralPath $p -Raw -Encoding UTF8
      $nameCount = ([regex]::Matches($text, [regex]::Escape($RepoName))).Count
      if ($nameCount -ne 1) {
        [void]$res.MissingMarkers.Add([pscustomobject]@{ File = $file; Marker = ($RepoName + ' exactly once'); Why = ('measured ' + $nameCount + ' occurrence(s): the repository name must appear exactly once per file so a rename stays a one-line edit') })
      } else {
        [void]$res.ExistingMarkers.Add([pscustomobject]@{ File = $file; Marker = ($RepoName + ' exactly once') })
      }
    }
  }

  return $res
}

function Get-UnclassifiedTokens {
  param($Res)
  # A token that no allow rule explains. The header promises this fails the gate ("no silent
  # pass"); measured while adding panel/ to the default roots, the promise was not kept - the
  # report printed the UNCLASSIFIED row but Get-BlockingCount ignored it. Fixed here, and the
  # self-test now proves an unapproved token alone fails.
  return @($Res.TokenClass.GetEnumerator() | Where-Object { $_.Value.Class -eq 'UNCLASSIFIED' })
}

function Get-BlockingCount {
  param($Res)
  $codeRefs = @($Res.ForbiddenHits | Where-Object { $_.Class -eq 'CODE_REFERENCE' }).Count
  $unclassified = @(Get-UnclassifiedTokens -Res $Res).Count
  return ($Res.BlockedHits.Count + $Res.UlaHits.Count + $Res.CredValueHits.Count + $Res.EncodingFailures.Count +
          $Res.BinaryFailures.Count + $codeRefs + $Res.MissingIgnores.Count + $Res.MissingMarkers.Count + $unclassified)
}

# ---------------------------------------------------------------------------
# 3. reporting
# ---------------------------------------------------------------------------
function Show-Report {
  param($Res)
  $pad = '  '
  Write-Host ''
  Write-Host 'remote-tailnet-guard - release-set hygiene gate (t12 + t24: panel/ is a default root)'
  Write-Host ('scan root : ' + $Res.Root)
  Write-Host ('roots     : ' + $Res.Roots)
  Write-Host ('files     : ' + $Res.FileCount + ' under those roots (release set by default)')
  Write-Host ''

  $blocked = $Res.BlockedHits.Count + $Res.UlaHits.Count
  Write-Host ('[1/8] blocked identifiers / private suffixes ... ' + $blocked + ' hit(s) ' + $(if ($blocked -eq 0) { '-> OK' } else { '-> FAIL' }))
  foreach ($h in $Res.BlockedHits) {
    Write-Host ($pad + $h.File + ':' + $h.Line + '  matched "' + $h.Match + '"')
    Write-Host ($pad + '    ' + $h.Text)
  }
  foreach ($h in $Res.UlaHits) {
    Write-Host ($pad + $h.File + ':' + $h.Line + '  matched "' + $h.Token + '" (private ULA node suffix)')
  }

  $cv = $Res.CredValueHits.Count
  Write-Host ('[2/8] credential VALUE shapes .............. ' + $cv + ' hit(s) ' + $(if ($cv -eq 0) { '-> OK' } else { '-> FAIL' }))
  foreach ($h in $Res.CredValueHits) { Write-Host ($pad + $h.File + ':' + $h.Line + '  ' + $h.Text) }

  $words = $Res.WordInventory.Count
  $wordFiles = ($Res.WordInventory | Group-Object File).Count
  Write-Host ('[3/8] credential word inventory ............ ' + $words + ' hit(s) in ' + $wordFiles + ' file(s) -> informational')
  Write-Host ($pad + 'rule: a hit fails only when it carries a value (see [2/8]); a bare word is a')
  Write-Host ($pad + 'field name, the declaration of what is never read, or fixture vocabulary.')
  $Res.WordInventory | Group-Object File | Sort-Object Count -Descending | Select-Object -First 15 | ForEach-Object {
    Write-Host ($pad + '{0,4}  {1}' -f $_.Count, $_.Name)
  }

  $cls = $Res.TokenClass.GetEnumerator() | Sort-Object { $_.Value.Class }, { - $_.Value.Count }
  $unclassified = @(Get-UnclassifiedTokens -Res $Res)
  Write-Host ('[4/8] allow-list classification ........... ' + @($cls).Count + ' distinct token(s), ' + $unclassified.Count + ' unclassified ' + $(if ($unclassified.Count -eq 0) { '-> OK' } else { '-> FAIL (no silent pass)' }))
  foreach ($e in $cls) {
    $files = ($e.Value.Files.Keys | Sort-Object) -join ', '
    Write-Host ($pad + '{0,-24} {1,-24} x{2,-4} {3}' -f $e.Key, $e.Value.Class, $e.Value.Count, $files)
  }

  $enc = $Res.EncodingFailures.Count
  Write-Host ('[5/8] encodings ............................ ' + $enc + ' violation(s) ' + $(if ($enc -eq 0) { '-> OK' } else { '-> FAIL' }) + '  [' + $Res.EncSummary + ']')
  foreach ($h in $Res.EncodingFailures) { Write-Host ($pad + $h.File + '  ' + $h.Why) }
  foreach ($h in $Res.LineEndingNotes) { Write-Host ($pad + '[note] ' + $h.File + '  ' + $h.Why) }

  $bin = $Res.BinaryFailures.Count
  Write-Host ('[6/8] binary products ...................... ' + $bin + ' hit(s) ' + $(if ($bin -eq 0) { '-> OK' } else { '-> FAIL' }))
  foreach ($h in $Res.BinaryFailures) { Write-Host ($pad + $h.File + '  ' + $h.Why) }

  $forbCode = @($Res.ForbiddenHits | Where-Object { $_.Class -eq 'CODE_REFERENCE' }).Count
  $forbDoc = @($Res.ForbiddenHits | Where-Object { $_.Class -eq 'DOCUMENTED' }).Count
  Write-Host ('[7/8] forbidden runtime reference .......... code=' + $forbCode + ' doc=' + $forbDoc + ' ' + $(if ($forbCode -eq 0) { '-> OK' } else { '-> FAIL' }))
  foreach ($h in $Res.ForbiddenHits) { Write-Host ($pad + '[' + $h.Class + '] ' + $h.File + '  ' + $h.Why) }

  $mis = $Res.MissingIgnores.Count + $Res.MissingMarkers.Count
  Write-Host ('[8/8] internal material + doc markers ...... ' + $mis + ' problem(s) ' + $(if ($mis -eq 0) { '-> OK' } else { '-> FAIL' }))
  Write-Host ($pad + 'internal docs excluded by .gitignore: ' + $Res.InternalSummary)
  foreach ($h in $Res.MissingIgnores) { Write-Host ($pad + $h.File + '  ' + $h.Why) }
  foreach ($h in $Res.MissingMarkers) { Write-Host ($pad + $h.File + '  marker not found: "' + $h.Marker + '" (' + $h.Why + ')') }

  $blocking = Get-BlockingCount -Res $Res
  Write-Host ''
  Write-Host ('verdict: ' + $(if ($blocking -eq 0) { 'CLEAN' } else { 'FAIL' }) + ' (' + $blocking + ' blocking finding(s))')
  return $blocking
}

# ---------------------------------------------------------------------------
# 4. -SelfTest: positive and negative controls
# ---------------------------------------------------------------------------
function Invoke-SelfTest {
  Write-Host 'remote-tailnet-guard - hygiene gate self-test (positive/negative controls)'
  $tmpRoot = Join-Path $env:TEMP ('rtg-hygiene-selftest-' + $PID)
  if (Test-Path -LiteralPath $tmpRoot) { Remove-Item -LiteralPath $tmpRoot -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null
  $checks = New-Object System.Collections.ArrayList
  try {
    # ---- dirty tree: one file per violation class
    $dirty = Join-Path $tmpRoot 'dirty'
    New-Item -ItemType Directory -Force -Path (Join-Path $dirty 'src') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $dirty 'tests') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $dirty '.github') | Out-Null

    $enc = New-Object System.Text.UTF8Encoding($false)
    # NOTE (measured trap): inside an @( ... ) array literal PowerShell treats an
    # unparenthesised "a" + $b + "c" element as several elements, which silently split the
    # fixture text across lines while this self-test was being written. Every concatenated
    # element below is therefore wrapped in parentheses.
    # blocked identifier (real address shape) + user path shape
    $ulas = $UlaPrefix
    # The approved sanitized placeholders are assembled from fragments for the same reason the
    # blocklist is: this file sits inside the scanned surface, and a literal placeholder here is
    # reported by the very scan this control exercises (measured: the suite case
    # scan-plugin-script-surface flagged line 514 of this file for exactly that).
    $phA = '100.' + '64.' + '0.' + '11'
    $phB = '100.' + '64.' + '0.' + '12'
    $phC = '10.' + '20.x ' + '10.' + '21.x ' + '10.' + '22.x'
    $phD = '10.' + '20.' + '182.' + '16'
    $phE = '10.' + '22.' + '236.' + '210'
    New-Item -ItemType Directory -Force -Path (Join-Path $dirty 'docs') | Out-Null
    [IO.File]::WriteAllText((Join-Path $dirty 'docs\collect.md'), ('peer = ' + $BlockedFragments[0] + "`n"), $enc)
    [IO.File]::WriteAllText((Join-Path $dirty 'docs\threat-model.md'), ('path = ' + $BlockedFragments[5] + "\`n"), $enc)
    # credential value shape (assembled, so this script stays clean)
    [IO.File]::WriteAllText((Join-Path $dirty 'tests\x.json'), ('{"' + 'token' + '": "' + 'ABCDEFGHIJKLMNOPQRSTUVWX' + '"}'), $enc)
    # private ULA node suffix (a node id that is NOT the documented example suffix: the
    # ::/48 prefix form and a ::1000:* example are ALLOWED, so planting ::1000:7 here would
    # assert the wrong thing - measured while this control was being written)
    [IO.File]::WriteAllText((Join-Path $dirty 'tests\y.json'), ($UlaPrefix + '4242:1'), $enc)
    # non-ASCII .ps1 without BOM
    [IO.File]::WriteAllBytes((Join-Path $dirty 'src\bad.ps1'), [byte[]](0x23, 0x20, 0xC3, 0xA9, 0x0A))
    # binary product
    [IO.File]::WriteAllBytes((Join-Path $dirty '.github\tool.exe'), [byte[]](0x4D, 0x5A, 0x00, 0x01))
    # forbidden runtime reference
    [IO.File]::WriteAllText((Join-Path $dirty 'src\host-half.js'), ('require("' + $ForbiddenRef + '")'), $enc)
    # .gitignore without the internal-material list
    [IO.File]::WriteAllText((Join-Path $dirty '.gitignore'), "# nothing here`n", $enc)

    $r = Invoke-HygieneScan -Root $dirty -SkipDocMarkers
    [void]$checks.Add(@{ name = 'blocked identifier is caught';        ok = ($r.BlockedHits.Count -ge 1) })
    [void]$checks.Add(@{ name = 'credential value shape is caught';    ok = ($r.CredValueHits.Count -ge 1) })
    [void]$checks.Add(@{ name = 'private ULA node suffix (non-1000 node id) is caught'; ok = ($r.UlaHits.Count -ge 1) })
    [void]$checks.Add(@{ name = 'non-ASCII .ps1 without BOM is caught'; ok = ($r.EncodingFailures.Count -ge 1) })
    [void]$checks.Add(@{ name = 'binary product is caught';            ok = ($r.BinaryFailures.Count -ge 1) })
    [void]$checks.Add(@{ name = 'forbidden reference is caught';       ok = ($r.ForbiddenHits.Count -ge 1) })
    [void]$checks.Add(@{ name = 'missing internal-material ignore is caught'; ok = ($r.MissingIgnores.Count -ge 1) })

    # ---- clean tree: allow-listed constants and placeholders only
    $clean = Join-Path $tmpRoot 'clean'
    New-Item -ItemType Directory -Force -Path (Join-Path $clean 'docs') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $clean 'src') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $clean 'tests') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $clean '.github') | Out-Null
    $cleanBody = @(
      ('0.0.0.0 and 127.0.0.1 are product constants'),
      ('the tailnet range is 100.64.0.0/10 and the documented ULA prefix is ' + $ulas + '/48'),
      ('an example node is ' + $ulas + '1000:1'),
      ('sanitized placeholders: ' + $phA + ' ' + $phB + ' ' + $phC + ' ' + $phD + ' ' + $phE),
      ('example node prefixes: ' + $ulas + '1000 and ' + $ulas + '1000: and ' + $ulas + '1000:1'),
      ('RFC 5737 documentation range 192.0.2.20 and 198.51.100.11'),
      ('netmask 255.255.0.0'),
      ('the user profile is <DSH_HOME> and the install root is <DSH_APP>'),
      ('this text only says that no token, secret, password, cookie or apikey is read')
    ) -join "`n"
    [IO.File]::WriteAllText((Join-Path $clean 'docs\collect.md'), $cleanBody, $enc)
    [IO.File]::WriteAllText((Join-Path $clean 'docs\threat-model.md'), $cleanBody, $enc)
    [IO.File]::WriteAllText((Join-Path $clean 'src\collect.ps1'), ('# ASCII only' + "`n"), $enc)
    [IO.File]::WriteAllText((Join-Path $clean 'tests\en.json'), $cleanBody, $enc)
    $ignoreBody = ($InternalMaterial | ForEach-Object { $_.Replace($BS, '/') }) -join "`n"
    [IO.File]::WriteAllText((Join-Path $clean '.gitignore'), $ignoreBody, $enc)

    $r2 = Invoke-HygieneScan -Root $clean -SkipDocMarkers
    [void]$checks.Add(@{ name = 'clean tree: no blocking finding';     ok = ((Get-BlockingCount -Res $r2) -eq 0) })
    $unclassified = @($r2.TokenClass.GetEnumerator() | Where-Object { $_.Value.Class -eq 'UNCLASSIFIED' })
    [void]$checks.Add(@{ name = 'allow list has no unclassified token'; ok = ($unclassified.Count -eq 0) })
    [void]$checks.Add(@{ name = 'allow list does classify tokens';      ok = (@($r2.TokenClass.GetEnumerator()).Count -ge 5) })
    [void]$checks.Add(@{ name = 'word inventory is not fatal';          ok = ($r2.WordInventory.Count -ge 1 -and $r2.CredValueHits.Count -eq 0) })

    # ---- unclassified-only tree: an unapproved token ALONE must fail the gate
    # Same reason for the fragments as above. This control exists because the very first run
    # with panel/ in the default roots printed an UNCLASSIFIED row while still answering
    # "CLEAN" - the documented "no silent pass" was not enforced.
    $unclass = Join-Path $tmpRoot 'unclass'
    New-Item -ItemType Directory -Force -Path (Join-Path $unclass 'tests') | Out-Null
    $unapproved = '100.' + '99.' + '1.' + '1'
    [IO.File]::WriteAllText((Join-Path $unclass 'tests\u.json'), ('peer = ' + $unapproved + "`n"), $enc)
    [IO.File]::WriteAllText((Join-Path $unclass '.gitignore'), $ignoreBody, $enc)
    $r3 = Invoke-HygieneScan -Root $unclass -SkipDocMarkers
    [void]$checks.Add(@{ name = 'unapproved token is classified UNCLASSIFIED'; ok = (@(Get-UnclassifiedTokens -Res $r3).Count -eq 1) })
    [void]$checks.Add(@{ name = 'unapproved token alone fails the gate (blocking = 1)'; ok = ((Get-BlockingCount -Res $r3) -eq 1) })

    # ---- documentation trees: final license wording + repository-name count (t24 items 5/6)
    # The real files carry these properties today; these two trees prove the checks still notice
    # when they stop being true, instead of reporting a green run forever.
    $mitText = 'MIT License' + "`n`n" + $LicenseHolder + "`n`nPermission is hereby granted, free of charge.`n"
    $goodDocs = Join-Path $tmpRoot 'docs-ok'
    New-Item -ItemType Directory -Force -Path $goodDocs | Out-Null
    [IO.File]::WriteAllText((Join-Path $goodDocs '.gitignore'), $ignoreBody, $enc)
    [IO.File]::WriteAllText((Join-Path $goodDocs 'LICENSE'), $mitText, $enc)
    [IO.File]::WriteAllText((Join-Path $goodDocs 'README.md'), ('MIT. SECURITY.md. read-only and report-only. ' + $InternalMaterialSentence + '. clone: https://github.com/<OWNER>/' + $RepoName + "`n"), $enc)
    [IO.File]::WriteAllText((Join-Path $goodDocs 'CHANGELOG.md'), ('MIT. first cut of ' + $RepoName + "`n"), $enc)
    [IO.File]::WriteAllText((Join-Path $goodDocs 'CONTRIBUTING.md'), ('Thanks for helping with ' + $RepoName + ".`n"), $enc)
    $r4 = Invoke-HygieneScan -Root $goodDocs
    [void]$checks.Add(@{ name = 'final license wording + one-line repo name: 0 problem'; ok = ($r4.MissingMarkers.Count -eq 0) })
    [void]$checks.Add(@{ name = 'documentation tree stays unclassified-free';            ok = (@(Get-UnclassifiedTokens -Res $r4).Count -eq 0) })

    $badDocs = Join-Path $tmpRoot 'docs-bad'
    New-Item -ItemType Directory -Force -Path $badDocs | Out-Null
    [IO.File]::WriteAllText((Join-Path $badDocs '.gitignore'), $ignoreBody, $enc)
    [IO.File]::WriteAllText((Join-Path $badDocs 'LICENSE'), ('proposed default MIT text' + "`n"), $enc)
    [IO.File]::WriteAllText((Join-Path $badDocs 'README.md'), ('this license is pending. MIT. SECURITY.md. read-only and report-only. ' + $InternalMaterialSentence + '. ' + $RepoName + ' and again ' + $RepoName + "`n"), $enc)
    [IO.File]::WriteAllText((Join-Path $badDocs 'CHANGELOG.md'), ('MIT. ' + $RepoName + "`n"), $enc)
    [IO.File]::WriteAllText((Join-Path $badDocs 'CONTRIBUTING.md'), ('Thanks. ' + $RepoName + "`n"), $enc)
    $r5 = Invoke-HygieneScan -Root $badDocs
    [void]$checks.Add(@{ name = 'provisional wording and a duplicated repo name are caught'; ok = ($r5.MissingMarkers.Count -ge 3) })

    $failed = @($checks | Where-Object { -not $_.ok })
    foreach ($c in $checks) { Write-Host ('  ' + $(if ($c.ok) { 'PASS' } else { 'FAIL' }) + '  ' + $c.name) }
    Write-Host ''
    Write-Host ('self-test: ' + $checks.Count + ' control(s), ' + $failed.Count + ' failed')
    if ($failed.Count -gt 0) { return 1 }
    return 0
  } finally {
    if (-not $KeepTemp) {
      if (Test-Path -LiteralPath $tmpRoot) { Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue }
    } else {
      Write-Host ('kept: ' + $tmpRoot)
    }
  }
}

# ---------------------------------------------------------------------------
# 5. entry point
# ---------------------------------------------------------------------------
if ($SelfTest) {
  $code = Invoke-SelfTest
  exit $code
}

$root = $RepoRootDefault
if ($ScanRoot -ne '') { $root = $ScanRoot }

try {
  $result = Invoke-HygieneScan -Root $root -ExtraRoots $ExtraRoots -StrictLineEndings:$StrictLineEndings
} catch {
  Write-Host ('gate could not run: ' + $_.Exception.Message)
  exit 2
}

$blocking = Show-Report -Res $result

if ($Json) {
  $forbCode = @($result.ForbiddenHits | Where-Object { $_.Class -eq 'CODE_REFERENCE' }).Count
  $forbDoc = @($result.ForbiddenHits | Where-Object { $_.Class -eq 'DOCUMENTED' }).Count
  $summaryUnclassified = @(Get-UnclassifiedTokens -Res $result).Count
  $summary = [pscustomobject]@{
    root             = $result.Root
    roots            = $result.Roots
    files            = $result.FileCount
    blockedHits      = $result.BlockedHits.Count
    credValueHits    = $result.CredValueHits.Count
    wordHits         = $result.WordInventory.Count
    encodingFailures = $result.EncodingFailures.Count
    lineEndingNotes  = $result.LineEndingNotes.Count
    binaryFailures   = $result.BinaryFailures.Count
    forbiddenCode    = $forbCode
    forbiddenDoc     = $forbDoc
    missingIgnores   = $result.MissingIgnores.Count
    missingMarkers   = $result.MissingMarkers.Count
    unclassified     = $summaryUnclassified
    blockingTotal    = $blocking
    verdict          = $(if ($blocking -eq 0) { 'clean' } else { 'fail' })
  }
  Write-Host ($summary | ConvertTo-Json -Compress)
}

if ($blocking -gt 0) { exit 1 }
exit 0
