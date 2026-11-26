<#
.SYNOPSIS
    Reads a Claude worker's answer to a mailbox message from its Claude Code transcript file, and returns only that answer.

.DESCRIPTION
    A Claude desktop chat has no reader like Get-CopilotChatTranscript.ps1. The worker's text is in its transcript file
    ~\.claude\projects\<working folder, every character that is not a letter or digit replaced by ->\<session id>.jsonl:
    one JSON object per line; the text of an answer is in message.content[].text of records of type "assistant". Other record
    types sit between them, and the last line is often not a message, so "finished" is never read from the last line:
    this script returns a text whose line starts with the marker (default "Replying to orchestrator") and that is NEWER than
    -AfterTimestamp. If several match, the latest wins. The answer is the text after the marker line, or the rest of the
    marker line when nothing follows.

    The file holds full prompts and tool output. Only the matching answer is returned: nothing else is printed or logged,
    and only the end of the file is read (-TailKB). Pick the file with -SessionFile, or -Folder (a project folder or the
    working folder it belongs to) plus -Channel (the mailbox channel name, found in the file's tail; titles are not unique),
    falling back to the newest file by write time.

.PARAMETER SessionFile
    The .jsonl file to read.

.PARAMETER Folder
    A ~\.claude\projects\<slug> folder, or a working folder path (turned into its slug). Default: the slug of the current folder.

.PARAMETER Channel
    Mailbox channel name; the file whose end contains it is used (newest first). Without a match the newest file is used.

.PARAMETER AfterTimestamp
    Only answers newer than this: an ISO time (2026-11-26T15:52:57Z) or Unix milliseconds. Pass the time of your send.

.PARAMETER Pattern
    Regular expression for the marker at the start of a line. Default 'Replying to orchestrator'.

.PARAMETER TailKB
    How much of the end of the file is read (default 4096 KB).

.PARAMETER AsJson
    Print the result as JSON.
#>
[CmdletBinding()]
param(
    [string]$SessionFile,
    [string]$Folder,
    [string]$Channel,
    [string]$AfterTimestamp,
    [string]$Pattern = 'Replying to orchestrator',
    [ValidateRange(16, 262144)][int]$TailKB = 4096,
    [switch]$AsJson
)
$ErrorActionPreference = 'Stop'

# ---- pure logic (tested offline in scripts\agent\Test-ReadClaudeReply.ps1) ----

# The projects-folder name for a working folder: every character that is not a letter or digit becomes '-' (C:\a\b -> C--a-b).
function Get-ClaudeProjectSlug {
    param([string]$WorkingFolder)
    return ([string]$WorkingFolder.TrimEnd('\', '/') -replace '[^A-Za-z0-9]', '-')
}

# An ISO time or Unix milliseconds as a UTC DateTime; $null for empty input.
function ConvertTo-ClaudeUtc {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    $ms = 0L
    if ([int64]::TryParse($Value, [ref]$ms)) { return [DateTimeOffset]::FromUnixTimeMilliseconds($ms).UtcDateTime }
    return ([DateTimeOffset]::Parse($Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal)).UtcDateTime
}

# Records are the parsed JSON objects of the transcript lines. Returns Found, Text, Timestamp of the latest matching answer.
function Select-ClaudeReply {
    param([object[]]$Records, $AfterUtc, [string]$Pattern = 'Replying to orchestrator')
    $marker = "(?m)^[ \t]*$Pattern"
    $markerLine = "^[ \t]*$Pattern"
    $best = $null
    foreach ($record in $Records) {
        if ($null -eq $record -or [string]$record.type -ne 'assistant') { continue }
        if ($null -eq $record.message -or $null -eq $record.message.content) { continue }
        $stamp = $null
        if ($record.timestamp) { try { $stamp = ([DateTimeOffset]::Parse([string]$record.timestamp, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal)).UtcDateTime } catch { $stamp = $null } }
        if ($null -ne $AfterUtc) { if ($null -eq $stamp -or $stamp -le $AfterUtc) { continue } }
        foreach ($item in @($record.message.content)) {
            if ($item -is [string] -or [string]$item.type -ne 'text') { continue }
            $text = [string]$item.text
            if ($text -notmatch $marker) { continue }
            $best = [pscustomobject]@{ Text = $text; Timestamp = $stamp }
        }
    }
    if ($null -eq $best) { return [pscustomobject]@{ Found = $false; Text = $null; Timestamp = $null } }
    $lines = @($best.Text -split "`r?`n")
    $at = 0
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $markerLine) { $at = $i } }
    $body = ((@($lines | Select-Object -Skip ($at + 1)) -join "`n").Trim())
    if (-not $body) { $body = ($lines[$at] -replace "^[ \t]*$Pattern[:\s]*", '').Trim() }
    return [pscustomobject]@{ Found = $true; Text = $body; Timestamp = $best.Timestamp }
}

# The last -TailKB of a file as text; the partial first line of a tail read is dropped.
function Read-ClaudeTail {
    param([string]$Path, [int]$TailKB = 4096)
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        $want = [int64]$TailKB * 1024
        $start = [Math]::Max(0L, $stream.Length - $want)
        [void]$stream.Seek($start, [IO.SeekOrigin]::Begin)
        $buffer = New-Object byte[] ([int]($stream.Length - $start))
        $read = 0
        while ($read -lt $buffer.Length) { $n = $stream.Read($buffer, $read, $buffer.Length - $read); if ($n -le 0) { break }; $read += $n }
        $text = [Text.Encoding]::UTF8.GetString($buffer, 0, $read)
        if ($start -gt 0) { $cut = $text.IndexOf("`n"); if ($cut -ge 0) { $text = $text.Substring($cut + 1) } }
        return $text
    }
    finally { $stream.Dispose() }
}

