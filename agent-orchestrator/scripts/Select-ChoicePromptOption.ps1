<#
.SYNOPSIS
    Answers a Copilot Chat ChoicePrompt card: selects the exact radio option, clicks Submit,
    and confirms the card closed.

.DESCRIPTION
    `click --strategy Name` can fail with ambiguous-match (the RadioButton and its child
    TextBlock share a Name) or land on a ToolTip and select the wrong option. This script finds
    RadioButton elements only with .NET UI Automation (excluding the completion footer's
    Like/Dislike buttons), brings the window forward, and clicks the requested option with a
    real mouse click at its clickable point. SelectionItemPattern.Select() is NOT used: in the
    newer Copilot Chat experience it marks the radio as selected but the card still submits
    its previous choice. It then invokes the single Submit button, waits for Submit to go
    away, and reads the "User entered: ..." echo. Success requires the echo to name exactly
    the requested option; a missing or different echo is reported as a failure.

    The mouse pointer is moved, so do not use the mouse while this runs.

    With no -Option, it lists the available options and changes nothing.

    Multi-question cards show one question per page, with "Next question" instead of Submit
    until the last page. On such a page the script selects the option, clicks "Next question",
    confirms the question text changed, and returns with CardClosed false and NextQuestion set
    to the new question. Call it again for each page; the last page is submitted as usual, and
    its echo lists every answer.

    With -Button, it answers a tool permission prompt ("Do you allow Copilot to ...?")
    instead: it invokes the button with that exact Name and confirms the prompt closed.
    Buttons that grant a lasting permission (names containing "always", "session",
    "solution", "workspace" or "don't ask") are refused unless -AllowPersistent is given.

.PARAMETER Hwnd
    Target window handle, e.g. "0x60AAA".

.PARAMETER Option
    Exact option text to select.

.PARAMETER Button
    Exact Name of a permission-prompt button to invoke, e.g. "Allow this time" or "Deny".
    Cannot be combined with -Option.

.PARAMETER AllowPersistent
    Permit -Button to invoke a button that grants a lasting permission, and required by
    -MenuItem. Use only when the user asked for it.

.PARAMETER MenuItem
    Exact Name of an item in the permission prompt's "More confirmation options" dropdown
    (the button with AutomationId ExtraActionsButton), e.g. "Always allow" or "Allow in this
    session". These items are MenuItems, not buttons, so -Button cannot click them. The script
    opens the dropdown, finds the MenuItem by exact Name, invokes it with InvokePattern and
    confirms the prompt closed. Every item there grants a lasting permission, so it is refused
    unless -AllowPersistent is given. If the item is not found it closes the dropdown again and
    lists the items it saw in Options. Cannot be combined with -Option or -Button.

.PARAMETER TitleContains
    Resolve the target window by title substring instead of passing -Hwnd (via
    Resolve-CopilotWindow.ps1). No match, or several matches, return Success false with a plain
    message or the candidate list in Error. Ignored when -Hwnd is also given.

.PARAMETER ExePath
    Path to agentdebug-ui.exe; used only to resolve -TitleContains.

.PARAMETER SubmitName
    UIA Name of the submit button. Default "Submit".

.PARAMETER TimeoutSeconds
    How long to wait for the card to close after Submit. Default 10.

.OUTPUTS
    PSCustomObject (or JSON with -AsJson): Success, Selected, Options, CardClosed, Echo,
    NextQuestion (set only after moving to the next page of a multi-question card), Error.

.EXAMPLE
    .\Select-ChoicePromptOption.ps1 -Hwnd 0x60AAA

.EXAMPLE
    .\Select-ChoicePromptOption.ps1 -Hwnd 0x60AAA -Option 'Yes, run Bootstrap'

.EXAMPLE
    .\Select-ChoicePromptOption.ps1 -Hwnd 0x60AAA -Button 'Allow this time'

