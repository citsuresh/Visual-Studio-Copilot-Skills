<#
.SYNOPSIS
    Sends a generic Copilot status notification through Pushbullet.
.DESCRIPTION
    Reads a Windows-user-encrypted SecureString credential file and sends a network
    request. Only fixed generic text and an optional approved repository label enter
    the notification. Does not modify local files or accept arbitrary message text.
    Server acceptance does not confirm phone delivery or Android channel support.
.PARAMETER Event
    Completed, Question or Blocker. Notification text is deliberately generic.
.PARAMETER TokenPath
    SecureString XML file created by Read-Host -AsSecureString | Export-Clixml.
.PARAMETER DeviceId
    Optional Pushbullet device identifier. Omit to notify all linked devices.
.PARAMETER Test
    Marks the notification as a test that requires no action.
.PARAMETER RepositoryName
    Optional user-approved, non-sensitive repository name to prefix the message body.
    Never supply a path, secret or confidential repository name.
.EXAMPLE
    .\scripts\agent\Send-PushbulletNotification.ps1 -Event Completed -Test
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Completed', 'Question', 'Blocker')]
    [string]$Event,

    [string]$TokenPath = (Join-Path $env:USERPROFILE '.copilot\pushbullet-token.xml'),

    [string]$DeviceId,

    [switch]$Test,

    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$')]
    [string]$RepositoryName
)

$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') {
    throw 'The encrypted credential file requires Windows and the user account that created it.'
}

$messages = @{
    Completed = 'A Copilot task has completed.'
    Question = 'A Copilot question needs your attention.'
    Blocker = 'A Copilot task is blocked and needs your attention.'
}
$title = "Copilot - $Event"
$body = $messages[$Event]
if ($Test) {
    $title = "[TEST] $title"
    $body = "Generic $Event notification test. No action is required."
}
if ($RepositoryName) {
    $body = "${RepositoryName}: $body"
}
$payload = @{ type = 'note'; title = $title; body = $body }
$target = 'Pushbullet account (all linked devices)'
if ($DeviceId) {
    $payload.device_iden = $DeviceId
    $target = 'Selected Pushbullet device'
}
if (-not $PSCmdlet.ShouldProcess($target, "Send $title")) {
    return
}

$secret = Import-Clixml -LiteralPath $TokenPath
if ($secret -isnot [System.Security.SecureString]) {
    throw 'The credential file must contain an encrypted SecureString, not a plain token string.'
}

$headers = @{}
$credential = $null
try {
    $credential = New-Object System.Management.Automation.PSCredential('Pushbullet', $secret)
    $headers['Access-Token'] = $credential.GetNetworkCredential().Password
    $response = Invoke-RestMethod -Uri 'https://api.pushbullet.com/v2/pushes' -Method Post `
        -Headers $headers -ContentType 'application/json' -Body ($payload | ConvertTo-Json -Compress) `
        -TimeoutSec 30
    if ([string]::IsNullOrWhiteSpace($response.iden) -or $response.type -ne 'note' -or
        $response.title -ne $title -or $response.body -ne $body) {
        throw 'Pushbullet returned an unexpected response; notification acceptance is unverified.'
    }
    [pscustomobject]@{
        Event = $Event
        Test = [bool]$Test
        ServerAccepted = $true
        PhoneDelivery = 'Unverified'
    }
}
finally {
    $headers.Clear()
    $credential = $null
    $secret.Dispose()
}