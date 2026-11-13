<#
.SYNOPSIS
Generates skills-index.json (version + one-line "what's new" per skill) from the SKILL.md files.

.DESCRIPTION
For every <folder>\SKILL.md in the repo that has a `CURRENT_SKILL_VERSION = N` line, the index holds
N and the first sentence of the changelog entry for vN (the "- vN <dash> text" line plus its indented
continuation lines). The changelog order in the file does not matter; the entry is found by number.
No AI and no commit message is involved: the same SKILL.md files always give the same index.
Skills with no CURRENT_SKILL_VERSION (for example install-skills) are not indexed.

.PARAMETER RepoRoot
Repository root. Default: the parent of this script's folder.

.PARAMETER Check
Read-only. Compares the generated index with the committed file; prints INDEX: UpToDate, or
INDEX: OutOfDate / Missing and exits 1. Writes nothing.

.PARAMETER Stage
After writing, runs `git add skills-index.json` (used by the pre-commit hook).

.PARAMETER WarnUnbumped
For SKILL.md files staged in git, prints a WARNING (never fails) when the staged content differs from
HEAD but CURRENT_SKILL_VERSION is unchanged. Wording-only edits legitimately skip a bump.

.PARAMETER WarnUnbumpedFrom
A git ref or SHA (for example the remote tip a push would replace). Prints the same WARNING (never
fails) for every SKILL.md whose content at -WarnUnbumpedTo differs from -WarnUnbumpedFrom but whose
CURRENT_SKILL_VERSION is unchanged. Judging the whole range means a bump in any commit of a series
satisfies it. Used by the pre-push hook. A ref that cannot be resolved is skipped silently.

.PARAMETER WarnUnbumpedTo
End of the range for -WarnUnbumpedFrom. Default: HEAD.

Modifies: writes <RepoRoot>\skills-index.json unless -Check; with -Stage also stages it.
#>
[CmdletBinding()]
param(
    [string]$RepoRoot,
    [switch]$Check,
    [switch]$Stage,
    [switch]$WarnUnbumped,
    [string]$WarnUnbumpedFrom,
    [string]$WarnUnbumpedTo = 'HEAD'
)

$ErrorActionPreference = 'Continue'
# $PSScriptRoot is empty in a parameter default under -File, so resolve the default here.
if (-not $RepoRoot) { $RepoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }
$indexPath = Join-Path $RepoRoot 'skills-index.json'
$maxLen = 240
$sep = '(?:' + [char]0x2014 + '|' + [char]0x2013 + '|--|-)'

function Get-SkillVersion([string[]]$Lines) {
    foreach ($l in $Lines) {
        $m = [regex]::Match($l, 'CURRENT_SKILL_VERSION\s*=\s*(\d+)')
        if ($m.Success) { return [int]$m.Groups[1].Value }
    }
    return $null
}

function Get-WhatsNew([string[]]$Lines, [int]$Version) {
    $start = '^(\s*)[-*]\s+v' + $Version + '\s+' + $sep + '\s+(.*)$'
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $m = [regex]::Match($Lines[$i], $start)
        if (-not $m.Success) { continue }
        $indent = $m.Groups[1].Length
        $text = $m.Groups[2].Value
        for ($j = $i + 1; $j -lt $Lines.Count; $j++) {
            $c = [regex]::Match($Lines[$j], '^(\s+)\S')
            if (-not $c.Success -or $c.Groups[1].Length -le $indent) { break }
            $text += ' ' + $Lines[$j].Trim()
        }
        $text = ($text -replace '`', '' -replace '\s+', ' ').Trim()
        if ($text.Length -gt 0) { $text = $text.Substring(0, 1).ToUpperInvariant() + $text.Substring(1) }
        $s = [regex]::Match($text, '^(.+?)(?<!\be\.g)(?<!\bi\.e)\.(?:\s+(?=[A-Z(])|$)')
        if ($s.Success) { $text = $s.Groups[1].Value + '.' }
        if ($text.Length -gt $maxLen) {
            $text = $text.Substring(0, $maxLen - 3)
            $text = $text.Substring(0, $text.LastIndexOf(' ')) + '...'
        }
        return $text
    }
    return ''
}

