<#
.SYNOPSIS
    Watches for deliberate user input for a number of seconds and reports whether any happened: key presses, mouse button
    clicks and wheel scrolls. Mouse MOVEMENT alone is ignored.

.DESCRIPTION
    For an "is the person here" check that does not take a nudged, drifting or vibrating mouse for presence. No hooks and no
    key logging: every -PollMs (default 30) it reads three cheap Windows values, the last-input time (GetLastInputInfo),
    the cursor position (GetCursorPos) and the up/down state of the keys and mouse buttons (GetAsyncKeyState), and compares
    them with the previous sample:
      - a key or mouse button is down in the sample: deliberate input;
      - the last-input time changed and the cursor did NOT move since the previous sample: a key press, a click or a wheel
        step without movement: deliberate input;
      - the cursor moved and nothing else changed: a mouse move, ignored (counted in MoveSamples).
    Only counts and times are reported, never which key it was. Known limits: a wheel step or a very short click made
    together with a cursor movement inside one 30 ms sample can be missed; input sent by this machine's agents (UI Automation
    typing or clicking) cannot be told from the person's and counts; a locked or absent session reports no input.

.PARAMETER Seconds
    How long to watch (default 60; 1 to 3600).

.PARAMETER PollMs
    Sampling interval (default 30; 10 to 500).

.PARAMETER StopAtFirst
    Return as soon as the first deliberate input is seen.

.PARAMETER AsJson
    Print the result as JSON.
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 3600)][int]$Seconds = 60,
    [ValidateRange(10, 500)][int]$PollMs = 30,
    [switch]$StopAtFirst,
    [switch]$AsJson
)
$ErrorActionPreference = 'Stop'

# ---- pure logic (tested offline in scripts\agent\Test-WatchUserInput.ps1) ----

# Samples: LastInputTick (the Windows tick of the last input of any kind), X, Y (cursor), AnyKeyDown, AnyButtonDown.
# Returns 'Input', 'Move' or 'None'.
function Get-InputKind {
    param($Previous, $Current)
    if ($Current.AnyKeyDown -or $Current.AnyButtonDown) { return 'Input' }
    if ($null -eq $Previous) { return 'None' }
    $moved = ($Current.X -ne $Previous.X) -or ($Current.Y -ne $Previous.Y)
    $tickChanged = ([int64]$Current.LastInputTick -ne [int64]$Previous.LastInputTick)
    if ($tickChanged -and -not $moved) { return 'Input' }
    if ($moved) { return 'Move' }
    return 'None'
}

# ---- reading the machine (not run offline) ----
if (-not ('UserInputSampler' -as [type])) {
    Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class UserInputSampler {
    [StructLayout(LayoutKind.Sequential)] struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
    [StructLayout(LayoutKind.Sequential)] struct POINT { public int X; public int Y; }
    [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO p);
    [DllImport("user32.dll")] static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int vKey);
    // {last-input tick, x, y, any key down (0/1), any mouse button down (0/1)}; the key identity is never returned.
    public static long[] Sample() {
        LASTINPUTINFO l = new LASTINPUTINFO(); l.cbSize = (uint)Marshal.SizeOf(l); GetLastInputInfo(ref l);
        POINT pt; GetCursorPos(out pt);
        long key = 0, button = 0;
        for (int vk = 0x01; vk <= 0xFE; vk++) {
            if ((GetAsyncKeyState(vk) & 0x8000) == 0) continue;
            if (vk <= 0x06) button = 1; else key = 1;
        }
        return new long[] { l.dwTime, pt.X, pt.Y, key, button };
    }
}
'@
}
function Read-InputSample {
    $s = [UserInputSampler]::Sample()
    return [pscustomobject]@{ LastInputTick = $s[0]; X = $s[1]; Y = $s[2]; AnyKeyDown = ($s[3] -eq 1); AnyButtonDown = ($s[4] -eq 1) }
}

# ---- main ----
$clock = [Diagnostics.Stopwatch]::StartNew()
$previous = Read-InputSample
$inputSamples = 0; $moveSamples = 0; $first = $null; $last = $null
while ($clock.Elapsed.TotalSeconds -lt $Seconds) {
    Start-Sleep -Milliseconds $PollMs
    $current = Read-InputSample
    switch (Get-InputKind -Previous $previous -Current $current) {
        'Input' { $inputSamples++; if ($null -eq $first) { $first = [int]$clock.ElapsedMilliseconds }; $last = [int]$clock.ElapsedMilliseconds }
        'Move' { $moveSamples++ }
    }
    $previous = $current
    if ($StopAtFirst -and $inputSamples -gt 0) { break }
}
$result = [pscustomobject]@{
    Active = ($inputSamples -gt 0)
    InputSamples = $inputSamples
    MoveSamples = $moveSamples
    FirstInputAtMs = $first
    LastInputAtMs = $last
    ElapsedMs = [int]$clock.ElapsedMilliseconds
}
if ($AsJson) { $result | ConvertTo-Json -Compress } else { $result }
