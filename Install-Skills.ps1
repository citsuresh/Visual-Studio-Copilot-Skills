<#
.SYNOPSIS
    Copies each skill folder in this repo into the personal Copilot skills directory
    (%USERPROFILE%\.copilot\skills\). Run this after cloning the repo on a new machine,
    or after pulling updates to an existing skill.

.PARAMETER Force
    Skip the per-skill confirmation prompt and copy/update everything automatically.

.PARAMETER Prune
    Also delete files that exist in an installed skill folder but no longer exist in the repo copy
    (for example a script that was removed from the repo). Without -Prune such files are only
    reported and left in place. The deletion is covered by the same per-skill confirmation as the
    copy (skipped with -Force), and only touches files inside that skill's own destination folder.

.PARAMETER Check
    Read-only: list, per skill, which files are new or changed (and which installed files are no longer
    in the repo), print a final line starting with RESULT:, and change nothing. No prompts. Use it to
    see whether an update is needed before running the installer for real.

.NOTES
    At the end of every run the script also looks for companion tool folders that the skills refer to by
    absolute path (for example C:\MyFiles\Git\GraphTools) and reports any that are missing, with the
    git clone command for the known ones. This is a report only: the script never clones or builds them.

.EXAMPLE
    .\Install-Skills.ps1
    .\Install-Skills.ps1 -Force
    .\Install-Skills.ps1 -Prune
    .\Install-Skills.ps1 -Check
#>

param(
    [switch]$Force,
    [switch]$Prune,
    [switch]$Check
)

# Companion repos the skills depend on, with where to get them (used only to print a clone command).
$knownCompanions = @{
    'GraphTools'            = 'https://github.com/citsuresh/GraphTools'
    'AgentDebugToolkit'     = 'https://github.com/citsuresh/AgentDebugToolkit'
    'VsChatHistoryToolkit'  = 'https://github.com/citsuresh/VsChatHistoryToolkit'
}
$skillsNeedingUpdate = @()

$repoRoot = $PSScriptRoot
$destRoot = Join-Path $env:USERPROFILE ".copilot\skills"

Write-Host "Scanning for skills in $repoRoot ..." -ForegroundColor Cyan

# A "skill folder" is any immediate subfolder containing a SKILL.md — this means new
# skills added to the repo later are picked up automatically, no script changes needed.
$skillFolders = Get-ChildItem -Path $repoRoot -Directory | Where-Object {
    Test-Path (Join-Path $_.FullName "SKILL.md")
}

if ($skillFolders.Count -eq 0) {
    Write-Host "No skill folders found (looking for subfolders containing SKILL.md)." -ForegroundColor Yellow
    exit 0
}

function Get-FileHashSafe($path) {
    if (Test-Path $path) { return (Get-FileHash -Path $path -Algorithm SHA256).Hash }
    return $null
}

