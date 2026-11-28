<#
.SYNOPSIS
    Shows ONE Visual Studio window in the agent theme while it is orchestrated, and restores its original theme afterwards.
    The theme is changed ONLY during orchestration. Best effort: a missing theme or a dialog that cannot be driven never blocks.

.DESCRIPTION
    Begin (default), run when orchestration of the window starts and the window is idle:
      records the window's current theme (read from the Tools > Theme menu) in the state file, switches it to the agent
      theme (the person's preference, default "Green Light"; fallback "Sunny Day" when the first is not in the Tools > Theme menu;
      unchanged, with one warning, when neither is), verifies by reading the menu again (the current theme is the entry whose
      selection state is on), and leaves the menus closed.
      A state-file entry of an earlier run for this window (a crash) is repaired first. A window that already shows an agent theme
      is not changed and gets no entry, except that while another orchestrated window is still running it gets a "shared" entry
      carrying the true original (the setting is shared, so the LAST window to finish restores it).
    -Restore, run when orchestration ends, on EVERY path (success, error, cancellation, early exit; call it from a finally-style
      step): restores the recorded original, verifies by reading the menu again, removes the entry. A failed restore keeps the
      entry, which the next start reports. While another orchestrated window is still running the restore is deferred to it.
    -DryRun: reads and prints what would happen. Opens no menu, takes no focus, writes nothing.
    -Explore: opens the Tools > Theme menu read-only (no theme change; the menu is closed again) and reports the current theme and
      the entries it found, to check the menu on a new Visual Studio build. It needs the same approval as a switch.

    User courtesy (same rules as the senders): one input block at a time, waits for a quiet keyboard and mouse, and gives the
    person's window and focus back afterwards. Refuses a window that is not Visual Studio, the window hosting this script
    (-AllowOwnHost), a window on another virtual desktop and a window that is not idle (Begin only).

    How it works: Tools > Theme lists the themes; the current one reports SelectionItemPattern.IsSelected, and invoking an entry
    applies the theme at once. This was read (not switched) on Visual Studio 18 Insiders. No dialog is used: invoking Tools >
    Options through UI Automation opened nothing, and the automation properties of the Options page are empty until that page
    has loaded. No keys are sent. NOT yet verified: that invoking an entry really switches the theme and that the selection
    state follows it (the first live switch checks both and reverts on any mismatch).

.PARAMETER Hwnd
    The window handle of the Visual Studio window being orchestrated (for example 0x2A04F6).

.PARAMETER Restore
    Restore the recorded original theme (end of orchestration).

.PARAMETER DryRun
    Only print the plan.

.PARAMETER Explore
    Open the Tools > Theme menu read-only and report the current theme and entries.

.PARAMETER Theme
    Preferred agent theme for this run (default: the preference file, else "Green Light").

.PARAMETER Fallback
    Fallback agent theme for this run (default: the preference file, else "Sunny Day").

.PARAMETER PreferenceFile
    Preference file (default %USERPROFILE%\.copilot\agent-theme.json).

.PARAMETER StateFile
    State file (default %LOCALAPPDATA%\AgentUi\theme-state.json).

.PARAMETER AllowOwnHost
    Allow the window that hosts this script. For a deliberate test only.

.PARAMETER IgnoreUserActivity
    Skip the quiet wait. Only when the person says nobody is at the machine.

.PARAMETER QuietSeconds
    Required idle time of the keyboard and mouse (default 3).

.PARAMETER MaxWaitSeconds
    How long to wait for a quiet keyboard before refusing (default 120).

