<#
.SYNOPSIS
Tests watcher progress and permission-button recognition without UI Automation, files, notifications or waiting.
.PARAMETER WatcherPath
V2 watcher source or external draft. Extracts only progress/result and permission-match functions using the PS AST.
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
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
foreach ($name in @('New-Flags', 'Cond', 'Test-PendingAllow', 'Add-Match')) {
    $function = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
    if (-not $function) { throw "Missing watcher function: $name" }
    . ([scriptblock]::Create($function.Extent.Text))
}
$nameProp = [System.Windows.Automation.AutomationElement]::NameProperty
$children = [System.Windows.Automation.TreeScope]::Children
function New-MockButton([string]$Name, [string]$Id = '', [bool]$Offscreen = $false, [bool]$Enabled = $true) {
    $element = [pscustomobject]@{ Current = [pscustomobject]@{ Name = $Name; AutomationId = $Id; IsOffscreen = $Offscreen; IsEnabled = $Enabled }; Parent = $null }
    $element
}
function New-MockParent($Kids) {
    $parent = New-Object PSObject
    $parent | Add-Member -NotePropertyName Kids -NotePropertyValue @($Kids)
    $parent | Add-Member -MemberType ScriptMethod -Name FindFirst -Value {
        param($scope, $condition)
        $this.Kids | Where-Object { $_.Current.Name -eq $condition.Value } | Select-Object -First 1
    }
    foreach ($kid in @($Kids)) { $kid.Parent = $parent }
    $parent
}
$walker = New-Object PSObject
$walker | Add-Member -MemberType ScriptMethod -Name GetParent -Value { param($e) if ($script:walkerFails) { throw 'stale element' }; $e.Parent }
$script:walkerFails = $false
function Get-MockFlags($Buttons) {
    $flags = New-Flags
    foreach ($button in $Buttons) { Add-Match $flags $button }
    $flags
}
$allow = New-MockButton 'Allow'; $deny = New-MockButton 'Deny'; $null = New-MockParent @($allow, $deny)
$flags = Get-MockFlags @($allow, $deny)
Assert-True ($flags.Permission -and $flags.Chat) 'A plain Allow beside a visible Deny must be a pending permission.'
$allow = New-MockButton 'Allow'; $null = New-MockParent @($allow, (New-MockButton 'Skip'))
Assert-True (-not (Get-MockFlags @($allow)).Permission) 'A lone Allow without a Deny sibling (historical or unrelated) must not match.'
$allow = New-MockButton 'Allow'; $null = New-MockParent @($allow, (New-MockButton 'Deny' '' $true))
Assert-True (-not (Get-MockFlags @($allow)).Permission) 'An Allow beside an offscreen Deny must not match.'
$allow = New-MockButton 'Allow'; $null = New-MockParent @($allow, (New-MockButton 'Deny' '' $false $false))
Assert-True (-not (Get-MockFlags @($allow)).Permission) 'An Allow beside a disabled Deny must not match.'
$allow = New-MockButton 'Allow' '' $true; $null = New-MockParent @($allow, (New-MockButton 'Deny'))
Assert-True (-not (Get-MockFlags @($allow)).Permission) 'A scrolled-out Allow must not match.'
$allow = New-MockButton 'Allow' '' $false $false; $null = New-MockParent @($allow, (New-MockButton 'Deny'))
Assert-True (-not (Get-MockFlags @($allow)).Permission) 'A disabled Allow must not match.'
$allow = New-MockButton 'Allow'
Assert-True (-not (Get-MockFlags @($allow)).Permission) 'An Allow without a parent must not match.'
$allow = New-MockButton 'Allow'; $null = New-MockParent @($allow, (New-MockButton 'Deny'))
$script:walkerFails = $true
Assert-True (-not (Get-MockFlags @($allow)).Permission) 'A failed parent read must not match.'
$script:walkerFails = $false
Assert-True ((Get-MockFlags @((New-MockButton 'Allow this time'))).Permission) 'The existing Allow this time match changed.'
$cancel = New-MockButton 'Cancel' 'CancelButton'
$flags = Get-MockFlags @($cancel)
Assert-True ($flags.Busy -and -not $flags.Permission) 'The stop button must only mean busy.'
Assert-True (-not (Get-MockFlags @((New-MockButton 'Cancel'))).Busy -and -not (Get-MockFlags @((New-MockButton 'Cancel'))).Permission) 'A plain button named Cancel must not match anything.'
$allow = New-MockButton 'Allow'; $null = New-MockParent @($allow, (New-MockButton 'Skip'))
$flags = Get-MockFlags @($cancel, $allow)
Assert-True ($flags.Busy -and -not $flags.Permission) 'A stop button plus a lone Allow must remain Busy, not Pending.'
$allow = New-MockButton 'Allow'; $deny = New-MockButton 'Deny'; $null = New-MockParent @($allow, $deny)
$flags = Get-MockFlags @($cancel, $allow, $deny)
Assert-True ($flags.Busy -and $flags.Permission) 'A pending approval keeps the stop button; Permission must still be set.'
$watcherText = Get-Content -Raw -LiteralPath $WatcherPath
Assert-True ($watcherText -match '\(Cond \$nameProp ''Allow''\)') 'The input-area condition must include the plain Allow name.'
Assert-True ($watcherText.IndexOf('if ($f.Permission) { return (Finish') -lt $watcherText.IndexOf('if ($f.Busy) {')) 'Pending must be decided before Busy so a pending approval is reported at once.'
Write-Output 'PASS: silent defaults, bounded cadence, operational facts, retries, cleanup ownership, terminal-state distinctions and plain-Allow permission recognition; no UI probes or notifications.'