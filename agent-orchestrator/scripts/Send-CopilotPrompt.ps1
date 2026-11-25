<#
.SYNOPSIS
    Sends a prompt to a VS Copilot Chat window, and only clicks Send after the pasted text is
    verified to match exactly.

.DESCRIPTION
    Optionally starts a new chat session, clears the chat input, pastes the prompt, and reads
    it back. If the input contains anything other than the exact prompt (for example stray
    keystrokes typed into the window during the paste), it clears and retries. If it still
    does not match after -Retries attempts, it does NOT send and returns Sent=false.
    Native arguments preserve double quotes and backslashes on Windows PowerShell 5.1.
    A separate ValuePattern/TextPattern read confirms the input; unsupported or ambiguous
    input reads fail without clicking Send.
    Existing drafts, including whitespace-only text, are refused by default before input changes.
    Pass -OverwriteInput only when replacing the draft is intentional.
    Draft refusal Error includes UTF-16 length, code-point count and up to 32 distinct character
    codes with occurrence counts, never draft text. ValuePattern takes precedence over TextPattern;
    neither read is normalized. These diagnostics do not establish the cause of a refusal.
    The window of the Visual Studio process hosting this script (a parent process) is refused by
    default, so an agent cannot type into its own chat; -AllowOwnHost overrides that. Windows of
    other processes, including other main or Insiders Visual Studio instances, are not affected.
    -Steer redirects an existing busy chat instead of sending a new turn. It preserves the same
    draft guards and exact read-back, checks busy before typing, and invokes only SteerButton
    after verification. It never clicks Stop or falls back to Send. Steer availability/click
    failures contain no draft text.

.PARAMETER Hwnd
    Target window handle, e.g. "0x60AAA". Optional when -TitleContains is given. A handle goes
    stale when Visual Studio is restarted; use -TitleContains to look it up each time.

.PARAMETER TitleContains
    Resolve the target window by title substring (list-windows --all --titleContains) instead
    of passing a handle. Fails with Sent=false when no window matches, and lists the candidates
    when more than one matches. Ignored when -Hwnd is also given. Declared last so the
    positional order of the other parameters is unchanged.

.PARAMETER Text
    Prompt text. Must be a single line; the CLI rejects embedded newlines.

.PARAMETER NewSession
    Click "Create new session" (AutomationId createNewThread) before pasting. A new session can
    take longer than 10 seconds to show its input; the script waits up to 30.

.PARAMETER Retries
    Extra clear-and-paste attempts after a verification mismatch. Default 2.

.PARAMETER NoSend
    Paste and verify only; do not click Send or Steer. Useful for testing.

.PARAMETER IgnoreBanners
    Send even if the chat shows a HarnessWorkspaceMismatchBanner ("The open folder is outside
    this session's working directory") or WorkspaceTrustWarningBanner. By default the script
    refuses and returns Sent=false, because the agent would run in the wrong folder.

.PARAMETER InputName
    UIA Name of the chat input. Default "Ask Copilot".

.PARAMETER ExePath
    Path to agentdebug-ui.exe.

.PARAMETER NoNavigate
    Do not look for the chat. By default, when the chat input is not showing, the script first
    selects the "Chat" tab (it can sit behind a sibling tab such as Git Changes in the same pane)
    and, if the pane then shows only the session list, creates a new session. Pass this to
    require the chat to be open already.

.PARAMETER Quiet
    On success, return InputText as $null instead of echoing the whole prompt back. Failures
    still return the text that was read from the input, since it explains the failure.

.PARAMETER OverwriteInput
    Permit clearing an existing draft. Without this switch a non-empty input is preserved,
    including when -NewSession is requested. Declared last to preserve positional parameters.

.PARAMETER AllowOwnHost
    Permit a target window owned by this script's own process or one of its parent processes (the
    Visual Studio hosting the calling chat). Without it the send is refused before any input is read
    or changed. Also skips the check when the window list or process chain cannot be read.

.PARAMETER Steer
    Redirect the currently visible busy chat using SteerButton (Name Steer, Button, InvokePattern).
    Requires an enabled, visible input-area Stop or Steer button and no visible SendButton before
    typing; requires enabled, visible SteerButton after exact read-back. Refuses -NewSession and
    does not navigate or create a chat. Action buttons must be direct children of the Chat pane
    (siblings of WpfTextViewHost), never input-host/message-list descendants. CancelButton may
    have UIA Name Cancel. A missing/disabled button or lost busy state fails closed
    with Sent=false and a text-free Error; verified unsent text is left as a protected draft.
    Appended to preserve all prior positional parameter indices.

.PARAMETER Trace
    Diagnostics only. Adds a Timings property to the result: milliseconds spent in each stage
    (resolve, ownHost, draft1, foreground, tabCheck, banner, ensureInput, screenCheck, draft2, and per
    attempt loopForeground, clear, paste, readback; then send) and totalMs. Contains no chat or
    draft text. Without -Trace the result has no Timings property and behaviour is unchanged.
    Appended last to preserve all prior positional parameter indices.

