<#
.SYNOPSIS
    Marks the system cursor while an agent is using the machine, so the user knows to keep
    their hands off, and restores the user's cursors afterwards.

.DESCRIPTION
    Shared by the ui-interaction, ui-navigation-orchestrator and agent-orchestrator skills.
    Three indicators, all drawn as the normal cursor with a coloured dot in the lower-right:

      Blue dot  (Orchestrator)  agent-orchestrator is driving or monitoring another Copilot
                                chat. Don't use the target window.
      Green dot (UiAutomation)  a multi-step ui-interaction / ui-navigation-orchestrator run is
                                in progress. Don't use the target application.
      Red dot   (Input)         the agent is moving the mouse or typing right now, whoever owns
                                the session. Don't touch the mouse or keyboard.

    A session is recorded, with its kind, in a flag file (%TEMP%\agent-cursor-session.flag) so
    it survives across separate script runs. Only one session exists at a time: the first one
    started owns the colour, a nested Start of the other kind changes nothing, and a Stop of
    the other kind leaves the owner's session alone. When an Input action ends, the cursor
    returns to the active session's colour, otherwise to the user's own cursors. A flag older
    than 12 hours is treated as abandoned and ignored. A flag without a kind (written by an
    older version) counts as Orchestrator.

    Dot-source this file to get:
      Start-AgentCursorSession   -Kind Orchestrator|UiAutomation: show its dot and record it
      Stop-AgentCursorSession    -Kind: clear that kind's session; no -Kind clears any session
      Get-AgentCursorSessionKind the active session's kind, or $null
      Enable-AgentCursor         red dot (or -Mode Session/Orchestrator/UiAutomation)
      Restore-AgentCursor        back to the active session's dot, else the user's cursors
      Set-AgentForegroundWindow  bring a window to the front (use inside a red-dot block)

    Always pair Enable-AgentCursor with Restore-AgentCursor in a `finally` block. If anything
    is left behind, run this file with -Restore (clears the session and restores everything),
    or sign out and back in.

.PARAMETER Session
    When the file is run (not dot-sourced): Start or Stop a session of -Kind.

.PARAMETER Kind
    Orchestrator (blue, default, for agent-orchestrator) or UiAutomation (green, for
    ui-interaction / ui-navigation-orchestrator runs).

.PARAMETER Restore
    When the file is run: clear any session and restore the user's cursors.

.PARAMETER Show
    When the file is run: show the -Mode indicator for -Seconds, then restore.

.EXAMPLE
    .\AgentCursor.ps1 -Session Start                     # agent-orchestrator: blue dot
    .\AgentCursor.ps1 -Session Stop                      # before every hand-back, always

.EXAMPLE
    .\AgentCursor.ps1 -Session Start -Kind UiAutomation  # multi-step UI run: green dot
    .\AgentCursor.ps1 -Session Stop -Kind UiAutomation

.EXAMPLE
    . .\AgentCursor.ps1
    Enable-AgentCursor
    try { <mouse/keyboard code> } finally { Restore-AgentCursor }

.EXAMPLE
    .\AgentCursor.ps1 -Show -Mode UiAutomation -Seconds 5
#>
[CmdletBinding()]
param(
    [ValidateSet('Start', 'Stop')]
    [string]$Session,

    [ValidateSet('Orchestrator', 'UiAutomation')]
    [string]$Kind = 'Orchestrator',

    [switch]$Restore,

    [switch]$Show,

    [ValidateSet('Input', 'Session', 'Orchestrator', 'UiAutomation')]
    [string]$Mode = 'Input',

    [ValidateRange(1, 60)]
    [int]$Seconds = 5
)

