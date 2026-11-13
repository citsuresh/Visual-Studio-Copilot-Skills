<#
.SYNOPSIS
    Waits for a Copilot chat in Visual Studio to finish or to need a person, with one small UI Automation
    probe per poll. The default watcher; Watch-CopilotChatV1.ps1 is the older full-tree one.

.DESCRIPTION
    WHAT IT DOES, IN ORDER
      1. Polls the chat cheaply (about 0.5 s per probe, no console output) until the chat is Idle (finished),
         Pending (a question card or permission prompt waits for a person), or something is wrong.
      2. Beeps once when the wait ends (-NoBeep silences it).
      3. Unless -NoDetail is given and the wait ended Pending or Idle, runs Watch-CopilotChatV1.ps1 ONCE to
         collect the details a light probe cannot see (question, options, banners, plain-text question
         detection, last message) and merges them into the result. This costs one full tree dump (about
         5 to 25 seconds) at the end only, never while polling.

    The result is therefore a superset of what V1 returned: same field names (State, PromptKind, Question,
    Options, Recommended, MorePages, Banners, LastMessage, LastMessageTail, AwaitingReply, Completed,
    CompletionFooter, MessageCount) plus the V2 fields (BusySeen, Polls, ProbeMsMedian, ProbeMsMax, ...).

    WHICH WATCHER?  Use V2 (this script) by default; use V1 directly only when you need to watch with live
    progress lines, -ProgressFile or -NotifyOnDone, or when agentdebug-ui.exe is unavailable and you accept
    that V2 then returns no details.

    V2 pros:
      - Light while polling: about 7 percent of one core, about 0.3 to 1.5 seconds per probe on a long chat
        (V1: about 70 percent and about 4 seconds per poll), so it hardly disturbs the Visual Studio being driven.
      - Silent while polling (no per-poll tokens); -TraceFile is opt-in.
      - Never activates, restores, scrolls, clicks or types, so it works with the window overlapped or minimized.
      - Needs no agentdebug-ui.exe for the wait itself (in-process UI Automation).
      - Also reports NotVisible, WindowGone and ProbeError, which V1 does not.
      - The final detail step is also a safety net: if the light probe said Idle but the full tree shows an
        open prompt, the result is upgraded to Pending (Upgraded = true).
    V2 cons:
      - It watches whichever chat is VISIBLE, not one specific conversation. A change of chat is detected only through
        the session title in the chat pane header (see ChatSwitched below); if the header is missing, or two chats
        share a title, a switch looks like the old chat finishing (a false Idle). Always confirm with Read-CopilotReply.ps1.
      - The waiting itself is blind to anything outside the few things it looks for (below). A prompt of a shape
        it does not know looks like "busy" until the timeout. -CrossCheck compares it with the whole-window
        probe to find such shapes; run it after a Visual Studio or Copilot update.
      - It sees a card or prompt only in the LAST real message of the chat list, and only while the list is
        scrolled to its end (the list is virtualized; it never scrolls). A card above a scrolled-up view is missed.
      - A card is recognized by a button named "Submit" or "Next question", a permission prompt by "Allow this
        time"; other wording is missed while polling (the final detail step can still catch it).
      - The detail step needs agentdebug-ui.exe and Watch-CopilotChatV1.ps1 next to this script; without them
        the result has DetailNote instead of details.
      - With -RequireBusyFirst, a reply that finishes before the first probe is reported only after
        -StartGraceSeconds (V1 notices the new footer at once).
      - The completion-footer pattern is fixed in the script.
      - No -AsJson (pipe the object to ConvertTo-Json) and no progress file.

    HOW THE POLL WORKS
      The chat pane (class GenericPane, name Chat) has two kinds of direct children: the message list (class
      ChatSessionList, AutomationId session) and the input area. The pane is found once and cached.

      Input area, always rendered:
        - stop button (AutomationId CancelButton)   -> Copilot is busy (it stays on while Copilot waits for a
          permission and between tool steps, where the "Working" text is absent)
        - "Allow this time" button                  -> Pending, PermissionPrompt
        - "Submit" / "Next question" button         -> Pending, ChoiceCard
        - "Ask Copilot" placeholder                 -> the chat pane is showing (input empty)

      End of the message list, read only when the list is scrolled to its end. The list can end with empty
      view-model placeholder items (name "Microsoft.VisualStudio....") that carry no text; they are skipped to
      reach the last real message, which is then checked for:
        - a completion footer ("The response cost N credits." / "The response used the ... model") -> finished
        - a card or permission button inside it (the question card is a message in the list, not in the input
          area) -> Pending

    WHEN THE WAIT ENDS
      Pending     as soon as a card or permission prompt is seen.
      Idle        (a) once the stop button has been seen and is gone and the list ends in a completion footer, or
                  (b) after -QuietSeconds with no stop button and no prompt.
      NotVisible  neither the list nor the input placeholder is showing (another tab, such as Git Changes, is active).
      ChatSwitched  the visible chat is no longer the one being watched (someone clicked "New chat" or opened another
                  session): the session title changed, the stop button is gone and there is no completion footer.
                  The watched chat may still be working; select it again and read it with Read-CopilotReply.ps1.
      WindowGone  the window no longer exists.
      ProbeError  three probes in a row failed while the window still exists.
      Timeout     still busy after -TimeoutSeconds.
    Confirm an Idle reply with Read-CopilotReply.ps1, which scrolls to the end and reads it.

    TEST CASES: tests\Watch-CopilotChatV2.tests.md next to this script lists every scenario, how to set it up, the
    expected result and the last result. Read it before changing the probes and update it afterwards.

    SAFETY: it never clicks, types, scrolls, activates or restores a window. It writes only -TraceFile, if given.
    The detail step starts V1, which only reads (agentdebug-ui inspect).
