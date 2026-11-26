param([string]$ScriptPath = (Join-Path $PSScriptRoot '..\..\agent-orchestrator\scripts\Send-ClaudePrompt.ps1'))
# Offline test of the Claude chat-box send sequence: every UI action is simulated, including the editor's asynchronous apply
# (a value set through UI Automation reads back as the OLD value for a while, measured live: exact by about 117 ms).
$ErrorActionPreference = 'Stop'
$ast = [Management.Automation.Language.Parser]::ParseFile((Resolve-Path $ScriptPath).Path, [ref]$null, [ref]$null)
$script:assertions = 0
function Assert-True([bool]$Condition, [string]$Message) { $script:assertions++; if (-not $Condition) { throw $Message } }
foreach ($name in @('Test-ClaudeDraft', 'Wait-ClaudeValue', 'Wait-ClaudeEmpty', 'Invoke-ClaudeSend')) {
    $fn = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    if (-not $fn) { throw "Missing function: $name" }
    . ([scriptblock]::Create($fn.Extent.Text))
}

# ---- a simulated chat box ----
$script:box = "`n"             # an empty box reads as one newline
$script:target = $null; $script:readsLeft = 0
$script:delayReads = 3         # reads that still show the old value after a SetValue
$script:neverApply = $false    # the editor ignores the set value
$script:neverEmpty = $false    # Send does not empty the box
$script:busy = $false; $script:hasSend = $true
$script:setCalls = New-Object System.Collections.ArrayList
$script:sent = New-Object System.Collections.ArrayList
function Reset-Box { $script:box = "`n"; $script:target = $null; $script:readsLeft = 0; $script:delayReads = 3; $script:neverApply = $false; $script:neverEmpty = $false; $script:busy = $false; $script:hasSend = $true; $script:setCalls.Clear(); $script:sent.Clear() }
$ui = @{
    IsBusy     = { $script:busy }
    ReadValue  = {
        if ($null -ne $script:target) {
            if ($script:readsLeft -le 0) { $script:box = $script:target; $script:target = $null } else { $script:readsLeft-- }
        }
        $script:box
    }
    SetValue   = { param($v) [void]$script:setCalls.Add([string]$v); if ($script:neverApply -and $v -ne '') { return }; $script:target = $(if ($v -eq '') { "`n" } else { [string]$v }); $script:readsLeft = $script:delayReads }
    FindSend   = { if ($script:hasSend -and ([string]$script:box).Trim().Length -gt 0) { 'SEND' } else { $null } }
    InvokeSend = { param($b) [void]$script:sent.Add([string]$script:box); if (-not $script:neverEmpty) { $script:target = "`n"; $script:readsLeft = $script:delayReads } }
}
function Invoke-Case { param([string]$Text = 'UIA-TEST: hello', [switch]$OverwriteInput, [switch]$NoSend) Invoke-ClaudeSend -Text $Text -Ui $ui -OverwriteInput:$OverwriteInput -NoSend:$NoSend -ReadBackTimeoutMs 400 -EmptyTimeoutMs 400 -PollMs 5 }

# Draft detection
Assert-True (-not (Test-ClaudeDraft "`n")) 'An empty box reads as one newline and is not a draft.'
Assert-True (-not (Test-ClaudeDraft "  `r`n ")) 'Whitespace only is not a draft.'
Assert-True (Test-ClaudeDraft "`nhello") 'Text after a newline is a draft.'
Assert-True (-not (Test-ClaudeDraft $null)) 'A null value is not a draft.'

# Normal send: the first reads still show the OLD value; the poll waits for the exact text, then Send, then the empty box
Reset-Box
$r = Invoke-Case
Assert-True ($r.Sent -and -not $r.Error) "A normal send must succeed: $($r.Error)"
Assert-True ($sent.Count -eq 1 -and $sent[0] -ceq 'UIA-TEST: hello') 'Send must be invoked once with the exact text in the box.'
Assert-True ($r.ReadBackMs -ge 0 -and $null -ne $r.EmptyMs -and ([string]$box).Trim() -eq '') 'The read-back and the empty box must be confirmed by polling.'
Assert-True ($setCalls.Count -eq 1) 'The text is set exactly once.'

# An immediate single read would have failed: with a delay of 3 reads the first read is the old value
Reset-Box; $script:delayReads = 3
& $ui.SetValue 'x'
$first = [string](& $ui.ReadValue)
Assert-True ($first -ceq "`n") 'The simulated editor must show the old value on the first read (the live behaviour).'

# Whitespace-only box is not a draft
Reset-Box; $script:box = "  `n"
$r = Invoke-Case
Assert-True ($r.Sent) 'A whitespace-only box must not block a send.'

# Draft present: refused, nothing typed
Reset-Box; $script:box = 'half-written thought'
$r = Invoke-Case
Assert-True (-not $r.Sent -and $r.Error -match '^DraftPresent' -and $setCalls.Count -eq 0 -and $sent.Count -eq 0) 'A draft must be refused before anything is typed.'
Assert-True ($script:box -ceq 'half-written thought') 'The draft must be left untouched.'
Assert-True ($r.Error -notmatch 'half-written') 'The error must not repeat the draft text.'

# -OverwriteInput replaces it
Reset-Box; $script:box = 'my own leftover'
$r = Invoke-Case -OverwriteInput
Assert-True ($r.Sent -and $sent[0] -ceq 'UIA-TEST: hello') '-OverwriteInput must replace leftover text.'

# Busy chat: refused
Reset-Box; $script:busy = $true
$r = Invoke-Case
Assert-True (-not $r.Sent -and $r.Error -match '^ClaudeBusy' -and $setCalls.Count -eq 0) 'A working chat (Stop present) must be refused before anything is typed.'