.PARAMETER QuietSeconds
    How long the keyboard and mouse must have been idle before the script takes the foreground (default 3;
    twice as long while the foreground application's focused editor holds text). A held mouse button or
    modifier key, a presentation or full-screen app, Windows quiet time and a manual pause
    (Set-AgentUiPause in AgentCursor.ps1) also make it wait. 0 turns the quiet wait off. While it waits the
    cursor shows an amber dot and one short sound plays. Appended last to preserve positional order.

.PARAMETER MaxWaitSeconds
    How long to wait for a quiet moment (default 120) before returning Sent=false with UserActive or
    DoNotDisturb and typing nothing. After about 30 s the person is asked once to pause (sound, or speech
    with -SpeakRequest).

.PARAMETER IgnoreUserActivity
    Skip the quiet wait and the checks for input during the send. For runs where nobody is at the machine.
    The cross-process lock and the focus hand-back still apply.

.PARAMETER NoRestoreFocus
    Do not give the person's window, focused control and pointer back after the send.

.PARAMETER SpeakRequest
    Speak the request to pause (read-aloud skill) instead of repeating the sound. Pass it only when speech is
    on in this chat.

.OUTPUTS
    PSCustomObject (or JSON with -AsJson): Sent, Attempts, InputText, Error (plus Timings with
    -Trace, and Handback after a send that borrowed the keyboard: Restored, UserInput, NotVerified and so on).
    When the window
    cannot be brought to the foreground and it no longer exists, Error says so (typically
    Visual Studio was restarted and the handle is stale). When the window exists but still
    cannot be brought forward after one retry, Error tells the person to click the target
    window and run the script again; the script does not loop.

.EXAMPLE
    .\Send-CopilotPrompt.ps1 -Hwnd 0x60AAA -NewSession -Text 'Run Bootstrap.'

.EXAMPLE
    .\Send-CopilotPrompt.ps1 -TitleContains 'AgentDebugToolkit - ' -Quiet -AsJson -Text 'Continue.'
#>
[CmdletBinding()]
param(
    [string]$Hwnd,

    [Parameter(Mandatory = $true)]
    [string]$Text,

    [switch]$NewSession,

    [ValidateRange(0, 10)]
    [int]$Retries = 2,

    [switch]$NoSend,

    [switch]$IgnoreBanners,

    [string]$InputName = 'Ask Copilot',

    [string]$ExePath = "$env:USERPROFILE\.copilot\toolkits\AgentDebugToolkit\src\AgentDebugToolkit.UiAutomation.Cli\bin\Debug\net8.0-windows\agentdebug-ui.exe",

    [switch]$AsJson,

    [switch]$Quiet,

    [string]$TitleContains,

    [switch]$NoNavigate,

    [switch]$OverwriteInput,

    [switch]$AllowOwnHost,

    [switch]$Steer,

    [switch]$Trace,

    [ValidateRange(0, 600)]
    [int]$QuietSeconds = 3,

    [ValidateRange(0, 3600)]
    [int]$MaxWaitSeconds = 120,

    [switch]$IgnoreUserActivity,

    [switch]$NoRestoreFocus,

    [switch]$SpeakRequest
)

$ErrorActionPreference = 'Stop'
# The inherited DOTNET_ROOT from VS breaks agentdebug-ui.exe; always clear it.
Remove-Item Env:DOTNET_ROOT -ErrorAction SilentlyContinue

if (-not (Test-Path $ExePath)) {
    throw "agentdebug-ui.exe not found at '$ExePath'. Pass -ExePath explicitly."
}
if ($Text -match "[`r`n]") {
    throw "-Text must be a single line; the chat CLI rejects embedded newlines."
}
if (-not $Hwnd -and -not $TitleContains) {
    throw "Pass -Hwnd or -TitleContains."
}

function ConvertTo-NativeArgument {
    param([string]$Argument)
    $escaped = [regex]::Replace($Argument, '(\\*)"', '$1$1\"')
    return '"' + [regex]::Replace($escaped, '(\\+)$', '$1$1') + '"'
}

function Invoke-Ui {
    param([string[]]$Arguments)
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo.FileName = $ExePath
    $process.StartInfo.Arguments = (@($Arguments | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' ')
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.CreateNoWindow = $true
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    $process.StartInfo.StandardOutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $process.StartInfo.StandardErrorEncoding = New-Object System.Text.UTF8Encoding($false)
    try {
        if (-not $process.Start()) { throw 'Could not start the UI executable.' }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $raw = ($stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()).Trim()
    }
    finally { $process.Dispose() }
    try { return $raw | ConvertFrom-Json } catch { return [pscustomobject]@{ success = $false; error = 'unparseable-output'; message = $raw } }
}

function Get-ChatInputElements {
    Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
    $window = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr][Convert]::ToInt64($Hwnd, 16))
    $condition = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::NameProperty, $InputName)
    return @($window.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condition))
}

# The two banners that make a send go to the wrong folder; found by AutomationId anywhere in the window.
function Get-ChatBannerElements {
    Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
    $window = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr][Convert]::ToInt64($Hwnd, 16))
    $ids = New-Object System.Windows.Automation.OrCondition(
        (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, 'HarnessWorkspaceMismatchBanner')),
        (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, 'WorkspaceTrustWarningBanner')))
    return @($window.FindAll([System.Windows.Automation.TreeScope]::Descendants, $ids))
}

