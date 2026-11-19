<#
.SYNOPSIS
Tests speech failure/availability and auto-TTS forwarding without producing audio.
.DESCRIPTION
Mocks speech creation and availability. Creates and removes only a unique fixture for the
auto-TTS wrapper; never reads real settings/credentials, changes voices, or sends notifications.
.PARAMETER ScriptsRoot
Directory containing Speak-Text.ps1 and Speak-IfAway.ps1; accepts an external reviewed draft.
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
$fakeSynth = [pscustomobject]@{}
$fakeSynth | Add-Member ScriptMethod GetInstalledVoices {
    if ($global:CopilotSpeechFixture.Mode -eq 'Enumeration') { throw 'PRIVATE-FAILURE-TEXT' }
    if ($global:CopilotSpeechFixture.Mode -eq 'Empty') { return @() }
    return [pscustomobject]@{ Enabled = $true }
}
$fakeSynth | Add-Member ScriptMethod Speak {
    param($Text)
    $global:CopilotSpeechFixture.Speaks++
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
    $lines = @(& $speech -Text 'DO-NOT-LOG-ME')
    Assert-True ($LASTEXITCODE -eq 2 -and $lines[0] -ceq 'NoVoice') "Legacy failure contract: $($case.Mode)"
    $diagnostic = ($lines[1] -replace '^SpeechDiagnostic: ', '') | ConvertFrom-Json
    Assert-True ($diagnostic.reason -eq $case.Reason -and $diagnostic.stage -eq $case.Stage) "Failure classification: $($case.Mode)"
    Assert-True (($lines -join ' ') -notmatch 'DO-NOT-LOG-ME|PRIVATE-FAILURE-TEXT') 'Diagnostic leaked text.'
    Assert-True ($diagnostic.processBitness -eq 64 -and $diagnostic.action -and $diagnostic.audioTested -eq $false) 'Missing actionable host facts.'
    Write-Output "PASS: $($case.Mode) failure is explicit, bounded and text-free."
}
$global:CopilotSpeechFixture.Mode = 'Assembly'
$lines = @(& $speech -Text 'DO-NOT-LOG-ME')
Assert-True ($LASTEXITCODE -eq 1 -and ($lines -join ' ') -match 'SpeechAssemblyUnavailable') 'Assembly startup failure changed.'
Assert-True (($lines -join ' ') -notmatch 'PRIVATE-FAILURE-TEXT') 'Raw startup exception leaked.'
$global:CopilotSpeechFixture.Mode = 'Success'
$before = $global:CopilotSpeechFixture.Speaks
$result = (& $speech -Diagnose) | ConvertFrom-Json
Assert-True ($LASTEXITCODE -eq 0 -and $result.reason -eq 'AvailabilityOnly' -and $result.audioTested -eq $false) 'Availability is not an audible success.'
Assert-True ($global:CopilotSpeechFixture.Speaks -eq $before) 'Diagnose must not speak.'
$null = & $speech -Text 'Mock speech only'
Assert-True ($LASTEXITCODE -eq 0 -and $global:CopilotSpeechFixture.Speaks -eq $before + 1) 'Existing speech path changed.'
$global:CopilotSpeechFixture.Mode = 'Empty'
$result = (& $speech -Diagnose) | ConvertFrom-Json
Assert-True ($LASTEXITCODE -eq 2 -and $result.reason -eq 'NoEnabledVoices') 'Diagnose failure must remain structured.'
Write-Output 'PASS: assembly failure, non-speaking diagnostics and existing success path.'

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
}
finally {
    Remove-Item -LiteralPath $fixture -Recurse -Force
    Remove-Variable -Name CopilotSpeechFixture -Scope Global
}
Write-Output 'PASS: speech regression fixtures; no audible output or notification sent.'