foreach ($skill in $skillFolders) {
    $dest = Join-Path $destRoot $skill.Name
    Write-Host ""
    Write-Host "Skill: $($skill.Name)" -ForegroundColor Green
    Write-Host "  Source:      $($skill.FullName)"
    Write-Host "  Destination: $dest"

    $srcFiles = Get-ChildItem -Path $skill.FullName -Recurse -File
    $changedFiles = @()

    foreach ($f in $srcFiles) {
        $relPath = $f.FullName.Substring($skill.FullName.Length).TrimStart('\', '/')
        $destFile = Join-Path $dest $relPath
        $srcHash = Get-FileHashSafe $f.FullName
        $destHash = Get-FileHashSafe $destFile
        if ($srcHash -ne $destHash) {
            $changedFiles += $relPath
        }
    }

    # Files present in the installed copy but not in the repo copy (e.g. a script removed from the repo).
    $orphanFiles = @()
    if (Test-Path $dest) {
        $srcRel = @($srcFiles | ForEach-Object { $_.FullName.Substring($skill.FullName.Length).TrimStart('\', '/') })
        $orphanFiles = @(Get-ChildItem -Path $dest -Recurse -File | ForEach-Object {
                $rel = $_.FullName.Substring($dest.Length).TrimStart('\', '/')
                if ($srcRel -notcontains $rel) { $rel }
            })
    }
    if ($Check) {
        if ($changedFiles.Count -eq 0 -and $orphanFiles.Count -eq 0) {
            Write-Host "  Up to date." -ForegroundColor DarkGray
            continue
        }
        $skillsNeedingUpdate += $skill.Name
        if (-not (Test-Path $dest)) { Write-Host "  Not installed yet." -ForegroundColor Yellow }
        if ($changedFiles.Count -gt 0) {
            Write-Host "  New/changed file(s):" -ForegroundColor Yellow
            $changedFiles | ForEach-Object { Write-Host "    - $_" }
        }
        if ($orphanFiles.Count -gt 0) {
            Write-Host "  Installed file(s) no longer in the repo (removed only with -Prune):" -ForegroundColor Yellow
            $orphanFiles | ForEach-Object { Write-Host "    - $_" }
        }
        continue
    }

    if (-not $Prune -and $orphanFiles.Count -gt 0) {
        Write-Host "  $($orphanFiles.Count) installed file(s) no longer in the repo (left in place; use -Prune to remove):" -ForegroundColor DarkYellow
        $orphanFiles | ForEach-Object { Write-Host "    - $_" }
        $orphanFiles = @()
    }

    if ($changedFiles.Count -eq 0 -and $orphanFiles.Count -eq 0) {
        Write-Host "  Already up to date. Skipping." -ForegroundColor DarkGray
        continue
    }

    if ($changedFiles.Count -gt 0) {
        Write-Host "  Changed/new file(s):" -ForegroundColor Yellow
        $changedFiles | ForEach-Object { Write-Host "    - $_" }
    }
    if ($orphanFiles.Count -gt 0) {
        Write-Host "  File(s) to remove (not in the repo copy):" -ForegroundColor Yellow
        $orphanFiles | ForEach-Object { Write-Host "    - $_" }
    }

    if (-not $Force) {
        $answer = Read-Host "  Apply these changes to $dest ? (y/N)"
        if ($answer -notmatch '^[Yy]$') {
            Write-Host "  Skipped." -ForegroundColor DarkGray
            continue
        }
    }

    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    Copy-Item -Path (Join-Path $skill.FullName "*") -Destination $dest -Recurse -Force

    $destFull = [System.IO.Path]::GetFullPath($dest).TrimEnd('\') + '\'
    foreach ($rel in $orphanFiles) {
        $target = [System.IO.Path]::GetFullPath((Join-Path $dest $rel))
        if ($target.StartsWith($destFull, [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $target -Force
            # Remove folders the deletion left empty, never the skill folder itself.
            $dir = Split-Path $target -Parent
            while ($dir.TrimEnd('\') + '\' -ne $destFull -and $dir.StartsWith($destFull, [StringComparison]::OrdinalIgnoreCase) -and -not (Get-ChildItem -LiteralPath $dir -Force)) {
                Remove-Item -LiteralPath $dir -Force
                $dir = Split-Path $dir -Parent
            }
        }
    }
    Write-Host "  Done." -ForegroundColor Green
}

Write-Host ""
if ($Check) {
    Write-Host "Check finished (nothing was changed)." -ForegroundColor Cyan
}
else {
    Write-Host "All skills processed." -ForegroundColor Cyan
}

# Companion tools: find absolute paths of the form C:\...\Git\<Name> in the skills' text and scripts.
$companionPaths = @{}
foreach ($skill in $skillFolders) {
    Get-ChildItem -Path $skill.FullName -Recurse -File -Include *.md, *.ps1 | ForEach-Object {
        $file = $_
        Select-String -Path $file.FullName -Pattern 'C:\\MyFiles\\Git\\([A-Za-z0-9_.-]+)' -AllMatches | ForEach-Object {
            foreach ($m in $_.Matches) {
                $name = $m.Groups[1].Value
                if ($name -ne (Split-Path $repoRoot -Leaf)) {
                    if (-not $companionPaths.ContainsKey($name)) { $companionPaths[$name] = New-Object System.Collections.Generic.HashSet[string] }
                    [void]$companionPaths[$name].Add($skill.Name)
                }
            }
        }
    }
}
$missingCompanions = @($companionPaths.Keys | Where-Object { -not (Test-Path (Join-Path 'C:\MyFiles\Git' $_)) } | Sort-Object)
if ($missingCompanions.Count -gt 0) {
    Write-Host ""
    Write-Host "Companion tool folder(s) the skills refer to but that were not found:" -ForegroundColor Yellow
    foreach ($name in $missingCompanions) {
        $used = ($companionPaths[$name] | Sort-Object) -join ', '
        Write-Host "  - C:\MyFiles\Git\$name  (used by: $used)"
        if ($knownCompanions.ContainsKey($name)) {
            Write-Host "      git clone $($knownCompanions[$name]) C:\MyFiles\Git\$name" -ForegroundColor DarkGray
        }
    }
    Write-Host "  Those skills will not work until the folders exist (and are built, where the skill says so)." -ForegroundColor DarkYellow
}
else {
    Write-Host "Companion tool folders referenced by the skills: all found." -ForegroundColor DarkGray
}

if ($Check) {
    if ($skillsNeedingUpdate.Count -gt 0) {
        Write-Host "RESULT: UpdatesAvailable ($($skillsNeedingUpdate.Count) skill(s): $($skillsNeedingUpdate -join ', '))"
    }
    else {
        Write-Host "RESULT: UpToDate"
    }
}
else {
    Write-Host "Reminder: after installing/updating the graph-enabled skill, confirm that" -ForegroundColor DarkGray
    Write-Host "GraphTools itself is built at the path referenced inside its SKILL.md." -ForegroundColor DarkGray
}