.PARAMETER AsJson
    Print the result as JSON.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Hwnd,
    [switch]$Restore,
    [switch]$DryRun,
    [switch]$Explore,
    [string]$Theme,
    [string]$Fallback,
    [string]$PreferenceFile = (Join-Path $env:USERPROFILE '.copilot\agent-theme.json'),
    [string]$StateFile = (Join-Path $env:LOCALAPPDATA 'AgentUi\theme-state.json'),
    [switch]$AllowOwnHost,
    [switch]$IgnoreUserActivity,
    [ValidateRange(0, 600)][int]$QuietSeconds = 3,
    [ValidateRange(0, 3600)][int]$MaxWaitSeconds = 120,
    [switch]$AsJson
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'AgentTheme.ps1')
$script:clock = [Diagnostics.Stopwatch]::StartNew()

function Write-Result {
    param([string]$Mode, [string]$Result, [string]$Reason, $Details)
    $o = [ordered]@{ Mode = $Mode; Hwnd = $Hwnd; Result = $Result; Reason = $Reason; ElapsedMs = [int]$script:clock.ElapsedMilliseconds }
    if ($Details) { foreach ($p in $Details.PSObject.Properties) { $o[$p.Name] = $p.Value } }
    if ($AsJson) { ([pscustomobject]$o) | ConvertTo-Json -Depth 6 -Compress } else { [pscustomobject]$o }
}

# This process and its ancestors (a parent that started after its child is a recycled PID, so the walk stops).
function Get-CallerProcessIds {
    $ids = New-Object 'System.Collections.Generic.List[int]'
    $pairs = $null
    if ('AgentProcessNative' -as [type]) { $pairs = [AgentProcessNative]::ParentPairs() }
    if ($pairs) {
        $parentOf = @{}
        for ($i = 0; $i + 1 -lt $pairs.Length; $i += 2) { $parentOf[[int]$pairs[$i]] = [int]$pairs[$i + 1] }
        $current = [int]$PID
        if (-not $parentOf.ContainsKey($current)) { throw "Process $PID was not found." }
        $ids.Add($current)
        for ($depth = 0; $depth -lt 32; $depth++) {
            if (-not $parentOf.ContainsKey($current)) { break }
            $parent = $parentOf[$current]
            if (-not $parent -or -not $parentOf.ContainsKey($parent) -or $ids.Contains($parent)) { break }
            $childStart = [AgentProcessNative]::StartTime($current); $parentStart = [AgentProcessNative]::StartTime($parent)
            if ($childStart -gt 0 -and $parentStart -gt $childStart) { break }
            $ids.Add($parent); $current = $parent
        }
        return $ids.ToArray()
    }
    $byId = @{}
    foreach ($process in @(Get-CimInstance Win32_Process -Property ProcessId, ParentProcessId, CreationDate -ErrorAction Stop)) { $byId[[int]$process.ProcessId] = $process }
    $current = $byId[[int]$PID]
    if (-not $current) { throw "Process $PID was not found." }
    $ids.Add([int]$current.ProcessId)
    for ($depth = 0; $depth -lt 32 -and $current.ParentProcessId; $depth++) {
        $parent = $byId[[int]$current.ParentProcessId]
        if (-not $parent -or $parent.CreationDate -gt $current.CreationDate -or $ids.Contains([int]$parent.ProcessId)) { break }
        $ids.Add([int]$parent.ProcessId); $current = $parent
    }
    return $ids.ToArray()
}

# ---- the Tools > Theme menu through UI Automation ----
# Verified read-only on Visual Studio 18 (Insiders): Tools (Alt+T) > Theme lists the themes as menu items; the current one reports
# SelectionItemPattern.IsSelected = True. Selecting an item applies the theme at once and closes the menu. No dialog is involved
# (invoking Tools > Options... through UI Automation opened nothing). The Options page properties (DTE SelectedTheme) are empty
# until that page has loaded, so they are not used. Keyboard keys are never sent.
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$AE = [Windows.Automation.AutomationElement]
$TS = [Windows.Automation.TreeScope]
$CT = [Windows.Automation.ControlType]
$script:ThemeMenuSkip = @('Use system setting', 'Get More Themes')