function Get-ChatBannerIds {
    return @(Get-ChatBannerElements | ForEach-Object { $_.Current.AutomationId } | Select-Object -Unique)
}

# Visible areas as this process sees them: monitor working areas, so the taskbar band is excluded. UIA
# rectangles read in the same process use the same coordinate space, so the two can be compared directly.
function Get-ChatScreenAreas {
    Add-Type -AssemblyName System.Windows.Forms
    return @([System.Windows.Forms.Screen]::AllScreens | ForEach-Object { $_.WorkingArea })
}

# Fast refusal when the chat input is outside the visible screen. Windows reports IsOffscreen false for a
# partly off-screen window, and the input verbs then fail only with a generic foreground error after several
# retries (about 15 s). The input's centre must lie in a monitor working area. This is a convenience check,
# not a safety guard: if the geometry cannot be read it returns $null and the send proceeds as before.
function Get-ChatInputScreenError {
    param([object[]]$Elements)
    try {
        $inputs = @(if ($PSBoundParameters.ContainsKey('Elements')) { $Elements } else { Get-ChatInputElements })
        if ($inputs.Count -ne 1) { return $null }
        $rect = $inputs[0].Current.BoundingRectangle
        $areas = @(Get-ChatScreenAreas)
        if ($areas.Count -eq 0) { return $null }
        $where = (@($areas | ForEach-Object { '{0},{1} {2}x{3}' -f $_.Left, $_.Top, ($_.Right - $_.Left), ($_.Bottom - $_.Top) }) -join '; ')
        $advice = 'Nothing was typed or clicked. Move the Visual Studio window so the chat input is on screen, then run this again.'
        if ($rect.IsEmpty -or $rect.Width -le 0 -or $rect.Height -le 0) {
            return "InputOffScreen: the chat input has no visible rectangle (visible areas: $where). $advice"
        }
        $x = $rect.X + $rect.Width / 2
        $y = $rect.Y + $rect.Height / 2
        foreach ($area in $areas) {
            if ($x -ge $area.Left -and $x -lt $area.Right -and $y -ge $area.Top -and $y -lt $area.Bottom) { return $null }
        }
        return ('InputOffScreen: the chat input centre ({0},{1}) is outside the visible screen area (visible areas: {2}). {3}' -f [int]$x, [int]$y, $where, $advice)
    }
    catch { return $null }
}

function Get-ChatInputText {
    # -Elements lets a caller that has just searched for the input reuse that result instead of
    # searching the whole window a second time; without it the input is searched for as before.
    param([object[]]$Elements)
    $inputs = @(if ($PSBoundParameters.ContainsKey('Elements')) { $Elements } else { Get-ChatInputElements })
    if ($inputs.Count -ne 1) { throw 'Chat input is missing or ambiguous; text was not verified and Send was not clicked.' }
    $pattern = $null
    if ($inputs[0].TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$pattern)) {
        $text = $pattern.Current.Value
    }
    elseif ($inputs[0].TryGetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern, [ref]$pattern)) {
        $text = $pattern.DocumentRange.GetText(-1)
    }
    else { throw 'Chat input exposes neither ValuePattern nor TextPattern; text was not verified and Send was not clicked.' }
    if ($null -eq $text) { throw 'Chat input returned null text; Send was not clicked.' }
    return $text
}

function Get-ChatDraftError {
    param([switch]$AllowMissing, [object[]]$Elements)
    $inputs = @(if ($PSBoundParameters.ContainsKey('Elements')) { $Elements } else { Get-ChatInputElements })
    if ($inputs.Count -eq 0 -and $AllowMissing) { return $null }
    if ($inputs.Count -ne 1) { return 'Chat input is missing or ambiguous; no input was changed.' }
    $draft = Get-ChatInputText -Elements $inputs
    if ($draft.Length -gt 0) {
        $counts = @{}
        $codePointCount = 0
        for ($i = 0; $i -lt $draft.Length; $i++) {
            $code = [int]$draft[$i]
            if ([char]::IsHighSurrogate($draft[$i]) -and $i + 1 -lt $draft.Length -and [char]::IsLowSurrogate($draft[$i + 1])) {
                $code = [char]::ConvertToUtf32($draft[$i], $draft[$i + 1])
                $i++
            }
            $counts[$code] = 1 + $counts[$code]
            $codePointCount++
        }
        $codes = (@($counts.Keys | Sort-Object | Select-Object -First 32 | ForEach-Object {
            'U+{0:X4}({1})' -f $_, $counts[$_]
        }) -join ',')
        return "InputNotEmpty: the chat input holds a draft. DraftLength=$($draft.Length); CodePointCount=$codePointCount; DistinctCodes=$($counts.Count); Codes=$codes. Nothing was typed; use -OverwriteInput to replace it."
    }
    return $null
}

