param([string]$ScriptPath = (Join-Path $PSScriptRoot '..\..\agent-orchestrator\scripts\Read-ClaudeReply.ps1'))
# Offline test of reading a Claude worker's answer from its transcript file, with fixtures in the real record shape
# (one JSON object per line; type assistant; message.content[] items of type text, thinking or tool_use; other record types between).
$ErrorActionPreference = 'Stop'
$resolved = (Resolve-Path $ScriptPath).Path
$ast = [Management.Automation.Language.Parser]::ParseFile($resolved, [ref]$null, [ref]$null)
$script:assertions = 0
function Assert-True([bool]$Condition, [string]$Message) { $script:assertions++; if (-not $Condition) { throw $Message } }
foreach ($name in @('Get-ClaudeProjectSlug', 'ConvertTo-ClaudeUtc', 'Select-ClaudeReply', 'Read-ClaudeTail', 'ConvertFrom-ClaudeTranscriptText', 'Find-ClaudeSessionFile')) {
    $fn = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    if (-not $fn) { throw "Missing function: $name" }
    . ([scriptblock]::Create($fn.Extent.Text))
}

function New-Line([string]$Type, [string]$Stamp, $Content, [string]$Role = 'assistant') {
    $o = [ordered]@{ type = $Type; uuid = [guid]::NewGuid().ToString(); timestamp = $Stamp; sessionId = 'fixture' }
    if ($null -ne $Content) { $o.message = [ordered]@{ role = $Role; content = @($Content) } }
    ($o | ConvertTo-Json -Depth 8 -Compress)
}
$text = { param($t) [ordered]@{ type = 'text'; text = $t } }
$wait = [ordered]@{ type = 'tool_use'; id = 'toolu_1'; name = 'Bash'; input = [ordered]@{ command = 'Wait-AgentMailbox.ps1 -Channel w1' } }

$lines = @(
    '{"type":"bridge-session","sessionId":"fixture","lastSequenceNum":3}',
    (New-Line 'assistant' '2026-11-26T10:00:00.000Z' (& $text "From orchestrator: old task.`n`nReplying to orchestrator: old answer.`nOLD")),
    (New-Line 'user' '2026-11-26T10:00:05.000Z' 'Replying to orchestrator: a user line quoting the marker, must be ignored' 'user'),
    '{"type":"queue-operation","operation":"enqueue","timestamp":"2026-11-26T10:00:06.000Z"}',
    '{"type":"api-request-blob","timestamp":"2026-11-26T10:00:07.000Z","message":{"role":"user","content":[{"type":"text","text":"Replying to orchestrator: blob text, must be ignored"}]}}',
    (New-Line 'assistant' '2026-11-26T10:01:00.000Z' ([ordered]@{ type = 'thinking'; thinking = 'Replying to orchestrator: thought, must be ignored' })),
    (New-Line 'assistant' '2026-11-26T10:02:00.000Z' (& $text "From orchestrator: count root files.`n`nReplying to orchestrator: root file count.`n12")),
    (New-Line 'assistant' '2026-11-26T10:02:05.000Z' $wait)
)
$records = ConvertFrom-ClaudeTranscriptText -TailText ($lines -join "`n")
Assert-True ($records.Count -eq 8) "All eight fixture lines must parse, got $($records.Count)."

# The latest answer after the send time; the older answer, user lines, blobs and thoughts are never returned
$after = ConvertTo-ClaudeUtc '2026-11-26T10:01:30Z'
$r = Select-ClaudeReply -Records $records -AfterUtc $after
Assert-True ($r.Found -and $r.Text -ceq '12') "The answer after the marker line must be returned: [$($r.Text)]"
Assert-True ($r.Timestamp -eq [datetime]::Parse('2026-11-26T10:02:00Z').ToUniversalTime()) 'The answer timestamp must be returned.'

# The last record being a tool_use does not matter and does not mean "finished" either way
Assert-True ($records[-1].message.content[0].type -eq 'tool_use') 'Fixture check: the last record is a tool_use.'

# Nothing newer than the send time: not found (an answer to an EARLIER instruction is never returned)
$r = Select-ClaudeReply -Records $records -AfterUtc (ConvertTo-ClaudeUtc '2026-11-26T10:03:00Z')
Assert-True (-not $r.Found) 'An answer older than the send time must not be returned.'

# Without a time limit the latest answer still wins over the older one
$r = Select-ClaudeReply -Records $records -AfterUtc $null
Assert-True ($r.Found -and $r.Text -ceq '12') 'With no time limit the latest answer wins.'

# Ignored record kinds alone give no answer
$r = Select-ClaudeReply -Records @($records[2], $records[3], $records[4], $records[5]) -AfterUtc $null
Assert-True (-not $r.Found) 'User records, blobs and thinking blocks must never count as an answer.'

# Marker in the middle of a sentence is not an answer; one-line answer returns the rest of the marker line
$mid = ConvertFrom-ClaudeTranscriptText -TailText (New-Line 'assistant' '2026-11-26T11:00:00.000Z' (& $text 'I will be Replying to orchestrator: later'))
Assert-True (-not (Select-ClaudeReply -Records $mid -AfterUtc $null).Found) 'The marker in the middle of a sentence is not an answer.'
$one = ConvertFrom-ClaudeTranscriptText -TailText (New-Line 'assistant' '2026-11-26T11:00:00.000Z' (& $text 'Replying to orchestrator: done, 3 files'))
$r = Select-ClaudeReply -Records $one -AfterUtc $null
Assert-True ($r.Found -and $r.Text -ceq 'done, 3 files') "A one-line answer returns the text after the marker: [$($r.Text)]"

