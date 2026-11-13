<#
.SYNOPSIS
    Forwards to the read-aloud skill's Speak-Text.ps1.

.DESCRIPTION
    Speak-Text.ps1 now lives in the read-aloud skill
    (%USERPROFILE%\.copilot\skills\read-aloud\scripts\Speak-Text.ps1). This stub only keeps the path
    written by project-memory-management-graph v25 and v26 (in a project's .github\copilot-instructions.md)
    working until that project is re-bootstrapped. It passes -Text through and returns the same output and
    exit codes (0 = spoken; 1 = could not start; 2 = NoVoice). If the read-aloud skill is not installed it
    writes a message and exits 1.

.PARAMETER Text
    The text to speak. Required.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Text
)

$target = Join-Path $env:USERPROFILE '.copilot\skills\read-aloud\scripts\Speak-Text.ps1'
if (-not (Test-Path -LiteralPath $target)) {
    Write-Output 'The read-aloud skill is not installed; run Install-Skills.ps1.'
    exit 1
}
& $target -Text $Text
exit $LASTEXITCODE
