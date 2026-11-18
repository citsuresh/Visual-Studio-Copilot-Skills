<#
.SYNOPSIS
    Forwards masked credential setup to the skill's bundled helper.
.DESCRIPTION
    Run in the user's own PowerShell window. May create encrypted XML and a nearby
    standalone setup helper. Sends no network request and accepts no token argument.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$TokenPath = (Join-Path $env:USERPROFILE '.copilot\skills\push-notifications\scripts\pushbullet-token.xml')
)

$ErrorActionPreference = 'Stop'
$PSBoundParameters['TokenPath'] = $TokenPath
& (Join-Path $PSScriptRoot '..\..\push-notifications\scripts\Initialize-Pushbullet.ps1') @PSBoundParameters