function Invoke-UiaElement {
    param($Element)
    $p = $null
    if ($Element.TryGetCurrentPattern([Windows.Automation.InvokePattern]::Pattern, [ref]$p)) { $p.Invoke(); return $true }
    if ($Element.TryGetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern, [ref]$p)) { $p.Select(); return $true }
    return $false
}

function Find-PopupMenuItem {
    param([int]$ProcessId, [string]$Name)
    $c = New-Object Windows.Automation.AndCondition((New-Object Windows.Automation.PropertyCondition($AE::NameProperty, $Name)), (New-Object Windows.Automation.PropertyCondition($AE::ProcessIdProperty, $ProcessId)), (New-Object Windows.Automation.PropertyCondition($AE::ControlTypeProperty, $CT::MenuItem)))
    return $AE::RootElement.FindFirst($TS::Descendants, $c)
}

function Get-ThemeMenuEntries {
    param($ThemeItem)
    return @($ThemeItem.FindAll($TS::Descendants, (New-Object Windows.Automation.PropertyCondition($AE::ControlTypeProperty, $CT::MenuItem))))
}

function New-VsOptionsUi {
    param($Window, [int]$ProcessId, [scriptblock]$IdleCheck)
    $script:UiaWindow = $Window; $script:UiaPid = $ProcessId; $script:UiaTools = $null; $script:UiaTheme = $null
    $script:UiaOpenMenu = {
        # Expand Tools, then Theme; returns the Theme item when its entries are readable, else $null. Safe to call when already open.
        if (-not $script:UiaTools) {
            $c = New-Object Windows.Automation.AndCondition((New-Object Windows.Automation.PropertyCondition($AE::NameProperty, 'Tools')), (New-Object Windows.Automation.PropertyCondition($AE::ControlTypeProperty, $CT::MenuItem)))
            $script:UiaTools = $script:UiaWindow.FindFirst($TS::Descendants, $c)
        }
        if (-not $script:UiaTools) { return $null }
        $tp = $null
        if (-not $script:UiaTools.TryGetCurrentPattern([Windows.Automation.ExpandCollapsePattern]::Pattern, [ref]$tp)) { return $null }
        if ($tp.Current.ExpandCollapseState -ne [Windows.Automation.ExpandCollapseState]::Expanded) { $tp.Expand() }
        $deadline = [DateTime]::UtcNow.AddSeconds(6); $theme = $null
        while ([DateTime]::UtcNow -lt $deadline -and -not $theme) { $theme = Find-PopupMenuItem -ProcessId $script:UiaPid -Name 'Theme'; if (-not $theme) { Start-Sleep -Milliseconds 200 } }
        if (-not $theme) { return $null }
        $ep = $null
        if ($theme.TryGetCurrentPattern([Windows.Automation.ExpandCollapsePattern]::Pattern, [ref]$ep)) { if ($ep.Current.ExpandCollapseState -ne [Windows.Automation.ExpandCollapseState]::Expanded) { $ep.Expand() } }
        else { [void](Invoke-UiaElement $theme) }
        $deadline = [DateTime]::UtcNow.AddSeconds(5); $kids = @()
        while ([DateTime]::UtcNow -lt $deadline) { $kids = @(Get-ThemeMenuEntries $theme); if ($kids.Count -gt 0) { break }; Start-Sleep -Milliseconds 200 }
        if ($kids.Count -eq 0) { return $null }
        $script:UiaTheme = $theme
        return $theme
    }
    $ui = @{
        WindowExists = { try { [bool](Get-Process -Id $script:UiaPid -ErrorAction Stop) -and ($script:UiaWindow.Current.ProcessId -eq $script:UiaPid) } catch { $false } }
        IsIdle = $IdleCheck
        OpenDialog = { [bool](& $script:UiaOpenMenu) }
        ReadCurrentTheme = {
            $theme = & $script:UiaOpenMenu; if (-not $theme) { return $null }
            foreach ($k in (Get-ThemeMenuEntries $theme)) {
                $sp = $null
                if ($k.TryGetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern, [ref]$sp)) { if ($sp.Current.IsSelected) { return [string]$k.Current.Name } }
            }
            return $null
        }
        ListThemes = {
            $theme = & $script:UiaOpenMenu; if (-not $theme) { return @() }
            return @(Get-ThemeMenuEntries $theme | ForEach-Object { [string]$_.Current.Name } | Where-Object { $script:ThemeMenuSkip -notcontains $_ })
        }
        SelectTheme = {
            param($name)
            $theme = & $script:UiaOpenMenu; if (-not $theme) { throw 'The Tools > Theme menu was not found.' }
            $item = $null
            foreach ($k in (Get-ThemeMenuEntries $theme)) { if ([string]$k.Current.Name -eq $name) { $item = $k; break } }
            if (-not $item) { throw "'$name' is not in the Tools > Theme menu." }
            [void](Invoke-UiaElement $item)
            Start-Sleep -Milliseconds 700
        }
        CloseDialog = {
            param($apply)
            # Selecting a theme closes the menu itself; this only collapses whatever is still open (nothing is applied or cancelled).
            foreach ($el in @($script:UiaTheme, $script:UiaTools)) {
                if (-not $el) { continue }
                $ep = $null
                try { if ($el.TryGetCurrentPattern([Windows.Automation.ExpandCollapsePattern]::Pattern, [ref]$ep)) { if ($ep.Current.ExpandCollapseState -eq [Windows.Automation.ExpandCollapseState]::Expanded) { $ep.Collapse() } } } catch { }
            }
            $script:UiaTheme = $null
        }
    }
    return $ui
}

