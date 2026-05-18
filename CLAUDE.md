# SGAT Dashboard — Project Briefing

## What SGAT is

SGAT (Stock Gainer Automated Trading) is Ganesh's automated NSE intraday
trading system. The system identifies opportunities in ~1,354 liquid
mid/small-cap NSE stocks (tagged `M5_LIQ_OK`), enters via TML/TMS Trade
Manager workflows, and exits via stop-loss + trailing rules.

**Scale path**: ₹1L → ₹5L → ₹10L → ₹50L. Currently at ₹1L deployed,
₹2K per position, paper-trading 1 qty live for discipline and data
collection. Ultimate target: ₹50L deployed capital with 1% daily return
(₹50K/day).

**Stack** (background context — not in this repo):
- n8n (self-hosted, Docker, Hostinger VPS) — workflow orchestration
- Zerodha Kite Connect — broker API
- Google Sheets — primary data bus (sheet ID `1DxGRAQ8jJ_DslfQWL0Qc5Rd5faJkvxeyTYJEooMbyEg`)
- Google Apps Script — read-only HTTP relay for the dashboard
- SQLite — supplementary storage

All intraday trades are **MIS product** with auto square-off. CNC is
reserved for future swing trades (not part of intraday system).

**SL deployment timeline**:
- Pre-Apr 17, 2026: 1.0% trail + 1.6% hard stop (1.0/1.6)
- Apr 17, 2026 onwards: 3.0% trail + 3.0% hard stop (3.0/3.0)

⚠ Never compare raw `pnl_inr` across the Apr 17 boundary. Pre-Apr-17 days
must be re-simulated under 3.0/3.0 on candle data for valid cross-day
comparison.

---

## What this repo is

**Dashboard only.** Single-file HTML (~9,000 lines) that renders SGAT
state in real time during the trading day and on historical days post-EOD.

The dashboard reads from a Google Apps Script web endpoint that wraps
the master Google Sheet. The dashboard does not call any workflows,
does not write any data, does not authenticate end-users — it's a
read-only viewer.

```
┌─────────────┐    HTTPS GET    ┌──────────────┐    Sheets API    ┌──────────────┐
│  index.html │───────────────▶ │  Apps Script │───────────────▶ │ Google Sheet │
│  (browser)  │ ◀───────────────│  (Code.gs)   │ ◀───────────────│              │
└─────────────┘    JSON         └──────────────┘                  └──────────────┘
```

## What this repo is NOT

**Workflows live elsewhere.** The n8n workflows that produce SGAT data
(`SGAT_30_LIVE_GetIndices_Trades`, `SGAT_35_LIVE_MovementIdentifier`, etc.)
are not in this repo. If a dashboard feature needs a new field, the
workflow change is a separate task — flag it in chat and Ganesh will
handle it outside this repo.

**Apps Script lives elsewhere too.** `appsscript/Code.gs` here is a
*reference copy* for schema understanding only. Don't generate
modifications to it expecting them to deploy from this repo. Real
deploys go through the Apps Script editor.

---

## Repo layout

```
sgat-dashboard/
├── CLAUDE.md                       ← you are here
├── README.md                       ← short human-facing orientation
├── .gitignore
├── .env.example                    ← template (DON'T commit a real .env)
│
├── index.html                      ← the dashboard, single-file
├── capture.sh                      ← daily data capture script
│
├── data/
│   ├── README.md                   ← what's in each captured day
│   ├── 2026-05-06.json             ← Apps Script ?tab=dashboard responses
│   ├── 2026-05-07.json
│   └── ...
│
├── appsscript/
│   └── Code.gs                     ← v8 — schema reference (not deployed from here)
│
└── docs/
    ├── known-data-quirks.md        ← lying-Z timestamps, missing tabs, etc.
    └── render-conventions.md       ← BUY/SELL markers, colors, etc.
```

---

## Dashboard architecture

**Single-file HTML/CSS/JS**. No build step, no bundler, no framework.
Open in any modern browser; it works. This is intentional — keeps deploy
trivial (drop in any web server / open the file directly).

### Section layout (top to bottom)

| Section | DOM ID prefix | What it shows |
|---|---|---|
| Header | `s1-` | Logo, market badge, quote, IST clock, date picker |
| Day Profile + KPIs | `s2-` | Regime, breadth bar, long/short industries, long/short indices, reasoning, P&L + KPI curves, sector tile grid |
| P&L curves + tables | `s3-` | Live P&L curve, equity, sparklines, trades table |
| Universe + Stock Drill | `s4-` | Universe filterbar, table, slide-in drill panel |

### Critical render functions

