# Scripts

Reusable scripts saved from working sessions. User-curated: scripts and rows are never deleted
without the user's approval.

| script | purpose | how to call | read-only or modifies | date |
| --- | --- | --- | --- | --- |
| `scripts/agent/Find-WrongLineEndings.ps1` | List lines whose line ending is not the expected one (lone LF in a CRLF file, or the reverse) after a tool edit | `.\scripts\agent\Find-WrongLineEndings.ps1 -Path <file>[,<file>] [-Ending CRLF\|LF]` | read-only | 2026-11-13 |
