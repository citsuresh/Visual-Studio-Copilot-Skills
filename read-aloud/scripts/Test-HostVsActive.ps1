# Purpose: report whether the Visual Studio (devenv.exe) that hosts this Copilot chat owns the foreground window.
# Finds the host by walking up the parent process chain; -HostPid (a process id) overrides that search, for testing.
# Always prints exactly one word: Active or Inactive (exit 0), or Unknown (exit 3) when there is no host process or anything fails.
# Read-only; changes nothing.
param($HostPid)

$result = 'Unknown'
try {
    $ErrorActionPreference = 'Stop'
    if (-not ('Native.Win' -as [type])) {
        Add-Type -Namespace Native -Name Win -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern System.IntPtr GetForegroundWindow();
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(System.IntPtr hWnd, out uint pid);
'@
    }
    $host_ = $null
    if ($PSBoundParameters.ContainsKey('HostPid')) {
        $id = [int]$HostPid
        if ($id -gt 0 -and (Get-Process -Id $id -ErrorAction SilentlyContinue)) { $host_ = $id }
    }
    else {
        $id = $PID
        for ($i = 0; $i -lt 12 -and $id; $i++) {
            $p = Get-CimInstance Win32_Process -Filter "ProcessId=$id" -ErrorAction SilentlyContinue
            if (-not $p) { break }
            if ($p.Name -ieq 'devenv.exe') { $host_ = $p.ProcessId; break }
            $id = $p.ParentProcessId
        }
    }
    if ($host_) {
        $fg = [Native.Win]::GetForegroundWindow()
        [uint32]$fgPid = 0
        [void][Native.Win]::GetWindowThreadProcessId($fg, [ref]$fgPid)
        if ($fgPid -eq $host_) { $result = 'Active' } else { $result = 'Inactive' }
    }
}
catch { $result = 'Unknown' }

$result
if ($result -eq 'Unknown') { exit 3 }