.EXAMPLE
    .\Select-ChoicePromptOption.ps1 -Hwnd 0x60AAA -MenuItem 'Always allow' -AllowPersistent
#>
[CmdletBinding()]
param(
    [string]$Hwnd,

    [string]$Option,

    [string]$Button,

    [switch]$AllowPersistent,

    [string]$SubmitName = 'Submit',

    [ValidateRange(1, 120)]
    [int]$TimeoutSeconds = 10,

    [switch]$AsJson,

    [string]$MenuItem,

    [string]$TitleContains,

    [string]$ExePath = "$env:USERPROFILE\.copilot\toolkits\AgentDebugToolkit\src\AgentDebugToolkit.UiAutomation.Cli\bin\Debug\net8.0-windows\agentdebug-ui.exe",

    # Be considerate of a person using the machine (see Send-CopilotPrompt.ps1): wait for a quiet keyboard
    # and mouse before taking the foreground, stop if they start using it, and hand their window back.
    [ValidateRange(0, 600)]
    [int]$QuietSeconds = 3,

    [ValidateRange(0, 3600)]
    [int]$MaxWaitSeconds = 120,

    [switch]$IgnoreUserActivity,

    [switch]$NoRestoreFocus,

    [switch]$SpeakRequest
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
if (-not ('ChoicePromptNative' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class ChoicePromptNative {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
    public static void LeftClick(int x, int y) {
        SetCursorPos(x, y);
        mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
        mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
    }
}
'@
}
# UIA reports physical pixels; match them so the click lands on the element.
[void][ChoicePromptNative]::SetProcessDPIAware()

function Write-Result {
    param([bool]$Success, [string]$Selected, [string[]]$Options, $CardClosed, [string]$Echo, [string]$ErrorText, [string]$NextQuestion)
    $result = [pscustomobject]@{
        Success      = $Success
        Selected     = $Selected
        Options      = $Options
        CardClosed   = $CardClosed
        Echo         = $Echo
        NextQuestion = $NextQuestion
        Error        = $ErrorText
    }
    if ($AsJson) { $result | ConvertTo-Json -Depth 3 } else { $result }
}

if (-not $Hwnd -and -not $TitleContains) {
    return Write-Result -Success $false -Selected $null -Options $null -CardClosed $null -Echo $null -ErrorText 'Pass -Hwnd or -TitleContains.'
}
if (-not $Hwnd) {
    if (-not (Test-Path $ExePath)) { throw "agentdebug-ui.exe not found at '$ExePath'. Pass -ExePath explicitly." }
    $resolved = & (Join-Path $PSScriptRoot 'Resolve-CopilotWindow.ps1') -TitleContains $TitleContains -ExePath $ExePath
    if ($resolved.Error) {
        return Write-Result -Success $false -Selected $null -Options $null -CardClosed $null -Echo $null -ErrorText $resolved.Error
    }
    $Hwnd = $resolved.Hwnd
}

$handleText = $Hwnd -replace '^0x', ''
$handle = [IntPtr][Convert]::ToInt64($handleText, 16)
$window = [System.Windows.Automation.AutomationElement]::FromHandle($handle)

$excludedIds = @('PART_LikeButton', 'PART_DislikeButton')
$scope = [System.Windows.Automation.TreeScope]::Descendants

function Get-RadioOptions {
    $condition = [System.Windows.Automation.PropertyCondition]::new(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::RadioButton)
    @($window.FindAll($scope, $condition) | Where-Object {
            $_.Current.Name -and $excludedIds -notcontains $_.Current.AutomationId
        })
}

function Get-SubmitButtons {
    $condition = [System.Windows.Automation.AndCondition]::new(
        [System.Windows.Automation.PropertyCondition]::new(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::Button),
        [System.Windows.Automation.PropertyCondition]::new(
            [System.Windows.Automation.AutomationElement]::NameProperty, $SubmitName))
    @($window.FindAll($scope, $condition))
}

function Get-EnabledNamedButtons {
    param([string]$Name)
    $condition = [System.Windows.Automation.AndCondition]::new(
        [System.Windows.Automation.PropertyCondition]::new(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::Button),
        [System.Windows.Automation.PropertyCondition]::new(
            [System.Windows.Automation.AutomationElement]::NameProperty, $Name))
    @($window.FindAll($scope, $condition) | Where-Object { $_.Current.IsEnabled })
}

function Get-QuestionLabels {
    $condition = [System.Windows.Automation.PropertyCondition]::new(
        [System.Windows.Automation.AutomationElement]::AutomationIdProperty, 'RadioFieldLabel')
    @($window.FindAll($scope, $condition) | ForEach-Object { $_.Current.Name })
}

# Same input-block functions as Send-CopilotPrompt.ps1 (a test keeps the two copies identical).
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
    # Stamp first, so a key pressed during the short lead before input starts is noticed; the lead is 250 ms (it was 800 ms)
    # because the quiet wait above has already shown the keyboard and mouse idle.
    $script:BlockStamp = Get-AgentInputStamp
    $script:BlockPoint = Get-AgentPointerPosition
    Enable-AgentCursor -LeadMilliseconds 250
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

$radios = Get-RadioOptions
$optionNames = @($radios | ForEach-Object { $_.Current.Name })

if ($MenuItem) {
    if ($Option -or $Button) {
        return Write-Result -Success $false -Selected $null -Options $optionNames -CardClosed $null -Echo $null -ErrorText 'Use only one of -Option, -Button and -MenuItem.'
    }
    if (-not $AllowPersistent) {
        return Write-Result -Success $false -Selected $null -Options $null -CardClosed $null -Echo $null -ErrorText "-MenuItem choices in the 'More confirmation options' dropdown grant a lasting permission; pass -AllowPersistent only if the user asked for it. Nothing was clicked."
    }
    $extraCondition = [System.Windows.Automation.PropertyCondition]::new(
        [System.Windows.Automation.AutomationElement]::AutomationIdProperty, 'ExtraActionsButton')
    $getExtraButtons = { @($window.FindAll($scope, $extraCondition) | Where-Object { $_.Current.IsEnabled }) }
    $extraButtons = & $getExtraButtons
    if ($extraButtons.Count -ne 1) {
        return Write-Result -Success $false -Selected $null -Options $null -CardClosed $null -Echo $null -ErrorText "Expected exactly one enabled 'More confirmation options' button (ExtraActionsButton); found $($extraButtons.Count). Is a permission prompt waiting? Nothing was clicked."
    }
    $agentCursor = Join-Path $PSScriptRoot '..\..\ui-interaction\scripts\AgentCursor.ps1'
    if (-not (Test-Path -LiteralPath $agentCursor)) { throw "AgentCursor.ps1 not found at $agentCursor. Install the ui-interaction skill (Install-Skills.ps1)." }
    . $agentCursor
    $menuNames = @()
    $menuHits = @()
    $dropdownError = $null
    $blockError = Start-InputBlock
    if ($blockError) { return Write-Result -Success $false -Selected $null -Options $null -CardClosed $null -Echo $null -ErrorText $blockError }
    try {
        $interrupted = Get-InputBlockInterruption
        if ($interrupted) { return Write-Result -Success $false -Selected $null -Options $null -CardClosed $null -Echo $null -ErrorText $interrupted }
        if (-not (Set-AgentForegroundWindow -Handle $handle)) {
            return Write-Result -Success $false -Selected $null -Options $null -CardClosed $null -Echo $null -ErrorText 'Could not bring the target window to the foreground; nothing was clicked.'
        }
        Update-InputBlockStamp
        $interrupted = Get-InputBlockInterruption -RequireForeground
        if ($interrupted) { return Write-Result -Success $false -Selected $null -Options $null -CardClosed $null -Echo $null -ErrorText $interrupted }
        $extraButtons[0].GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
        Update-InputBlockStamp
        # The dropdown is a popup that may sit outside the window's own tree, so search every
        # top-level element, limited to this window's process.
        $menuCondition = [System.Windows.Automation.AndCondition]::new(
            [System.Windows.Automation.PropertyCondition]::new(
                [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
                [System.Windows.Automation.ControlType]::MenuItem),
            [System.Windows.Automation.PropertyCondition]::new(
                [System.Windows.Automation.AutomationElement]::ProcessIdProperty, $window.Current.ProcessId))
        $menuDeadline = (Get-Date).AddSeconds(3)
        while ((Get-Date) -lt $menuDeadline -and $menuHits.Count -eq 0) {
            Start-Sleep -Milliseconds 400
            $menus = @([System.Windows.Automation.AutomationElement]::RootElement.FindAll($scope, $menuCondition))
            $menuNames = @($menus | ForEach-Object { $_.Current.Name } | Where-Object { $_ })
            $menuHits = @($menus | Where-Object { $_.Current.Name -eq $MenuItem -and $_.Current.IsEnabled })
        }
        if ($menuHits.Count -eq 1) {
            $interrupted = Get-InputBlockInterruption -RequireForeground
            if ($interrupted) { $dropdownError = $interrupted }
            else { $menuHits[0].GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); Update-InputBlockStamp }
        }
        else {
            $dropdownError = "Expected exactly one enabled menu item named '$MenuItem' in the dropdown; found $($menuHits.Count)."
            # Close the dropdown again so the prompt is left as it was.
            try { $extraButtons[0].GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Collapse() } catch { }
        }
    }
    finally {
        Stop-InputBlock
    }
    if ($dropdownError) {
        return Write-Result -Success $false -Selected $null -Options $menuNames -CardClosed $false -Echo $null -ErrorText "$dropdownError The dropdown may still be open; check the window."
    }
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $closed = $false
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500
        if ((& $getExtraButtons).Count -eq 0) { $closed = $true; break }
    }
    $errorText = if ($closed) { $null } else { "The permission prompt did not close within $TimeoutSeconds seconds." }
    return Write-Result -Success $closed -Selected $MenuItem -Options $menuNames -CardClosed $closed -Echo $null -ErrorText $errorText
}

if ($Button) {
    if ($Option) {
        return Write-Result -Success $false -Selected $null -Options $optionNames -CardClosed $null -Echo $null -ErrorText 'Use either -Option or -Button, not both.'
    }
    if (-not $AllowPersistent -and $Button -match "always|session|solution|workspace|don't ask|do not ask") {
        return Write-Result -Success $false -Selected $null -Options $null -CardClosed $null -Echo $null -ErrorText "'$Button' looks like a lasting permission; pass -AllowPersistent only if the user asked for it. Nothing was clicked."
    }
    $buttonType = [System.Windows.Automation.PropertyCondition]::new(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::Button)
    $getPromptButtons = {
        $all = @($window.FindAll($scope, $buttonType))
        # Only the run of adjacent sibling buttons around a "Deny" button or the ExtraActionsButton
        # belongs to the prompt; the card can share a parent with the chat pane's own buttons.
        $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
        $isButton = { param($e) $e -and $e.Current.ControlType -eq [System.Windows.Automation.ControlType]::Button }
        $seen = @{}
        foreach ($anchor in @($all | Where-Object { $_.Current.Name -eq 'Deny' -or $_.Current.AutomationId -eq 'ExtraActionsButton' })) {
            $run = [System.Collections.Generic.List[object]]::new()
            $run.Add($anchor)
            $s = $walker.GetPreviousSibling($anchor)
            while (& $isButton $s) { $run.Add($s); $s = $walker.GetPreviousSibling($s) }
            $s = $walker.GetNextSibling($anchor)
            while (& $isButton $s) { $run.Add($s); $s = $walker.GetNextSibling($s) }
            foreach ($b in $run) {
                $id = $b.GetRuntimeId() -join '.'
                if (-not $seen.ContainsKey($id)) { $seen[$id] = $true; $b }
            }
        }
    }
    $promptButtons = & $getPromptButtons
    $buttonNames = @($promptButtons | Where-Object { $_.Current.IsEnabled } | ForEach-Object { $_.Current.Name })
    $buttonHits = @($promptButtons | Where-Object { $_.Current.Name -eq $Button -and $_.Current.IsEnabled })
    if ($buttonHits.Count -ne 1) {
        return Write-Result -Success $false -Selected $null -Options $buttonNames -CardClosed $null -Echo $null -ErrorText "Expected exactly one enabled permission-prompt button named '$Button'; found $($buttonHits.Count)."
    }
    $agentCursor = Join-Path $PSScriptRoot '..\..\ui-interaction\scripts\AgentCursor.ps1'
    if (-not (Test-Path -LiteralPath $agentCursor)) { throw "AgentCursor.ps1 not found at $agentCursor. Install the ui-interaction skill (Install-Skills.ps1)." }
    . $agentCursor
    $blockError = Start-InputBlock
    if ($blockError) { return Write-Result -Success $false -Selected $null -Options $buttonNames -CardClosed $null -Echo $null -ErrorText $blockError }
    try {
        $interrupted = Get-InputBlockInterruption
        if ($interrupted) { return Write-Result -Success $false -Selected $null -Options $buttonNames -CardClosed $null -Echo $null -ErrorText $interrupted }
        if (-not (Set-AgentForegroundWindow -Handle $handle)) {
            return Write-Result -Success $false -Selected $null -Options $buttonNames -CardClosed $null -Echo $null -ErrorText 'Could not bring the target window to the foreground; nothing was clicked.'
        }
        Update-InputBlockStamp
        $interrupted = Get-InputBlockInterruption -RequireForeground
        if ($interrupted) { return Write-Result -Success $false -Selected $null -Options $buttonNames -CardClosed $null -Echo $null -ErrorText $interrupted }
        $buttonHits[0].GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
        Update-InputBlockStamp
    }
    finally {
        Stop-InputBlock
    }
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $closed = $false
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500
        if (@(& $getPromptButtons | Where-Object { $_.Current.Name -eq $Button }).Count -eq 0) { $closed = $true; break }
    }
    $errorText = if ($closed) { $null } else { "The permission prompt did not close within $TimeoutSeconds seconds." }
    return Write-Result -Success $closed -Selected $Button -Options $buttonNames -CardClosed $closed -Echo $null -ErrorText $errorText
}