.PARAMETER Hwnd
    Window handle, e.g. "0x121B1A".

.PARAMETER PollIntervalSeconds
    Time between poll starts. Default 5.

.PARAMETER QuietSeconds
    Fallback idle rule: no stop button and no prompt for this many seconds. Default 20, long enough to
    cover a quiet gap between Copilot's steps.

.PARAMETER RequireBusyFirst
    Do not report Idle until the stop button has been seen, or -StartGraceSeconds have passed. Use right
    after sending a prompt.

.PARAMETER StartGraceSeconds
    With -RequireBusyFirst: how long to wait for the stop button before accepting Idle. Default 30.

.PARAMETER TimeoutSeconds
    Give up after this long and report Timeout. Default 900.

.PARAMETER TraceFile
    Optional file; one line per poll: time, probe duration, flags.

.PARAMETER TitleContains
    Resolve the target window by title substring instead of passing -Hwnd (via
    Resolve-CopilotWindow.ps1, which needs agentdebug-ui.exe). No match throws a plain message,
    several matches throw the candidate list. Ignored when -Hwnd is also given.

.PARAMETER ExePath
    Path to agentdebug-ui.exe, used only by the detail step (V1). Default: the AgentDebugToolkit build output.

.PARAMETER NoDetail
    Skip the final detail step: the result then has no Question/Options/Banners/AwaitingReply/LastMessage and the
    wait ends sooner (no full tree dump). Use when only "done or waiting" matters.

.PARAMETER DetailTimeoutSeconds
    Upper bound for the detail step (it runs V1 once with a short poll interval). Default 25.

.PARAMETER CrossCheck
    Debug/validation: also run the slow whole-window probe on every poll and count disagreements with the
    scoped probe (Mismatches in the result). Adds the load this script exists to avoid; use it to validate.

