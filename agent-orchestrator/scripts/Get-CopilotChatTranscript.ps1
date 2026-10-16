<#
.SYNOPSIS
    Returns the full text of the rendered messages in a VS Copilot Chat window.

.DESCRIPTION
    Uses `inspect`, not `read-visible-text`, because `read-visible-text` cuts each value off at
    2000 characters, which truncates long replies such as tool-call traces. Messages are the
    ChatMessageItem elements in render order; completion footers ("The response used the
    <model> model...") are tagged IsFooter and excluded unless -IncludeFooter is given.

    The chat list is virtualized: only messages Visual Studio has currently rendered are
    returned. Scroll the chat if an older message is missing.

.PARAMETER Hwnd
    Target window handle, e.g. "0x60AAA".

.PARAMETER Last
    Number of messages to return, counting back from the newest. 0 returns all. Default 1.

.PARAMETER IncludeFooter
    Include completion-footer messages.

.PARAMETER MaxDepth
    --maxDepth passed to `inspect`. Default 30.

.PARAMETER ExePath
    Path to agentdebug-ui.exe.

.OUTPUTS
    PSCustomObject per message: Index, IsFooter, Text. With -AsText, plain text separated by
    blank lines; with -AsJson, a JSON array.

.EXAMPLE
    .\Get-CopilotChatTranscript.ps1 -Hwnd 0x60AAA -AsText

.EXAMPLE
    .\Get-CopilotChatTranscript.ps1 -Hwnd 0x60AAA -Last 0 -IncludeFooter -AsJson
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Hwnd,

    [ValidateRange(0, 1000)]
    [int]$Last = 1,

    [switch]$IncludeFooter,

    [int]$MaxDepth = 30,

    [string]$CompletionPattern = '^The response used the .+ model',

    # ChatMessageItem Names that are only view-model type names carry no text; skip them.
    [string]$PlaceholderPattern = '^Microsoft\.VisualStudio\.',

    [string]$ExePath = 'C:\MyFiles\Git\AgentDebugToolkit\src\AgentDebugToolkit.UiAutomation.Cli\bin\Debug\net8.0-windows\agentdebug-ui.exe',

    [switch]$AsText,

    [switch]$AsJson
)

$ErrorActionPreference = 'Stop'
# The inherited DOTNET_ROOT from VS breaks agentdebug-ui.exe; always clear it.
Remove-Item Env:DOTNET_ROOT -ErrorAction SilentlyContinue

if (-not (Test-Path $ExePath)) {
    throw "agentdebug-ui.exe not found at '$ExePath'. Pass -ExePath explicitly."
}

$scratch = Join-Path $env:TEMP ("copilot-transcript-{0}.json" -f [guid]::NewGuid().ToString('N'))
$data = $null
try {
    # inspect occasionally fails with a transient UIA virtualization race; retry a few times.
    for ($try = 1; $try -le 3 -and -not $data; $try++) {
        & $ExePath inspect --hwnd $Hwnd --maxDepth $MaxDepth > $scratch 2>&1
        $raw = Get-Content -Raw -Encoding UTF8 -Path $scratch -ErrorAction SilentlyContinue
        try { $parsed = $raw | ConvertFrom-Json } catch { $parsed = $null }
        if ($parsed -and $parsed.root) { $data = $parsed } elseif ($try -lt 3) { Start-Sleep -Milliseconds 500 }
    }
}
finally {
    Remove-Item -LiteralPath $scratch -ErrorAction SilentlyContinue
}

if (-not $data) {
    throw "inspect returned no parseable UIA tree for hwnd $Hwnd."
}

# Depth-first, children in order, so messages come out in render order.
$messages = [System.Collections.Generic.List[object]]::new()
$stack = [System.Collections.Generic.Stack[object]]::new()
$stack.Push($data.root)
while ($stack.Count -gt 0) {
    $node = $stack.Pop()
    if ($node.ClassName -eq 'ChatMessageItem' -and $node.Name) {
        if ($node.Name -notmatch $PlaceholderPattern) { $messages.Add($node.Name) }
        continue
    }
    $children = @($node.Children)
    for ($i = $children.Count - 1; $i -ge 0; $i--) {
        if ($children[$i]) { $stack.Push($children[$i]) }
    }
}

$items = for ($i = 0; $i -lt $messages.Count; $i++) {
    [pscustomobject]@{
        Index    = $i
        IsFooter = $messages[$i] -match $CompletionPattern
        Text     = $messages[$i]
    }
}
$items = @($items | Where-Object { $IncludeFooter -or -not $_.IsFooter })
if ($Last -gt 0) {
    $items = @($items | Select-Object -Last $Last)
}

if ($AsJson) { ConvertTo-Json -InputObject $items -Depth 3 }
elseif ($AsText) { ($items | ForEach-Object { $_.Text }) -join "`r`n`r`n" }
else { $items }
