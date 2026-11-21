<#
.SYNOPSIS
Offline reply-classification regression checks for Get-CopilotChatTranscript.ps1 and Read-CopilotReply.ps1; no chat interaction.
.PARAMETER ScriptsFolder
Folder holding the two scripts under test.
.PARAMETER TemporaryRoot
Existing directory for a disposable fake UI executable and UIA tree fixtures. Only that fixture folder is created/deleted.
.DESCRIPTION
Runs both scripts against a fake agentdebug-ui replacement that serves synthetic UIA trees, so no
window, chat, focus or repository file is touched.
#>
[CmdletBinding()]
param(
    [string]$ScriptsFolder = (Join-Path $PSScriptRoot '..\..\agent-orchestrator\scripts'),
    [string]$TemporaryRoot = [IO.Path]::GetTempPath()
)
$ErrorActionPreference = 'Stop'
$script:assertions = 0
function Assert-True([bool]$Condition, [string]$Message) {
    $script:assertions++
    if (-not $Condition) { throw $Message }
}
if (-not (Test-Path -LiteralPath $TemporaryRoot -PathType Container)) { throw 'TemporaryRoot must be an existing directory.' }
$transcriptScript = Join-Path $ScriptsFolder 'Get-CopilotChatTranscript.ps1'
$readerScript = Join-Path $ScriptsFolder 'Read-CopilotReply.ps1'

function New-Node([string]$ClassName, [string]$Name, [string]$AutomationId = '', $Children = @()) {
    [pscustomobject]@{ ClassName = $ClassName; Name = $Name; AutomationId = $AutomationId; Children = @($Children) }
}
function New-Plain([string]$Name) { New-Node 'ChatMessageItem' $Name '' @((New-Node 'TextBlock' $Name), (New-Node 'Button' 'x')) }
function New-Header([string]$Name) { New-Node 'ChatMessageItem' $Name '' @((New-Node 'TextBlock' $Name)) }
function New-Chip([string]$Name) { New-Node 'ChatMessageItem' $Name '' @((New-Node 'Image' 'icon'), (New-Node 'TextBlock' $Name)) }
function New-Body([string]$Text) {
    New-Node 'ChatMessageItem' $Text '' @((New-Node 'FlowDocumentScrollViewer' '' 'PART_FlowScrollViewer' @((New-Node 'Paragraph' $Text))))
}
function New-Tool([string]$Name, [bool]$WithExpander = $true, [bool]$NestedBody = $false) {
    $inner = @((New-Node 'Border' '' 'HeaderSite' @((New-Node 'TextBlock' $Name))))
    if ($NestedBody) { $inner += New-Node 'FlowDocumentScrollViewer' '' 'PART_FlowScrollViewer' @((New-Node 'Paragraph' 'tool output')) }
    $child = if ($WithExpander) { New-Node 'Expander' $Name 'toolCallExpander' $inner } else { $inner[0] }
    New-Node 'ChatMessageItem' $Name '' @($child)
}
function New-Footer([string]$Text, [bool]$WithLike) {
    $children = if ($WithLike) { @((New-Node 'Button' 'Like' 'PART_LikeButton')) } else { @() }
    New-Node 'ChatMessageItem' $Text '' $children
}
function New-Tree($Messages) {
    [pscustomobject]@{ root = (New-Node 'Window' 'VS' '' @((New-Node 'ListBox' 'chat' 'session' $Messages))) }
}

