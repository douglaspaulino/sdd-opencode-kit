#!/usr/bin/env bash
set -euo pipefail

RUNS_DIR="${1:-.sdd/runs}"
OUTPUT="${2:-.sdd/debug-report.html}"
OPEN_BROWSER="${3:-}"

if [[ ! -d "$RUNS_DIR" ]]; then
    echo "Error: runs directory not found: $RUNS_DIR" >&2
    echo "Usage: sdd-debug-report.sh [.sdd/runs] [output.html] [--open]" >&2
    exit 1
fi

if [[ "${1:-}" == "--open" || "${2:-}" == "--open" || "${3:-}" == "--open" ]]; then
    OPEN_BROWSER="--open"
fi

export SDD_RUNS_DIR="$RUNS_DIR"
export SDD_OUTPUT="$OUTPUT"

python3 << 'PYEOF'
import json, glob, os, re, sys
from datetime import datetime

RUNS_DIR = os.environ['SDD_RUNS_DIR']
OUTPUT = os.environ['SDD_OUTPUT']

sessions = []
for sf in sorted(glob.glob(f'{RUNS_DIR}/**/debug/**/state.json', recursive=True)):
    d = os.path.dirname(sf)
    try:
        state = json.load(open(sf))
    except:
        continue
    rel = os.path.relpath(d, RUNS_DIR)
    slug = state.get('slug', os.path.basename(d))
    problem = state.get('problem', '')
    bugs = state.get('bugs', {})
    status = state.get('status', 'unknown')
    started = state.get('started_at', '')
    updated = state.get('updated_at', '')
    phases = state.get('phases', {})

    def read_report(name):
        p = os.path.join(d, name)
        return open(p).read() if os.path.exists(p) else ''

    knowledge = read_report('knowledge.md')

    sessions.append({
        'slug': slug,
        'rel': rel,
        'problem': problem,
        'bugs': bugs,
        'status': status,
        'started_at': started,
        'updated_at': updated,
        'phases': phases,
        'knowledge': knowledge,
    })

def escape(s):
    if not isinstance(s, str): s = str(s)
    return s.replace('&','&amp;').replace('<','&lt;').replace('>','&gt;').replace('"','&quot;').replace("'",'&#39;')

