param([string]$ScriptPath = (Join-Path $PSScriptRoot '..\..\agent-orchestrator\scripts\Get-AgentThemeStatus.ps1'), [string]$LibraryPath = (Join-Path $PSScriptRoot '..\..\agent-orchestrator\scripts\AgentTheme.ps1'))
# Offline test of the agent-theme status and plan logic. Everything runs on fixtures in a temp folder; no theme is changed and no
# dialog is opened. The live smoke run only checks that the script is read-only and returns its fields.
$ErrorActionPreference = 'Stop'
$resolved = (Resolve-Path $ScriptPath).Path
$lib = (Resolve-Path $LibraryPath).Path
$ast = [Management.Automation.Language.Parser]::ParseFile($lib, [ref]$null, [ref]$null)
$script:assertions = 0
function Assert-True([bool]$Condition, [string]$Message) { $script:assertions++; if (-not $Condition) { throw $Message } }
foreach ($name in @('ConvertTo-ThemeKey', 'Test-ThemeName', 'Find-ThemeExtension', 'Get-ThemePreference', 'Set-ThemePreference', 'Resolve-AgentThemePlan', 'Get-StaleThemeState')) {
    $fn = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    if (-not $fn) { throw "Missing function: $name" }
    . ([scriptblock]::Create($fn.Extent.Text))
}
$dir = Join-Path $env:TEMP ('agent-theme-test-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory $dir | Out-Null
$enc = New-Object Text.UTF8Encoding($false)
try {
    # Names
    Assert-True ((ConvertTo-ThemeKey 'Green Light') -eq 'greenlight' -and (ConvertTo-ThemeKey 'green-light') -eq 'greenlight') 'Display name and id must give the same key.'
    Assert-True ((ConvertTo-ThemeKey 'light') -ne (ConvertTo-ThemeKey 'Green Light')) '"light" is not Green Light.'
    Assert-True ((Test-ThemeName 'Green Light') -and (Test-ThemeName "Sunny Day") -and (Test-ThemeName "Icy-Mint 2.0")) 'Plain theme names must be accepted.'
    Assert-True (-not (Test-ThemeName '') -and -not (Test-ThemeName 'a;b') -and -not (Test-ThemeName 'x"y') -and -not (Test-ThemeName ('a' * 61)) -and -not (Test-ThemeName $null)) 'Empty, long and special-character names must be refused.'

    # Extension scan
    $ext = Join-Path $dir 'Extensions'
    foreach ($f in @(@('a', 'Green Light'), @('b', 'Dark Green Forest'), @('c', 'GreenLight'))) {
        New-Item -ItemType Directory (Join-Path $ext $f[0]) | Out-Null
        [IO.File]::WriteAllText((Join-Path $ext "$($f[0])\extension.vsixmanifest"), "<PackageManifest><Metadata><DisplayName>$($f[1])</DisplayName></Metadata></PackageManifest>", $enc)
    }
    Assert-True ((Find-ThemeExtension -Roots @($ext) -DisplayName 'Green Light') -eq 2) 'Green Light and GreenLight must be found, "Dark Green Forest" must not.'
    Assert-True ((Find-ThemeExtension -Roots @((Join-Path $dir 'nope'), $null) -DisplayName 'Green Light') -eq 0) 'A missing root must count as none, not fail.'

    # Preference
    $pf = Join-Path $dir 'agent-theme.json'
    $p = Get-ThemePreference -Path $pf
    Assert-True ($p.Theme -eq 'Green Light' -and $p.Fallback -eq 'Sunny Day' -and $p.Enabled -and -not $p.Note) 'Without a file the defaults apply.'
    [IO.File]::WriteAllText($pf, '{"theme":"Icy Mint","fallback":"Cool Breeze","enabled":false}', $enc)
    $p = Get-ThemePreference -Path $pf
    Assert-True ($p.Theme -eq 'Icy Mint' -and $p.Fallback -eq 'Cool Breeze' -and -not $p.Enabled) 'The person''s preference must be read.'
    [IO.File]::WriteAllText($pf, '{"theme":"bad;name"}', $enc)
    $p = Get-ThemePreference -Path $pf
    Assert-True ($p.Theme -eq 'Green Light' -and $p.Note) 'An invalid name must fall back to the default with a note.'
    [IO.File]::WriteAllText($pf, '{not json', $enc)
    Assert-True ((Get-ThemePreference -Path $pf).Note -match 'not valid JSON') 'Broken JSON must give the defaults with a note.'
    Remove-Item -LiteralPath $pf
    Assert-True ($null -eq (Set-ThemePreference -Path $pf -Theme 'Icy Mint')) 'Writing a valid preference must succeed.'
    $p = Get-ThemePreference -Path $pf
    Assert-True ($p.Theme -eq 'Icy Mint' -and $p.Fallback -eq 'Sunny Day') 'A written theme must be read back and keep the fallback.'
    Assert-True ($null -eq (Set-ThemePreference -Path $pf -Theme 'Green Light' -Fallback 'Cool Breeze')) 'Writing theme and fallback must succeed.'
    Assert-True ((Get-ThemePreference -Path $pf).Fallback -eq 'Cool Breeze') 'The written fallback must be read back.'
    $before = [IO.File]::ReadAllText($pf)
    Assert-True ($null -ne (Set-ThemePreference -Path $pf -Theme 'x;y')) 'An invalid name must be refused.'
    Assert-True ([IO.File]::ReadAllText($pf) -ceq $before) 'A refused write must leave the file untouched.'

    # The plan
    $hint = 'HINT'
    $plan = Resolve-AgentThemePlan -Original 'light' -Theme 'Green Light' -Fallback 'Sunny Day' -Installed @{ greenlight = $true } -InstallHint $hint
    Assert-True ($plan.Action -eq 'Switch' -and $plan.Target -eq 'Green Light' -and $plan.Reason -eq 'PreferredAvailable' -and -not $plan.NeedsOriginal -and -not $plan.Notice) 'An installed Green Light is the target.'
    $plan = Resolve-AgentThemePlan -Original 'light' -Theme 'Green Light' -Fallback 'Sunny Day' -Installed @{ greenlight = $false } -InstallHint $hint
    Assert-True ($plan.Action -eq 'Switch' -and $plan.Target -eq 'Sunny Day' -and $plan.Reason -eq 'PreferredMissingUsingFallback') 'A missing Green Light must use the fallback.'
    Assert-True ($plan.Notice -match 'not installed' -and $plan.Notice -match 'Sunny Day' -and $plan.Notice -match 'HINT') 'The notice must say what is missing, what is used, and how to install.'
    foreach ($o in 'green-light', 'Green Light', 'sunny-day', 'Sunny Day') {
        $plan = Resolve-AgentThemePlan -Original $o -Theme 'Green Light' -Fallback 'Sunny Day' -Installed @{ greenlight = $true }
        Assert-True ($plan.Action -eq 'None' -and $plan.Reason -eq 'AlreadyAgentTheme') "An original of '$o' must change nothing and write no restore entry."
    }
    $plan = Resolve-AgentThemePlan -Original $null -Theme 'Green Light' -Fallback 'Sunny Day' -Installed @{ greenlight = $true }
    Assert-True ($plan.Action -eq 'Switch' -and $plan.NeedsOriginal) 'Without a known original the plan is provisional and asks for it.'
    $plan = Resolve-AgentThemePlan -Original 'light' -Theme 'Green Light' -Fallback 'Sunny Day' -Enabled $false -Installed @{ greenlight = $true }
    Assert-True ($plan.Action -eq 'None' -and $plan.Reason -eq 'Disabled') 'A disabled plan changes nothing.'
    $plan = Resolve-AgentThemePlan -Original 'light' -Theme 'Green Light' -Fallback 'Sunny Day' -Installed @{ greenlight = $false; sunnyday = $false } -InstallHint $hint
    Assert-True ($plan.Action -eq 'None' -and $plan.Reason -eq 'NothingAvailable' -and $plan.Notice -match 'unchanged') 'With nothing available the theme stays unchanged with one notice.'
    $plan = Resolve-AgentThemePlan -Original 'light' -Theme 'Icy Mint' -Fallback 'Sunny Day' -Installed @{ greenlight = $false }
    Assert-True ($plan.Action -eq 'Switch' -and $plan.Target -eq 'Icy Mint' -and $plan.Candidates[0].Availability -eq 'BuiltInUnverified') 'A theme the person asked for is used; a built-in is verified at switch time.'
    $plan = Resolve-AgentThemePlan -Original 'light' -Theme 'Sunny Day' -Fallback 'sunny-day' -Installed @{}
    Assert-True (@($plan.Candidates).Count -eq 1) 'The same theme as theme and fallback is listed once.'
    $plan = Resolve-AgentThemePlan -Original 'light' -Theme 'Green Light' -Fallback 'Cool Breeze' -Installed @{ greenlight = $false }
    Assert-True ($plan.Target -eq 'Cool Breeze' -and $plan.Reason -eq 'PreferredMissingUsingFallback') 'The person''s own fallback is used when Green Light is missing.'

    # Stale state
    $sf = Join-Path $dir 'theme-state.json'
    Assert-True (@(Get-StaleThemeState -Path $sf).Count -eq 0) 'No state file means nothing stale.'
    $now = [datetime]::Parse('2026-11-28T12:00:00Z').ToUniversalTime()
    $state = '{"entries":[{"hwnd":"0x1","pid":111,"original":"light","at":"2026-11-28T11:00:00Z"},{"hwnd":"0x2","pid":222,"original":"dark","at":"2026-11-28T11:30:00Z"},{"hwnd":"0x3","pid":333,"original":"light","at":"2026-11-27T01:00:00Z"}]}'
    [IO.File]::WriteAllText($sf, $state, $enc)
    $alive = { param($id) $id -ne 111 }
    $stale = @(Get-StaleThemeState -Path $sf -IsAlive $alive -Now $now)
    Assert-True ($stale.Count -eq 2) "A gone process and an entry older than 12 hours are stale; a fresh live one is not: got $($stale.Count)."
    Assert-True ((@($stale | Where-Object { $_.Pid -eq 111 })[0].Why) -match 'gone' -and (@($stale | Where-Object { $_.Pid -eq 333 })[0].Why) -match 'older') 'Each stale entry must say why.'
    [IO.File]::WriteAllText($sf, '{broken', $enc)
    Assert-True ((@(Get-StaleThemeState -Path $sf))[0].Why -match 'not valid JSON') 'A broken state file must be reported, not ignored.'

    # No hive or root-suffix logic: the plan is the same for whichever instance is the target
    $code = [IO.File]::ReadAllText($resolved) + [IO.File]::ReadAllText($lib)
    Assert-True ($code -notmatch '(?i)rootsuffix|Get-VsHiveName|isolation\.ini|settings\.json') 'The script must not special-case a hive, a root suffix or a settings file.'

    # The script end to end: read-only, returns its fields, theme preference file written only on request
    $settingsFiles = @(Get-ChildItem "$env:LOCALAPPDATA\Microsoft\VisualStudio" -Recurse -Filter settings.json -Depth 2 -ErrorAction SilentlyContinue)
    $hashBefore = ($settingsFiles | ForEach-Object { (Get-FileHash $_.FullName -Algorithm SHA1).Hash }) -join ','
    $json = & powershell -NoProfile -File $resolved -AsJson -PreferenceFile (Join-Path $dir 'none.json') -StateFile (Join-Path $dir 'none-state.json') 2>&1 | Out-String
    $obj = $json.Trim() | ConvertFrom-Json
    Assert-True ($obj.ReadOnly -eq $true -and $obj.ThemeChangedOnlyDuringOrchestration -eq $true -and $null -ne $obj.Preference -and $null -ne $obj.Instances) "The script must return its fields: $json"
    $hashAfter = ($settingsFiles | ForEach-Object { (Get-FileHash $_.FullName -Algorithm SHA1).Hash }) -join ','
    Assert-True ($hashBefore -ceq $hashAfter) 'The read-only run must not change any settings file.'
    Assert-True (-not (Test-Path (Join-Path $dir 'none.json'))) 'The read-only run must not write the preference file.'
    $w = & powershell -NoProfile -File $resolved -SetPreference 'Icy Mint' -PreferenceFile (Join-Path $dir 'set.json') -AsJson 2>&1 | Out-String
    Assert-True ((($w.Trim() | ConvertFrom-Json).Written -eq $true) -and ((Get-ThemePreference -Path (Join-Path $dir 'set.json')).Theme -eq 'Icy Mint')) 'The script must write the preference on request.'
}
finally { [IO.Directory]::Delete($dir, $true) }
Write-Host "PASS: $script:assertions assertions; names and keys, extension scan, preference read and write, the plan (installed, missing with fallback, already an agent theme, unknown original, disabled, nothing available, the person's own theme), stale state, no hive or root-suffix logic, read-only run."