function Get-ChatActionButtons {
    $inputs = @(Get-ChatInputElements)
    if ($inputs.Count -ne 1) { return @() }
    $node = $inputs[0]
    $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    for ($depth = 0; $depth -lt 32; $depth++) {
        $parent = $walker.GetParent($node)
        if ($null -eq $parent) { break }
        if ($parent.Current.ClassName -eq 'GenericPane' -and $parent.Current.Name -eq 'Chat') {
            if ($node.Current.ClassName -eq 'ChatSessionList' -or $node.Current.AutomationId -eq 'session') { return @() }
            $ids = New-Object System.Windows.Automation.OrCondition(
                (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, 'CancelButton')),
                (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, 'SteerButton')),
                (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, 'SendButton')))
            $condition = New-Object System.Windows.Automation.AndCondition($ids,
                (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)))
            return @($parent.FindAll([System.Windows.Automation.TreeScope]::Children, $condition))
        }
        $node = $parent
    }
    return @()
}

function Get-ChatSteerError {
    param([switch]$RequireButton)
    $buttons = @(Get-ChatActionButtons)
    $visible = @($buttons | Where-Object { -not $_.Current.IsOffscreen })
    $send = @($visible | Where-Object { $_.Current.AutomationId -eq 'SendButton' })
    $steerButtons = @($visible | Where-Object { $_.Current.AutomationId -eq 'SteerButton' })
    $busy = @($visible | Where-Object {
        $_.Current.IsEnabled -and (
            $_.Current.AutomationId -eq 'CancelButton' -or
            ($_.Current.AutomationId -eq 'SteerButton' -and $_.Current.Name -eq 'Steer'))
    })
    if ($RequireButton) {
        if ($send.Count -gt 0 -or $busy.Count -ne 1 -or $steerButtons.Count -ne 1 -or -not $steerButtons[0].Current.IsEnabled -or $steerButtons[0].Current.Name -ne 'Steer') {
            return 'SteerUnavailable: no unique enabled input-area SteerButton in a busy chat; nothing was clicked.'
        }
        $pattern = $null
        if (-not $steerButtons[0].TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$pattern)) {
            return 'SteerUnavailable: SteerButton lacks InvokePattern; nothing was clicked.'
        }
    }
    elseif ($send.Count -gt 0 -or $busy.Count -ne 1) {
        return 'SteerRequiresBusy: the visible input area does not confirm a busy chat; nothing was typed or clicked.'
    }
    return $null
}

# This process and its ancestors; a parent that started after its child is a recycled PID, so the walk stops.
# One process snapshot is read once and walked in memory (a lookup per ancestor cost about 350 ms each).
function Get-CallerProcessIds {
    $ids = New-Object 'System.Collections.Generic.List[int]'
    $byId = @{}
    foreach ($process in @(Get-CimInstance Win32_Process -Property ProcessId, ParentProcessId, CreationDate -ErrorAction Stop)) { $byId[[int]$process.ProcessId] = $process }
    $current = $byId[[int]$PID]
    if (-not $current) { throw "Process $PID was not found." }
    $ids.Add([int]$current.ProcessId)
    for ($depth = 0; $depth -lt 32 -and $current.ParentProcessId; $depth++) {
        $parent = $byId[[int]$current.ParentProcessId]
        if (-not $parent -or $parent.CreationDate -gt $current.CreationDate -or $ids.Contains([int]$parent.ProcessId)) { break }
        $ids.Add([int]$parent.ProcessId)
        $current = $parent
    }
    return $ids.ToArray()
}

# Fails closed: an unreadable window list or process chain refuses instead of guessing.
function Get-OwnHostError {
    $windows = Get-TopLevelWindows
    if ($null -eq $windows) {
        return "OwnHostCheckFailed: could not list windows to check the target's process ($script:ListWindowsError). Nothing was typed; use -AllowOwnHost to skip the check."
    }
    $wanted = [Convert]::ToInt64($Hwnd, 16)
    $target = @($windows | Where-Object { [Convert]::ToInt64($_.Hwnd, 16) -eq $wanted })
    if ($target.Count -ne 1) {
        return "Window $Hwnd no longer exists (the app may have been restarted, so the handle is stale). Look it up again, or pass -TitleContains. Nothing was typed."
    }
    try { $callerIds = @(Get-CallerProcessIds) }
    catch { return "OwnHostCheckFailed: could not read this script's process chain ($($_.Exception.Message)). Nothing was typed; use -AllowOwnHost to skip the check." }
    if ($callerIds -contains [int]$target[0].Pid) {
        return "OwnHostWindow: window $Hwnd belongs to process $($target[0].Pid), which hosts this script, so it would type into the calling chat itself. Nothing was typed; target another Visual Studio window, or pass -AllowOwnHost if that is intended."
    }
    return $null
}