# ---- main ----
$mode = if ($Explore) { 'Explore' } elseif ($Restore) { 'Restore' } elseif ($DryRun) { 'DryRun' } else { 'Begin' }
$want = $null; try { $want = [Convert]::ToInt64($Hwnd, 16) } catch { }
$proc = $null
if ($null -ne $want) { $proc = @(Get-Process devenv -ErrorAction SilentlyContinue | Where-Object { [int64]$_.MainWindowHandle -eq $want }) | Select-Object -First 1 }
# A restore for a window that no longer exists must still run: it defers to another orchestrated window or reports WindowGone (rule: restore first, or ask).
if ($null -eq $proc -and $Restore -and -not $DryRun -and -not $Explore) {
    $gone = @{ WindowExists = { $false }; OpenDialog = { $false }; ReadCurrentTheme = { $null }; ListThemes = { @() }; SelectTheme = { param($n) }; CloseDialog = { param($a) } }
    $r = Invoke-AgentThemeRestore -Ui $gone -Hwnd $Hwnd -StateFile $StateFile
    return (Write-Result -Mode 'Restore' -Result $r.Result -Reason $null -Details ([pscustomobject]@{ Original = $r.Original; Warnings = @($r.Warnings) }))
}
if ($null -eq $proc) { return (Write-Result -Mode $mode -Result 'Refused' -Reason 'NotVisualStudioWindow' -Details ([pscustomobject]@{ Warnings = @("$Hwnd is not the main window of a running Visual Studio (devenv.exe). Nothing was touched.") })) }
$pref = Get-ThemePreference -Path $PreferenceFile
if ($Theme) { if (Test-ThemeName $Theme) { $pref.Theme = $Theme.Trim() } else { throw '-Theme must be 1 to 60 plain characters.' } }
if ($Fallback) { if (Test-ThemeName $Fallback) { $pref.Fallback = $Fallback.Trim() } else { throw '-Fallback must be 1 to 60 plain characters.' } }
$ide = ''; try { $ide = Split-Path -Parent $proc.MainModule.FileName } catch { }
$hint = if ($ide) { 'Install it with: "' + (Join-Path $ide 'VSIXInstaller.exe') + '" "<path to GreenLight.vsix>", then start the orchestrator again.' } else { '' }