# Unix milliseconds and ISO times
Assert-True ((ConvertTo-ClaudeUtc '1795687290000') -eq [DateTimeOffset]::FromUnixTimeMilliseconds(1795687290000).UtcDateTime) 'Unix milliseconds must convert.'
Assert-True ($null -eq (ConvertTo-ClaudeUtc '')) 'Empty input gives no limit.'

# Slug rule
Assert-True ((Get-ClaudeProjectSlug 'C:\MyFiles\Git\Visual-Studio-Copilot-Skills') -ceq 'C--MyFiles-Git-Visual-Studio-Copilot-Skills') 'The project slug must match the real folder name.'
Assert-True ((Get-ClaudeProjectSlug 'C:\a b\c\') -ceq 'C--a-b-c') 'A trailing slash and spaces become dashes without a trailing dash.'

# Garbage lines are skipped
$mixed = @(ConvertFrom-ClaudeTranscriptText -TailText "not json`n{broken`n$($lines[1])`n`n")
Assert-True ($mixed.Count -eq 1) 'Unreadable lines must be skipped.'

# Files: tail reading, picking the file by channel, newest-file fallback
$dir = Join-Path $env:TEMP ('claude-reply-test-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory $dir | Out-Null
try {
    $enc = New-Object Text.UTF8Encoding($false)
    $a = Join-Path $dir 'aaaa.jsonl'; $b = Join-Path $dir 'bbbb.jsonl'; $c = Join-Path $dir 'cccc.jsonl'
    $mk = { param($p, $ls, $age) [IO.File]::WriteAllText($p, (($ls -join "`n") + "`n"), $enc); [IO.File]::SetLastWriteTimeUtc($p, [DateTime]::UtcNow.AddMinutes(-$age)) }
    & $mk $a $lines 30
    & $mk $b (@($lines) + (New-Line 'assistant' '2026-11-26T12:00:00.000Z' (& $text 'run Wait-AgentMailbox.ps1 -Channel wzz999 now'))) 20
    & $mk $c @('{"type":"bridge-session","sessionId":"c"}') 5
    Assert-True ((Find-ClaudeSessionFile -ProjectFolder $dir -Channel 'wzz999') -eq $b) 'The file whose end names the channel must be chosen over a newer file.'
    Assert-True ((Find-ClaudeSessionFile -ProjectFolder $dir -Channel 'nomatch') -eq $c) 'With no channel match the newest file is the fallback.'
    Assert-True ((Find-ClaudeSessionFile -ProjectFolder $dir) -eq $c) 'Without a channel the newest file is used.'
    Assert-True ($null -eq (Find-ClaudeSessionFile -ProjectFolder (New-Item -ItemType Directory (Join-Path $dir 'empty')).FullName)) 'A folder with no session files gives none.'
    # a small tail drops the partial first line and still parses the rest
    $big = Join-Path $dir 'big.jsonl'
    $fill = 1..400 | ForEach-Object { '{"type":"queue-operation","timestamp":"2026-11-26T09:00:00.000Z","pad":"' + ('x' * 200) + '"}' }
    & $mk $big (@($fill) + $lines[6]) 1
    $tailRecords = ConvertFrom-ClaudeTranscriptText -TailText (Read-ClaudeTail -Path $big -TailKB 16)
    Assert-True ($tailRecords.Count -gt 1 -and $tailRecords.Count -lt 401) 'A 16 KB tail must hold part of the file, with no broken first line.'
    Assert-True ((Select-ClaudeReply -Records $tailRecords -AfterUtc $null).Text -ceq '12') 'The answer at the end of a large file must be found from its tail.'
    # the whole script end to end: only the answer comes back, nothing else is printed
    $json = & powershell -NoProfile -File $resolved -SessionFile $b -AfterTimestamp '2026-11-26T10:01:30Z' -AsJson 2>&1 | Out-String
    $obj = ($json.Trim() | ConvertFrom-Json)
    Assert-True ($obj.Found -and $obj.Text -ceq '12' -and $obj.File -eq 'bbbb.jsonl') "The script must return the answer as JSON: $json"
    Assert-True ($json -notmatch 'old answer|blob text|thought' ) 'Nothing but the answer may be printed.'
    $none = & powershell -NoProfile -File $resolved -SessionFile $a -AfterTimestamp '2026-11-26T23:00:00Z' -AsJson 2>&1 | Out-String
    Assert-True (-not ($none.Trim() | ConvertFrom-Json).Found) 'The script must report no answer when none is newer.'
}
finally { [IO.Directory]::Delete($dir, $true) }

Write-Host "PASS: $script:assertions assertions; real record shapes (assistant text, thinking, tool_use, user, blobs, other types), answer after the marker line, send-time limit, ignored record kinds, mid-sentence marker, slug rule, tail reads, file choice by channel, end-to-end JSON."