function Write-Result {
    param([bool]$Sent, [int]$Attempts, [string]$InputText, [string]$ErrorText)
    if ($Quiet -and $Sent) { $InputText = $null }
    $result = [pscustomobject]@{ Sent = $Sent; Attempts = $Attempts; InputText = $InputText; Error = $ErrorText }
    # Present only after an input block gave the person's window back (see Stop-InputBlock).
    $handback = Get-Variable -Name FocusResult -Scope Script -ValueOnly -ErrorAction SilentlyContinue
    if ($handback) { Add-Member -InputObject $result -NotePropertyName Handback -NotePropertyValue $handback }
    # -Trace only: the variables exist only when the script body enabled tracing.
    $stages = Get-Variable -Name SendStages -Scope Script -ValueOnly -ErrorAction SilentlyContinue
    $clock = Get-Variable -Name SendClock -Scope Script -ValueOnly -ErrorAction SilentlyContinue
    if ($stages -and $clock) {
        $stages['totalMs'] = [int]$clock.ElapsedMilliseconds
        Add-Member -InputObject $result -NotePropertyName Timings -NotePropertyValue $stages
    }
    if ($AsJson) { $result | ConvertTo-Json -Depth 3 } else { $result }
}

function Clear-ChatInput {
    $cleared = Invoke-Ui @('type', '--hwnd', $Hwnd, '--strategy', 'Name', '--value', $InputName, '--clear')
    if (-not $cleared.success) {
        # Fall back to keyboard selection when the input exposes no writable ValuePattern.
        $null = Invoke-Ui @('send-keys', '--hwnd', $Hwnd, '--strategy', 'Name', '--value', $InputName, '--keys', '^a{DEL}')
    }
}

function Get-TopLevelWindows {
    param([string[]]$Filter = @())
    $r = Invoke-Ui (@('list-windows', '--all') + $Filter)
    # The leading comma keeps an empty list an empty array; a bare empty array would unroll to $null,
    # which this function uses to mean "the listing failed".
    if ($r.success) { return ,@($r.windows) }
    $script:ListWindowsError = "$($r.error) $($r.message)".Trim()
    return $null
}

# Explains a foreground failure: a handle that is no longer in the window list means the
# window was closed or Visual Studio was restarted, which is the usual cause of a stale handle.
function Get-ForegroundFailureText {
    $wanted = [Convert]::ToInt64($Hwnd, 16)
    $windows = Get-TopLevelWindows
    if ($null -eq $windows) {
        return "Could not bring the target window to the foreground, and the window list failed too ($script:ListWindowsError)."
    }
    $present = @($windows | Where-Object { [Convert]::ToInt64($_.Hwnd, 16) -eq $wanted })
    if ($present.Count -eq 0) {
        return "Window $Hwnd no longer exists (the app may have been restarted, so the handle is stale). Look it up again, or pass -TitleContains."
    }
    return 'Could not bring the target window to the foreground, even after a second try (Windows can refuse to let a background process take focus). Click the target Visual Studio window yourself, then run this again.'
}

# Brings the target forward; on failure waits a moment and tries once more (not a loop).
function Request-Foreground {
    $h = [IntPtr][Convert]::ToInt64($Hwnd, 16)
    if (Set-AgentForegroundWindow -Handle $h) { return $true }
    Start-Sleep -Seconds 1
    return [bool](Set-AgentForegroundWindow -Handle $h)
}

function Test-ChatInput {
    param([int]$TimeoutMs = 1500)
    $r = Invoke-Ui @('wait-for-element', '--hwnd', $Hwnd, '--strategy', 'Name', '--value', $InputName, '--state', 'enabled', '--timeoutMs', [string]$TimeoutMs)
    return [bool]$r.success
}

# The Chat tab can sit behind a sibling tab in the same pane (for example Git Changes), in which
# case neither the input nor the "Create new session" button is rendered. Select the Chat tab.
function Select-ChatTabIfHidden {
    if (Test-ChatInput) { return }
    $button = Invoke-Ui @('wait-for-element', '--hwnd', $Hwnd, '--strategy', 'AutomationId', '--value', 'createNewThread', '--timeoutMs', '1000')
    if ($button.success) { return }
    $null = Invoke-Ui @('click', '--hwnd', $Hwnd, '--strategy', 'Name', '--value', 'Chat', '--controlType', 'TabItem')
}

# With the Chat tab showing but no input, the pane is on its session list: create a session.
# Returns $null when the input is ready, otherwise an error text.
function Ensure-ChatInput {
    if (Test-ChatInput) { return $null }
    $created = Invoke-Ui @('click', '--hwnd', $Hwnd, '--strategy', 'AutomationId', '--value', 'createNewThread')
    if (-not $created.success) {
        return "The chat input is not showing and a new session could not be created: $($created.error) $($created.message)"
    }
    if (Test-ChatInput -TimeoutMs 30000) { return $null }
    return 'The chat input did not appear after creating a session.'
}

# -Trace: record elapsed milliseconds since the previous mark under a stage name. No-op otherwise.
if ($Trace) {
    $script:SendStages = [ordered]@{}
    $script:SendClock = [Diagnostics.Stopwatch]::StartNew()
    $script:SendLastMark = 0
}
function Set-StageMark {
    param([string]$Name)
    if (-not $Trace) { return }
    $now = [int]$script:SendClock.ElapsedMilliseconds
    $key = $Name
    for ($n = 2; $script:SendStages.Contains($key); $n++) { $key = "$Name#$n" }
    $script:SendStages[$key] = $now - $script:SendLastMark
    $script:SendLastMark = $now
}