.OUTPUTS
    PSCustomObject:
      State (Idle, Pending, NotVisible, ChatSwitched, WindowGone, ProbeError, Timeout), PromptKind (ChoiceCard / PermissionPrompt from the light probe; ChoicePrompt / FreeTextPrompt /
      PermissionPrompt once the detail step has run), BusySeen, Polls, ProbeMsMedian, ProbeMsMax, ElapsedSeconds,
      Mismatches (only with -CrossCheck), Note.
      From the detail step (null when it did not run or failed; see DetailNote):
        Question, Options, Recommended, MorePages (a multi-question card has more pages), Banners (Id, Text,
        Buttons of workspace-mismatch / trust banners), LastMessage, LastMessageTail (last 600 characters, only
        when AwaitingReply), AwaitingReply (the last message looks like a plain-text question or approval request:
        Idle then does NOT mean the task is done), Completed, CompletionFooter, MessageCount.
      Upgraded = true when the light probe said Idle but the detail step found an open prompt.
      DetailNote explains a skipped or failed detail step.

.EXAMPLE
    # Right after sending a prompt: wait for done/waiting, with details.
    .\Watch-CopilotChatV2.ps1 -Hwnd 0x121B1A -RequireBusyFirst

.EXAMPLE
    # Only "done or waiting" matters; no full tree dump at the end.
    .\Watch-CopilotChatV2.ps1 -Hwnd 0x121B1A -RequireBusyFirst -NoDetail

.EXAMPLE
    # Validate the light probe against the whole-window probe (Mismatches should be 0), with a trace.
    .\Watch-CopilotChatV2.ps1 -Hwnd 0x121B1A -TimeoutSeconds 30 -CrossCheck -TraceFile $env:TEMP\v2.txt -NoBeep
#>
[CmdletBinding()]
param(
    [string]$Hwnd,

    [ValidateRange(2, 120)]
    [int]$PollIntervalSeconds = 5,

    [ValidateRange(5, 300)]
    [int]$QuietSeconds = 20,

    [switch]$RequireBusyFirst,

    [ValidateRange(0, 300)]
    [int]$StartGraceSeconds = 30,

    [ValidateRange(10, 7200)]
    [int]$TimeoutSeconds = 900,

    [string]$TraceFile,

    [switch]$CrossCheck,

    [string]$ExePath = "$env:USERPROFILE\.copilot\toolkits\AgentDebugToolkit\src\AgentDebugToolkit.UiAutomation.Cli\bin\Debug\net8.0-windows\agentdebug-ui.exe",

    [switch]$NoDetail,

    [ValidateRange(10, 300)]
    [int]$DetailTimeoutSeconds = 25,

    # One short beep when the wait ends (done or waiting for a person). -NoBeep silences it (the review wrapper does, and beeps once itself).
    [switch]$NoBeep,

    [string]$TitleContains
)

$ErrorActionPreference = 'Stop'
if (-not $Hwnd -and -not $TitleContains) { throw 'Pass -Hwnd or -TitleContains.' }
if (-not $Hwnd) {
    $resolved = & (Join-Path $PSScriptRoot 'Resolve-CopilotWindow.ps1') -TitleContains $TitleContains -ExePath $ExePath
    if ($resolved.Error) { throw $resolved.Error }
    $Hwnd = $resolved.Hwnd
}
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes

$A = [System.Windows.Automation.AutomationElement]
$handle = [IntPtr][Convert]::ToInt64($Hwnd, 16)
$idProp = $A::AutomationIdProperty
$nameProp = $A::NameProperty
$classProp = $A::ClassNameProperty
function Cond($prop, [string]$value) { New-Object System.Windows.Automation.PropertyCondition($prop, $value) }

# What to look for in the input area, and (for the slow cross-check) in the whole window.
$inputCond = New-Object System.Windows.Automation.OrCondition(
    (Cond $idProp 'CancelButton'),
    (Cond $nameProp 'Allow this time'),
    (Cond $nameProp 'Submit'),
    (Cond $nameProp 'Next question'),
    (Cond $nameProp 'Ask Copilot'))
