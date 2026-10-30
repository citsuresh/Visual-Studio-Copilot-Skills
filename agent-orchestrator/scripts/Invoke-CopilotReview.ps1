<#
.SYNOPSIS
    Sends one prompt to the Copilot chat of a Visual Studio window and returns only Copilot's reply:
    checks the chat is visible and the input empty, sends, waits, scrolls the chat list to its end,
    and reads what follows the prompt. Built for review loops ("NO ISSUES REMAIN").

.DESCRIPTION
    One call replaces the usual send / watch / scroll / read sequence:
      1. Resolves the window (-Hwnd, or -TitleContains restricted to one process name, devenv by
         default, so Explorer or browser windows with the same folder name are never matched).
      2. Refuses to send, returning a status instead, when the chat is not showing (another tab such
         as Git Changes is active), or when the input already holds text (Send-CopilotPrompt.ps1
         clears the input first, which would destroy a draft someone is typing). -OverwriteInput
         overrides the second check.
      3. Appends a short unique reference tag to the prompt, sends it with Send-CopilotPrompt.ps1, and
         waits with Watch-CopilotChatV2.ps1 (default, -Poller V2: one cheap probe of the input area per poll,
         works with the window overlapped or minimized) or Watch-CopilotChatV1.ps1 (-Poller V1).
      4. A tool permission prompt or question card is never answered here: the call returns
         Status NeedsUser with the question and options so the person can answer it.
      5. When the chat goes idle, Read-CopilotReply.ps1 scrolls to the end and returns the reply after
         the tag. The reply counts as complete only with a completion footer and the stop button gone.

    Review mode (-Review) wraps the prompt in the standard review-only rules and asks for a ranked
    numbered list or the exact sentence NO ISSUES REMAIN; IsClean is true for that sentence.

    The blue "orchestration session" cursor (AgentCursor.ps1 -Session Start/Stop) is the caller's job;
    Send-CopilotPrompt.ps1 shows the red input dot itself.

.PARAMETER Hwnd
    Window handle. Use -TitleContains instead when the handle may be stale.

.PARAMETER TitleContains
    Substring of the window title (for example "Visual-Studio-Copilot-Skills"). Must match exactly one window.

.PARAMETER ProcessName
    Process the window must belong to when -TitleContains is used. Default devenv.

.PARAMETER Prompt
    The text to send (one paragraph; line breaks are collapsed to spaces).

.PARAMETER Review
    Wrap the prompt in review-only rules and the NO ISSUES REMAIN reply format.

.PARAMETER TimeoutSeconds
    Total time to wait for the reply. Default 900.

.PARAMETER OverwriteInput
    Send even when the input holds text (it will be cleared).

.OUTPUTS
    PSCustomObject: Status (Done, NeedsUser, NotSent, NoReply, Timeout), Reason, Hwnd, Reply, Footer,
    IsClean, PromptKind, Question, Options, ScrolledToEnd, ElapsedSeconds.

.EXAMPLE
    .\Invoke-CopilotReview.ps1 -TitleContains 'Visual-Studio-Copilot-Skills' -Review -Prompt 'Review vs-chat-history\SKILL.md against docs\CLI_CONTRACT.md.'
#>
[CmdletBinding()]
param(
    [string]$Hwnd,
    [string]$TitleContains,
    [string]$ProcessName = 'devenv',

    [Parameter(Mandatory = $true)]
    [string]$Prompt,

    [switch]$Review,

    [ValidateRange(60, 7200)]
    [int]$TimeoutSeconds = 900,

    # A fixed short interval: the watcher runs in this script, so polling costs the caller no tokens, and a
    # finished or waiting agent is noticed within about this many seconds.
    [ValidateRange(3, 120)]
    [int]$PollIntervalSeconds = 6,

    [switch]$OverwriteInput,

    # Plays the Windows "tada" sound when the wait ends (done or needs the person; any result except NotSent), falling back to a beep. -NoBeep silences it.
    [switch]$NoBeep,

    # V2 (default): Watch-CopilotChatV2.ps1, about 7 percent of one core while waiting. V1: the original
    # Watch-CopilotChatV1.ps1 tree-dump poller (about 70 percent of one core at a 5 second interval).
    [ValidateSet('V2', 'V1')]
    [string]$Poller = 'V2',

    [ValidateRange(200, 100000)]
    [int]$MaxReplyChars = 6000,

    [string]$ExePath = 'C:\MyFiles\Git\AgentDebugToolkit\src\AgentDebugToolkit.UiAutomation.Cli\bin\Debug\net8.0-windows\agentdebug-ui.exe'
)

$ErrorActionPreference = 'Stop'
# The inherited DOTNET_ROOT from VS breaks agentdebug-ui.exe; always clear it.
Remove-Item Env:DOTNET_ROOT -ErrorAction SilentlyContinue
if (-not (Test-Path $ExePath)) { throw "agentdebug-ui.exe not found at '$ExePath'. Pass -ExePath explicitly." }
foreach ($n in 'Send-CopilotPrompt.ps1', 'Watch-CopilotChatV1.ps1', 'Watch-CopilotChatV2.ps1', 'Read-CopilotReply.ps1') {
    if (-not (Test-Path (Join-Path $PSScriptRoot $n))) { throw "$n not found next to this script." }
}
$started = Get-Date

