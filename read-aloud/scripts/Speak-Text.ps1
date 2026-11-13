<#
.SYNOPSIS
    Speaks a short text aloud with the Windows default voice (System.Speech).

.DESCRIPTION
    Used by the read-aloud skill ("enable tts" / "start tts"). Runs in 64-bit Windows PowerShell 5.1
    or PowerShell 7 on Windows.

    The script never sets, selects or prefers a voice: it speaks with the system default voice
    configured in Windows, through the default audio device. If no voice is installed, or the
    default voice cannot speak, it writes the message NoVoice to the output, and exits 2.

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

.EXAMPLE
    .\Speak-Text.ps1 -Text "The build succeeded and all tests passed."
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Text
)

$ErrorActionPreference = 'Stop'

# SAPI voices are registered per bitness; a 32-bit host sees a different, usually smaller, list.
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    Write-Output 'Speak-Text.ps1 must run in a 64-bit PowerShell.'
    exit 1
}

try {
    Add-Type -AssemblyName System.Speech
}
catch {
    Write-Output "System.Speech is not available: $($_.Exception.Message)"
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
$duckFactor = Get-DuckFactor
$staleState = Test-Path -LiteralPath $statePath

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
try {
    $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
    if (@($synth.GetInstalledVoices() | Where-Object { $_.Enabled }).Count -eq 0) {
        Write-Output 'NoVoice'
        exit 2
    }
    if ($ducker -and $null -ne $duckFactor) {
        [void][AudioDucker]::Duck($duckFactor, $statePath)
        $ducked = Test-Path -LiteralPath $statePath
    }
    $synth.Speak($Text)
}
catch {
    Write-Output 'NoVoice'
    exit 2
}
finally {
    if ($ducked) { [void][AudioDucker]::Restore($statePath) }
    if ($synth) { $synth.Dispose() }
}
exit 0