$wholeCond = New-Object System.Windows.Automation.OrCondition($inputCond, (Cond $idProp 'session'))
$paneCond = New-Object System.Windows.Automation.AndCondition((Cond $classProp 'GenericPane'), (Cond $nameProp 'Chat'))
$descendants = [System.Windows.Automation.TreeScope]::Descendants
$children = [System.Windows.Automation.TreeScope]::Children
$walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
$footerPattern = '^The response (used the .+ model|cost [\d.]+ credits?\.?$)'
$script:pane = $null
if (-not ('CopilotWait.NativeCheck' -as [type])) {   # define once per process; the wrapper may start this script many times
    Add-Type -Namespace CopilotWait -Name NativeCheck -MemberDefinition '[DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);'
}

# Title is the session title shown in the chat pane header (AutomationId "title"); $null when that element was not found.
function New-Flags { @{ Busy = $false; Permission = $false; Card = $false; Chat = $false; Footer = $false; Title = $null } }

function Add-Match($f, $e) {
    $id = $e.Current.AutomationId
    $name = $e.Current.Name
    if ($id -eq 'CancelButton') { $f.Busy = $true; $f.Chat = $true }
    elseif ($name -eq 'Allow this time') { $f.Permission = $true; $f.Chat = $true }
    elseif ($name -eq 'Submit' -or $name -eq 'Next question') { $f.Card = $true; $f.Chat = $true }
    elseif ($id -eq 'session' -or $name -eq 'Ask Copilot') { $f.Chat = $true }
}

# True when the list is scrolled to its end (or does not scroll), so its last rendered item is the last message.
function Test-ListAtEnd($list) {
    try {
        $p = $list.GetCurrentPattern([System.Windows.Automation.ScrollPattern]::Pattern)
        if (-not $p.Current.VerticallyScrollable) { return $true }
        $percent = $p.Current.VerticalScrollPercent
        if ($percent -ge 99) { return $true }
        # The scroll percentage is counted in items and often stops a little short of 100 (for example 98.5 with a
        # trailing placeholder item) although the last message is fully visible. Treat that as "at the end": the
        # last rendered item lies fully inside the visible list, so nothing further down is waiting to be rendered.
        if ($percent -ge 90) {
            $last = $walker.GetLastChild($list)
            if ($last) {
                $listBottom = $list.Current.BoundingRectangle.Bottom
                return ($last.Current.BoundingRectangle.Bottom -le ($listBottom + 3))
            }
        }
        return $false
    }
    catch { return $false }
}

# True when the list is scrolled to within about 10 percent of its end, so the last few rendered items are the
# newest messages. Looser than Test-ListAtEnd: used only to look for a card or prompt, which may be partly scrolled out.
function Test-ListNearEnd($list) {
    try {
        $p = $list.GetCurrentPattern([System.Windows.Automation.ScrollPattern]::Pattern)
        return (-not $p.Current.VerticallyScrollable) -or ($p.Current.VerticalScrollPercent -ge 90)
    }
    catch { return $false }
}
# Slow reference probe over the whole window (used only for -CrossCheck).
function Get-FlagsWhole {
    $f = New-Flags
    foreach ($e in $A::FromHandle($handle).FindAll($descendants, $wholeCond)) { Add-Match $f $e }
    $f
}