# The CLI prints its fields at the top level; the MCP tools wrap them in "result". Accept both.
function Invoke-Cli([string[]]$CliArgs) {
    $out = & $ExePath @CliArgs 2>&1 | Out-String
    try { $parsed = $out | ConvertFrom-Json } catch { return $null }
    if ($parsed -and $parsed.PSObject.Properties.Name -contains 'result' -and $parsed.result) { return $parsed.result }
    $parsed
}

function New-Result([string]$Status, [string]$Reason, $Extra = @{}) {
    $o = [ordered]@{
        Status = $Status; Reason = $Reason; Hwnd = $script:Hwnd; Reply = $null; Footer = $null; IsClean = $false
        PromptKind = $null; Question = $null; Options = $null; ScrolledToEnd = $null
        ElapsedSeconds = [int]((Get-Date) - $script:started).TotalSeconds
    }
    foreach ($k in $Extra.Keys) { $o[$k] = $Extra[$k] }
    if (-not $NoBeep -and $Status -ne 'NotSent') { try { (New-Object System.Media.SoundPlayer (Join-Path $env:SystemRoot 'Media\tada.wav')).PlaySync() } catch { try { [console]::Beep(880, 200) } catch { } } }
    [pscustomobject]$o
}

# ---- 1. resolve the window
if (-not $Hwnd) {
    if (-not $TitleContains) { throw 'Pass -Hwnd or -TitleContains.' }
    $list = Invoke-Cli @('list-windows', '--processName', $ProcessName, '--titleContains', $TitleContains)
    $wins = @($list.windows)
    if ($wins.Count -ne 1) {
        $names = ($wins | ForEach-Object { "$($_.Hwnd) '$($_.Title)'" }) -join '; '
        throw "Expected exactly one $ProcessName window containing '$TitleContains', found $($wins.Count): $names"
    }
    $Hwnd = $wins[0].Hwnd
}

# ---- 2. is the chat showing, and is the input empty?
$listShown = Invoke-Cli @('find-first', '--hwnd', $Hwnd, '--strategy', 'AutomationId', '--value', 'session')
$inputEmpty = Invoke-Cli @('find-first', '--hwnd', $Hwnd, '--strategy', 'Name', '--value', 'Ask Copilot')
$chatVisible = ($listShown -and $listShown.found) -or ($inputEmpty -and $inputEmpty.found)
if (-not $chatVisible) {
    return New-Result 'NotSent' 'ChatNotVisible: the chat pane is not showing in that window (another tab, such as Git Changes, may be active). Nothing was sent.'
}
if (-not ($inputEmpty -and $inputEmpty.found) -and -not $OverwriteInput) {
    return New-Result 'NotSent' 'InputNotEmpty: the chat input holds text (possibly a draft). Nothing was sent; use -OverwriteInput to replace it.'
}

# ---- 3. build the prompt (one paragraph, unique tag) and send it
$text = ($Prompt -replace '\s*\r?\n\s*', ' ').Trim()
if ($Review) {
    $text = 'Review only: do not edit any file, do not commit, do not push, do not run git commands that change anything. ' + $text +
        ' Reply with a short numbered list ranked by severity with file and line and a suggested fix, or say clearly: NO ISSUES REMAIN.'
}
$tag = 'ref ' + [guid]::NewGuid().ToString('N').Substring(0, 8)
$text = "$text ($tag)"

$send = & (Join-Path $PSScriptRoot 'Send-CopilotPrompt.ps1') -Hwnd $Hwnd -Quiet -Text $text -ExePath $ExePath
if (-not $send.Sent) {
    return New-Result 'NotSent' "Send-CopilotPrompt.ps1 did not send: $($send.Error)"
}

