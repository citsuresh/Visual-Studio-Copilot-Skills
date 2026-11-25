<#
.SYNOPSIS
    Library for the opt-in mailbox between an orchestrator and a worker chat (dot-source it; it runs nothing).

.DESCRIPTION
    A mailbox is a private folder per channel. The orchestrator posts a message as a file; a worker chat that is
    running Wait-AgentMailbox.ps1 claims it within about 0.2 s. A message can only reach a chat that is already
    listening: the mailbox never wakes an idle chat, and Send-AgentMessage.ps1 uses the UI sender for that.

    Folder (default <temp folder>\AgentUi\mailbox\<channel>, AGENTUI_MAILBOX_ROOT overrides the root):
      listener.json   who is listening: process id and start time, a heartbeat updated about once a second
      inbox\          *.msg files, written under another name and renamed, so a half-written file is never read
      claimed\        a message while the listener reads it (deleted at once)
      acks\           one small file per claimed message: id and time, so the sender knows it was taken

    Limits and privacy: the folder is private to the current user (inheritance removed); a message is at most 8000
    characters; the inbox holds at most 20 messages; messages and acks older than 10 minutes are deleted; a claimed
    message is deleted after it is printed. Nothing is archived, so no chat text stays on disk after delivery.
    A listener counts as alive only while its heartbeat is under 3 s old AND its process exists with the recorded
    start time, so a dead or hung listener is not mistaken for a live one.
#>

$script:MailboxMaxChars = 8000
$script:MailboxMaxInbox = 20
$script:MailboxMaxAgeSeconds = 600
$script:MailboxBeatMaxAgeMs = 3000

function Get-MailboxNowMs { return [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() }

function Get-MailboxRoot {
    if ($env:AGENTUI_MAILBOX_ROOT) { return $env:AGENTUI_MAILBOX_ROOT }
    # Under the temp folder, not %LOCALAPPDATA%: a worker chat's terminal sees files that other processes put in the temp folder,
    # but in a live test it saw an empty folder where this one had put messages under %LOCALAPPDATA%\AgentUi.
    return (Join-Path ([System.IO.Path]::GetTempPath()) 'AgentUi\mailbox')
}

# 'w' plus the window handle's hex digits, for example 0x240CCA gives w240cca.
function Get-MailboxChannelName {
    param([Parameter(Mandatory)][string]$Hwnd)
    $value = [Convert]::ToInt64($Hwnd, 16)
    return ('w{0:x}' -f $value)
}

function Test-MailboxChannelName {
    param([string]$Channel)
    return [bool]($Channel -cmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,39}$')
}

function Get-MailboxPaths {
    param([Parameter(Mandatory)][string]$Channel)
    if (-not (Test-MailboxChannelName $Channel)) { throw "Invalid channel name '$Channel' (letters, digits, - and _ only; at most 40 characters)." }
    $dir = Join-Path (Get-MailboxRoot) $Channel
    return [pscustomobject]@{
        Channel = $Channel; Dir = $dir
        Inbox = (Join-Path $dir 'inbox'); Claimed = (Join-Path $dir 'claimed'); Acks = (Join-Path $dir 'acks')
        Listener = (Join-Path $dir 'listener.json')
    }
}

# Only the current user (and the system) may read or change the folder.
function Set-MailboxPrivateAcl {
    param([Parameter(Mandatory)][string]$Path)
    $acl = New-Object System.Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    $inherit = [System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
    $none = [System.Security.AccessControl.PropagationFlags]::None
    $allow = [System.Security.AccessControl.AccessControlType]::Allow
    $full = [System.Security.AccessControl.FileSystemRights]::FullControl
    $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $system = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::LocalSystemSid, $null)
    foreach ($sid in @($me, $system)) { $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($sid, $full, $inherit, $none, $allow))) }
    [System.IO.Directory]::SetAccessControl($Path, $acl)
}

