<#
.SYNOPSIS
    Speaks a short text with Speak-Text.ps1 only when Visual Studio is not the foreground window.

.DESCRIPTION
    Entry point of the read-aloud skill's auto tts mode. Runs Test-HostVsActive.ps1 (next to this
    script) and calls Speak-Text.ps1 (also next to it) only when the check prints Inactive. Active,
    Unknown and any error mean silence. It always prints one line:

        Spoken (Inactive)
        Silent (Active) | Silent (Unknown) | Silent (Error: <reason>)

    Exit codes: 0 = spoken or silent without an error; 1 = error in this script; otherwise the exit
    code of Speak-Text.ps1 (1 = could not start, 2 = NoVoice) when speaking failed.
    Both scripts run in this process, so only one PowerShell start-up is paid.
    Changes nothing itself; see Speak-Text.ps1 for what speaking touches.

.PARAMETER Text
    The text to speak. Required.

.PARAMETER HostPid
    Testing only: passed to Test-HostVsActive.ps1 to override the search for the hosting devenv.exe.

.EXAMPLE
    .\Speak-IfAway.ps1 -Text 'The build succeeded and all tests passed.'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Text,

    $HostPid
)

$ErrorActionPreference = 'Stop'
$code = 0
try {
    $check = Join-Path $PSScriptRoot 'Test-HostVsActive.ps1'
    $speak = Join-Path $PSScriptRoot 'Speak-Text.ps1'
    if (-not (Test-Path -LiteralPath $check) -or -not (Test-Path -LiteralPath $speak)) {
        throw 'Test-HostVsActive.ps1 or Speak-Text.ps1 is missing next to this script'
    }

    $checkArgs = @{}
    if ($PSBoundParameters.ContainsKey('HostPid')) { $checkArgs.HostPid = $HostPid }
    $lines = @(& $check @checkArgs 2>&1 | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
    $state = if ($lines.Count -gt 0) { $lines[-1] } else { '' }

    if ($state -eq 'Inactive') {
        $global:LASTEXITCODE = 0
        $spoken = @(& $speak -Text $Text 2>&1 | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
        if ($LASTEXITCODE -eq 0) { "Spoken ($state)" }
        else {
            $code = $LASTEXITCODE
            $why = if ($spoken.Count -gt 0) { $spoken[-1] } else { "Speak-Text.ps1 exit code $code" }
            "Silent (Error: $why)"
        }
    }
    elseif ($state -eq 'Active' -or $state -eq 'Unknown') { "Silent ($state)" }
    else {
        'Silent (Error: unexpected output from Test-HostVsActive.ps1)'
        $code = 1
    }
}
catch {
    "Silent (Error: $(($_.Exception.Message -split '\r?\n')[0]))"
    $code = 1
}
exit $code
