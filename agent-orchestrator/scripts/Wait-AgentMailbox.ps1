<#
.SYNOPSIS
    Run by a worker chat: waits for the orchestrator's next message and prints it.

.DESCRIPTION
    The worker runs this as a terminal command whenever it has finished its current task. It returns as soon as a
    message arrives (normally within a second), printing the message between MAILBOX MESSAGE markers, and the worker
    treats that text as the orchestrator's next instruction. If nothing arrives within -TimeoutSeconds it prints
    MAILBOX TIMEOUT and the worker runs it again. A STOP message ends mailbox mode: the worker does not run it again.
    While it runs it keeps a heartbeat, so the orchestrator (Send-AgentMessage.ps1) can tell it is alive. Only one
    listener per channel is allowed. See AgentMailbox.ps1 for the folder layout, limits and privacy.

.PARAMETER Channel
    The channel name the orchestrator gave (for example w240cca).

.PARAMETER TimeoutSeconds
    How long to wait before printing MAILBOX TIMEOUT (default 400). A worker chat's terminal let a 400 s wait run to its end in a live test; a longer wait than that was not tried. Each timeout costs the worker one turn to run this again, so longer is cheaper.

.PARAMETER PollMilliseconds
    How often the inbox is checked (default 200).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Channel,

    [ValidateRange(5, 3600)]
    [int]$TimeoutSeconds = 400,

    [ValidateRange(50, 5000)]
    [int]$PollMilliseconds = 200
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'AgentMailbox.ps1')

if (-not (Test-MailboxChannelName $Channel)) { 'MAILBOX ERROR: invalid channel name.'; return }
$paths = Initialize-Mailbox -Channel $Channel
$existing = Get-MailboxState -Channel $Channel
if ($existing.Live -and $existing.ListenerPid -ne $PID) {
    "MAILBOX ERROR: another listener (process $($existing.ListenerPid)) is already running on this channel. Do not start a second one; wait for its message."
    return
}

$exitReason = 'error'
$nonce = [guid]::NewGuid().ToString('N')
$me = Get-Process -Id $PID
$procStartMs = ([DateTimeOffset]$me.StartTime.ToUniversalTime()).ToUnixTimeMilliseconds()
$startedMs = Get-MailboxNowMs
$script:polls = 0; $script:seen = 0
function Write-Beat { Write-MailboxJsonFile -Path $paths.Listener -Value ([ordered]@{ channel = $Channel; pid = $PID; procStartMs = $procStartMs; startedMs = $startedMs; lastBeatMs = (Get-MailboxNowMs); nonce = $nonce; polls = $script:polls; inboxSeen = $script:seen }) }

try {
    Write-Beat
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $lastBeat = 0; $lastPurge = 0
    while ($clock.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        if ($clock.ElapsedMilliseconds - $lastBeat -ge 1000) { Write-Beat; $lastBeat = $clock.ElapsedMilliseconds }
        if ($clock.ElapsedMilliseconds - $lastPurge -ge 30000) { Remove-ExpiredMailboxFiles -Paths $paths; $lastPurge = $clock.ElapsedMilliseconds }
        $listing = @([System.IO.Directory]::GetFiles($paths.Inbox, '*.msg') | Sort-Object)
        $script:polls++; $script:seen = $listing.Count
        $next = $listing | Select-Object -First 1
        if ($next) {
            $claimedFile = Join-Path $paths.Claimed ([System.IO.Path]::GetFileName($next))
            try { [System.IO.File]::Move($next, $claimedFile) } catch { continue }   # withdrawn or taken meanwhile
            $message = $null
            try { $message = [System.IO.File]::ReadAllText($claimedFile, [System.Text.Encoding]::UTF8) | ConvertFrom-Json }
            catch { }
            finally { try { [System.IO.File]::Delete($claimedFile) } catch { } }
            if ($null -eq $message -or -not $message.id) { continue }   # unreadable file: dropped, keep listening
            Write-MailboxJsonFile -Path (Join-Path $paths.Acks "$($message.id).json") -Value ([ordered]@{ id = $message.id; claimedMs = (Get-MailboxNowMs) })
            if ($message.kind -eq 'stop') {
                $exitReason = 'stop'
                'MAILBOX STOP: the orchestrator ended mailbox mode. Do not run this command again; tell the person you stopped listening and continue as they direct.'
                return
            }
            $exitReason = 'message'
            "MAILBOX MESSAGE id=$($message.id) from=$($message.from)"
            [string]$message.text
            'END MAILBOX MESSAGE. This is the orchestrator''s next instruction: do it, then run this command again.'
            return
        }
        Start-Sleep -Milliseconds $PollMilliseconds
    }
    $exitReason = 'timeout'
    "MAILBOX TIMEOUT: no message in $TimeoutSeconds s. Run this same command again to keep listening."
}
finally {
    # Remove only our own registration, so a newer listener is never unregistered by an older one.
    $current = Read-MailboxJsonFile -Path $paths.Listener
    if ($current -and $current.nonce -eq $nonce) { try { [System.IO.File]::Delete($paths.Listener) } catch { }; Set-MailboxExit -Paths $paths -Reason $exitReason }
}