# Parsed records of a tail text; unreadable lines are skipped.
function ConvertFrom-ClaudeTranscriptText {
    param([string]$TailText)
    $records = New-Object System.Collections.ArrayList
    foreach ($line in ($TailText -split "`n")) {
        $line = $line.Trim()
        if (-not $line.StartsWith('{')) { continue }
        try { [void]$records.Add(($line | ConvertFrom-Json)) } catch { }
    }
    return @($records)
}

# The session file to read: files newest first; the first whose end contains the channel name, else the newest.
function Find-ClaudeSessionFile {
    param([string]$ProjectFolder, [string]$Channel, [int]$TailKB = 1024)
    $files = @(Get-ChildItem -LiteralPath $ProjectFolder -Filter *.jsonl -File | Sort-Object LastWriteTimeUtc -Descending)
    if ($files.Count -eq 0) { return $null }
    if ($Channel) {
        foreach ($file in $files) {
            if ((Read-ClaudeTail -Path $file.FullName -TailKB $TailKB).Contains($Channel)) { return $file.FullName }
        }
    }
    return $files[0].FullName
}

# ---- main ----
if (-not $SessionFile) {
    if (-not $Folder) { $Folder = (Get-Location).Path }
    $projectFolder = $Folder
    if (-not (Test-Path -LiteralPath (Join-Path $Folder '*.jsonl'))) {
        $candidate = Join-Path (Join-Path $env:USERPROFILE '.claude\projects') (Get-ClaudeProjectSlug $Folder)
        if (Test-Path -LiteralPath $candidate) { $projectFolder = $candidate }
    }
    if (-not (Test-Path -LiteralPath $projectFolder)) { throw "No Claude project folder found for '$Folder'." }
    $SessionFile = Find-ClaudeSessionFile -ProjectFolder $projectFolder -Channel $Channel
    if (-not $SessionFile) { throw "No .jsonl session file in '$projectFolder'." }
}
$after = ConvertTo-ClaudeUtc $AfterTimestamp
$records = ConvertFrom-ClaudeTranscriptText -TailText (Read-ClaudeTail -Path $SessionFile -TailKB $TailKB)
$reply = Select-ClaudeReply -Records $records -AfterUtc $after -Pattern $Pattern
$out = [ordered]@{ Found = [bool]$reply.Found; Text = $reply.Text; Timestamp = $(if ($reply.Timestamp) { ([datetime]$reply.Timestamp).ToString('o') } else { $null }); File = (Split-Path -Leaf $SessionFile) }
if ($AsJson) { ([pscustomobject]$out) | ConvertTo-Json -Compress } else { [pscustomobject]$out }
