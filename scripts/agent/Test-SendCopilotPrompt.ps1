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
foreach ($name in @('ConvertTo-NativeArgument', 'Invoke-Ui', 'Get-ChatInputText', 'Get-ChatDraftError', 'Get-ChatActionButtons', 'Get-ChatSteerError', 'Get-CallerProcessIds', 'Get-OwnHostError', 'Set-HeldChatInput', 'Get-ChatInputElementsCached', 'Invoke-ChatSendButton', 'Get-WindowProcessId', 'Invoke-ChatPasteAtFocus', 'Write-Result', 'Set-StageMark', 'Start-InputBlock', 'Get-InputBlockInterruption', 'Update-InputBlockStamp', 'Stop-InputBlock')) {
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
# The input block (quiet wait, lock, hand-back) is off in these checks; its own tests set what they need.
$script:InputBlockStarted = $false; $script:UiLock = $null; $script:UserContext = $null; $script:BlockStamp = [uint32]0; $script:FocusResult = $null
$IgnoreUserActivity = $false; $QuietSeconds = 3; $MaxWaitSeconds = 120; $SpeakRequest = $false; $NoRestoreFocus = $false
function Exit-AgentUiLock { param($Lock) }
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
Assert-True (@($ast.ParamBlock.Parameters.Name.VariablePath.UserPath)[-10] -eq 'OverwriteInput') 'Draft switch must stay in its published position.'
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
Assert-True ((Get-WindowProcessId) -eq 0) 'Without the native helper loaded the window process must read as unknown (0), so the window listing is used.'
$script:fixtureWindowPid = 0
function Get-WindowProcessId { return $script:fixtureWindowPid }
$script:fixtureCallers = @(7, 100)
function Get-CallerProcessIds { if ($null -eq $script:fixtureCallers) { throw 'chain unreadable' }; return $script:fixtureCallers }
$Hwnd = '0x1234'
Assert-True ((Get-OwnHostError) -match 'OwnHostWindow') 'The caller host window was not refused.'
$Hwnd = '0x2000'
Assert-True ($null -eq (Get-OwnHostError)) 'A different devenv process (main or Insiders) must remain targetable.'
$Hwnd = '0x3000'
Assert-True ($null -eq (Get-OwnHostError)) 'A non-devenv process must remain targetable.'
$Hwnd = '0x9999'
$script:otherDesktop = $false
function Test-TargetOnOtherDesktop { return $script:otherDesktop }
Assert-True ((Get-OwnHostError) -match 'no longer exists') 'A stale handle was accepted.'
$script:otherDesktop = $true
$desktopError = Get-OwnHostError
Assert-True ($desktopError -match 'another virtual desktop' -and $desktopError -notmatch 'no longer exists' -and $desktopError -match 'nothing was typed') 'A window on another virtual desktop must be refused with its own explanation, not reported as gone.'
$script:otherDesktop = $false
$Hwnd = '0x2000'
$script:fixtureWindows = $null
Assert-True ((Get-OwnHostError) -match 'OwnHostCheckFailed') 'An unreadable window list did not fail closed.'
$script:fixtureWindows = @([pscustomobject]@{ Hwnd = '0x2000'; Pid = 200; ProcessName = 'devenv' })
$script:fixtureCallers = $null
Assert-True ((Get-OwnHostError) -match 'OwnHostCheckFailed') 'An unreadable process chain did not fail closed.'
# Fast path: the window's process is read in this process, so no window listing is needed (an unreadable listing proves it).
$script:fixtureWindows = $null; $script:fixtureWindowPid = 200; $script:fixtureCallers = @(7, 100); $script:otherDesktop = $false
Assert-True ($null -eq (Get-OwnHostError)) 'The fast path must allow a window of another process without listing windows.'
$script:fixtureCallers = @(7, 200)
Assert-True ((Get-OwnHostError) -match 'OwnHostWindow: window 0x2000 belongs to process 200') 'The fast path must refuse the calling host.'
$script:fixtureCallers = $null
Assert-True ((Get-OwnHostError) -match 'OwnHostCheckFailed') 'The fast path must fail closed on an unreadable process chain.'
$script:fixtureCallers = @(7, 100); $script:otherDesktop = $true
$fastDesktop = Get-OwnHostError
Assert-True ($fastDesktop -match 'another virtual desktop' -and $fastDesktop -match 'nothing was typed') 'The fast path must refuse a window on another virtual desktop.'
$script:otherDesktop = $false; $script:fixtureWindowPid = 0
Assert-True ((Get-OwnHostError) -match 'OwnHostCheckFailed') 'An unknown window process must fall back to the listing, which fails closed.'
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
# On-screen check: the input centre must lie in a monitor working area; unreadable geometry never blocks a send.
Add-Type -AssemblyName WindowsBase
$screenFunction = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-ChatInputScreenError' }, $true)
Assert-True ($null -ne $screenFunction) 'The on-screen input check is missing.'
. ([scriptblock]::Create($screenFunction.Extent.Text))
function New-ScreenArea([int]$L, [int]$T, [int]$R, [int]$B) { [pscustomobject]@{ Left = $L; Top = $T; Right = $R; Bottom = $B } }
function New-RectInput($rect) { [pscustomobject]@{ Current = [pscustomobject]@{ BoundingRectangle = $rect } } }
$script:areas = @(New-ScreenArea 0 0 1920 1008)
function Get-ChatScreenAreas { if ($script:areas -eq 'unreadable') { throw 'screens unreadable' }; return $script:areas }
function Test-ScreenCase([double[]]$Xywh, $Expect, [string]$Why) {
    $element = New-RectInput (New-Object System.Windows.Rect($Xywh[0], $Xywh[1], $Xywh[2], $Xywh[3]))
    $error1 = Get-ChatInputScreenError -Elements @($element)
    if ($Expect) { Assert-True ($error1 -match '^InputOffScreen:' -and $error1 -match 'Nothing was typed or clicked') "Expected an off-screen refusal: $Why" }
    else { Assert-True ($null -eq $error1) "Expected the input to count as on screen: $Why" }
}
Test-ScreenCase 128, 779, 510, 26 $false 'docked input on a 1920x1008 working area'
Test-ScreenCase 100, 985, 400, 40 $false 'partly below the working area but the centre is visible'
Test-ScreenCase 1292, 1520, 366, 26 $true 'input below the screen (the observed case)'
Test-ScreenCase 100, 1030, 400, 20 $true 'input centre under the taskbar band'
Test-ScreenCase 2500, 500, 300, 30 $true 'input to the right of every screen'
Test-ScreenCase -3000, 500, 300, 30 $true 'input to the left of every screen'
Test-ScreenCase 0, 0, 0, 0 $true 'zero-size rectangle'
$script:areas = @((New-ScreenArea 0 0 1920 1008), (New-ScreenArea 1920 0 3840 1040))
Test-ScreenCase 2500, 500, 300, 30 $false 'input on a second monitor'
Test-ScreenCase 2500, 1100, 300, 30 $true 'input below the second monitor'
$script:areas = @(New-ScreenArea 0 0 1920 1008)
$emptyError = Get-ChatInputScreenError -Elements @(New-RectInput ([System.Windows.Rect]::Empty))
Assert-True ($emptyError -match '^InputOffScreen: the chat input has no visible rectangle') 'An empty rectangle must be refused with its own wording.'
Assert-True ($null -eq (Get-ChatInputScreenError -Elements @())) 'A missing input is left to the draft check.'
Assert-True ($null -eq (Get-ChatInputScreenError -Elements @((New-RectInput (New-Object System.Windows.Rect(1, 1, 5, 5))), (New-RectInput (New-Object System.Windows.Rect(1, 1, 5, 5)))))) 'An ambiguous input is left to the draft check.'
$script:areas = 'unreadable'
Assert-True ($null -eq (Get-ChatInputScreenError -Elements @((New-RectInput (New-Object System.Windows.Rect(1292, 1520, 366, 26)))))) 'Unreadable screens must never block a send.'
$script:areas = @()
Assert-True ($null -eq (Get-ChatInputScreenError -Elements @((New-RectInput (New-Object System.Windows.Rect(1292, 1520, 366, 26)))))) 'No screens must never block a send.'
Assert-True ($null -eq (Get-ChatInputScreenError -Elements @([pscustomobject]@{ Current = $null }))) 'An unreadable rectangle must never block a send.'
$script:areas = @(New-ScreenArea 0 0 1920 1008)
# ---- reuse of the input element found a moment ago (revalidated; never a stale or changed element) ----
$InputName = 'Ask Copilot'
$Conservative = $false
$script:HeldInput = $null; $script:HeldInputRect = $null; $script:HeldInputAt = 0
$script:searches = 0
$script:searchResult = @()
function Get-ChatInputElements { $script:searches++; return @($script:searchResult) }
function New-HeldInput([string]$Name = 'Ask Copilot', [bool]$Enabled = $true, [bool]$Offscreen = $false, $Rect = (New-Object System.Windows.Rect(100, 700, 400, 26))) {
    [pscustomobject]@{ Current = [pscustomobject]@{ Name = $Name; IsEnabled = $Enabled; IsOffscreen = $Offscreen; BoundingRectangle = $Rect } }
}
$first = New-HeldInput
$script:searchResult = @($first)
$got = @(Get-ChatInputElementsCached)
Assert-True ($script:searches -eq 1 -and $got.Count -eq 1 -and [object]::ReferenceEquals($got[0], $first)) 'The first lookup must search and keep the single input.'
$got = @(Get-ChatInputElementsCached)
Assert-True ($script:searches -eq 1 -and [object]::ReferenceEquals($got[0], $first)) 'A young, unchanged input must be reused without another search.'
$first.Current.BoundingRectangle = New-Object System.Windows.Rect(100, 701, 400, 26)
$second = New-HeldInput -Rect (New-Object System.Windows.Rect(100, 701, 400, 26)); $script:searchResult = @($second)
$got = @(Get-ChatInputElementsCached)
Assert-True ($script:searches -eq 2 -and [object]::ReferenceEquals($got[0], $second)) 'An input whose rectangle changed must be searched for again.'
foreach ($case in @(
    @{ Label = 'disabled'; Change = { $second.Current.IsEnabled = $false } },
    @{ Label = 'off-screen'; Change = { $second.Current.IsOffscreen = $true } },
    @{ Label = 'renamed'; Change = { $second.Current.Name = 'Something else' } }
)) {
    $fresh = New-HeldInput -Rect (New-Object System.Windows.Rect(100, 701, 400, 26)); $script:searchResult = @($fresh)
    Set-HeldChatInput -Elements @($second)
    $before = $script:searches
    & $case.Change
    $got = @(Get-ChatInputElementsCached)
    Assert-True ($script:searches -eq $before + 1 -and [object]::ReferenceEquals($got[0], $fresh)) "A $($case.Label) input must be searched for again."
    $second.Current.IsEnabled = $true; $second.Current.IsOffscreen = $false; $second.Current.Name = 'Ask Copilot'
}
$script:searchResult = @($first); Set-HeldChatInput -Elements @($second)
$script:HeldInputAt = [Diagnostics.Stopwatch]::GetTimestamp() - (11 * [Diagnostics.Stopwatch]::Frequency)
$before = $script:searches; $null = Get-ChatInputElementsCached
Assert-True ($script:searches -eq $before + 1) 'An input held for more than the age limit must be searched for again.'
$stale = [pscustomobject]@{}; $stale | Add-Member -MemberType ScriptProperty -Name Current -Value { throw 'ElementNotAvailable' }
$script:HeldInput = $stale; $script:HeldInputAt = [Diagnostics.Stopwatch]::GetTimestamp()
$script:searchResult = @($second); $before = $script:searches
$got = @(Get-ChatInputElementsCached)
Assert-True ($script:searches -eq $before + 1 -and [object]::ReferenceEquals($got[0], $second)) 'A stale element (error reading it) must fall back to a new search.'
$script:searchResult = @($first, $second); Set-HeldChatInput -Elements @($first, $second)
Assert-True ($null -eq $script:HeldInput) 'Two inputs must never be held as one.'
$script:searchResult = @(); $before = $script:searches; $got = @(Get-ChatInputElementsCached)
Assert-True ($got.Count -eq 0 -and $null -eq $script:HeldInput) 'No input must stay no input.'
$screenStatement = $ast.Extent.Text
Assert-True ($screenStatement -match '\$inputElements = @\(Get-ChatInputElementsCached\)') 'The screen check must take the input through the revalidating lookup.'
Assert-True ($screenStatement -match 'Get-ChatInputText -Elements @\(Get-ChatInputElementsCached\)') 'The read-back must read the same revalidated element.'
Assert-True ($screenStatement -notmatch '\$inputElements = @\(Get-ChatInputElements\)') 'The screen check must not search the whole window itself.'
function Get-ChatInputElements { return $script:inputFixtures }   # back to the shared fixture search for the checks below
# ---- in-process Send click: only when unambiguous, never a second send after an attempted Invoke ----
$savedValueSupported = $script:valueSupported; $savedValueRead = $script:valueRead
$script:invokeCount = 0; $script:invokeThrows = $false; $script:hasInvoke = $true
function New-ActionButton([string]$Id, [bool]$Enabled = $true, [bool]$Offscreen = $false) {
    $b = [pscustomobject]@{ Current = [pscustomobject]@{ AutomationId = $Id; IsEnabled = $Enabled; IsOffscreen = $Offscreen } }
    $b | Add-Member -MemberType ScriptMethod -Name TryGetCurrentPattern -Value {
        param($patternId, $reference)
        if (-not $script:hasInvoke) { return $false }
        $reference.Value = ([pscustomobject]@{} | Add-Member -MemberType ScriptMethod -Name Invoke -Value { $script:invokeCount++; if ($script:invokeThrows) { throw 'ElementNotAvailable' } } -PassThru)
        return $true
    }
    return $b
}
function Get-ChatInputElementsCached { param([int]$MaxAgeSeconds = 10) return $inputElement }
$script:actionButtons = @((New-ActionButton 'SendButton'))
$script:actionButtonsThrow = $false
function Get-ChatActionButtons { param([object[]]$Elements) if ($script:actionButtonsThrow) { throw 'tree unreadable' }; return $script:actionButtons }
Assert-True ((Invoke-ChatSendButton) -eq $true -and $script:invokeCount -eq 1) 'A single enabled, visible SendButton must be invoked once in this process.'
foreach ($case in @(
    @{ Label = 'disabled'; Buttons = { @((New-ActionButton 'SendButton' $false)) } },
    @{ Label = 'off-screen'; Buttons = { @((New-ActionButton 'SendButton' $true $true)) } },
    @{ Label = 'busy (Cancel beside Send)'; Buttons = { @((New-ActionButton 'CancelButton'), (New-ActionButton 'SendButton')) } },
    @{ Label = 'missing'; Buttons = { @() } },
    @{ Label = 'duplicated'; Buttons = { @((New-ActionButton 'SendButton'), (New-ActionButton 'SendButton')) } },
    @{ Label = 'only Steer'; Buttons = { @((New-ActionButton 'SteerButton')) } }
)) {
    $script:actionButtons = & $case.Buttons; $script:invokeCount = 0
    Assert-True ((Invoke-ChatSendButton) -eq $false -and $script:invokeCount -eq 0) "A $($case.Label) Send button must be left to the helper's click, with nothing invoked."
}
$script:actionButtons = @((New-ActionButton 'SendButton')); $script:hasInvoke = $false; $script:invokeCount = 0
Assert-True ((Invoke-ChatSendButton) -eq $false -and $script:invokeCount -eq 0) 'A Send button without InvokePattern must fall back to the helper.'
$script:hasInvoke = $true; $script:actionButtonsThrow = $true
Assert-True ((Invoke-ChatSendButton) -eq $false -and $script:invokeCount -eq 0) 'An unreadable button tree must fall back to the helper.'
$script:actionButtonsThrow = $false; $script:invokeThrows = $true
$script:valueSupported = $true; $script:valueRead = ''
Assert-True ((Invoke-ChatSendButton) -eq $true -and $script:invokeCount -eq 1) 'An Invoke error with an emptied input means the prompt went out.'
$script:valueRead = 'still here'; $script:invokeCount = 0
$threw = $false; try { $null = Invoke-ChatSendButton } catch { $threw = $true }
Assert-True ($threw -and $script:invokeCount -eq 1) 'An Invoke error with the prompt still in the input must be reported, and never retried here.'
$script:invokeThrows = $false; $script:valueSupported = $savedValueSupported; $script:valueRead = $savedValueRead
# ---- paste at the keyboard focus: only when the input holds the focus and the target window is in front ----
function New-FocusInput([bool]$Focus = $true, [bool]$Throws = $false) {
    $o = [pscustomobject]@{ Current = [pscustomobject]@{ HasKeyboardFocus = $Focus } }
    $o | Add-Member -MemberType ScriptMethod -Name SetFocus -Value { $script:focusCalls++; if ($script:focusThrows) { throw 'cannot focus' } } -PassThru
}
$savedHwnd = $Hwnd; $savedText = if (Test-Path variable:Text) { $Text } else { $null }
$script:focusCalls = 0; $script:focusThrows = $false; $script:uiCalls = New-Object 'Collections.Generic.List[string]'; $script:uiOk = $true
$Text = 'hello'; $Hwnd = '0x1234'; $script:foregroundNow = [IntPtr]0x1234
function Get-ChatInputElementsCached { param([int]$MaxAgeSeconds = 10) return $script:pasteInputs }
function Get-AgentForegroundHandle { return $script:foregroundNow }
function Invoke-Ui { param([string[]]$Arguments) $script:uiCalls.Add($Arguments -join ' '); return [pscustomobject]@{ success = $script:uiOk; error = $(if ($script:uiOk) { $null } else { 'clipboard-unavailable' }); message = $null } }
$script:pasteInputs = @((New-FocusInput))
$r = Invoke-ChatPasteAtFocus
Assert-True ($r.success -and $script:focusCalls -eq 1 -and $script:uiCalls.Count -eq 1 -and $script:uiCalls[0] -ceq 'paste-text --hwnd 0x1234 --text hello --restoreDelayMs 100') 'A focused input in the foreground window must be pasted into with paste-text.'
foreach ($case in @(
    @{ Label = 'input without keyboard focus'; Setup = { $script:pasteInputs = @((New-FocusInput $false)) } },
    @{ Label = 'another window in front'; Setup = { $script:foregroundNow = [IntPtr]0x9999 } },
    @{ Label = 'no input'; Setup = { $script:pasteInputs = @() } },
    @{ Label = 'two inputs'; Setup = { $script:pasteInputs = @((New-FocusInput), (New-FocusInput)) } },
    @{ Label = 'empty text'; Setup = { $script:Text = $null; $Text = '' } },
    @{ Label = 'failing SetFocus'; Setup = { $script:focusThrows = $true } }
)) {
    $script:pasteInputs = @((New-FocusInput)); $script:foregroundNow = [IntPtr]0x1234; $Text = 'hello'; $script:focusThrows = $false
    $script:uiCalls.Clear(); & $case.Setup
    Assert-True ($null -eq (Invoke-ChatPasteAtFocus) -and $script:uiCalls.Count -eq 0) "A $($case.Label) must fall back to the old paste, with nothing pasted."
}
$script:pasteInputs = @((New-FocusInput)); $script:foregroundNow = [IntPtr]0x1234; $Text = 'hello'; $script:focusThrows = $false; $script:uiOk = $false; $script:uiCalls.Clear()
$r = Invoke-ChatPasteAtFocus
Assert-True (-not $r.success -and $r.error -ceq 'clipboard-unavailable' -and $null -eq $r.actual) 'A failed paste-text must be reported as a failed paste.'
$script:uiOk = $true
foreach ($name in @('Invoke-Ui', 'Get-ChatActionButtons', 'Get-ChatInputElementsCached')) {   # the real functions again for the checks below
    . ([scriptblock]::Create(($ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)).Extent.Text))
}
$script:HeldInput = $null   # nothing held from these checks for the send-loop tests
$Hwnd = $savedHwnd; if ($null -ne $savedText) { $Text = $savedText }
$sendSource = $ast.Extent.Text
Assert-True ($sendSource -match '\$typed = if \(\$Conservative\) \{ \$null \} else \{ Invoke-ChatPasteAtFocus \}\s+if \(\$null -eq \$typed\) \{ \$typed = Invoke-Ui @\(''type'', .*--paste.*--verify') 'The paste step must try the focus paste first and keep the verified type-paste as the fallback.'
Assert-True ($sendSource -match 'if \(-not \$Steer -and -not \$Conservative\) \{\s+try \{ \$invoked = Invoke-ChatSendButton \}') 'Only a plain, non-conservative send may use the in-process click; a steer or -Conservative keeps the helper.'
Assert-True ($sendSource -match '\$script:HeldInput -and -not \$Conservative') '-Conservative must search for the input again instead of reusing the held element.'
Assert-True ($sendSource -match '\$inputSeen -and \$null -ne \$script:SeenBannerIds') 'The banner stage may reuse the combined search only when the input was found by it.'
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
Assert-True (($ast.ParamBlock.Parameters[-9].Name.VariablePath.UserPath) -eq 'AllowOwnHost') 'Sender switch must preserve prior positional parameter order.'
Assert-True (($ast.ParamBlock.Parameters[-8].Name.VariablePath.UserPath) -eq 'Steer') 'Steer must be appended after existing positional parameters.'
Assert-True (($ast.ParamBlock.Parameters[-7].Name.VariablePath.UserPath) -eq 'Trace') 'Trace must be appended after existing positional parameters.'
$newNames = @($ast.ParamBlock.Parameters[-6..-1] | ForEach-Object { $_.Name.VariablePath.UserPath })
Assert-True (($newNames -join ',') -ceq 'QuietSeconds,MaxWaitSeconds,IgnoreUserActivity,NoRestoreFocus,SpeakRequest,Conservative') 'The user-activity parameters must be appended last, in this order.'
$quietParam = $ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'QuietSeconds' }
$waitParam = $ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'MaxWaitSeconds' }
Assert-True ($quietParam.DefaultValue.Extent.Text -eq '3' -and $waitParam.DefaultValue.Extent.Text -eq '120') 'Defaults must be a 3 second quiet period and a 120 second limit.'

