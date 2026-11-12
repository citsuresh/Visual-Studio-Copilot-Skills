<#
.SYNOPSIS
    Lists the lines of text files whose line ending is not the expected one. Read-only.

.DESCRIPTION
    Reads each file as bytes and reports every line break that is not the expected ending
    (a lone LF in a CRLF file, or a CRLF in an LF file). Use it after editing a file with a tool
    that may have mixed line endings. It never changes a file.

.PARAMETER Path
    One or more file paths.

.PARAMETER Ending
    The expected line ending: CRLF (default) or LF.

.EXAMPLE
    .\scripts\agent\Find-WrongLineEndings.ps1 -Path .github\copilot-instructions.md, docs\CODE_SUMMARY.md

.NOTES
    Output: one line per file, "<path>: <line numbers or none>". Exit code 1 if any file has a
    wrong line ending, otherwise 0. Modifies nothing.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string[]]$Path,

    [ValidateSet('CRLF', 'LF')]
    [string]$Ending = 'CRLF'
)

$anyWrong = $false
foreach ($p in $Path) {
    $b = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $p).Path)
    $line = 1
    $wrong = New-Object System.Collections.Generic.List[int]
    for ($i = 0; $i -lt $b.Length; $i++) {
        if ($b[$i] -eq 10) {
            $hasCr = ($i -gt 0 -and $b[$i - 1] -eq 13)
            if (($Ending -eq 'CRLF' -and -not $hasCr) -or ($Ending -eq 'LF' -and $hasCr)) { $wrong.Add($line) }
            $line++
        }
    }
    if ($wrong.Count -gt 0) { $anyWrong = $true }
    "${p}: " + $(if ($wrong.Count) { $wrong -join ',' } else { 'none' })
}
if ($anyWrong) { exit 1 }
exit 0