function Initialize-Mailbox {
    param([Parameter(Mandatory)][string]$Channel)
    $paths = Get-MailboxPaths -Channel $Channel
    $root = Get-MailboxRoot
    if (-not (Test-Path -LiteralPath $root)) { [void](New-Item -ItemType Directory -Path $root -Force) }
    if (-not (Test-Path -LiteralPath $paths.Dir)) {
        [void](New-Item -ItemType Directory -Path $paths.Dir -Force)
        Set-MailboxPrivateAcl -Path $paths.Dir
    }
    foreach ($sub in @($paths.Inbox, $paths.Claimed, $paths.Acks)) { if (-not (Test-Path -LiteralPath $sub)) { [void](New-Item -ItemType Directory -Path $sub -Force) } }
    return $paths
}

# Deletes messages, claimed leftovers and acks that nobody collected within the retention time.
function Remove-ExpiredMailboxFiles {
    param([Parameter(Mandatory)]$Paths, [int]$MaxAgeSeconds = $script:MailboxMaxAgeSeconds)
    $cutoff = (Get-Date).AddSeconds(-$MaxAgeSeconds)
    foreach ($folder in @($Paths.Inbox, $Paths.Claimed, $Paths.Acks)) {
        if (-not (Test-Path -LiteralPath $folder)) { continue }
        foreach ($file in [System.IO.Directory]::GetFiles($folder)) {
            try { if ([System.IO.File]::GetLastWriteTime($file) -lt $cutoff) { [System.IO.File]::Delete($file) } } catch { }
        }
    }
}

function Read-MailboxJsonFile {
    param([string]$Path)
    for ($try = 0; $try -lt 4; $try++) {
        try {
            if (-not (Test-Path -LiteralPath $Path)) { return $null }
            return ([System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json)
        }
        catch { Start-Sleep -Milliseconds 40 }
    }
    return $null
}

function Write-MailboxJsonFile {
    param([string]$Path, $Value)
    $json = $Value | ConvertTo-Json -Compress -Depth 4
    [System.IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding($false)))
}

# Is a worker chat listening on this channel right now? Registered means a listener file exists (even a stale one);
# Live means it is also fresh and its process is the recorded one.
function Get-MailboxState {
    param([Parameter(Mandatory)][string]$Channel)
    $paths = Get-MailboxPaths -Channel $Channel
    $state = [pscustomobject]@{ Registered = $false; Live = $false; Reason = 'NoListener'; ListenerPid = 0; BeatAgeMs = $null; LastExitReason = $null; LastExitAgeMs = $null }
    $exit = Read-MailboxJsonFile -Path (Join-Path $paths.Dir 'exit.json')
    if ($exit) { $state.LastExitReason = [string]$exit.reason; $state.LastExitAgeMs = (Get-MailboxNowMs) - [int64]$exit.atMs }
    $info = Read-MailboxJsonFile -Path $paths.Listener
    if ($null -eq $info) { return $state }
    $state.Registered = $true
    $state.ListenerPid = [int]$info.pid
    $age = (Get-MailboxNowMs) - [int64]$info.lastBeatMs
    $state.BeatAgeMs = $age
    if ($age -gt $script:MailboxBeatMaxAgeMs) { $state.Reason = 'HeartbeatStale'; return $state }
    try {
        $proc = Get-Process -Id ([int]$info.pid) -ErrorAction Stop
        $started = ([DateTimeOffset]$proc.StartTime.ToUniversalTime()).ToUnixTimeMilliseconds()
        if ([Math]::Abs($started - [int64]$info.procStartMs) -gt 2000) { $state.Reason = 'ProcessReplaced'; return $state }
    }
    catch { $state.Reason = 'ProcessGone'; return $state }
    $state.Live = $true
    $state.Reason = 'Listening'
    return $state
}