if (-not $Hwnd) {
    $found = Get-TopLevelWindows -Filter @('--titleContains', $TitleContains)
    if ($null -eq $found) {
        return Write-Result -Sent $false -Attempts 0 -InputText $null -ErrorText "Could not list windows to resolve -TitleContains '$TitleContains': $script:ListWindowsError. Nothing was typed."
    }
    $candidates = @($found)
    if ($candidates.Count -eq 0) {
        return Write-Result -Sent $false -Attempts 0 -InputText $null -ErrorText "No window title contains '$TitleContains'. Nothing was typed."
    }
    if ($candidates.Count -gt 1) {
        $list = ($candidates | ForEach-Object { "$($_.Hwnd) '$($_.Title)'" }) -join '; '
        return Write-Result -Sent $false -Attempts 0 -InputText $null -ErrorText "More than one window title contains '$TitleContains': $list. Pass -Hwnd or a longer -TitleContains. Nothing was typed."
    }
    $Hwnd = [string]$candidates[0].Hwnd
}
Set-StageMark 'resolve'

if (-not $AllowOwnHost) {
    $ownHostError = Get-OwnHostError
    if ($ownHostError) { return Write-Result -Sent $false -Attempts 0 -InputText $null -ErrorText $ownHostError }
}
Set-StageMark 'ownHost'

if (-not $OverwriteInput) {
    $draftError = Get-ChatDraftError -AllowMissing
    if ($draftError) { return Write-Result -Sent $false -Attempts 0 -InputText $null -ErrorText $draftError }
}
Set-StageMark 'draft1'

if ($Steer) {
    if ($NewSession) { return Write-Result -Sent $false -Attempts 0 -InputText $null -ErrorText 'SteerRequiresExistingChat: -Steer cannot be combined with -NewSession; nothing was typed or clicked.' }
    $steerError = Get-ChatSteerError
    if ($steerError) { return Write-Result -Sent $false -Attempts 0 -InputText $null -ErrorText $steerError }
}

# Red-dot cursor while this script activates the window, types and clicks; always restored.
# Shared with ui-interaction; agent-orchestrator and ui-interaction are sibling skill folders.
$agentCursor = Join-Path $PSScriptRoot '..\..\ui-interaction\scripts\AgentCursor.ps1'
if (-not (Test-Path -LiteralPath $agentCursor)) { throw "AgentCursor.ps1 not found at $agentCursor. Install the ui-interaction skill (Install-Skills.ps1)." }
. $agentCursor

# ---- Be considerate of a person using the machine. Taking the foreground while someone types sends their
# keystrokes into the target chat, so: queue behind other agents (one input block at a time), wait for a quiet
# keyboard and mouse, take the foreground only for the input steps, stop if the person starts using the
# keyboard or mouse, and give their window, focused control and pointer back. The helpers live in
# AgentCursor.ps1 (ui-interaction).
$script:InputBlockStarted = $false
$script:UiLock = $null
$script:UserContext = $null
$script:BlockStamp = [uint32]0
$script:BlockPoint = $null
$script:FocusResult = $null

# Returns an error text when the block cannot start (nothing was typed or clicked), otherwise $null. Safe to call twice.
function Start-InputBlock {
    if ($script:InputBlockStarted) { return $null }
    $script:UiLock = Enter-AgentUiLock
    if (-not $script:UiLock) { return 'UiBusy: other agents kept the keyboard and mouse for more than five minutes. Nothing was typed or clicked; try again later.' }
    if (-not $IgnoreUserActivity -and $QuietSeconds -gt 0) {
        $quiet = Wait-AgentUserQuiet -QuietMilliseconds ($QuietSeconds * 1000) -DraftQuietMilliseconds ($QuietSeconds * 2000) -MaxWaitMilliseconds ($MaxWaitSeconds * 1000) -SpeakRequest:$SpeakRequest
        if (-not $quiet.Quiet) {
            Exit-AgentUiLock $script:UiLock
            $script:UiLock = $null
            $inUse = if ($quiet.InUse) { " ($($quiet.InUse))" } else { '' }
            switch ($quiet.Reason) {
                'SessionNotPresent' { return 'SessionNotPresent: the session is locked or the person is away, so keyboard and mouse input is not possible. Nothing was typed or clicked.' }
                'DoNotDisturb' { return "DoNotDisturb${inUse}: Windows reports a presentation, a full-screen app, quiet time or a menu or drag in progress, or a manual pause is set. Nothing was typed or clicked; try again later." }
                default { return "UserActive${inUse}: the keyboard or mouse stayed in use for $MaxWaitSeconds s. Nothing was typed or clicked; try again when the person has paused." }
            }
        }
    }
    $script:UserContext = Save-AgentUserFocus
    Enable-AgentCursor
    $script:BlockStamp = Get-AgentInputStamp
    $script:BlockPoint = Get-AgentPointerPosition
    $script:InputBlockStarted = $true
    return $null
}