| Function | Renders |
|---|---|
| `s2RenderProfile()` | Day Profile bar (regime, breadth, industries, indices) |
| `s2IxRender()` | 20-tile index sparkline grid |
| `s3DrawCurveFromState()` | Live P&L curve (calls `s3RenderCurve`) |
| `s3RenderCurve()` | Actually draws the SVG |
| `s4RenderTable()` | Universe table |
| `s4OpenDrill()` | Stock drill panel (chart + context blocks + trade card) |
| `s4DrawChart()` | Stacked dual-charts in the drill (stock + industry/index) |
| `s4PopulateHeaderChips()` | Drill panel header chip line |
| `s4PopulateHeaderStatus()` | Drill panel STATUS line |
| `s4PopulateTradeCard()` | Trade card sidebar (Entry/Exit/Net) |
| `s4PopulateContextBlocks()` | At-Entry / At-Exit 3-column blocks |

### Color tokens (CSS variables)

```
--green:  #00e5a0   (positive, BUY, LONG)
--red:    #ff4d6a   (negative, SELL, SHORT)
--amber:  #ffb84d   (chop, warning, industry overlay)
--blue:   #38b6ff   (index, neutral info, dashed)
--dim:    #7a8a99   (labels, secondary)
--border: rgba(40,65,80,...) — section dividers
--text:   #d4e0ec (default)
```

### CRITICAL render conventions

**BUY/SELL marker convention** (chart drill panel):

| Marker | Meaning | Color | Position |
|---|---|---|---|
| ▲ | BUY | `#00e5a0` green | below data point, apex up |
| ▼ | SELL | `#ff4d6a` red | above data point, apex down |

For LONG trades: ▲ first (entry buy) → ▼ second (exit sell).
For SHORT trades: ▼ first (entry sell) → ▲ second (exit buy).

Color = action only. Never modulate by P&L outcome.

**Time-anchored X-axis** (all session charts):
- Session = 09:15 to 15:30 IST = 375 minutes
- `x = (minsSince915 / 375) * W`
- Hourly gridlines at minutes 60, 120, 180, 240, 300, 360
- Label marks at 09:15, 10:00, 11:00, 12:00, 13:00, 14:00, 15:00, 15:30

NEVER use index-based `x = i / (n-1) * W` for time-series charts. That
squashes 5 morning data points across the full width.

---

## Data shape

The Apps Script `?tab=dashboard` endpoint returns:

```json
{
  "ok": true,
  "tab": "dashboard",
  "date": "2026-05-07",
  "data": {
    "context":             [...],   // LiveContext — universe with PFO
    "profile":             [...],   // DayProfile — per-cycle market state
    "trades":              [...],   // DailyTrades — closed trades
    "positions":           [...],   // PositionLog latest per symbol
    "nifty":               [...],   // NiftyCandles — 3 days × ~20 indices
    "symbolstate":         [...],   // SymbolState
    "tmlong":              [...],   // TML latest + first ENTER merged per stock
    "curve":               [...],   // positions_curve — per-minute P&L
    "supervisor":          {...},   // SupervisorState latest single row
    "indexctx":            [...],   // IndexContext latest cycle (~20 rows)
    "industryctx":         [...],   // IndustryContext latest cycle (~22 rows)
    "industryctx_history": {...}    // {industry: [{hhmm, median_pfo, ...}, ...]}
  },
  "ts": "2026-05-07T..."
}
```

### Key field reference

Per row in `data.curve` (positions_curve):
```
ts          : "2026-05-07T04:20"  ← naive UTC (no Z, even though UTC)
pnl         : numeric
long_pnl    : numeric (v3 schema)
short_pnl   : numeric (v3 schema)
count       : open_count
trades      : open + closed
deployed    : capital deployed
```

Per row in `data.trades` (DailyTrades, closed):
```
tradingsymbol     : "SHRIRAMFIN"
first_entry_ts    : "2026-05-06T14:31:35.000Z"  ← lying Z (see quirks)
last_exit_ts      : "2026-05-06T15:12:31.000Z"  ← lying Z
buy_value         : 994.00
sell_value        : 1002.70
qty_closed        : 1
pnl_inr           : 8.70
pnl_pct           : 0.88
avg_holding_min   : 40.93
trade_direction   : "LONG" | "SHORT"
industry          : "Financial Services"
theme_index_primary : "NIFTY FIN SERVICE"
```

Per row in `data.tmlong` (TML latest + first-ENTER merged):
```
tradingsymbol     : "..."
last_entry_time   : "2026-05-07T..."
entry_price       : 994.0
entry_score       : 67
entry_rank        : 12
_enter_entry_score : 67   ← same, but explicitly from ENTER row
_enter_entry_rank  : 12   ← same
last_action       : "ENTER" | "HOLD" | "EXIT" | "SL_HIT" | ...
tm_reason         : "enter_ok|q=100|TREND_UP|STRONG"
position_status   : "OPEN" | "CLOSED" | ""
```

