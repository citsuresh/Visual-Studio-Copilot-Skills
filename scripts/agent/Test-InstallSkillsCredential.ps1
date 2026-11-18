<#
.SYNOPSIS
    Tests installer credential exclusions and pruning in an isolated fake profile.
.DESCRIPTION
    Creates and deletes only its own temporary fixture. Temporarily redirects USERPROFILE
    for installer calls with SkipToolkits; never uses real credentials, skills or network.
.PARAMETER InstallerPath
    Installer implementation to copy into the disposable source fixture.
.PARAMETER TemporaryRoot
    Existing parent directory in which to create the unique disposable fixture.
#>
[CmdletBinding()]
param(
    [string]$InstallerPath = (Join-Path $PSScriptRoot '..\..\Install-Skills.ps1'),
    [string]$TemporaryRoot = ([IO.Path]::GetTempPath())
)

$ErrorActionPreference = 'Stop'
$installer = (Resolve-Path -LiteralPath $InstallerPath).Path
$parent = (Resolve-Path -LiteralPath $TemporaryRoot).Path
$fixture = Join-Path $parent ('install-credential-test-' + [guid]::NewGuid().ToString('N'))
$originalProfile = $env:USERPROFILE

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

try {
    $source = Join-Path $fixture 'source'
    $profile = Join-Path $fixture 'profile'
    $sourceSkill = Join-Path $source 'push-notifications'
    $installedSkill = Join-Path $profile '.copilot\skills\push-notifications'
    $null = New-Item -ItemType Directory -Path "$sourceSkill\scripts", "$installedSkill\scripts" -Force
    $fixture = (Resolve-Path -LiteralPath $fixture).Path
    $fixtureInstaller = Join-Path $source 'Install-Skills.ps1'
    Copy-Item -LiteralPath $installer -Destination $fixtureInstaller
    [IO.File]::WriteAllText("$sourceSkill\SKILL.md", 'Disposable fixture skill')
    [IO.File]::WriteAllText("$installedSkill\SKILL.md", 'Disposable fixture skill')
    [IO.File]::WriteAllText("$sourceSkill\scripts\helper.ps1", 'source-v1')
    [IO.File]::WriteAllText("$installedSkill\scripts\helper.ps1", 'old')
    [IO.File]::WriteAllText("$sourceSkill\PUSHBULLET-TOKEN.XML", 'dummy-source-marker')
    [IO.File]::WriteAllText("$sourceSkill\scripts\pushbullet-token.xml", 'different-dummy-source-marker')
    $credential = "$installedSkill\scripts\pushbullet-token.xml"
    [IO.File]::WriteAllText($credential, 'dummy-installed-marker')
    $credentialHash = (Get-FileHash -LiteralPath $credential).Hash
    $orphan = "$installedSkill\obsolete.txt"
    [IO.File]::WriteAllText($orphan, 'disposable orphan')
    $env:USERPROFILE = $profile

    $check = & $fixtureInstaller -Check -SkipToolkits 6>&1 | Out-String
    Assert-True ($check.Contains('RESULT: UpdatesAvailable')) 'Check must detect the changed helper and orphan.'
    Assert-True ((Get-FileHash -LiteralPath $credential).Hash -eq $credentialHash) 'Check changed the local credential.'
    Assert-True (Test-Path -LiteralPath $orphan) 'Check must not prune.'

    $null = & $fixtureInstaller -Force -Prune -SkipToolkits 6>&1
    Assert-True ((Get-FileHash -LiteralPath $credential).Hash -eq $credentialHash) 'Install/prune replaced or removed the local credential.'
    Assert-True (-not (Test-Path -LiteralPath $orphan)) 'Prune must still remove ordinary orphan files.'
    Assert-True ([IO.File]::ReadAllText("$installedSkill\scripts\helper.ps1") -ceq 'source-v1') 'Install did not update nested script content.'
    Assert-True (-not (Test-Path -LiteralPath "$installedSkill\pushbullet-token.xml")) 'A source credential was distributed.'
    $check = & $fixtureInstaller -Check -SkipToolkits 6>&1 | Out-String
    Assert-True ($check.Contains('RESULT: UpToDate')) 'Local credentials must not become orphan updates.'

    Remove-Item -LiteralPath $credential
    [IO.File]::WriteAllText("$sourceSkill\scripts\helper.ps1", 'source-v2')
    $null = & $fixtureInstaller -Force -SkipToolkits 6>&1
    Assert-True (-not (Test-Path -LiteralPath $credential)) 'A missing credential must not be copied from source.'
    Assert-True ([IO.File]::ReadAllText("$installedSkill\scripts\helper.ps1") -ceq 'source-v2') 'Normal installation stopped updating scripts.'
    Write-Output 'PASS: isolated check, nested copy, credential exclusion/preservation, ordinary pruning and post-check.'
}
finally {
    $env:USERPROFILE = $originalProfile
    if (Test-Path -LiteralPath $fixture) {
        Remove-Item -LiteralPath $fixture -Recurse -Force
    }
}