# Before an input step: $null when it is safe to go on, otherwise why the send stopped. Input from the person,
# a held mouse button or modifier, or (after the window was taken) another window in front all stop it.
function Get-InputBlockInterruption {
    param([switch]$RequireForeground)
    if ($IgnoreUserActivity -or -not $script:InputBlockStarted) { return $null }
    if (Test-AgentMeaningfulInputSince -Stamp $script:BlockStamp -Point $script:BlockPoint) { return 'UserInput: the keyboard or mouse was used while the send was in progress, so it stopped before its next input step. Text already pasted was left in the input.' }
    # Input that came only with the pointer moving (no key, no button) is not the person using it: take it as the new baseline.
    Update-InputBlockStamp
    $held = Get-AgentInputInUse
    if ($held) { return "${held}InUse: a mouse button or modifier key is held, so the send stopped before its next input step. Text already pasted was left in the input." }
    if ($RequireForeground -and (Get-AgentForegroundHandle) -ne [IntPtr][Convert]::ToInt64($Hwnd, 16)) { return 'ForegroundLost: another window came to the front, so the send stopped before its next input step. Text already pasted was left in the input.' }
    return $null
}

# After one of this script's own input steps: its input is not the person's.
function Update-InputBlockStamp { if ($script:InputBlockStarted) { $script:BlockStamp = Get-AgentInputStamp; $script:BlockPoint = Get-AgentPointerPosition } }

# Ends the block: cursor dot, the person's window/focus/pointer, the shared own-input stamp, the lock. Safe to call twice.
function Stop-InputBlock {
    try {
        if ($script:InputBlockStarted) {
            Restore-AgentCursor
            $noUserInput = -not (Test-AgentMeaningfulInputSince -Stamp $script:BlockStamp -Point $script:BlockPoint)
            if ($script:UserContext -and -not $NoRestoreFocus) {
                $handed = Restore-AgentUserFocus -Context $script:UserContext -OwnStamp $script:BlockStamp -OwnPoint $script:BlockPoint -HeldHandle ([IntPtr][Convert]::ToInt64($Hwnd, 16))
                $script:FocusResult = $handed.Reason
            }
            if ($noUserInput) { Set-AgentOwnInputStamp }
        }
    }
    finally {
        Exit-AgentUiLock $script:UiLock
        $script:UiLock = $null
        $script:InputBlockStarted = $false
    }
}

