<#
.SYNOPSIS
    Speaks a short text aloud with the Windows default voice (System.Speech).

.DESCRIPTION
    Used by the read-aloud skill ("enable tts" / "start tts"). Runs in 64-bit Windows PowerShell 5.1
    or PowerShell 7 on Windows.

    The script never sets, selects or prefers a voice: it speaks with the system default voice
    configured in Windows, through the default audio device. If no voice is installed, or the
    default voice cannot speak, it retains the legacy NoVoice marker and exit 2, followed by
    bounded diagnostics that never include the spoken text or raw exception messages.
    -Diagnose checks initialization/voice availability without speaking or touching ducking.

    Optional ducking (off by default): if %USERPROFILE%\.copilot\tts-settings.json contains
    {"duck":true,"duckPercent":25}, the volume of other applications' audio sessions on the default
    output device is lowered to that percentage (default 25) while the text is spoken, then put back.
    AudioDucker.cs (next to this script) is compiled in memory only when ducking is on, or when a
    leftover state file from an interrupted run has to be undone. Ducking never blocks speech: if it
    cannot run, the text is spoken at normal volume. A volume you changed during speech is left alone.
    The volumes are recorded in %USERPROFILE%\.copilot\tts-duck-state.txt while ducked.

    Apart from that temporary state file and the temporary per-application volume, it does not
    change the registry, the installed voices, or any system or user setting.

    Exit codes: 0 = spoken; 1 = could not start (not 64-bit, or System.Speech unavailable);
    2 = NoVoice (no installed voice, or the default voice cannot speak).

.PARAMETER Text
    The text to speak. Required.

.PARAMETER Diagnose
    Read-only JSON diagnostics, without speaking. Availability is not an audible test.

.EXAMPLE
    .\Speak-Text.ps1 -Text "The build succeeded and all tests passed."
#>
[CmdletBinding(DefaultParameterSetName = 'Speak')]
param(
    [Parameter(Mandatory = $true, Position = 0, ParameterSetName = 'Speak')]
    [string]$Text,

    [Parameter(Mandatory = $true, ParameterSetName = 'Diagnose')]
    [switch]$Diagnose
)

$ErrorActionPreference = 'Stop'

function Write-SpeechDiagnostic {
    param([string]$Reason, [string]$Stage, [Exception]$Failure, $EnabledVoiceCount)
    $action = switch ($Reason) {
        'HostBitness' { 'Use a 64-bit PowerShell host under the same Windows account and session.' }
        'SpeechAssemblyUnavailable' { 'Check System.Speech availability in a supported Windows PowerShell host.' }
        'NoEnabledVoices' { 'Check Windows speech settings for a usable default voice under this account and host bitness.' }
        'AvailabilityOnly' { 'Initialization and voice enumeration succeeded; audible output has not been tested.' }
        default { 'Check the default voice, audio output, volume and remote audio routing in the same Windows session.' }
    }
    if ($Reason -ne 'AvailabilityOnly') {
        $action += ' After correcting setup, request one audible retest before claiming recovery.'
    }
    $rootFailure = if ($Failure) { $Failure.GetBaseException() } else { $null }
    $data = [ordered]@{
        reason = $Reason
        stage = $Stage
        processBitness = [IntPtr]::Size * 8
        powerShellVersion = $PSVersionTable.PSVersion.ToString()
        enabledVoiceCount = $EnabledVoiceCount
        exceptionType = $(if ($rootFailure) { $rootFailure.GetType().FullName } else { $null })
        hresult = $(if ($rootFailure) { '0x{0:X8}' -f $rootFailure.HResult } else { $null })
        audioTested = $false
        action = $action
    }
    $json = $data | ConvertTo-Json -Compress
    if ($Diagnose) { Write-Output $json }
    else { Write-Output "SpeechDiagnostic: $json" }
}

# SAPI voices are registered per bitness; a 32-bit host sees a different, usually smaller, list.
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    if (-not $Diagnose) { Write-Output 'Speak-Text.ps1 must run in a 64-bit PowerShell.' }
    Write-SpeechDiagnostic -Reason HostBitness -Stage host
    exit 1
}

try {
    Add-Type -AssemblyName System.Speech
}
catch {
    if (-not $Diagnose) { Write-Output 'System.Speech is not available.' }
    Write-SpeechDiagnostic -Reason SpeechAssemblyUnavailable -Stage assembly -Failure $_.Exception
    exit 1
}

# Returns the duck factor (0..1) when ducking is switched on in the settings file, otherwise $null.
function Get-DuckFactor {
    $settingsPath = Join-Path $env:USERPROFILE '.copilot\tts-settings.json'
    if (-not (Test-Path -LiteralPath $settingsPath)) { return $null }
    try {
        $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
        if ($settings.duck -ne $true) { return $null }
        $percent = 25
        if ($null -ne $settings.duckPercent) { $percent = [double]$settings.duckPercent }
        return [Math]::Min(100, [Math]::Max(0, $percent)) / 100
    }
    catch { return $null }
}

$statePath = Join-Path $env:USERPROFILE '.copilot\tts-duck-state.txt'
$duckFactor = $null
$staleState = $false
if (-not $Diagnose) {
    $duckFactor = Get-DuckFactor
    $staleState = Test-Path -LiteralPath $statePath
}

# Compile the helper only if it is needed; any failure here just means no ducking.
$ducker = $false
if ($null -ne $duckFactor -or $staleState) {
    try {
        if (-not ('AudioDucker' -as [type])) {
            Add-Type -Path (Join-Path $PSScriptRoot 'AudioDucker.cs') -ErrorAction Stop
        }
        $ducker = $true
    }
    catch { $ducker = $false }
}
if ($ducker -and $staleState) { [void][AudioDucker]::Restore($statePath) }

$synth = $null
$ducked = $false
$stage = 'initialize'
$enabledVoiceCount = $null
try {
    $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
    $stage = 'enumerate-voices'
    $enabledVoiceCount = @($synth.GetInstalledVoices() | Where-Object { $_.Enabled }).Count
    if ($enabledVoiceCount -eq 0) {
        if (-not $Diagnose) { Write-Output 'NoVoice' }
        Write-SpeechDiagnostic -Reason NoEnabledVoices -Stage $stage -EnabledVoiceCount $enabledVoiceCount
        exit 2
    }
    if ($Diagnose) {
        Write-SpeechDiagnostic -Reason AvailabilityOnly -Stage $stage -EnabledVoiceCount $enabledVoiceCount
        exit 0
    }
    $stage = 'duck'
    if ($ducker -and $null -ne $duckFactor) {
        [void][AudioDucker]::Duck($duckFactor, $statePath)
        $ducked = Test-Path -LiteralPath $statePath
    }
    $stage = 'speak'
    $synth.Speak($Text)
}
catch {
    if (-not $Diagnose) { Write-Output 'NoVoice' }
    Write-SpeechDiagnostic -Reason OperationFailed -Stage $stage -Failure $_.Exception -EnabledVoiceCount $enabledVoiceCount
    exit 2
}
finally {
    if ($ducked) { [void][AudioDucker]::Restore($statePath) }
    if ($synth) { $synth.Dispose() }
}
exit 0
