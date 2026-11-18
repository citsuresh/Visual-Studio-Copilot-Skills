<#
.SYNOPSIS
    Creates an encrypted Pushbullet credential using a masked interactive prompt.
.DESCRIPTION
    Run in your own PowerShell window, not an agent tool call. Places this setup helper
    beside the XML outside Git. Existing credentials and differing helper copies are
    never overwritten. Does not send notifications or accept a plaintext token argument.
.PARAMETER TokenPath
    Local XML destination. Defaults beside this script, matching the bundled sender.
.EXAMPLE
    .\scripts\agent\Initialize-Pushbullet.ps1
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$TokenPath = (Join-Path $PSScriptRoot 'pushbullet-token.xml')
)

$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') {
    throw 'Credential setup requires Windows; each Windows user/machine must run its own setup.'
}
$destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($TokenPath)
if ([IO.Path]::GetExtension($destination) -ine '.xml') {
    throw 'Choose an XML credential filename outside Git.'
}
$directory = Split-Path -Parent $destination
$setupCopy = Join-Path $directory 'Initialize-Pushbullet.ps1'
for ($ancestor = $directory; $ancestor; $ancestor = Split-Path -Parent $ancestor) {
    if (Test-Path -LiteralPath (Join-Path $ancestor '.git')) {
        throw 'Credential XML must stay outside Git. Choose a per-user location instead.'
    }
}
if (-not $PSCmdlet.ShouldProcess($directory, 'Place setup helper and create credential XML if missing')) {
    return
}

$null = New-Item -ItemType Directory -Path $directory -Force
if (-not [string]::Equals($PSCommandPath, $setupCopy, [StringComparison]::OrdinalIgnoreCase)) {
    if (Test-Path -LiteralPath $setupCopy) {
        $sourceHash = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash
        $copyHash = (Get-FileHash -LiteralPath $setupCopy -Algorithm SHA256).Hash
        if ($sourceHash -ne $copyHash) {
            throw 'A different local setup helper already exists; it and any credential were left unchanged.'
        }
    }
    else {
        [IO.File]::Copy($PSCommandPath, $setupCopy, $false)
    }
}
if (Test-Path -LiteralPath $destination) {
    if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) {
        throw 'The credential destination is not a file; it was left unchanged.'
    }
    Write-Output 'Setup helper is beside the existing credential. The credential was not changed or validated.'
    return
}

Write-Host 'Create an access token at https://www.pushbullet.com/#settings/account.'
Write-Host 'Paste only at the masked prompt below. Do not paste it into chat or create XML manually.'
$secret = $null
try {
    $secret = Read-Host 'Pushbullet access token' -AsSecureString
    if ($null -eq $secret -or $secret.Length -eq 0) {
        throw 'An empty token was not saved. Push notifications are not enabled.'
    }
    $secret | Export-Clixml -LiteralPath $destination -NoClobber
}
finally {
    if ($null -ne $secret) { $secret.Dispose() }
}
Write-Output 'Encrypted XML created. Push notifications are not enabled yet.'
Write-Output 'Return to chat and issue enable push notifications or start push notifications again.'