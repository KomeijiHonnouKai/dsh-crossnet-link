<#
.SYNOPSIS
  README style gate (read-only). Companion to the remote-tailnet-guard README revision plan.
.DESCRIPTION
  Reads one Markdown file, judges it against the plan's hard rules, prints measured
  numbers plus PASS/FAIL per rule. Fenced code blocks are excluded; inline code spans
  are stripped before punctuation statistics.
  Exit codes follow this project's own contract: 0 = all pass; 1 = advisory only; 2 = blocking.
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\readme-style-check.ps1 -Path .\README.md
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Path,
    [int]$MaxLines = 240,
    [int]$MaxWidth = 90,
    [int]$MaxBold = 30,
    [int]$MaxTables = 4,
    [int]$MaxTableCols = 4,
    [int]$MaxSectionRefs = 3,
    [double]$MinFullWidthRatio = 0.9,
    [switch]$AsJson
)

$ErrorActionPreference = 'Stop'
trap { Write-Host ("[FAIL] checker crashed: " + $_.Exception.Message); exit 2 }
if (-not (Test-Path -LiteralPath $Path)) { Write-Host "[FAIL] file not found: $Path"; exit 2 }

$bt = [char]96
$fence = ([string]$bt) + ([string]$bt) + ([string]$bt)
$inlineRe = [regex]("[" + $bt + "][^" + $bt + "]*[" + $bt + "]")

$raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
$all = $raw -split "\r?\n"

$inCode = $false
$codeBlocks = 0
$codeLines = 0
$body = New-Object System.Collections.ArrayList
$headings = New-Object System.Collections.ArrayList
$n = 0
foreach ($line in $all) {
    $n++
    if ($line.TrimStart().StartsWith($fence)) { $inCode = -not $inCode; $codeBlocks++; continue }
    if ($inCode) { $codeLines++; continue }
    [void]$body.Add([pscustomobject]@{ N = $n; T = $line })
    if ($line -match '^#{1,6}\s') { [void]$headings.Add([pscustomobject]@{ N = $n; T = $line }) }
}

function Get-DisplayWidth([string]$s) {
    $w = 0
    foreach ($ch in $s.ToCharArray()) {
        $c = [int][char]$ch
        if (($c -ge 0x4E00 -and $c -le 0x9FFF) -or ($c -ge 0x3000 -and $c -le 0x303F) -or ($c -ge 0xFF00 -and $c -le 0xFF60)) { $w += 2 } else { $w++ }
    }
    return $w
}

$wide = New-Object System.Collections.ArrayList
$multiParen = New-Object System.Collections.ArrayList
$boldSpans = 0
$fwPunct = 0
$hwPunct = 0
$taskTags = New-Object System.Collections.ArrayList
$sectionRefs = 0
$headingBold = New-Object System.Collections.ArrayList

foreach ($row in $body) {
    $t = $row.T
    $prose = $inlineRe.Replace($t, '')
    if ((Get-DisplayWidth($t)) -gt $MaxWidth) { [void]$wide.Add([pscustomobject]@{ N = $row.N; W = (Get-DisplayWidth($t)) }) }
    if ($t -match '^#') {
        if ($prose -match '\*\*') { [void]$headingBold.Add($row) }
        continue
    }
    if ($t -match '^\s*\|') { continue }
    $boldSpans += ([regex]::Matches($prose, '\*\*[^*]+\*\*')).Count
    if (([regex]::Matches($prose, '\(|\uFF08')).Count -ge 2) { [void]$multiParen.Add($row) }
    $fwPunct += ([regex]::Matches($prose, '[\uFF0C\u3002\uFF1A\uFF1B\uFF08\uFF09\uFF1F\uFF01\u3001]')).Count
    $hwPunct += ([regex]::Matches($prose, '[,.:;?!]')).Count
    if ($prose -match '(?<![A-Za-z0-9])t\d{1,2}(?![A-Za-z0-9])') { [void]$taskTags.Add($row) }
    $sectionRefs += ([regex]::Matches($prose, [string][char]0x00A7)).Count
}

$tableBlocks = 0
$maxCols = 0
$prevWasRow = $false
foreach ($row in $body) {
    $isRow = $row.T -match '^\s*\|'
    if ($isRow) {
        $cells = $row.T.Trim().Trim('|') -split '\|'
        if ($cells.Count -gt $maxCols) { $maxCols = $cells.Count }
        if (-not $prevWasRow) { $tableBlocks++ }
    }
    $prevWasRow = $isRow
}

$nums = @()
foreach ($h in $headings) { if ($h.T -match '^##\s+(\d+)\.\s') { $nums += [int]$Matches[1] } }
$numOk = $true
$numNote = 'none'
if ($nums.Count -gt 0) {
    for ($k = 1; $k -lt $nums.Count; $k++) { if ($nums[$k] -ne $nums[$k - 1] + 1) { $numOk = $false } }
    $numNote = ($nums -join ',')
}

