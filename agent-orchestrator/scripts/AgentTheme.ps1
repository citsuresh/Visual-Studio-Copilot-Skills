# AgentTheme.ps1 - shared logic for Get-AgentThemeStatus.ps1 and Set-AgentWindowTheme.ps1 (dot-sourced; functions only).
#
# A Visual Studio window that is being orchestrated is shown in an "agent theme" (default "Green Light", fallback "Sunny Day",
# or the person's own choice) and shown in its original theme again afterwards. The theme is switched ONLY during orchestration.
# The current theme of a window is read from the Tools > Theme menu; the state file records it BEFORE the switch so that a crash
# can be repaired at the next start. A theme that is missing never blocks anything.
#
# Begin and restore take $Ui, a hashtable of script blocks that drive the Tools > Theme menu (so the logic is tested without a
# window): OpenDialog -> $true/$false; ReadCurrentTheme -> text; ListThemes -> names; SelectTheme (param $name);
# CloseDialog (param $apply); WindowExists -> $true/$false; IsIdle (optional) -> $true/$false.

# "Green Light", "green-light" and "GreenLight" are the same theme; "light" is a different one.
function ConvertTo-ThemeKey {
    param([string]$Name)
    return (([string]$Name).ToLowerInvariant() -replace '[^a-z0-9]', '')
}

# A theme name is short and plain text (it is printed and typed into a dropdown search, never run).
function Test-ThemeName {
    param([string]$Name)
    return (-not [string]::IsNullOrWhiteSpace($Name)) -and ($Name.Trim().Length -le 60) -and ($Name -match "^[A-Za-z0-9 .'-]+$")
}

# Number of extension manifests under the roots that name the theme as an installed extension.
function Find-ThemeExtension {
    param([string[]]$Roots, [string]$DisplayName = 'Green Light')
    $pattern = '(?i)' + ([regex]::Escape($DisplayName.Trim()) -replace '(\\ )+', '\s*')
    $count = 0
    foreach ($root in @($Roots)) {
        if (-not $root -or -not (Test-Path -LiteralPath $root)) { continue }
        foreach ($manifest in @(Get-ChildItem -LiteralPath $root -Recurse -Filter extension.vsixmanifest -ErrorAction SilentlyContinue)) {
            try { if ([IO.File]::ReadAllText($manifest.FullName) -match $pattern) { $count++ } } catch { }
        }
    }
    return $count
}

# The person's preference: {Theme, Fallback, Enabled, Note}. Missing or invalid values use the defaults.
function Get-ThemePreference {
    param([string]$Path)
    $pref = [pscustomobject]@{ Theme = 'Green Light'; Fallback = 'Sunny Day'; Enabled = $true; Note = $null }
    if (-not (Test-Path -LiteralPath $Path)) { return $pref }
    try { $json = [IO.File]::ReadAllText($Path) | ConvertFrom-Json }
    catch { $pref.Note = 'The preference file is not valid JSON; defaults are used.'; return $pref }
    if ($null -ne $json.theme) { if (Test-ThemeName ([string]$json.theme)) { $pref.Theme = ([string]$json.theme).Trim() } else { $pref.Note = 'The preferred theme name is not valid; the default is used.' } }
    if ($null -ne $json.fallback) { if (Test-ThemeName ([string]$json.fallback)) { $pref.Fallback = ([string]$json.fallback).Trim() } else { $pref.Note = 'The fallback theme name is not valid; the default is used.' } }
    if ($null -ne $json.enabled) { $pref.Enabled = [bool]$json.enabled }
    return $pref
}

# Writes the preference file (only when the person asked). Returns an error text, or $null.
function Set-ThemePreference {
    param([string]$Path, [string]$Theme, [string]$Fallback)
    if (-not (Test-ThemeName $Theme)) { return 'The theme name must be 1 to 60 plain characters (letters, digits, space, . - ''). Nothing was written.' }
    if ($Fallback -and -not (Test-ThemeName $Fallback)) { return 'The fallback name must be 1 to 60 plain characters. Nothing was written.' }
    $current = Get-ThemePreference -Path $Path
    $obj = [ordered]@{ theme = $Theme.Trim(); fallback = $(if ($Fallback) { $Fallback.Trim() } else { $current.Fallback }); enabled = $current.Enabled }
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Force -Path $dir) }
    [IO.File]::WriteAllText($Path, (([pscustomobject]$obj | ConvertTo-Json) + "`r`n"), (New-Object Text.UTF8Encoding($false)))
    return $null
}

