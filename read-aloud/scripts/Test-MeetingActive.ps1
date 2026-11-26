# Purpose: report whether the user is probably in an online meeting, so read-aloud can stay quiet.
# Signal: the Windows privacy ConsentStore (HKCU\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone
# and its NonPackaged subkey). An app is using the microphone now when LastUsedTimeStart is set and LastUsedTimeStop is 0.
# It is a meeting when such an app is NOT in -ExcludeApps (so a conferencing app, a browser, Slack... holds the microphone).
# Prints exactly one line: "Meeting (<app names>)", "NoMeeting" or "Unknown (<reason>)". Exit code is always 0.
# Privacy: reads only registry value names and two timestamps; never window titles, call content, emails or any personal data.
# Read-only: opens no microphone, changes nothing. Fails open: callers treat Unknown like NoMeeting.
# -ExcludeApps: app names (without .exe, wildcards allowed, case-insensitive) that never count as a meeting.
# -EntrySource: testing only; a script block returning objects with Name, LastUsedTimeStart, LastUsedTimeStop instead of the registry.
param(
    [string[]]$ExcludeApps = @('devenv', 'VoiceType*', 'Speak*', 'powershell*', 'pwsh*', 'VsCopilotChatVoice*'),
    [scriptblock]$EntrySource
)

function Get-ConsentEntries {
    $root = 'Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone'
    foreach ($path in @($root, "$root\NonPackaged")) {
        $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($path)
        if (-not $key) { continue }
        try {
            foreach ($name in $key.GetSubKeyNames()) {
                if ($name -eq 'NonPackaged') { continue }
                $sub = $key.OpenSubKey($name)
                if (-not $sub) { continue }
                try {
                    [pscustomobject]@{
                        Name = $name
                        LastUsedTimeStart = $sub.GetValue('LastUsedTimeStart')
                        LastUsedTimeStop = $sub.GetValue('LastUsedTimeStop')
                    }
                }
                finally { $sub.Close() }
            }
        }
        finally { $key.Close() }
    }
}

function ConvertTo-AppName([string]$RegistryName) {
    # NonPackaged names are paths with '#' for '\' (C:#Program Files#...#app.exe); packaged names are Publisher.App_hash.
    $leaf = ($RegistryName -split '[#\/]')[-1]
    if ($RegistryName -notmatch '[#\/]') { $leaf = ($leaf -split '_')[0] }
    $leaf = $leaf -replace '(?i)\.exe$', ''
    $leaf = $leaf -replace '[^A-Za-z0-9 ._-]', ''
    if ($leaf.Length -gt 40) { $leaf = $leaf.Substring(0, 40) }
    return $leaf
}

$result = 'Unknown (unexpected failure)'
try {
    $ErrorActionPreference = 'Stop'
    $entries = if ($EntrySource) { @(& $EntrySource) } else { @(Get-ConsentEntries) }
    $apps = @()
    foreach ($e in $entries) {
        if (-not $e) { continue }
        $start = 0L; $stop = 0L
        if ($null -ne $e.LastUsedTimeStart) { $start = [int64]$e.LastUsedTimeStart }
        if ($null -ne $e.LastUsedTimeStop) { $stop = [int64]$e.LastUsedTimeStop }
        if ($start -le 0 -or $stop -ne 0) { continue }
        $app = ConvertTo-AppName ([string]$e.Name)
        if (-not $app) { continue }
        $excluded = $false
        foreach ($pattern in $ExcludeApps) { if ($app -like $pattern) { $excluded = $true; break } }
        if (-not $excluded -and -not ($apps -contains $app)) { $apps += $app }
    }
    if (@($apps).Count -gt 0) { $result = 'Meeting (' + (($apps | Sort-Object) -join ', ') + ')' }
    else { $result = 'NoMeeting' }
}
catch { $result = 'Unknown (' + $_.Exception.GetType().Name + ')' }
$result
exit 0