# ---- 4. wait, never answering a prompt on the person's behalf
$watchV1 = Join-Path $PSScriptRoot 'Watch-CopilotChatV1.ps1'
$watchV2 = Join-Path $PSScriptRoot 'Watch-CopilotChatV2.ps1'
$read = Join-Path $PSScriptRoot 'Read-CopilotReply.ps1'
$deadline = $started.AddSeconds($TimeoutSeconds)
$first = $true
$misses = 0
$unconfirmed = 0
do {
    $left = ($deadline - (Get-Date)).TotalSeconds
    if ($left -lt 10) { break }       # not enough time for another wait: fall through to the Timeout result
    $remaining = [int][Math]::Min(180, $left)
    if ($Poller -eq 'V2') {
        $w = & $watchV2 -Hwnd $Hwnd -TimeoutSeconds $remaining -PollIntervalSeconds $PollIntervalSeconds -QuietSeconds 20 -RequireBusyFirst:$first -NoBeep
        if ($w.State -eq 'Pending') {
            # The light poller only says that something is waiting; the watcher extracts the question and options once.
            $leftNow = ($deadline - (Get-Date)).TotalSeconds
            if ($leftNow -lt 15) {
                # Too little time left to ask the watcher: report the prompt without its question rather than overrun the deadline.
                $w = [pscustomobject]@{ State = 'Pending'; PromptKind = $w.PromptKind; Question = $null; Options = $null }
                $d = $w
            }
            else {
                $d = & $watchV1 -Hwnd $Hwnd -ExePath $ExePath -TimeoutSeconds ([int][Math]::Min(40, $leftNow - 3)) -PollIntervalSeconds 8 6>$null | Select-Object -Last 1
            }
            if ($d -and $d.State -eq 'Pending') {
                $w = [pscustomobject]@{ State = 'Pending'; PromptKind = $(if ($d.PromptKind) { $d.PromptKind } else { $w.PromptKind }); Question = $d.Question; Options = $d.Options }
            }
            else {
                # The watcher does not see the prompt: it may have been answered meanwhile, or it is a kind the watcher does
                # not extract. Probe once more. If something is still waiting, report it without a question: a prompt must
                # never be missed. Otherwise carry on waiting.
                # With under 12 s left there is no time for another probe (the wait needs at least 10 s): report it unconfirmed.
                if (($deadline - (Get-Date)).TotalSeconds -ge 12) {
                    $again = & $watchV2 -Hwnd $Hwnd -TimeoutSeconds 10 -PollIntervalSeconds 2 -QuietSeconds 5 -NoBeep
                }
                else { $again = [pscustomobject]@{ State = 'Pending'; PromptKind = $w.PromptKind } }
                if ($again.State -eq 'Pending') {
                    $w = [pscustomobject]@{ State = 'Pending'; PromptKind = $again.PromptKind; Question = $null; Options = $null }
                }
                else { $first = $false; continue }
            }
        }
        elseif ($w.State -eq 'NotVisible') {
            return New-Result 'NoReply' 'ChatNotVisible: the chat pane stopped showing while waiting (another tab was selected). Nothing more was sent; select the Chat tab and read the reply with Read-CopilotReply.ps1.'
        }
        elseif ($w.State -eq 'ProbeError') {
            return New-Result 'NoReply' "ProbeError: $($w.Note)"
        }
        elseif ($w.State -eq 'WindowGone') {
            return New-Result 'NoReply' 'WindowGone: the window closed while waiting. The prompt may or may not have been answered.'
        }
    }
    elseif ($first) {
        $w = & $watchV1 -Hwnd $Hwnd -ExePath $ExePath -TimeoutSeconds $remaining -PollIntervalSeconds $PollIntervalSeconds -MaxPollIntervalSeconds $PollIntervalSeconds -PollBackoffMultiplier 1 -IdleWithoutFooterPolls 4 -RequireWorkingFirst 6>$null | Select-Object -Last 1
    }
    else {
        $w = & $watchV1 -Hwnd $Hwnd -ExePath $ExePath -TimeoutSeconds $remaining -PollIntervalSeconds $PollIntervalSeconds -MaxPollIntervalSeconds $PollIntervalSeconds -PollBackoffMultiplier 1 -IdleWithoutFooterPolls 4 6>$null | Select-Object -Last 1
    }
    $first = $false

    if ($w -and $w.State -eq 'Pending') {
        return New-Result 'NeedsUser' 'Copilot is waiting for an answer or permission; answer it yourself, then read the reply with Read-CopilotReply.ps1.' @{
            PromptKind = $w.PromptKind; Question = $w.Question; Options = $w.Options
        }
    }
    if ($w -and $w.State -eq 'Idle') {
        $r = & $read -Hwnd $Hwnd -AfterPrompt $tag -MaxReplyChars $MaxReplyChars -ExePath $ExePath
        if ($r.PromptFound -and $r.Footer -and -not $r.Busy -and $r.ScrolledToEnd) {
            return New-Result 'Done' 'Reply complete (completion footer present, stop button gone, chat list confirmed at its end).' @{
                Reply = $r.Reply; Footer = $r.Footer; IsClean = $r.IsClean; ScrolledToEnd = $r.ScrolledToEnd
            }
        }
        if ($r.PromptFound -and $r.Footer -and -not $r.Busy -and -not $r.ScrolledToEnd) {
            # The reply looks complete but the list was not confirmed at its end, so a later part may be unseen: read again.
            $unconfirmed++
            if ($unconfirmed -ge 3) {
                return New-Result 'NoReply' 'ReadNotConfirmed: the reply looked complete but the chat list could not be confirmed at its end after several reads.' @{
                    Reply = $r.Reply; Footer = $r.Footer; ScrolledToEnd = $r.ScrolledToEnd
                }
            }
            Start-Sleep -Seconds 5
            continue
        }
        if (-not $r.Busy) { $misses++ } else { $misses = 0 }
        if ($misses -ge 3) {
            return New-Result 'NoReply' 'The chat is idle but no complete reply to this prompt was found (no footer, or the prompt is not in the rendered list).' @{
                Reply = $r.Reply; ScrolledToEnd = $r.ScrolledToEnd
            }
        }
        Start-Sleep -Seconds 10
    }
} while ((Get-Date) -lt $deadline)

New-Result 'Timeout' "No complete reply within $TimeoutSeconds seconds."