# The plan for one window. Installed maps a theme key to $true/$false for themes that are extensions and can be checked from
# files (here 'greenlight'); any other name is a built-in or unknown theme: 'BuiltInUnverified', verified at switch time.
# Original is the window's current theme read from the Tools > Theme menu; when it is not known yet (the status run) the plan is
# provisional (NeedsOriginal) and the live step runs it again with the value it read.
function Resolve-AgentThemePlan {
    param([string]$Original, [string]$Theme, [string]$Fallback, [bool]$Enabled = $true, [hashtable]$Installed = @{}, [string]$InstallHint)
    $plan = [ordered]@{ Action = 'None'; Target = $null; Reason = $null; NeedsOriginal = $false; Candidates = @(); Notice = $null }
    $names = @(); foreach ($n in @($Theme, $Fallback)) { if ($n -and (@($names | ForEach-Object { ConvertTo-ThemeKey $_ }) -notcontains (ConvertTo-ThemeKey $n))) { $names += $n } }
    $cands = @(); foreach ($n in $names) {
        $k = ConvertTo-ThemeKey $n
        $state = if ($Installed.ContainsKey($k)) { if ($Installed[$k]) { 'Installed' } else { 'Missing' } } else { 'BuiltInUnverified' }
        $cands += [pscustomobject]@{ Name = $n; Availability = $state }
    }
    $plan.Candidates = $cands
    if (-not $Enabled) { $plan.Reason = 'Disabled'; return [pscustomobject]$plan }
    if (-not [string]::IsNullOrWhiteSpace($Original)) {
        $originalKey = ConvertTo-ThemeKey $Original
        foreach ($c in $cands) { if ((ConvertTo-ThemeKey $c.Name) -eq $originalKey) { $plan.Reason = 'AlreadyAgentTheme'; return [pscustomobject]$plan } }
    }
    else { $plan.NeedsOriginal = $true }
    $pick = @($cands | Where-Object { $_.Availability -ne 'Missing' }) | Select-Object -First 1
    if ($null -eq $pick) {
        $plan.Reason = 'NothingAvailable'
        $plan.Notice = "None of the agent themes is available ($(($cands | ForEach-Object { $_.Name }) -join ', ')): the theme is left unchanged. $InstallHint".Trim()
        return [pscustomobject]$plan
    }
    $plan.Action = 'Switch'; $plan.Target = $pick.Name
    if ($pick.Name -ne $cands[0].Name -and $cands[0].Availability -eq 'Missing') {
        $plan.Reason = 'PreferredMissingUsingFallback'
        $plan.Notice = "Theme '$($cands[0].Name)' is not installed; using the fallback '$($pick.Name)'. $InstallHint".Trim()
    }
    else { $plan.Reason = 'PreferredAvailable' }
    return [pscustomobject]$plan
}

# The first candidate that the Color theme dropdown really lists (its own spelling is returned, so it can be selected).
function Select-ThemeFromList {
    param([string[]]$Candidates, [string[]]$Available)
    $keys = @{}
    foreach ($a in @($Available)) { if ($a) { $keys[(ConvertTo-ThemeKey $a)] = $a } }
    $i = 0
    foreach ($c in @($Candidates)) {
        $k = ConvertTo-ThemeKey $c
        if ($keys.ContainsKey($k)) { return [pscustomobject]@{ Target = $keys[$k]; UsedFallback = ($i -gt 0); Missing = @($Candidates | Select-Object -First $i) } }
        $i++
    }
    return [pscustomobject]@{ Target = $null; UsedFallback = $false; Missing = @($Candidates) }
}

# ---- state file: one entry per orchestrated window {hwnd, pid, original, target, shared, at} ----

function Read-ThemeState {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    try { $json = [IO.File]::ReadAllText($Path) | ConvertFrom-Json } catch { return @() }
    $out = @()
    foreach ($e in @($json.entries)) {
        if ($null -ne $e) { $out += [pscustomobject]@{ hwnd = [string]$e.hwnd; pid = [int]$e.pid; original = [string]$e.original; target = [string]$e.target; shared = [bool]$e.shared; at = [string]$e.at } }
    }
    return $out
}

