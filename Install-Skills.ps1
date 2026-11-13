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
    see whether an update is needed before running the installer for real. It also prints one INDEX:
    line saying whether skills-index.json matches the SKILL.md files (informational; RESULT: ignores it).

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
    It applies to the toolkit clones as well as this repo.

.PARAMETER SkipToolkits
    Do not look at the toolkits (GraphTools, AgentDebugToolkit, VsChatHistoryToolkit) at all: no TOOLKIT:
    lines, no clone, no build.

.PARAMETER ToolkitBaseUrl
    Where the toolkit repos are cloned from: <ToolkitBaseUrl>/<Name>. Defaults to https://github.com/citsuresh.
    A folder path also works (used by the tests, or for a fork).

.NOTES
    Every real (non -Check) run records this clone's absolute path in %USERPROFILE%\.copilot\skills-source.json
    ({"schema":1,"skillsRepo":"<path>"}), so the skills' first-use update check finds the clone without a path
    typed into each SKILL.md. With -Check it only prints one SOURCE: line (Recorded, Differs or NotRecorded;
    informational, RESULT: ignores it).

    Toolkits: the skills call three companion tools, each a git clone of its own public repo under
    %USERPROFILE%\.copilot\toolkits\<Name> and built in place by its scripts\agent\Build-Toolkit.ps1 (which
    writes .built-version after a successful build). Only toolkits used by a skill in this repo are looked at.
    Every run prints one TOOLKIT: line per toolkit: UpToDate, NotInstalled, NeedsBuild (source and build
    differ), Behind (-Remote only: upstream has newer commits), Diverged, NotAClone (a folder that is not a
    git clone; left alone), NoDotnetSdk (a build is needed but no .NET SDK is installed), or after a real run
    CloneFailed, PullFailed, NoBuildScript, BuildFailed. With -Check nothing changes and any state other than
    UpToDate is added to the RESULT: line. Without -Check the script clones missing toolkits, with -Remote
    also fast-forwards a toolkit that is only behind (never over uncommitted changes to tracked files), and
    builds whatever needs it; it asks first unless -Force. Exit code 1 if a clone, pull or build failed.

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
    [int]$MaxAgeHours = 0,
    [switch]$SkipToolkits,
    [string]$ToolkitBaseUrl = 'https://github.com/citsuresh'
)

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
                                    # -Remote stays on so the new copy also updates the toolkits; behind is 0 now, so it cannot loop.
                                    $rerun = @{} + $PSBoundParameters
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

# Where this clone lives, for the skills' first-use update check (read from skills-source.json).
$sourceFile = Join-Path (Split-Path $destRoot -Parent) 'skills-source.json'
$recordedRepo = $null
if (Test-Path -LiteralPath $sourceFile) {
    try { $recordedRepo = (Get-Content -LiteralPath $sourceFile -Raw | ConvertFrom-Json).skillsRepo } catch { $recordedRepo = $null }
}
if (-not $Check -and $recordedRepo -ne $repoRoot) {
    New-Item -ItemType Directory -Path (Split-Path $sourceFile -Parent) -Force | Out-Null
    $sourceJson = "{`r`n  `"schema`": 1,`r`n  `"skillsRepo`": `"" + $repoRoot.Replace('\', '\\') + "`"`r`n}`r`n"
    [IO.File]::WriteAllText($sourceFile, $sourceJson, (New-Object Text.UTF8Encoding($false)))
    if ($recordedRepo) { Write-Host "Recorded this clone's path in $sourceFile (was: $recordedRepo)." -ForegroundColor DarkGray }
    else { Write-Host "Recorded this clone's path in $sourceFile." -ForegroundColor DarkGray }
}

# Toolkits: companion tools the skills call. Each is a git clone of its own repo under
# %USERPROFILE%\.copilot\toolkits\<Name>, built in place by its scripts\agent\Build-Toolkit.ps1.
$toolkitDefs = @(
    @{ Name = 'GraphTools'; Skills = @('project-memory-management-graph') },
    @{ Name = 'AgentDebugToolkit'; Skills = @('ui-interaction', 'vs-debug', 'agent-orchestrator', 'ui-navigation-orchestrator') },
    @{ Name = 'VsChatHistoryToolkit'; Skills = @('vs-chat-history') }
)
$toolkitsRoot = Join-Path (Split-Path $destRoot -Parent) 'toolkits'
$toolkitResults = @()
$toolkitFailed = $false

