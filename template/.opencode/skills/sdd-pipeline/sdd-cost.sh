#!/usr/bin/env bash
set -euo pipefail

STATE_FILE="$1"
STEP="$2"
SESSION_ID="$3"
DB="${OPENCODE_DB:-$HOME/.local/share/opencode/opencode.db}"

if [[ -z "$STATE_FILE" || -z "$STEP" || -z "$SESSION_ID" ]]; then
    echo "Usage: sdd-cost.sh <state.json> <step-name> <session-id>" >&2
    exit 1
fi

if [[ ! -f "$STATE_FILE" ]]; then
    echo "Error: state file not found: $STATE_FILE" >&2
    exit 1
fi

if [[ ! -f "$DB" ]]; then
    echo "Error: opencode database not found: $DB" >&2
    exit 1
fi

python3 -c "
import json, sqlite3, sys
from datetime import datetime, timezone

state_path = '$STATE_FILE'
step_name = '$STEP'
session_id = '$SESSION_ID'
db_path = '$DB'

db = sqlite3.connect(db_path)
cur = db.execute('SELECT cost, model, time_created, time_updated FROM session WHERE id = ?', (session_id,))
row = cur.fetchone()

if not row or row[0] is None:
    print(f'Warning: no cost found for session {session_id}', file=sys.stderr)
    sys.exit(0)

cost = float(row[0])
model_raw = row[1] or '{}'
try:
    model_data = json.loads(model_raw)
    model_id = model_data.get('id', model_raw)
except (json.JSONDecodeError, TypeError):
    model_id = model_raw

def ms_to_iso(ms):
    if not ms:
        return ''
    dt = datetime.fromtimestamp(ms / 1000, tz=timezone.utc)
    return dt.strftime('%Y-%m-%dT%H:%M:%SZ')

started_at = ms_to_iso(row[2])
finished_at = ms_to_iso(row[3])

with open(state_path) as f:
    state = json.load(f)

step = state['steps'][step_name]
current_cost = step.get('cost_usd', 0) or 0
new_cost = current_cost + cost
step['cost_usd'] = round(new_cost, 6)
step['model'] = str(model_id)
step['session_id'] = session_id
step['started_at'] = started_at
step['finished_at'] = finished_at

with open(state_path, 'w') as f:
    json.dump(state, f, indent=2)
    f.write('\n')

print(f'cost_usd: {current_cost:.6f} + {cost:.6f} = {step[\"cost_usd\"]:.6f} | model: {model_id} | {started_at} -> {finished_at} (session: {session_id})')
" || exit 1
