<#
.SYNOPSIS
Offline sender native-argument, input read-back, draft-guard and own-host guard regression checks; no chat interaction.
.PARAMETER SenderPath
Sender whose functions and send-loop statements are tested through its AST.
.PARAMETER TemporaryRoot
Existing directory for a disposable argument-echo fixture. Only that fixture is created/deleted.
.DESCRIPTION
Launches an isolated PowerShell argument-echo process. UIA input and foreground calls are mocked;
no real chat, clipboard, cursor, focus or repository files are modified.
#>
[CmdletBinding()]
param(
    [string]$SenderPath = (Join-Path $PSScriptRoot '..\..\agent-orchestrator\scripts\Send-CopilotPrompt.ps1'),
    [string]$TemporaryRoot = [IO.Path]::GetTempPath()
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($SenderPath, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
$script:assertions = 0
function Assert-True([bool]$Condition, [string]$Message) {
    $script:assertions++
    if (-not $Condition) { throw $Message }
}
foreach ($name in @('ConvertTo-NativeArgument', 'Invoke-Ui', 'Get-ChatInputText', 'Get-ChatDraftError', 'Get-CallerProcessIds', 'Get-OwnHostError', 'Write-Result')) {
    $function = $ast.Find({ param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    }, $true)
    if (-not $function) { throw "Missing function: $name" }
    . ([scriptblock]::Create($function.Extent.Text))
}
if (-not (Test-Path -LiteralPath $TemporaryRoot -PathType Container)) { throw 'TemporaryRoot must be an existing directory.' }
$fixtureDirectory = Join-Path $TemporaryRoot ('sender-argv-' + [guid]::NewGuid().ToString('N'))
$fixture = Join-Path $fixtureDirectory 'Echo-Arguments.ps1'
$null = New-Item -ItemType Directory -Path $fixtureDirectory
try {
    Set-Content -LiteralPath $fixture -Encoding ASCII -Value '[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false); [pscustomobject]@{ arguments = [Environment]::GetCommandLineArgs() } | ConvertTo-Json -Depth 3 -Compress'
    $ExePath = Join-Path $PSHOME $(if ($PSVersionTable.PSEdition -eq 'Desktop') { 'powershell.exe' } else { 'pwsh.exe' })
    foreach ($text in @(
        'Before "Worked" after',
        'Before "two words" after',
        'Before "" after',
        'Path C:\folder with spaces\',
        'Slash before quote: \" and \\"',
        'Quotes at end: "last"',
        'Literal --text and $value; {braces}',
        '',
        ('Unicode ' + [char]0x03A9 + ' "quoted"')
    )) {
        $response = Invoke-Ui @('-NoProfile', '-NonInteractive', '-File', $fixture, 'begin', $text, 'end')
        $actual = @($response.arguments)
        Assert-True ($actual.Count -ge 3) 'Native probe returned no argument array.'
        Assert-True ($actual[-3] -ceq 'begin' -and $actual[-1] -ceq 'end') 'Native argument boundaries changed.'
        Assert-True ($actual[-2] -ceq $text) "Native text changed: $text"
    }
}
finally {
    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Force }
    Remove-Item -LiteralPath $fixtureDirectory
}

Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$script:valueSupported = $true
$script:textSupported = $true
$script:valueRead = 'original "quoted text"'
$script:textRead = 'original "quoted text"'
$inputElement = New-Object PSObject
$inputElement | Add-Member -MemberType ScriptMethod -Name TryGetCurrentPattern -Value {
    param($patternId, $patternReference)
    if ($patternId -eq [Windows.Automation.ValuePattern]::Pattern -and $script:valueSupported) {
        $patternReference.Value = [pscustomobject]@{ Current = [pscustomobject]@{ Value = $script:valueRead } }
        return $true
    }
    if ($patternId -eq [Windows.Automation.TextPattern]::Pattern -and $script:textSupported) {
        $range = New-Object PSObject
        $range | Add-Member -MemberType ScriptMethod -Name GetText -Value { param($length) return $script:textRead }
        $patternReference.Value = [pscustomobject]@{ DocumentRange = $range }
        return $true
    }
    return $false
}
$script:inputFixtures = @($inputElement)
function Get-ChatInputElements { return $script:inputFixtures }
Assert-True ((Get-ChatInputText) -ceq $script:valueRead) 'ValuePattern read-back failed.'
$script:valueSupported = $false
Assert-True ((Get-ChatInputText) -ceq $script:textRead) 'TextPattern read-back failed.'
foreach ($case in @('missing', 'ambiguous', 'unsupported', 'null')) {
    $script:inputFixtures = @($inputElement)
    $script:textSupported = $true
    $script:textRead = 'original'
    switch ($case) {
        'missing' { $script:inputFixtures = @() }
        'ambiguous' { $script:inputFixtures = @($inputElement, $inputElement) }
        'unsupported' { $script:textSupported = $false }
        'null' { $script:textRead = $null }
    }
    $refused = $false
    try { $null = Get-ChatInputText } catch { $refused = $true }
    Assert-True $refused "Unverified input was accepted: $case"
}

$script:inputFixtures = @($inputElement)
$script:textSupported = $true
$Quiet = $false
$AsJson = $false
foreach ($draftText in @('user draft', ' ', 'original "quoted text"')) {
    $script:textRead = $draftText
    Assert-True ((Get-ChatDraftError) -match 'InputNotEmpty') 'A non-empty draft was accepted.'
    Assert-True ($script:textRead -ceq $draftText) 'Draft inspection changed the text.'
}
$script:textRead = ''
Assert-True ($null -eq (Get-ChatDraftError)) 'An empty input should be allowed.'
$script:inputFixtures = @()
Assert-True ($null -eq (Get-ChatDraftError -AllowMissing)) 'A hidden input should allow the navigation preflight.'
Assert-True ((Get-ChatDraftError) -match 'missing or ambiguous') 'Final draft check accepted an absent input.'
$script:inputFixtures = @($inputElement, $inputElement)
Assert-True ((Get-ChatDraftError -AllowMissing) -match 'missing or ambiguous') 'Preflight accepted ambiguous input.'
$script:inputFixtures = @($inputElement)
$script:textRead = 'user draft'
$OverwriteInput = $false
$NewSession = $true
$preflight = $ast.EndBlock.Statements | Where-Object {
    $_ -is [Management.Automation.Language.IfStatementAst] -and $_.Extent.Text -match 'Get-ChatDraftError -AllowMissing'
} | Select-Object -First 1
Assert-True ($null -ne $preflight) 'Missing default draft preflight.'
$result = & ([scriptblock]::Create($preflight.Extent.Text))
Assert-True (-not $result.Sent -and $result.Attempts -eq 0 -and $result.Error -match 'InputNotEmpty') 'Draft preflight did not refuse before a new session/send.'
$enableCursor = $ast.Find({ param($node)
    $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Enable-AgentCursor'
}, $true)
Assert-True ($preflight.Extent.EndOffset -lt $enableCursor.Extent.StartOffset) 'Draft refusal must precede cursor/input actions.'
$OverwriteInput = $true
Assert-True ($null -eq (& ([scriptblock]::Create($preflight.Extent.Text)))) 'Explicit overwrite should bypass draft refusal.'
Assert-True (@($ast.ParamBlock.Parameters.Name.VariablePath.UserPath)[-2] -eq 'OverwriteInput') 'Draft switch must stay in its published position.'
$callerPath = Join-Path (Split-Path -Parent $SenderPath) 'Invoke-CopilotReview.ps1'
$callerAst = [Management.Automation.Language.Parser]::ParseFile($callerPath, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
$sendCommand = $callerAst.Find({ param($node)
    $node -is [Management.Automation.Language.CommandAst] -and
    $node.InvocationOperator -eq [Management.Automation.Language.TokenKind]::Ampersand -and
    $node.CommandElements[0].Extent.Text -match 'Send-CopilotPrompt\.ps1'
}, $true)
Assert-True ($null -ne $sendCommand) 'Review wrapper sender call not found.'
$captureCall = [scriptblock]::Create($sendCommand.Extent.Text.Replace($sendCommand.CommandElements[0].Extent.Text, "'Capture-SendCall'"))
function Capture-SendCall {
    param($Hwnd, [switch]$Quiet, $Text, $ExePath, [switch]$OverwriteInput, [switch]$AllowOwnHost)
    return [pscustomobject]@{ OverwriteInput = [bool]$OverwriteInput; AllowOwnHost = [bool]$AllowOwnHost }
}
$Hwnd = '0x1234'
$text = 'mock prompt'
foreach ($OverwriteInput in @($false, $true)) {
    foreach ($AllowOwnHost in @($false, $true)) {
        $captured = & $captureCall
        Assert-True ($captured.OverwriteInput -eq $OverwriteInput) 'Review wrapper did not forward overwrite choice unchanged.'
        Assert-True ($captured.AllowOwnHost -eq $AllowOwnHost) 'Review wrapper did not forward own-host choice unchanged.'
    }
}
Assert-True (($callerAst.ParamBlock.Parameters[-1].Name.VariablePath.UserPath) -eq 'AllowOwnHost') 'Wrapper switch must preserve prior positional parameter order.'

$ownerProcess = Get-CimInstance Win32_Process -Filter "ProcessId = $PID"
$callerIds = @(Get-CallerProcessIds)
Assert-True ($callerIds[0] -eq $PID -and $callerIds -contains [int]$ownerProcess.ParentProcessId) 'Caller process chain must include this process and its parent.'
$script:ListWindowsError = ''
$script:fixtureWindows = @(
    [pscustomobject]@{ Hwnd = '0x1234'; Pid = 100; ProcessName = 'devenv' },
    [pscustomobject]@{ Hwnd = '0x2000'; Pid = 200; ProcessName = 'devenv' },
    [pscustomobject]@{ Hwnd = '0x3000'; Pid = 300; ProcessName = 'notepad' }
)
function Get-TopLevelWindows {
    if ($null -eq $script:fixtureWindows) { $script:ListWindowsError = 'listing failed'; return $null }
    return ,@($script:fixtureWindows)
}
$script:fixtureCallers = @(7, 100)
function Get-CallerProcessIds { if ($null -eq $script:fixtureCallers) { throw 'chain unreadable' }; return $script:fixtureCallers }
$Hwnd = '0x1234'
Assert-True ((Get-OwnHostError) -match 'OwnHostWindow') 'The caller host window was not refused.'
$Hwnd = '0x2000'
Assert-True ($null -eq (Get-OwnHostError)) 'A different devenv process (main or Insiders) must remain targetable.'
$Hwnd = '0x3000'
Assert-True ($null -eq (Get-OwnHostError)) 'A non-devenv process must remain targetable.'
$Hwnd = '0x9999'
Assert-True ((Get-OwnHostError) -match 'no longer exists') 'A stale handle was accepted.'
$Hwnd = '0x2000'
$script:fixtureWindows = $null
Assert-True ((Get-OwnHostError) -match 'OwnHostCheckFailed') 'An unreadable window list did not fail closed.'
$script:fixtureWindows = @([pscustomobject]@{ Hwnd = '0x2000'; Pid = 200; ProcessName = 'devenv' })
$script:fixtureCallers = $null
Assert-True ((Get-OwnHostError) -match 'OwnHostCheckFailed') 'An unreadable process chain did not fail closed.'
$ownGuard = $ast.EndBlock.Statements | Where-Object {
    $_ -is [Management.Automation.Language.IfStatementAst] -and $_.Extent.Text -match 'Get-OwnHostError'
} | Select-Object -First 1
Assert-True ($null -ne $ownGuard -and $ownGuard.Extent.EndOffset -lt $preflight.Extent.StartOffset) 'Own-host refusal must precede draft inspection and cursor actions.'
$script:fixtureWindows = @([pscustomobject]@{ Hwnd = '0x2000'; Pid = 100; ProcessName = 'devenv' })
$script:fixtureCallers = @(7, 100)
$AllowOwnHost = $false
$result = & ([scriptblock]::Create($ownGuard.Extent.Text))
Assert-True (-not $result.Sent -and $result.Attempts -eq 0 -and $result.Error -match 'OwnHostWindow') 'Default own-host guard did not return a refusal.'
$AllowOwnHost = $true
Assert-True ($null -eq (& ([scriptblock]::Create($ownGuard.Extent.Text)))) 'Explicit AllowOwnHost should bypass the guard.'
Assert-True (($ast.ParamBlock.Parameters[-1].Name.VariablePath.UserPath) -eq 'AllowOwnHost') 'Sender switch must preserve prior positional parameter order.'

$tryStatement = $ast.EndBlock.Statements | Where-Object { $_ -is [Management.Automation.Language.TryStatementAst] } | Select-Object -Last 1
$statements = @($tryStatement.Body.Statements)
$start = -1
for ($index = 0; $index -lt $statements.Count; $index++) {
    if ($statements[$index].Extent.Text -eq '$attempt = 0') { $start = $index; break }
}
if ($start -lt 0) { throw 'Sender loop could not be isolated.' }
$finalGuard = $statements | Where-Object {
    $_ -is [Management.Automation.Language.IfStatementAst] -and $_.Extent.Text -match 'Get-ChatDraftError'
} | Select-Object -Last 1
Assert-True ($null -ne $finalGuard -and $finalGuard.Extent.EndOffset -lt $statements[$start].Extent.StartOffset) 'Missing draft recheck before clearing.'
$OverwriteInput = $false
$script:textRead = 'draft appeared during navigation'
$result = & ([scriptblock]::Create($finalGuard.Extent.Text))
Assert-True (-not $result.Sent -and $result.Attempts -eq 0 -and $result.Error -match 'InputNotEmpty') 'Final guard did not preserve a newly exposed draft.'
$sendLoop = [scriptblock]::Create((@($statements | Select-Object -Skip $start | ForEach-Object { $_.Extent.Text }) -join "`n"))
$Hwnd = '0x1234'
$InputName = 'Ask Copilot'
$Text = 'original "quoted text"'
$Retries = 2
$NoSend = $false
$Quiet = $false
$AsJson = $false
$script:inputFixtures = @($inputElement)
$script:textSupported = $true
function Set-AgentForegroundWindow { param($Handle) return $true }
function Clear-ChatInput { $script:events.Add('clear') }
function Invoke-Ui {
    param([string[]]$Arguments)
    $script:events.Add($Arguments[0])
    return [pscustomobject]@{ success = $true }
}
foreach ($case in @('matching', 'different case', 'missing quotes', 'NoSend')) {
    $script:events = New-Object 'Collections.Generic.List[string]'
    $NoSend = $case -eq 'NoSend'
    $script:textRead = switch ($case) {
        'different case' { 'ORIGINAL "quoted text"' }
        'missing quotes' { 'original quoted text' }
        default { $Text }
    }
    $result = & $sendLoop 6>$null
    $shouldSend = $case -eq 'matching'
    Assert-True ($result.Sent -eq $shouldSend) "Unexpected send result: $case"
    Assert-True ((@($script:events | Where-Object { $_ -eq 'click' }).Count -gt 0) -eq $shouldSend) "Unexpected Send click: $case"
    Assert-True ($result.InputText -ceq $script:textRead) "InputText was not the independent read-back: $case"
    if ($case -in @('different case', 'missing quotes')) {
        Assert-True ($result.Attempts -eq 3 -and $result.Error -match 'read-back-mismatch') 'Mismatch retries/result changed.'
    }
}
Write-Output "PASS: $script:assertions assertions; native quoted-argument round trips, mocked read-back/send gating, draft refusal/rechecks, own-host refusal and caller switch forwarding; no chat or UI actions."
