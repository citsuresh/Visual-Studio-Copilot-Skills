<#
.SYNOPSIS
    Scrolls the Copilot Chat message list up or down by pages and reports whether it moved.

.DESCRIPTION
    The chat list (AutomationId "session") is virtualized, so messages outside the visible area
    are not returned by Get-CopilotChatTranscript.ps1 until the list is scrolled. Found in live
    testing: ScrollPattern.SetScrollPercent does NOT move this list, while
    ScrollPattern.Scroll(NoAmount, LargeDecrement / LargeIncrement) does. This script uses the
    second form, one page per step, and reads VerticalScrollPercent before and after. Always
    check Moved: a scroll that did nothing looks the same as a scroll to a position that was
    already showing.

    With -ToEnd it keeps paging in -Direction until the percent stops changing (at most 60 pages).

    Read-only except for the list's scroll position. It never activates the window, clicks or
    types, so it does not use the red-dot cursor.

.PARAMETER Hwnd
    Target window handle, e.g. "0x60AAA".

.PARAMETER Direction
    Up or Down. Default Down.

.PARAMETER Pages
    Number of pages to scroll. Default 1. Ignored with -ToEnd.

.PARAMETER ToEnd
    Scroll until the list stops moving (the top for Up, the bottom for Down).

.OUTPUTS
    PSCustomObject: Success, Direction, PercentBefore, PercentAfter, Moved, Steps, Error.
    Percents are 0-100; -1 means the list reported that it cannot scroll vertically.

.EXAMPLE
    .\Set-ChatScroll.ps1 -Hwnd 0x60AAA -Direction Up -Pages 2

.EXAMPLE
    .\Set-ChatScroll.ps1 -Hwnd 0x60AAA -ToEnd
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Hwnd,

    [ValidateSet('Up', 'Down')]
    [string]$Direction = 'Down',

    [ValidateRange(1, 200)]
    [int]$Pages = 1,

    [switch]$ToEnd,

    [switch]$AsJson
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

function Write-Result {
    param([bool]$Success, [double]$Before, [double]$After, [int]$Steps, [string]$ErrorText)
    $result = [pscustomobject]@{
        Success       = $Success
        Direction     = $Direction
        PercentBefore = $Before
        PercentAfter  = $After
        Moved         = ($Before -ne $After)
        Steps         = $Steps
        Error         = $ErrorText
    }
    if ($AsJson) { $result | ConvertTo-Json -Depth 3 } else { $result }
}

$handle = [IntPtr][Convert]::ToInt64(($Hwnd -replace '^0x', ''), 16)
$window = [System.Windows.Automation.AutomationElement]::FromHandle($handle)
$idCondition = [System.Windows.Automation.PropertyCondition]::new(
    [System.Windows.Automation.AutomationElement]::AutomationIdProperty, 'session')
$list = $window.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $idCondition)
if (-not $list) {
    return Write-Result -Success $false -Before 0 -After 0 -Steps 0 -ErrorText "No chat list (AutomationId 'session') in window $Hwnd. Is the chat showing?"
}
$scroll = $null
try { $scroll = $list.GetCurrentPattern([System.Windows.Automation.ScrollPattern]::Pattern) } catch { }
if (-not $scroll) {
    return Write-Result -Success $false -Before 0 -After 0 -Steps 0 -ErrorText "The chat list does not support ScrollPattern."
}

$amount = if ($Direction -eq 'Up') { [System.Windows.Automation.ScrollAmount]::LargeDecrement } else { [System.Windows.Automation.ScrollAmount]::LargeIncrement }
$none = [System.Windows.Automation.ScrollAmount]::NoAmount

$before = [double]$scroll.Current.VerticalScrollPercent
$limit = if ($ToEnd) { 60 } else { $Pages }
$steps = 0
$last = $before
for ($i = 1; $i -le $limit; $i++) {
    try { $scroll.Scroll($none, $amount) }
    catch {
        return Write-Result -Success $false -Before $before -After ([double]$scroll.Current.VerticalScrollPercent) -Steps $steps -ErrorText "Scroll failed: $($_.Exception.Message)"
    }
    $steps++
    Start-Sleep -Milliseconds 250
    $now = [double]$scroll.Current.VerticalScrollPercent
    if ($ToEnd -and $now -eq $last) { break }
    $last = $now
}
$after = [double]$scroll.Current.VerticalScrollPercent
Write-Result -Success $true -Before $before -After $after -Steps $steps -ErrorText $null