function Get-FlagsScoped {
    $f = New-Flags
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        if (-not $script:pane) { $script:pane = $A::FromHandle($handle).FindFirst($descendants, $paneCond) }
        if (-not $script:pane) { return $f }
        try {
            $kids = $script:pane.FindAll($children, [System.Windows.Automation.Condition]::TrueCondition)
            foreach ($k in $kids) {
                if ($k.Current.ClassName -eq 'ChatSessionList' -or $k.Current.AutomationId -eq 'session') {
                    $f.Chat = $true
                    $atEnd = Test-ListAtEnd $k
                    if ($atEnd -or (Test-ListNearEnd $k)) {
                        $item = $walker.GetLastChild($k)
                        # The list can end with empty view-model placeholders (name "Microsoft.VisualStudio....");
                        # V1 ignores them too, so skip them to reach the last real message.
                        $skipped = 0
                        while ($item -and $skipped -lt 5 -and $item.Current.Name -match '^Microsoft\.VisualStudio\.') {
                            $item = $walker.GetPreviousSibling($item)
                            $skipped++
                        }
                        # A finished reply: the last real message is a completion footer. Strict: only when the list
                        # is really at its end, otherwise an older reply's footer could be mistaken for the last one.
                        if ($atEnd -and $item -and ($item.Current.Name -match $footerPattern)) { $f.Footer = $true }
                        # A question card or permission prompt is a message in the list (a ChatMessageItem holding
                        # Submit / Next question / Allow this time), not part of the input area. It can be partly
                        # scrolled out of view, so look at the last few real messages while the list is near its end.
                        if (-not $f.Footer) {
                            $looked = 0
                            while ($item -and $looked -lt 3) {
                                foreach ($e in $item.FindAll($descendants, $inputCond)) { Add-Match $f $e }
                                $item = $walker.GetPreviousSibling($item)
                                $looked++
                            }
                        }
                    }                    continue
                }
                if ($k.Current.AutomationId -eq 'title') { $f.Title = $k.Current.Name }   # marker for ChatSwitched
                Add-Match $f $k                                   # the child itself may be the element
                foreach ($e in $k.FindAll($descendants, $inputCond)) { Add-Match $f $e }
            }
            return $f
        }
        catch {
            $script:pane = $null        # the cached pane may be stale (tab switch, window rebuilt): find it again once
            $f = New-Flags
            if ($attempt -ge 2) { throw }   # still failing on a fresh pane: a real probe failure, never "chat not visible"
        }
    }
    $f
}

# The details a light probe cannot see (question, options, banners, plain-text question detection, last message)
# come from one run of Watch-CopilotChatV1.ps1, made only when the wait ends. Returns @{ Data = <V1 result> } or
# @{ Error = <why not> }; never throws.
function Get-V1Detail {
    $v1 = Join-Path $PSScriptRoot 'Watch-CopilotChatV1.ps1'
    if (-not (Test-Path $v1)) { return @{ Error = 'Watch-CopilotChatV1.ps1 not found next to this script.' } }
    if (-not (Test-Path $ExePath)) { return @{ Error = "agentdebug-ui.exe not found at '$ExePath'; pass -ExePath." } }
    try {
        # 6>$null drops V1's per-poll console lines (Write-Host); its result is the JSON on the output stream.
        $raw = & $v1 -Hwnd $Hwnd -ExePath $ExePath -TimeoutSeconds $DetailTimeoutSeconds -PollIntervalSeconds 2 -MaxPollIntervalSeconds 3 -AsJson 6>$null | Out-String
        $d = $raw | ConvertFrom-Json
        if (-not $d) { return @{ Error = 'The detail step returned nothing.' } }
        return @{ Data = $d }
    }
    catch { return @{ Error = "The detail step failed: $($_.Exception.Message)" } }
}

# One field of a V1 result, or $null when V1 did not return it (V1 omits fields that do not apply to its state).
function Get-V1Field($d, [string]$Name) {
    if ($d.PSObject.Properties.Name -contains $Name) { return $d.$Name }
    $null
}