if ($DryRun) {
    $entries = @(Read-ThemeState -Path $StateFile)
    $mine = @($entries | Where-Object { $_.hwnd -eq $Hwnd })
    $others = @(Get-OtherLiveThemeEntries -Entries $entries -Hwnd $Hwnd -IsAlive { param($id) [bool](Get-Process -Id $id -ErrorAction SilentlyContinue) })
    $extRoots = @(); if ($ide) { $extRoots += (Join-Path $ide 'Extensions'); $extRoots += (Join-Path $ide 'CommonExtensions') }
    $settingsRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\VisualStudio'
    if (Test-Path -LiteralPath $settingsRoot) { foreach ($d in @(Get-ChildItem -LiteralPath $settingsRoot -Directory -ErrorAction SilentlyContinue)) { $extRoots += (Join-Path $d.FullName 'Extensions') } }
    $green = (Find-ThemeExtension -Roots $extRoots -DisplayName 'Green Light') -gt 0
    $plan = Resolve-AgentThemePlan -Original $null -Theme $pref.Theme -Fallback $pref.Fallback -Enabled $pref.Enabled -Installed @{ greenlight = $green } -InstallHint $hint
    $would = if ($Restore) { if ($mine.Count -eq 0) { 'Nothing to restore (no entry for this window).' } elseif ($others.Count -gt 0) { "Defer: $($others.Count) other orchestrated window(s) are still running; this entry would only be removed." } else { "Restore '$($mine[0].original)' and remove the entry." } } else { if ($mine.Count -gt 0) { 'Repair the earlier entry first (restore), then switch.' } else { "Read the current theme from the Options dialog, then $($plan.Action) to '$($plan.Target)' ($($plan.Reason)); the dropdown decides which candidate is really available." } }
    return (Write-Result -Mode 'DryRun' -Result 'Planned' -Reason $plan.Reason -Details ([pscustomobject]@{ Preference = $pref; GreenLightInstalled = $green; Plan = $plan; EntryForThisWindow = $mine; OtherLiveEntries = $others.Count; WouldDo = $would; Warnings = @() }))
}

# Everything below can change the person's screen: load the shared helpers, then apply the courtesy rules.
$agentCursor = Join-Path $PSScriptRoot '..\..\ui-interaction\scripts\AgentCursor.ps1'
if (-not (Test-Path -LiteralPath $agentCursor)) { throw "AgentCursor.ps1 not found at $agentCursor. Install the ui-interaction skill (Install-Skills.ps1)." }
# AgentCursor.ps1 has its own param block with a [switch]$Restore: dot-sourcing it resets OUR $Restore to false (a restore then ran as a
# begin). Keep this script's switches and put them back afterwards.
$savedRestore = [bool]$Restore; $savedExplore = [bool]$Explore; $savedDryRun = [bool]$DryRun
. $agentCursor
$Restore = [switch]$savedRestore; $Explore = [switch]$savedExplore; $DryRun = [switch]$savedDryRun
if (-not $AllowOwnHost) {
    try { $callerIds = @(Get-CallerProcessIds) } catch { return (Write-Result -Mode $mode -Result 'Refused' -Reason 'OwnHostCheckFailed' -Details ([pscustomobject]@{ Warnings = @("Could not read this script's process chain ($($_.Exception.Message)). Nothing was touched; use -AllowOwnHost to skip the check.") })) }
    if ($callerIds -contains [int]$proc.Id) { return (Write-Result -Mode $mode -Result 'Refused' -Reason 'OwnHostWindow' -Details ([pscustomobject]@{ Warnings = @("Window $Hwnd belongs to process $($proc.Id), which hosts this script. Nothing was touched; pass -AllowOwnHost if that is intended.") })) }
}
try { if ('AgentProcessNative' -as [type]) { if ([AgentProcessNative]::IsOnOtherDesktop([IntPtr]$want)) { return (Write-Result -Mode $mode -Result 'Refused' -Reason 'OtherDesktop' -Details ([pscustomobject]@{ Warnings = @("Window $Hwnd is on another virtual desktop. Nothing was touched; ask the person to switch to it.") })) } } } catch { }