Per row in `data.indexctx` (latest IndexContext cycle):
```
index_name        : "NIFTY BANK"
sector_tag        : "BANK"
pct_from_open     : 0.45
strength_rank     : 13
structure         : "BULL" | "BEAR" | "MIXED_POS" | "MIXED_NEG" | "CHOP"
ema_state         : "STRONG_UP" | "WEAK_UP" | "STRONG_DOWN" | "WEAK_DOWN"
velocity_5m       : 0.12
velocity_15m      : 0.45
relative_to_nifty50 : -0.10
```

Per `data.industryctx_history[industry]` row (v8 — for sparklines + tooltip):
```
hhmm                : 1430
median_pfo          : 0.52
pct_above_open      : 67   ← v8 addition
industry_structure  : "BULL"  ← v8 addition
strength_rank       : 8       ← v8 addition
verdict             : "LONG_PERMITTED"  ← v8 addition
```

---

## ⚠ Critical data quirks

These are bugs in the upstream data that the dashboard has to work around.
Each has bitten us at least once.

### 1. Lying-Z timestamps

Google Apps Script's `Date.toJSON()` always appends `Z` even when the
underlying Date represents an IST timestamp from a sheet cell. Example:

```json
{
  "first_entry_ts": "2026-05-06T14:31:35.000Z"
}
```

That `Z` is a **lie** — 14:31 is the actual IST trade time, not UTC.
If interpreted as UTC, it shifts to 20:01 IST (after market close).

**Detection heuristic** (used in 4+ places in `index.html`):

```js
var hasZ = s.indexOf('Z') >= 0 || /\+0000/.test(s);
var isUTC;
if (hasZ) {
  // Check if interpreting as UTC pushes IST > 16:00 (after-hours)
  var carry = (mm + 30) >= 60 ? 1 : 0;
  var istHHTest = (hh + 5 + carry) % 24;
  var lyingZ = (istHHTest > 16 || istHHTest < 4) && (hh >= 9 && hh <= 15);
  isUTC = !lyingZ;
} else {
  isUTC = (hh < 4);  // naive UTC catch — but see quirk #2
}
```

Locations of the autodetect:
1. `tsToIstHHMM` (module-level, ~line 4260) — main helper
2. `s4OpenDrill` chart entry/exit ts parser (~line 5285)
3. `s4FetchAndUpgradeCandles` candle ts parser (~line 5495)
4. `cycleTsToHhmmLocal` inside trade-card helpers (~line 6000)

When fixing one, **review all four for consistency**.

### 2. positions_curve timestamps are always UTC (no Z)

The Apps Script `readPositionsCurve()` does:
```js
const ts = tsRaw instanceof Date ? tsRaw.toISOString() : String(tsRaw);
const minuteKey = ts.slice(0, 16);   // strips the Z
```

So `data.curve[].ts` is **naive UTC**. The dashboard's `s3DrawCurveFromState`
detects this by pre-scanning the array: if any `hh < 9` or `hh > 15`, the
whole array is UTC (since NSE trading hours in IST are 09:15-15:30).

This handles both live data (always UTC) and past-day snapshots (which
may be naive IST if snapshotter normalizes them differently).

### 3. Date filters break sheet reads

Apps Script base sheets are cleaned daily. Adding date filters to the
sheet read causes 1-row bugs (seen in original Sector Context build).
**Never** add `where date = ...` filters in Apps Script readers.

### 4. EOD-only fields

These appear only AFTER market close, never use them for intraday
decisions:
- `day_return_pct`, `max_run_from_open_pct`, `min_drawdown_from_open_pct`
- `day_profile_csv`
- `r_915_930`, `r_930_1000`, `r_1000_1200`, `r_1200_1400`, `r_1400_1530`
- `close_position_pct`, `efficiency_ratio`

### 5. Known-bad data dates

| Date | Issue |
|---|---|
| 2026-04-03 | Corrupt DayProfile (constant values), no live trades |
| 2026-04-09 | Sparse TML logging (only 09:20 and 13:09 cycles) |
| 2026-04-20 | DailyTrades reconciliation broken; PositionLog is truth |
| 2026-04-24 | Empty TradeManagerLong and DayCandles sheets |
| Pre-2026-04-07 | `velocity_stalling` and `momentum_stall` fired together |

### 6. realised=0 PositionLogger bug

148 of 157 closed trades show `pnl_inr=0` because the P&L sits in
unrealised. Not a dashboard bug — flagged for backend fix.

---

## Working preferences

When making changes:

1. **Discuss structure before writing code.** Outline plain language →
   node/function sequence → code, in that order. Don't jump to
   implementation.

2. **Data-first analysis.** When investigating issues, look at actual
   data shape before forming theories. When uncertain about field names
   or values, add a one-shot console diagnostic, read the output, then
   write the fix.

