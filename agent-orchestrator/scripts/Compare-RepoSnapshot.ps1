<#
.SYNOPSIS
    Snapshots file hashes under a folder, then reports which files were added, modified or
    deleted since the snapshot.

.DESCRIPTION
    Use before handing a task to another agent (-Mode Snap) and again afterwards (-Mode Diff)
    to check independently which files it really changed, including untracked and ignored
    files that `git status` may not show. Read-only apart from writing the snapshot file.

.PARAMETER Mode
    Snap writes a snapshot; Diff compares the folder to an existing snapshot. Snapshot is
    accepted as another name for Snap.

.PARAMETER Path
    Folder to snapshot, usually the target repo root.

.PARAMETER SnapshotFile
    CSV file to write (Snap) or read (Diff). Keep it outside -Path.

.PARAMETER ExcludeDirectory
    Directory names skipped at any depth. Default .git, .vs, bin, obj.

.OUTPUTS
    Snap: a one-line summary. Diff: PSCustomObject per change (Path, Change), or nothing when
    there are no changes.

.EXAMPLE
    .\Compare-RepoSnapshot.ps1 -Mode Snap -Path C:\repo -SnapshotFile $env:TEMP\before.csv
    .\Compare-RepoSnapshot.ps1 -Mode Diff -Path C:\repo -SnapshotFile $env:TEMP\before.csv
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Snap', 'Snapshot', 'Diff')]
    [string]$Mode,

    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [string]$SnapshotFile,

    [string[]]$ExcludeDirectory = @('.git', '.vs', 'bin', 'obj')
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath $Path).Path.TrimEnd('\')

function Get-CurrentHashes {
    $separator = [regex]::Escape([IO.Path]::DirectorySeparatorChar)
    Get-ChildItem -LiteralPath $root -Recurse -File -Force | Where-Object {
        $relative = $_.FullName.Substring($root.Length + 1)
        $parts = @($relative -split $separator)
        $directories = if ($parts.Count -gt 1) { $parts[0..($parts.Count - 2)] } else { @() }
        -not ($directories | Where-Object { $ExcludeDirectory -contains $_ })
    } | ForEach-Object {
        [pscustomobject]@{
            Path = $_.FullName.Substring($root.Length + 1)
            Hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        }
    }
}

if ($Mode -in @('Snap', 'Snapshot')) {
    $current = @(Get-CurrentHashes)
    $current | Export-Csv -LiteralPath $SnapshotFile -NoTypeInformation -Encoding UTF8
    return "Snapshot of $($current.Count) files under $root written to $SnapshotFile"
}

if (-not (Test-Path -LiteralPath $SnapshotFile)) {
    throw "Snapshot file not found: $SnapshotFile. Run with -Mode Snap first."
}

$before = @{}
foreach ($row in Import-Csv -LiteralPath $SnapshotFile) { $before[$row.Path] = $row.Hash }
$after = @{}
foreach ($row in Get-CurrentHashes) { $after[$row.Path] = $row.Hash }

$changes = foreach ($key in $after.Keys) {
    if (-not $before.ContainsKey($key)) { [pscustomobject]@{ Path = $key; Change = 'Added' } }
    elseif ($before[$key] -ne $after[$key]) { [pscustomobject]@{ Path = $key; Change = 'Modified' } }
}
$changes = @($changes) + @(foreach ($key in $before.Keys) {
        if (-not $after.ContainsKey($key)) { [pscustomobject]@{ Path = $key; Change = 'Deleted' } }
    })
$changes | Where-Object { $_ } | Sort-Object Path
