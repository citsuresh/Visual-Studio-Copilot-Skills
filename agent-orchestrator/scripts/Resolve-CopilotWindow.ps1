<#
.SYNOPSIS
    Resolves a Visual Studio window handle from a title substring, for the scripts that take
    -TitleContains.

.DESCRIPTION
    Runs `agentdebug-ui.exe list-windows --all --titleContains <text>` and returns the single
    match. No match gives a plain message, several matches give the candidate list, and a failed
    listing is reported as such; in each case Hwnd is $null and nothing was touched. Same wording
    as Send-CopilotPrompt.ps1. Read-only; it never activates, clicks or types.

.PARAMETER TitleContains
    Title substring (not a wildcard).

.PARAMETER ExePath
    Path to agentdebug-ui.exe.

.OUTPUTS
    PSCustomObject: Hwnd (string such as "0x60AAA", or $null), Error ($null on success).

.EXAMPLE
    $w = .\Resolve-CopilotWindow.ps1 -TitleContains 'MyProject - '
    if ($w.Error) { $w.Error } else { $w.Hwnd }
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TitleContains,

    [string]$ExePath = 'C:\MyFiles\Git\AgentDebugToolkit\src\AgentDebugToolkit.UiAutomation.Cli\bin\Debug\net8.0-windows\agentdebug-ui.exe'
)

$ErrorActionPreference = 'Stop'
# The inherited DOTNET_ROOT from VS breaks agentdebug-ui.exe; always clear it.
Remove-Item Env:DOTNET_ROOT -ErrorAction SilentlyContinue

function New-Resolution {
    param([string]$Hwnd, [string]$ErrorText)
    [pscustomobject]@{ Hwnd = $Hwnd; Error = $ErrorText }
}

if (-not (Test-Path $ExePath)) {
    throw "agentdebug-ui.exe not found at '$ExePath'. Pass -ExePath explicitly."
}

$raw = (& $ExePath list-windows --all --titleContains $TitleContains 2>&1 | Out-String).Trim()
try { $r = $raw | ConvertFrom-Json } catch { $r = [pscustomobject]@{ success = $false; error = 'unparseable-output'; message = $raw } }
if (-not $r.success) {
    return New-Resolution -Hwnd $null -ErrorText "Could not list windows to resolve -TitleContains '$TitleContains': $("$($r.error) $($r.message)".Trim()). Nothing was touched."
}
$candidates = @($r.windows)
if ($candidates.Count -eq 0) {
    return New-Resolution -Hwnd $null -ErrorText "No window title contains '$TitleContains'. Nothing was touched."
}
if ($candidates.Count -gt 1) {
    $list = ($candidates | ForEach-Object { "$($_.Hwnd) '$($_.Title)'" }) -join '; '
    return New-Resolution -Hwnd $null -ErrorText "More than one window title contains '$TitleContains': $list. Pass -Hwnd or a longer -TitleContains. Nothing was touched."
}
New-Resolution -Hwnd ([string]$candidates[0].Hwnd) -ErrorText $null
