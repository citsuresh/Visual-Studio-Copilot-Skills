param([string]$ScriptPath = (Join-Path $PSScriptRoot '..\..\ui-interaction\scripts\Watch-UserInput.ps1'))
# Offline test of the input classifier (key presses, clicks and wheel steps count; mouse movement alone does not), with
# synthetic samples. The live sampling itself is only checked for starting and returning the documented fields.
$ErrorActionPreference = 'Stop'
$resolved = (Resolve-Path $ScriptPath).Path
$ast = [Management.Automation.Language.Parser]::ParseFile($resolved, [ref]$null, [ref]$null)
$script:assertions = 0
function Assert-True([bool]$Condition, [string]$Message) { $script:assertions++; if (-not $Condition) { throw $Message } }
$fn = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-InputKind' }, $true)
if (-not $fn) { throw 'Missing function: Get-InputKind' }
. ([scriptblock]::Create($fn.Extent.Text))

function S([long]$Tick, [int]$X = 100, [int]$Y = 100, [bool]$Key = $false, [bool]$Button = $false) { [pscustomobject]@{ LastInputTick = $Tick; X = $X; Y = $Y; AnyKeyDown = $Key; AnyButtonDown = $Button } }

# Quiet: nothing changed
Assert-True ((Get-InputKind (S 1000) (S 1000)) -eq 'None') 'No change must be no input.'
Assert-True ((Get-InputKind $null (S 1000)) -eq 'None') 'The first sample alone is no input.'

# Mouse movement alone: ignored (the last-input tick moves with it, the cursor moves too)
Assert-True ((Get-InputKind (S 1000 100 100) (S 1030 140 100)) -eq 'Move') 'A mouse move must be a Move, not input.'
Assert-True ((Get-InputKind (S 1000 100 100) (S 1030 101 100)) -eq 'Move') 'A one-pixel drift must be a Move, not input.'
Assert-True ((Get-InputKind (S 1000 100 100) (S 1000 140 100)) -eq 'Move') 'A move with an unchanged tick is still only a Move.'

# A key or a mouse button held at the sample: input
Assert-True ((Get-InputKind (S 1000) (S 1000 100 100 $true)) -eq 'Input') 'A key down must be input.'
Assert-True ((Get-InputKind (S 1000) (S 1030 100 100 $false $true)) -eq 'Input') 'A mouse button down must be input.'
Assert-True ((Get-InputKind (S 1000 100 100) (S 1030 140 100 $false $true)) -eq 'Input') 'A click made while moving must be input.'
Assert-True ((Get-InputKind (S 1000 100 100) (S 1030 140 100 $true)) -eq 'Input') 'A key pressed while moving the mouse must be input.'

# A key tap, click or wheel step between samples: the last-input tick changes and the cursor did not move
Assert-True ((Get-InputKind (S 1000) (S 1060)) -eq 'Input') 'A tick change with no cursor movement (a quick tap, click or wheel step) must be input.'

# The tick counter wraps at 2^32 (about 49.7 days); a changed value is still a change
Assert-True ((Get-InputKind (S 4294967290) (S 20)) -eq 'Input') 'A wrapped tick counter must still read as a change.'

# The real script starts, runs a short watch and returns the documented fields (the value of Active depends on the person)
$json = & powershell -NoProfile -File $resolved -Seconds 1 -PollMs 20 -AsJson 2>&1 | Out-String
$obj = $json.Trim() | ConvertFrom-Json
Assert-True ($null -ne $obj.Active -and $null -ne $obj.InputSamples -and $null -ne $obj.MoveSamples -and $obj.ElapsedMs -ge 900) "The live run must return the documented fields: $json"
Assert-True ($json -notmatch '"Key"|vk|VirtualKey') 'The result must never name a key.'

Write-Host "PASS: $script:assertions assertions; key presses, mouse buttons and wheel/tap steps count as input, mouse movement and drift do not, a click or key made while moving counts, tick wrap; the live run returns its fields and names no key."
