<#
.SYNOPSIS
    Dispatches a mouse click at an absolute physical screen coordinate.

.DESCRIPTION
    Dot-source this file to load Invoke-ScreenClick. It loads the shared AgentCursor helpers
    and sets process DPI awareness before screenshot coordinates are mapped to screen points.
    A returned object means the input was dispatched, not that the intended target acted.

.PARAMETER X
    Absolute physical screen X coordinate.

.PARAMETER Y
    Absolute physical screen Y coordinate.

.PARAMETER Button
    Mouse button to dispatch: Left (default) or Right.

.PARAMETER Double
    Dispatch two clicks with a short interval.

.EXAMPLE
    . .\Invoke-ScreenClick.ps1
    Invoke-ScreenClick -X 420 -Y 260

.NOTES
    Live-tested against a Notepad editor window on 2026-11-08; a test string was saved and
    read back after a coordinate click.
#>
. (Join-Path $PSScriptRoot 'AgentCursor.ps1')

if (-not ('AgentScreenClickNative' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class AgentScreenClickNative {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SetProcessDPIAware();

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SetCursorPos(int x, int y);

    [DllImport("user32.dll")]
    public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
}
'@
}

[void][AgentScreenClickNative]::SetProcessDPIAware()

function Invoke-ScreenClick {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$X,

        [Parameter(Mandatory = $true)]
        [int]$Y,

        [ValidateSet('Left', 'Right')]
        [string]$Button = 'Left',

        [switch]$Double
    )

    $downFlag = if ($Button -eq 'Left') { 0x0002 } else { 0x0008 }
    $upFlag = if ($Button -eq 'Left') { 0x0004 } else { 0x0010 }
    $clickCount = if ($Double) { 2 } else { 1 }

    try {
        Enable-AgentCursor
        [void][AgentScreenClickNative]::SetProcessDPIAware()
        if (-not [AgentScreenClickNative]::SetCursorPos($X, $Y)) {
            $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            throw "SetCursorPos failed for ($X, $Y) with Win32 error $errorCode."
        }

        for ($i = 0; $i -lt $clickCount; $i++) {
            [AgentScreenClickNative]::mouse_event([uint32]$downFlag, 0, 0, 0, [UIntPtr]::Zero)
            [AgentScreenClickNative]::mouse_event([uint32]$upFlag, 0, 0, 0, [UIntPtr]::Zero)
            if ($Double -and $i -eq 0) { Start-Sleep -Milliseconds 100 }
        }

        [pscustomobject]@{
            X                = $X
            Y                = $Y
            Button           = $Button
            Double           = [bool]$Double
            InputDispatched  = $true
        }
    }
    finally {
        Restore-AgentCursor
    }
}
