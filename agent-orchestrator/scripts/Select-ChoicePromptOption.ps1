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
    Permit -Button to invoke a button that grants a lasting permission. Use only when the
    user asked for it.

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
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Hwnd,

    [string]$Option,

    [string]$Button,

    [switch]$AllowPersistent,

    [string]$SubmitName = 'Submit',

    [ValidateRange(1, 120)]
    [int]$TimeoutSeconds = 10,

    [switch]$AsJson
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

$radios = Get-RadioOptions
$optionNames = @($radios | ForEach-Object { $_.Current.Name })

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
    Enable-AgentCursor
    try {
        if (-not (Set-AgentForegroundWindow -Handle $handle)) {
            return Write-Result -Success $false -Selected $null -Options $buttonNames -CardClosed $null -Echo $null -ErrorText 'Could not bring the target window to the foreground; nothing was clicked.'
        }
        $buttonHits[0].GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    }
    finally {
        Restore-AgentCursor
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
$target.SetFocus()
# Mark the cursor while the agent owns the mouse and keyboard; always restore it.
# Shared with ui-interaction; agent-orchestrator and ui-interaction are sibling skill folders.
$agentCursor = Join-Path $PSScriptRoot '..\..\ui-interaction\scripts\AgentCursor.ps1'
if (-not (Test-Path -LiteralPath $agentCursor)) { throw "AgentCursor.ps1 not found at $agentCursor. Install the ui-interaction skill (Install-Skills.ps1)." }
. $agentCursor
Enable-AgentCursor
try {
    if (-not (Set-AgentForegroundWindow -Handle $handle)) {
        return Write-Result -Success $false -Selected $null -Options $optionNames -CardClosed $null -Echo $null -ErrorText 'Could not bring the target window to the foreground; nothing was clicked.'
    }
    $point = $target.GetClickablePoint()
    [ChoicePromptNative]::LeftClick([int]$point.X, [int]$point.Y)
    Start-Sleep -Milliseconds 400
}
finally {
    Restore-AgentCursor
}
$selection = $target.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
if (-not $selection.Current.IsSelected) {
    return Write-Result -Success $false -Selected $null -Options $optionNames -CardClosed $null -Echo $null -ErrorText "Option '$Option' is not selected after clicking it; Submit was not clicked."
}

$submitButtons = Get-SubmitButtons
$nextButtons = Get-EnabledNamedButtons -Name 'Next question'
if ($submitButtons.Count -eq 0 -and $nextButtons.Count -eq 1) {
    $before = (Get-QuestionLabels) -join ' | '
    $nextButtons[0].GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
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
