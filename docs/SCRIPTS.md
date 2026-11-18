# Scripts

Reusable scripts saved from working sessions. User-curated: scripts and rows are never deleted
without the user's approval.

| script | purpose | how to call | read-only or modifies | date |
| --- | --- | --- | --- | --- |
| `scripts/agent/Find-WrongLineEndings.ps1` | List lines whose line ending is not the expected one (lone LF in a CRLF file, or the reverse) after a tool edit | `.\scripts\agent\Find-WrongLineEndings.ps1 -Path <file>[,<file>] [-Ending CRLF\|LF]` | read-only | 2026-11-13 |
| `scripts/agent/Compare-TrxCoverage.ps1` | Verify complete passing TRX runs jointly cover exactly the reference case names, without duplicates; reference names must be unique | `.\scripts\agent\Compare-TrxCoverage.ps1 -ReferenceTrx <reference.trx> -ResultTrx <run1.trx>[,<run2.trx>]` | read-only | 2026-11-18 |
| `scripts/agent/Send-PushbulletNotification.ps1` | Compatibility forwarder to the canonical sender bundled in `push-notifications/scripts/`; fixed generic alerts, approved repository prefix, optional test/device routing and no credential read/send under WhatIf | `.\scripts\agent\Send-PushbulletNotification.ps1 -Event Completed [-RepositoryName PublicRepo] [-Test] [-DeviceId <id>] [-TokenPath <file>] [-WhatIf]` | Network send; local files read-only | 2026-11-18 |
| `scripts/agent/Test-PushbulletNotification.ps1` | Offline sender privacy/regression checks through the compatibility entry point; optional bundled setup fixtures test encrypted creation, nearby helper and overwrite protection without real credentials or network | `.\scripts\agent\Test-PushbulletNotification.ps1 [-SenderPath <script>] [-InitializerPath <script>] [-IncludeSetupFixtures]` | read-only by default; `-IncludeSetupFixtures` creates/removes its own temporary files | 2026-11-18 |
| `scripts/agent/Initialize-Pushbullet.ps1` | Compatibility forwarder to the bundled standalone setup helper; run in the user's own PowerShell window for masked XML creation and nearby helper copy; preserves existing files; WhatIf previews | `.\scripts\agent\Initialize-Pushbullet.ps1 [-TokenPath <file>] [-WhatIf]` | modifies: creates local setup-helper copy and credential XML; no network | 2026-11-18 |
