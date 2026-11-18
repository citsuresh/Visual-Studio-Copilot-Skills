<#
.SYNOPSIS
    Forwards manual notification calls to the skill's bundled sender.
.DESCRIPTION
    Sends fixed generic text over the network; reads local encrypted credentials.
    Preserves existing parameters, WhatIf behavior and output.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Completed', 'Question', 'Blocker')]
    [string]$Event,
    [string]$TokenPath = (Join-Path $env:USERPROFILE '.copilot\skills\push-notifications\scripts\pushbullet-token.xml'),
    [string]$DeviceId,
    [switch]$Test,
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$')]
    [string]$RepositoryName
)

$ErrorActionPreference = 'Stop'
$PSBoundParameters['TokenPath'] = $TokenPath
& (Join-Path $PSScriptRoot '..\..\push-notifications\scripts\Send-PushbulletNotification.ps1') @PSBoundParameters