function Read-ToolkitMarker([string]$dir) {
    $f = Join-Path $dir '.built-version'
    if (Test-Path -LiteralPath $f) { try { return (Get-Content -LiteralPath $f -Raw | ConvertFrom-Json) } catch { } }
    return $null
}
function Read-TrimmedFile([string]$path) {
    if (Test-Path -LiteralPath $path) { return (Get-Content -LiteralPath $path -Raw).Trim() }
    return $null
}
function Get-GitText([string]$dir, [string[]]$gitArgs) {
    $o = & git -C $dir @gitArgs 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    return ($o | Out-String).Trim()
}

if ($SkipToolkits) {
    Write-Host "Toolkits: skipped (-SkipToolkits)." -ForegroundColor DarkGray
}
else {
    $hasGit = [bool](Get-Command git -ErrorAction SilentlyContinue)
    $hasSdk = $false
    if (Get-Command dotnet -CommandType Application -ErrorAction SilentlyContinue) { $hasSdk = @(& dotnet --list-sdks 2>$null).Count -gt 0 }
    $savedPrompt = $env:GIT_TERMINAL_PROMPT
    $env:GIT_TERMINAL_PROMPT = '0'   # never wait for a password: these runs can be unattended
    Write-Host ""
    Write-Host "Toolkits (under $toolkitsRoot):" -ForegroundColor Cyan

    foreach ($tk in $toolkitDefs) {
        $name = $tk.Name
        $usedBy = @($tk.Skills | Where-Object { $skillFolders.Name -contains $_ })
        if ($usedBy.Count -eq 0) { continue }
        $dir = Join-Path $toolkitsRoot $name
        $url = $ToolkitBaseUrl.TrimEnd('/', '\') + '/' + $name
        $status = $null; $detail = $null; $action = 'None'; $behind = 0

        if (-not $hasGit) { $status = 'NoGit'; $detail = 'git was not found on PATH' }
        elseif (-not (Test-Path -LiteralPath $dir)) { $status = 'NotInstalled'; $action = 'Clone' }
        elseif (-not (Test-Path -LiteralPath (Join-Path $dir '.git'))) { $status = 'NotAClone'; $detail = "$dir is not a git clone; left alone" }
        else {
            $marker = Read-ToolkitMarker $dir
            $head = Get-GitText $dir @('rev-parse', 'HEAD')
            $ahead = 0
            if ($Remote) {
                $fetchHead = Join-Path $dir '.git\FETCH_HEAD'
                $recent = $MaxAgeHours -gt 0 -and (Test-Path -LiteralPath $fetchHead) -and ((Get-Date) - (Get-Item -LiteralPath $fetchHead).LastWriteTime).TotalHours -lt $MaxAgeHours
                $fetchOk = $true
                if (-not $recent) {
                    & git -C $dir fetch --quiet origin 2>$null
                    if ($LASTEXITCODE -ne 0) { $fetchOk = $false; $detail = 'GitHub not reachable; compared with the local clone only' }
                }
                if ($fetchOk -and (Get-GitText $dir @('rev-parse', '--abbrev-ref', '@{u}'))) {
                    $behind = [int](Get-GitText $dir @('rev-list', '--count', 'HEAD..@{u}'))
                    $ahead = [int](Get-GitText $dir @('rev-list', '--count', '@{u}..HEAD'))
                }
            }
            if ($behind -gt 0) {
                $status = 'Behind'
                $upVersion = Get-GitText $dir @('show', '@{u}:VERSION')
                $myVersion = Read-TrimmedFile (Join-Path $dir 'VERSION')
                $detail = "behind $behind commit(s); installed version $myVersion, upstream version $upVersion"
                Write-Host "  $name - commits not installed yet:" -ForegroundColor Yellow
                & git -C $dir log --oneline --max-count=10 'HEAD..@{u}' 2>$null | ForEach-Object { Write-Host "      $_" }
                if ($ahead -gt 0) { $status = 'Diverged'; $detail = "behind $behind, ahead $ahead; not pulled" }
                elseif ((Get-GitText $dir @('status', '--porcelain', '--untracked-files=no'))) { $detail += '; NOT updated: uncommitted changes to tracked files' }
                else { $action = 'Pull' }
            }
            elseif (-not $marker -or -not $head -or $marker.commit -ne $head) { $status = 'NeedsBuild'; $action = 'Build'; if (-not $detail) { $detail = 'the built files do not match this source' } }
            else { $status = 'UpToDate'; $detail = "version $($marker.version), commit $($head.Substring(0, 7))" }
        }

        if ($action -ne 'None' -and -not $hasSdk) {
            $detail = "would be $status; a .NET SDK 8 or later is needed to build it (install one, then run this script again)"
            $status = 'NoDotnetSdk'; $action = 'None'
        }

        if (-not $Check -and $action -ne 'None') {
            $go = $true
            if (-not $Force) {
                $what = if ($action -eq 'Clone') { "Clone $url and build it" } elseif ($action -eq 'Pull') { "Update $name (git pull, then build)" } else { "Build $name" }
                $answer = Read-Host "  $what in $dir ? (y/N)"
                $go = $answer -match '^[Yy]$'
            }
            if (-not $go) { $detail = 'skipped by you' }
            else {
                $ok = $true
                if ($action -eq 'Clone') {
                    New-Item -ItemType Directory -Path $toolkitsRoot -Force | Out-Null
                    $out = & git clone --quiet $url $dir 2>&1 | ForEach-Object { "$_" } | Out-String
                    if ($LASTEXITCODE -ne 0) { $ok = $false; $status = 'CloneFailed'; $detail = $out.Trim() }
                }
                elseif ($action -eq 'Pull') {
                    $out = & git -C $dir pull --ff-only --quiet 2>&1 | ForEach-Object { "$_" } | Out-String
                    if ($LASTEXITCODE -ne 0) { $ok = $false; $status = 'PullFailed'; $detail = $out.Trim() }
                }
                if ($ok) {
                    $buildScript = Join-Path $dir 'scripts\agent\Build-Toolkit.ps1'
                    if (-not (Test-Path -LiteralPath $buildScript)) { $status = 'NoBuildScript'; $detail = "$buildScript not found" }
                    else {
                        Write-Host "  Building $name ..." -ForegroundColor Cyan
                        & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File $buildScript 2>&1 | ForEach-Object { Write-Host "      $_" }
                        $buildExit = $LASTEXITCODE
                        $marker = Read-ToolkitMarker $dir
                        if ($buildExit -ne 0 -or -not $marker) { $status = 'BuildFailed'; $detail = "Build-Toolkit.ps1 exited with code $buildExit; see the output above" }
                        else { $status = 'UpToDate'; $detail = "version $($marker.version), commit $($marker.commit.Substring(0, 7))" }
                    }
                }
            }
        }

        if ($status -in 'CloneFailed', 'PullFailed', 'NoBuildScript', 'BuildFailed') { $toolkitFailed = $true }
        $toolkitResults += [pscustomobject]@{ Name = $name; Status = $status }
        $line = "TOOLKIT: $name $status"
        if ($detail) { $line += " ($detail; used by $($usedBy -join ', '))" } else { $line += " (used by $($usedBy -join ', '))" }
        Write-Host $line
    }
    if ($null -eq $savedPrompt) { Remove-Item Env:\GIT_TERMINAL_PROMPT -ErrorAction SilentlyContinue } else { $env:GIT_TERMINAL_PROMPT = $savedPrompt }
}

if ($Check) {
    # Maintainer aid: is skills-index.json in step with the SKILL.md files? Does not change RESULT.
    $indexScript = Join-Path $repoRoot 'scripts\Update-SkillsIndex.ps1'
    if (Test-Path -LiteralPath $indexScript) { & $indexScript -Check | Out-Null }
    if ($recordedRepo -eq $repoRoot) { Write-Host "SOURCE: Recorded ($repoRoot)" }
    elseif ($recordedRepo) { Write-Host "SOURCE: Differs (recorded $recordedRepo; this clone is $repoRoot; run the installer to update it)" }
    else { Write-Host "SOURCE: NotRecorded (run the installer once to record this clone's path)" }
    $parts = @()
    if ($skillsNeedingUpdate.Count -gt 0) { $parts += "local: $($skillsNeedingUpdate.Count) skill(s): $($skillsNeedingUpdate -join ', ')" }
    if ($remoteTouched.Count -gt 0) { $parts += "remote: not pulled yet, touches $($remoteTouched -join ', ')" }
    $toolkitsPending = @($toolkitResults | Where-Object { $_.Status -ne 'UpToDate' })
    if ($toolkitsPending.Count -gt 0) { $parts += "toolkits: $(($toolkitsPending | ForEach-Object { "$($_.Name) $($_.Status)" }) -join ', ')" }
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
    if ($toolkitFailed) {
        Write-Host "A toolkit could not be installed or built; see the TOOLKIT: lines above." -ForegroundColor Red
        exit 1
    }
}