$lock = Enter-AgentUiLock
if (-not $lock) { return (Write-Result -Mode $mode -Result 'Refused' -Reason 'UiBusy' -Details ([pscustomobject]@{ Warnings = @('Other agents kept the keyboard and mouse for more than five minutes. Nothing was touched; try again later.') })) }
$context = $null; $stamp = [uint32]0; $point = $null; $quietRefusal = $null
try {
    if (-not $IgnoreUserActivity -and $QuietSeconds -gt 0) {
        $quiet = Wait-AgentUserQuiet -QuietMilliseconds ($QuietSeconds * 1000) -DraftQuietMilliseconds ($QuietSeconds * 2000) -MaxWaitMilliseconds ($MaxWaitSeconds * 1000) -NoCue
        if (-not $quiet.Quiet) { $quietRefusal = "The keyboard or mouse stayed in use ($($quiet.Reason)). Nothing was touched; try again when the person has paused." }
    }
    if ($quietRefusal) { return (Write-Result -Mode $mode -Result 'Refused' -Reason 'UserActive' -Details ([pscustomobject]@{ Warnings = @($quietRefusal) })) }
    $context = Save-AgentUserFocus; $stamp = Get-AgentInputStamp; $point = Get-AgentPointerPosition
    $window = $AE::FromHandle([IntPtr]$want)
    $idle = { $w = & (Join-Path $PSScriptRoot 'Watch-CopilotChatV2.ps1') -Hwnd $Hwnd -QuietSeconds 5 -PollIntervalSeconds 2 -TimeoutSeconds 40 -NoDetail 6>$null; [string]$w.State -eq 'Idle' }
    $ui = New-VsOptionsUi -Window $window -ProcessId ([int]$proc.Id) -IdleCheck $idle
    if ($Explore) {
        $report = [ordered]@{ DialogOpened = $false; CurrentTheme = $null; ThemeCount = 0; Themes = @(); Warnings = @() }
        try {
            $report.DialogOpened = [bool](& $ui.OpenDialog)
            if ($report.DialogOpened) { $report.CurrentTheme = & $ui.ReadCurrentTheme; $t = @(& $ui.ListThemes); $report.ThemeCount = $t.Count; $report.Themes = $t }
            else { $report.Warnings += 'The Tools > Theme menu could not be opened or its entries were not found.' }
        }
        finally { try { & $ui.CloseDialog $false } catch { } }
        return (Write-Result -Mode 'Explore' -Result $(if ($report.DialogOpened) { 'Explored' } else { 'NotExplored' }) -Reason $null -Details ([pscustomobject]$report))
    }
    elseif ($Restore) {
        $r = Invoke-AgentThemeRestore -Ui $ui -Hwnd $Hwnd -StateFile $StateFile
        return (Write-Result -Mode 'Restore' -Result $r.Result -Reason $null -Details ([pscustomobject]@{ Original = $r.Original; Warnings = @($r.Warnings) }))
    }
    else {
        $r = Invoke-AgentThemeBegin -Ui $ui -Hwnd $Hwnd -ProcessId ([int]$proc.Id) -Theme $pref.Theme -Fallback $pref.Fallback -Enabled $pref.Enabled -StateFile $StateFile -InstallHint $hint
        return (Write-Result -Mode 'Begin' -Result $r.Result -Reason $r.Reason -Details ([pscustomobject]@{ Original = $r.Original; Target = $r.Target; UsedFallback = $r.UsedFallback; RestoredEarlier = $r.RestoredEarlier; Warnings = @($r.Warnings) }))
    }
}
finally {
    try { if ($context) { [void](Restore-AgentUserFocus -Context $context -OwnStamp $stamp -OwnPoint $point -HeldHandle ([IntPtr]$want)) } } catch { }
    try { Set-AgentOwnInputStamp } catch { }
    Exit-AgentUiLock $lock
}