# Written through a temporary file and one move, so a crash never leaves half a file. No entries: the file is removed.
function Write-ThemeState {
    param([string]$Path, [object[]]$Entries)
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Force -Path $dir) }
    if (@($Entries).Count -eq 0) { if (Test-Path -LiteralPath $Path) { [IO.File]::Delete($Path) }; return }
    $tmp = "$Path.tmp"
    [IO.File]::WriteAllText($tmp, ([pscustomobject]@{ entries = @($Entries) } | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Add-ThemeStateEntry {
    param([string]$Path, $Entry)
    $entries = @(Read-ThemeState -Path $Path | Where-Object { $_.hwnd -ne $Entry.hwnd })
    $entries += $Entry
    Write-ThemeState -Path $Path -Entries $entries
}

function Remove-ThemeStateEntry {
    param([string]$Path, [string]$Hwnd)
    Write-ThemeState -Path $Path -Entries @(Read-ThemeState -Path $Path | Where-Object { $_.hwnd -ne $Hwnd })
}

# Entries of OTHER windows whose process is still running: other orchestrations that still need the agent theme.
function Get-OtherLiveThemeEntries {
    param([object[]]$Entries, [string]$Hwnd, [scriptblock]$IsAlive)
    return @(@($Entries) | Where-Object { $_.hwnd -ne $Hwnd -and [bool](& $IsAlive $_.pid) })
}

# State-file entries of earlier runs that were not restored: the process is gone, or the entry is older than MaxAgeHours.
function Get-StaleThemeState {
    param([string]$Path, [scriptblock]$IsAlive = { param($id) [bool](Get-Process -Id $id -ErrorAction SilentlyContinue) }, [datetime]$Now = [datetime]::UtcNow, [int]$MaxAgeHours = 12)
    $out = @()
    if (-not (Test-Path -LiteralPath $Path)) { return $out }
    try { $json = [IO.File]::ReadAllText($Path) | ConvertFrom-Json } catch { return @([pscustomobject]@{ Hwnd = $null; Pid = $null; Original = $null; Why = 'The state file is not valid JSON' }) }
    foreach ($e in @($json.entries)) {
        if ($null -eq $e) { continue }
        $why = $null
        $alive = $false; try { $alive = [bool](& $IsAlive ([int]$e.pid)) } catch { }
        if (-not $alive) { $why = 'The window process is gone' }
        else {
            $at = $null; try { $at = ([DateTimeOffset]::Parse([string]$e.at, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal)).UtcDateTime } catch { }
            if ($null -eq $at -or ($Now - $at).TotalHours -gt $MaxAgeHours) { $why = "The entry is older than $MaxAgeHours hours" }
        }
        if ($why) { $out += [pscustomobject]@{ Hwnd = [string]$e.hwnd; Pid = [int]$e.pid; Original = [string]$e.original; Why = $why } }
    }
    return $out
}

# ---- begin and restore (driven through $Ui; tested offline with a simulated dialog) ----

# Restores the recorded original theme of one window, last one out: while another orchestrated window is still running the agent
# theme stays (its entry carries the true original). Result: Restored, Deferred, NothingToRestore, WindowGone or Failed.
# A failed or impossible restore keeps the entry so the next start can report it. The dialog is always closed.
function Invoke-AgentThemeRestore {
    param([hashtable]$Ui, [string]$Hwnd, [string]$StateFile, [scriptblock]$IsAlive = { param($id) [bool](Get-Process -Id $id -ErrorAction SilentlyContinue) })
    $r = [ordered]@{ Result = 'NothingToRestore'; Original = $null; Warnings = @() }
    $entries = @(Read-ThemeState -Path $StateFile)
    $mine = @($entries | Where-Object { $_.hwnd -eq $Hwnd }) | Select-Object -First 1
    if ($null -eq $mine) { return [pscustomobject]$r }
    $r.Original = $mine.original
    $others = @(Get-OtherLiveThemeEntries -Entries $entries -Hwnd $Hwnd -IsAlive $IsAlive)
    if ($others.Count -gt 0) {
        Remove-ThemeStateEntry -Path $StateFile -Hwnd $Hwnd
        $r.Result = 'Deferred'
        return [pscustomobject]$r
    }
    $windowExists = $true; try { $windowExists = [bool](& $Ui.WindowExists) } catch { }
    if (-not $windowExists) {
        $r.Result = 'WindowGone'
        $r.Warnings += "The window $Hwnd is gone, so its theme could not be restored to '$($mine.original)'. The entry is kept: restore it from another window of that Visual Studio, or ask the person."
        return [pscustomobject]$r
    }
    $apply = $false
    try {
        $opened = $false; try { $opened = [bool](& $Ui.OpenDialog) } catch { }
        if (-not $opened) { $r.Result = 'Failed'; $r.Warnings += "The Tools > Theme menu could not be opened to restore '$($mine.original)'. The entry is kept."; return [pscustomobject]$r }
        $current = $null; try { $current = [string](& $Ui.ReadCurrentTheme) } catch { }
        if ($current -and (ConvertTo-ThemeKey $current) -eq (ConvertTo-ThemeKey $mine.original)) {
            Remove-ThemeStateEntry -Path $StateFile -Hwnd $Hwnd; $r.Result = 'Restored'; return [pscustomobject]$r
        }
        try { & $Ui.SelectTheme $mine.original } catch { $r.Warnings += "Selecting '$($mine.original)' failed: $($_.Exception.Message)" }
        $after = $null; try { $after = [string](& $Ui.ReadCurrentTheme) } catch { }
        if ($after -and (ConvertTo-ThemeKey $after) -eq (ConvertTo-ThemeKey $mine.original)) {
            $apply = $true; Remove-ThemeStateEntry -Path $StateFile -Hwnd $Hwnd; $r.Result = 'Restored'
        }
        else { $r.Result = 'Failed'; $r.Warnings += "The theme could not be verified as '$($mine.original)' after the restore. The entry is kept." }
    }
    finally { try { & $Ui.CloseDialog $apply } catch { } }
    return [pscustomobject]$r
}

# Shows one window in an agent theme. Everything is best effort: a missing theme, a dialog that cannot be driven or an unreadable
# current theme leaves the theme unchanged with a warning and never blocks orchestration. The state entry is written BEFORE the
# switch. The dialog is always closed. Result: Switched, NoChange or Skipped.
function Invoke-AgentThemeBegin {
    param(
        [hashtable]$Ui, [string]$Hwnd, [int]$ProcessId, [string]$Theme = 'Green Light', [string]$Fallback = 'Sunny Day', [bool]$Enabled = $true,
        [string]$StateFile, [string]$InstallHint = '', [datetime]$Now = [datetime]::UtcNow,
        [scriptblock]$IsAlive = { param($id) [bool](Get-Process -Id $id -ErrorAction SilentlyContinue) }
    )
    $r = [ordered]@{ Result = 'NoChange'; Reason = $null; Original = $null; Target = $null; UsedFallback = $false; RestoredEarlier = $false; Warnings = @() }
    if (-not $Enabled) { $r.Reason = 'Disabled'; return [pscustomobject]$r }
    # An entry of an earlier run for this window (a crash or an aborted run): repair it first.
    if (@(Read-ThemeState -Path $StateFile | Where-Object { $_.hwnd -eq $Hwnd }).Count -gt 0) {
        $earlier = Invoke-AgentThemeRestore -Ui $Ui -Hwnd $Hwnd -StateFile $StateFile -IsAlive $IsAlive
        $r.RestoredEarlier = $true
        $r.Warnings += "An earlier orchestration of this window had not restored its theme (restore: $($earlier.Result))."
        $r.Warnings += @($earlier.Warnings)
        if ($earlier.Result -eq 'Failed' -or $earlier.Result -eq 'WindowGone') { $r.Reason = 'EarlierRestoreFailed'; return [pscustomobject]$r }
    }
    if ($Ui.ContainsKey('IsIdle')) {
        $idle = $false; try { $idle = [bool](& $Ui.IsIdle) } catch { }
        if (-not $idle) { $r.Result = 'Skipped'; $r.Reason = 'NotIdle'; $r.Warnings += 'The window is not idle, so its theme was not changed.'; return [pscustomobject]$r }
    }
    $apply = $false
    try {
        $opened = $false; try { $opened = [bool](& $Ui.OpenDialog) } catch { $r.Warnings += "The Tools > Theme menu could not be opened: $($_.Exception.Message)" }
        if (-not $opened) { $r.Reason = 'DialogUnavailable'; $r.Warnings += 'The Tools > Theme menu could not be driven, so the theme was left unchanged.'; return [pscustomobject]$r }
        $original = $null; try { $original = [string](& $Ui.ReadCurrentTheme) } catch { }
        if ([string]::IsNullOrWhiteSpace($original)) { $r.Reason = 'OriginalUnknown'; $r.Warnings += 'The current theme could not be read, so the theme was left unchanged (a restore could not be recorded).'; return [pscustomobject]$r }
        $r.Original = $original
        $plan = Resolve-AgentThemePlan -Original $original -Theme $Theme -Fallback $Fallback -Enabled $true -InstallHint $InstallHint
        if ($plan.Reason -eq 'AlreadyAgentTheme') {
            $others = @(Get-OtherLiveThemeEntries -Entries @(Read-ThemeState -Path $StateFile) -Hwnd $Hwnd -IsAlive $IsAlive)
            if ($others.Count -gt 0) {
                # Another orchestration is already showing the agent theme: keep the TRUE original so that the last one out restores it.
                Add-ThemeStateEntry -Path $StateFile -Entry ([pscustomobject]@{ hwnd = $Hwnd; pid = $ProcessId; original = $others[0].original; target = $original; shared = $true; at = $Now.ToString('o') })
                $r.Reason = 'AlreadyAgentThemeShared'
            }
            else { $r.Reason = 'AlreadyAgentTheme' }
            return [pscustomobject]$r
        }
        $available = @(); try { $available = @(& $Ui.ListThemes) } catch { }
        $choice = Select-ThemeFromList -Candidates @($plan.Candidates | ForEach-Object { $_.Name }) -Available $available
        if ($null -eq $choice.Target) {
            $r.Reason = 'NothingAvailable'
            $r.Warnings += "None of the agent themes ($(($plan.Candidates | ForEach-Object { $_.Name }) -join ', ')) is in the Color theme list, so the theme was left unchanged. $InstallHint".Trim()
            return [pscustomobject]$r
        }
        if ($choice.UsedFallback) { $r.Warnings += "Theme '$($choice.Missing[0])' is not in the Tools > Theme menu; using the fallback '$($choice.Target)'. $InstallHint".Trim() }
        Add-ThemeStateEntry -Path $StateFile -Entry ([pscustomobject]@{ hwnd = $Hwnd; pid = $ProcessId; original = $original; target = $choice.Target; shared = $false; at = $Now.ToString('o') })
        try { & $Ui.SelectTheme $choice.Target } catch { $r.Warnings += "Selecting '$($choice.Target)' failed: $($_.Exception.Message)" }
        $after = $null; try { $after = [string](& $Ui.ReadCurrentTheme) } catch { }
        if ($after -and (ConvertTo-ThemeKey $after) -eq (ConvertTo-ThemeKey $choice.Target)) {
            $apply = $true; $r.Result = 'Switched'; $r.Reason = $(if ($choice.UsedFallback) { 'PreferredMissingUsingFallback' } else { 'PreferredAvailable' }); $r.Target = $choice.Target; $r.UsedFallback = $choice.UsedFallback
            return [pscustomobject]$r
        }
        # The switch could not be verified: put things back to the original and drop the entry once that is confirmed.
        $r.Reason = 'VerifyFailed'; $r.Warnings += "The theme could not be verified as '$($choice.Target)'."
        $afterRevert = $after
        if (-not ($afterRevert -and (ConvertTo-ThemeKey $afterRevert) -eq (ConvertTo-ThemeKey $original))) {
            try { & $Ui.SelectTheme $original } catch { }
            try { $afterRevert = [string](& $Ui.ReadCurrentTheme) } catch { $afterRevert = $null }
        }
        if ($afterRevert -and (ConvertTo-ThemeKey $afterRevert) -eq (ConvertTo-ThemeKey $original)) { Remove-ThemeStateEntry -Path $StateFile -Hwnd $Hwnd }
        else { $r.Warnings += "The original theme '$original' could not be confirmed after the failed switch. The entry is kept for the next start." }
        return [pscustomobject]$r
    }
    finally { try { & $Ui.CloseDialog $apply } catch { } }
}
