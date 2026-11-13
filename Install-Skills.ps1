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

.PARAMETER Remote
    First look at the repo's remote (git fetch of this clone's upstream branch). With -Check: report how
    many commits the clone is behind, which skills they touch and the commit subjects, and change
    nothing. Without -Check: if the clone is only behind (never ahead or diverged) and has no uncommitted
    changes to tracked files, run git pull --ff-only, then install as usual; if Install-Skills.ps1
    itself changed, the new copy is run instead of this one. If the remote cannot be reached the script
    says so and carries on with the local files. Prints one line starting with REMOTE:.

.PARAMETER MaxAgeHours
    With -Remote: skip the git fetch when the clone was fetched less than this many hours ago (the
    time of .git\FETCH_HEAD); the already-fetched state is still compared. 0 (default) always fetches.

.NOTES
    At the end of every run the script also looks for companion tool folders that the skills refer to by
    absolute path (for example C:\MyFiles\Git\GraphTools) and reports any that are missing, with the
    git clone command for the known ones. This is a report only: the script never clones or builds them.

.EXAMPLE
    .\Install-Skills.ps1
    .\Install-Skills.ps1 -Force
    .\Install-Skills.ps1 -Prune
    .\Install-Skills.ps1 -Check
    .\Install-Skills.ps1 -Check -Remote -MaxAgeHours 6
    .\Install-Skills.ps1 -Remote -Force
#>

param(
    [switch]$Force,
    [switch]$Prune,
    [switch]$Check,
    [switch]$Remote,
    [int]$MaxAgeHours = 0
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
$remoteTouched = @()

if ($Remote) {
    # Runs before the skill folders are listed, because a pull can add or change them.
    $remoteStatus = 'Unknown'
    $remoteDetail = $null
    $git = Get-Command git -ErrorAction SilentlyContinue
    if (-not $git) { $remoteStatus = 'NoGit' }
    elseif (-not (Test-Path (Join-Path $repoRoot '.git'))) { $remoteStatus = 'NotAGitClone' }
    else {
        $fetchHead = Join-Path $repoRoot '.git\FETCH_HEAD'
        $recent = $MaxAgeHours -gt 0 -and (Test-Path $fetchHead) -and ((Get-Date) - (Get-Item $fetchHead).LastWriteTime).TotalHours -lt $MaxAgeHours
        $fetchOk = $true
        if (-not $recent) {
            $fetchOut = git -C $repoRoot fetch --quiet origin 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -and $_ -ne 'System.Management.Automation.RemoteException' } | Out-String
            if ($LASTEXITCODE -ne 0) { $fetchOk = $false; $remoteStatus = 'Unreachable'; $remoteDetail = $fetchOut.Trim() }
        }
        else { $remoteDetail = "fetch skipped: this clone was fetched less than $MaxAgeHours hour(s) ago" }
        if ($fetchOk) {
            $upstream = (git -C $repoRoot rev-parse --abbrev-ref '@{u}' 2>$null | Out-String).Trim()
            if ($LASTEXITCODE -ne 0 -or -not $upstream) { $remoteStatus = 'NoUpstream' }
            else {
                $behind = [int](git -C $repoRoot rev-list --count 'HEAD..@{u}')
                $ahead = [int](git -C $repoRoot rev-list --count '@{u}..HEAD')
                if ($behind -eq 0) { $remoteStatus = 'UpToDate' }
                elseif ($ahead -gt 0) { $remoteStatus = "Diverged (behind $behind, ahead $ahead; not pulled)" }
                else { $remoteStatus = "Behind $behind commit(s)" }
                if ($behind -gt 0) {
                    Write-Host "Commits on $upstream that this clone does not have yet:" -ForegroundColor Yellow
                    git -C $repoRoot log --oneline --max-count=15 'HEAD..@{u}' | ForEach-Object { Write-Host "    $_" }
                    $changedPaths = @(git -C $repoRoot diff --name-only 'HEAD..@{u}')
                    foreach ($top in ($changedPaths | ForEach-Object { ($_ -split '/')[0] } | Sort-Object -Unique)) {
                        git -C $repoRoot cat-file -e "@{u}:$top/SKILL.md" 2>$null
                        if ($LASTEXITCODE -eq 0) { $remoteTouched += $top }
                    }
                    $installerChanged = $changedPaths -contains 'Install-Skills.ps1'
                    if ($remoteTouched.Count -gt 0) { Write-Host "  Skills touched: $($remoteTouched -join ', ')" -ForegroundColor Yellow }
                    if ($installerChanged) { Write-Host "  Install-Skills.ps1 itself changed" -ForegroundColor Yellow }
                    if (-not $Check -and $ahead -eq 0) {
                        $dirty = (git -C $repoRoot status --porcelain --untracked-files=no | Out-String).Trim()
                        if ($dirty) { $remoteStatus = "Behind $behind commit(s), NOT pulled: uncommitted changes to tracked files" }
                        else {
                            $pullOut = git -C $repoRoot pull --ff-only --quiet 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -and $_ -ne 'System.Management.Automation.RemoteException' } | Out-String
                            if ($LASTEXITCODE -ne 0) { $remoteStatus = "Behind $behind commit(s), NOT pulled: $($pullOut.Trim())" }
                            else {
                                $remoteStatus = "Pulled $behind commit(s)"
                                if ($installerChanged) {
                                    Write-Host "REMOTE: $remoteStatus (Install-Skills.ps1 changed; continuing with the new copy)"
                                    $rerun = @{} + $PSBoundParameters
                                    [void]$rerun.Remove('Remote'); [void]$rerun.Remove('MaxAgeHours')
                                    & (Join-Path $repoRoot 'Install-Skills.ps1') @rerun
                                    exit $LASTEXITCODE
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    if ($remoteDetail) { Write-Host "  $remoteDetail" -ForegroundColor DarkGray }
    Write-Host "REMOTE: $remoteStatus"
    Write-Host ""
}

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
    $parts = @()
    if ($skillsNeedingUpdate.Count -gt 0) { $parts += "local: $($skillsNeedingUpdate.Count) skill(s): $($skillsNeedingUpdate -join ', ')" }
    if ($remoteTouched.Count -gt 0) { $parts += "remote: not pulled yet, touches $($remoteTouched -join ', ')" }
    $notChecked = $Remote -and ($remoteStatus -in 'Unreachable', 'NoUpstream', 'NotAGitClone', 'NoGit')
    if ($parts.Count -gt 0) {
        if ($notChecked) { $parts += "GitHub not checked: $remoteStatus" }
        Write-Host "RESULT: UpdatesAvailable ($($parts -join '; '))"
    }
    elseif ($notChecked) {
        Write-Host "RESULT: UpToDate (local clone only; GitHub not checked: $remoteStatus)"
    }
    else {
        Write-Host "RESULT: UpToDate"
    }
}
else {
    Write-Host "Reminder: after installing/updating the graph-enabled skill, confirm that" -ForegroundColor DarkGray
    Write-Host "GraphTools itself is built at the path referenced inside its SKILL.md." -ForegroundColor DarkGray
}