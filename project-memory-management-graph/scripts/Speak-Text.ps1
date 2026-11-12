<#
.SYNOPSIS
    Speaks a short text aloud with the Windows default voice (System.Speech).

.DESCRIPTION
    Used by the optional "read aloud" (TTS) rule that project-memory-management-graph Bootstrap
    writes into a repo's .github/copilot-instructions.md. Runs in 64-bit Windows PowerShell 5.1
    or PowerShell 7 on Windows.

    The script never sets, selects or prefers a voice: it speaks with the system default voice
    configured in Windows, through the default audio device. If no voice is installed, or the
    default voice cannot speak, it writes the message NoVoice to the output, and exits 2.

    It does not change the registry, the installed voices, or any system or user setting.

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

$synth = $null
try {
    $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
    if (@($synth.GetInstalledVoices() | Where-Object { $_.Enabled }).Count -eq 0) {
        Write-Output 'NoVoice'
        exit 2
    }
    $synth.Speak($Text)
}
catch {
    Write-Output 'NoVoice'
    exit 2
}
finally {
    if ($synth) { $synth.Dispose() }
}
exit 0