if (-not $Option) {
    return Write-Result -Success ($optionNames.Count -gt 0) -Selected $null -Options $optionNames -CardClosed $null -Echo $null -ErrorText $(if ($optionNames.Count -eq 0) { 'No ChoicePrompt options found.' } else { $null })
}

$found = @($radios | Where-Object { $_.Current.Name -eq $Option })
if ($found.Count -ne 1) {
    return Write-Result -Success $false -Selected $null -Options $optionNames -CardClosed $null -Echo $null -ErrorText "Expected exactly one option named '$Option'; found $($found.Count)."
}

$target = $found[0]
# Mark the cursor while the agent owns the mouse and keyboard; always restore it.
# Shared with ui-interaction; agent-orchestrator and ui-interaction are sibling skill folders.
$agentCursor = Join-Path $PSScriptRoot '..\..\ui-interaction\scripts\AgentCursor.ps1'
if (-not (Test-Path -LiteralPath $agentCursor)) { throw "AgentCursor.ps1 not found at $agentCursor. Install the ui-interaction skill (Install-Skills.ps1)." }
. $agentCursor
# One input block covers the whole answer (option click, then Next question or Submit), so the person's window
# is handed back once. UIA SetFocus on the card is inside it too: outside, it could pull focus from whatever
# the person is typing in. Waiting for the card to close and reading the echo need no foreground and come after.
$blockError = Start-InputBlock
if ($blockError) { return Write-Result -Success $false -Selected $null -Options $optionNames -CardClosed $null -Echo $null -ErrorText $blockError }
try {
    $interrupted = Get-InputBlockInterruption
    if ($interrupted) { return Write-Result -Success $false -Selected $null -Options $optionNames -CardClosed $null -Echo $null -ErrorText $interrupted }
    if (-not (Set-AgentForegroundWindow -Handle $handle)) {
        return Write-Result -Success $false -Selected $null -Options $optionNames -CardClosed $null -Echo $null -ErrorText 'Could not bring the target window to the foreground; nothing was clicked.'
    }
    Update-InputBlockStamp
    $interrupted = Get-InputBlockInterruption -RequireForeground
    if ($interrupted) { return Write-Result -Success $false -Selected $null -Options $optionNames -CardClosed $null -Echo $null -ErrorText $interrupted }
    $target.SetFocus()
    Update-InputBlockStamp
    $point = $target.GetClickablePoint()
    [ChoicePromptNative]::LeftClick([int]$point.X, [int]$point.Y)
    Update-InputBlockStamp
    Start-Sleep -Milliseconds 400
    $selection = $target.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
    if (-not $selection.Current.IsSelected) {
        return Write-Result -Success $false -Selected $null -Options $optionNames -CardClosed $null -Echo $null -ErrorText "Option '$Option' is not selected after clicking it; Submit was not clicked."
    }

    $submitButtons = Get-SubmitButtons
    $nextButtons = Get-EnabledNamedButtons -Name 'Next question'
    if ($submitButtons.Count -eq 0 -and $nextButtons.Count -eq 1) {
        $before = (Get-QuestionLabels) -join ' | '
        $nextButtons[0].GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
        Update-InputBlockStamp
        Stop-InputBlock
        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        $after = $before
        while ((Get-Date) -lt $deadline -and $after -eq $before) {
            Start-Sleep -Milliseconds 400
            $after = (Get-QuestionLabels) -join ' | '
        }
        if ($after -eq $before) {
            return Write-Result -Success $false -Selected $Option -Options $optionNames -CardClosed $false -Echo $null -ErrorText "Clicked 'Next question' but the question did not change within $TimeoutSeconds seconds."
        }
        return Write-Result -Success $true -Selected $Option -Options $optionNames -CardClosed $false -Echo $null -ErrorText $null -NextQuestion $after
    }
    if ($submitButtons.Count -ne 1) {
        return Write-Result -Success $false -Selected $Option -Options $optionNames -CardClosed $false -Echo $null -ErrorText "Expected exactly one '$SubmitName' button; found $($submitButtons.Count). Option is selected but not submitted."
    }
    $submitButtons[0].GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    Update-InputBlockStamp
}
finally {
    Stop-InputBlock
}

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$closed = $false
$echo = $null
$entered = $null
$textCondition = [System.Windows.Automation.PropertyCondition]::new(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::Text)
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 500
    if ((Get-SubmitButtons).Count -eq 0) {
        $closed = $true
        # The echo is appended to the question text, e.g. "Pick one option. User entered: Option 2".
        $echo = @($window.FindAll($scope, $textCondition) | ForEach-Object { $_.Current.Name } | Where-Object { $_ -match 'User entered:' }) | Select-Object -Last 1
        if ($echo) {
            $entered = ($echo -replace '(?s)^.*User entered:\s*', '').Trim()
            break
        }
    }
}

$errorText = if (-not $closed) { "The card did not close within $TimeoutSeconds seconds." }
elseif (-not $echo) { "The card closed but no 'User entered:' echo was found; confirm the submitted option manually." }
elseif ($entered -ne $Option) { "Wrong option submitted: requested '$Option', card echoed '$entered'." }
else { $null }
Write-Result -Success ($closed -and -not $errorText) -Selected $entered -Options $optionNames -CardClosed $closed -Echo $echo -ErrorText $errorText