Add-Type -AssemblyName System.Drawing
if (-not ('AgentCursorNativeV2' -as [type])) {
    Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;

public static class AgentCursorNativeV2 {
    [StructLayout(LayoutKind.Sequential)]
    struct ICONINFO { public bool fIcon; public int xHotspot; public int yHotspot; public IntPtr hbmMask; public IntPtr hbmColor; }

    [DllImport("user32.dll")] static extern IntPtr LoadCursor(IntPtr hInstance, IntPtr name);
    [DllImport("user32.dll")] static extern bool GetIconInfo(IntPtr hIcon, out ICONINFO info);
    [DllImport("user32.dll")] static extern IntPtr CreateIconIndirect(ref ICONINFO info);
    [DllImport("user32.dll")] static extern bool SetSystemCursor(IntPtr hcur, uint id);
    [DllImport("user32.dll")] static extern bool SystemParametersInfo(uint action, uint param, IntPtr vparam, uint winIni);
    [DllImport("user32.dll")] static extern bool DestroyIcon(IntPtr hIcon);
    [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr obj);

    static readonly uint[] Ids = { 32512 /* arrow */, 32649 /* hand */, 32513 /* I-beam */ };

    // Copies the current system cursor, adds a dot in the lower-right, and keeps the hotspot.
    static IntPtr CreateMarkedCursor(uint id, Color dot) {
        IntPtr source = LoadCursor(IntPtr.Zero, (IntPtr)id);
        ICONINFO info;
        if (source == IntPtr.Zero || !GetIconInfo(source, out info)) return IntPtr.Zero;
        if (info.hbmMask != IntPtr.Zero) DeleteObject(info.hbmMask);
        if (info.hbmColor != IntPtr.Zero) DeleteObject(info.hbmColor);

        using (Icon icon = Icon.FromHandle(source))
        using (Bitmap bitmap = icon.ToBitmap()) {
            int size = Math.Min(bitmap.Width, bitmap.Height);
            float diameter = size * 0.42f;
            float x = size - diameter - 1;
            float y = size - diameter - 1;
            using (Graphics g = Graphics.FromImage(bitmap))
            using (SolidBrush fill = new SolidBrush(dot))
            using (Pen white = new Pen(Color.White, Math.Max(1.5f, size / 16f))) {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.FillEllipse(fill, x, y, diameter, diameter);
                g.DrawEllipse(white, x, y, diameter, diameter);
            }

            // GetHicon keeps the alpha channel; re-create it as a cursor with the original hotspot.
            IntPtr hicon = bitmap.GetHicon();
            ICONINFO marked;
            if (!GetIconInfo(hicon, out marked)) { DestroyIcon(hicon); return IntPtr.Zero; }
            marked.fIcon = false;
            marked.xHotspot = info.xHotspot;
            marked.yHotspot = info.yHotspot;
            IntPtr cursor = CreateIconIndirect(ref marked);
            if (marked.hbmMask != IntPtr.Zero) DeleteObject(marked.hbmMask);
            if (marked.hbmColor != IntPtr.Zero) DeleteObject(marked.hbmColor);
            DestroyIcon(hicon);
            return cursor;
        }
    }

    public static bool Mark(int r, int g, int b) {
        // Reload the user's scheme first so a previous dot isn't copied into the new cursor.
        RestoreAll();
        bool all = true;
        foreach (uint id in Ids) {
            IntPtr cursor = CreateMarkedCursor(id, Color.FromArgb(255, r, g, b));
            // SetSystemCursor takes ownership of the handle.
            if (cursor == IntPtr.Zero || !SetSystemCursor(cursor, id)) all = false;
        }
        return all;
    }

    public static bool RestoreAll() {
        const uint SPI_SETCURSORS = 0x0057;
        return SystemParametersInfo(SPI_SETCURSORS, 0, IntPtr.Zero, 0);
    }
}
'@
}

$script:AgentCursorSessionFlag = Join-Path $env:TEMP 'agent-cursor-session.flag'

function Get-AgentCursorSessionKind {
    $flag = Get-Item -LiteralPath $script:AgentCursorSessionFlag -ErrorAction SilentlyContinue
    if (-not $flag -or ((Get-Date) - $flag.LastWriteTime).TotalHours -ge 12) { return $null }
    $content = [string](Get-Content -LiteralPath $flag.FullName -Raw -ErrorAction SilentlyContinue)
    if ($content -match 'kind=UiAutomation') { return 'UiAutomation' }
    return 'Orchestrator'
}

function Test-AgentCursorSession {
    return [bool](Get-AgentCursorSessionKind)
}

function Set-AgentCursorMark {
    param([ValidateSet('Input', 'Orchestrator', 'UiAutomation')][string]$Mode)
    $ok = switch ($Mode) {
        'Input'        { [AgentCursorNativeV2]::Mark(230, 30, 30) }
        'Orchestrator' { [AgentCursorNativeV2]::Mark(30, 110, 230) }
        'UiAutomation' { [AgentCursorNativeV2]::Mark(30, 170, 70) }
    }
    if (-not $ok) { Write-Warning "Could not set the $Mode cursor indicator; continuing without it." }
}

function Enable-AgentCursor {
    [CmdletBinding()]
    param(
        # Session means the active session's colour (blue if none is active).
        [ValidateSet('Input', 'Session', 'Orchestrator', 'UiAutomation')]
        [string]$Mode = 'Input',

        # Pause after switching so the user notices before input starts.
        [ValidateRange(0, 5000)]
        [int]$LeadMilliseconds = 800
    )
    if ($Mode -eq 'Session') {
        $Mode = Get-AgentCursorSessionKind
        if (-not $Mode) { $Mode = 'Orchestrator' }
    }
    Set-AgentCursorMark -Mode $Mode
    if ($LeadMilliseconds -gt 0) { Start-Sleep -Milliseconds $LeadMilliseconds }
}

