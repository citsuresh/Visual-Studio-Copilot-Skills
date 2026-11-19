<#
.SYNOPSIS
Tests watcher progress without UI Automation, files, notifications or waiting.
.PARAMETER WatcherPath
V2 watcher source or external draft. Extracts only progress/result functions using the PS AST.
#>
[CmdletBinding()]
param([string]$WatcherPath = (Join-Path $PSScriptRoot '..\..\agent-orchestrator\scripts\Watch-CopilotChatV2.ps1'))
$ErrorActionPreference = 'Stop'
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($WatcherPath, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
foreach ($name in @('Write-WatchProgress', 'Finish')) {
    $function = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
    if (-not $function) { throw "Missing watcher function: $name" }
    . ([scriptblock]::Create($function.Extent.Text))
}
$script:lines = [Collections.Generic.List[string]]::new()
$script:hostLines = [Collections.Generic.List[string]]::new()
function Add-Content { param($LiteralPath, $Value, $Encoding) $script:lines.Add($Value) }
function Write-Host { param($Object) $script:hostLines.Add([string]$Object) }
function Assert-True([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
$ProgressFile = ''
$HeartbeatSeconds = 0
$script:started = Get-Date
$script:lastHeartbeat = $null
$script:lastSuccessfulOperation = $null
$script:lastSuccessfulUtc = $null
$script:retryCount = 0
Write-WatchProgress -Phase polling -State Waiting -Operation 'observe' -Force
Assert-True ($script:lines.Count -eq 0 -and $script:hostLines.Count -eq 0) 'Default must remain silent.'
$ProgressFile = 'mock-progress.jsonl'
Write-WatchProgress -Phase polling -State Waiting -Operation 'observe' -Force
$first = $script:lines[0] | ConvertFrom-Json
Assert-True ($first.state -eq 'Waiting' -and $first.elapsedSeconds -ge 0 -and $null -eq $first.lastSuccessfulOperation -and $first.retryCount -eq 0 -and $first.cleanupState) 'Initial facts must be explicit, not invented.'
Write-WatchProgress -Phase polling -State Waiting -Operation 'observe'
Assert-True ($script:lines.Count -eq 1) 'Heartbeat must be throttled.'
$script:lastHeartbeat = (Get-Date).AddSeconds(-31)
$script:lastSuccessfulOperation = 'read-only chat probe'
$script:lastSuccessfulUtc = (Get-Date).ToUniversalTime().ToString('o')
$script:retryCount = 2
Write-WatchProgress -Phase polling -State Waiting -Operation 'retry observation'
$next = $script:lines[1] | ConvertFrom-Json
Assert-True ($next.retryCount -eq 2 -and $next.lastSuccessfulOperation -eq 'read-only chat probe' -and $script:hostLines.Count -eq 0) 'File-only mode must preserve facts without host output.'
$HeartbeatSeconds = 30
Write-WatchProgress -Phase detail -State Waiting -Operation 'read final observation' -Force
Assert-True ($script:hostLines.Count -eq 1) 'Opt-in host heartbeat missing.'
$NoBeep = $true
$NoDetail = $true
$CrossCheck = $false
$script:probeMs = @(12, 14)
$script:busySeen = $true
foreach ($case in @(
    @{ State = 'Idle'; Expected = 'ObservationReady' },
    @{ State = 'Pending'; Expected = 'NeedsInput' },
    @{ State = 'Timeout'; Expected = 'StillWaiting' },
    @{ State = 'ProbeError'; Expected = 'Failed' },
    @{ State = 'WindowGone'; Expected = 'Blocked' }
)) {
    $result = Finish $case.State '' 'mock observation'
    $last = $script:lines[$script:lines.Count - 1] | ConvertFrom-Json
    Assert-True ($result.State -eq $case.State -and $last.state -eq $case.Expected -and $last.phase -eq 'finished') "Incorrect terminal progress: $($case.State)"
    Assert-True ($last.state -ne 'Completed') 'A watcher must not declare the overall task complete.'
}
Write-Output 'PASS: silent defaults, bounded cadence, operational facts, retries, cleanup ownership and terminal-state distinctions; no UI probes or notifications.'