# Adds the V1 details to the result and reconciles the state (V1's full-tree view wins over the light probe).
function Add-Detail($o) {
    $res = Get-V1Detail
    foreach ($n in 'Question', 'Options', 'Recommended', 'MorePages', 'Banners', 'LastMessage', 'LastMessageTail', 'AwaitingReply', 'Completed', 'CompletionFooter', 'MessageCount') { $o[$n] = $null }
    if ($res.Error) { $o.DetailNote = $res.Error; return }
    $d = $res.Data
    foreach ($n in 'Question', 'Options', 'Recommended', 'MorePages', 'LastMessage', 'LastMessageTail', 'AwaitingReply', 'Completed', 'MessageCount') { $o[$n] = Get-V1Field $d $n }
    $o.CompletionFooter = Get-V1Field $d 'CompletionFooter'
    # V1 prints an empty banner list as an empty object; normalize to an empty array.
    $b = Get-V1Field $d 'Banners'
    $o.Banners = if ($b -and @($b.PSObject.Properties).Count -gt 0 -and ($b -is [System.Array] -or $b.Id)) { @($b) } else { @() }
    $v1State = Get-V1Field $d 'State'
    if ($v1State -eq 'Pending') {
        if ($o.State -ne 'Pending') {
            $o.Upgraded = $true
            $o.State = 'Pending'
            $o.Note = 'The light probe missed an open prompt; the full tree found it.'
        }
        $o.PromptKind = Get-V1Field $d 'PromptKind'
    }
    elseif ($o.State -eq 'Pending') {
        $o.DetailNote = "The detail step saw state '$v1State', not Pending: the prompt may have been answered meanwhile."
    }
    elseif ($v1State -ne 'Idle') {
        $o.DetailNote = "The detail step saw state '$v1State', so the chat may not be finished."
    }
    if ($o.State -eq 'Idle' -and $o.AwaitingReply) {
        $o.Note = 'The last message looks like a question or approval request in plain text (no card): Idle does not mean the task is done. Read LastMessageTail and reply.'
    }
}

function Finish([string]$State, [string]$Kind, [string]$Note) {
    $sorted = @($script:probeMs | Sort-Object)
    $o = [ordered]@{
        State          = $State
        PromptKind     = $Kind
        BusySeen       = $script:busySeen
        Polls          = $script:probeMs.Count
        ProbeMsMedian  = $(if ($sorted.Count) { $sorted[[int][math]::Floor(($sorted.Count - 1) / 2)] } else { $null })
        ProbeMsMax     = $(if ($sorted.Count) { $sorted[-1] } else { $null })
        ElapsedSeconds = [int]((Get-Date) - $script:started).TotalSeconds
    }
    if ($CrossCheck) { $o.Mismatches = $script:mismatches }
    $o.Note = $Note
    if (-not $NoBeep) { try { [console]::Beep(880, 200) } catch { } }   # beep first: the details below can take a while
    if (-not $NoDetail -and $State -in 'Pending', 'Idle') { Add-Detail $o }
    [pscustomobject]$o
}

$script:started = Get-Date
$script:probeMs = New-Object System.Collections.Generic.List[int]
$script:busySeen = $false
$script:mismatches = 0
$script:errors = 0
# ChatSwitched marker: the session title of the chat being watched. Adopted from the first non-empty title, so a new
# chat whose title only appears when its first message is sent does not count as a switch.
$script:titleMarker = $null
$script:markerSet = $false
$deadline = $script:started.AddSeconds($TimeoutSeconds)
$quietSince = $null
if ($TraceFile) { Set-Content -Path $TraceFile -Value "# Watch-CopilotChatV2 trace, hwnd $Hwnd, interval ${PollIntervalSeconds}s" -Encoding UTF8 }