3. **Don't propose changes outside dashboard scope.** If a fix needs
   workflow changes or Apps Script changes, flag it — don't try to
   modify those files in this repo (Apps Script reference copy may
   exist but isn't the deploy target).

4. **Always show what's changing and why.** Especially for tricky JS
   like the lying-Z autodetect — comment liberally.

5. **n8n paired item requirement.** Every code-node emitted item needs
   `pairedItem` set. (Only relevant if drafting workflow code, which is
   rare here.)

6. **Simulation standards.** For any trade-simulation work:
   - % of move already consumed before entry
   - % remaining potential after entry
   - Actual extraction efficiency = P&L captured / remaining potential
   These three numbers are core profitability metrics.

7. **Cross-period P&L comparisons.** Never compare raw `pnl_inr` across
   the Apr 17 SL transition.

### Don't propose

- Exit-rule modifications inside TML/TMS analysis (exit lives in a
  separate workflow — out of scope for this repo)
- Bear-day-mode redesign (long deferred, has a pending clean redesign)

---

## How to test changes

### Offline mode (works without internet)

```
file:///path/to/index.html?offline=2026-05-07
```

When `offline=YYYY-MM-DD` is in the URL, the dashboard fetches from
`data/YYYY-MM-DD.json` instead of the live Apps Script. The captured
file must exist in `data/`.

This is the primary development affordance — pick any captured day,
test rendering changes, see them apply consistently across history.

### Capturing a new day's data

```bash
# Capture today (after market close, ideally)
./capture.sh

# Capture a specific date
./capture.sh 2026-05-07
```

Requires `.env` with:
```
SGAT_TOKEN=...
SGAT_SCRIPT_URL=https://script.google.com/macros/s/.../exec
```

(Copy `.env.example` and fill in.)

### When introducing a render change

1. Capture today + a few past days (`./capture.sh 2026-05-06`, etc.)
2. Load offline mode for each captured day
3. Visually verify the change is consistent
4. Especially check: untraded stocks, open positions, closed trades,
   SHORT trades, days with no trades at all, days with corrupt fields

---

## Quick reference — file paths inside index.html

When asking Claude Code to find something, these line numbers are approximate
(as of 2026-05-07). Use `grep` to confirm before editing.

| Looking for | Search for |
|---|---|
| The lying-Z autodetect | `lyingZ` (should be 4 matches) |
| Color tokens | `--green:` |
| Day Profile render | `function s2RenderProfile` |
| Index tile grid HTML | `s2-idx-row` |
| Index list (key → name) | `S2_IX_PANELS` |
| Index render config | `idxMap = [` |
| Index hover registry | `idxHoverMap = [` |
| Industry-to-index map | `INDUSTRY_TO_INDEX = {` |
| Stock drill panel HTML | `s4-drill"` |
| Drill chart render | `function s4DrawChart` |
| Trade card sidebar | `function s4PopulateTradeCard` |
| At-entry / at-exit blocks | `function s4PopulateContextBlocks` |
| P&L curve render | `function s3RenderCurve` |
| P&L curve data prep | `function s3DrawCurveFromState` |

---

## What's been worked on recently (high-level)

- **Phase 1-3 stock drill redesign** (May 6): stacked dual-charts,
  header chip line + STATUS line, At-Entry / At-Exit context blocks,
  Trade Card sidebar (60/40 → 70/30 layout)
- **Index swap** (May 6-7): dropped NIFTY MIDCAP 150 + NIFTY SMLCAP 250,
  added NIFTY COMMODITIES + NIFTY CHEMICALS; tile order reorganized
  into 7 logical groups (broad → financials → health → tech & services
  → consumer → infra → energy & materials); subtle dividers between groups
- **P&L curve UTC fix** (May 7): array-wide UTC detection in
  `s3DrawCurveFromState` so live curves render correctly when trading
  starts after 09:30
- **Lying-Z fix** (earlier): applied to all 4 autodetect helpers

### Pending / on the horizon

- **Short-side marker direction** — verify SHORT trades render markers
  in correct order (▼ then ▲); APTUS / GOKULAGRO are recent SHORT trades
  to test against
- **Phase 4 — TM cycle log table** — render `tmlog_stock` rows already
  cached on `STATE.s4TmHistory` as a clean forensic table; remove the
  Loading... artifacts on session-stat cards
- **Trades table entry/exit times** (~line 5309) — still uses
  `slice(11,16)` for entry/exit times — may show wrong times for
  lying-Z data; needs the autodetect treatment

---

## Tone

Step-by-step, practical, explanatory — like a mentor teaching an
engineer. Short structured explanations and tables where they help.
When code is shown, comment briefly so the change is self-explanatory.

When in doubt, ask. Better to clarify scope than to over-build.
