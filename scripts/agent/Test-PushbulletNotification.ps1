<#
.SYNOPSIS
    Runs offline regression checks for the Pushbullet sender.
.DESCRIPTION
    Uses mocked credential loading and HTTP. Never reads real credentials or contacts
    a service. Read-only unless IncludeSetupFixtures is explicitly requested.
.PARAMETER SenderPath
    Sender script to test. Defaults to the script next to this test.
.PARAMETER InitializerPath
    Standalone setup implementation to test when IncludeSetupFixtures is requested.
.PARAMETER IncludeSetupFixtures
    Creates and removes its own temporary dummy credentials and helper copies to test
    first-machine setup. Never uses the real credential location or a real token.
#>
[CmdletBinding()]
param(
    [string]$SenderPath = (Join-Path $PSScriptRoot 'Send-PushbulletNotification.ps1'),
    [string]$InitializerPath = (Join-Path $PSScriptRoot '..\..\push-notifications\scripts\Initialize-Pushbullet.ps1'),
    [switch]$IncludeSetupFixtures
)

$ErrorActionPreference = 'Stop'
$state = @{
    Requests = (New-Object 'System.Collections.Generic.List[object]')
    CredentialReads = 0
    FakeToken = 'offline-test-token-not-a-real-credential'
    PlainCredential = $false
    BadResponse = $false
    FailRequest = $false
}

function Import-Clixml {
    param([string]$LiteralPath)
    $state.CredentialReads++
    if ($state.PlainCredential) { return 'plain-test-value' }
    ConvertTo-SecureString $state.FakeToken -AsPlainText -Force
}

function Invoke-RestMethod {
    param($Uri, $Method, $Headers, $ContentType, $Body, $TimeoutSec)
    if ($Uri -ne 'https://api.pushbullet.com/v2/pushes' -or $Method -ne 'Post' -or
        $ContentType -ne 'application/json' -or $TimeoutSec -ne 30 -or
        $Headers['Access-Token'] -ne $state.FakeToken) {
        throw 'Unexpected mocked transport contract.'
    }
    if ($state.FailRequest) { throw 'Mock transport failure.' }
    $payload = $Body | ConvertFrom-Json
    if ($Body.Contains($state.FakeToken)) { throw 'Credential leaked into payload.' }
    $allowed = @('type', 'title', 'body', 'device_iden')
    if (@($payload.PSObject.Properties.Name | Where-Object { $_ -notin $allowed }).Count) {
        throw 'Unexpected notification payload field.'
    }
    $state.Requests.Add($payload)
    $iden = 'mock-response'
    if ($state.BadResponse) { $iden = '' }
    [pscustomobject]@{ iden = $iden; type = $payload.type; title = $payload.title; body = $payload.body }
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Throws {
    param([scriptblock]$Action, [string]$Expected)
    $failure = $null
    try { & $Action | Out-Null } catch { $failure = $_ }
    Assert-True ($null -ne $failure -and $failure.Exception.Message.Contains($Expected)) `
        "Expected a failure containing: $Expected"
}

$expectedBodies = @{
    Completed = 'A Copilot task has completed.'
    Question = 'A Copilot question needs your attention.'
    Blocker = 'A Copilot task is blocked and needs your attention.'
}
foreach ($eventName in @('Completed', 'Question', 'Blocker')) {
    foreach ($isTest in @($false, $true)) {
        foreach ($withRepository in @($false, $true)) {
            $parameters = @{ Event = $eventName; Test = $isTest; TokenPath = 'mock-credential.xml' }
            $expectedTitle = "Copilot - $eventName"
            $expectedBody = $expectedBodies[$eventName]
            if ($isTest) {
                $expectedTitle = "[TEST] $expectedTitle"
                $expectedBody = "Generic $eventName notification test. No action is required."
            }
            if ($withRepository) {
                $parameters.RepositoryName = 'Public-Repo'
                $expectedBody = "Public-Repo: $expectedBody"
            }
            $result = & $SenderPath @parameters
            $payload = $state.Requests[$state.Requests.Count - 1]
            Assert-True ($payload.type -eq 'note' -and $payload.title -ceq $expectedTitle -and
                $payload.body -ceq $expectedBody) 'Fixed notification text or stable title changed.'
            Assert-True ($result.ServerAccepted -eq $true -and $result.PhoneDelivery -eq 'Unverified') `
                'Acceptance must not imply phone delivery.'
        }
    }
}
Assert-True ($state.Requests.Count -eq 12) 'Expected twelve payload combinations.'

