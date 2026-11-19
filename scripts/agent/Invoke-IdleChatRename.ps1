<#
.SYNOPSIS
Compatibility entry point for the idle-rename worker bundled with vs-chat-history.
.DESCRIPTION
Forwards unchanged parameters/output to the repository's canonical bundled helper.
Only that helper performs UI input and private result writes; ValidateOnly stays read-only.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$UiExe,
    [Parameter(Mandatory)][string]$CursorScript,
    [Parameter(Mandatory)][int]$HostProcessId,
    [Parameter(Mandatory)][long]$HostStartTicks,
    [Parameter(Mandatory)][ValidatePattern('^0x[0-9A-Fa-f]+$')][string]$WindowHandle,
    [Parameter(Mandatory)][string]$ExpectedHeader,
    [Parameter(Mandatory)][string]$OldTitle,
    [Parameter(Mandatory)][ValidateLength(1,120)][string]$NewTitle,
    [Parameter(Mandatory)][ValidatePattern('^[0-9A-Fa-f]{64}$')][string]$ReadyMessageHash,
    [Parameter(Mandatory)][string]$ResultPath,
    [ValidateRange(1,300)][int]$DelaySeconds = 20,
    [ValidateRange(1,600)][int]$IdleTimeoutSeconds = 120,
    [ValidateRange(1,30)][int]$StableIdleSeconds = 3,
    [ValidateRange(100,5000)][int]$PollMilliseconds = 500,
    [ValidateRange(1,30)][int]$VerificationSeconds = 5,
    [switch]$ValidateOnly
)
$worker = Join-Path $PSScriptRoot '..\..\vs-chat-history\scripts\Invoke-IdleChatRename.ps1'
if (-not (Test-Path -LiteralPath $worker -PathType Leaf)) {
    throw 'Bundled idle-rename worker missing; restore vs-chat-history\scripts\Invoke-IdleChatRename.ps1.'
}
& $worker @PSBoundParameters