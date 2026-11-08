<#
.SYNOPSIS
    Reads Copilot's reply to a given prompt from a VS Copilot Chat window: scrolls the chat list to
    its end first, then returns only what follows that prompt.

.DESCRIPTION
    The chat list is virtualized, so a reply below the visible area is not returned until the list is
    scrolled; an unscrolled read can look like "no reply yet" while the reply is already there. This
    script moves the list to the bottom (`scroll-container` on the AutomationId `session` list),
    checks that the scroll really reached the end (boundaryReached or verticalScrollPercentAfter 100,
    retrying a few times), reads all rendered messages with Get-CopilotChatTranscript.ps1, finds the
    prompt, and returns the messages after it.

    The prompt is found by -AfterPrompt: a distinctive phrase from the prompt that was sent (the LAST
    message containing it counts). Without it, the last "Restore Checkpoint" marker is used: the
    message after the marker is the user's prompt and everything after that is the reply.

    Skipped when building the reply text: the "GitHub Copilot" header, "Restore Checkpoint" markers,
    and tool-activity summaries such as "9 tasks done", "Read 3 items" and "Run command (2 completed)".
    The completion footer ("The response used ... / The response cost N credits.") is returned
    separately in Footer.

    When the reply is longer than the visible chat area, the prompt message is not rendered at the bottom of the
    list, so it cannot be found there. The script then scrolls up in steps (85, 70, 55, 40, 25, 10, 0 percent) until the
    prompt is rendered, takes the messages after it, appends the messages rendered at the bottom that it has not seen
    yet, and scrolls back to the bottom. Messages that were rendered at neither position are missing, so PartialReply
    is true in that case: read the complete text in the chat if it matters. (Found 2026-10-31: before this, a long
    reply gave PromptFound false and an empty Reply.)

    Read-only except for the chat list's scroll position. It never types or clicks.

.PARAMETER Hwnd
    Target window handle, e.g. "0x121B1A".

.PARAMETER TitleContains
    Resolve the target window by title substring instead of passing -Hwnd (via
    Resolve-CopilotWindow.ps1). No match throws a plain message, several matches throw the
    candidate list. Ignored when -Hwnd is also given.

.PARAMETER AfterPrompt
    A distinctive phrase from the prompt whose reply you want (case-insensitive, matched as plain text).

.PARAMETER MaxReplyChars
    Cap for the returned Reply text. Default 6000; Truncated says when it was cut.

.PARAMETER NoScroll
    Do not scroll the list first (not recommended).

.PARAMETER ExePath
    Path to agentdebug-ui.exe.

.OUTPUTS
    PSCustomObject: PromptFound, ScrolledToEnd, ScrollPercent, Reply, Footer, ReplyMessageCount,
    Truncated, Busy (the stop button is showing: Copilot is still working), IsClean (the complete reply
    has a line that starts with NO ISSUES REMAIN (only spaces or ** before it; a quoted "> " line does not count) and lists no numbered findings; never true for a truncated reply).

.EXAMPLE
    .\Read-CopilotReply.ps1 -Hwnd 0x121B1A -AfterPrompt 'Verify cheaply paragraph'
#>
[CmdletBinding()]
param(
    [string]$Hwnd,

    [string]$AfterPrompt = '',

    [ValidateRange(200, 100000)]
    [int]$MaxReplyChars = 6000,

    [switch]$NoScroll,

    [string]$ExePath = 'C:\MyFiles\Git\AgentDebugToolkit\src\AgentDebugToolkit.UiAutomation.Cli\bin\Debug\net8.0-windows\agentdebug-ui.exe',

    [string]$FooterPattern = '^The response (used the .+ model|cost [\d.]+ credits?\.?$)',

    # Tool-activity summaries and chrome that are not part of the answer text.
    [string]$ChromePattern = '^(GitHub Copilot|Restore Checkpoint|\d+ tasks? done|Read \d+ items?|Run command.*|Used \d+ tools?.*|Searched .*|Thinking.*)$',

    [string]$TitleContains
)

$ErrorActionPreference = 'Stop'
# The inherited DOTNET_ROOT from VS breaks agentdebug-ui.exe; always clear it.
Remove-Item Env:DOTNET_ROOT -ErrorAction SilentlyContinue

if (-not (Test-Path $ExePath)) { throw "agentdebug-ui.exe not found at '$ExePath'. Pass -ExePath explicitly." }
$transcript = Join-Path $PSScriptRoot 'Get-CopilotChatTranscript.ps1'
if (-not (Test-Path $transcript)) { throw "Get-CopilotChatTranscript.ps1 not found next to this script." }
if (-not $Hwnd -and -not $TitleContains) { throw 'Pass -Hwnd or -TitleContains.' }
if (-not $Hwnd) {
    $resolved = & (Join-Path $PSScriptRoot 'Resolve-CopilotWindow.ps1') -TitleContains $TitleContains -ExePath $ExePath
    if ($resolved.Error) { throw $resolved.Error }
    $Hwnd = $resolved.Hwnd
}

# The CLI prints its fields at the top level; the MCP tools wrap them in "result". Accept both.
function Invoke-Cli([string[]]$CliArgs) {
    $out = & $ExePath @CliArgs 2>&1 | Out-String
    try { $parsed = $out | ConvertFrom-Json } catch { return $null }
    if ($parsed -and $parsed.PSObject.Properties.Name -contains 'result' -and $parsed.result) { return $parsed.result }
    $parsed
}

