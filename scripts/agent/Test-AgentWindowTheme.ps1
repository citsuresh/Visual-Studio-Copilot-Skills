param(
    [string]$LibraryPath = (Join-Path $PSScriptRoot '..\..\agent-orchestrator\scripts\AgentTheme.ps1'),
    [string]$ScriptPath = (Join-Path $PSScriptRoot '..\..\agent-orchestrator\scripts\Set-AgentWindowTheme.ps1')
)
# Offline test of switching an orchestrated window to the agent theme and restoring it, with a SIMULATED Tools > Theme menu and a state
# file in a temp folder. No real theme is changed and no dialog is opened. The command-line script is only run for its refusals
# and its dry run, which touch nothing.
$ErrorActionPreference = 'Stop'
$script:assertions = 0
function Assert-True([bool]$Condition, [string]$Message) { $script:assertions++; if (-not $Condition) { throw $Message } }
. (Resolve-Path $LibraryPath).Path
$dir = Join-Path $env:TEMP ('agent-window-theme-test-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory $dir | Out-Null
$script:sf = Join-Path $dir 'theme-state.json'
$enc = New-Object Text.UTF8Encoding($false)

# ---- the simulated dialog ----
$script:log = New-Object System.Collections.ArrayList
$script:current = 'Light'; $script:themes = @('Light', 'Dark', 'Blue', 'Green Light', 'Sunny Day')
$script:openFails = $false; $script:selectThrows = $false; $script:selectIgnored = $false; $script:selectWrong = $null
$script:readNull = $false; $script:idle = $true; $script:windowExists = $true; $script:applied = $null; $script:stateAtSelect = $null
$script:alivePids = @(100, 200)
$alive = { param($id) $script:alivePids -contains $id }
function Reset-Sim {
    $script:log.Clear(); $script:current = 'Light'; $script:themes = @('Light', 'Dark', 'Blue', 'Green Light', 'Sunny Day')
    $script:openFails = $false; $script:selectThrows = $false; $script:selectIgnored = $false; $script:selectWrong = $null
    $script:readNull = $false; $script:idle = $true; $script:windowExists = $true; $script:applied = $null; $script:stateAtSelect = $null
    $script:alivePids = @(100, 200)
    if (Test-Path $script:sf) { [IO.File]::Delete($script:sf) }
}
$ui = @{
    WindowExists = { $script:windowExists }
    IsIdle = { $script:idle }
    OpenDialog = { [void]$script:log.Add('open'); if ($script:openFails) { return $false }; return $true }
    ReadCurrentTheme = { if ($script:readNull) { return $null }; return $script:current }
    ListThemes = { return @($script:themes) }
    SelectTheme = {
        param($n)
        [void]$script:log.Add("select:$n")
        $script:stateAtSelect = if (Test-Path $script:sf) { [IO.File]::ReadAllText($script:sf) } else { $null }
        if ($script:selectThrows) { throw 'boom' }
        if ($script:selectWrong) { $script:current = $script:selectWrong; return }
        if (-not $script:selectIgnored) { $script:current = $n }
    }
    CloseDialog = { param($a) [void]$script:log.Add("close:$a"); $script:applied = $a }
}
function Begin-Case { param([string]$Hwnd = '0xA', [int]$ProcessId = 100, [bool]$Enabled = $true) Invoke-AgentThemeBegin -Ui $ui -Hwnd $Hwnd -ProcessId $ProcessId -Theme 'Green Light' -Fallback 'Sunny Day' -Enabled $Enabled -StateFile $script:sf -InstallHint 'HINT' -IsAlive $alive }
function Restore-Case { param([string]$Hwnd = '0xA') Invoke-AgentThemeRestore -Ui $ui -Hwnd $Hwnd -StateFile $script:sf -IsAlive $alive }
function Entries { return ,@(Read-ThemeState -Path $script:sf) }
function Log { $script:log -join ',' }

try {
    # ---- normal begin and restore ----
    Reset-Sim
    $r = Begin-Case
    Assert-True ($r.Result -eq 'Switched' -and $r.Target -eq 'Green Light' -and $r.Original -eq 'Light' -and -not $r.UsedFallback) "A normal begin must switch to Green Light: $($r | ConvertTo-Json -Compress)"
    Assert-True ($script:current -eq 'Green Light' -and $script:applied -eq $true) 'The new theme must be applied and the dialog closed with OK.'
    Assert-True ((Log) -eq 'open,select:Green Light,close:True') "The dialog is opened once and closed: $(Log)"
    Assert-True ($script:stateAtSelect -match '"original":\s*"Light"') 'The original theme must be in the state file BEFORE the switch.'
    Assert-True ((Entries).Count -eq 1 -and (Entries)[0].original -eq 'Light' -and (Entries)[0].target -eq 'Green Light' -and (Entries)[0].pid -eq 100) 'The state entry holds the handle, process, original and target.'
    $script:log.Clear()
    $r = Restore-Case
    Assert-True ($r.Result -eq 'Restored' -and $script:current -eq 'Light' -and -not (Test-Path $script:sf)) 'A restore must bring back the original, verify it and remove the state file.'
    Assert-True ((Log) -eq 'open,select:Light,close:True') "The restore opens and closes the dialog once: $(Log)"

    # ---- fallback when Green Light is not in the list ----
    Reset-Sim; $script:themes = @('Light', 'Dark', 'Sunny Day')
    $r = Begin-Case
    Assert-True ($r.Result -eq 'Switched' -and $r.Target -eq 'Sunny Day' -and $r.UsedFallback -and $r.Reason -eq 'PreferredMissingUsingFallback') 'A missing Green Light must use Sunny Day.'
    Assert-True ((@($r.Warnings) -join ' ') -match 'not in the Tools > Theme menu' -and (@($r.Warnings) -join ' ') -match 'HINT') 'The fallback must be announced with the install hint.'
    # the person's own theme first
    Reset-Sim; $script:themes = @('Light', 'Icy Mint', 'Sunny Day')
    $r = Invoke-AgentThemeBegin -Ui $ui -Hwnd '0xA' -ProcessId 100 -Theme 'Icy Mint' -Fallback 'Sunny Day' -StateFile $script:sf -IsAlive $alive
    Assert-True ($r.Result -eq 'Switched' -and $r.Target -eq 'Icy Mint' -and -not $r.UsedFallback) 'A theme the person asked for must be used first.'
    # the dropdown's own spelling is selected
    Reset-Sim; $script:themes = @('Light', 'green-light')
    $r = Begin-Case
    Assert-True ($r.Result -eq 'Switched' -and $r.Target -eq 'green-light') 'The theme must be selected with the spelling the dropdown lists.'

    # ---- nothing available: unchanged, one warning, never an error ----
    Reset-Sim; $script:themes = @('Light', 'Dark')
    $r = Begin-Case
    Assert-True ($r.Result -eq 'NoChange' -and $r.Reason -eq 'NothingAvailable' -and (@($r.Warnings) -join ' ') -match 'left unchanged') 'With neither theme listed the theme stays unchanged with a warning.'
    Assert-True ((Log) -eq 'open,close:False' -and -not (Test-Path $script:sf) -and $script:current -eq 'Light') 'Nothing is selected, no entry is written and the dialog is cancelled.'

    # ---- already an agent theme ----
    Reset-Sim; $script:current = 'Green Light'
    $r = Begin-Case
    Assert-True ($r.Result -eq 'NoChange' -and $r.Reason -eq 'AlreadyAgentTheme' -and -not (Test-Path $script:sf) -and (Log) -eq 'open,close:False') 'An agent theme already showing must change nothing and write no entry.'
    Reset-Sim; $script:current = 'sunny-day'
    $r = Begin-Case
    Assert-True ($r.Reason -eq 'AlreadyAgentTheme') 'The fallback theme counts as an agent theme too.'

    # ---- last one out ----
    Reset-Sim
    Add-ThemeStateEntry -Path $script:sf -Entry ([pscustomobject]@{ hwnd = '0xB'; pid = 200; original = 'Light'; target = 'Green Light'; shared = $false; at = '2026-11-28T10:00:00Z' })
    $script:current = 'Green Light'
    $r = Begin-Case
    Assert-True ($r.Reason -eq 'AlreadyAgentThemeShared' -and (Entries).Count -eq 2) 'While another orchestration runs, a second window gets a shared entry.'
    $mineA = @(Entries | Where-Object { $_.hwnd -eq '0xA' })[0]
    Assert-True ($mineA.original -eq 'Light' -and $mineA.shared) 'The shared entry carries the TRUE original, not the agent theme.'
    $script:log.Clear()
    $r = Restore-Case -Hwnd '0xB'
    Assert-True ($r.Result -eq 'Deferred' -and $script:current -eq 'Green Light' -and (Log) -eq '') 'The first window to finish must leave the agent theme in place and not open the dialog.'
    Assert-True ((Entries).Count -eq 1 -and (Entries)[0].hwnd -eq '0xA') 'The finished window''s entry is removed; the other stays.'
    $r = Restore-Case -Hwnd '0xA'
    Assert-True ($r.Result -eq 'Restored' -and $script:current -eq 'Light' -and -not (Test-Path $script:sf)) 'The last window to finish restores the true original.'
    # a dead process does not hold the theme
    Reset-Sim; $script:alivePids = @(100)
    Add-ThemeStateEntry -Path $script:sf -Entry ([pscustomobject]@{ hwnd = '0xB'; pid = 200; original = 'Light'; target = 'Green Light'; shared = $false; at = '2026-11-28T10:00:00Z' })
    Add-ThemeStateEntry -Path $script:sf -Entry ([pscustomobject]@{ hwnd = '0xA'; pid = 100; original = 'Light'; target = 'Green Light'; shared = $true; at = '2026-11-28T10:01:00Z' })
    $script:current = 'Green Light'
    $r = Restore-Case -Hwnd '0xA'
    Assert-True ($r.Result -eq 'Restored' -and $script:current -eq 'Light') 'An entry of a dead process must not defer the restore.'

    # ---- best effort: nothing here ever throws or blocks ----
    Reset-Sim; $script:readNull = $true
    $r = Begin-Case
    Assert-True ($r.Result -eq 'NoChange' -and $r.Reason -eq 'OriginalUnknown' -and -not (Test-Path $script:sf) -and (Log) -eq 'open,close:False') 'An unreadable current theme must leave the theme unchanged (a restore could not be recorded).'
    Reset-Sim; $script:openFails = $true
    $r = Begin-Case
    Assert-True ($r.Result -eq 'NoChange' -and $r.Reason -eq 'DialogUnavailable' -and (@($r.Warnings) -join ' ') -match 'could not be driven' -and -not (Test-Path $script:sf)) 'A dialog that cannot be opened warns and continues.'
    Reset-Sim; $script:idle = $false
    $r = Begin-Case
    Assert-True ($r.Result -eq 'Skipped' -and $r.Reason -eq 'NotIdle' -and (Log) -eq '') 'A window that is not idle must not be touched: the dialog is never opened.'
    Reset-Sim
    $r = Begin-Case -Enabled $false
    Assert-True ($r.Result -eq 'NoChange' -and $r.Reason -eq 'Disabled' -and (Log) -eq '') 'A disabled plan touches nothing.'

    # ---- a switch that fails is put back and the dialog is closed ----
    Reset-Sim; $script:selectThrows = $true
    $r = Begin-Case
    Assert-True ($r.Result -eq 'NoChange' -and $r.Reason -eq 'VerifyFailed' -and (Log) -match 'close:False$' -and -not (Test-Path $script:sf) -and $script:current -eq 'Light') 'A selection that throws must close the dialog, keep the original and drop the entry.'
    Reset-Sim; $script:selectIgnored = $true
    $r = Begin-Case
    Assert-True ($r.Reason -eq 'VerifyFailed' -and -not (Test-Path $script:sf)) 'A switch that is not verified is undone and its entry dropped.'
    Reset-Sim; $script:selectWrong = 'Dark'
    $r = Begin-Case
    Assert-True ($r.Reason -eq 'VerifyFailed' -and (Test-Path $script:sf) -and (@($r.Warnings) -join ' ') -match 'could not be confirmed') 'If the original cannot be confirmed after a failed switch the entry is kept.'

    # ---- restore failures keep the entry ----
    Reset-Sim; [void](Begin-Case); $script:selectIgnored = $true; $script:log.Clear()
    $r = Restore-Case
    Assert-True ($r.Result -eq 'Failed' -and (Entries).Count -eq 1 -and (Log) -match 'close:False$') 'A restore that cannot be verified keeps the entry and closes the dialog.'
    Reset-Sim; [void](Begin-Case); $script:windowExists = $false; $script:log.Clear()
    $r = Restore-Case
    Assert-True ($r.Result -eq 'WindowGone' -and (Entries).Count -eq 1 -and (Log) -eq '' -and (@($r.Warnings) -join ' ') -match 'ask the person') 'A restore for a window that is gone keeps the entry and says to ask.'
    Reset-Sim
    $r = Restore-Case
    Assert-True ($r.Result -eq 'NothingToRestore' -and (Log) -eq '') 'A restore with no entry opens nothing.'
    Reset-Sim; [void](Begin-Case); $script:current = 'Light'; $script:log.Clear()
    $r = Restore-Case
    Assert-True ($r.Result -eq 'Restored' -and (Log) -eq 'open,close:False' -and -not (Test-Path $script:sf)) 'If the theme is already the original nothing is selected; the entry is just removed.'

    # ---- an entry of an earlier run is repaired first ----
    Reset-Sim
    Add-ThemeStateEntry -Path $script:sf -Entry ([pscustomobject]@{ hwnd = '0xA'; pid = 100; original = 'Light'; target = 'Green Light'; shared = $false; at = '2026-11-28T09:00:00Z' })
    $script:current = 'Green Light'
    $r = Begin-Case
    Assert-True ($r.Result -eq 'Switched' -and $r.RestoredEarlier -and (Log) -eq 'open,select:Light,close:True,open,select:Green Light,close:True') "A leftover entry must be restored first, then the window switched: $(Log)"
    Assert-True ((Entries).Count -eq 1 -and (Entries)[0].original -eq 'Light') 'After the repair the new entry holds the true original.'

    # ---- list selection and the state file ----
    $c = Select-ThemeFromList -Candidates @('Green Light', 'Sunny Day') -Available @('Dark', 'sunny-day')
    Assert-True ($c.Target -eq 'sunny-day' -and $c.UsedFallback -and $c.Missing[0] -eq 'Green Light') 'The fallback is chosen when the first candidate is not listed.'
    Assert-True ($null -eq (Select-ThemeFromList -Candidates @('A') -Available @()).Target) 'An empty list gives no target.'
    [IO.File]::WriteAllText($script:sf, '{broken', $enc)
    Assert-True ((Read-ThemeState -Path $script:sf).Count -eq 0) 'A broken state file reads as empty.'
    Write-ThemeState -Path $script:sf -Entries @()
    Assert-True (-not (Test-Path $script:sf)) 'Writing no entries removes the state file.'
    Add-ThemeStateEntry -Path $script:sf -Entry ([pscustomobject]@{ hwnd = '0x1'; pid = 1; original = 'a'; target = 'b'; shared = $false; at = 'x' })
    Add-ThemeStateEntry -Path $script:sf -Entry ([pscustomobject]@{ hwnd = '0x1'; pid = 1; original = 'c'; target = 'b'; shared = $false; at = 'x' })
    Assert-True ((Entries).Count -eq 1 -and (Entries)[0].original -eq 'c' -and -not (Test-Path "$($script:sf).tmp")) 'An entry for the same window is replaced, and no temporary file is left.'

    # ---- the command-line script: refusals and the dry run touch nothing ----
    $resolvedScript = (Resolve-Path $ScriptPath).Path
    Reset-Sim
    $out = & powershell -NoProfile -File $resolvedScript -Hwnd 0x1 -AsJson -StateFile $script:sf 2>&1 | Out-String
    $o = $out.Trim() | ConvertFrom-Json
    Assert-True ($o.Result -eq 'Refused' -and $o.Reason -eq 'NotVisualStudioWindow') "A window that is not Visual Studio must be refused: $out"
    $out = & powershell -NoProfile -File $resolvedScript -Hwnd 0x1 -Restore -AsJson -StateFile $script:sf 2>&1 | Out-String
    Assert-True ((($out.Trim() | ConvertFrom-Json).Result) -eq 'NothingToRestore') 'A restore with no entry reports nothing to restore.'
    Add-ThemeStateEntry -Path $script:sf -Entry ([pscustomobject]@{ hwnd = '0x1'; pid = 99999991; original = 'Light'; target = 'Green Light'; shared = $false; at = '2026-11-28T10:00:00Z' })
    $out = & powershell -NoProfile -File $resolvedScript -Hwnd 0x1 -Restore -AsJson -StateFile $script:sf 2>&1 | Out-String
    $o = $out.Trim() | ConvertFrom-Json
    Assert-True ($o.Result -eq 'WindowGone' -and (Entries).Count -eq 1) 'A restore for a window that no longer exists reports WindowGone and keeps the entry.'
    $vs = @(Get-Process devenv -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 }) | Select-Object -First 1
    if ($vs) {
        $settings = @(Get-ChildItem "$env:LOCALAPPDATA\Microsoft\VisualStudio" -Recurse -Filter settings.json -Depth 2 -ErrorAction SilentlyContinue)
        $before = ($settings | ForEach-Object { (Get-FileHash $_.FullName -Algorithm SHA1).Hash }) -join ','
        [IO.File]::Delete($script:sf)
        $hwndText = '0x{0:X}' -f [int64]$vs.MainWindowHandle
        $out = & powershell -NoProfile -File $resolvedScript -Hwnd $hwndText -DryRun -AsJson -StateFile $script:sf -PreferenceFile (Join-Path $dir 'none.json') 2>&1 | Out-String
        $o = $out.Trim() | ConvertFrom-Json
        Assert-True ($o.Result -eq 'Planned' -and $o.Mode -eq 'DryRun' -and $null -ne $o.Plan -and $o.WouldDo) "The dry run must print a plan: $out"
        Assert-True (-not (Test-Path $script:sf) -and (($settings | ForEach-Object { (Get-FileHash $_.FullName -Algorithm SHA1).Hash }) -join ',') -ceq $before) 'The dry run must write no state and change no settings file.'
    }
}
finally { [IO.Directory]::Delete($dir, $true) }
# Source checks for bugs that only a REAL run showed (the simulated dialog cannot): see DESIGN_DECISIONS.
$src = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\..\agent-orchestrator\scripts\Set-AgentWindowTheme.ps1'))
$watch = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\..\agent-orchestrator\scripts\Watch-CopilotChatV2.ps1'))
# 1. AgentCursor.ps1 has its own [switch]$Restore: dot-sourcing it reset this script's $Restore, so a restore ran as a begin.
Assert-True ($src -match '(?s)\$savedRestore\s*=\s*\[bool\]\$Restore.*?\.\s+\$agentCursor.*?\$Restore\s*=\s*\[switch\]\$savedRestore') 'The switches must be saved before and restored after dot-sourcing AgentCursor.ps1.'
# 2. The idle check passes -QuietSeconds to the watcher, which refuses values below its minimum (that read as "not idle").
$min = [int]([regex]::Match($watch, '\[ValidateRange\((\d+),\s*\d+\)\]\s*\[int\]\$QuietSeconds').Groups[1].Value)
$given = [int]([regex]::Match($src, 'Watch-CopilotChatV2\.ps1''\)\s+-Hwnd \$Hwnd -QuietSeconds (\d+)').Groups[1].Value)
Assert-True ($min -gt 0 -and $given -ge $min) "The idle check passes -QuietSeconds $given but the watcher needs at least $min."
# 3. Every helper the menu layer calls must be defined in the script itself (a replaced layer once lost Invoke-UiaElement).
foreach ($fn in 'Invoke-UiaElement', 'Find-PopupMenuItem', 'Get-ThemeMenuEntries', 'New-VsOptionsUi') { Assert-True ($src -match "(?m)^function $fn\b") "$fn must be defined in Set-AgentWindowTheme.ps1." }
# 4. The menu layer keeps its script blocks at script scope (a local variable was not visible once New-VsOptionsUi returned).
Assert-True ($src -notmatch '& \$openMenu') 'The menu opener must not be a local variable of New-VsOptionsUi.'
Write-Host "PASS: $script:assertions assertions; begin and restore against a simulated dialog (state written before the switch, verified, fallback, the person's own theme, nothing available, already an agent theme, unknown original, dialog that cannot open, not idle, disabled, a failed switch put back, restore failures, window gone, repair of an earlier run), last window out, state file, and the command-line refusals and dry run. No theme was changed."
