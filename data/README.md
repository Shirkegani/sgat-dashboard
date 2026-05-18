# data/

Captured Apps Script `?tab=dashboard` responses, one JSON file per day.

## Filename convention

`YYYY-MM-DD.json` — date is IST.

## How to capture

```bash
./capture.sh              # today
./capture.sh 2026-05-07   # a specific date
./capture.sh --list       # see what dates the master sheet has
```

## How to use

Load the dashboard in offline mode against a captured day:

```
file:///path/to/index.html?offline=2026-05-07
```

The dashboard will fetch `data/2026-05-07.json` instead of the live
Apps Script endpoint. A small banner appears at top of the page in
offline mode so you don't mistake it for live data.

## What's in each file

Top-level structure:
```json
{
  "ok": true,
  "tab": "dashboard",
  "date": "2026-05-07",
  "data": {
    "context": [...],          // universe
    "profile": [...],          // per-cycle market state
    "trades": [...],           // closed trades
    "positions": [...],
    "nifty": [...],            // ~20 indices × ~75 cycles × 3 days
    "tmlong": [...],
    "curve": [...],            // per-minute P&L
    "supervisor": {...},
    "indexctx": [...],
    "industryctx": [...],
    "industryctx_history": {...}
  },
  "ts": "..."
}
```

Files are pretty-printed for readable git diffs. Typical size: ~2-5 MB.

## When to recapture

- After market close on any day you want to keep for testing
- When the Apps Script schema changes (e.g. new field in `industryctx_history`)
- When a specific day exposes a bug you want to debug repeatedly

Don't recapture historical days unless you specifically want to refresh
their snapshot — old captures are the most reliable test fixtures
because they're frozen.

## Days worth keeping as test fixtures

- A typical trading day with closed trades (e.g. 2026-05-06)
- A day with at least one SHORT trade
- A day with no trades at all (renders the empty-state paths)
- A day with corrupt data (e.g. 2026-04-24, 2026-04-03) for stress testing

The CLAUDE.md at repo root has the "known-bad data dates" list.
