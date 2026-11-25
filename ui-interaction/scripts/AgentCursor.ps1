<#
.SYNOPSIS
    Marks the system cursor while an agent is using the machine, so the user knows to keep
    their hands off, and restores the user's cursors afterwards.

.DESCRIPTION
    Shared by the ui-interaction, ui-navigation-orchestrator and agent-orchestrator skills.
    Four indicators, all drawn as the normal cursor with a coloured dot in the lower-right:

      Amber dot (Waiting)       the agent wants the keyboard or mouse and is waiting for the person to
                                pause (Wait-AgentUserQuiet shows it after about half a second of waiting).
                                Nothing is being typed or clicked yet; pausing lets it proceed.

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

# ---- Native helpers: compiled once, cached as a small assembly --------------------------------------------------
# Compiling these three C# types on every run cost about 1.1 s of every UI script. They are compiled together,
# cached as %LOCALAPPDATA%\AgentUi\AgentCursor.Native.<hash of the source>.dll (AGENTUI_CACHE_DIR overrides the
# folder) and loaded from there next time. If the cache cannot be written or loaded (a locked-down machine, a
# read-only profile) they are compiled in memory as before; AGENTUI_NO_NATIVE_CACHE=1 forces that.
$script:AgentNativeSource = @'
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


public static class AgentForegroundNative {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int cmd);
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
}


