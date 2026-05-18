#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# capture.sh — Capture an SGAT dashboard data snapshot for offline development
#
# Usage:
#   ./capture.sh              → captures TODAY (IST)
#   ./capture.sh 2026-05-07   → captures the given date
#   ./capture.sh --list       → list available dates from the master sheet
#
# Reads SGAT_TOKEN and SGAT_SCRIPT_URL from .env (gitignored). Copy
# .env.example to .env and fill in your values.
#
# Saves to: data/YYYY-MM-DD.json (pretty-printed for readable diffs).
#
# Validates the response (checks ok:true) and refuses to save error payloads.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Locate repo root regardless of where the script was invoked from ─────────
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# ── Load .env ───────────────────────────────────────────────────────────────
if [[ ! -f .env ]]; then
  echo "✗ No .env found. Copy .env.example to .env and fill in your token + URL."
  exit 1
fi
# shellcheck disable=SC1091
set -a; source .env; set +a

# ── Detect Python command (python3 / python / py) ────────────────────────────
# Windows installs Python as `python` or `py`; Linux/Mac as `python3`. Pick
# whichever exists and is Python 3.x.
PY=""
for cand in python3 python py; do
  if command -v "$cand" >/dev/null 2>&1; then
    if "$cand" -c 'import sys; sys.exit(0 if sys.version_info[0]==3 else 1)' >/dev/null 2>&1; then
      PY="$cand"
      break
    fi
  fi
done
if [[ -z "$PY" ]]; then
  echo "✗ No Python 3 found (tried python3, python, py)."
  echo "  Install Python 3 or add it to PATH, then re-run."
  exit 1
fi

if [[ -z "${SGAT_TOKEN:-}" ]] || [[ -z "${SGAT_SCRIPT_URL:-}" ]]; then
  echo "✗ .env must define SGAT_TOKEN and SGAT_SCRIPT_URL."
  exit 1
fi

# ── Helpers ─────────────────────────────────────────────────────────────────
today_ist() {
  # Date in Asia/Kolkata regardless of host timezone
  TZ='Asia/Kolkata' date +%Y-%m-%d
}

# ── Modes ───────────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--list" ]]; then
  echo "↻ Fetching available dates..."
  curl -fsSL "${SGAT_SCRIPT_URL}?token=${SGAT_TOKEN}&tab=dates" \
    | "$PY" -m json.tool
  exit 0
fi

DATE="${1:-$(today_ist)}"

# Validate date format
if [[ ! "$DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "✗ Invalid date format: '$DATE' (expected YYYY-MM-DD)"
  exit 1
fi

mkdir -p data
OUT="data/${DATE}.json"
# Use a repo-relative temp file (NOT mktemp). On Git Bash + native Windows
# Python, mktemp returns a Unix path like /tmp/xxx that Windows Python
# can't open. A relative path inside the repo works for both shells.
TMP=".capture_tmp_${DATE}.json"
trap 'rm -f "$TMP"' EXIT

# ── Build URL ───────────────────────────────────────────────────────────────
# For "today" we don't pass &date= (Apps Script picks today automatically).
TODAY="$(today_ist)"
if [[ "$DATE" == "$TODAY" ]]; then
  URL="${SGAT_SCRIPT_URL}?token=${SGAT_TOKEN}&tab=dashboard"
  LABEL="today ($DATE)"
else
  URL="${SGAT_SCRIPT_URL}?token=${SGAT_TOKEN}&tab=dashboard&date=${DATE}"
  LABEL="$DATE"
fi

echo "↻ Capturing $LABEL ..."
echo "  → $OUT"

# ── Fetch ───────────────────────────────────────────────────────────────────
# Apps Script web apps return 200 + JSON even on error, so we don't rely
# on -f for HTTP status — we validate the JSON body instead.
#
# Full past-day snapshots are 2-5 MB and Apps Script is slow to serialize
# them (cold start + ~14 tab reads). A 60s timeout is too tight. We allow
# up to 240s per attempt and retry up to 3 times — Apps Script often
# succeeds on the 2nd try once it's warm.
FETCH_OK=0
for attempt in 1 2 3; do
  echo "  ... fetch attempt $attempt (timeout 240s)"
  if curl -sSL --max-time 240 \
       --connect-timeout 20 \
       --retry 0 \
       "$URL" -o "$TMP" \
     && [[ -s "$TMP" ]]; then
    FETCH_OK=1
    break
  fi
  echo "  ... attempt $attempt failed, retrying in 5s"
  sleep 5
done
if [[ "$FETCH_OK" -ne 1 ]]; then
  echo "X curl failed after 3 attempts."
  echo "  The Apps Script may be timing out on a heavy past-day snapshot."
  echo "  Try again (it's often faster on a warm 2nd run), or capture a"
  echo "  lighter day. If it persistently fails, the snapshot file may be"
  echo "  very large — tell Claude and we'll add per-tab fetching."
  exit 1
fi

# ── Validate ────────────────────────────────────────────────────────────────
# Pass the temp file PATH as argv[1]. We cannot pipe via stdin here because
# the heredoc (<<'PY') already occupies Python's stdin. The temp file is a
# repo-relative path, which native Windows Python resolves correctly (only
# absolute Unix /tmp/... paths were the earlier problem).
"$PY" - "$TMP" <<'PY'
import json, sys
tmp_path = sys.argv[1]
try:
    with open(tmp_path, "r", encoding="utf-8") as f:
        body = json.load(f)
except json.JSONDecodeError as e:
    sys.exit(f"X Response is not JSON: {e}")
except FileNotFoundError:
    sys.exit(f"X Temp file not found: {tmp_path}")
if not isinstance(body, dict):
    sys.exit("X Response is not a JSON object.")
if body.get("error"):
    sys.exit(f"X Apps Script returned error: {body['error']}")
if body.get("ok") is not True:
    sys.exit("X Response missing ok:true.")
data = body.get("data", {})
nkeys = len(data) if isinstance(data, dict) else 0
print(f"OK Response valid - {nkeys} top-level data keys")

for k, label in [
    ("context",  "universe"),
    ("trades",   "closed trades"),
    ("tmlong",   "TML rows"),
    ("curve",    "curve points"),
    ("indexctx", "index rows"),
    ("industryctx", "industry rows"),
    ("industryctx_history", "history industries"),
]:
    v = data.get(k)
    if v is None:
        print(f"  - {label:20s} : (missing)")
        continue
    n = len(v) if isinstance(v, (list, dict)) else "-"
    print(f"  - {label:20s} : {n}")
PY

# ── Pretty-print into final destination ─────────────────────────────────────
# Read the temp file by path, write pretty JSON to $OUT. Both are
# repo-relative paths → safe for native Windows Python.
"$PY" - "$TMP" "$OUT" <<'PY'
import json, sys
src, dst = sys.argv[1], sys.argv[2]
with open(src, "r", encoding="utf-8") as f:
    data = json.load(f)
with open(dst, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
PY
echo "OK Saved $OUT ($(wc -c < "$OUT" | awk '{print int($1/1024)}') KB)"
