# macOS performance

Development builds 13 and later retain a parsed usage index between launches. The published `v1.2.0-beta.3` packages are build 12; their immutable checksums have not changed.

## Startup and refresh

The menu bar appears immediately. Recent records load first, followed by history when the goal ledger or selected range needs it. Goal lifetime amounts remain pending until history is available. Log parsing and analytics use separate background queues, allowing range changes on already loaded data during historical scanning.

Every 30 seconds, the app enumerates file metadata. Unchanged files reuse their parsed records. If the manifest, day, timezone and overrides are unchanged, timer refreshes skip aggregation. A manual refresh rechecks titles and file evidence; automatic enrichment is rechecked at least every five minutes. Switching date ranges reuses today's totals, full lifetime and daily activity when those inputs are still valid.

Goal summaries are invalidated when the book or underlying snapshots change. Their usage and Decimal costs are calculated once per summary instead of for each row render or sorting comparison.

## Local cache

`~/Library/Caches/local.codexledger.app/usage-v1` stores a separate index per canonical data source. Entries include parsed usage and the local text/path metadata needed for classification and navigation. They do not contain complete chat logs or image attachments and are never uploaded by Ledger. Directories and files use owner-only permissions.

Entries are checked against source-file size and modification time, parser schema and an internal payload checksum. Deleted source records are not returned from the cache. Corrupt/incompatible entries and failed cache writes fall back to the source logs. Complete files are cached, so extending the date range preserves older responses without reparsing them. Prices are recalculated from the offline catalog, not persisted in the log index.

This is a disposable cache: macOS or the user can clear it, after which it is rebuilt. Goal books and preferences are stored separately. A first scan without an index still needs to parse the selected source files. A changed file currently reparses in full; append-only checkpoints and per-response aggregation are possible subsequent optimizations.

## Measurement and regressions

For a development build:

```sh
"/Applications/Codex Ledger.app/Contents/MacOS/CodexLedger" --diagnose --scope=all
"/Applications/Codex Ledger.app/Contents/MacOS/CodexLedger" --diagnose --scope=all --use-cache
```

Use the actual application path if installed under `~/Applications`. Diagnostics retain existing accounting fields and include `scanSeconds`, `aggregationSeconds`, `heatmapSeconds`, `totalSeconds`, `parsedFiles`, `diskCacheHits` and `memoryCacheHits`. The default diagnostic does not write a persistent index; `--use-cache` opts into the application's index.

`zsh test.sh` checks exact cached token subsets, Decimal amounts, month activity, range expansion, changed/deleted files, corrupt/schema-incompatible entries and failed writes. It also exercises real asynchronous staged startup, unchanged timer refreshes, reused lifetime scopes, goal-summary invalidation and incomplete-record completion blocking with isolated synthetic sources and preferences.