$null = & $SenderPath -Event Completed -DeviceId 'mock-device' -TokenPath 'mock-credential.xml'
Assert-True ($state.Requests[12].device_iden -eq 'mock-device') 'Explicit device routing changed.'
$reads = $state.CredentialReads
$requests = $state.Requests.Count
& $SenderPath -Event Completed -TokenPath 'must-not-be-read.xml' -WhatIf
Assert-True ($state.CredentialReads -eq $reads -and $state.Requests.Count -eq $requests) `
    'WhatIf must not load a credential or send a notification.'

Assert-Throws { & $SenderPath -Event Completed -RepositoryName 'C:\private\repo' } 'RepositoryName'
Assert-Throws { & $SenderPath -Event Completed -RepositoryName "repo`nprivate" } 'RepositoryName'
Assert-True ($state.Requests.Count -eq $requests) 'Invalid names must not send requests.'
$state.PlainCredential = $true
Assert-Throws { & $SenderPath -Event Completed -TokenPath 'mock-credential.xml' } 'encrypted SecureString'
$state.PlainCredential = $false
$state.BadResponse = $true
Assert-Throws { & $SenderPath -Event Completed -TokenPath 'mock-credential.xml' } 'unexpected response'
$state.BadResponse = $false
$state.FailRequest = $true
Assert-Throws { & $SenderPath -Event Completed -TokenPath 'mock-credential.xml' } 'Mock transport failure'

if ($IncludeSetupFixtures) {
    $state.SetupPrompts = 0
    $state.EmptySetupToken = $false
    function Read-Host {
        param([string]$Prompt, [switch]$AsSecureString)
        Assert-True ([bool]$AsSecureString) 'Setup must use a masked secure-string prompt.'
        $state.SetupPrompts++
        if ($state.EmptySetupToken) { return (New-Object System.Security.SecureString) }
        ConvertTo-SecureString $state.FakeToken -AsPlainText -Force
    }
    $fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('pushbullet-setup-test-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $fixtureRoot
    try {
        $fixtureToken = Join-Path $fixtureRoot 'fresh\pushbullet-token.xml'
        & $InitializerPath -TokenPath $fixtureToken | Out-Null
        $fixtureHelper = Join-Path $fixtureRoot 'fresh\Initialize-Pushbullet.ps1'
        Assert-True (Test-Path -LiteralPath $fixtureToken -PathType Leaf) 'Fresh setup must create XML.'
        Assert-True ((Get-FileHash -LiteralPath $fixtureHelper).Hash -eq
            (Get-FileHash -LiteralPath $InitializerPath).Hash) 'Setup helper must be beside the XML and match its source.'
        $saved = Microsoft.PowerShell.Utility\Import-Clixml -LiteralPath $fixtureToken
        try {
            Assert-True ($saved -is [Security.SecureString]) 'Credential XML must contain a SecureString.'
            $roundTrip = New-Object System.Management.Automation.PSCredential('offline-test', $saved)
            Assert-True ($roundTrip.GetNetworkCredential().Password -ceq $state.FakeToken) 'Encrypted credential round trip failed.'
            Assert-True (-not [IO.File]::ReadAllText($fixtureToken).Contains($state.FakeToken)) 'A plaintext token was written to XML.'
        }
        finally {
            $roundTrip = $null
            if ($saved -is [Security.SecureString]) { $saved.Dispose() }
        }
        $beforeHash = (Get-FileHash -LiteralPath $fixtureToken).Hash
        & $InitializerPath -TokenPath $fixtureToken | Out-Null
        Assert-True ($state.SetupPrompts -eq 1 -and
            (Get-FileHash -LiteralPath $fixtureToken).Hash -eq $beforeHash) 'Existing credentials must not be prompted for or overwritten.'

        $state.EmptySetupToken = $true
        $emptyToken = Join-Path $fixtureRoot 'empty\pushbullet-token.xml'
        Assert-Throws { & $InitializerPath -TokenPath $emptyToken } 'empty token'
        Assert-True (-not (Test-Path -LiteralPath $emptyToken)) 'An empty token must not create XML.'
        $conflictDirectory = Join-Path $fixtureRoot 'conflict'
        $null = New-Item -ItemType Directory -Path $conflictDirectory
        $conflictingHelper = Join-Path $conflictDirectory 'Initialize-Pushbullet.ps1'
        [IO.File]::WriteAllText($conflictingHelper, 'existing-local-helper')
        Assert-Throws { & $InitializerPath -TokenPath (Join-Path $conflictDirectory 'pushbullet-token.xml') } 'different local setup helper'
        Assert-True ([IO.File]::ReadAllText($conflictingHelper) -ceq 'existing-local-helper') 'A differing helper must not be overwritten.'
        Write-Output 'PASS: fresh encrypted setup, nearby helper, no credential overwrite, empty-token and helper-conflict checks.'
    }
    finally {
        $resolvedFixture = (Resolve-Path -LiteralPath $fixtureRoot).Path
        Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
    }
}

Write-Output 'PASS: offline payload, prefix, credential, validation, error and WhatIf regression checks.'