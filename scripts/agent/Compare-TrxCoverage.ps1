<#
.SYNOPSIS
Compare a reference TRX case set with one or more complete, passing TRX runs.
.PARAMETER ReferenceTrx
Reference TRX file defining the expected case display names, which must be unique.
.PARAMETER ResultTrx
TRX files whose combined cases must match the reference exactly, without duplicates.
.NOTES
Read-only. Does not run tests or modify files. Throws on incomplete, non-passing or mismatched results.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ReferenceTrx,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string[]]$ResultTrx
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-TrxCases {
    param([string]$Path)

    $settings = New-Object System.Xml.XmlReaderSettings
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $reader = [System.Xml.XmlReader]::Create((Resolve-Path -LiteralPath $Path).ProviderPath, $settings)
    try {
        $document = New-Object System.Xml.XmlDocument
        $document.XmlResolver = $null
        $document.Load($reader)
    }
    finally {
        $reader.Dispose()
    }

    $results = @($document.TestRun.Results.UnitTestResult)
    $counters = $document.TestRun.ResultSummary.Counters
    $summaryPassed = @('Completed', 'Passed') -ccontains [string]$document.TestRun.ResultSummary.outcome
    if (-not $summaryPassed -or $results.Count -eq 0 -or [int]$counters.total -ne $results.Count -or
        [int]$counters.executed -ne $results.Count -or [int]$counters.passed -ne $results.Count -or
        @($results | Where-Object { $_.outcome -cne 'Passed' -or [string]::IsNullOrWhiteSpace($_.testName) }).Count -ne 0) {
        throw "TRX run is empty, incomplete or non-passing: $Path"
    }
    foreach ($result in $results) { [string]$result.testName }
}

$expected = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($name in @(Read-TrxCases -Path $ReferenceTrx)) {
    if (-not $expected.Add($name)) { throw "Ambiguous duplicate reference case: $name" }
}
$actual = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($path in $ResultTrx) {
    foreach ($name in @(Read-TrxCases -Path $path)) {
        if (-not $actual.Add($name)) { throw "Duplicate result case: $name" }
    }
}
$missing = @($expected | Where-Object { -not $actual.Contains($_) } | Sort-Object)
$unexpected = @($actual | Where-Object { -not $expected.Contains($_) } | Sort-Object)
if ($missing.Count -ne 0 -or $unexpected.Count -ne 0) {
    throw "TRX coverage mismatch. Missing: $($missing -join '; '). Unexpected: $($unexpected -join '; ')."
}
[pscustomobject]@{ Matched = $true; CaseCount = $actual.Count; ResultFiles = $ResultTrx.Count }