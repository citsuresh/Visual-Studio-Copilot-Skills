# Compare-RepoSnapshot.ps1: test cases

Script: `..\Compare-RepoSnapshot.ps1`. Use an isolated temporary folder as `-Path` and put `-SnapshotFile` outside it. These cases are read-only apart from the test fixture and snapshot file. Not run as of 2026-10-31.

| ID | Setup / action | Expected result | Last result |
| --- | --- | --- | --- |
| P-01 | In a temporary fixture, create `modified.txt` and `deleted.txt`; run `-Mode Snap`, change `modified.txt`, delete `deleted.txt`, add `added.txt`, then run `-Mode Diff` | Returns one row per change with relative `Path` values: `modified.txt` / `Modified`, `deleted.txt` / `Deleted`, and `added.txt` / `Added` | Not run: not exercised during this documentation task |
| P-02 | Run `-Mode Snapshot` on a fixture, leave it unchanged, then run `-Mode Diff` | `Snapshot` works as an alias for `Snap`; Diff returns no change rows | Not run: not exercised during this documentation task |
| P-03 | In the fixture, include a hidden file and files under `.git`, `.vs`, `bin` and `obj` directories at the root and a nested level; snapshot, then change each | The changed hidden file is reported; files in the four default-excluded directory names are ignored at any depth | Not run: not exercised during this documentation task |
| P-04 | Run Snap and Diff with `-ExcludeDirectory cache` on a fixture containing `cache` folders at multiple depths and files outside them; change files in both locations | Files under directories named `cache` are excluded at any depth; changed files outside them are reported | Not run: not exercised during this documentation task |
| P-05 | Run `-Mode Diff` with a `-SnapshotFile` that does not exist | Throws an error identifying the missing snapshot and instructing the caller to run `-Mode Snap` first | Not run: not exercised during this documentation task |