# Multi-line and empty text: refused
Reset-Box
$r = Invoke-Case -Text "line one`nline two"
Assert-True (-not $r.Sent -and $r.Error -match '^MultiLine' -and $setCalls.Count -eq 0) 'Multi-line text must be refused.'
$r = Invoke-Case -Text '   '
Assert-True (-not $r.Sent -and $r.Error -match '^EmptyText' -and $setCalls.Count -eq 0) 'Blank text must be refused.'

# Read-back never matches: cleared again, nothing sent
Reset-Box; $script:neverApply = $true
$r = Invoke-Case
Assert-True (-not $r.Sent -and $r.Error -match '^ReadBackMismatch' -and $sent.Count -eq 0) 'A value that never reads back exactly must not be sent.'
Assert-True ($r.Cleared -and $setCalls[-1] -ceq '') 'A mismatch must clear the box again.'

# The editor changes the text (for example a trimmed or altered copy): mismatch, not sent
Reset-Box
$ui2 = $ui.Clone(); $ui2.SetValue = { param($v) [void]$script:setCalls.Add([string]$v); $script:target = $(if ($v -eq '') { "`n" } else { ([string]$v) + ' ' }); $script:readsLeft = 1 }
$r = Invoke-ClaudeSend -Text 'exact?' -Ui $ui2 -ReadBackTimeoutMs 300 -EmptyTimeoutMs 300 -PollMs 5
Assert-True (-not $r.Sent -and $r.Error -match '^ReadBackMismatch' -and $sent.Count -eq 0) 'Text that differs by even one character must not be sent.'

# Send button missing: cleared, nothing sent
Reset-Box; $script:hasSend = $false
$r = Invoke-Case
Assert-True (-not $r.Sent -and $r.Error -match '^SendButtonMissing' -and $r.Cleared -and $sent.Count -eq 0) 'A missing Send button must clear the box and send nothing.'

# Send invoked but the box never empties: not claimed as sent
Reset-Box; $script:neverEmpty = $true
$r = Invoke-Case
Assert-True (-not $r.Sent -and $r.Error -match '^SendUnconfirmed' -and $sent.Count -eq 1) 'If the box does not empty after Send the result must not claim success.'

# Dry run: filled, read back, cleared, never sent
Reset-Box
$r = Invoke-Case -NoSend
Assert-True (-not $r.Sent -and -not $r.Error -and $r.Cleared -and $sent.Count -eq 0 -and $setCalls[0] -ceq 'UIA-TEST: hello' -and $setCalls[-1] -ceq '') '-NoSend must fill, read back and clear without invoking Send.'

# A reader that throws (element briefly stale) is retried until the timeout
Reset-Box
$script:reads = 0
$ui3 = $ui.Clone(); $ui3.ReadValue = { $script:reads++; if ($script:reads -eq 2 -or $script:reads -eq 3) { throw 'stale element' }; if ($null -ne $script:target) { if ($script:readsLeft -le 0) { $script:box = $script:target; $script:target = $null } else { $script:readsLeft-- } }; $script:box }
$r = Invoke-ClaudeSend -Text 'after stale' -Ui $ui3 -ReadBackTimeoutMs 500 -EmptyTimeoutMs 500 -PollMs 5
Assert-True ($r.Sent) 'A read that throws during the polling must be retried, not fail the send.'

# The very first read fails: the draft cannot be ruled out, so nothing is typed (a clean refusal, not an unhandled error)
Reset-Box
$ui4 = $ui.Clone(); $ui4.ReadValue = { throw 'element is gone' }
$r = Invoke-ClaudeSend -Text 'unreadable' -Ui $ui4 -ReadBackTimeoutMs 200 -EmptyTimeoutMs 200 -PollMs 5
Assert-True (-not $r.Sent -and $r.Error -match '^InputUnreadable' -and $setCalls.Count -eq 0) 'An unreadable box must refuse before typing anything.'

# A working chat that becomes idle while we wait: typed only after it is idle
Reset-Box
$script:busyPolls = 3
$ui5 = $ui.Clone(); $ui5.IsBusy = { if ($script:busyPolls -gt 0) { $script:busyPolls--; $true } else { $false } }
$r = Invoke-ClaudeSend -Text 'after idle' -Ui $ui5 -ReadBackTimeoutMs 400 -EmptyTimeoutMs 400 -PollMs 5 -WaitIdleMs 2000
Assert-True ($r.Sent -and $setCalls.Count -eq 1 -and $sent[0] -ceq 'after idle') 'A chat that becomes idle within the wait must then be sent to.'

# A chat that never becomes idle: refused after the wait, nothing typed; the message names the wait
Reset-Box; $script:busy = $true
$r = Invoke-ClaudeSend -Text 'never idle' -Ui $ui -ReadBackTimeoutMs 200 -EmptyTimeoutMs 200 -PollMs 5 -WaitIdleMs 200
Assert-True (-not $r.Sent -and $r.Error -match '^ClaudeBusy' -and $r.Error -match 'still working' -and $setCalls.Count -eq 0) 'A chat that stays busy must be refused after the wait without typing.'
# Without a wait the refusal is immediate and points at -WaitIdleSeconds
$r = Invoke-ClaudeSend -Text 'no wait' -Ui $ui -ReadBackTimeoutMs 200 -EmptyTimeoutMs 200 -PollMs 5
Assert-True ($r.Error -match 'WaitIdleSeconds' -and $setCalls.Count -eq 0) 'The immediate refusal must mention -WaitIdleSeconds.'

Write-Host "PASS: $script:assertions assertions; draft rule (empty box is one newline), polled read-back against the editor's asynchronous apply, busy/multi-line/empty refusals, mismatch clears and does not send, missing Send, unconfirmed Send, dry run, stale reads. UI simulated."
