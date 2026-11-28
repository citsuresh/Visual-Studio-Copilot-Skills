<#
.SYNOPSIS
    READ-ONLY: for each open Visual Studio window (or one -Hwnd), reports whether the agent theme is installed and the plan for
    showing that window in the agent theme while it is orchestrated. Changes no theme.

.DESCRIPTION
    Run once when the orchestrator skill starts. It never opens a dialog, never types and takes no focus; it reads files only:
      - the open devenv.exe windows (handle, process, title) and the folder of each devenv.exe;
      - the extension manifests of that folder and of every per-user extensions folder, to see whether a theme extension
        ("Green Light") is installed. Built-in themes (for example "Sunny Day") are not files that can be listed, so their
        availability is only verified when the Options dropdown is read at switch time.
    The theme is installed globally and switched at runtime only. The CURRENT theme of a window is not read here: it is read from
    the Options dialog at switch time (the live step), recorded in the state file, and restored afterwards.

    When the theme is switched: ONLY while a window is being orchestrated. It is switched when orchestration of that window begins,
    when the window is idle, and restored when orchestration ends, including on errors, cancellation and early exits. It is never
    changed at any other time. This script only reports the plan.

    The plan: the person's preferred theme (default "Green Light"), then the fallback (default "Sunny Day"). A preferred theme that
    is an extension and is missing is skipped with one notice (never an error, never a block). Nothing changes when the current
    theme is already one of the agent themes, when the plan is disabled or when no candidate is available. The person can ask for
    a different agent theme: -SetPreference writes %USERPROFILE%\.copilot\agent-theme.json (write it only when the person asks).
    Leftover entries in the state file of an earlier run are reported as stale (an orchestration that did not restore).

.PARAMETER Hwnd
    One window handle (for example 0x2A04F6). Without it every open Visual Studio window is reported.

.PARAMETER Theme
    Preferred agent theme for this run only (default: the preference file, else "Green Light").

.PARAMETER Fallback
    Fallback agent theme for this run only (default: the preference file, else "Sunny Day").

.PARAMETER SetPreference
    Write the preferred agent theme to the preference file and stop (use only when the person asked for it).

.PARAMETER SetFallback
    With -SetPreference: also write the fallback theme.

.PARAMETER PreferenceFile
    Preference file (default %USERPROFILE%\.copilot\agent-theme.json).

.PARAMETER StateFile
    State file of orchestrated windows (default %LOCALAPPDATA%\AgentUi\theme-state.json); only read here.

.PARAMETER AsJson
    Print the result as JSON.
#>
[CmdletBinding()]
param(
    [string]$Hwnd,
    [string]$Theme,
    [string]$Fallback,
    [string]$SetPreference,
    [string]$SetFallback,
    [string]$PreferenceFile = (Join-Path $env:USERPROFILE '.copilot\agent-theme.json'),
    [string]$StateFile = (Join-Path $env:LOCALAPPDATA 'AgentUi\theme-state.json'),
    [switch]$AsJson
)
$ErrorActionPreference = 'Stop'

# The logic (names, scan, preference, plan, stale state) is shared with Set-AgentWindowTheme.ps1; it is tested offline in
# scripts\agent\Test-AgentThemeStatus.ps1 and scripts\agent\Test-AgentWindowTheme.ps1.
. (Join-Path $PSScriptRoot 'AgentTheme.ps1')

# ---- reading the machine (not run offline) ----
if ($SetPreference) {
    $err = Set-ThemePreference -Path $PreferenceFile -Theme $SetPreference -Fallback $SetFallback
    $r = [pscustomobject]@{ Written = (-not $err); Error = $err; File = $(if (-not $err) { $PreferenceFile } else { $null }) }
    if ($AsJson) { $r | ConvertTo-Json -Compress } else { $r }
    return
}

$pref = Get-ThemePreference -Path $PreferenceFile
if ($Theme) { if (Test-ThemeName $Theme) { $pref.Theme = $Theme.Trim() } else { throw '-Theme must be 1 to 60 plain characters.' } }
if ($Fallback) { if (Test-ThemeName $Fallback) { $pref.Fallback = $Fallback.Trim() } else { throw '-Fallback must be 1 to 60 plain characters.' } }

$processes = @(Get-Process devenv -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 })
if ($Hwnd) {
    $want = [Convert]::ToInt64($Hwnd, 16)
    $processes = @($processes | Where-Object { [int64]$_.MainWindowHandle -eq $want })
    if ($processes.Count -eq 0) { throw "No Visual Studio window with handle $Hwnd was found." }
}
# Per-user extension folders of every Visual Studio settings folder (a theme installed for the current user lands in one of them).
$userRoots = @()
$settingsRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\VisualStudio'
if (Test-Path -LiteralPath $settingsRoot) { foreach ($d in @(Get-ChildItem -LiteralPath $settingsRoot -Directory -ErrorAction SilentlyContinue)) { $userRoots += (Join-Path $d.FullName 'Extensions') } }
$scanCache = @{}
$instances = @(); $notices = New-Object System.Collections.ArrayList
foreach ($p in $processes) {
    $path = ''
    try { $path = $p.MainModule.FileName } catch { }
    $ide = if ($path) { Split-Path -Parent $path } else { '' }
    $roots = @($userRoots); if ($ide) { $roots += (Join-Path $ide 'Extensions'); $roots += (Join-Path $ide 'CommonExtensions') }
    $rootKey = ($roots -join '|')
    if (-not $scanCache.ContainsKey($rootKey)) { $scanCache[$rootKey] = Find-ThemeExtension -Roots $roots -DisplayName 'Green Light' }
    $greenInstalled = ($scanCache[$rootKey] -gt 0)
    $hint = if ($ide) { 'Install it with: "' + (Join-Path $ide 'VSIXInstaller.exe') + '" "<path to GreenLight.vsix>", then start the orchestrator again.' } else { '' }
    $plan = Resolve-AgentThemePlan -Original $null -Theme $pref.Theme -Fallback $pref.Fallback -Enabled $pref.Enabled -Installed @{ greenlight = $greenInstalled } -InstallHint $hint
    if ($plan.Notice -and -not $notices.Contains($plan.Notice)) { [void]$notices.Add($plan.Notice) }
    $instances += [pscustomobject]@{
        Hwnd = ('0x{0:X}' -f [int64]$p.MainWindowHandle); ProcessId = [int]$p.Id; Title = [string]$p.MainWindowTitle
        VisualStudioFolder = $ide; GreenLightInstalled = $greenInstalled; Plan = $plan
    }
}
$stale = @(Get-StaleThemeState -Path $StateFile)
$result = [pscustomobject]@{
    ReadOnly = $true
    ThemeChangedOnlyDuringOrchestration = $true
    Preference = $pref
    Instances = $instances
    Notices = @($notices)
    StaleState = $stale
}
if ($AsJson) { $result | ConvertTo-Json -Depth 8 -Compress } else { $result }