# ---- 1. scroll to the end and check that it worked
$scrolled = $false
$percent = $null
if (-not $NoScroll) {
    for ($try = 1; $try -le 3 -and -not $scrolled; $try++) {
        $r = Invoke-Cli @('scroll-container', '--hwnd', $Hwnd, '--strategy', 'AutomationId', '--value', 'session', '--verticalPercent', '100')
        if ($r -and $r.success) {
            $percent = $r.verticalScrollPercentAfter
            if ($r.boundaryReached -or $percent -ge 99.9) { $scrolled = $true }
        }
        if (-not $scrolled -and $try -lt 3) { Start-Sleep -Milliseconds 400 }
    }
}
else { $scrolled = $null }
# The scroll position is counted in items and often stops a little short of 100 (for example 98.5) although the end is
# showing. NearEnd (95 percent or more) lets a caller that has already seen the completion footer accept that case.
$nearEnd = [bool]($scrolled -or ($null -ne $percent -and $percent -ge 95))

# ---- 2. read every rendered message
$items = @(& $transcript -Hwnd $Hwnd -Last 0 -IncludeFooter -ExePath $ExePath)
$texts = @($items | ForEach-Object { $_.Text })

# ---- 3. locate the prompt
$start = -1
if ($AfterPrompt) {
    for ($i = $texts.Count - 1; $i -ge 0; $i--) {
        if ($texts[$i].IndexOf($AfterPrompt, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $start = $i + 1; break }
    }
}
else {
    for ($i = $texts.Count - 1; $i -ge 0; $i--) {
        if ($texts[$i] -eq 'Restore Checkpoint') { $start = $i + 2; break }   # marker, then the user's prompt
    }
}

# ---- 3b. long reply: the prompt scrolled out of the rendered part of the list. Look further up for it.
$scrolledUp = $false
if ($start -lt 0 -and $AfterPrompt -and -not $NoScroll) {
    $bottomTexts = $texts
    foreach ($pct in 85, 70, 55, 40, 25, 10, 0) {
        $null = Invoke-Cli @('scroll-container', '--hwnd', $Hwnd, '--strategy', 'AutomationId', '--value', 'session', '--verticalPercent', [string]$pct)
        Start-Sleep -Milliseconds 300
        $upTexts = @(@(& $transcript -Hwnd $Hwnd -Last 0 -IncludeFooter -ExePath $ExePath) | ForEach-Object { $_.Text })
        $found = -1
        for ($i = $upTexts.Count - 1; $i -ge 0; $i--) {
            if ($upTexts[$i].IndexOf($AfterPrompt, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $found = $i; break }
        }
        if ($found -ge 0) {
            $merged = New-Object System.Collections.Generic.List[string]
            foreach ($m in @($upTexts | Select-Object -Skip ($found + 1))) { $merged.Add($m) }
            foreach ($m in $bottomTexts) { if (-not $merged.Contains($m)) { $merged.Add($m) } }
            $texts = $merged.ToArray()
            $start = 0
            $scrolledUp = $true
            break
        }
    }
    # leave the list where we found it: at the bottom
    $null = Invoke-Cli @('scroll-container', '--hwnd', $Hwnd, '--strategy', 'AutomationId', '--value', 'session', '--verticalPercent', '100')
}

$footer = $null
$replyParts = New-Object System.Collections.Generic.List[string]
if ($start -ge 0) {
    for ($i = $start; $i -lt $texts.Count; $i++) {
        $t = $texts[$i]
        if ($t -match $FooterPattern) { $footer = $t; continue }
        if ($t -match $ChromePattern) { continue }
        $replyParts.Add($t)
    }
}
$reply = ($replyParts -join "`n`n").Trim()
$fullReply = $reply
$truncated = $false
if ($reply.Length -gt $MaxReplyChars) { $reply = $reply.Substring(0, $MaxReplyChars); $truncated = $true }

# ---- 4. is Copilot still working? (the stop button in the input area)
$busy = $false
$f = Invoke-Cli @('find-first', '--hwnd', $Hwnd, '--strategy', 'AutomationId', '--value', 'CancelButton')
if ($f -and $f.found) { $busy = $true }

# Clean only when the COMPLETE reply (not the capped copy) has a line that STARTS with the verdict (a preamble sentence may precede it) and lists no numbered findings;
# a quoted phrase later in the text, or findings beyond the cap, never count.
$clean = (-not $truncated) -and ($fullReply -match '(?im)^[ \t]*(\*\*)?NO ISSUES REMAIN\b') -and ($fullReply -notmatch '(?m)^\s*\d+\.\s')

[pscustomobject]@{
    PromptFound       = ($start -ge 0)
    ScrolledToEnd     = $scrolled
    NearEnd           = $nearEnd
    ScrollPercent     = $percent
    Reply             = $reply
    Footer            = $footer
    ReplyMessageCount = $replyParts.Count
    Truncated         = $truncated
    Busy              = $busy
    IsClean           = $clean
    ScrolledUpToFindPrompt = $scrolledUp
    PartialReply      = $scrolledUp
}