while ($true) {
    $pollStart = Get-Date
    try {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $f = Get-FlagsScoped
        $sw.Stop()
        $whole = $null
        if ($CrossCheck) { $whole = Get-FlagsWhole }
    }
    catch {
        # Only a window that really no longer exists is WindowGone; any other failure is a probe error.
        if (-not [CopilotWait.NativeCheck]::IsWindow($handle)) { return (Finish 'WindowGone' $null 'The window no longer exists.') }
        $script:errors++
        if ($script:errors -ge 3) {
            return (Finish 'ProbeError' $null "The probe failed $($script:errors) times in a row while the window still exists: $($_.Exception.Message)")
        }
        if ((Get-Date) -ge $deadline) { return (Finish 'Timeout' $null "Still failing or busy after $TimeoutSeconds seconds.") }
        Start-Sleep -Seconds 1
        continue
    }
    $script:errors = 0
    $script:probeMs.Add([int]$sw.Elapsed.TotalMilliseconds)
    $elapsed = ($pollStart - $script:started).TotalSeconds

    $agree = $true
    if ($whole) {
        foreach ($k in 'Busy', 'Permission', 'Card', 'Chat') { if ($whole[$k] -ne $f[$k]) { $agree = $false } }
        if (-not $agree) { $script:mismatches++ }
    }
    if ($TraceFile) {
        $line = 't={0:N1} probeMs={1} busy={2} permission={3} card={4} chat={5} footerAtEnd={6} title=[{7}]' -f $elapsed, $script:probeMs[-1], [int]$f.Busy, [int]$f.Permission, [int]$f.Card, [int]$f.Chat, [int]$f.Footer, $(if ($f.Title) { $f.Title.Substring(0, [Math]::Min(30, $f.Title.Length)) })
        if ($whole) { $line += (' | whole busy={0} permission={1} card={2} chat={3} agree={4}' -f [int]$whole.Busy, [int]$whole.Permission, [int]$whole.Card, [int]$whole.Chat, [int]$agree) }
        Add-Content -Path $TraceFile -Encoding UTF8 -Value $line
    }

    if (-not $f.Chat) { return (Finish 'NotVisible' $null 'Neither the chat list nor the input placeholder is showing: another tab may be active.') }
    if ($f.Permission) { return (Finish 'Pending' 'PermissionPrompt' 'A tool permission prompt is waiting. Question and Options below come from the detail step.') }
    if ($f.Card) { return (Finish 'Pending' 'ChoiceCard' 'A question card is waiting. Question and Options below come from the detail step.') }

    # Chat switch: the title changed, the stop button is gone and nothing says the reply finished. A title that changes
    # while the chat is busy, or after a completion footer, is Copilot renaming the same session: follow it.
    if ($null -ne $f.Title) {
        if (-not $script:markerSet) {
            if ($f.Title) { $script:titleMarker = $f.Title; $script:markerSet = $true }
        }
        elseif ($f.Title -ne $script:titleMarker) {
            if ($script:busySeen -and -not $f.Busy -and -not $f.Footer) {
                return (Finish 'ChatSwitched' $null 'The visible chat is no longer the one being watched (its session title changed and the stop button is gone). The original chat may still be working: select it again and read it with Read-CopilotReply.ps1.')
            }
            $script:titleMarker = $f.Title
        }
    }

    if ($f.Busy) {
        $script:busySeen = $true
        $quietSince = $null
    }
    else {
        # Fast path: it was busy, the stop button is gone and the end of the list is a completion footer.
        if ($script:busySeen -and $f.Footer) {
            return (Finish 'Idle' $null 'The stop button is gone and the chat ends in a completion footer. Confirm the reply with Read-CopilotReply.ps1.')
        }
        $startGate = $RequireBusyFirst -and -not $script:busySeen -and ($elapsed -lt $StartGraceSeconds)
        if (-not $startGate) {
            if (-not $quietSince) { $quietSince = $pollStart }
            if (($pollStart - $quietSince).TotalSeconds -ge $QuietSeconds) {
                return (Finish 'Idle' $null 'No stop button and no prompt for the quiet period. Confirm the reply with Read-CopilotReply.ps1.')
            }
        }
    }

    if ((Get-Date) -ge $deadline) { return (Finish 'Timeout' $null "Still busy after $TimeoutSeconds seconds.") }
    $sleep = $PollIntervalSeconds - ((Get-Date) - $pollStart).TotalSeconds
    if ($sleep -gt 0) { Start-Sleep -Milliseconds ([int]($sleep * 1000)) }
}