$fixtureDirectory = Join-Path $TemporaryRoot ('reply-fixture-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $fixtureDirectory
try {
    $fakeUi = Join-Path $fixtureDirectory 'Fake-Ui.ps1'
    Set-Content -LiteralPath $fakeUi -Encoding ASCII -Value @'
$verb = $args[0]
$state = Join-Path $PSScriptRoot 'scroll.txt'
if ($verb -eq 'inspect') {
    $percent = if (Test-Path -LiteralPath $state) { (Get-Content -Raw -LiteralPath $state).Trim() } else { '100' }
    $file = if ($percent -eq '100') { 'tree-bottom.json' } else { 'tree-top.json' }
    Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $PSScriptRoot $file)
}
elseif ($verb -eq 'scroll-container') {
    $index = [array]::IndexOf($args, '--verticalPercent')
    Set-Content -LiteralPath $state -Value $args[$index + 1]
    '{"success":true,"boundaryReached":true,"verticalScrollPercentAfter":100}'
}
elseif ($verb -eq 'find-first') { '{"found":false}' }
'@
    function Set-Fixture([string]$Name, $Messages) {
        $json = New-Tree $Messages | ConvertTo-Json -Depth 30
        [IO.File]::WriteAllText((Join-Path $fixtureDirectory $Name), $json, (New-Object System.Text.UTF8Encoding($false)))
        $state = Join-Path $fixtureDirectory 'scroll.txt'
        if (Test-Path -LiteralPath $state) { Remove-Item -LiteralPath $state }
    }
    function Read-Fixture([hashtable]$Extra = @{}) {
        & $readerScript -Hwnd '0x1' -AfterPrompt 'distinctive-phrase' -ExePath $fakeUi -MaxReplyChars 20000 @Extra
    }
    $prompt = New-Plain 'please review distinctive-phrase msg-abcdefgh'
    $chipPath = 'agent-orchestrator\scripts\tests\Reading-and-review-scripts.tests.md'
    Assert-True ($chipPath.Length -ge 60 -and $chipPath.Length -le 70) 'Fixture path chip should resemble the observed 62-character chip.'

    # Structured turn: several bodies and tool items before the footer.
    $structured = @(
        (New-Header 'Restore Checkpoint'), $prompt, (New-Header 'GitHub Copilot'),
        (New-Tool 'Worked on 7 tasks' $false), (New-Chip 'README.md'), (New-Chip $chipPath),
        (New-Body 'First paragraph of the answer.'), (New-Tool 'Run command (3 completed)'),
        (New-Body 'Done'), (New-Body 'Thinking about the edge case'),
        (New-Tool 'Run command: dotnet test' $true $true), (New-Footer 'The response cost 1.0 credits.' $false)
    )
    Set-Fixture 'tree-bottom.json' $structured
    $items = @(& $transcriptScript -Hwnd '0x1' -Last 0 -IncludeFooter -ExePath $fakeUi)
    $kinds = @($items | ForEach-Object { $_.Kind }) -join ','
    Assert-True ($kinds -ceq 'Header,Other,Header,Tool,Other,Other,Body,Tool,Body,Body,Tool,Other') "Unexpected kinds: $kinds"
    Assert-True ($items[4].ChildCount -eq 2 -and -not $items[4].HasMarker -and $items[8].ChildCount -eq 1 -and $items[8].HasMarker) 'Child counts or markers changed.'
    Assert-True (@($items | Where-Object IsFooter).Count -eq 0) 'IsFooter must stay limited to the model-form footer text.'
    $default = @(& $transcriptScript -Hwnd '0x1' -Last 0 -ExePath $fakeUi)
    Assert-True ($default.Count -eq $items.Count) 'Default transcript item set changed.'
    $result = Read-Fixture
    Assert-True ($result.PromptFound -and $result.ReplyMessageCount -eq 3) "Unexpected body count: $($result.ReplyMessageCount)"
    Assert-True ($result.Reply -ceq "First paragraph of the answer.`n`nDone`n`nThinking about the edge case") 'Structured reply contained chrome, chips or lost short/chrome-like bodies.'
    Assert-True ($result.Footer -ceq 'The response cost 1.0 credits.') 'Cost-only footer was not returned separately.'
    Assert-True ($result.Reply -notmatch 'Worked on|README|tests\.md|Run command|tool output') 'Tool or chip text leaked into Reply.'

    # Short reply: one marked body with one child must survive the chip rule.
    Set-Fixture 'tree-bottom.json' @($prompt, (New-Tool 'Worked on 2 tasks' $false), (New-Body 'Done'), (New-Footer 'The response cost 2.0 credits.' $false))
    $result = Read-Fixture
    Assert-True ($result.Reply -ceq 'Done' -and $result.ReplyMessageCount -eq 1) 'A legitimate one-word body was dropped.'

    # Footer by the like button, whatever its text; clean verdict still works.
    Set-Fixture 'tree-bottom.json' @($prompt, (New-Body 'NO ISSUES REMAIN'), (New-Footer 'The response used the GPT-6 Luna model. The response cost 2.0 credits.' $true))
    $result = Read-Fixture
    Assert-True ($result.IsClean -and $result.Footer -match 'GPT-6 Luna model') 'Like-button footer or clean verdict failed.'
    Set-Fixture 'tree-bottom.json' @($prompt, (New-Body 'Reply text'), (New-Footer 'Completed' $true))
    Assert-True ((Read-Fixture).Footer -ceq 'Completed') 'A footer identified only by the like button was not returned as Footer.'

    # Unmarked long, multi-line and chip-rule-off items are retained; the regex fallback still applies.
    $longText = ('long unmarked sentence ' * 20).Trim()
    Assert-True ($longText.Length -gt 260) 'Fixture long text is too short.'
    Set-Fixture 'tree-bottom.json' @($prompt, (New-Body 'Marked body'), (New-Plain $longText), (New-Plain "two`nlines"), (New-Plain '3 tasks done'), (New-Chip 'notes.txt'))
    $result = Read-Fixture
    Assert-True ($result.Reply -ceq "Marked body`n`n$longText`n`ntwo`nlines") 'Structured fallback kept chrome, dropped long/multi-line text or kept a chip.'
    Assert-True ((Read-Fixture @{ ChipMaxLength = 0 }).Reply -match 'notes\.txt') 'ChipMaxLength 0 did not disable the chip rule.'

    # No structural marker anywhere: the previous pattern-only behavior is unchanged.
    Set-Fixture 'tree-bottom.json' @($prompt, (New-Header 'GitHub Copilot'), (New-Plain '9 tasks done'), (New-Plain 'Plain answer text'), (New-Chip 'README.md'), (New-Footer 'The response used the GPT-6 Luna model.' $false))
    $result = Read-Fixture
    Assert-True ($result.Reply -ceq "Plain answer text`n`nREADME.md" -and $result.Footer -match 'Luna') 'Legacy unmarked behavior changed.'

    # Long reply: the prompt is only rendered at the top; both halves merge without duplicates.
    Set-Fixture 'tree-top.json' @($prompt, (New-Body 'Top body'), (New-Tool 'Worked on 3 tasks' $false), (New-Body 'Shared body'))
    Set-Fixture 'tree-bottom.json' @((New-Body 'Shared body'), (New-Chip 'src.cs'), (New-Body 'Bottom body'), (New-Footer 'The response cost 1.0 credits.' $false))
    $state = Join-Path $fixtureDirectory 'scroll.txt'
    if (Test-Path -LiteralPath $state) { Remove-Item -LiteralPath $state }
    $result = Read-Fixture
    Assert-True ($result.PartialReply -and $result.PromptFound) 'Scroll-up merge did not find the prompt.'
    Assert-True ($result.Reply -ceq "Top body`n`nShared body`n`nBottom body") "Scroll-up merge changed: $($result.Reply)"
    Assert-True ($result.Footer -ceq 'The response cost 1.0 credits.') 'Scroll-up merge lost the footer.'
}
finally {
    if (Test-Path -LiteralPath $fixtureDirectory) { Remove-Item -LiteralPath $fixtureDirectory -Recurse -Force }
}
Write-Output "PASS: $script:assertions assertions; structural Kind metadata, body-first reply classification, chip/tool exclusion, regex fallback and scroll-up merge against a fake UI; no chat or UI actions."
