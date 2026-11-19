<#
.SYNOPSIS
Read-only syntax and idle-evidence policy tests; no UI, processes, files or audio changed.
.PARAMETER ScriptPath
Idle rename script whose pure hash and idle-gate functions are tested through its AST.
.PARAMETER EntryPointPath
Compatibility forwarder whose parameter contract is checked against the bundled worker.
.PARAMETER SkillPath
Skill containing the independent launch recipe, tested with a mocked process launcher.
#>
[CmdletBinding()]
param(
    [string]$ScriptPath = (Join-Path $PSScriptRoot '..\..\vs-chat-history\scripts\Invoke-IdleChatRename.ps1'),
    [string]$EntryPointPath = (Join-Path $PSScriptRoot 'Invoke-IdleChatRename.ps1'),
    [string]$SkillPath = (Join-Path $PSScriptRoot '..\..\vs-chat-history\SKILL.md')
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
foreach ($name in @('Get-MessageHash', 'Test-IdleEvidence', 'Test-ClipboardPreserved', 'Confirm-HostForeground', 'Read-RenameTitle', 'Write-Result')) {
    $function = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
    if (-not $function) { throw "Missing function: $name" }
    . ([scriptblock]::Create($function.Extent.Text))
}
function Assert-True([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
$entryAst = [Management.Automation.Language.Parser]::ParseFile($EntryPointPath, [ref]$tokens, [ref]$errors)
Assert-True ($errors.Count -eq 0) 'Compatibility entry point has syntax errors.'
Assert-True ($entryAst.ParamBlock.Extent.Text -ceq $ast.ParamBlock.Extent.Text) 'Compatibility parameter names, validations or defaults drifted.'
$forwarding = @($entryAst.FindAll({ param($node)
    $node -is [Management.Automation.Language.CommandAst] -and
    $node.InvocationOperator -eq [Management.Automation.Language.TokenKind]::Ampersand
}, $true))
Assert-True ($forwarding.Count -eq 1 -and $forwarding[0].Extent.Text -ceq '& $worker @PSBoundParameters') 'Compatibility entry point must forward unchanged parameters exactly once.'
Assert-True (Test-ClipboardPreserved ([pscustomobject]@{ clipboardSnapshotComplete = $true; clipboardRestored = $true })) 'Complete successful clipboard restoration rejected.'
Assert-True (Test-ClipboardPreserved ([pscustomobject]@{ clipboardSnapshotComplete = $true })) 'A verified empty clipboard is a valid restoration no-op.'
foreach ($clipboard in @(
    $null,
    [pscustomobject]@{},
    [pscustomobject]@{ clipboardRestored = $true },
    [pscustomobject]@{ clipboardSnapshotComplete = $false },
    [pscustomobject]@{ clipboardSnapshotComplete = $false; clipboardRestored = $true },
    [pscustomobject]@{ clipboardSnapshotComplete = 'true' },
    [pscustomobject]@{ clipboardSnapshotComplete = $true; clipboardRestored = $false },
    [pscustomobject]@{ clipboardSnapshotComplete = $true; clipboardRestored = $null }
)) {
    Assert-True (-not (Test-ClipboardPreserved $clipboard)) 'Unknown, incomplete or failed clipboard preservation accepted.'
}
$WindowHandle = '0x1234'
$script:focusAttempts = 0
$script:cursorEnabled = 0
$script:cursorRestored = 0
$script:allowFocus = $true
function Enable-AgentCursor { $script:cursorEnabled++ }
function Restore-AgentCursor { $script:cursorRestored++ }
function Set-AgentForegroundWindow { param($Handle) $script:focusAttempts++; return $script:allowFocus }
Confirm-HostForeground
Assert-True ($script:focusAttempts -eq 1 -and $script:cursorEnabled -eq 1 -and $script:cursorRestored -eq 1) 'Verified activation must run once with cursor cleanup.'
$script:allowFocus = $false
$focusRefused = $false
try { Confirm-HostForeground } catch { $focusRefused = $true }
Assert-True ($focusRefused -and $script:focusAttempts -eq 2 -and $script:cursorEnabled -eq 2 -and $script:cursorRestored -eq 2) 'Denied activation must fail once and restore the cursor without retry.'
$hash = Get-MessageHash "a`nb"
Assert-True ($hash -ceq (Get-MessageHash " a`r`nb ")) 'CRLF/trim normalization failed.'
Assert-True ($hash -ceq (Get-MessageHash "a`rb")) 'Lone CR normalization failed.'
Assert-True ($hash -cne (Get-MessageHash 'other')) 'Different messages must not match.'
$good = @{ Header = 'expected'; ReadyMessageSeen = $true; CancelCount = 0; DraftEmpty = $true; RenameEditorCount = 0 }
Assert-True (Test-IdleEvidence ([pscustomobject]$good) 'expected') 'Valid idle evidence rejected.'
foreach ($case in @(
    @{ Key = 'Header'; Value = 'another chat' },
    @{ Key = 'ReadyMessageSeen'; Value = $false },
    @{ Key = 'ReadyMessageSeen'; Value = $null },
    @{ Key = 'CancelCount'; Value = 1 },
    @{ Key = 'CancelCount'; Value = $null },
    @{ Key = 'DraftEmpty'; Value = $false },
    @{ Key = 'DraftEmpty'; Value = $null },
    @{ Key = 'RenameEditorCount'; Value = 1 }
)) {
    $invalid = $good.Clone()
    $invalid[$case.Key] = $case.Value
    Assert-True (-not (Test-IdleEvidence ([pscustomobject]$invalid) 'expected')) "Unsafe idle state accepted: $($case.Key)"
}
$collisionProbe = {
    param([ValidateSet('Start','Stop')][string]$Session)
    $cursorStartReply = [pscustomobject]@{ changed = $true }
    return $cursorStartReply.changed
}
Assert-True (& $collisionProbe) 'Cursor start reply collided with the imported Session parameter.'
$assignments = $ast.FindAll({ param($node)
    $node -is [Management.Automation.Language.AssignmentStatementAst] -and
    $node.Left -is [Management.Automation.Language.VariableExpressionAst]
}, $true)
Assert-True (@($assignments | Where-Object { $_.Left.VariablePath.UserPath -ieq 'Session' }).Count -eq 0) 'Do not assign the cursor helper validated Session variable.'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
$script:patternSupported = $true
$script:mockValuePattern = [pscustomobject]@{ Current = [pscustomobject]@{ Value = 'old title' } }
$editor = New-Object PSObject
$editor | Add-Member -MemberType ScriptMethod -Name TryGetCurrentPattern -Value {
    param($patternId, $patternReference)
    $patternReference.Value = $script:mockValuePattern
    return $script:patternSupported
}
$script:editorFixtures = @($editor)
function Get-RenameEditors { param($Chat) return $script:editorFixtures }
Assert-True ((Read-RenameTitle $null) -ceq 'old title') 'Old-title read failed.'
$script:mockValuePattern.Current.Value = 'typed title'
Assert-True ((Read-RenameTitle $null) -ceq 'typed title') 'Typed-title read must be fresh, not cached.'
foreach ($case in @('missing', 'ambiguous', 'unsupported')) {
    $script:editorFixtures = @($editor)
    $script:patternSupported = $true
    if ($case -eq 'missing') { $script:editorFixtures = @() }
    if ($case -eq 'ambiguous') { $script:editorFixtures = @($editor, $editor) }
    if ($case -eq 'unsupported') { $script:patternSupported = $false }
    $refused = $false
    try { $null = Read-RenameTitle $null } catch { $refused = $true }
    Assert-True $refused "Unsafe title read was accepted: $case"
}
$script:runTimer = [pscustomobject]@{ Elapsed = [pscustomobject]@{ TotalMilliseconds = 10.0 } }
$script:uiTimings = New-Object 'Collections.Generic.List[object]'
$script:phaseTimings = New-Object 'Collections.Generic.List[object]'
$script:lastTimedPhase = 'Preflight'
$script:phaseStartedMs = 0.0
$script:result = [ordered]@{
    phase = 'Delay'; elapsedMs = 0.0; currentPhaseElapsedMs = 0.0
    phaseTimings = @(); uiCommandTimings = @(); updatedUtc = $null
}
$ResultPath = 'mock-result'
function Set-Content { param($LiteralPath, $Encoding, [Parameter(ValueFromPipeline)]$Value) process { $script:lastResult = $Value | ConvertFrom-Json } }
Write-Result
Assert-True ($script:lastResult.phaseTimings[0].phase -eq 'Preflight' -and $script:lastResult.phaseTimings[0].elapsedMs -eq 10) 'Preflight timing missing.'
$script:runTimer.Elapsed.TotalMilliseconds = 25.0
Write-Result
Assert-True ($script:lastResult.phaseTimings.Count -eq 1 -and $script:lastResult.currentPhaseElapsedMs -eq 15) 'Same-phase timing duplicated or incorrect.'
$script:runTimer.Elapsed.TotalMilliseconds = 30.0
$script:result.phase = 'WaitingForIdle'
Write-Result
Assert-True ($script:lastResult.phaseTimings[1].phase -eq 'Delay' -and $script:lastResult.phaseTimings[1].elapsedMs -eq 20) 'Phase duration failed.'
$skill = Get-Content -LiteralPath $SkillPath -Raw
$recipes = [regex]::Matches($skill, '(?ms)^   ```powershell\r?\n(?<code>.*?)^   ```\r?$')
Assert-True ($recipes.Count -eq 1) 'Expected exactly one independent launch recipe.'
$recipe = [scriptblock]::Create($recipes[0].Groups['code'].Value)
$script:launchCalls = 0
function Start-Process {
    param($FilePath, $ArgumentList, $WindowStyle, $RedirectStandardOutput, $RedirectStandardError, [switch]$PassThru)
    $script:launchCalls++
    $script:launchArguments = $ArgumentList
    Assert-True ($WindowStyle -eq 'Hidden' -and $PassThru) 'Launcher must be hidden and return worker identity.'
    Assert-True ($RedirectStandardOutput -cne $RedirectStandardError) 'Worker logs must use distinct paths.'
    return [pscustomobject]@{ Id = 123; StartTime = [datetime]'2026-01-01T00:00:00Z' }
}
function Capture-WorkerParameters {
    param($NewTitle, $ExpectedHeader, $ResultPath, [long]$HostStartTicks, [int]$DelaySeconds)
    $script:transported = $PSBoundParameters
}
$script:launchInjectionObserved = $false
$workerScript = 'Capture-WorkerParameters'
$renameParameters = @{
    NewTitle = 'O''Brien; $script:launchInjectionObserved = $true'
    ExpectedHeader = 'O''Brien, Working directory: C:\Repo with spaces'
    ResultPath = (Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '.json'))
    HostStartTicks = [long]639306668422189780
    DelaySeconds = 2
}
$launch = & $recipe | ConvertFrom-Json
Assert-True ($script:launchCalls -eq 1 -and $launch.workerPid -eq 123) 'Launcher must return the actual worker identity once.'
Assert-True (($script:launchArguments -join ' ') -like '*-NoProfile -NonInteractive -STA -EncodedCommand *') 'Worker startup flags changed.'
$command = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($script:launchArguments[-1]))
& ([scriptblock]::Create($command))
foreach ($key in $renameParameters.Keys) {
    Assert-True ($script:transported[$key] -ceq $renameParameters[$key]) "Parameter changed during launch transport: $key"
}
Assert-True (-not $script:launchInjectionObserved) 'Title text was evaluated as code.'
$workerScript = 'C:\Folder O''Brien\Invoke-IdleChatRename.ps1'
$null = & $recipe
$command = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($script:launchArguments[-1]))
$commandAst = [Management.Automation.Language.Parser]::ParseInput($command, [ref]$tokens, [ref]$errors)
Assert-True ($errors.Count -eq 0) 'Quoted worker path produced invalid PowerShell.'
$invocation = $commandAst.Find({ param($node)
    $node -is [Management.Automation.Language.CommandAst] -and
    $node.InvocationOperator -eq [Management.Automation.Language.TokenKind]::Ampersand
}, $true)
Assert-True ($invocation.CommandElements[0].Value -ceq $workerScript) 'Worker path changed during launch quoting.'
Write-Output 'PASS: syntax, compatibility forwarding, hash/idle guards, fresh title reads, phase timings and mocked independent launch recipe; no live UI, processes or rename performed.'
