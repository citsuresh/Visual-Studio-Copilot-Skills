<#
.SYNOPSIS
    Light-weight alternative to Watch-CopilotChatV1.ps1: waits for a Copilot chat to finish or to need a
    person, using one small UI Automation probe per poll instead of a full tree dump.

.DESCRIPTION
    WHICH WATCHER? This is V2, the light watcher and the default. Watch-CopilotChatV1.ps1 is the
    full-tree one; reach for it only for what this script does not return.

    V2 pros:
      - Light: about 7 percent of one core and about 0.3 seconds per probe on a long chat (V1: about
        70 percent and about 4 seconds), so it hardly disturbs the Visual Studio being driven.
      - Silent while polling (no per-poll tokens); -TraceFile is opt-in.
      - Never activates, restores, scrolls, clicks or types, so it works with the window overlapped or
        minimized.
      - In-process UI Automation: no agentdebug-ui.exe needed.
      - Also reports NotVisible, WindowGone and ProbeError, which V1 does not.
    V2 cons:
      - Says only THAT a prompt is waiting (Pending plus a prompt type); it does not return the
        question or options. Call Watch-CopilotChatV1.ps1 once for those.
      - No plain-text question detection: a reply that ends "please approve" is reported as plain
        Idle. Read the reply with Read-CopilotReply.ps1 and look for a question.
      - No banner reporting, and no -AsJson.
      - Recognizes a permission prompt only by the exact "Allow this time" button, and a card by
        "Submit" or "Next question"; other wording or the older "Waiting..." marker can be missed.
      - The completion-footer pattern is fixed in the script.
      - With -RequireBusyFirst, a reply that finishes before the first probe is reported only after
        -StartGraceSeconds (V1 notices the new footer at once).
    Watch-CopilotChatV1.ps1 dumps the whole UI tree on every poll (several seconds of UI Automation work
    inside Visual Studio per poll on a long chat). This script asks one cheap question per poll, in-process,
    and never searches inside the message list's items (it checks only the list's scroll position and its last item):

    Input area (always rendered, independent of how the list is scrolled):
      - the stop button (AutomationId CancelButton)       -> Copilot is busy (it stays on while Copilot waits
        for a permission and between tool steps, where the "Working" text is absent)
      - the "Allow this time" button (the "Deny" button is not checked separately) -> Pending, PermissionPrompt
      - a card's "Submit" or "Next question" button        -> Pending, ChoiceCard
      - the "Ask Copilot" placeholder                      -> the chat pane is showing (input empty)

    End of the message list (about 3 ms; read only when the list is scrolled to its end, because the list is
    virtualized and its last rendered item is only the real last message at the end):
      - the last item is a completion footer ("The response cost N credits." / "The response used the ...
        model")                                            -> a finished reply

    The chat pane (class GenericPane, name Chat) has the message list (class ChatSessionList) and the input
    area as direct children; only the non-list children are searched. The pane is found once and cached.
    The script never scrolls anything.

    Pending is reported as soon as it is seen. Idle is reported (a) as soon as the stop button has been seen
    and is gone and the list, scrolled to its end, ends in a completion footer, or (b) after -QuietSeconds
    with no stop button and no prompt. Either way, confirm the reply with Read-CopilotReply.ps1, which scrolls
    to the end and reads it. For the question text and options of a Pending prompt, call
    Watch-CopilotChatV1.ps1 once (it extracts them); this script only says that something is waiting.

    Nothing is written to the console while polling, so a caller reading only the final result spends no
    tokens on polls. -TraceFile writes one line per poll for debugging.

    It never clicks, types, scrolls, activates or restores a window. The only thing it writes is -TraceFile, if given.

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

.PARAMETER CrossCheck
    Debug/validation: also run the slow whole-window probe on every poll and count disagreements with the
    scoped probe (Mismatches in the result). Adds the load this script exists to avoid; use it to validate.

.OUTPUTS
    PSCustomObject: State (Idle, Pending, NotVisible, WindowGone, ProbeError, Timeout), PromptKind, BusySeen, Polls,
    ProbeMsMedian, ProbeMsMax, ElapsedSeconds, Mismatches (only with -CrossCheck), Note.

.EXAMPLE
    .\Watch-CopilotChatV2.ps1 -Hwnd 0x121B1A -RequireBusyFirst
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
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

    # One short beep when the wait ends. -NoBeep silences it (the review wrapper does, and beeps once itself).
    [switch]$NoBeep
)

$ErrorActionPreference = 'Stop'
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

function New-Flags { @{ Busy = $false; Permission = $false; Card = $false; Chat = $false; Footer = $false } }

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
        return (-not $p.Current.VerticallyScrollable) -or ($p.Current.VerticalScrollPercent -ge 99)
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
                    if (Test-ListAtEnd $k) {
                        $last = $walker.GetLastChild($k)
                        if ($last -and ($last.Current.Name -match $footerPattern)) { $f.Footer = $true }
                    }
                    continue
                }
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
    if (-not $NoBeep) { try { [console]::Beep(880, 200) } catch { } }
    [pscustomobject]$o
}

$script:started = Get-Date
$script:probeMs = New-Object System.Collections.Generic.List[int]
$script:busySeen = $false
$script:mismatches = 0
$script:errors = 0
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
        $line = 't={0:N1} probeMs={1} busy={2} permission={3} card={4} chat={5} footerAtEnd={6}' -f $elapsed, $script:probeMs[-1], [int]$f.Busy, [int]$f.Permission, [int]$f.Card, [int]$f.Chat, [int]$f.Footer
        if ($whole) { $line += (' | whole busy={0} permission={1} card={2} chat={3} agree={4}' -f [int]$whole.Busy, [int]$whole.Permission, [int]$whole.Card, [int]$whole.Chat, [int]$agree) }
        Add-Content -Path $TraceFile -Encoding UTF8 -Value $line
    }

    if (-not $f.Chat) { return (Finish 'NotVisible' $null 'Neither the chat list nor the input placeholder is showing: another tab may be active.') }
    if ($f.Permission) { return (Finish 'Pending' 'PermissionPrompt' 'A tool permission prompt is waiting. Use Watch-CopilotChatV1.ps1 for its question and options.') }
    if ($f.Card) { return (Finish 'Pending' 'ChoiceCard' 'A question card is waiting. Use Watch-CopilotChatV1.ps1 for its question and options.') }

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