$totalPunct = $fwPunct + $hwPunct
$ratio = 0.0
if ($totalPunct -gt 0) { $ratio = [math]::Round($fwPunct / $totalPunct, 3) }

$results = New-Object System.Collections.ArrayList
function Add-Rule([string]$id, [string]$sev, [bool]$ok, [string]$actual, [string]$limit, [string]$note) {
    [void]$results.Add([pscustomobject]@{ id = $id; severity = $sev; ok = $ok; actual = $actual; limit = $limit; note = $note })
}

Add-Rule 'L1-total-lines'       'advisory' (($all.Count) -le $MaxLines)        ("$($all.Count)")            "<= $MaxLines"           'total lines incl. code'
Add-Rule 'L2-line-width'        'blocking' ($wide.Count -eq 0)                 ("$($wide.Count) lines")     "<= $MaxWidth display"   'over-wide lines'
Add-Rule 'P1-fullwidth-ratio'   'blocking' ($ratio -ge $MinFullWidthRatio)    ("$ratio")                   ">= $MinFullWidthRatio"  "fullwidth=$fwPunct halfwidth=$hwPunct"
Add-Rule 'P2-paren-density'     'blocking' ($multiParen.Count -eq 0)           ("$($multiParen.Count) lines") "0 lines with >=2 parens" 'paren density'
Add-Rule 'F1-bold-density'      'blocking' ($boldSpans -le $MaxBold)           ("$boldSpans")               "<= $MaxBold"            'bold spans in prose'
Add-Rule 'F2-heading-bold'      'blocking' ($headingBold.Count -eq 0)          ("$($headingBold.Count)")    '0'                      'bold inside headings'
Add-Rule 'F3-table-budget'      'blocking' (($tableBlocks -le $MaxTables) -and ($maxCols -le $MaxTableCols)) ("$tableBlocks tables / max $maxCols cols") "<= $MaxTables tables, <= $MaxTableCols cols" 'table budget'
Add-Rule 'S1-section-refs'      'advisory' ($sectionRefs -le $MaxSectionRefs)   ("$sectionRefs")             "<= $MaxSectionRefs"     'section cross-references'
Add-Rule 'S2-task-tags'         'blocking' ($taskTags.Count -eq 0)             ("$($taskTags.Count) lines") '0'                      'internal task ids'
Add-Rule 'S3-heading-numbering' 'blocking' $numOk                             ($numNote)                   'contiguous'             '## numbering continuity'

$blocking = @($results | Where-Object { -not $_.ok -and $_.severity -eq 'blocking' })
$advisory = @($results | Where-Object { -not $_.ok -and $_.severity -eq 'advisory' })

if ($AsJson) {
    [pscustomobject]@{
        file = (Resolve-Path -LiteralPath $Path).Path
        lines = $all.Count; codeLines = $codeLines; codeBlocks = $codeBlocks
        fullWidthPunct = $fwPunct; halfWidthPunct = $hwPunct; ratio = $ratio
        boldSpans = $boldSpans; tables = $tableBlocks; maxTableCols = $maxCols
        blocking = $blocking.Count; advisory = $advisory.Count; rules = $results
    } | ConvertTo-Json -Depth 5
}
else {
    Write-Host ("readme style gate - " + (Resolve-Path -LiteralPath $Path).Path)
    Write-Host ("lines=$($all.Count)  code=$codeLines lines/$codeBlocks blocks  punct fw=$fwPunct hw=$hwPunct ratio=$ratio  bold=$boldSpans  tables=$tableBlocks (max $maxCols cols)  refs=$sectionRefs  taskTags=$($taskTags.Count)")
    Write-Host ''
    foreach ($r in $results) {
        $tag = '[PASS]'
        if (-not $r.ok) { if ($r.severity -eq 'blocking') { $tag = '[FAIL]' } else { $tag = '[WARN]' } }
        "{0} {1,-22} {2,-8} actual={3,-30} limit={4}" -f $tag, $r.id, $r.severity, $r.actual, $r.limit | Write-Host
    }
    Write-Host ''
    if ($wide.Count -gt 0) { Write-Host ("widest: " + (($wide | Sort-Object W -Descending | Select-Object -First 6 | ForEach-Object { "L$($_.N)=$($_.W)" }) -join ' ')) }
    if ($multiParen.Count -gt 0) { Write-Host ("paren-heavy: " + (($multiParen | Select-Object -First 6 | ForEach-Object { "L$($_.N)" }) -join ' ')) }
    Write-Host ("verdict: blocking=$($blocking.Count) advisory=$($advisory.Count)")
}
if ($blocking.Count -gt 0) { exit 2 }
if ($advisory.Count -gt 0) { exit 1 }
exit 0
