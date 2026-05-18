# SGAT Dashboard

Read-only viewer for the SGAT automated intraday trading system. Single
HTML file, no build step.

## Quick start

```bash
# Open the dashboard against live data
open index.html

# Open against a captured day (offline)
open "index.html?offline=2026-05-07"

# Capture today's data for offline testing
./capture.sh
```

## Setup (once)

```bash
cp .env.example .env
# Edit .env — fill in SGAT_TOKEN and SGAT_SCRIPT_URL
```

## Working with Claude Code

`CLAUDE.md` at the repo root briefs Claude Code on the project. First
session:

```bash
claude
> Read CLAUDE.md. Then look at data/2026-05-07.json to understand the
> response shape. Then check git log to see what's been worked on recently.
```

## Files

| | |
|---|---|
| `index.html` | The dashboard. Single-file HTML/CSS/JS. |
| `capture.sh` | Capture an Apps Script response as `data/YYYY-MM-DD.json`. |
| `data/` | Captured daily responses (test fixtures + offline mode source). |
| `appsscript/Code.gs` | Reference copy of the Apps Script (not deployed from here). |
| `docs/` | Design notes, known quirks, render conventions. |
| `CLAUDE.md` | Project briefing for Claude Code. Read this first. |

## What this repo is NOT

- The n8n workflows that produce SGAT data live elsewhere
- The Apps Script deploys from the Apps Script editor, not from this repo
- This is a viewer, not a trading bot

## License

Private. Not for distribution.
