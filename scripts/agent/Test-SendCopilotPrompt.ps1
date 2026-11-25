<#
.SYNOPSIS
Offline sender native-argument, read-back, draft/own-host guards and busy-chat steering regression checks; no chat interaction.
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
    [string]$SenderPath,
    [string]$TemporaryRoot = [IO.Path]::GetTempPath()
)
$ErrorActionPreference = 'Stop'
# Default set in the body: under powershell.exe 5.1 -File, $PSScriptRoot is empty inside a param() default of an advanced script.
if (-not $SenderPath) { $SenderPath = Join-Path $PSScriptRoot '..\..\agent-orchestrator\scripts\Send-CopilotPrompt.ps1' }
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
foreach ($name in @('ConvertTo-NativeArgument', 'Invoke-Ui', 'Get-ChatInputText', 'Get-ChatDraftError', 'Get-ChatActionButtons', 'Get-ChatSteerError', 'Get-CallerProcessIds', 'Get-OwnHostError', 'Write-Result', 'Set-StageMark')) {
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
$Steer = $false
$Trace = $false
foreach ($draftText in @('user draft', ' ', 'original "quoted text"')) {
    $script:textRead = $draftText
    Assert-True ((Get-ChatDraftError) -match 'InputNotEmpty') 'A non-empty draft was accepted.'
    Assert-True ($script:textRead -ceq $draftText) 'Draft inspection changed the text.'
}
$script:textRead = ''
Assert-True ($null -eq (Get-ChatDraftError)) 'An empty input should be allowed.'
# The draft check must search the window for the input once, not once to count and again to read.
$script:findCount = 0
function Get-ChatInputElements { $script:findCount++; return $script:inputFixtures }
Assert-True ($null -eq (Get-ChatDraftError) -and $script:findCount -eq 1) 'An empty-input draft check must search for the input once.'
$script:findCount = 0
$script:textRead = 'user draft'
Assert-True ((Get-ChatDraftError) -match 'InputNotEmpty' -and $script:findCount -eq 1) 'A refused draft check must search for the input once.'
$script:textRead = ''
function Get-ChatInputElements { return $script:inputFixtures }
foreach ($useValue in @($false, $true)) {
    $script:valueSupported = $useValue
    foreach ($case in @(
        @{ Draft = ' '; Length = 1; Points = 1; Codes = 'U+0020(1)' },
        @{ Draft = ([string][char]10); Length = 1; Points = 1; Codes = 'U+000A(1)' },
        @{ Draft = ([string][char]0x200B); Length = 1; Points = 1; Codes = 'U+200B(1)' },
        @{ Draft = ([string][char]0xFEFF); Length = 1; Points = 1; Codes = 'U+FEFF(1)' },
        @{ Draft = 'Ask Copilot'; Length = 11; Points = 11; Codes = 'U+0041(1)' },
        @{ Draft = 'attachment.txt'; Length = 14; Points = 14; Codes = 'U+002E(1)' },
        @{ Draft = ([char]::ConvertFromUtf32(0x1F600) + [char]::ConvertFromUtf32(0x1F600)); Length = 4; Points = 2; Codes = 'U+1F600(2)' },
        @{ Draft = ([string][char]0xD800); Length = 1; Points = 1; Codes = 'U+D800(1)' }
    )) {
        $script:valueRead = $case.Draft
        $script:textRead = $case.Draft
        $draftError = Get-ChatDraftError
        Assert-True ($draftError -match 'InputNotEmpty') 'Invisible/provider-like text must still be refused by default.'
        Assert-True ($draftError.Contains("DraftLength=$($case.Length); CodePointCount=$($case.Points);")) 'Draft diagnostic lengths changed.'
        Assert-True ($draftError.Contains($case.Codes)) 'Draft diagnostic omitted expected character codes/counts.'
        Assert-True ($draftError -match 'Codes=(U\+[0-9A-F]+\([0-9]+\),?)+\. Nothing was typed;') 'Draft diagnostic must contain only codes/counts, not input text.'
        Assert-True ((Get-ChatInputText) -ceq $case.Draft) 'Diagnostics changed the draft.'
    }
    $script:valueRead = ''
    $script:textRead = ''
    Assert-True ($null -eq (Get-ChatDraftError)) 'An empty pattern read must remain allowed.'
}
$script:valueRead = ''
$script:textRead = 'TextPattern-only content'
Assert-True ($null -eq (Get-ChatDraftError)) 'An empty ValuePattern must win over non-empty TextPattern.'
$script:valueRead = 'ValuePattern-only content'
$script:textRead = ''
Assert-True ((Get-ChatDraftError) -match 'DraftLength=25;') 'A non-empty ValuePattern must win over empty TextPattern.'
$script:valueSupported = $false
$script:textRead = -join (33..72 | ForEach-Object { [char]$_ })
$draftError = Get-ChatDraftError
Assert-True ($draftError -match 'DistinctCodes=40;') 'Distinct-code diagnostic count changed.'
Assert-True ([regex]::Matches($draftError, 'U\+[0-9A-F]+\(').Count -eq 32) 'Diagnostic output must be bounded to 32 distinct codes.'
Assert-True (-not $draftError.Contains($script:textRead)) 'Diagnostic leaked the draft text.'
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
Assert-True (@($ast.ParamBlock.Parameters.Name.VariablePath.UserPath)[-4] -eq 'OverwriteInput') 'Draft switch must stay in its published position.'
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
# The snapshot walk must give the same chain as the earlier one-lookup-per-ancestor walk.
$legacyIds = New-Object 'System.Collections.Generic.List[int]'
$legacyCurrent = $ownerProcess
$legacyIds.Add([int]$legacyCurrent.ProcessId)
for ($legacyDepth = 0; $legacyDepth -lt 32 -and $legacyCurrent.ParentProcessId; $legacyDepth++) {
    $legacyParent = Get-CimInstance Win32_Process -Filter "ProcessId = $($legacyCurrent.ParentProcessId)"
    if (-not $legacyParent -or $legacyParent.CreationDate -gt $legacyCurrent.CreationDate -or $legacyIds.Contains([int]$legacyParent.ProcessId)) { break }
    $legacyIds.Add([int]$legacyParent.ProcessId); $legacyCurrent = $legacyParent
}
Assert-True ((@($legacyIds.ToArray()) -join ',') -ceq (@($callerIds) -join ',')) 'The snapshot process chain must equal the per-lookup chain.'
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
# Banner lookup: a targeted AutomationId search, never a full-tree dump, and a failed read refuses.
$bannerIdsFunction = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-ChatBannerIds' }, $true)
$bannerElementsFunction = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-ChatBannerElements' }, $true)
Assert-True ($null -ne $bannerIdsFunction -and $null -ne $bannerElementsFunction) 'Banner lookup functions are missing.'
. ([scriptblock]::Create($bannerIdsFunction.Extent.Text))
Assert-True ($bannerElementsFunction.Extent.Text -match 'HarnessWorkspaceMismatchBanner' -and $bannerElementsFunction.Extent.Text -match 'WorkspaceTrustWarningBanner') 'The banner lookup must search both banner ids.'
Assert-True ($ast.Extent.Text -notmatch 'inspect --hwnd \$Hwnd --maxDepth 25') 'The banner check must not dump the whole tree with inspect.'
Assert-True ($ast.Extent.Text -match 'BannerCheckFailed') 'A failed banner read must refuse instead of reading as no banner.'
function New-BannerElement([string]$Id) { [pscustomobject]@{ Current = [pscustomobject]@{ AutomationId = $Id } } }
$script:bannerFixtures = @()
function Get-ChatBannerElements { return $script:bannerFixtures }
Assert-True (@(Get-ChatBannerIds).Count -eq 0) 'No banner element must give no banner ids.'
$script:bannerFixtures = @(New-BannerElement 'WorkspaceTrustWarningBanner')
Assert-True ((@(Get-ChatBannerIds) -join ',') -ceq 'WorkspaceTrustWarningBanner') 'A trust banner must be reported.'
$script:bannerFixtures = @((New-BannerElement 'HarnessWorkspaceMismatchBanner'), (New-BannerElement 'WorkspaceTrustWarningBanner'), (New-BannerElement 'WorkspaceTrustWarningBanner'))
Assert-True ((@(Get-ChatBannerIds | Sort-Object) -join ',') -ceq 'HarnessWorkspaceMismatchBanner,WorkspaceTrustWarningBanner') 'Both banners must be reported once each.'
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
Assert-True (($ast.ParamBlock.Parameters[-3].Name.VariablePath.UserPath) -eq 'AllowOwnHost') 'Sender switch must preserve prior positional parameter order.'
Assert-True (($ast.ParamBlock.Parameters[-2].Name.VariablePath.UserPath) -eq 'Steer') 'Steer must be appended after existing positional parameters.'
Assert-True (($ast.ParamBlock.Parameters[-1].Name.VariablePath.UserPath) -eq 'Trace') 'Trace must be appended after existing positional parameters.'

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
function New-MockChatButton([string]$Id, [string]$Name, [bool]$Enabled = $true, [bool]$Offscreen = $false, [bool]$Invokable = $true) {
    $button = [pscustomobject]@{
        Current = [pscustomobject]@{ AutomationId = $Id; Name = $Name; IsEnabled = $Enabled; IsOffscreen = $Offscreen; ClassName = 'Button'; ControlType = [Windows.Automation.ControlType]::Button.Id }
        Invokable = $Invokable
    }
    $button | Add-Member -MemberType ScriptMethod -Name TryGetCurrentPattern -Value {
        param($patternId, $patternReference)
        if ($patternId -eq [Windows.Automation.InvokePattern]::Pattern -and $this.Invokable) {
            $patternReference.Value = [pscustomobject]@{}
            return $true
        }
        return $false
    }
    return $button
}
$stopButton = New-MockChatButton 'CancelButton' 'Cancel'
$steerButton = New-MockChatButton 'SteerButton' 'Steer'
$sendButton = New-MockChatButton 'SendButton' 'Send'
$actionFunction = $ast.Find({ param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-ChatActionButtons'
}, $true)
. ([scriptblock]::Create($actionFunction.Extent.Text.Replace(
    '$walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker', '$walker = $script:mockActionWalker')))
$pane = [pscustomobject]@{ Current = [pscustomobject]@{ ClassName = 'GenericPane'; Name = 'Chat' }; Parent = $null; Children = @() }
$area = [pscustomobject]@{ Current = [pscustomobject]@{ ClassName = 'WpfTextViewHost'; AutomationId = ''; ControlType = [Windows.Automation.ControlType]::Pane.Id }; Parent = $pane; Children = @() }
$messageList = [pscustomobject]@{
    Current = [pscustomobject]@{ ClassName = 'ChatSessionList'; AutomationId = 'session'; ControlType = [Windows.Automation.ControlType]::List.Id }
    Parent = $pane
    Children = @((New-MockChatButton 'SteerButton' 'Steer'), (New-MockChatButton 'CancelButton' 'Cancel'), (New-MockChatButton 'SendButton' 'Send'))
}
$area | Add-Member -MemberType ScriptMethod -Name FindAll -Value { param($scope, $condition) return @() }
$pane | Add-Member -MemberType ScriptMethod -Name FindAll -Value {
    param($scope, $condition)
    $script:actionScope = $scope
    $script:actionConditions = $condition.GetConditions()
    $ids = @($script:actionConditions[0].GetConditions() | ForEach-Object { $_.Value })
    $controlType = $script:actionConditions[1].Value
    $nodes = @($this.Children)
    if ($scope -eq [Windows.Automation.TreeScope]::Descendants) {
        foreach ($child in @($this.Children)) {
            if ($child.Current.ClassName -eq 'ChatSessionList') { $nodes += @($child.Children) }
        }
    }
    return @($nodes | Where-Object { $_.Current.AutomationId -in $ids -and $_.Current.ControlType -eq $controlType })
}
$inputElement | Add-Member -NotePropertyName Parent -NotePropertyValue $area
$script:mockActionWalker = New-Object PSObject
$script:mockActionWalker | Add-Member -MemberType ScriptMethod -Name GetParent -Value {
    param($node)
    $script:parentReads++
    return $node.Parent
}
$script:parentReads = 0
$pane.Children = @($area, $messageList, $stopButton)
$actionButtons = @(Get-ChatActionButtons)
Assert-True ($actionButtons.Count -eq 1 -and $actionButtons[0].Current.AutomationId -eq 'CancelButton' -and $script:parentReads -eq 2) 'Sibling-layout regression: CancelButton must be discovered on the Chat pane, not inside WpfTextViewHost.'
Assert-True ($null -eq (Get-ChatSteerError)) 'A direct-child CancelButton named Cancel must confirm busy.'
$pane.Children = @($area, $messageList, $steerButton)
$actionButtons = @(Get-ChatActionButtons)
Assert-True ($actionButtons.Count -eq 1 -and $actionButtons[0].Current.AutomationId -eq 'SteerButton') 'SteerButton must be discovered as a sibling of WpfTextViewHost.'
Assert-True ($null -eq (Get-ChatSteerError -RequireButton)) 'A direct-child SteerButton must be ready after verification.'
$pane.Children = @($area, $messageList, $sendButton)
$actionButtons = @(Get-ChatActionButtons)
Assert-True ($actionButtons.Count -eq 1 -and $actionButtons[0].Current.AutomationId -eq 'SendButton') 'SendButton must be discovered as a sibling for idle rejection.'
Assert-True ((Get-ChatSteerError) -match 'SteerRequiresBusy') 'A direct-child SendButton must refuse steering.'
Assert-True ($script:actionScope -eq [Windows.Automation.TreeScope]::Children -and $script:actionConditions[1].Value -eq [Windows.Automation.ControlType]::Button.Id) 'Action discovery must constrain direct-child scope and control type.'
$actionIds = @($script:actionConditions[0].GetConditions() | ForEach-Object { $_.Value })
Assert-True (($actionIds -join ',') -ceq 'CancelButton,SteerButton,SendButton') 'Action discovery selectors changed.'
$pane.Children = @($area, $messageList)
Assert-True (@(Get-ChatActionButtons).Count -eq 0) 'Nested message-list buttons must be excluded from direct-child discovery.'
Assert-True ((Get-ChatSteerError) -match 'SteerRequiresBusy') 'Historical Cancel/Steer buttons must not prove busy.'
Assert-True ((Get-ChatSteerError -RequireButton) -match 'SteerUnavailable') 'Historical SteerButton must not be invoked.'
$pane.Children = @($area, $messageList, $stopButton)
$area.Current.ClassName = 'ChatSessionList'
Assert-True (@(Get-ChatActionButtons).Count -eq 0) 'Historical message-list buttons must not prove busy.'
$area.Current.ClassName = 'WpfTextViewHost'
$area.Parent = $area
$script:parentReads = 0
Assert-True (@(Get-ChatActionButtons).Count -eq 0 -and $script:parentReads -eq 32) 'Missing pane/cyclic ancestry must fail closed with bounded traversal.'
$area.Parent = $pane
$script:inputFixtures = @($inputElement, $inputElement)
Assert-True (@(Get-ChatActionButtons).Count -eq 0) 'Ambiguous inputs must not prove busy.'
$script:inputFixtures = @($inputElement)
function Get-ChatActionButtons { return $script:buttonFixtures }
foreach ($case in @(
    @{ Buttons = @(); Busy = $false; Ready = $false },
    @{ Buttons = @($sendButton); Busy = $false; Ready = $false },
    @{ Buttons = @($stopButton); Busy = $true; Ready = $false },
    @{ Buttons = @($steerButton); Busy = $true; Ready = $true },
    @{ Buttons = @($steerButton, $steerButton); Busy = $false; Ready = $false },
    @{ Buttons = @($steerButton, $sendButton); Busy = $false; Ready = $false },
    @{ Buttons = @($steerButton, $stopButton); Busy = $false; Ready = $false },
    @{ Buttons = @((New-MockChatButton 'SteerButton' 'Steer' $false)); Busy = $false; Ready = $false },
    @{ Buttons = @((New-MockChatButton 'SteerButton' 'Steer' $true $true)); Busy = $false; Ready = $false },
    @{ Buttons = @((New-MockChatButton 'SteerButton' 'Wrong')); Busy = $false; Ready = $false },
    @{ Buttons = @((New-MockChatButton 'SteerButton' 'Steer' $true $false $false)); Busy = $true; Ready = $false },
    @{ Buttons = @((New-MockChatButton 'CancelButton' 'Stop' $false)); Busy = $false; Ready = $false }
)) {
    $script:buttonFixtures = $case.Buttons
    Assert-True (($null -eq (Get-ChatSteerError)) -eq $case.Busy) 'Busy-state steer precondition changed.'
    Assert-True (($null -eq (Get-ChatSteerError -RequireButton)) -eq $case.Ready) 'Steer readiness must require one visible enabled invokable button and no Send.'
}
$steerPreflight = $ast.EndBlock.Statements | Where-Object {
    $_ -is [Management.Automation.Language.IfStatementAst] -and $_.Extent.Text -match '^if \(\$Steer\)'
} | Select-Object -First 1
Assert-True ($null -ne $steerPreflight -and $steerPreflight.Extent.EndOffset -lt $enableCursor.Extent.StartOffset) 'Steer preflight must precede cursor/navigation/input actions.'
$Steer = $true
$NewSession = $true
$result = & ([scriptblock]::Create($steerPreflight.Extent.Text))
Assert-True (-not $result.Sent -and $result.Attempts -eq 0 -and $result.Error -match 'SteerRequiresExistingChat' -and [string]::IsNullOrEmpty($result.InputText)) 'Steer must refuse NewSession without input actions.'
$NewSession = $false
$script:buttonFixtures = @()
$result = & ([scriptblock]::Create($steerPreflight.Extent.Text))
Assert-True (-not $result.Sent -and $result.Attempts -eq 0 -and $result.Error -match 'SteerRequiresBusy') 'Steer must refuse an unverified/idle target before typing.'
$OverwriteInput = $false
$script:textRead = ' '
$result = & ([scriptblock]::Create($preflight.Extent.Text))
Assert-True (-not $result.Sent -and $result.Error -match 'InputNotEmpty') 'Steer must not bypass the whitespace draft preflight.'
$script:textRead = 'draft appeared during navigation'
$result = & ([scriptblock]::Create($finalGuard.Extent.Text))
Assert-True (-not $result.Sent -and $result.Error -match 'InputNotEmpty') 'Steer must not bypass the final draft recheck.'
$AllowOwnHost = $false
$script:fixtureWindows = @([pscustomobject]@{ Hwnd = $Hwnd; Pid = 100; ProcessName = 'devenv' })
$result = & ([scriptblock]::Create($ownGuard.Extent.Text))
Assert-True (-not $result.Sent -and $result.Error -match 'OwnHostWindow') 'Steer must not bypass own-host refusal.'

$tabNavigation = $statements | Where-Object { $_.Extent.Text -match '^if \(-not \$NoNavigate.*Select-ChatTabIfHidden' } | Select-Object -First 1
$sessionNavigation = $statements | Where-Object { $_.Extent.Text -match '^if \(\$NewSession\)' } | Select-Object -First 1
Assert-True ($null -ne $tabNavigation -and $null -ne $sessionNavigation) 'Navigation statements must be available for offline verification.'
$navigation = [scriptblock]::Create($tabNavigation.Extent.Text + [Environment]::NewLine + $sessionNavigation.Extent.Text)
function Select-ChatTabIfHidden { $script:events.Add('navigate') }
function Ensure-ChatInput { $script:events.Add('ensure-session'); return $null }
function Test-ChatInput { param($TimeoutMs) return $script:inputReady }
$NoNavigate = $false
$script:events = New-Object 'Collections.Generic.List[string]'
$script:inputReady = $true
$result = & $navigation
Assert-True ($null -eq $result -and $script:events.Count -eq 0) 'Steer must not navigate/create a chat even without NoNavigate.'
$script:inputReady = $false
$result = & $navigation
Assert-True (-not $result.Sent -and $result.Error -match 'SteerRequiresBusy' -and $script:events.Count -eq 0) 'Lost steer input must fail without navigation or misleading NoNavigate claims.'
$Steer = $false
$script:inputReady = $true
$null = & $navigation
Assert-True (($script:events -join ',') -ceq 'navigate,ensure-session') 'Default Send navigation behavior must remain unchanged.'
$Steer = $true

function Get-ChatActionButtons {
    if ($script:pasted) { return $script:afterPasteButtons }
    return $script:beforePasteButtons
}
function Clear-ChatInput { $script:events.Add('clear'); $script:pasted = $false }
function Invoke-Ui {
    param([string[]]$Arguments)
    if ($Arguments[0] -eq 'type') {
        $script:events.Add('type')
        $script:pasted = $true
        $script:pasteCount++
        $script:textRead = if ($script:steerCase -eq 'mismatch' -or ($script:steerCase -eq 'retry' -and $script:pasteCount -eq 1)) { 'wrong read-back' } else { $Text }
    }
    elseif ($Arguments[0] -eq 'click') {
        $buttonId = $Arguments[[array]::IndexOf($Arguments, '--value') + 1]
        $script:events.Add('click:' + $buttonId)
        if ($script:steerCase -eq 'click failure') { return [pscustomobject]@{ success = $false; error = 'element-not-found'; message = $Text } }
    }
    return [pscustomobject]@{ success = $true }
}
foreach ($script:steerCase in @('success', 'idle before paste', 'missing Steer', 'disabled Steer', 'busy lost after paste', 'mismatch', 'retry', 'NoSend', 'click failure', 'Quiet')) {
    $script:events = New-Object 'Collections.Generic.List[string]'
    $script:pasteCount = 0
    $script:pasted = $false
    $script:beforePasteButtons = @($stopButton)
    $script:afterPasteButtons = @($steerButton)
    if ($script:steerCase -eq 'idle before paste') { $script:beforePasteButtons = @($sendButton) }
    if ($script:steerCase -eq 'missing Steer') { $script:afterPasteButtons = @($stopButton) }
    if ($script:steerCase -eq 'disabled Steer') { $script:afterPasteButtons = @((New-MockChatButton 'SteerButton' 'Steer' $false)) }
    if ($script:steerCase -eq 'busy lost after paste') { $script:afterPasteButtons = @($sendButton) }
    $NoSend = $script:steerCase -eq 'NoSend'
    $Quiet = $script:steerCase -eq 'Quiet'
    $result = & $sendLoop 6>$null
    $shouldSteer = $script:steerCase -in @('success', 'retry', 'Quiet')
    $clicks = @($script:events | Where-Object { $_ -like 'click:*' })
    Assert-True ($result.Sent -eq $shouldSteer) "Unexpected steer result: $script:steerCase"
    Assert-True (@($clicks | Where-Object { $_ -ne 'click:SteerButton' }).Count -eq 0) 'Steer must never click Send or Stop.'
    Assert-True ($clicks.Count -le 1) 'Steer must not retry/fall back after a click failure.'
    if ($script:steerCase -eq 'idle before paste') {
        Assert-True ($script:pasteCount -eq 0 -and $result.Error -match 'SteerRequiresBusy') 'Busy must be rechecked before clearing/pasting.'
    }
    elseif ($script:steerCase -in @('missing Steer', 'disabled Steer', 'busy lost after paste', 'click failure')) {
        Assert-True ($result.Error -match '^Steer(Unavailable|ClickFailed):' -and -not $result.Error.Contains($Text) -and [string]::IsNullOrEmpty($result.InputText)) 'Steer failure must be explicit and text-free.'
        Assert-True ($script:pasted -and $script:textRead -ceq $Text) 'Verified unsent text must be preserved as a draft.'
    }
    elseif ($script:steerCase -eq 'mismatch') {
        Assert-True ($clicks.Count -eq 0 -and $result.Attempts -eq 3 -and $result.Error -match 'read-back-mismatch') 'Steer must retain exact read-back and bounded retries.'
    }
    elseif ($script:steerCase -eq 'NoSend') {
        Assert-True ($clicks.Count -eq 0 -and [string]::IsNullOrEmpty($result.Error)) 'NoSend must suppress Steer submission.'
    }
    elseif ($script:steerCase -eq 'Quiet') {
        Assert-True ([string]::IsNullOrEmpty($result.InputText) -and $clicks.Count -eq 1) 'Quiet must suppress successful steer text.'
    }
    else {
        Assert-True ($clicks.Count -eq 1 -and $result.InputText -ceq $Text) 'Steer must submit only after exact independent read-back.'
        if ($script:steerCase -eq 'retry') { Assert-True ($result.Attempts -eq 2) 'Steer paste retry count changed.' }
    }
}
Write-Output "PASS: $script:assertions assertions; native quoted-argument round trips, mocked read-back/send/steer gating, busy/button checks, draft refusal/rechecks, own-host refusal and caller switch forwarding; no chat or UI actions."