# ---- the input block: lock, quiet wait, hand-back (real sender functions, mocked shared helpers) ----
$script:blockEvents = New-Object 'Collections.Generic.List[string]'
$script:lockAvailable = $true
$script:quietResult = [pscustomobject]@{ Quiet = $true; Reason = 'Idle'; InUse = $null }
$script:inputStamp = [uint32]500
$script:held = $null
$script:restoreReason = 'Restored'
$Hwnd = '0x1234'
$script:foregroundNow = [IntPtr]0x1234
function Enter-AgentUiLock { $script:blockEvents.Add('lock'); if ($script:lockAvailable) { return [pscustomobject]@{ Name = 'lock' } } else { return $null } }
function Exit-AgentUiLock { param($Lock) $script:blockEvents.Add('unlock') }
function Wait-AgentUserQuiet { param([int]$QuietMilliseconds, [int]$DraftQuietMilliseconds, [int]$MaxWaitMilliseconds, [switch]$SpeakRequest) $script:blockEvents.Add("wait:$QuietMilliseconds/$DraftQuietMilliseconds/$MaxWaitMilliseconds/$([bool]$SpeakRequest)"); return $script:quietResult }
function Save-AgentUserFocus { $script:blockEvents.Add('save'); return [pscustomobject]@{ Foreground = [IntPtr]0x9999 } }
function Enable-AgentCursor { param([int]$LeadMilliseconds = 800) $script:blockEvents.Add('cursor-on'); $script:lastLead = $LeadMilliseconds }
function Restore-AgentCursor { $script:blockEvents.Add('cursor-off') }
function Get-AgentInputStamp { return [uint32]$script:inputStamp }
function Get-AgentInputInUse { return $script:held }
function Get-AgentForegroundHandle { return $script:foregroundNow }
$script:pointer = [pscustomobject]@{ X = 10; Y = 10 }
$script:jitterOnly = $false   # when set, a changed stamp counts as pointer jitter, not as the person
function Get-AgentPointerPosition { return $script:pointer }
function Test-AgentMeaningfulInputSince { param([uint32]$Stamp, $Point, [int]$JitterPixels = 8) return (((Get-AgentInputStamp) -ne $Stamp) -and -not $script:jitterOnly) }
function Restore-AgentUserFocus { param($Context, [uint32]$OwnStamp, $OwnPoint, [IntPtr]$HeldHandle) $script:blockEvents.Add("restore:${OwnStamp}:$([int]$HeldHandle)"); return [pscustomobject]@{ Reason = $script:restoreReason } }
function Set-AgentOwnInputStamp { $script:blockEvents.Add('own-stamp') }
function Reset-Block {
    $script:blockEvents.Clear(); $script:InputBlockStarted = $false; $script:UiLock = $null; $script:UserContext = $null; $script:FocusResult = $null
    $script:lockAvailable = $true; $script:held = $null; $script:inputStamp = [uint32]500; $script:restoreReason = 'Restored'
    $script:foregroundNow = [IntPtr]0x1234
    $script:quietResult = [pscustomobject]@{ Quiet = $true; Reason = 'Idle'; InUse = $null }
    $script:jitterOnly = $false; $script:pointer = [pscustomobject]@{ X = 10; Y = 10 }
    $global:IgnoreUserActivity = $false
}
Reset-Block; $script:lockAvailable = $false
$blockError = Start-InputBlock
Assert-True ($blockError -match '^UiBusy' -and -not $script:InputBlockStarted -and ($script:blockEvents -join ',') -eq 'lock') 'A lock that stays taken must refuse before anything else happens.'
foreach ($case in @(
    @{ Result = @{ Quiet = $false; Reason = 'UserActive'; InUse = 'MouseButton' }; Match = '^UserActive \(MouseButton\)' },
    @{ Result = @{ Quiet = $false; Reason = 'UserActive'; InUse = $null }; Match = '^UserActive:' },
    @{ Result = @{ Quiet = $false; Reason = 'DoNotDisturb'; InUse = 'PresentationMode' }; Match = '^DoNotDisturb \(PresentationMode\)' },
    @{ Result = @{ Quiet = $false; Reason = 'SessionNotPresent'; InUse = 'SessionNotPresent' }; Match = '^SessionNotPresent' }
)) {
    Reset-Block; $script:quietResult = [pscustomobject]$case.Result
    $blockError = Start-InputBlock
    Assert-True ($blockError -match $case.Match -and $blockError -match 'Nothing was typed or clicked' -and -not $script:InputBlockStarted) "A refused quiet wait must say so and type nothing: $($case.Result.Reason)"
    Assert-True (($script:blockEvents -join ',') -ceq 'lock,wait:3000/6000/120000/False,unlock') 'A refused quiet wait must release the lock and never touch the cursor or the focus.'
}
Reset-Block
$blockError = Start-InputBlock
Assert-True ($null -eq $blockError -and $script:InputBlockStarted -and $script:BlockStamp -eq 500) 'A quiet person must let the block start and record the input stamp.'
Assert-True (($script:blockEvents -join ',') -ceq 'lock,wait:3000/6000/120000/False,save,cursor-on') 'The block must lock, wait, save the person''s focus, then show the red dot, in that order.'
$script:blockEvents.Clear()
Assert-True ($null -eq (Start-InputBlock) -and $script:blockEvents.Count -eq 0) 'Starting a started block must change nothing.'
Reset-Block; $SpeakRequest = $true; $null = Start-InputBlock; $SpeakRequest = $false
Assert-True (($script:blockEvents -join ',') -match 'wait:3000/6000/120000/True') '-SpeakRequest must reach the wait.'
Reset-Block; $QuietSeconds = 0; $null = Start-InputBlock; $QuietSeconds = 3
Assert-True (($script:blockEvents -join ',') -ceq 'lock,save,cursor-on') '-QuietSeconds 0 must skip the wait but still lock and hand back.'
Reset-Block; $global:IgnoreUserActivity = $true; $IgnoreUserActivity = $true; $null = Start-InputBlock
Assert-True (($script:blockEvents -join ',') -ceq 'lock,save,cursor-on') '-IgnoreUserActivity must skip the wait but still lock and hand back.'
$IgnoreUserActivity = $false
# interruptions between input steps
Reset-Block; $null = Start-InputBlock
Assert-True ($null -eq (Get-InputBlockInterruption)) 'No input since the block started must not interrupt.'
$script:inputStamp = [uint32]501
Assert-True ((Get-InputBlockInterruption) -match '^UserInput:' -and (Get-InputBlockInterruption) -match 'Text already pasted was left in the input') 'New input from the person must stop the send before the next step.'
Update-InputBlockStamp
Assert-True ($null -eq (Get-InputBlockInterruption)) 'After the agent''s own step the new stamp must be accepted.'
$script:held = 'MouseButton'
Assert-True ((Get-InputBlockInterruption) -match '^MouseButtonInUse:') 'A held mouse button must stop the send.'
$script:held = 'Modifier'
Assert-True ((Get-InputBlockInterruption) -match '^ModifierInUse:') 'A held modifier key must stop the send.'
$script:held = $null
$script:foregroundNow = [IntPtr]0x7777
Assert-True ($null -eq (Get-InputBlockInterruption) -and (Get-InputBlockInterruption -RequireForeground) -match '^ForegroundLost:') 'Another window in front must stop the send only when the target is required to be in front.'
$script:foregroundNow = [IntPtr]0x1234
$script:inputStamp = [uint32]502; $IgnoreUserActivity = $true
Assert-True ($null -eq (Get-InputBlockInterruption)) '-IgnoreUserActivity must disable the interruption checks.'
$IgnoreUserActivity = $false
Reset-Block
Assert-True ($null -eq (Get-InputBlockInterruption) -and ($script:inputStamp = [uint32]999) -eq 999 -and $null -eq (Get-InputBlockInterruption)) 'Before the block starts nothing can interrupt it.'
# pointer jitter is not the person typing: it must not stop a send, and it becomes the new baseline
Reset-Block; $null = Start-InputBlock
$script:inputStamp = [uint32]501; $script:jitterOnly = $true; $script:pointer = [pscustomobject]@{ X = 12; Y = 11 }
Assert-True ($null -eq (Get-InputBlockInterruption) -and $script:BlockStamp -eq 501 -and $script:BlockPoint.X -eq 12) 'Input that came with only pointer jitter must not interrupt, and must become the new baseline.'
$script:jitterOnly = $false
Assert-True ($null -eq (Get-InputBlockInterruption)) 'After jitter was accepted, an unchanged stamp must not interrupt.'
$script:inputStamp = [uint32]502
Assert-True ((Get-InputBlockInterruption) -match '^UserInput:') 'Typing after jitter must still stop the send.'
# jitter during the block must not stop the own-input stamp from being recorded at the end
Reset-Block; $null = Start-InputBlock; $script:inputStamp = [uint32]501; $script:jitterOnly = $true; $script:blockEvents.Clear()
Stop-InputBlock
Assert-True (($script:blockEvents -join ',') -ceq 'cursor-off,restore:500:4660,own-stamp,unlock') 'Jitter must not be treated as the person''s input when the block ends.'
# ending the block
Reset-Block; $null = Start-InputBlock; $script:blockEvents.Clear()
Stop-InputBlock
Assert-True (($script:blockEvents -join ',') -ceq 'cursor-off,restore:500:4660,own-stamp,unlock' -and $script:FocusResult -eq 'Restored' -and -not $script:InputBlockStarted) 'Stopping must restore the cursor, hand the window back, record the own stamp and release the lock.'
$script:blockEvents.Clear()
Stop-InputBlock
Assert-True (($script:blockEvents -join ',') -ceq 'unlock') 'Stopping a stopped block must only release a lock that is still held.'
Reset-Block; $null = Start-InputBlock; $script:inputStamp = [uint32]777; $script:blockEvents.Clear()
Stop-InputBlock
Assert-True (($script:blockEvents -join ',') -ceq 'cursor-off,restore:500:4660,unlock') 'Input by the person during the block must not be recorded as the agent''s own.'
Reset-Block; $NoRestoreFocus = $true; $null = Start-InputBlock; $script:blockEvents.Clear()
Stop-InputBlock; $NoRestoreFocus = $false
Assert-True (($script:blockEvents -join ',') -ceq 'cursor-off,own-stamp,unlock' -and $null -eq $script:FocusResult) '-NoRestoreFocus must skip the hand-back only.'
Reset-Block; $script:restoreReason = 'NotVerified'; $null = Start-InputBlock; Stop-InputBlock
Assert-True ($script:FocusResult -eq 'NotVerified') 'An unverified hand-back must be reported, not claimed.'
Reset-Block
$result = Write-Result -Sent $true -Attempts 1 -InputText $null -ErrorText $null
Assert-True ($null -eq $result.PSObject.Properties['Handback']) 'Without a hand-back the result must have no Handback property.'
$script:FocusResult = 'Restored'
$result = Write-Result -Sent $true -Attempts 1 -InputText $null -ErrorText $null
Assert-True ($result.Handback -eq 'Restored') 'A hand-back must be visible in the result.'
$script:FocusResult = $null
# keep the block off for the remaining checks, and drop the mocks that would shadow later ones
Remove-Item function:Enter-AgentUiLock, function:Wait-AgentUserQuiet, function:Save-AgentUserFocus, function:Enable-AgentCursor, function:Restore-AgentCursor, function:Get-AgentInputStamp, function:Get-AgentInputInUse, function:Get-AgentForegroundHandle, function:Restore-AgentUserFocus, function:Set-AgentOwnInputStamp, function:Get-AgentPointerPosition, function:Test-AgentMeaningfulInputSince
function Exit-AgentUiLock { param($Lock) }
$script:InputBlockStarted = $false

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
$inputElements = @($script:inputFixtures)   # the sender looks the input up once and shares it with this check
$result = & ([scriptblock]::Create($finalGuard.Extent.Text))
Assert-True (-not $result.Sent -and $result.Attempts -eq 0 -and $result.Error -match 'InputNotEmpty') 'Final guard did not preserve a newly exposed draft.'
# The on-screen refusal must come before any clear, paste or click, and must send nothing.
$screenGuard = $statements | Where-Object { $_ -is [Management.Automation.Language.IfStatementAst] -and $_.Extent.Text -match '\$screenError' } | Select-Object -First 1
Assert-True ($null -ne $screenGuard -and $screenGuard.Extent.EndOffset -lt $statements[$start].Extent.StartOffset) 'The on-screen refusal must precede the clear/paste/send loop.'
Assert-True ($screenGuard.Extent.StartOffset -lt $finalGuard.Extent.StartOffset) 'The on-screen refusal must precede the second draft check.'
$screenError = 'InputOffScreen: test'
$script:events = New-Object 'Collections.Generic.List[string]'
$result = & ([scriptblock]::Create($screenGuard.Extent.Text))
Assert-True (-not $result.Sent -and $result.Attempts -eq 0 -and $result.Error -match '^InputOffScreen' -and $script:events.Count -eq 0) 'The on-screen refusal must send nothing and make no attempt.'
# Order of the user-activity steps: wait for a quiet keyboard before the final checks, take the foreground only
# to navigate or inside the input loop, and guard every input action with an interruption check.
$gateStatement = $statements | Where-Object { $_.Extent.Text -match '^\$blockError = Start-InputBlock' } | Select-Object -First 1
Assert-True ($null -ne $gateStatement -and $gateStatement.Extent.EndOffset -lt $screenGuard.Extent.StartOffset) 'The quiet wait must come before the final checks and the foreground.'
$navigateAssignment = $statements | Where-Object { $_.Extent.Text -match '^\$navigate = ' } | Select-Object -First 1
$foregroundStatements = @($statements | Where-Object { $_.Extent.Text -match 'Request-Foreground' })
Assert-True ($foregroundStatements.Count -eq 1 -and $foregroundStatements[0].Extent.Text -match '^if \(\$navigate\)') 'The early foreground request must happen only when navigation needs it.'
Assert-True ($null -ne $navigateAssignment -and $navigateAssignment.Extent.EndOffset -lt $foregroundStatements[0].Extent.StartOffset -and $foregroundStatements[0].Extent.StartOffset -lt $gateStatement.Extent.StartOffset) 'The navigation decision must precede the foreground request, and both the quiet wait.'
Assert-True ($navigateAssignment.Extent.Text -match 'Test-ChatInput' -and $navigateAssignment.Extent.Text -match '\$NewSession') 'Navigation must be decided from a read-only look at the chat, or a requested new session.'
$loopText = (@($statements | Select-Object -Skip $start | ForEach-Object { $_.Extent.Text }) -join "`n")
$guardPositions = @([regex]::Matches($loopText, 'Get-InputBlockInterruption') | ForEach-Object { $_.Index })
$foregroundPosition = $loopText.IndexOf('Set-AgentForegroundWindow')
$clearPosition = $loopText.IndexOf('Clear-ChatInput')
$pastePosition = $loopText.IndexOf("'type', '--hwnd'")
$clickPosition = $loopText.IndexOf("'click', '--hwnd'")
Assert-True ($guardPositions.Count -eq 4 -and $guardPositions[0] -lt $foregroundPosition -and $foregroundPosition -lt $guardPositions[1] -and $guardPositions[1] -lt $clearPosition -and $clearPosition -lt $guardPositions[2] -and $guardPositions[2] -lt $pastePosition -and $pastePosition -lt $guardPositions[3] -and $guardPositions[3] -lt $clickPosition) 'Every foreground, clear, paste and send step must be preceded by its own interruption check.'
$stopPosition = $loopText.IndexOf('Stop-InputBlock')
Assert-True ($stopPosition -gt $clickPosition -and $stopPosition -lt $loopText.IndexOf('Write-Result -Sent $true')) 'The keyboard must be handed back right after the send click, before the result is returned.'
Assert-True ($tryStatement.Finally.Extent.Text -match 'Stop-InputBlock') 'Every exit path must end the input block.'
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
# An interruption stops the send before the step it guards: nothing after that point runs.
$realInterruption = ${function:Get-InputBlockInterruption}
$script:interruptAt = 0; $script:interruptCalls = 0
function Get-InputBlockInterruption { param([switch]$RequireForeground) $script:interruptCalls++; if ($script:interruptCalls -eq $script:interruptAt) { return 'UserInput: test interruption' }; return $null }
$NoSend = $false; $Quiet = $false; $script:textRead = $Text
foreach ($case in @(@(1, ''), @(2, ''), @(3, ''), @(4, 'type'))) {
    $script:events = New-Object 'Collections.Generic.List[string]'
    $script:interruptAt = $case[0]; $script:interruptCalls = 0
    $result = & $sendLoop 6>$null
    Assert-True (-not $result.Sent -and $result.Error -match '^UserInput:' -and ($script:events -join ',') -ceq $case[1]) "An interruption at check $($case[0]) must stop before the next input action (events: $($script:events -join ','))."
    Assert-True (@($script:events | Where-Object { $_ -eq 'click' }).Count -eq 0) 'An interrupted send must never click Send.'
}
$script:events = New-Object 'Collections.Generic.List[string]'; $script:interruptAt = 0; $script:interruptCalls = 0
$result = & $sendLoop 6>$null
Assert-True ($result.Sent -and $script:interruptCalls -eq 4) 'An uninterrupted send must pass all four checks and send.'
Assert-True (@($script:events | Where-Object { $_ -eq 'clear' }).Count -eq 0) 'The first attempt must not clear an input that was just verified empty.'
Set-Item function:Get-InputBlockInterruption $realInterruption
# -OverwriteInput skipped the draft check, so it still clears first
$OverwriteInput = $true
$script:events = New-Object 'Collections.Generic.List[string]'
$result = & $sendLoop 6>$null
Assert-True ($result.Sent -and ($script:events -join ',') -match '^clear,type') '-OverwriteInput must clear before it pastes.'
$OverwriteInput = $false
# a retry clears first: a first read-back that does not match leaves stray text to remove
$script:retryReads = 0
$realReadText = ${function:Get-ChatInputText}
function Get-ChatInputText { $script:retryReads++; if ($script:retryReads -eq 1) { return 'stray text' } else { return $Text } }
$script:events = New-Object 'Collections.Generic.List[string]'
$result = & $sendLoop 6>$null
Assert-True ($result.Sent -and $result.Attempts -eq 2 -and ($script:events -join ',') -match '^type,clear,type') 'A retry after a bad read-back must clear before pasting again.'
Set-Item function:Get-ChatInputText $realReadText
# the in-process input check: one enabled input counts, nothing else does
$inputShowingFunction = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Test-ChatInputShowing' }, $true)
Assert-True ($null -ne $inputShowingFunction) 'The in-process input check is missing.'
. ([scriptblock]::Create($inputShowingFunction.Extent.Text))
$enabledInput = [pscustomobject]@{ Current = [pscustomobject]@{ IsEnabled = $true } }
$disabledInput = [pscustomobject]@{ Current = [pscustomobject]@{ IsEnabled = $false } }
$script:SeenBannerIds = $null
function Get-ChatInputAndBanners { return [pscustomobject]@{ Inputs = @($enabledInput); BannerIds = @() } }
Assert-True (Test-ChatInputShowing) 'One enabled input must count as showing.'
Assert-True ($null -ne $script:SeenBannerIds -and @($script:SeenBannerIds).Count -eq 0) 'The combined search must leave its (empty) banner list for the banner check.'
function Get-ChatInputAndBanners { return [pscustomobject]@{ Inputs = @($enabledInput); BannerIds = @('HarnessWorkspaceMismatchBanner') } }
Assert-True (Test-ChatInputShowing -and (@($script:SeenBannerIds) -join ',') -eq 'HarnessWorkspaceMismatchBanner') 'A banner found by the combined search must be handed on, not lost.'
function Get-ChatInputAndBanners { return [pscustomobject]@{ Inputs = @($disabledInput); BannerIds = @() } }
Assert-True (-not (Test-ChatInputShowing)) 'A disabled input must not count as showing.'
function Get-ChatInputAndBanners { return [pscustomobject]@{ Inputs = @(); BannerIds = @() } }
Assert-True (-not (Test-ChatInputShowing)) 'No input must not count as showing.'
function Get-ChatInputAndBanners { return [pscustomobject]@{ Inputs = @($enabledInput, $enabledInput); BannerIds = @() } }
Assert-True (-not (Test-ChatInputShowing)) 'An ambiguous input must not count as showing.'
$script:SeenBannerIds = $null
function Get-ChatInputAndBanners { throw 'search failed' }
Assert-True (-not (Test-ChatInputShowing) -and $null -eq $script:SeenBannerIds) 'A failed search must fall back to the slower wait, not count as showing, and leave no banner result behind.'
$script:HeldInput = $null
$script:inputFixtures = @($inputElement)
# the early draft check applies only to a new session or a steer; a plain send relies on the check after the quiet wait
$script:textRead = 'draft before a plain send'
$NewSession = $false; $Steer = $false; $OverwriteInput = $false
Assert-True ($null -eq (& ([scriptblock]::Create($preflight.Extent.Text)))) 'A plain send must skip the early draft check (the later one refuses).'
$NewSession = $true
Assert-True ((& ([scriptblock]::Create($preflight.Extent.Text))).Error -match 'InputNotEmpty') 'A new session must still refuse a draft early.'
$NewSession = $false; $Steer = $true
Assert-True ((& ([scriptblock]::Create($preflight.Extent.Text))).Error -match 'InputNotEmpty') 'A steer must still refuse a draft early.'
$Steer = $false
Assert-True ($tryStatement.Body.Statements[0].Extent.Text -match 'inputSeen' -and ($statements | Where-Object { $_.Extent.Text -match '^\$navigate = ' } | Select-Object -First 1).Extent.Text -match '-not \$inputSeen') 'The navigation decision must use the in-process input check before the slower wait.'
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

$tabNavigation = $statements | Where-Object { $_.Extent.Text -match '^if \(\$navigate -and -not \$NoNavigate.*Select-ChatTabIfHidden' } | Select-Object -First 1
$navigate = $true
$inputSeen = $false
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
