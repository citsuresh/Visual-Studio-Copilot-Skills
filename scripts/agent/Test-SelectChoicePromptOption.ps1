<#
.SYNOPSIS
Offline structure checks of Select-ChoicePromptOption.ps1's user-activity handling: its input-block functions match
the ones in Send-CopilotPrompt.ps1, and every step that takes focus, moves the mouse or invokes a control is guarded.
No chat, window, keyboard, mouse or clipboard is touched; the scripts are only parsed.
.PARAMETER ChoicePath
Select-ChoicePromptOption.ps1 to check. Default: the one in the sibling agent-orchestrator skill.
.PARAMETER SenderPath
Send-CopilotPrompt.ps1 to compare with. Default: the one in the sibling agent-orchestrator skill.
#>
[CmdletBinding()]
param([string]$ChoicePath, [string]$SenderPath)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
if (-not $ChoicePath) { $ChoicePath = Join-Path $PSScriptRoot '..\..\agent-orchestrator\scripts\Select-ChoicePromptOption.ps1' }
if (-not $SenderPath) { $SenderPath = Join-Path $PSScriptRoot '..\..\agent-orchestrator\scripts\Send-CopilotPrompt.ps1' }
$script:assertions = 0
function Assert-True([bool]$Condition, [string]$Message) { $script:assertions++; if (-not $Condition) { throw $Message } }
function Read-Ast([string]$Path) {
    $errors = $null
    $text = [IO.File]::ReadAllText((Resolve-Path $Path).Path)
    $ast = [Management.Automation.Language.Parser]::ParseInput($text, [ref]$null, [ref]$errors)
    if ($errors.Count) { throw ($errors | Out-String) }
    [pscustomobject]@{ Ast = $ast; Text = $text }
}
$choice = Read-Ast $ChoicePath
$sender = Read-Ast $SenderPath

# --- the copied input-block functions must stay identical to the sender's ---
foreach ($name in 'Start-InputBlock', 'Get-InputBlockInterruption', 'Update-InputBlockStamp', 'Stop-InputBlock') {
    $find = { param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }
    $a = $choice.Ast.Find($find, $true)
    $b = $sender.Ast.Find($find, $true)
    Assert-True ($null -ne $a -and $null -ne $b) "Missing function $name."
    Assert-True (($a.Extent.Text -replace '\r\n', "`n") -ceq ($b.Extent.Text -replace '\r\n', "`n")) "$name differs between Select-ChoicePromptOption.ps1 and Send-CopilotPrompt.ps1; keep the two copies identical."
}

# --- parameters: the user-activity switches are appended last, in the sender's order ---
$names = @($choice.Ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
Assert-True ((($names | Select-Object -Last 5) -join ',') -ceq 'QuietSeconds,MaxWaitSeconds,IgnoreUserActivity,NoRestoreFocus,SpeakRequest') 'The user-activity parameters must be appended last.'
Assert-True ($names[-6] -eq 'ExePath') 'Existing parameters must keep their positions.'

# --- no direct cursor calls outside the helper functions ---
$commands = @($choice.Ast.FindAll({ param($n) $n -is [Management.Automation.Language.CommandAst] }, $true))
$insideHelpers = { param($node) $p = $node.Parent; while ($p) { if ($p -is [Management.Automation.Language.FunctionDefinitionAst] -and $p.Name -in 'Start-InputBlock', 'Stop-InputBlock') { return $true }; $p = $p.Parent }; $false }
foreach ($direct in @($commands | Where-Object { $_.GetCommandName() -in 'Enable-AgentCursor', 'Restore-AgentCursor' })) {
    Assert-True (& $insideHelpers $direct) 'Enable-AgentCursor and Restore-AgentCursor may only be called inside the input-block helpers.'
}

# --- every foreground change is inside a block, after its start and behind an interruption check ---
$foreground = @($commands | Where-Object { $_.GetCommandName() -eq 'Set-AgentForegroundWindow' })
$starts = @($commands | Where-Object { $_.GetCommandName() -eq 'Start-InputBlock' })
$checks = @($commands | Where-Object { $_.GetCommandName() -eq 'Get-InputBlockInterruption' })
Assert-True ($foreground.Count -eq 3 -and $starts.Count -eq 3) 'Expected three input blocks: dropdown item, permission button and card option.'
foreach ($f in $foreground) {
    $start = @($starts | Where-Object { $_.Extent.StartOffset -lt $f.Extent.StartOffset } | Select-Object -Last 1)
    Assert-True ($start.Count -eq 1) 'A foreground change must follow Start-InputBlock.'
    $guard = @($checks | Where-Object { $_.Extent.StartOffset -gt $start[0].Extent.StartOffset -and $_.Extent.EndOffset -lt $f.Extent.StartOffset })
    Assert-True ($guard.Count -ge 1) 'A foreground change must be preceded by an interruption check.'
}

# --- every mouse click, focus change and invoke after the foreground is guarded and followed by a stamp update ---
$stamps = @($commands | Where-Object { $_.GetCommandName() -eq 'Update-InputBlockStamp' })
$clicks = @($choice.Ast.FindAll({ param($n) $n -is [Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Member.Value -eq 'LeftClick' }, $true))
$focus = @($choice.Ast.FindAll({ param($n) $n -is [Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Member.Value -eq 'SetFocus' }, $true))
Assert-True ($clicks.Count -eq 1 -and $focus.Count -eq 1) 'Expected one mouse click and one SetFocus in the script.'
$requireForeground = @($checks | Where-Object { $_.Extent.Text -match '-RequireForeground' })
foreach ($step in @($clicks) + @($focus)) {
    Assert-True (@($requireForeground | Where-Object { $_.Extent.EndOffset -lt $step.Extent.StartOffset }).Count -ge 1) 'A click or focus change must follow a RequireForeground check.'
    Assert-True (@($stamps | Where-Object { $_.Extent.StartOffset -gt $step.Extent.StartOffset }).Count -ge 1) 'A click or focus change must be followed by a stamp update.'
}
$optionForeground = $foreground[-1]
Assert-True ($focus[0].Extent.StartOffset -gt $optionForeground.Extent.EndOffset) 'SetFocus on the card must happen after the foreground is taken, never before: outside the block it can pull focus from the person.'
$invokes = @($choice.Ast.FindAll({ param($n) $n -is [Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Member.Value -eq 'Invoke' }, $true))
foreach ($invoke in $invokes) {
    $inBlock = $false
    foreach ($try in @($choice.Ast.FindAll({ param($n) $n -is [Management.Automation.Language.TryStatementAst] }, $true))) {
        if ($try.Finally -and $try.Finally.Extent.Text -match 'Stop-InputBlock' -and $try.Body.Extent.StartOffset -lt $invoke.Extent.StartOffset -and $invoke.Extent.EndOffset -lt $try.Body.Extent.EndOffset) { $inBlock = $true }
    }
    Assert-True $inBlock 'Every Invoke on a control must run inside an input block that is always ended.'
}
$tries = @($choice.Ast.FindAll({ param($n) $n -is [Management.Automation.Language.TryStatementAst] -and $n.Finally -and $n.Finally.Extent.Text -match 'Stop-InputBlock' }, $true))
Assert-True ($tries.Count -eq 3) 'Every input block must end in a finally that calls Stop-InputBlock.'

Write-Output "PASS: $script:assertions assertions; input-block functions identical to the sender's, parameters appended last, every foreground change, click, focus change and invoke inside a guarded block that always ends; scripts parsed only, nothing run."
