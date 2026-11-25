<#
.SYNOPSIS
Offline mailbox protocol checks: privacy, liveness, claim and ack, withdrawal, limits, retention and stop; no chat or UI.
.DESCRIPTION
Uses a disposable folder (AGENTUI_MAILBOX_ROOT) and real child PowerShell processes as listeners. No window, keyboard,
mouse, clipboard or repository file is touched.
#>
[CmdletBinding()]
param([string]$ScriptsPath)
$ErrorActionPreference = 'Stop'
if (-not $ScriptsPath) { $ScriptsPath = Join-Path $PSScriptRoot '..\..\agent-orchestrator\scripts' }
$ScriptsPath = (Resolve-Path $ScriptsPath).Path
$script:assertions = 0
function Assert-True([bool]$Condition, [string]$Message) { $script:assertions++; if (-not $Condition) { throw "$Message (assertion $($script:assertions), line $((Get-PSCallStack)[1].ScriptLineNumber))" } }
$root = Join-Path ([IO.Path]::GetTempPath()) ('mailbox-test-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$env:AGENTUI_MAILBOX_ROOT = $root
$logDir = Join-Path ([IO.Path]::GetTempPath()) ('mailbox-test-logs-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$env:AGENTUI_LOG_DIR = $logDir
$psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$router = Join-Path $ScriptsPath 'Send-AgentMessage.ps1'
$children = New-Object 'System.Collections.Generic.List[object]'
function Start-Listener([string]$Channel, [int]$TimeoutSeconds = 30) {
    $out = Join-Path $root ("out-$Channel-" + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.txt')
    $p = Start-Process $psExe -ArgumentList '-NoLogo', '-NoProfile', '-File', (Join-Path $ScriptsPath 'Wait-AgentMailbox.ps1'), '-Channel', $Channel, '-TimeoutSeconds', $TimeoutSeconds -PassThru -RedirectStandardOutput $out -WindowStyle Hidden
    $children.Add($p)
    $w = [Diagnostics.Stopwatch]::StartNew()
    while ($w.Elapsed.TotalSeconds -lt 15) { if ((Get-MailboxState -Channel $Channel).Live) { break }; Start-Sleep -Milliseconds 100 }
    return [pscustomobject]@{ Process = $p; Out = $out }
}
function Read-Listener($l) { $l.Process.WaitForExit(15000) | Out-Null; return ((Get-Content -LiteralPath $l.Out -Raw) -replace "`r`n", "`n").Trim() }
try {
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    . (Join-Path $ScriptsPath 'AgentMailbox.ps1')

    # ---- names ----
    Assert-True ((Get-MailboxChannelName -Hwnd '0x240CCA') -ceq 'w240cca') 'The channel name must come from the window handle in lower-case hex.'
    foreach ($bad in @('', '..', 'a b', 'a\b', 'a/b', '-x', ('x' * 41), 'a:b')) { Assert-True (-not (Test-MailboxChannelName $bad)) "Channel name '$bad' must be refused." }
    foreach ($good in @('w240cca', 'build-1', 'A_b', ('x' * 40))) { Assert-True (Test-MailboxChannelName $good) "Channel name '$good' must be accepted." }
    $threw = $false; try { $null = Get-MailboxPaths -Channel '..\evil' } catch { $threw = $true }
    Assert-True $threw 'A path-like channel name must never reach the file system.'

    # ---- privacy ----
    $paths = Initialize-Mailbox -Channel 'priv'
    $acl = Get-Acl -LiteralPath $paths.Dir
    $me = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $rules = @($acl.Access)
    Assert-True ($acl.AreAccessRulesProtected) 'The mailbox folder must not inherit permissions.'
    Assert-True (@($rules | Where-Object { $_.IsInherited }).Count -eq 0) 'No inherited permission may remain on the mailbox folder.'
    $sids = @($rules | ForEach-Object { $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value } | Sort-Object -Unique)
    $allowed = @($me.Value, 'S-1-5-18')
    Assert-True (@($sids | Where-Object { $allowed -notcontains $_ }).Count -eq 0) 'Only the current user and the system may have access to the mailbox folder.'
    Assert-True ($sids -contains $me.Value) 'The current user must keep access to the mailbox folder.'
    Assert-True ((Test-Path $paths.Inbox) -and (Test-Path $paths.Claimed) -and (Test-Path $paths.Acks)) 'The inbox, claimed and acks folders must exist.'

    # ---- liveness ----
    $state = Get-MailboxState -Channel 'live1'
    Assert-True (-not $state.Registered -and -not $state.Live -and $state.Reason -eq 'NoListener') 'A channel with no listener file must read as no listener.'
    $paths = Initialize-Mailbox -Channel 'live1'
    $startMs = ([DateTimeOffset](Get-Process -Id $PID).StartTime.ToUniversalTime()).ToUnixTimeMilliseconds()
    function Write-FakeListener([int]$ProcessId, [int64]$StartMs, [int64]$BeatAgeMs) {
        Write-MailboxJsonFile -Path (Get-MailboxPaths 'live1').Listener -Value ([ordered]@{ channel = 'live1'; pid = $ProcessId; procStartMs = $StartMs; startedMs = $StartMs; lastBeatMs = ((Get-MailboxNowMs) - $BeatAgeMs); nonce = 'x' })
    }
    Write-FakeListener $PID $startMs 100
    $state = Get-MailboxState -Channel 'live1'
    Assert-True ($state.Live -and $state.Registered -and $state.Reason -eq 'Listening') 'A fresh heartbeat from a real process with the recorded start time must read as live.'
    Write-FakeListener $PID $startMs 5000
    $state = Get-MailboxState -Channel 'live1'
    Assert-True ($state.Registered -and -not $state.Live -and $state.Reason -eq 'HeartbeatStale') 'An old heartbeat must read as stale, not live.'
    Write-FakeListener 999999 $startMs 100
    $state = Get-MailboxState -Channel 'live1'
    Assert-True (-not $state.Live -and $state.Reason -eq 'ProcessGone') 'A heartbeat from a process that does not exist must not read as live.'
    Write-FakeListener $PID ($startMs - 60000) 100
    $state = Get-MailboxState -Channel 'live1'
    Assert-True (-not $state.Live -and $state.Reason -eq 'ProcessReplaced') 'A reused process id (different start time) must not read as live.'
    [IO.File]::WriteAllText((Get-MailboxPaths 'live1').Listener, '{ not json', (New-Object Text.UTF8Encoding($false)))
    Assert-True (-not (Get-MailboxState -Channel 'live1').Live) 'A corrupt listener file must not read as live.'

    # ---- posting without a live listener, limits ----
    $r = Send-AgentMailboxMessage -Channel 'nobody' -Text 'hello'
    Assert-True (-not $r.Delivered -and $r.Reason -match '^NoLiveListener') 'Posting with no listener must not deliver.'
    Assert-True (-not (Test-Path (Join-Path $root 'nobody'))) 'Posting with no listener must not create a mailbox folder.'
    Write-FakeListener $PID $startMs 100
    $r = Send-AgentMailboxMessage -Channel 'live1' -Text ('x' * 8001)
    Assert-True (-not $r.Delivered -and $r.Reason -match '^TooLong') 'A message over 8000 characters must be refused.'
    $r = Send-AgentMailboxMessage -Channel 'live1' -Text ''
    Assert-True (-not $r.Delivered -and $r.Reason -match '^Empty') 'An empty message must be refused.'
    $inbox = (Get-MailboxPaths 'live1').Inbox
    1..20 | ForEach-Object { [IO.File]::WriteAllText((Join-Path $inbox ('{0:D15}-fill{1}.msg' -f $_, $_)), '{}') }
    $r = Send-AgentMailboxMessage -Channel 'live1' -Text 'one too many'
    Assert-True (-not $r.Delivered -and $r.Reason -eq 'InboxFull') 'A full inbox must refuse the 21st message.'
    foreach ($f in [IO.Directory]::GetFiles($inbox)) { [IO.File]::Delete($f) }

    # ---- withdrawal: a listener that looks alive but never claims ----
    Write-FakeListener $PID $startMs 100
    $r = Send-AgentMailboxMessage -Channel 'live1' -Text 'nobody takes this' -AckTimeoutMs 600
    Assert-True (-not $r.Delivered -and $r.Reason -match '^NotClaimed') 'An unclaimed message must report not delivered.'
    Assert-True (@([IO.Directory]::GetFiles($inbox)).Count -eq 0) 'An unclaimed message must be withdrawn so it cannot arrive later as a duplicate.'

    # ---- retention ----
    $paths = Get-MailboxPaths 'live1'
    $old = Join-Path $paths.Inbox '000000000000001-old.msg'; $new = Join-Path $paths.Inbox '000000000000002-new.msg'
    $oldAck = Join-Path $paths.Acks 'old.json'; $oldClaimed = Join-Path $paths.Claimed 'left.msg'
    foreach ($f in @($old, $new, $oldAck, $oldClaimed)) { [IO.File]::WriteAllText($f, '{}') }
    foreach ($f in @($old, $oldAck, $oldClaimed)) { [IO.File]::SetLastWriteTime($f, (Get-Date).AddMinutes(-11)) }
    Remove-ExpiredMailboxFiles -Paths $paths
    Assert-True (-not (Test-Path $old) -and -not (Test-Path $oldAck) -and -not (Test-Path $oldClaimed)) 'Messages, acks and claimed leftovers older than ten minutes must be deleted.'
    Assert-True (Test-Path $new) 'A recent message must be kept.'
    [IO.File]::Delete($new)
    [IO.File]::Delete($paths.Listener)

    # ---- a real listener: claim, ack, content, cleanup ----
    $text = "line one`nline two `"quoted`" C:\temp\x `$env:PATH ; & ( ) { }"
    $l = Start-Listener 'real1'
    $state = Get-MailboxState -Channel 'real1'
    Assert-True ($state.Live -and $state.ListenerPid -eq $l.Process.Id) 'A running listener must read as live with its own process id.'
    $r = Send-AgentMailboxMessage -Channel 'real1' -Text $text -From 'tester'
    Assert-True ($r.Delivered -and $r.Reason -eq 'Delivered') 'A message to a live listener must be claimed and acknowledged.'
    $printed = Read-Listener $l
    $expectedBody = $text -replace "`r`n", "`n"
    Assert-True ($printed -ceq ("MAILBOX MESSAGE id=$($r.Id) from=tester`n$expectedBody`nEND MAILBOX MESSAGE. This is the orchestrator's next instruction: do it, start your answer with the line `"Replying to orchestrator: <a few words>`", then run this command again.")) 'The listener must print the exact text, multi-line and with quotes, between markers.'
    Assert-True ($l.Process.HasExited) 'A listener must exit after printing a message.'
    $paths = Get-MailboxPaths 'real1'
    Assert-True (-not (Test-Path $paths.Listener)) 'A listener must remove its registration when it exits.'
    Assert-True (@([IO.Directory]::GetFiles($paths.Inbox)).Count -eq 0 -and @([IO.Directory]::GetFiles($paths.Claimed)).Count -eq 0 -and @([IO.Directory]::GetFiles($paths.Acks)).Count -eq 0) 'After delivery no message text or ack may stay on disk.'
    Assert-True (-not (Get-MailboxState -Channel 'real1').Live) 'After a listener exits the channel must read as not live.'
    $exitState = Get-MailboxState -Channel 'real1'
    Assert-True ($exitState.LastExitReason -eq 'message' -and $exitState.LastExitAgeMs -ge 0 -and $exitState.LastExitAgeMs -lt 15000) 'A listener that took a message must record that, so a sender knows the worker is busy and will listen again.'

    # ---- order, a second listener, stop ----
    $l = Start-Listener 'real2'
    $second = Start-Process $psExe -ArgumentList '-NoLogo', '-NoProfile', '-File', (Join-Path $ScriptsPath 'Wait-AgentMailbox.ps1'), '-Channel', 'real2', '-TimeoutSeconds', 20 -PassThru -RedirectStandardOutput (Join-Path $root 'second.txt') -WindowStyle Hidden -Wait
    $secondOut = (Get-Content -LiteralPath (Join-Path $root 'second.txt') -Raw).Trim()
    Assert-True ($secondOut -match '^MAILBOX ERROR: another listener .* already running') 'A second listener on the same channel must refuse to start.'
    Assert-True ((Get-MailboxState -Channel 'real2').ListenerPid -eq $l.Process.Id) 'A refused second listener must not take over the registration.'
    $r = Send-AgentMailboxMessage -Channel 'real2' -Text 'stop' -Kind stop
    Assert-True $r.Delivered 'A stop message must be delivered like any other.'
    Assert-True ((Read-Listener $l) -match '^MAILBOX STOP:.*From orchestrator: stop listening.*Do not run this command again') 'A stop message must tell the worker to say it is stopping, and not to listen again.'
    Assert-True ((Get-MailboxState -Channel 'real2').LastExitReason -eq 'stop') 'A stopped listener must record stop, so it is not waited for.'

    $paths = Initialize-Mailbox -Channel 'order'
    $a = Join-Path $paths.Inbox ('{0:D15}-aaaaaaaaaaaa.msg' -f 100); $b = Join-Path $paths.Inbox ('{0:D15}-bbbbbbbbbbbb.msg' -f 200)
    Write-MailboxJsonFile -Path $b -Value ([ordered]@{ id = 'bbbbbbbbbbbb'; kind = 'message'; from = 't'; createdMs = 2; text = 'second' })
    Write-MailboxJsonFile -Path $a -Value ([ordered]@{ id = 'aaaaaaaaaaaa'; kind = 'message'; from = 't'; createdMs = 1; text = 'first' })
    $l = Start-Listener 'order'
    $printed = Read-Listener $l
    Assert-True ($printed -match 'id=aaaaaaaaaaaa' -and $printed -match "`nfirst`n") 'The oldest message must be delivered first.'
    $l = Start-Listener 'order'
    Assert-True ((Read-Listener $l) -match 'id=bbbbbbbbbbbb' -and (Test-Path $paths.Inbox)) 'The next listener must get the next message.'

    # ---- a damaged message is dropped, the listener keeps listening ----
    $paths = Initialize-Mailbox -Channel 'bad'
    [IO.File]::WriteAllText((Join-Path $paths.Inbox ('{0:D15}-bad.msg' -f 1)), 'not json at all')
    $l = Start-Listener 'bad' -TimeoutSeconds 6
    Start-Sleep -Milliseconds 700
    Assert-True (-not $l.Process.HasExited) 'A damaged message must not end the listener.'
    Assert-True (@([IO.Directory]::GetFiles($paths.Inbox)).Count -eq 0 -and @([IO.Directory]::GetFiles($paths.Claimed)).Count -eq 0) 'A damaged message must be dropped, not kept.'
    $r = Send-AgentMailboxMessage -Channel 'bad' -Text 'after the bad one'
    Assert-True ($r.Delivered -and ((Read-Listener $l) -match 'after the bad one')) 'A good message after a damaged one must still be delivered.'

    # ---- timeout ----
    $l = Start-Listener 'tmo' -TimeoutSeconds 5
    Assert-True ((Read-Listener $l) -match '^MAILBOX TIMEOUT: no message in 5 s\. Run this same command again') 'With no message the listener must say timeout and how to continue.'
    Assert-True (-not (Test-Path (Get-MailboxPaths 'tmo').Listener)) 'A timed-out listener must remove its registration.'
    Assert-True ((Get-MailboxState -Channel 'tmo').LastExitReason -eq 'timeout') 'A timed-out listener must record timeout.'
    $rows = @(Get-MailboxStatusList)
    $tmoRow = @($rows | Where-Object { $_.Channel -eq 'tmo' })
    Assert-True ($tmoRow.Count -eq 1 -and -not $tmoRow[0].Live -and $tmoRow[0].LastExitReason -eq 'timeout' -and $tmoRow[0].MessagesWaiting -eq 0) 'The status list must show an ended channel with its exit reason and no waiting messages.'
    Assert-True (@($rows | Where-Object { $_.Channel -eq 'nobody' }).Count -eq 0) 'A channel that was never created must not be listed.'
    $statusListener = Start-Listener 'stat1'
    $liveRow = @(Get-MailboxStatusList | Where-Object { $_.Channel -eq 'stat1' })
    Assert-True ($liveRow.Count -eq 1 -and $liveRow[0].Live -and $liveRow[0].ListenerPid -eq $statusListener.Process.Id) 'The status list must show a live listener with its process id.'
    $null = Send-AgentMailboxMessage -Channel 'stat1' -Text 'stop' -Kind stop
    $null = Read-Listener $statusListener
    Assert-True ((Get-MailboxState -Channel 'nobody2').LastExitReason -eq $null) 'A channel that never had a listener has no exit reason.'

    # ---- troubleshooting log ----
    $secret = 'log-secret-phrase-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
    $l = Start-Listener 'logch'
    $r = Send-AgentMailboxMessage -Channel 'logch' -Text "please do $secret"
    Assert-True $r.Delivered 'A message for the log test must be delivered.'
    $null = Read-Listener $l
    $fp = Get-MailboxTextFingerprint "please do $secret"
    $log = @(Read-MailboxLog -Channel 'logch' -Last 0)
    $post = @($log | Where-Object { $_.Side -eq 'sender' -and $_.event -eq 'post' -and $_.id -eq $r.Id })
    $claim = @($log | Where-Object { $_.Side -eq 'listener' -and $_.event -eq 'claim' -and $_.id -eq $r.Id })
    Assert-True ($post.Count -eq 1 -and $post[0].delivered -eq $true -and $post[0].hash -eq $fp.Hash -and $post[0].length -eq $fp.Length) 'The sender log must record the post with the message length and hash.'
    Assert-True ($claim.Count -eq 1 -and $claim[0].hash -eq $fp.Hash -and $claim[0].length -eq $fp.Length) 'The listener log must record the claim with the same hash, so one message can be followed across both logs.'
    Assert-True (@($log | Where-Object { $_.Side -eq 'listener' -and $_.event -eq 'listen-start' }).Count -ge 1 -and @($log | Where-Object { $_.Side -eq 'listener' -and $_.event -eq 'listen-end' -and $_.reason -eq 'message' }).Count -ge 1) 'The listener log must record when it started and why it ended.'
    foreach ($f in @((Get-MailboxLogPath -Side sender), (Get-MailboxLogPath -Side listener -Channel 'logch'))) { Assert-True ((Test-Path $f) -and -not ([IO.File]::ReadAllText($f) -match [regex]::Escape($secret))) "No message text may be written to a log by default: $f" }
    Assert-True (@($log | Select-Object -ExpandProperty ts) -join ',' -ceq ((@($log | Select-Object -ExpandProperty ts) | Sort-Object) -join ',')) 'Merged log entries must be oldest first.'
    Assert-True (@(Read-MailboxLog -Channel 'logch' -Last 2).Count -eq 2 -and @(Read-MailboxLog -Channel 'other-channel' -Last 0 | Where-Object { $_.Side -eq 'sender' }).Count -eq 0) 'Last must limit the entries, and another channel must not see this channel''s sender entries.'
    Write-FakeListener $PID $startMs 100
    $before = @(Read-MailboxLog -Channel 'live1' -Last 0 | Where-Object { $_.event -eq 'post' }).Count
    $null = Send-AgentMailboxMessage -Channel 'live1' -Text 'unclaimed' -AckTimeoutMs 400
    $after = @(Read-MailboxLog -Channel 'live1' -Last 0 | Where-Object { $_.event -eq 'post' })
    Assert-True ($after.Count -eq $before + 1 -and $after[-1].delivered -eq $false -and $after[-1].reason -eq 'withdrawn') 'A withdrawn message must be logged as not delivered.'
    Assert-True ((Get-Content -LiteralPath $router -Raw) -match 'if \(-not \$NoLog\)' -and (Get-Content -LiteralPath $router -Raw) -match 'if \(\$LogText\) \{ \$entry\.text') 'The router must log each send unless -NoLog, and add text only with -LogText.'

    # ---- logs stay small ----
    $bigPath = Join-Path $logDir 'rotate.jsonl'
    1..40 | ForEach-Object { Write-MailboxLog -Path $bigPath -Entry ([ordered]@{ event = 'fill'; filler = ('x' * 20000) }) }
    Assert-True ((Test-Path $bigPath) -and (Test-Path "$bigPath.1")) 'A log over 512 KB must be rotated, keeping one old file.'
    Assert-True ((Get-Item $bigPath).Length -le 600000 -and (Get-Item "$bigPath.1").Length -le 600000) 'Each log file must stay near the size limit.'
    [IO.File]::SetLastWriteTime("$bigPath.1", (Get-Date).AddDays(-31))
    Write-MailboxLog -Path $bigPath -Entry ([ordered]@{ event = 'after' })
    Assert-True (-not (Test-Path "$bigPath.1")) 'A rotated log older than 30 days must be deleted.'
    $oldLog = Join-Path $logDir 'ancient.jsonl'; [IO.File]::WriteAllText($oldLog, '{}'); [IO.File]::SetLastWriteTime($oldLog, (Get-Date).AddDays(-45))
    $freshLog = Join-Path $logDir 'recent.jsonl'; [IO.File]::WriteAllText($freshLog, '{}')
    $oldChannel = Join-Path $root 'stalechannel'; $newChannel = Join-Path $root 'freshchannel'
    foreach ($ch in @($oldChannel, $newChannel)) { New-Item -ItemType Directory -Path "$ch\inbox" -Force | Out-Null; [IO.File]::WriteAllText("$ch\events.jsonl", '{}') }
    foreach ($item in @("$oldChannel\events.jsonl", "$oldChannel\inbox", $oldChannel)) { if (Test-Path -LiteralPath $item -PathType Leaf) { [IO.File]::SetLastWriteTime($item, (Get-Date).AddDays(-40)) } else { [IO.Directory]::SetLastWriteTime($item, (Get-Date).AddDays(-40)) } }
    Remove-OldMailboxFiles -LogFolder $logDir
    Assert-True (-not (Test-Path $oldLog) -and (Test-Path $freshLog)) 'Log files older than 30 days must be deleted and recent ones kept.'
    Assert-True (-not (Test-Path $oldChannel) -and (Test-Path $newChannel)) 'A channel folder unused for 30 days must be deleted and a recent one kept.'
    $noThrow = $true; try { Write-MailboxLog -Path 'Z:\no\such\drive\x.jsonl' -Entry ([ordered]@{ event = 'x' }) } catch { $noThrow = $false }
    Assert-True $noThrow 'A log that cannot be written must never stop a message.'
}
finally {
    foreach ($c in $children) { try { if (-not $c.HasExited) { $c.Kill() } } catch { } }
    Remove-Item Env:AGENTUI_MAILBOX_ROOT -ErrorAction SilentlyContinue
    Remove-Item Env:AGENTUI_LOG_DIR -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $logDir) { Remove-Item -LiteralPath $logDir -Recurse -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}
"PASS: $script:assertions assertions; mailbox privacy, liveness (stale, gone, reused id, corrupt), claim/ack, withdrawal, limits, retention, order, second listener, stop, damaged message and timeout against real listener processes, plus the troubleshooting log (hash not text, both sides, rotation, 30-day cleanup); no chat or UI."
