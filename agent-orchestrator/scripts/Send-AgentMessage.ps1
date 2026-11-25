<#
.SYNOPSIS
    Sends one message to a worker Copilot chat by the fastest route that is safe: mailbox, then the UI sender, then
    the UI sender's conservative path.

.DESCRIPTION
    Tier 1, Mailbox: if a worker chat is listening on this window's channel (Wait-AgentMailbox.ps1 is running and its
    heartbeat is fresh), the message is posted as a file and the listener claims it in about 0.2 s. Nothing is typed,
    no window is touched and the person at the keyboard is not disturbed. The message must be claimed within the
    ack timeout; otherwise it is withdrawn so it cannot arrive later as a duplicate.
    Tier 2, Ui: Send-CopilotPrompt.ps1 (all its guards: quiet wait, draft refusal, banners, own-host, exact read-back).
    Tier 3, Conservative: Send-CopilotPrompt.ps1 -Conservative (the older click-and-paste steps), tried only when tier 2
    failed in its input mechanics (read-back mismatch, paste or Send click failing, foreground not taken). A refusal
    that is a decision, not a mechanical failure (a draft in the input, the person is typing, off-screen input, a
    banner, own-host window, another agent holding the keyboard) is returned as it is: a second try would not help.
    When the chat is known to be listening but the mailbox could not deliver, the UI tiers use -Steer, because a
    listening chat is busy and a plain send would type into a busy chat.
    -Bootstrap sends the first message through the UI tiers and adds the one-line instructions that tell the worker to
    listen on the mailbox after each task (the mailbox cannot wake an idle chat).

.PARAMETER Hwnd
    Target window handle (hex). Optional when -TitleContains is given.

.PARAMETER TitleContains
    Resolve the target window by title substring. Used for the UI tiers; the channel name needs a handle or -Channel.

.PARAMETER Text
    The message. The mailbox accepts up to 8000 characters with line breaks; the UI tiers need a single line.

.PARAMETER Channel
    Mailbox channel. Default: derived from the window handle (w + hex digits).

.PARAMETER Mode
    Auto (default): mailbox, then Ui, then Conservative. Mailbox: only the mailbox. Ui: only the UI sender.
    Conservative: only the conservative UI sender.

.PARAMETER Bootstrap
    Send -Text as the worker's task by the UI tiers, with instructions to listen on the mailbox afterwards.

.PARAMETER StopListening
    Tell the listening worker to stop listening (a STOP message; no -Text needed).

.PARAMETER AckTimeoutSeconds
    How long to wait for the listener to claim a mailbox message (default 5).

.PARAMETER ReListenWaitSeconds
    A worker that has just taken a message is busy with it and listens again within seconds. When the last listener
    ended with a message or a timeout less than 20 s ago, wait up to this long (default 8) for a new one before using
    the UI. 0 turns the wait off.

.PARAMETER NewSession, Steer, OverwriteInput, AllowOwnHost, IgnoreBanners, IgnoreUserActivity, SpeakRequest
    Passed to Send-CopilotPrompt.ps1 for the UI tiers.

.PARAMETER QuietSeconds, MaxWaitSeconds
    Passed to Send-CopilotPrompt.ps1 for the UI tiers.

.PARAMETER AsJson
    Return JSON.

.OUTPUTS
    Sent, Tier (Mailbox, Ui, Conservative or None), Channel, MessageId (mailbox), Attempts (one line per tier tried),
    ElapsedMs, Error, plus Preview (the first 120 characters of the message, on one line) and Display (one line for the
    orchestrator to show the person: direction, route, time and preview). No reply text is returned.

.EXAMPLE
    .\Send-AgentMessage.ps1 -Hwnd 0x240CCA -Text 'Now run the build and report errors.'
#>
[CmdletBinding()]
param(
    [string]$Hwnd,

    [string]$Text,

    [string]$TitleContains,

    [string]$Channel,

    [ValidateSet('Auto', 'Mailbox', 'Ui', 'Conservative')]
    [string]$Mode = 'Auto',

    [switch]$Bootstrap,

    [switch]$StopListening,

    [ValidateRange(1, 60)]
    [int]$AckTimeoutSeconds = 5,

    [ValidateRange(0, 60)]
    [int]$ReListenWaitSeconds = 8,

    [switch]$NewSession,

    [switch]$Steer,

    [switch]$OverwriteInput,

    [switch]$AllowOwnHost,

    [switch]$IgnoreBanners,

    [switch]$IgnoreUserActivity,

    [switch]$SpeakRequest,

    [ValidateRange(0, 600)]
    [int]$QuietSeconds = 3,

    [ValidateRange(0, 3600)]
    [int]$MaxWaitSeconds = 120,

    [switch]$AsJson
)
$ErrorActionPreference = 'Stop'
$clock = [Diagnostics.Stopwatch]::StartNew()
. (Join-Path $PSScriptRoot 'AgentMailbox.ps1')
$script:ScriptDir = $PSScriptRoot
$senderPath = Join-Path $script:ScriptDir 'Send-CopilotPrompt.ps1'