function ConvertTo-JsonString([string]$s) {
    return '"' + $s.Replace('\', '\\').Replace('"', '\"') + '"'
}

# Build the index text.
$entries = @()
$names = @(Get-ChildItem -LiteralPath $RepoRoot -Directory |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') } |
    ForEach-Object { $_.Name })
[Array]::Sort($names, [StringComparer]::Ordinal)
foreach ($name in $names) {
    $lines = Get-Content -LiteralPath (Join-Path (Join-Path $RepoRoot $name) 'SKILL.md') -Encoding UTF8
    $ver = Get-SkillVersion $lines
    if ($null -eq $ver) { if (-not $Check) { Write-Host "Not indexed (no CURRENT_SKILL_VERSION): $name" }; continue }
    $new = Get-WhatsNew $lines $ver
    if (-not $new) { Write-Host "WARNING: $name has no changelog entry for v$ver; whatsNew left empty." }
    $entries += [pscustomobject]@{ Name = $name; Version = $ver; WhatsNew = $new }
}

$out = New-Object System.Collections.Generic.List[string]
$out.Add('{'); $out.Add('  "schema": 1,'); $out.Add('  "skills": {')
for ($k = 0; $k -lt $entries.Count; $k++) {
    $e = $entries[$k]
    $comma = if ($k -lt $entries.Count - 1) { ',' } else { '' }
    $out.Add('    ' + (ConvertTo-JsonString $e.Name) + ': {')
    $out.Add('      "version": ' + $e.Version + ',')
    $out.Add('      "whatsNew": ' + (ConvertTo-JsonString $e.WhatsNew))
    $out.Add('    }' + $comma)
}
$out.Add('  }'); $out.Add('}')
$text = ($out -join "`r`n") + "`r`n"

function ConvertTo-Lf([string]$s) { return $s.Replace("`r`n", "`n") }

$status = 'UpToDate'
if (-not (Test-Path -LiteralPath $indexPath)) { $status = 'Missing' }
elseif ((ConvertTo-Lf ([IO.File]::ReadAllText($indexPath))) -ne (ConvertTo-Lf $text)) { $status = 'OutOfDate' }

if ($WarnUnbumped) {
    $staged = @(git -C $RepoRoot diff --cached --name-only --diff-filter=AM 2>$null) | Where-Object { $_ -match '^[^/]+/SKILL\.md$' }
    foreach ($p in $staged) {
        $newLines = @(git -C $RepoRoot show ":$p" 2>$null)
        $oldLines = @(git -C $RepoRoot show "HEAD:$p" 2>$null)
        if ($LASTEXITCODE -ne 0 -or $oldLines.Count -eq 0) { continue }
        if (($newLines -join "`n") -eq ($oldLines -join "`n")) { continue }
        $nv = Get-SkillVersion $newLines
        if ($null -ne $nv -and $nv -eq (Get-SkillVersion $oldLines)) {
            Write-Host "WARNING: $p changed but CURRENT_SKILL_VERSION is still $nv. Bump it and add a changelog entry if the change affects behaviour; ignore this for wording-only edits."
        }
    }
}

if ($WarnUnbumpedFrom) {
    $changed = @(git -C $RepoRoot diff --name-only --diff-filter=AM $WarnUnbumpedFrom $WarnUnbumpedTo 2>$null) | Where-Object { $_ -match '^[^/]+/SKILL\.md$' }
    if ($LASTEXITCODE -eq 0) {
        foreach ($p in $changed) {
            $newLines = @(git -C $RepoRoot show "${WarnUnbumpedTo}:$p" 2>$null)
            $oldLines = @(git -C $RepoRoot show "${WarnUnbumpedFrom}:$p" 2>$null)
            if ($oldLines.Count -eq 0 -or $newLines.Count -eq 0) { continue }
            $nv = Get-SkillVersion $newLines
            if ($null -ne $nv -and $nv -eq (Get-SkillVersion $oldLines)) {
                Write-Host "WARNING: $p changed in this push but CURRENT_SKILL_VERSION is still $nv. Bump it and add a changelog entry if the change affects behaviour; ignore this for wording-only edits."
            }
        }
    }
}

if ($Check) {
    if ($status -eq 'UpToDate') { Write-Host 'INDEX: UpToDate'; exit 0 }
    Write-Host "INDEX: $status - run scripts\Update-SkillsIndex.ps1 and commit skills-index.json"
    exit 1
}

if ($status -ne 'UpToDate') {
    [IO.File]::WriteAllText($indexPath, $text, (New-Object Text.UTF8Encoding($false)))
    Write-Host "INDEX: Updated ($($entries.Count) skills)"
} else {
    Write-Host 'INDEX: UpToDate'
}
if ($Stage) { git -C $RepoRoot add -- skills-index.json 2>$null | Out-Null }
exit 0
