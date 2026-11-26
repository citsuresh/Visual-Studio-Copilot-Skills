<#
.SYNOPSIS
Tests speech failure/availability and auto-TTS forwarding without producing audio.
.DESCRIPTION
Mocks speech creation and availability. Creates and removes only a unique fixture for the
auto-TTS wrapper and stub meeting probes. Meeting cases fake the microphone consent entries through
Test-MeetingActive.ps1 -EntrySource and Speak-Text.ps1 -MeetingCheckPath/-SettingsPath, so the real
microphone state and real tts-settings.json are never read; never reads real settings/credentials, changes voices, or sends notifications.
.PARAMETER ScriptsRoot
Directory containing Speak-Text.ps1, Speak-IfAway.ps1 and Test-MeetingActive.ps1; accepts an external reviewed draft.
.PARAMETER TemporaryRoot
Existing directory for the disposable wrapper fixture. Defaults to the system temp directory.
#>
[CmdletBinding()]
param(
    [string]$ScriptsRoot = (Join-Path $PSScriptRoot '..\..\read-aloud\scripts'),
    [string]$TemporaryRoot = [IO.Path]::GetTempPath()
)
$ErrorActionPreference = 'Stop'
$speech = Join-Path $ScriptsRoot 'Speak-Text.ps1'
$global:CopilotSpeechFixture = @{ Mode = 'Success'; Speaks = 0; Disposals = 0 }
$stubRoot = Join-Path (Resolve-Path -LiteralPath $TemporaryRoot).Path ('read-aloud-meeting-stubs-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $stubRoot
trap { Remove-Item -LiteralPath $stubRoot -Recurse -Force -ErrorAction SilentlyContinue; throw $_ }
function New-Stub([string]$Name, [string]$Body) {
    $path = Join-Path $stubRoot $Name
    [IO.File]::WriteAllText($path, $Body)
    return $path
}
$stubNoMeeting = New-Stub 'nomeeting.ps1' "'NoMeeting'`r`nexit 0"
$fakeSynth = [pscustomobject]@{ Volume = 100 }
$fakeSynth | Add-Member ScriptMethod GetInstalledVoices {
    if ($global:CopilotSpeechFixture.Mode -eq 'Enumeration') { throw 'PRIVATE-FAILURE-TEXT' }
    if ($global:CopilotSpeechFixture.Mode -eq 'Empty') { return @() }
    return [pscustomobject]@{ Enabled = $true }
}
$fakeSynth | Add-Member ScriptMethod Speak {
    param($Text)
    $global:CopilotSpeechFixture.Speaks++
    $global:CopilotSpeechFixture.VolumeAtSpeak = $this.Volume
    if ($global:CopilotSpeechFixture.Mode -eq 'Speak') { throw 'PRIVATE-FAILURE-TEXT' }
}
$fakeSynth | Add-Member ScriptMethod Dispose { $global:CopilotSpeechFixture.Disposals++ }
function Add-Type {
    param([string]$AssemblyName)
    if ($AssemblyName -ne 'System.Speech') { throw 'Unexpected assembly load.' }
    if ($global:CopilotSpeechFixture.Mode -eq 'Assembly') { throw 'PRIVATE-FAILURE-TEXT' }
}
function New-Object {
    param([string]$TypeName)
    if ($TypeName -ne 'System.Speech.Synthesis.SpeechSynthesizer') { throw 'Unexpected object creation.' }
    if ($global:CopilotSpeechFixture.Mode -eq 'Initialize') { throw 'PRIVATE-FAILURE-TEXT' }
    return $fakeSynth
}
function Test-Path {
    param([string]$LiteralPath)
    if ($LiteralPath -match 'tts-settings\.json$|tts-duck-state\.txt$') { return $false }
    return Microsoft.PowerShell.Management\Test-Path -LiteralPath $LiteralPath
}
function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
foreach ($case in @(
    @{ Mode = 'Empty'; Reason = 'NoEnabledVoices'; Stage = 'enumerate-voices' },
    @{ Mode = 'Initialize'; Reason = 'OperationFailed'; Stage = 'initialize' },
    @{ Mode = 'Enumeration'; Reason = 'OperationFailed'; Stage = 'enumerate-voices' },
    @{ Mode = 'Speak'; Reason = 'OperationFailed'; Stage = 'speak' }
)) {
    $global:CopilotSpeechFixture.Mode = $case.Mode
    $lines = @(& $speech -Text 'DO-NOT-LOG-ME' -MeetingCheckPath $stubNoMeeting)
    Assert-True ($LASTEXITCODE -eq 2 -and $lines[0] -ceq 'NoVoice') "Legacy failure contract: $($case.Mode)"
    $diagnostic = ($lines[1] -replace '^SpeechDiagnostic: ', '') | ConvertFrom-Json
    Assert-True ($diagnostic.reason -eq $case.Reason -and $diagnostic.stage -eq $case.Stage) "Failure classification: $($case.Mode)"
    Assert-True (($lines -join ' ') -notmatch 'DO-NOT-LOG-ME|PRIVATE-FAILURE-TEXT') 'Diagnostic leaked text.'
    Assert-True ($diagnostic.processBitness -eq 64 -and $diagnostic.action -and $diagnostic.audioTested -eq $false) 'Missing actionable host facts.'
    Write-Output "PASS: $($case.Mode) failure is explicit, bounded and text-free."
}
$global:CopilotSpeechFixture.Mode = 'Assembly'
$lines = @(& $speech -Text 'DO-NOT-LOG-ME' -MeetingCheckPath $stubNoMeeting)
Assert-True ($LASTEXITCODE -eq 1 -and ($lines -join ' ') -match 'SpeechAssemblyUnavailable') 'Assembly startup failure changed.'
Assert-True (($lines -join ' ') -notmatch 'PRIVATE-FAILURE-TEXT') 'Raw startup exception leaked.'
$global:CopilotSpeechFixture.Mode = 'Success'
$before = $global:CopilotSpeechFixture.Speaks
$result = (& $speech -Diagnose) | ConvertFrom-Json
Assert-True ($LASTEXITCODE -eq 0 -and $result.reason -eq 'AvailabilityOnly' -and $result.audioTested -eq $false) 'Availability is not an audible success.'
Assert-True ($global:CopilotSpeechFixture.Speaks -eq $before) 'Diagnose must not speak.'
$null = & $speech -Text 'Mock speech only' -MeetingCheckPath $stubNoMeeting
Assert-True ($LASTEXITCODE -eq 0 -and $global:CopilotSpeechFixture.Speaks -eq $before + 1) 'Existing speech path changed.'
$global:CopilotSpeechFixture.Mode = 'Empty'
$result = (& $speech -Diagnose) | ConvertFrom-Json
Assert-True ($LASTEXITCODE -eq 2 -and $result.reason -eq 'NoEnabledVoices') 'Diagnose failure must remain structured.'
Write-Output 'PASS: assembly failure, non-speaking diagnostics and existing success path.'

# --- Test-MeetingActive.ps1: fake consent entries, never the real registry ---
$probe = Join-Path $ScriptsRoot 'Test-MeetingActive.ps1'
function New-Entry([string]$Name, $Start, $Stop) { [pscustomobject]@{ Name = $Name; LastUsedTimeStart = $Start; LastUsedTimeStop = $Stop } }
$teams = New-Entry 'MSTeams_8wekyb3d8bbwe' 133000000000000000 0
$browser = New-Entry 'C:#Program Files#Google#Chrome#Application#chrome.exe' 133000000000000001 0
$ide = New-Entry 'C:#Program Files#Microsoft Visual Studio#Common7#IDE#devenv.exe' 133000000000000002 0
$voice = New-Entry 'C:#Tools#VoiceType.Host.exe' 133000000000000003 0
$own = New-Entry 'C:#Windows#System32#WindowsPowerShell#v1.0#powershell.exe' 133000000000000004 0
$ended = New-Entry 'C:#Program Files#Zoom#bin#Zoom.exe' 133000000000000005 133000000000000009
$never = New-Entry 'C:#Program Files#Webex#webex.exe' 0 0
$oddName = New-Entry 'C:#Users#jane.doe@example.com#App$1#chat!.exe' 133000000000000006 0
foreach ($case in @(
    @{ Name = 'one conferencing app'; Entries = @($teams); Expect = 'Meeting (MSTeams)' },
    @{ Name = 'NonPackaged path becomes app name'; Entries = @($browser); Expect = 'Meeting (chrome)' },
    @{ Name = 'sorted, deduplicated names'; Entries = @($browser, $teams, $browser); Expect = 'Meeting (chrome, MSTeams)' },
    @{ Name = 'only excluded apps (devenv, VoiceType, own PowerShell)'; Entries = @($ide, $voice, $own); Expect = 'NoMeeting' },
    @{ Name = 'excluded app plus conferencing app'; Entries = @($ide, $teams); Expect = 'Meeting (MSTeams)' },
    @{ Name = 'stopped call (Stop not 0)'; Entries = @($ended); Expect = 'NoMeeting' },
    @{ Name = 'never used (Start 0)'; Entries = @($never); Expect = 'NoMeeting' },
    @{ Name = 'no entries'; Entries = @(); Expect = 'NoMeeting' },
    @{ Name = 'name sanitised, no email or symbols'; Entries = @($oddName); Expect = 'Meeting (chat)' }
)) {
    $entries = $case.Entries
    $lines = @(& $probe -EntrySource { $entries }.GetNewClosure())
    Assert-True ($LASTEXITCODE -eq 0 -and $lines.Count -eq 1 -and $lines[0] -ceq $case.Expect) "Meeting probe '$($case.Name)': got '$($lines -join '|')'"
}
$lines = @(& $probe -ExcludeApps @('msteams*') -EntrySource { @($teams) })
Assert-True ($lines[0] -ceq 'NoMeeting') 'Custom ExcludeApps must replace the default list.'
$lines = @(& $probe -EntrySource { throw 'PRIVATE-FAILURE-TEXT' })
Assert-True ($LASTEXITCODE -eq 0 -and $lines.Count -eq 1 -and $lines[0] -match '^Unknown \(' -and $lines[0] -notmatch 'PRIVATE-FAILURE-TEXT') 'Probe failure must be Unknown and bounded.'
$lines = @(& $probe -EntrySource { @([pscustomobject]@{ Name = 'x.exe'; LastUsedTimeStart = 'abc'; LastUsedTimeStop = 0 }) })
Assert-True ($lines.Count -eq 1 -and $lines[0] -match '^Unknown \(') 'Malformed timestamp must be Unknown.'
$elapsed = (Measure-Command { $null = & $probe -EntrySource { @($teams) } }).TotalMilliseconds
Assert-True ($elapsed -lt 1000) "Probe too slow: $elapsed ms"
Write-Output 'PASS: Test-MeetingActive detection, exclusions, sanitising, Unknown on failure; fake entries only.'

# --- Speak-Text.ps1 meeting modes with a faked synthesizer (no audio) ---
$stubMeeting = New-Stub 'meeting.ps1' "'Meeting (MSTeams)'`r`nexit 0"
$stubUnknown = New-Stub 'unknown.ps1' "'Unknown (RegistryAccess)'`r`nexit 0"
$stubGarbage = New-Stub 'garbage.ps1' "'something unexpected'`r`nexit 0"
$stubThrows = New-Stub 'throws.ps1' "throw 'PRIVATE-FAILURE-TEXT'"
$missingProbe = Join-Path $stubRoot 'does-not-exist.ps1'
function Set-Settings($Json) {
    $path = Join-Path $stubRoot 'meeting-settings.json'
    if ($null -eq $Json) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
    else { [IO.File]::WriteAllText($path, $Json) }
    return $path
}
function Invoke-Speak($Probe, $Json) {
    $global:CopilotSpeechFixture.Mode = 'Success'
    $global:CopilotSpeechFixture.VolumeAtSpeak = $null
    $fakeSynth.Volume = 100
    $before = $global:CopilotSpeechFixture.Speaks
    $settings = Set-Settings $Json
    $lines = @(& $speech -Text 'DO-NOT-LOG-ME' -SettingsPath $settings -MeetingCheckPath $Probe)
    return @{ Lines = $lines; Code = $LASTEXITCODE; Spoke = ($global:CopilotSpeechFixture.Speaks -eq $before + 1); Volume = $global:CopilotSpeechFixture.VolumeAtSpeak }
}
foreach ($case in @(
    @{ Name = 'default (no settings file) mutes'; Json = $null },
    @{ Name = 'meeting:mute'; Json = '{"meeting":"mute"}' },
    @{ Name = 'invalid mode falls back to mute'; Json = '{"meeting":"loud"}' },
    @{ Name = 'unreadable settings fall back to mute'; Json = '{not json' }
)) {
    $r = Invoke-Speak $stubMeeting $case.Json
    Assert-True ($r.Code -eq 0 -and -not $r.Spoke -and $r.Lines.Count -eq 1 -and $r.Lines[0] -ceq 'Silent (Meeting)') "Meeting mute: $($case.Name)"
}
$r = Invoke-Speak $stubMeeting '{"meeting":"off"}'
Assert-True ($r.Code -eq 0 -and $r.Spoke -and $r.Lines.Count -eq 0 -and $r.Volume -eq 100) 'meeting:off must speak normally with no extra output.'
foreach ($case in @(
    @{ Json = '{"meeting":"duck"}'; Percent = 20 },
    @{ Json = '{"meeting":"duck","meetingDuckPercent":45}'; Percent = 45 },
    @{ Json = '{"meeting":"duck","meetingDuckPercent":0}'; Percent = 0 },
    @{ Json = '{"meeting":"duck","meetingDuckPercent":250}'; Percent = 100 },
    @{ Json = '{"meeting":"duck","meetingDuckPercent":-5}'; Percent = 0 },
    @{ Json = '{"meeting":"duck","meetingDuckPercent":"abc"}'; Percent = 20 }
)) {
    $r = Invoke-Speak $stubMeeting $case.Json
    Assert-True ($r.Code -eq 0 -and $r.Spoke -and $r.Volume -eq $case.Percent -and $r.Lines.Count -eq 1 -and $r.Lines[0] -ceq "Spoken (Meeting, ducked to $($case.Percent)%)") "Meeting duck: $($case.Json) -> got '$($r.Lines -join '|')' volume $($r.Volume)"
}
foreach ($probeCase in @(
    @{ Name = 'NoMeeting'; Probe = $stubNoMeeting },
    @{ Name = 'Unknown'; Probe = $stubUnknown },
    @{ Name = 'unexpected output'; Probe = $stubGarbage },
    @{ Name = 'probe throws'; Probe = $stubThrows },
    @{ Name = 'probe missing'; Probe = $missingProbe }
)) {
    foreach ($json in @($null, '{"meeting":"mute"}', '{"meeting":"duck"}')) {
        $r = Invoke-Speak $probeCase.Probe $json
        Assert-True ($r.Code -eq 0 -and $r.Spoke -and $r.Lines.Count -eq 0 -and $r.Volume -eq 100) "Fail open ($($probeCase.Name), $json) must speak unchanged."
        Assert-True (($r.Lines -join ' ') -notmatch 'PRIVATE-FAILURE-TEXT') 'Probe failure text leaked.'
    }
}
# -Diagnose never mutes; a speech failure while ducked keeps the legacy NoVoice contract.
$settings = Set-Settings '{"meeting":"mute"}'
$before = $global:CopilotSpeechFixture.Speaks
$result = (& $speech -Diagnose -SettingsPath $settings -MeetingCheckPath $stubMeeting) | ConvertFrom-Json
Assert-True ($LASTEXITCODE -eq 0 -and $result.reason -eq 'AvailabilityOnly' -and $global:CopilotSpeechFixture.Speaks -eq $before) 'Diagnose must ignore meeting state and not speak.'
$null = Set-Settings '{"meeting":"duck"}'
$global:CopilotSpeechFixture.Mode = 'Speak'
$lines = @(& $speech -Text 'DO-NOT-LOG-ME' -SettingsPath $settings -MeetingCheckPath $stubMeeting)
Assert-True ($LASTEXITCODE -eq 2 -and $lines[0] -ceq 'NoVoice' -and ($lines -join ' ') -notmatch 'Spoken \(Meeting') 'Speech failure during a meeting must keep NoVoice/exit 2 and not claim Spoken.'
$global:CopilotSpeechFixture.Mode = 'Success'
Write-Output 'PASS: Speak-Text meeting mute/duck/off, defaults, clamping, fail-open, Diagnose and failure contract; synthesizer faked.'

$fixture = Join-Path (Resolve-Path -LiteralPath $TemporaryRoot).Path ('read-aloud-test-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $fixture
try {
    Copy-Item -LiteralPath (Join-Path $ScriptsRoot 'Speak-IfAway.ps1') -Destination $fixture
    $check = Join-Path $fixture 'Test-HostVsActive.ps1'
    [IO.File]::WriteAllText($check, "'Inactive'`r`nexit 0")
    [IO.File]::WriteAllText((Join-Path $fixture 'Speak-Text.ps1'), "param([string]`$Text)`r`n'NoVoice'`r`n'SpeechDiagnostic: mocked-safe-diagnostic'`r`nexit 2")
    $result = & (Join-Path $fixture 'Speak-IfAway.ps1') -Text 'DO-NOT-LOG-ME'
    Assert-True ($LASTEXITCODE -eq 2 -and $result -match 'NoVoice.*SpeechDiagnostic: mocked-safe-diagnostic') 'Auto TTS lost failure marker or diagnostics.'
    [IO.File]::WriteAllText($check, "'Active'`r`nexit 0")
    $result = & (Join-Path $fixture 'Speak-IfAway.ps1') -Text 'DO-NOT-LOG-ME'
    Assert-True ($LASTEXITCODE -eq 0 -and $result -ceq 'Silent (Active)') 'Active window must stay silent.'
    [IO.File]::WriteAllText($check, "'Unknown'`r`nexit 3")
    $result = & (Join-Path $fixture 'Speak-IfAway.ps1') -Text 'DO-NOT-LOG-ME'
    Assert-True ($LASTEXITCODE -eq 0 -and $result -ceq 'Silent (Unknown)') 'Unknown host must stay silent.'
    Write-Output 'PASS: auto-TTS preserves diagnostics/exit code and Active/Unknown silence.'
    [IO.File]::WriteAllText($check, "'Inactive'`r`nexit 0")
    foreach ($line in @('Silent (Meeting)', 'Spoken (Meeting, ducked to 20%)')) {
        [IO.File]::WriteAllText((Join-Path $fixture 'Speak-Text.ps1'), "param([string]`$Text)`r`n'$line'`r`nexit 0")
        $result = & (Join-Path $fixture 'Speak-IfAway.ps1') -Text 'DO-NOT-LOG-ME'
        Assert-True ($LASTEXITCODE -eq 0 -and $result -ceq $line) "Auto TTS must forward meeting line: $line"
    }
    [IO.File]::WriteAllText((Join-Path $fixture 'Speak-Text.ps1'), "param([string]`$Text)`r`nexit 0")
    $result = & (Join-Path $fixture 'Speak-IfAway.ps1') -Text 'DO-NOT-LOG-ME'
    Assert-True ($LASTEXITCODE -eq 0 -and $result -ceq 'Spoken (Inactive)') 'Auto TTS without a meeting line must keep Spoken (Inactive).'
    [IO.File]::WriteAllText($check, "'Active'`r`nexit 0")
    [IO.File]::WriteAllText((Join-Path $fixture 'Speak-Text.ps1'), "param([string]`$Text)`r`n'Silent (Meeting)'`r`nexit 0")
    $result = & (Join-Path $fixture 'Speak-IfAway.ps1') -Text 'DO-NOT-LOG-ME'
    Assert-True ($result -ceq 'Silent (Active)') 'Active must still win over the meeting line.'
    Write-Output 'PASS: auto-TTS forwards Silent (Meeting) / Spoken (Meeting, ducked) and keeps Active precedence.'
}
finally {
    Remove-Item -LiteralPath $fixture -Recurse -Force
    Remove-Item -LiteralPath $stubRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Variable -Name CopilotSpeechFixture -Scope Global
}
Write-Output 'PASS: speech regression fixtures; no audible output or notification sent.'