try {
    # Everything read-only runs first, with the person's window still in front. The foreground is needed here
    # only to navigate (select the Chat tab, create a session); input verbs refuse a background window.
    $navigate = $NewSession -or (-not $NoNavigate -and -not $Steer -and -not (Test-ChatInput -TimeoutMs 1500))
    if ($navigate) {
        $blockError = Start-InputBlock
        if ($blockError) { return Write-Result -Sent $false -Attempts 0 -InputText $null -ErrorText $blockError }
        if (-not (Request-Foreground)) {
            return Write-Result -Sent $false -Attempts 0 -InputText $null -ErrorText "$(Get-ForegroundFailureText) Nothing was typed or clicked."
        }
        Update-InputBlockStamp
    }
    Set-StageMark 'foreground'
    if ($navigate -and -not $NoNavigate -and -not $Steer) { Select-ChatTabIfHidden; Update-InputBlockStamp }
    Set-StageMark 'tabCheck'

    # Banner check before any input; banners only render while the chat is visible.
    if (-not $IgnoreBanners) {
        # A targeted lookup instead of a full-tree dump. A failed lookup refuses; it must not read as "no banner".
        try { $found = @(Get-ChatBannerIds) }
        catch { return Write-Result -Sent $false -Attempts 0 -InputText $null -ErrorText "BannerCheckFailed: the chat banners could not be read ($($_.Exception.Message)). Nothing was typed; pass -IgnoreBanners to skip the check." }
        if ($found.Count -gt 0) {
            return Write-Result -Sent $false -Attempts 0 -InputText $null -ErrorText "Chat shows $($found -join ', '): the session's folder does not match the open folder (or is untrusted). Nothing was typed. Ask the user, then fix it or pass -IgnoreBanners."
        }
    }
    Set-StageMark 'banner'

    if ($NewSession) {
        $created = Invoke-Ui @('click', '--hwnd', $Hwnd, '--strategy', 'AutomationId', '--value', 'createNewThread')
        if (-not $created.success) {
            return Write-Result -Sent $false -Attempts 0 -InputText $null -ErrorText "Could not create a new session: $($created.error) $($created.message)"
        }
        # A new session can take well over 10 seconds to render its input.
        if (-not (Test-ChatInput -TimeoutMs 30000)) {
            return Write-Result -Sent $false -Attempts 0 -InputText $null -ErrorText 'Chat input did not appear after creating a session.'
        }
    }
    elseif (-not $NoNavigate -and -not $Steer) {
        $chatError = Ensure-ChatInput
        if ($chatError) {
            return Write-Result -Sent $false -Attempts 0 -InputText $null -ErrorText "$chatError Nothing was typed."
        }
    }
    elseif (-not (Test-ChatInput -TimeoutMs 5000)) {
        if ($Steer) { return Write-Result -Sent $false -Attempts 0 -InputText $null -ErrorText 'SteerRequiresBusy: the existing chat input is no longer available; nothing was typed or clicked.' }
        return Write-Result -Sent $false -Attempts 0 -InputText $null -ErrorText 'The chat input is not showing (-NoNavigate was given). Nothing was typed.'
    }
    Set-StageMark 'ensureInput'

    # The person must be quiet before the foreground is taken. The checks below run after this wait, so they
    # see the input as it is at the last moment (a draft may have been typed, or another agent may have sent).
    $blockError = Start-InputBlock
    if ($blockError) { return Write-Result -Sent $false -Attempts 0 -InputText $null -ErrorText $blockError }
    Set-StageMark 'quietWait'

    # One search for the input, shared by the on-screen check and the second draft check.
    $inputElements = @(Get-ChatInputElements)
    $screenError = Get-ChatInputScreenError -Elements $inputElements
    if ($screenError) { return Write-Result -Sent $false -Attempts 0 -InputText $null -ErrorText $screenError }
    Set-StageMark 'screenCheck'

    if (-not $OverwriteInput) {
        $draftError = Get-ChatDraftError -Elements $inputElements
        if ($draftError) { return Write-Result -Sent $false -Attempts 0 -InputText $null -ErrorText $draftError }
    }
    Set-StageMark 'draft2'

    $attempt = 0
    $lastError = $null
    $actual = $null
    while ($attempt -le $Retries) {
        $attempt++
        $interrupted = Get-InputBlockInterruption
        if ($interrupted) { return Write-Result -Sent $false -Attempts $attempt -InputText $null -ErrorText $interrupted }
        if (-not (Set-AgentForegroundWindow -Handle ([IntPtr][Convert]::ToInt64($Hwnd, 16)))) {
            $lastError = Get-ForegroundFailureText
            Set-StageMark 'loopForeground-failed'
            continue
        }
        Update-InputBlockStamp
        Set-StageMark 'loopForeground'
        if ($Steer) {
            $steerError = Get-ChatSteerError
            if ($steerError) { return Write-Result -Sent $false -Attempts $attempt -InputText $null -ErrorText $steerError }
        }
        $interrupted = Get-InputBlockInterruption -RequireForeground
        if ($interrupted) { return Write-Result -Sent $false -Attempts $attempt -InputText $null -ErrorText $interrupted }
        Clear-ChatInput
        Update-InputBlockStamp
        Set-StageMark 'clear'
        $interrupted = Get-InputBlockInterruption -RequireForeground
        if ($interrupted) { return Write-Result -Sent $false -Attempts $attempt -InputText $null -ErrorText $interrupted }
        $typed = Invoke-Ui @('type', '--hwnd', $Hwnd, '--strategy', 'Name', '--value', $InputName, '--text', $Text, '--paste', '--verify')
        Update-InputBlockStamp
        Set-StageMark 'paste'
        if ($typed.success) {
            $actual = Get-ChatInputText
            Set-StageMark 'readback'
            if ([string]::Equals(($actual.Replace("`r`n", "`n").Replace("`r", "`n")), $Text, [StringComparison]::Ordinal)) {
                $lastError = $null
                break
            }
            $lastError = 'read-back-mismatch: the chat input did not match the original prompt.'
        }
        else {
            $actual = $typed.actual
            $lastError = "$($typed.error): $($typed.message)"
        }
        Write-Host "[attempt $attempt] paste did not verify ($lastError); actual='$actual'" -ForegroundColor Yellow
    }

    if ($lastError) {
        Clear-ChatInput
        return Write-Result -Sent $false -Attempts $attempt -InputText $actual -ErrorText "Not sent; input never matched the prompt. Last error: $lastError"
    }

    if ($NoSend) {
        return Write-Result -Sent $false -Attempts $attempt -InputText $actual -ErrorText $null
    }

    $buttonId = 'SendButton'
    if ($Steer) {
        $steerError = Get-ChatSteerError -RequireButton
        if ($steerError) { return Write-Result -Sent $false -Attempts $attempt -InputText $null -ErrorText $steerError }
        $buttonId = 'SteerButton'
    }
    $interrupted = Get-InputBlockInterruption -RequireForeground
    if ($interrupted) { return Write-Result -Sent $false -Attempts $attempt -InputText $null -ErrorText $interrupted }
    $sent = Invoke-Ui @('click', '--hwnd', $Hwnd, '--strategy', 'AutomationId', '--value', $buttonId)
    Update-InputBlockStamp
    Set-StageMark 'send'
    if (-not $sent.success) {
        if ($Steer) { return Write-Result -Sent $false -Attempts $attempt -InputText $null -ErrorText 'SteerClickFailed: SteerButton was not invoked; no fallback was attempted.' }
        return Write-Result -Sent $false -Attempts $attempt -InputText $actual -ErrorText "Send click failed: $($sent.error) $($sent.message)"
    }
    # Hand the keyboard back at once; the result then says whether the person's window and focus were restored.
    Stop-InputBlock
    Set-StageMark 'handback'
    Write-Result -Sent $true -Attempts $attempt -InputText $actual -ErrorText $null
}
finally {
    Stop-InputBlock
}