# Records why the last listener ended (message, timeout, stop or error), so a sender can tell a worker that is busy with
# the message it just took (it will listen again) from one that was never listening or was told to stop.
function Set-MailboxExit {
    param([Parameter(Mandatory)]$Paths, [Parameter(Mandatory)][string]$Reason)
    try { Write-MailboxJsonFile -Path (Join-Path $Paths.Dir 'exit.json') -Value ([ordered]@{ reason = $Reason; atMs = (Get-MailboxNowMs) }) } catch { }
}

# Posts a message and waits for the listener to claim it. Delivered is true only when the listener took it.
# When nobody takes it in time the message is withdrawn (so it can never arrive later, after a UI send), unless the
# listener claimed it at that very moment, which counts as delivered.
function Send-AgentMailboxMessage {
    param(
        [Parameter(Mandatory)][string]$Channel,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [string]$From = 'orchestrator',
        [ValidateSet('message', 'stop')][string]$Kind = 'message',
        [int]$AckTimeoutMs = 5000
    )
    $result = [pscustomobject]@{ Delivered = $false; Id = $null; AckMs = $null; Reason = $null }
    if ($Text.Length -gt $script:MailboxMaxChars) { $result.Reason = "TooLong: the message is $($Text.Length) characters; the limit is $script:MailboxMaxChars."; return $result }
    if ([string]::IsNullOrEmpty($Text) -and $Kind -eq 'message') { $result.Reason = 'Empty: nothing to send.'; return $result }
    $state = Get-MailboxState -Channel $Channel
    if (-not $state.Live) { $result.Reason = "NoLiveListener: $($state.Reason)"; return $result }
    $paths = Initialize-Mailbox -Channel $Channel
    Remove-ExpiredMailboxFiles -Paths $paths
    if (@([System.IO.Directory]::GetFiles($paths.Inbox, '*.msg')).Count -ge $script:MailboxMaxInbox) { $result.Reason = 'InboxFull'; return $result }
    $id = [guid]::NewGuid().ToString('N').Substring(0, 12)
    $name = '{0:D15}-{1}' -f (Get-MailboxNowMs), $id
    $final = Join-Path $paths.Inbox "$name.msg"
    $temp = Join-Path $paths.Inbox "$name.tmp"
    $started = [Diagnostics.Stopwatch]::StartNew()
    Write-MailboxJsonFile -Path $temp -Value ([ordered]@{ id = $id; kind = $Kind; from = $From; createdMs = (Get-MailboxNowMs); text = $Text })
    [System.IO.File]::Move($temp, $final)
    $result.Id = $id
    $ackFile = Join-Path $paths.Acks "$id.json"
    while ($started.ElapsedMilliseconds -lt $AckTimeoutMs -and -not (Test-Path -LiteralPath $ackFile)) { Start-Sleep -Milliseconds 25 }
    if (-not (Test-Path -LiteralPath $ackFile)) {
        # Withdraw it. If the delete fails the listener has just claimed it, so wait briefly for the ack.
        $withdrawn = $false
        # Delete does not fail for a missing file, so look first: a file that is already gone was claimed.
        if (Test-Path -LiteralPath $final) { try { [System.IO.File]::Delete($final); $withdrawn = -not (Test-Path -LiteralPath $final) } catch { } }
        if ($withdrawn) { $result.Reason = 'NotClaimed: the listener did not take the message in time; it was withdrawn.'; return $result }
        $grace = [Diagnostics.Stopwatch]::StartNew()
        while ($grace.ElapsedMilliseconds -lt 1500 -and -not (Test-Path -LiteralPath $ackFile)) { Start-Sleep -Milliseconds 25 }
        if (-not (Test-Path -LiteralPath $ackFile)) { $result.Reason = 'Unconfirmed: the message left the inbox but no ack arrived.'; return $result }
    }
    $result.AckMs = [int]$started.ElapsedMilliseconds
    try { [System.IO.File]::Delete($ackFile) } catch { }
    $result.Delivered = $true
    $result.Reason = 'Delivered'
    return $result
}