html = '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>SDD Debug Report</title>
<script src="https://cdn.jsdelivr.net/npm/chart.js@4"></script>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:#0F172A;color:#E2E8F0;padding:2rem;max-width:1200px;margin:0 auto}
h1{font-size:1.8rem;margin-bottom:.3rem;color:#F8FAFC}
h2{font-size:1.3rem;margin:2rem 0 1rem;color:#94A3B8;border-bottom:1px solid #1E293B;padding-bottom:.5rem}
h3{font-size:1.1rem;margin:1rem 0 .5rem;color:#CBD5E1}
.subtitle{color:#64748B;margin-bottom:2rem}
.summary-cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:1rem;margin-bottom:2rem}
.card{background:#1E293B;border-radius:8px;padding:1rem;text-align:center}
.card .num{font-size:2rem;font-weight:700;color:#38BDF8}
.card .label{font-size:.8rem;color:#64748B;margin-top:.3rem}
.session{background:#1E293B;border-radius:8px;padding:1.5rem;margin-bottom:1.5rem;border-left:4px solid #38BDF8}
.session.fixed{border-left-color:#22C55E}
.session.deferred{border-left-color:#F59E0B}
.session-head{display:flex;justify-content:space-between;align-items:start;margin-bottom:.5rem}
.session-title{font-size:1.1rem;font-weight:600;color:#F1F5F9}
.session-meta{font-size:.8rem;color:#64748B}
.session-problem{color:#94A3B8;font-size:.9rem;margin-bottom:1rem;padding:.5rem;background:#0F172A;border-radius:4px}
.bug{margin:.8rem 0;padding:.8rem;background:#0F172A;border-radius:6px;border-left:3px solid #64748B}
.bug.fixed{border-left-color:#22C55E}
.bug.deferred{border-left-color:#F59E0B}
.bug-header{display:flex;justify-content:space-between;margin-bottom:.4rem}
.bug-id{font-weight:600;font-size:.95rem;color:#38BDF8}
.bug-status{font-size:.75rem;padding:2px 8px;border-radius:10px;background:#1E293B;color:#94A3B8}
.bug-status.fixed{background:#166534;color:#22C55E}
.bug-status.deferred{background:#713F12;color:#FBBF24}
.bug-desc{color:#CBD5E1;font-size:.9rem;margin-bottom:.5rem}
.bug-detail{font-size:.85rem;color:#94A3B8;margin:2px 0}
.bug-detail strong{color:#64748B}
pre{font-size:.8rem;color:#94A3B8;white-space:pre-wrap;margin-top:.5rem;padding:.5rem;background:#0F172A;border-radius:4px;max-height:200px;overflow:auto}
.phases{display:grid;grid-template-columns:repeat(auto-fit,minmax(100px,1fr));gap:.5rem;margin-top:1rem}
.phase{text-align:center;font-size:.75rem;padding:.3rem;border-radius:4px;background:#0F172A;color:#64748B}
.phase.completed{background:#166534;color:#22C55E;font-weight:600}
.phase.in_progress{background:#1E3A5F;color:#38BDF8;font-weight:600}
.chart-row{display:grid;grid-template-columns:1fr 1fr;gap:2rem;margin:2rem 0}
.chart-box{background:#1E293B;border-radius:8px;padding:1rem;min-height:250px}
.chart-box canvas{max-height:220px}
.agents-section{margin-top:2rem;background:#1E293B;border-radius:8px;padding:1.5rem}
.agents-section pre{background:#0F172A;padding:1rem;border-radius:6px;max-height:none;font-size:.85rem;color:#CBD5E1}
.footer{text-align:center;color:#475569;font-size:.8rem;margin-top:3rem}
</style>
</head>
<body>
<h1>SDD Debug Report</h1>
'''

total_sessions = len(sessions)
total_bugs = sum(len(s['bugs']) for s in sessions)
total_fixed = sum(1 for s in sessions for b in s['bugs'].values() if b.get('status') == 'fixed')
total_deferred = sum(1 for s in sessions for b in s['bugs'].values() if b.get('status') == 'deferred')

html += f'<p class="subtitle">{RUNS_DIR} &mdash; {datetime.now().strftime("%Y-%m-%d %H:%M")}</p>'
html += '<div class="summary-cards">'
html += f'<div class="card"><div class="num">{total_sessions}</div><div class="label">Debug Sessions</div></div>'
html += f'<div class="card"><div class="num">{total_bugs}</div><div class="label">Bugs Found</div></div>'
html += f'<div class="card"><div class="num" style="color:#22C55E">{total_fixed}</div><div class="label">Fixed</div></div>'
html += f'<div class="card"><div class="num" style="color:#F59E0B">{total_deferred}</div><div class="label">Deferred</div></div>'
html += '</div>'

if sessions:
    html += '<div class="chart-row">'
    html += '<div class="chart-box"><canvas id="bugsChart"></canvas></div>'
    html += '<div class="chart-box"><canvas id="statusChart"></canvas></div>'
    html += '</div>'

for s in sessions:
    slug = s['slug']
    bug_count = len(s['bugs'])
    fixed_count = sum(1 for b in s['bugs'].values() if b.get('status') == 'fixed')
    cls = 'fixed' if s['status'] == 'completed' else ''
    html += f'<div class="session {cls}">'
    html += '<div class="session-head">'
    html += f'<div><span class="session-title">{slug}</span><br><span class="session-meta">{s["rel"]}</span></div>'
    html += f'<span class="session-meta">{fixed_count}/{bug_count} fixed &middot; {s["started_at"][:19]}</span>'
    html += '</div>'
    if s['problem']:
        html += f'<div class="session-problem">{escape(s["problem"])}</div>'

    for bid, bug in s['bugs'].items():
        bcls = bug.get('status', '')
        html += f'<div class="bug {bcls}">'
        html += '<div class="bug-header">'
        html += f'<span class="bug-id">{escape(bid)}</span>'
        html += f'<span class="bug-status {bcls}">{bug.get("status","")}</span>'
        html += '</div>'
        html += f'<div class="bug-desc">{escape(bug.get("description",""))}</div>'
        html += f'<div class="bug-detail"><strong>Root cause:</strong> {escape(bug.get("root_cause",""))}</div>'
        html += f'<div class="bug-detail"><strong>Fix:</strong> {escape(bug.get("fix",""))}</div>'
        html += f'<div class="bug-detail"><strong>Test:</strong> {escape(bug.get("regression_test",""))}</div>'
        if bug.get('knowledge_entry'):
            html += f'<pre>{escape(bug["knowledge_entry"])}</pre>'
        html += '</div>'

    # phases
    html += '<div class="phases">'
    for pid, pdata in s['phases'].items():
        pstatus = pdata.get('status', '')
        plabel = pid.replace('_', ' ').title()
        html += f'<div class="phase {pstatus}">{plabel}</div>'
    html += '</div>'

    if s['knowledge']:
        html += '<details><summary style="cursor:pointer;font-size:.8rem;color:#64748B;margin-top:.5rem">Raw report</summary>'
        html += f'<pre>{escape(s["knowledge"])}</pre></details>'

    html += '</div>'

# AGENTS.md entries
agents_entries = []
for s in sessions:
    for b in s['bugs'].values():
        if b.get('knowledge_entry'):
            agents_entries.append(escape(b['knowledge_entry']))

if agents_entries:
    html += '<div class="agents-section">'
    html += '<h2 style="border:none;margin-top:0">AGENTS.md entries</h2>'
    html += '<p style="color:#94A3B8;font-size:.85rem;margin-bottom:1rem">Copy these into your AGENTS.md to prevent similar bugs:</p>'
    html += '<pre>' + '\n\n'.join(agents_entries) + '</pre>'
    html += '</div>'

# ── Lessons learned & recommendations ──────────────────────

cats = {'frontend': 0, 'backend': 0, 'css': 0, 'dto': 0, 'type': 0, 'config': 0}
cat_keywords = {
    'frontend': ['angular', 'template', 'component', 'html', 'tsx', 'jsx', 'vue', 'react'],
    'backend': ['dto', 'controller', 'service', 'repository', 'api', 'endpoint', 'java', 'sql'],
    'css': ['scss', 'css', 'color', 'theme', 'dark', 'light', 'style', 'muted', 'token'],
    'dto': ['dto', 'json', 'shape', 'serialize', 'record', 'flat', 'nested'],
    'type': ['typeerror', 'undefined', 'null', 'type', 'interface', 'type-safe'],
    'config': ['config', 'env', 'pipeline', 'ci', 'build', 'import', 'path'],
}
for s in sessions:
    text = (s.get('problem', '') + ' ' + ' '.join(
        b.get('description', '') + ' ' + b.get('root_cause', '') for b in s['bugs'].values()
    )).lower()
    for cat, kws in cat_keywords.items():
        for kw in kws:
            if kw in text:
                cats[cat] += 1
                break

dom_cats = sorted([c for c in cats if cats[c] > 0], key=lambda c: -cats[c])

html += '<div class="agents-section" style="margin-top:2rem">'
html += '<h2 style="border:none;margin-top:0">Lessons Learned</h2>'

if total_bugs > 0 and dom_cats:
    html += '<h3 style="font-size:1rem;color:#CBD5E1;margin:.5rem 0">Affected Layers</h3>'
    html += '<div class="chart-row" style="grid-template-columns:1fr">'
    html += '<div class="chart-box" style="min-height:180px"><canvas id="layersChart"></canvas></div>'
    html += '</div>'

html += '<h3 style="font-size:1rem;color:#CBD5E1;margin:1rem 0 .5rem">Pattern Analysis</h3>'
html += '<ul style="color:#94A3B8;font-size:.9rem;line-height:1.6;padding-left:1.5rem">'
if dom_cats:
    html += f'<li><strong>Most affected:</strong> {dom_cats[0].capitalize()} layer ({cats[dom_cats[0]]} occurrences)</li>'
    if len(dom_cats) > 1:
        html += f'<li><strong>Secondary:</strong> {dom_cats[1].capitalize()} layer ({cats[dom_cats[1]]} occurrences)</li>'
html += '</ul>'

html += '<h3 style="font-size:1rem;color:#CBD5E1;margin:1rem 0 .5rem">ADR Suggestions</h3>'
html += '<ul style="color:#94A3B8;font-size:.9rem;line-height:1.6;padding-left:1.5rem">'

adrs = []
if cats['css'] > 0:
    adrs.append(('ADR-001: CSS Theme Architecture',
        'Replace global element-level color rules (h1,h2,h3,h4,h5,h6,p) with CSS custom properties scoped to themes. '
        'Each component inherits from theme tokens instead of relying on global overrides.'))
if cats['dto'] > 0:
    adrs.append(('ADR-002: DTO Shape Contracts',
        'Every API endpoint must have a contract test that asserts JSON shape matches the frontend type. '
        'Use jsonPath assertions in controller tests to verify nested object structure.'))
if len(dom_cats) >= 2:
    adrs.append(('ADR-003: Frontend-Backend Type Sync',
        'Generate TypeScript interfaces from Java/Kotlin DTOs via OpenAPI schema or a shared type library. '
        'Eliminates manual type duplication as a failure mode.'))
if not adrs:
    adrs.append(('ADR-NONE',
        'No recurring pattern detected across debug sessions. Review individual bugs for ad-hoc ADR needs.'))

for title, desc in adrs:
    html += f'<li><strong>{escape(title)}</strong><br><span style="font-size:.85rem">{escape(desc)}</span></li>'

html += '</ul>'

html += '<h3 style="font-size:1rem;color:#CBD5E1;margin:1rem 0 .5rem">Skill Recommendations</h3>'
html += '<ul style="color:#94A3B8;font-size:.9rem;line-height:1.6;padding-left:1.5rem">'
skills = []
if cats['css'] > 0:
    skills.append(('CSS Theme Debugging',
        'Add a skill that runs a contrast audit (axe-core, Lighthouse) and checks for legacy global rules '
        'whenever dark theme components are modified.'))
if cats['dto'] > 0:
    skills.append(('DTO Contract Testing',
        'Add a skill that generates jsonPath contract tests from OpenAPI specs and flags missing nested fields '
        'before PR review.'))
if cats['type'] > 0:
    skills.append(('Type Safety Audit',
        'Add a skill that cross-references Java DTO fields against TypeScript interfaces with nullable/undefined analysis.'))
if not skills:
    skills.append(('Generic debugging',
        'No strong pattern. The systematic debugging skill already covers the process. '
        'Add domain-specific skills as patterns emerge.'))

for title, desc in skills:
    html += f'<li><strong>{escape(title)}</strong><br><span style="font-size:.85rem">{escape(desc)}</span></li>'
html += '</ul>'

html += '<h3 style="font-size:1rem;color:#CBD5E1;margin:1rem 0 .5rem">AGENTS.md Context Improvements</h3>'
html += '<ul style="color:#94A3B8;font-size:.9rem;line-height:1.6;padding-left:1.5rem">'
ctx_items = []
if cats['css'] > 0:
    ctx_items.append(
        'Document the CSS architecture: which rules live in infrastructure.scss (legacy light-theme globals), '
        'which tokens in _colors.scss are safe for dark theme, and the convention for component-level color overrides.'
    )
if cats['dto'] > 0:
    ctx_items.append(
        'Add project glossary entries for all DTO classes with their JSON shape examples. '
        'Mention the Java → Angular field naming convention (camelCase, snake_case if any translation layer).'
    )
if not ctx_items:
    ctx_items.append(
        'Consider adding CONTEXT.md with project module map, key architectural decisions, and common failure patterns.'
    )

for item in ctx_items:
    html += f'<li>{escape(item)}</li>'
html += '</ul>'
html += '</div>'

html += '<script>'
if sessions:
    slug_list = ','.join(f'"{escape(s["slug"])}"' for s in sessions)
    fixed_list = ','.join(str(sum(1 for b in s['bugs'].values() if b.get('status') == 'fixed')) for s in sessions)
    deferred_list = ','.join(str(sum(1 for b in s['bugs'].values() if b.get('status') == 'deferred')) for s in sessions)
    cat_labels = ','.join(f'"{escape(c)}"' for c in dom_cats)
    cat_counts = ','.join(str(cats[c]) for c in dom_cats)
    cat_colors = ','.join(f'["#38BDF8","#22C55E","#F59E0B","#A855F7","#EC4899","#14B8A6"][{i}]' for i in range(len(dom_cats)))
    js_script = f'''const bugLabels = [{slug_list}];
const fixedCounts = [{fixed_list}];
const deferredCounts = [{deferred_list}];
new Chart(document.getElementById('bugsChart'), {{
  type: 'bar',
  data: {{ labels: bugLabels, datasets: [
    {{ label: 'Fixed', data: fixedCounts, backgroundColor: '#22C55E' }},
    {{ label: 'Deferred', data: deferredCounts, backgroundColor: '#F59E0B' }}
  ]}},
  options: {{
    responsive: true, maintainAspectRatio: false,
    plugins: {{ legend: {{ labels: {{ color: '#94A3B8' }} }}, title: {{ display: true, text: 'Bugs per Session', color: '#E2E8F0' }} }},
    scales: {{ x: {{ ticks: {{ color: '#64748B' }} }}, y: {{ ticks: {{ color: '#64748B' }}, beginAtZero: true }} }}
  }}
}});
new Chart(document.getElementById('statusChart'), {{
  type: 'doughnut',
  data: {{ labels: ['Fixed', 'Deferred'], datasets: [{{ data: [{total_fixed},{total_deferred}], backgroundColor: ['#22C55E', '#F59E0B'] }}] }},
  options: {{
    responsive: true, maintainAspectRatio: false,
    plugins: {{ legend: {{ labels: {{ color: '#94A3B8' }} }}, title: {{ display: true, text: 'Overall Status', color: '#E2E8F0' }} }}
  }}
}});
const catLabels = [{cat_labels}];
const catCounts = [{cat_counts}];
const catColors = [{cat_colors}];
if (catLabels.length) {{
  new Chart(document.getElementById('layersChart'), {{
    type: 'bar',
    data: {{ labels: catLabels, datasets: [{{ label: 'Mentions', data: catCounts, backgroundColor: catColors }}] }},
    options: {{
      responsive: true, maintainAspectRatio: false, indexAxis: 'y',
      plugins: {{ legend: {{ display: false }}, title: {{ display: true, text: 'Root Cause Distribution', color: '#E2E8F0' }} }},
      scales: {{ x: {{ ticks: {{ color: '#64748B' }}, beginAtZero: true }}, y: {{ ticks: {{ color: '#64748B' }} }} }}
    }}
  }});
}});'''
    html += js_script
html += '</script>'

html += '<div class="footer">Generated by sdd-debug-report.sh</div>'
html += '\n</body>\n</html>'

with open(OUTPUT, 'w') as f:
    f.write(html)

print(f'Report generated: {OUTPUT}')
print(f'{total_sessions} sessions, {total_bugs} bugs ({total_fixed} fixed, {total_deferred} deferred)')
PYEOF

if [[ "$OPEN_BROWSER" == "--open" ]]; then
    (sleep 1 && python3 -m webbrowser "file://$(realpath "$OUTPUT")" 2>/dev/null) &
    echo "Opening browser..."
fi
