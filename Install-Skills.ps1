<#
.SYNOPSIS
    Copies each skill folder in this repo into the personal Copilot skills directory
    (%USERPROFILE%\.copilot\skills\). Run this after cloning the repo on a new machine,
    or after pulling updates to an existing skill.

.PARAMETER Force
    Skip the per-skill confirmation prompt and copy/update everything automatically.

.EXAMPLE
    .\Install-Skills.ps1
    .\Install-Skills.ps1 -Force
#>

param(
    [switch]$Force
)

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

    if ($changedFiles.Count -eq 0) {
        Write-Host "  Already up to date. Skipping." -ForegroundColor DarkGray
        continue
    }

    Write-Host "  Changed/new file(s):" -ForegroundColor Yellow
    $changedFiles | ForEach-Object { Write-Host "    - $_" }

    if (-not $Force) {
        $answer = Read-Host "  Copy these changes into $dest ? (y/N)"
        if ($answer -notmatch '^[Yy]$') {
            Write-Host "  Skipped." -ForegroundColor DarkGray
            continue
        }
    }

    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    Copy-Item -Path (Join-Path $skill.FullName "*") -Destination $dest -Recurse -Force
    Write-Host "  Done." -ForegroundColor Green
}

Write-Host ""
Write-Host "All skills processed." -ForegroundColor Cyan
Write-Host "Reminder: after installing/updating the graph-enabled skill, confirm that" -ForegroundColor DarkGray
Write-Host "GraphTools itself is built at the path referenced inside its SKILL.md." -ForegroundColor DarkGray