# Failures of the input mechanics, where the older steps may still work. Anything else is a decision (a refusal) or
# a problem the same steps would meet again.
function Test-MechanicalUiFailure {
    param([string]$ErrorText)
    if ([string]::IsNullOrEmpty($ErrorText)) { return $false }
    return [bool]($ErrorText -match 'input never matched the prompt|read-back-mismatch|Send click failed|paste did not verify|Could not bring the target window to the foreground|verify-mismatch|verify-unstable|clipboard-unavailable')
}

function Invoke-UiSender {
    param([hashtable]$Arguments)
    try {
        $r = & $senderPath @Arguments 6>$null
        if ($null -eq $r) { return [pscustomobject]@{ Sent = $false; Attempts = 0; InputText = $null; Error = 'The sender returned nothing.' } }
        return $r
    }
    catch { return [pscustomobject]@{ Sent = $false; Attempts = 0; InputText = $null; Error = "SenderFailed: $($_.Exception.Message)" } }
}

function New-BootstrapText {
    param([string]$Task, [string]$ChannelName)
    $wait = Join-Path $script:ScriptDir 'Wait-AgentMailbox.ps1'
    $suffix = "Mailbox mode: whenever you have finished a task, run exactly this terminal command and nothing else: powershell -NoProfile -File `"$wait`" -Channel $ChannelName . It waits for my next instruction and prints it between MAILBOX MESSAGE markers; treat that text as my next instruction, begin your reply with one line starting From orchestrator: and a few words, so the person watching this chat can follow, do it, then run the command again. If it prints MAILBOX TIMEOUT run it again at once, but after two MAILBOX TIMEOUTs in a row stop listening and tell the person. If it prints MAILBOX STOP, stop listening and do not run it again."
    return "$Task $suffix"
}

function Invoke-AgentMessage {
    param([string]$MessageText)
    $attempts = New-Object 'System.Collections.Generic.List[string]'
    $out = [pscustomobject]@{ Sent = $false; Tier = 'None'; Channel = $script:ChannelName; MessageId = $null; Attempts = $null; ElapsedMs = 0; Error = $null }
    $registered = $false

    if (($Mode -in 'Auto', 'Mailbox') -and -not $NewSession -and -not $Bootstrap) {
        try {
            $state = Get-MailboxState -Channel $script:ChannelName
            # A worker that has just taken a message is busy with it and listens again within seconds: wait for that
            # instead of typing into its chat. One that stopped, timed out long ago or never listened is not waited for.
            if (-not $state.Live -and $ReListenWaitSeconds -gt 0 -and $state.LastExitReason -in 'message', 'timeout' -and $null -ne $state.LastExitAgeMs -and $state.LastExitAgeMs -lt 20000) {
                $wait = [Diagnostics.Stopwatch]::StartNew()
                while (-not $state.Live -and $wait.Elapsed.TotalSeconds -lt $ReListenWaitSeconds) { Start-Sleep -Milliseconds 100; $state = Get-MailboxState -Channel $script:ChannelName }
                $attempts.Add("Mailbox: waited $([int]$wait.ElapsedMilliseconds) ms for the worker to listen again ($(if ($state.Live) { 'it did' } else { 'it did not' }))")
            }
            # A chat that is listening, or has taken a message and not listened since, is busy: the UI tiers must steer it.
            $registered = [bool]($state.Registered -or ($state.LastExitReason -in 'message', 'timeout' -and $null -ne $state.LastExitAgeMs -and $state.LastExitAgeMs -lt 600000))
            if ($state.Live) {
                $posted = if ($StopListening) { Send-AgentMailboxMessage -Channel $script:ChannelName -Text 'stop' -Kind stop -AckTimeoutMs ($AckTimeoutSeconds * 1000) }
                          else { Send-AgentMailboxMessage -Channel $script:ChannelName -Text $MessageText -AckTimeoutMs ($AckTimeoutSeconds * 1000) }
                $attempts.Add("Mailbox: $($posted.Reason)")
                if ($posted.Delivered) { $out.Sent = $true; $out.Tier = 'Mailbox'; $out.MessageId = $posted.Id; return $out }
            }
            else { $attempts.Add("Mailbox: not used ($($state.Reason))") }
        }
        catch { $attempts.Add("Mailbox: error ($($_.Exception.Message))") }
        if ($Mode -eq 'Mailbox') { $out.Error = "Mailbox mode: not delivered. $($attempts[-1])"; $out.Attempts = @($attempts); return $out }
    }
    elseif ($Mode -eq 'Mailbox') { $out.Error = 'Mailbox mode cannot be used with -NewSession or -Bootstrap.'; return $out }
    if ($StopListening) { $out.Error = 'StopListening: no live listener on this channel, so nothing was sent.'; $out.Attempts = @($attempts); return $out }

    # The UI tiers.
    $uiArgs = @{ Text = $MessageText; Quiet = $true; QuietSeconds = $QuietSeconds; MaxWaitSeconds = $MaxWaitSeconds }
    if ($Hwnd) { $uiArgs.Hwnd = $Hwnd } else { $uiArgs.TitleContains = $TitleContains }
    foreach ($name in 'NewSession', 'AllowOwnHost', 'IgnoreBanners', 'IgnoreUserActivity', 'SpeakRequest', 'OverwriteInput') { if ((Get-Variable -Name $name -ValueOnly)) { $uiArgs[$name] = $true } }
    # A chat that was listening is busy (its listen command is running), so a plain send would type into a busy chat.
    if ($Steer -or ($registered -and -not $NewSession)) { $uiArgs.Steer = $true }

    foreach ($tier in @('Ui', 'Conservative')) {
        if ($Mode -eq 'Ui' -and $tier -ne 'Ui') { break }
        if ($Mode -eq 'Conservative' -and $tier -ne 'Conservative') { continue }
        $args2 = $uiArgs.Clone()
        if ($tier -eq 'Conservative') { $args2.Conservative = $true }
        $r = Invoke-UiSender -Arguments $args2
        if ($args2.ContainsKey('Steer') -and -not $Steer -and $r.Error -match '^SteerRequiresBusy') {
            # The listener had ended, so the chat is idle again: a plain send is right.
            $attempts.Add("$tier (steer): chat not busy; trying a plain send")
            $args2.Remove('Steer'); $r = Invoke-UiSender -Arguments $args2
        }
        if ($r.Sent) { $attempts.Add("${tier}: sent"); $out.Sent = $true; $out.Tier = $tier; $out.Attempts = @($attempts); return $out }
        $reason = if ($r.Error) { ([string]$r.Error -replace '\s+', ' ') } else { 'not sent' }
        if ($reason.Length -gt 160) { $reason = $reason.Substring(0, 160) + '...' }
        $attempts.Add("${tier}: $reason")
        $out.Error = [string]$r.Error
        $mechanical = Test-MechanicalUiFailure -ErrorText ([string]$r.Error)
        if ($tier -eq 'Ui' -and $mechanical -and $Mode -eq 'Auto') {
            # A Send click that failed leaves our own prompt in the input; the second try may replace exactly that.
            if ($r.InputText -is [string] -and $r.InputText -ceq $MessageText) { $uiArgs.OverwriteInput = $true }
            continue
        }
        break
    }
    $out.Attempts = @($attempts)
    return $out
}

if (-not $Hwnd -and -not $TitleContains -and -not $Channel) { throw 'Pass -Hwnd, -TitleContains or -Channel.' }
if (-not $Channel) {
    if (-not $Hwnd) { throw 'The channel name is derived from -Hwnd; pass -Hwnd or -Channel.' }
    $Channel = Get-MailboxChannelName -Hwnd $Hwnd
}
$script:ChannelName = $Channel
if (-not (Test-MailboxChannelName $Channel)) { throw "Invalid channel name '$Channel'." }
if (-not $StopListening -and [string]::IsNullOrWhiteSpace($Text)) { throw 'Pass -Text.' }

$sendText = $Text
if ($Bootstrap) {
    if ($Text -match "[`r`n]") { throw '-Bootstrap needs a single-line task.' }
    $sendText = New-BootstrapText -Task $Text -ChannelName $Channel
    [void](Initialize-Mailbox -Channel $Channel)
}
$result = Invoke-AgentMessage -MessageText $sendText
$result.ElapsedMs = [int]$clock.ElapsedMilliseconds
# Something the orchestrator can show the person, so the exchange is not invisible (message preview only, no reply text).
$shown = if ($StopListening) { '(stop listening)' } else { ([string]$Text -replace '\s+', ' ').Trim() }
if ($shown.Length -gt 120) { $shown = $shown.Substring(0, 120) + '...' }
Add-Member -InputObject $result -NotePropertyName Preview -NotePropertyValue $shown
$route = if ($result.Sent) { "via $($result.Tier) in $($result.ElapsedMs) ms" } else { "NOT SENT ($(([string]$result.Error -replace '\s+', ' ').Trim()))" }
Add-Member -InputObject $result -NotePropertyName Display -NotePropertyValue "Master -> worker $route : $shown"
if ($AsJson) { $result | ConvertTo-Json -Depth 3 } else { $result }
