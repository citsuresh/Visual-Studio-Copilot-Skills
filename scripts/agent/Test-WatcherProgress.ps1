<#
.SYNOPSIS
Tests watcher progress, polling decisions and permission-button recognition without UI probes, files, notifications or waiting.
.PARAMETER WatcherPath
V2 watcher source or external draft. Extracts functions and the actual polling loop using the PS AST;
mock flags and a virtual clock replace UI probes and sleeps.
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
foreach ($name in @('Add-Detail', 'Get-V1Field')) {
    $function = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
    if (-not $function) { throw "Missing watcher function: $name" }
    . ([scriptblock]::Create($function.Extent.Text))
}
$initialization = $ast.EndBlock.Statements | Where-Object {
    $_ -is [Management.Automation.Language.AssignmentStatementAst] -and $_.Left.Extent.Text -eq '$script:started'
} | Select-Object -First 1
if (-not $initialization) { throw 'Missing watcher polling initialization.' }
$pollingBody = [scriptblock]::Create($watcherText.Substring($initialization.Extent.StartOffset))
if (-not ('CopilotWait.NativeCheck' -as [type])) {
    Add-Type -Namespace CopilotWait -Name NativeCheck -MemberDefinition 'public static bool IsWindow(System.IntPtr h) { return true; }'
}
function Invoke-WatchSequence {
    param(
        [string[]]$Steps,
        [switch]$RequireBusyFirst,
        [int]$TimeoutSeconds = 15,
        [int]$QuietSeconds = 20,
        [int]$StartGraceSeconds = 30,
        [int]$PollIntervalSeconds = 5,
        [switch]$WithDetail
    )
    $script:clock = [datetime]'2026-01-01T00:00:00Z'
    $script:stepIndex = 0
    $script:detailCalls = 0
    $script:lines.Clear()
    $script:hostLines.Clear()
    $NoBeep = $true
    $NoDetail = -not $WithDetail
    $CrossCheck = $false
    $ProgressFile = ''
    $HeartbeatSeconds = 0
    $TraceFile = ''
    $handle = [IntPtr]::Zero
    function Get-Date { $script:clock }
    function Start-Sleep {
        param([int]$Milliseconds, [int]$Seconds)
        $script:clock = $script:clock.AddMilliseconds($Milliseconds).AddSeconds($Seconds)
    }
    function Get-FlagsScoped {
        if ($script:stepIndex -ge $Steps.Count) { throw 'Mock probe sequence exhausted.' }
        $step = $Steps[$script:stepIndex++]
        if ($step -eq 'ErrorAtDeadline') {
            $script:clock = $script:clock.AddSeconds($TimeoutSeconds)
            throw 'mock probe failure'
        }
        if ($step -eq 'Error') { throw 'mock probe failure' }
        $flags = New-Flags
        $flags.Chat = $true
        $flags.Title = 'same chat'
        switch ($step) {
            'Footer' { $flags.Footer = $true }
            'Quiet' { }
            'Busy' { $flags.Busy = $true }
            'BusyFooter' { $flags.Busy = $true; $flags.Footer = $true }
            'CardFooter' { $flags.Card = $true; $flags.Footer = $true }
            'PermissionFooter' { $flags.Permission = $true; $flags.Footer = $true }
            'Hidden' { $flags.Chat = $false }
            'Switched' { $flags.Title = 'other chat' }
            default { throw "Unknown mock step: $step" }
        }
        $flags
    }
    function Get-V1Detail {
        $script:detailCalls++
        @{ Data = [pscustomobject]@{ State = 'Pending'; PromptKind = 'PermissionPrompt' } }
    }
    . $pollingBody
}
$result = Invoke-WatchSequence -Steps Footer, Footer
Assert-True ($result.State -eq 'Idle' -and $result.Polls -eq 2 -and $result.ElapsedSeconds -eq 5 -and -not $result.BusySeen) 'An already-idle footer must finish on poll two before a 15-second timeout.'
Assert-True ($result.Note -match 'Two consecutive polls' -and $script:detailCalls -eq 0) 'Fast idle must explain its evidence and honor NoDetail.'
$result = Invoke-WatchSequence -Steps Footer, Footer -TimeoutSeconds 10 -PollIntervalSeconds 2 -QuietSeconds 300
Assert-True ($result.State -eq 'Idle' -and $result.Polls -eq 2 -and $result.ElapsedSeconds -eq 2) 'Footer fast idle must not wait for QuietSeconds.'
$result = Invoke-WatchSequence -Steps Footer, Quiet, Footer, Quiet
Assert-True ($result.State -eq 'Timeout' -and $result.Polls -eq 4) 'Nonconsecutive footers must not trigger fast idle.'
Assert-True ($result.Note -eq 'No terminal state after 15 seconds (busy seen no, footer at end no, quiet countdown 15 of 20 seconds).') 'Quiet timeout facts must match the latest probe and countdown.'
$result = Invoke-WatchSequence -Steps Footer, Error, Footer, Footer
Assert-True ($result.State -eq 'Idle' -and $result.Polls -eq 3 -and $result.ElapsedSeconds -eq 11 -and $script:stepIndex -eq 4) 'A failed probe must break the footer streak; two fresh successful polls are required.'
$result = Invoke-WatchSequence -Steps Footer, Footer, Footer, Footer -RequireBusyFirst
Assert-True ($result.State -eq 'Timeout' -and -not $result.BusySeen) 'RequireBusyFirst must not fast-idle on a previous footer.'
Assert-True ($result.Note -eq 'No terminal state after 15 seconds (busy seen no, footer at end yes, quiet countdown 0 of 20 seconds).') 'Start-gated timeout must not claim busy or a running quiet countdown.'
$result = Invoke-WatchSequence -Steps (@('Footer') * 11) -RequireBusyFirst -TimeoutSeconds 60
Assert-True ($result.State -eq 'Idle' -and $result.Polls -eq 11 -and $result.ElapsedSeconds -eq 50 -and -not $result.BusySeen -and $result.Note -match 'quiet period') 'RequireBusyFirst must preserve grace plus quiet timing.'
$result = Invoke-WatchSequence -Steps Footer, Footer, Footer, Footer -RequireBusyFirst -StartGraceSeconds 0
Assert-True ($result.State -eq 'Timeout' -and $result.Note -match 'quiet countdown 15 of 20') 'Zero grace still must not enable the two-poll path with RequireBusyFirst.'
$result = Invoke-WatchSequence -Steps (@('Quiet') * 5) -TimeoutSeconds 30
Assert-True ($result.State -eq 'Idle' -and $result.ElapsedSeconds -eq 20 -and $result.Polls -eq 5) 'No-footer fallback must preserve quiet timing.'
$result = Invoke-WatchSequence -Steps Busy, Footer -RequireBusyFirst
Assert-True ($result.State -eq 'Idle' -and $result.BusySeen -and $result.Polls -eq 2) 'Observed busy-to-footer must retain immediate idle with RequireBusyFirst.'
$result = Invoke-WatchSequence -Steps Footer, BusyFooter, Footer
Assert-True ($result.State -eq 'Idle' -and $result.BusySeen -and $result.Polls -eq 3) 'A stop button must block fast idle, then preserve the existing busy-to-footer path.'
$result = Invoke-WatchSequence -Steps Busy, Quiet, Quiet, Quiet
Assert-True ($result.State -eq 'Timeout' -and $result.Note -eq 'No terminal state after 15 seconds (busy seen yes, footer at end no, quiet countdown 10 of 20 seconds).') 'Timeout must report busy history and the quiet reset accurately.'
$result = Invoke-WatchSequence -Steps (@('BusyFooter') * 4)
Assert-True ($result.State -eq 'Timeout' -and $result.Note -match 'busy seen yes, footer at end yes, quiet countdown 0') 'A persistent stop button must never fast-idle even with a footer.'
foreach ($case in @(
    @{ Step = 'CardFooter'; Kind = 'ChoiceCard' },
    @{ Step = 'PermissionFooter'; Kind = 'PermissionPrompt' }
)) {
    $result = Invoke-WatchSequence -Steps Footer, $case.Step
    Assert-True ($result.State -eq 'Pending' -and $result.PromptKind -eq $case.Kind -and $result.Polls -eq 2) "Prompt must take priority over a second footer: $($case.Kind)"
}
$result = Invoke-WatchSequence -Steps Footer, Hidden
Assert-True ($result.State -eq 'NotVisible' -and $result.Polls -eq 2) 'A hidden chat must not count as a second footer.'
$result = Invoke-WatchSequence -Steps Busy, Switched
Assert-True ($result.State -eq 'ChatSwitched' -and $result.Polls -eq 2) 'Chat-switch handling must remain unchanged.'
$result = Invoke-WatchSequence -Steps ErrorAtDeadline -TimeoutSeconds 10
Assert-True ($result.State -eq 'Timeout' -and $result.Note -eq 'No terminal state after 10 seconds; latest probe failed: mock probe failure') 'Failed-probe timeout must report the failure without claiming busy.'
$result = Invoke-WatchSequence -Steps Error, Error, Error
Assert-True ($result.State -eq 'ProbeError' -and $script:stepIndex -eq 3) 'Three consecutive probe failures must still report ProbeError.'
$result = Invoke-WatchSequence -Steps Footer, Footer -WithDetail
Assert-True ($result.State -eq 'Pending' -and $result.Upgraded -and $script:detailCalls -eq 1) 'Fast idle must still run one detail reconciliation and upgrade a missed prompt.'
Write-Output 'PASS: 19 virtual-clock polling scenarios plus silent defaults, bounded cadence, operational facts, retries, cleanup ownership, terminal-state distinctions and plain-Allow recognition; no UI probes, files, notifications or real sleeps.'