public static class AgentUserActivityNative {
    [StructLayout(LayoutKind.Sequential)] public struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
    [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO info);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int vKey);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct GUITHREADINFO {
        public uint cbSize; public uint flags; public IntPtr hwndActive; public IntPtr hwndFocus; public IntPtr hwndCapture;
        public IntPtr hwndMenuOwner; public IntPtr hwndMoveSize; public IntPtr hwndCaret; public RECT rcCaret;
    }
    [DllImport("user32.dll")] static extern bool GetGUIThreadInfo(uint idThread, ref GUITHREADINFO info);
    [DllImport("shell32.dll")] static extern int SHQueryUserNotificationState(out int state);

    // GUITHREADINFO.flags of the foreground thread: 0x2 move or size in progress, 0x4 menu mode, 0x10 popup menu.
    public static uint ForegroundGuiFlags() {
        GUITHREADINFO info = new GUITHREADINFO();
        info.cbSize = (uint)Marshal.SizeOf(typeof(GUITHREADINFO));
        return GetGUIThreadInfo(0, ref info) ? info.flags : 0;
    }

    // QUERY_USER_NOTIFICATION_STATE as an int (1 not present ... 5 accepts notifications ... 7 app), 0 when unreadable.
    public static int NotificationState() {
        int state;
        return SHQueryUserNotificationState(out state) == 0 ? state : 0;
    }

    // True while the physical key or button is held down. GetAsyncKeyState reports physical state, so a
    // swapped-button setting does not matter as long as every mouse button is checked.
    public static bool IsDown(int vKey) { return (GetAsyncKeyState(vKey) & 0x8000) != 0; }

    // True while the key or button is down, or if it was pressed since this process last asked (the low bit):
    // a quick click that is over between two polls is still seen.
    public static bool DownOrPressed(int vKey) { return (GetAsyncKeyState(vKey) & 0x8001) != 0; }

    // Tick count of the last keyboard or mouse input in this session (0 when it cannot be read).
    public static uint LastInputTick() {
        LASTINPUTINFO info = new LASTINPUTINFO();
        info.cbSize = (uint)Marshal.SizeOf(typeof(LASTINPUTINFO));
        return GetLastInputInfo(ref info) ? info.dwTime : 0;
    }

    // Milliseconds since that input, or -1 when it cannot be read.
    public static long IdleMs() {
        uint last = LastInputTick();
        if (last == 0) return -1;
        return unchecked((uint)Environment.TickCount - last);
    }
}
// Process ids and start times without a WMI query (a Win32_Process snapshot cost 0.6 to 0.9 s).
public static class AgentProcessNative {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct PROCESSENTRY32 {
        public uint dwSize; public uint cntUsage; public uint th32ProcessID; public UIntPtr th32DefaultHeapID;
        public uint th32ModuleID; public uint cntThreads; public uint th32ParentProcessID; public int pcPriClassBase;
        public uint dwFlags; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string szExeFile;
    }
    [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr CreateToolhelp32Snapshot(uint flags, uint pid);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern bool Process32First(IntPtr s, ref PROCESSENTRY32 e);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern bool Process32Next(IntPtr s, ref PROCESSENTRY32 e);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
    [DllImport("kernel32.dll")] static extern bool GetProcessTimes(IntPtr h, out long create, out long exit, out long kernel, out long user);

    // Flat array: process id, parent process id, process id, parent process id, ... Null when the snapshot fails.
    public static int[] ParentPairs() {
        IntPtr snap = CreateToolhelp32Snapshot(0x2, 0);
        if (snap == IntPtr.Zero || snap == new IntPtr(-1)) return null;
        try {
            var list = new System.Collections.Generic.List<int>();
            var e = new PROCESSENTRY32(); e.dwSize = (uint)Marshal.SizeOf(typeof(PROCESSENTRY32));
            if (!Process32First(snap, ref e)) return null;
            do { list.Add((int)e.th32ProcessID); list.Add((int)e.th32ParentProcessID); } while (Process32Next(snap, ref e));
            return list.ToArray();
        } finally { CloseHandle(snap); }
    }

    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [ComImport, Guid("a5cd92ff-29be-454c-8d04-d82879fb3f1b"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IVirtualDesktopManager { [PreserveSig] int IsWindowOnCurrentVirtualDesktop(IntPtr h, out bool on); }
    [ComImport, Guid("aa509086-5ca9-4c25-8f95-589d3c07b48a")] class VirtualDesktopManagerClass { }

    // The process that owns a window, or 0 when the handle is not a window.
    public static int WindowProcessId(IntPtr h) {
        if (h == IntPtr.Zero || !IsWindow(h)) return 0;
        uint pid; GetWindowThreadProcessId(h, out pid);
        return (int)pid;
    }

    // True when the window exists and is not on the virtual desktop the person is looking at.
    public static bool IsOnOtherDesktop(IntPtr h) {
        if (!IsWindow(h)) return false;
        bool on;
        int hr = ((IVirtualDesktopManager)new VirtualDesktopManagerClass()).IsWindowOnCurrentVirtualDesktop(h, out on);
        return hr == 0 && !on;
    }
    // Process creation time (FILETIME ticks), or 0 when it cannot be read.
    public static long StartTime(int pid) {
        IntPtr h = OpenProcess(0x1000, false, (uint)pid);
        if (h == IntPtr.Zero) return 0;
        try { long c, x, k, u; return GetProcessTimes(h, out c, out x, out k, out u) ? c : 0; } finally { CloseHandle(h); }
    }
}
'@

function Initialize-AgentNative {
    $names = 'AgentCursorNativeV2', 'AgentForegroundNative', 'AgentUserActivityNative', 'AgentProcessNative'
    if (-not @($names | Where-Object { -not ($_ -as [type]) })) { return }
    Add-Type -AssemblyName System.Drawing
    if (-not $env:AGENTUI_NO_NATIVE_CACHE) {
        try {
            $hash = ([BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($script:AgentNativeSource))) -replace '-', '').Substring(0, 12)
            $dir = if ($env:AGENTUI_CACHE_DIR) { $env:AGENTUI_CACHE_DIR } else { Join-Path $env:LOCALAPPDATA 'AgentUi' }
            $dll = Join-Path $dir "AgentCursor.Native.$hash.dll"
            if (-not (Test-Path -LiteralPath $dll)) {
                New-Item -ItemType Directory -Force -Path $dir | Out-Null
                $tmp = Join-Path $dir "AgentCursor.Native.$hash.$PID.tmp.dll"
                Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition $script:AgentNativeSource -OutputAssembly $tmp
                # Several agents may start together: publish with one rename; the loser just discards its copy.
                try { Move-Item -LiteralPath $tmp -Destination $dll -ErrorAction Stop } catch { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
            }
            if (@($names | Where-Object { -not ($_ -as [type]) })) { Add-Type -Path $dll }
        }
        catch { }
    }
    if (@($names | Where-Object { -not ($_ -as [type]) })) {
        Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition $script:AgentNativeSource
    }
}
Initialize-AgentNative

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
    param([ValidateSet('Input', 'Waiting', 'Orchestrator', 'UiAutomation')][string]$Mode)
    $ok = switch ($Mode) {
        'Input'        { [AgentCursorNativeV2]::Mark(230, 30, 30) }
        'Waiting'      { [AgentCursorNativeV2]::Mark(240, 170, 0) }
        'Orchestrator' { [AgentCursorNativeV2]::Mark(30, 110, 230) }
        'UiAutomation' { [AgentCursorNativeV2]::Mark(30, 170, 70) }
    }
    if (-not $ok) { Write-Warning "Could not set the $Mode cursor indicator; continuing without it." }
}

function Enable-AgentCursor {
    [CmdletBinding()]
    param(
        # Session means the active session's colour (blue if none is active). Waiting (amber) means the
        # agent wants the keyboard or mouse and is waiting for the person to pause; it is not acting yet.
        [ValidateSet('Input', 'Waiting', 'Session', 'Orchestrator', 'UiAutomation')]
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
        # Poll instead of a fixed 300 ms sleep: the switch normally lands within a few tens of ms. A first try that Windows
        # refused (common when giving the person's window back) is not waited on for long; the Alt-tap retry follows.
        $polls = if ($i -eq 1) { 6 } else { 12 }
        for ($wait = 0; $wait -lt $polls -and [AgentForegroundNative]::GetForegroundWindow() -ne $Handle; $wait++) { Start-Sleep -Milliseconds 25 }
    }
    return ([AgentForegroundNative]::GetForegroundWindow() -eq $Handle)
}



# ---- Be considerate of a person using the machine -----------------------------------------------
# The helpers below let an input script wait for a quiet moment before it takes the foreground, notice
# input that arrives while it works, and give the person's window, focused control and pointer back.
# Real keyboard and mouse input is detected with GetLastInputInfo; no hook is installed and no key is
# recorded. GetLastInputInfo also counts input this process injects, so read the stamp again after each
# of your own input actions and compare it before the next one.

# Small wrappers so the logic below can be tested without touching the keyboard.
function Get-AgentUserIdleMilliseconds { return [AgentUserActivityNative]::IdleMs() }

function Get-AgentInputStamp { return [AgentUserActivityNative]::LastInputTick() }

# True while a mouse button is down, or if one was pressed since the last look (a quick click is still seen).
function Test-AgentMouseButtonPressed {
    foreach ($button in 0x01, 0x02, 0x04, 0x05, 0x06) { if ([AgentUserActivityNative]::DownOrPressed($button)) { return $true } }
    return $false
}

# $true when the person has typed, clicked or scrolled since the mark (-Stamp from Get-AgentInputStamp and -Point
# from Get-AgentPointerPosition, both read at the same moment). Moving the pointer does not count, whatever the
# distance: people move the mouse for many reasons and that alone is not using it, and a pointer that jitters
# would otherwise keep every wait going. A change with the pointer unchanged (a key, a click on the spot, a
# scroll) counts, and so does any button press. Without -Point any change counts.
function Test-AgentMeaningfulInputSince {
    param(
        [Parameter(Mandatory)][uint32]$Stamp,
        $Point
    )
    if ((Get-AgentInputStamp) -eq $Stamp) { return $false }
    if ($Point) {
        $now = Get-AgentPointerPosition
        if (($now.X -ne $Point.X -or $now.Y -ne $Point.Y) -and -not (Test-AgentMouseButtonPressed)) { return $false }
    }
    return $true
}

function Get-AgentForegroundHandle { return [AgentForegroundNative]::GetForegroundWindow() }

function Test-AgentWindowExists { param([IntPtr]$Handle) return [AgentUserActivityNative]::IsWindow($Handle) }

# One short, soft system sound from the person's own Windows sound scheme; no files, no custom audio.
function Invoke-AgentCueSound { try { [System.Media.SystemSounds]::Asterisk.Play() } catch { } }

# The amber dot on the cursor plus one short sound: the agent wants a turn and is waiting for the person to
# pause. The dot is replaced by the red Input dot when the agent starts to act and cleared (back to the session
# colour or the person's own cursors) when the wait ends.
function Show-AgentWaitingCue { Enable-AgentCursor -Mode Waiting -LeadMilliseconds 0; Invoke-AgentCueSound }

function Hide-AgentWaitingCue { Restore-AgentCursor }

# A longer wait: ask the person to pause. Spoken only when the caller says speech is on for this chat (the
# read-aloud skill's Speak-Text.ps1); otherwise the short sound is repeated once.
function Request-AgentUserPause {
    param([switch]$Speak, [string]$Text = 'I need a few seconds of keyboard quiet to send a message to the agent. Please pause typing.')
    $speaker = Join-Path $env:USERPROFILE '.copilot\skills\read-aloud\scripts\Speak-Text.ps1'
    if ($Speak -and (Test-Path -LiteralPath $speaker)) { try { [void](& $speaker -Text $Text) } catch { Invoke-AgentCueSound } }
    else { Invoke-AgentCueSound }
}

# ---- Do not disturb: presenting, full screen, quiet time, a locked session, a menu or drag in progress, or a
# manual pause. SHQueryUserNotificationState is the supported Windows signal; it reports full-screen apps,
# Windows presentation settings, Focus assist (quiet time) and a locked or screen-saver session, but not an
# ordinary window shared in a meeting, which is what the manual pause is for.
function Get-AgentPausePath { return (Join-Path $env:USERPROFILE '.copilot\ui-pause.flag') }

function Get-AgentNotificationState { return [AgentUserActivityNative]::NotificationState() }

function Get-AgentForegroundGuiFlags { return [AgentUserActivityNative]::ForegroundGuiFlags() }

# Pause every UI input script for -Minutes (default 60) by writing the manual pause marker; Clear-AgentUiPause removes it.
function Set-AgentUiPause {
    [CmdletBinding()]
    param([ValidateRange(1, 1440)][int]$Minutes = 60)
    $path = Get-AgentPausePath
    New-Item -ItemType Directory -Force -Path (Split-Path $path) | Out-Null
    [IO.File]::WriteAllText($path, "until=$((Get-Date).AddMinutes($Minutes).ToUniversalTime().ToString('o'))", [Text.Encoding]::ASCII)
}

function Clear-AgentUiPause { Remove-Item -LiteralPath (Get-AgentPausePath) -ErrorAction SilentlyContinue }

# Returns why the person should not be disturbed, or $null. Order: manual pause, Windows state, menu or drag.
function Get-AgentDoNotDisturbReason {
    $path = Get-AgentPausePath
    if (Test-Path -LiteralPath $path) {
        $until = $null
        try {
            $text = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
            if ($text -match 'until=(\S+)') { $until = [datetime]::Parse($Matches[1], [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind) }
        }
        catch { }
        $now = if ($until -and $until.Kind -eq [DateTimeKind]::Utc) { (Get-Date).ToUniversalTime() } else { Get-Date }
        if ($null -eq $until -or $now -lt $until) { return 'ManualPause' }
    }
    switch ([int](Get-AgentNotificationState)) {
        1 { return 'SessionNotPresent' }
        2 { return 'FullScreenOrPresenting' }
        3 { return 'FullScreenGame' }
        4 { return 'PresentationMode' }
        6 { return 'QuietTime' }
        7 { return 'FullScreenApp' }
    }
    if (([uint32](Get-AgentForegroundGuiFlags)) -band 0x16) { return 'MenuOrDragInProgress' }
    return $null
}

# ---- One UI block at a time per session, and a shared "my own last input" stamp --------------------------
# Several orchestrators may run at once. A named mutex serialises their input blocks (quiet wait, input,
# hand-back). GetLastInputInfo also counts input an orchestrator injects, so each block records the stamp after
# its last action; the next block that finds the same stamp knows nobody else has touched the keyboard or mouse
# since, and does not wait for input that was never the person's.
function Enter-AgentUiLock {
    param(
        [ValidateRange(0, 3600000)][int]$TimeoutMilliseconds = 300000,
        [string]$Name = 'Local\AgentUiInputLock'
    )
    $mutex = New-Object System.Threading.Mutex($false, $Name)
    $got = $false
    try { $got = $mutex.WaitOne($TimeoutMilliseconds) } catch [System.Threading.AbandonedMutexException] { $got = $true }
    if (-not $got) { $mutex.Dispose(); return $null }
    return $mutex
}

function Exit-AgentUiLock {
    param($Lock)
    if ($Lock) { try { $Lock.ReleaseMutex() } catch { }; $Lock.Dispose() }
}

function Get-AgentOwnStampPath { return (Join-Path $env:LOCALAPPDATA 'AgentUi\own-input.stamp') }

function Set-AgentOwnInputStamp {
    try {
        $path = Get-AgentOwnStampPath
        New-Item -ItemType Directory -Force -Path (Split-Path $path) | Out-Null
        [IO.File]::WriteAllText($path, [string](Get-AgentInputStamp), [Text.Encoding]::ASCII)
    }
    catch { }
}

# $true when the last input of the session is the one this machine's agents recorded: nobody else has used the
# keyboard or mouse since.
function Test-AgentNoUserInputSinceOwn {
    try {
        $path = Get-AgentOwnStampPath
        if (-not (Test-Path -LiteralPath $path)) { return $false }
        $now = [string](Get-AgentInputStamp)
        return ($now -ne '0' -and ([IO.File]::ReadAllText($path).Trim() -ceq $now))
    }
    catch { return $false }
}

# Names what the person is holding right now, or $null when nothing is held. A held mouse button usually
# means a drag, a text selection or a resize in progress; it produces no new input event while held, so the
# idle time cannot see it. A held modifier changes what an injected click or key would mean.
function Get-AgentInputInUse {
    foreach ($button in 0x01, 0x02, 0x04, 0x05, 0x06) { if ([AgentUserActivityNative]::IsDown($button)) { return 'MouseButton' } }
    foreach ($modifier in 0x10, 0x11, 0x12, 0x5B, 0x5C) { if ([AgentUserActivityNative]::IsDown($modifier)) { return 'Modifier' } }
    return $null
}

function Get-AgentPointerPosition {
    $point = New-Object AgentUserActivityNative+POINT
    [void][AgentUserActivityNative]::GetCursorPos([ref]$point)
    return [pscustomobject]@{ X = $point.X; Y = $point.Y }
}

function Set-AgentPointerPosition { param([int]$X, [int]$Y) [void][AgentUserActivityNative]::SetCursorPos($X, $Y) }

# $true when the focused control of the foreground application holds text: a person may be mid-sentence.
# Only the presence of text is read, never the text itself. Unreadable counts as no draft.
function Test-AgentForegroundDraft {
    try {
        Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
        $element = [System.Windows.Automation.AutomationElement]::FocusedElement
        if (-not $element) { return $false }
        $type = $element.Current.ControlType
        if ($type -ne [System.Windows.Automation.ControlType]::Edit -and $type -ne [System.Windows.Automation.ControlType]::Document) { return $false }
        $pattern = $null
        if ($element.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$pattern)) { return ([string]$pattern.Current.Value).Length -gt 0 }
        if ($element.TryGetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern, [ref]$pattern)) { return $pattern.DocumentRange.GetText(1).Length -gt 0 }
    }
    catch { }
    return $false
}

function Wait-AgentUserQuiet {
    <#
    .SYNOPSIS
        Waits until it is safe to take the foreground: the person has not used the keyboard or mouse for a few
        seconds, holds no mouse button or modifier, and is not presenting. Returns Quiet, WaitedMilliseconds,
        Reason, InUse, CueShown.
    .DESCRIPTION
        Idle for at least -QuietMilliseconds (default 3000) is required, or -DraftQuietMilliseconds (default
        6000) while the focused control of the foreground application holds text. Each time the person types
        again the wait restarts from their last input. A held mouse button or modifier key blocks the wait
        however long ago the last input was, because holding produces no new input event. A do-not-disturb
        state (manual pause, full screen or presenting, Focus assist, a menu or drag in progress) also blocks it;
        a locked or absent session returns SessionNotPresent at once, since nothing can be done there.
        If no one but this machine's agents has used the keyboard or mouse since the last agent input block
        (Set-AgentOwnInputStamp), the idle wait is skipped (Reason OwnInputOnly). An idle time that cannot be
        read lets the caller proceed (IdleUnknown). After -MaxWaitMilliseconds (default 120000) it gives up
        with Quiet false and Reason UserActive or DoNotDisturb; the caller must not take the foreground.
        After about half a second of waiting the cursor shows the amber dot and one short sound plays. After
        -RequestAfterMilliseconds (default 30000) the person is asked once to pause: spoken with -SpeakRequest
        (use it only when speech is on in this chat), otherwise the sound repeats. When the person has already
        been idle long enough it returns at once; the check costs microseconds.
    #>
    [CmdletBinding()]
    param(
        [ValidateRange(0, 600000)][int]$QuietMilliseconds = 3000,
        [ValidateRange(0, 600000)][int]$DraftQuietMilliseconds = 6000,
        [ValidateRange(0, 3600000)][int]$MaxWaitMilliseconds = 120000,
        [ValidateRange(10, 5000)][int]$PollMilliseconds = 100,
        [ValidateRange(0, 60000)][int]$CueAfterMilliseconds = 500,
        [switch]$NoCue,
        [ValidateRange(0, 3600000)][int]$RequestAfterMilliseconds = 30000,
        [switch]$SpeakRequest,
        [string]$RequestText,
        [switch]$IgnoreDoNotDisturb
    )
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $cueShown = $false
    $requested = $false
    $stampSeen = Get-AgentInputStamp
    $posSeen = Get-AgentPointerPosition
    $movementOnlySeen = $false
    $startIdle = Get-AgentUserIdleMilliseconds
    $meaningfulAt = -[Math]::Max(0, $startIdle)
    function New-QuietResult([bool]$Quiet, [string]$Reason, $InUse) {
        [pscustomobject]@{ Quiet = $Quiet; WaitedMilliseconds = [int]$clock.ElapsedMilliseconds; Reason = $Reason; InUse = $InUse; CueShown = $cueShown }
    }
    try {
        while ($true) {
            $dnd = if ($IgnoreDoNotDisturb) { $null } else { Get-AgentDoNotDisturbReason }
            if ($dnd -eq 'SessionNotPresent') { return (New-QuietResult $false 'SessionNotPresent' $dnd) }
            $held = Get-AgentInputInUse
            $idle = Get-AgentUserIdleMilliseconds
            # An input event that came with the pointer moving and no button pressed is only the mouse being
            # moved: it does not mean the person is using it. Keep counting idle time from the last meaningful
            # input (typing, a click, scrolling) instead of from that event.
            if ($idle -ge 0) {
                $stampNow = Get-AgentInputStamp
                $clicked = Test-AgentMouseButtonPressed
                if ($stampNow -ne $stampSeen -or $clicked) {
                    $posNow = Get-AgentPointerPosition
                    $moved = ($posNow.X -ne $posSeen.X -or $posNow.Y -ne $posSeen.Y)
                    if ($moved -and -not $clicked) { $movementOnlySeen = $true }
                    else { $meaningfulAt = $clock.ElapsedMilliseconds - $(if ($clicked) { 0 } else { $idle }) }
                    $stampSeen = $stampNow; $posSeen = $posNow
                }
                if ($movementOnlySeen) { $idle = [Math]::Max($idle, [int]($clock.ElapsedMilliseconds - $meaningfulAt)) }
            }
            if (-not $dnd -and -not $held) {
                if (Test-AgentNoUserInputSinceOwn) { return (New-QuietResult $true 'OwnInputOnly' $null) }
                if ($idle -lt 0) { return (New-QuietResult $true 'IdleUnknown' $null) }
                $needed = $QuietMilliseconds
                if ($idle -lt $DraftQuietMilliseconds -and $DraftQuietMilliseconds -gt $QuietMilliseconds -and (Test-AgentForegroundDraft)) { $needed = $DraftQuietMilliseconds }
                if ($idle -ge $needed) { return (New-QuietResult $true 'Idle' $null) }
            }
            if ($clock.ElapsedMilliseconds -ge $MaxWaitMilliseconds) {
                if ($dnd) { return (New-QuietResult $false 'DoNotDisturb' $dnd) }
                return (New-QuietResult $false 'UserActive' $held)
            }
            if (-not $NoCue -and -not $cueShown -and $clock.ElapsedMilliseconds -ge $CueAfterMilliseconds) { Show-AgentWaitingCue; $cueShown = $true }
            if (-not $NoCue -and -not $requested -and $RequestAfterMilliseconds -gt 0 -and $clock.ElapsedMilliseconds -ge $RequestAfterMilliseconds) {
                $requested = $true
                if ($RequestText) { Request-AgentUserPause -Speak:$SpeakRequest -Text $RequestText } else { Request-AgentUserPause -Speak:$SpeakRequest }
            }
            $sleep = $PollMilliseconds
            if (-not $dnd -and -not $held -and $idle -ge 0) { $sleep = [Math]::Min($PollMilliseconds, [Math]::Max(10, [int]($QuietMilliseconds - $idle))) }
            Start-Sleep -Milliseconds $sleep
        }
    }
    finally { if ($cueShown) { Hide-AgentWaitingCue } }
}

# Remembers where the person was: foreground window, focused control and pointer. Call it before the first
# foreground change.
function Save-AgentUserFocus {
    [CmdletBinding()]
    param()
    $point = Get-AgentPointerPosition
    $focused = $null
    try { Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes; $focused = [System.Windows.Automation.AutomationElement]::FocusedElement } catch { }
    return [pscustomobject]@{ Foreground = (Get-AgentForegroundHandle); Focused = $focused; CursorX = $point.X; CursorY = $point.Y }
}

function Test-AgentFocusedElementIs {
    param($Element)
    try {
        $now = [System.Windows.Automation.AutomationElement]::FocusedElement
        if (-not $now -or -not $Element) { return $false }
        return ((@($now.GetRuntimeId()) -join '.') -ceq (@($Element.GetRuntimeId()) -join '.'))
    }
    catch { return $false }
}

function Restore-AgentUserFocus {
    <#
    .SYNOPSIS
        Gives the person's window, focused control and pointer back after an automated input block.
    .DESCRIPTION
        -OwnStamp is Get-AgentInputStamp read right after the caller's last input action. If the stamp has
        changed, the person has used the keyboard or mouse since, and nothing is restored (Restored false,
        Reason UserInput): their own action wins. Otherwise the saved window is brought forward, the saved
        control gets focus if it does not already have it, and the pointer is put back. Returns Restored,
        Foreground, Focus, Pointer and Reason; failures are reported, never thrown.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][uint32]$OwnStamp,
        # The pointer position read with -OwnStamp. With it, input that came only with the pointer moving (no
        # key, no button) does not count as the person using the keyboard or mouse.
        $OwnPoint,
        # The window the agent took the foreground for. If the person used the keyboard while that window was
        # still in front, their input went to the wrong window, so their own window is given back at once (the
        # pointer is left alone). If they have moved to another window themselves, nothing is changed.
        [IntPtr]$HeldHandle = [IntPtr]::Zero
    )
    $result = [pscustomobject]@{ Restored = $false; Foreground = $false; Focus = $false; Pointer = $false; Reason = '' }
    try {
        if ($null -eq $Context -or $Context.Foreground -eq [IntPtr]::Zero) { $result.Reason = 'NothingSaved'; return $result }
        $userInput = if ($OwnPoint) { Test-AgentMeaningfulInputSince -Stamp $OwnStamp -Point $OwnPoint } else { (Get-AgentInputStamp) -ne $OwnStamp }
        if ($userInput -and ($HeldHandle -eq [IntPtr]::Zero -or (Get-AgentForegroundHandle) -ne $HeldHandle)) { $result.Reason = 'UserInput'; return $result }
        # A button or modifier held since before this block gives no new event; do not move the pointer or switch windows under it.
        $held = Get-AgentInputInUse
        if ($held) { $result.Reason = "${held}InUse"; return $result }
        if (-not (Test-AgentWindowExists -Handle $Context.Foreground)) { $result.Reason = 'WindowGone'; return $result }
        if ((Get-AgentForegroundHandle) -eq $Context.Foreground) { $result.Foreground = $true }
        else { $result.Foreground = [bool](Set-AgentForegroundWindow -Handle $Context.Foreground) }
        if ($Context.Focused) {
            if (Test-AgentFocusedElementIs -Element $Context.Focused) { $result.Focus = $true }
            else {
                try { $Context.Focused.SetFocus() } catch { }
                $result.Focus = [bool](Test-AgentFocusedElementIs -Element $Context.Focused)
            }
        }
        else { $result.Focus = $true }
        if (-not $userInput) {
            # The stamp was unchanged, so the pointer is still where the automation left it.
            Set-AgentPointerPosition -X ([int]$Context.CursorX) -Y ([int]$Context.CursorY)
            $point = Get-AgentPointerPosition
            $result.Pointer = ([Math]::Abs($point.X - $Context.CursorX) -le 2 -and [Math]::Abs($point.Y - $Context.CursorY) -le 2)
        }
        $result.Restored = ($result.Foreground -and $result.Focus)
        $result.Reason = if ($result.Restored) { if ($userInput) { 'RestoredAfterUserInput' } else { 'Restored' } } else { 'NotVerified' }
    }
    catch { $result.Reason = "Error: $($_.Exception.Message)" }
    return $result
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