function Restore-AgentCursor {
    [CmdletBinding()]
    param()
    $active = Get-AgentCursorSessionKind
    if ($active) {
        Set-AgentCursorMark -Mode $active
    }
    elseif (-not [AgentCursorNativeV2]::RestoreAll()) {
        Write-Warning 'Could not restore the cursor scheme. Run AgentCursor.ps1 -Restore, or sign out and back in.'
    }
}

# Returns the kind that owns the session afterwards: -Kind if it started (or was already
# running), the other kind if that one was already active (nothing changed).
function Start-AgentCursorSession {
    [CmdletBinding()]
    param(
        [ValidateSet('Orchestrator', 'UiAutomation')]
        [string]$Kind = 'Orchestrator'
    )
    $active = Get-AgentCursorSessionKind
    if ($active -and $active -ne $Kind) { return $active }
    Set-Content -LiteralPath $script:AgentCursorSessionFlag -Value "kind=$Kind pid=$PID started=$(Get-Date -Format o)" -Encoding ASCII
    Set-AgentCursorMark -Mode $Kind
    return $Kind
}

# Without -Kind, clears any session. With -Kind, clears it only if that kind owns it, and
# returns $false (changing nothing) if the other kind does.
function Stop-AgentCursorSession {
    [CmdletBinding()]
    param(
        [ValidateSet('Orchestrator', 'UiAutomation')]
        [string]$Kind
    )
    $active = Get-AgentCursorSessionKind
    if ($Kind -and $active -and $active -ne $Kind) { return $false }
    Remove-Item -LiteralPath $script:AgentCursorSessionFlag -ErrorAction SilentlyContinue
    if (-not [AgentCursorNativeV2]::RestoreAll()) {
        Write-Warning 'Could not restore the cursor scheme. Run AgentCursor.ps1 -Restore, or sign out and back in.'
    }
    return $true
}

if (-not ('AgentForegroundNative' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class AgentForegroundNative {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int cmd);
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
}
'@
}

function Set-AgentForegroundWindow {
    <#
    .SYNOPSIS
        Brings a window to the foreground and returns $true only if it really is in front.
        Windows' focus-stealing prevention often refuses SetForegroundWindow from a background
        process (agentdebug-ui `activate` fails with stale-context); a single Alt key tap first
        is the documented way to make the switch allowed. Call it inside an Input-cursor block.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [IntPtr]$Handle,

        [ValidateRange(1, 10)]
        [int]$Attempts = 3
    )
    if ([AgentForegroundNative]::IsIconic($Handle)) { [void][AgentForegroundNative]::ShowWindow($Handle, 9) }
    for ($i = 1; $i -le $Attempts; $i++) {
        if ([AgentForegroundNative]::GetForegroundWindow() -eq $Handle) { return $true }
        if ($i -gt 1) {
            [AgentForegroundNative]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero)
            [AgentForegroundNative]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)
        }
        [void][AgentForegroundNative]::SetForegroundWindow($Handle)
        Start-Sleep -Milliseconds 300
    }
    return ([AgentForegroundNative]::GetForegroundWindow() -eq $Handle)
}

if ($MyInvocation.InvocationName -ne '.') {
    $dot = @{ Orchestrator = 'blue'; UiAutomation = 'green' }
    if ($Restore) {
        [void](Stop-AgentCursorSession)
        'All sessions cleared; cursors restored.'
    }
    elseif ($Session -eq 'Stop') {
        $active = Get-AgentCursorSessionKind
        if (Stop-AgentCursorSession -Kind $Kind) { 'Session cleared; cursors restored.' }
        else { "$Kind session not active; the $active session ($($dot[$active]) dot) still owns the cursor." }
    }
    elseif ($Session -eq 'Start') {
        $owner = Start-AgentCursorSession -Kind $Kind
        if ($owner -eq $Kind) { "$Kind session started ($($dot[$Kind]) dot). Run with -Session Stop$(if ($Kind -ne 'Orchestrator') { " -Kind $Kind" }) when done." }
        else { "$owner session already active ($($dot[$owner]) dot); it keeps the cursor. Nothing changed." }
    }
    elseif ($Show) {
        Enable-AgentCursor -Mode $Mode -LeadMilliseconds 0
        try { Start-Sleep -Seconds $Seconds } finally { Restore-AgentCursor }
        "$Mode indicator shown; cursor restored."
    }
}
