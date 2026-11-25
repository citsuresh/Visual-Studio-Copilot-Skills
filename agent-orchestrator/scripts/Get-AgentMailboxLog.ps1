<#
.SYNOPSIS
    Shows the mailbox troubleshooting log for a channel: sender and listener entries merged, oldest first.

.DESCRIPTION
    Reads the sender log (%LOCALAPPDATA%\AgentUi\logs\mailbox.jsonl) and the channel's listener log (events.jsonl in the
    channel folder under the temp folder). Entries hold lengths and short hashes, not message text (the sender log has
    text only if the message was sent with -LogText). A message can be followed across both logs by its hash.
    Logs are rotated at 512 KB and anything older than 30 days is deleted automatically.

.PARAMETER Channel
    Channel name, for example w240cca. Optional when -Hwnd is given.

.PARAMETER Hwnd
    Window handle; the channel name is derived from it.

.PARAMETER Last
    How many of the newest entries to show (default 40; 0 for all).

.PARAMETER SinceMinutes
    Only entries from the last N minutes.

.PARAMETER AsJson
    Return the entries as JSON instead of lines.

.EXAMPLE
    .\Get-AgentMailboxLog.ps1 -Hwnd 0x240CCA -SinceMinutes 30
#>
[CmdletBinding()]
param(
    [string]$Channel,

    [string]$Hwnd,

    [int]$Last = 40,

    [int]$SinceMinutes = 0,

    [switch]$AsJson
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'AgentMailbox.ps1')
if (-not $Channel) {
    if (-not $Hwnd) { throw 'Pass -Channel or -Hwnd.' }
    $Channel = Get-MailboxChannelName -Hwnd $Hwnd
}
$entries = @(Read-MailboxLog -Channel $Channel -Last $Last -SinceMinutes $SinceMinutes)
if ($AsJson) { $entries | ConvertTo-Json -Depth 5; return }
if ($entries.Count -eq 0) { "No log entries for channel $Channel."; return }
foreach ($e in $entries) {
    $rest = @($e.PSObject.Properties | Where-Object { $_.Name -notin 'ts', 'pid', 'event', 'channel', 'Side' } | ForEach-Object {
        $v = if ($_.Value -is [System.Array]) { ($_.Value -join ' | ') } else { [string]$_.Value }
        if ($v -ne '') { "$($_.Name)=$v" } })
    '{0}  {1,-8} {2,-12} {3}' -f $e.ts, $e.Side, $e.event, ($rest -join '  ')
}