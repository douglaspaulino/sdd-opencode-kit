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
import json, glob, os, re, sys, math
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
        'slug': slug, 'rel': rel, 'problem': problem,
        'bugs': bugs, 'status': status, 'started_at': started,
        'updated_at': updated, 'phases': phases, 'knowledge': knowledge,
    })

def esc(s):
    if not isinstance(s, str): s = str(s)
    return s.replace('&','&amp;').replace('<','&lt;').replace('>','&gt;').replace('"','&quot;').replace("'",'&#39;')

def svg_bar(data, labels, colors, title, width=500, height=220):
    if not data: return ''
    pad_top, pad_bottom, pad_left, pad_right = 30, 35, 50, 20
    cw = width - pad_left - pad_right
    ch = height - pad_top - pad_bottom
    max_val = max(data) or 1
    n = len(data)
    bw = max(20, min(60, (cw - (n-1)*8) // n))
    gap = 8
    total_w = n * bw + (n-1) * gap
    if total_w > cw:
        bw = max(12, (cw - (n-1)*gap) // n)
        total_w = n * bw + (n-1) * gap
    ox = pad_left + (cw - total_w) // 2
    bars = ''
    labels_svg = ''
    for i, val in enumerate(data):
        bh = (val / max_val) * (ch - 15)
        x = ox + i * (bw + gap)
        y = pad_top + ch - 10 - bh
        color = colors[i] if i < len(colors) else '#38BDF8'
        bars += f'<rect x="{x}" y="{y}" width="{bw}" height="{bh}" rx="3" fill="{color}"><title>{labels[i]}: {val}</title></rect>'
        label_trunc = labels[i][:12]
        labels_svg += f'<text x="{x+bw/2}" y="{pad_top+ch+5}" text-anchor="end" font-size="10" fill="#64748B" transform="rotate(-25,{x+bw/2},{pad_top+ch+5})">{esc(label_trunc)}</text>'
    return f'''<svg width="{width}" height="{height}" viewBox="0 0 {width} {height}">
<text x="{width/2}" y="18" text-anchor="middle" font-size="13" fill="#E2E8F0" font-weight="600">{esc(title)}</text>
{bars}{labels_svg}</svg>'''

def svg_donut(data, labels, colors, title, size=200):
    if not data or sum(data) == 0: return ''
    total = sum(data)
    cx, cy, r = size//2, size//2, 70
    dash_array = ''
    offset = 0
    segs = ''
    for i, val in enumerate(data):
        pct = val / total
        if pct == 0: continue
        circ = 2 * math.pi * r
        length = circ * pct
        dash = f'{length} {circ - length}'
        color = colors[i] if i < len(colors) else '#38BDF8'
        segs += f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="none" stroke="{color}" stroke-width="28" stroke-dasharray="{dash}" stroke-dashoffset="-{offset}" transform="rotate(-90 {cx} {cy})"><title>{labels[i]}: {val}</title></circle>'
        offset += length
    leg = ''
    for i, (l, v) in enumerate(zip(labels, data)):
        color = colors[i] if i < len(colors) else '#38BDF8'
        pct = int(v / total * 100)
        leg += f'<rect x="20" y="{cy*2+20+i*22}" width="12" height="12" rx="2" fill="{color}"/>'
        leg += f'<text x="38" y="{cy*2+30+i*22}" font-size="12" fill="#94A3B8">{esc(l)}: {v} ({pct}%)</text>'
    return f'''<svg width="{size}" height="{size+len(data)*22+20}" viewBox="0 0 {size} {size+len(data)*22+20}">
<text x="{cx}" y="18" text-anchor="middle" font-size="13" fill="#E2E8F0" font-weight="600">{esc(title)}</text>
{segs}{leg}</svg>'''

CAT_COLORS = ['#38BDF8','#22C55E','#F59E0B','#A855F7','#EC4899','#14B8A6']

cats = {'frontend': 0, 'backend': 0, 'css': 0, 'dto': 0, 'type': 0, 'config': 0}
cat_keywords = {
    'frontend': ['angular', 'template', 'component', 'html', 'tsx', 'jsx', 'vue', 'react'],
    'backend': ['dto', 'controller', 'service', 'repository', 'api', 'endpoint', 'java'],
    'css': ['scss', 'css', 'color', 'theme', 'dark', 'light', 'style', 'muted', 'token'],
    'dto': ['dto', 'json', 'shape', 'serialize', 'record', 'flat', 'nested'],
    'type': ['typeerror', 'undefined', 'null', 'interface', 'type-safe'],
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
cat_data = [cats[c] for c in dom_cats]
cat_lbl = [c.capitalize() for c in dom_cats]
cat_colors_list = [CAT_COLORS[i % len(CAT_COLORS)] for i in range(len(dom_cats))]

total_sessions = len(sessions)
total_bugs = sum(len(s['bugs']) for s in sessions)
total_fixed = sum(1 for s in sessions for b in s['bugs'].values() if b.get('status') == 'fixed')
total_deferred = sum(1 for s in sessions for b in s['bugs'].values() if b.get('status') == 'deferred')

sess_slugs = [s['slug'] for s in sessions]
sess_fixed = [sum(1 for b in s['bugs'].values() if b.get('status') == 'fixed') for s in sessions]
sess_deferred = [sum(1 for b in s['bugs'].values() if b.get('status') == 'deferred') for s in sessions]

bug_bar = svg_bar(sess_fixed, sess_slugs, [CAT_COLORS[1]]*len(sessions),
    'Bugs Fixed per Session', 500, 220)
if total_deferred > 0:
    bug_bar = svg_bar([sess_fixed[i]+sess_deferred[i] for i in range(len(sessions))],
        sess_slugs, [CAT_COLORS[1]]*len(sessions), 'Bugs Fixed per Session', 500, 220)

donut_chart = svg_donut(
    [total_fixed, total_deferred] if total_deferred > 0 else [total_fixed, 0],
    ['Fixed', 'Deferred'] if total_deferred > 0 else ['Fixed', ''],
    [CAT_COLORS[1], CAT_COLORS[2]], 'Overall Status', 200) if total_bugs > 0 else ''

layers_chart = svg_bar(cat_data, cat_lbl, cat_colors_list,
    'Root Cause Distribution', 500, 220) if dom_cats else ''

html = '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>SDD Debug Report</title>
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
.chart-row{display:grid;grid-template-columns:repeat(auto-fit,minmax(380px,1fr));gap:2rem;margin:2rem 0}
.chart-box{background:#1E293B;border-radius:8px;padding:1rem;text-align:center;min-height:200px}
.chart-box svg{max-width:100%;height:auto}
.agents-section{margin-top:2rem;background:#1E293B;border-radius:8px;padding:1.5rem}
.agents-section pre{background:#0F172A;padding:1rem;border-radius:6px;max-height:none;font-size:.85rem;color:#CBD5E1}
.footer{text-align:center;color:#475569;font-size:.8rem;margin-top:3rem}
</style>
</head>
<body>
<h1>SDD Debug Report</h1>
<p class="subtitle">''' + esc(RUNS_DIR) + ' &mdash; ' + datetime.now().strftime("%Y-%m-%d %H:%M") + '''</p>
<div class="summary-cards">
<div class="card"><div class="num">''' + str(total_sessions) + '''</div><div class="label">Debug Sessions</div></div>
<div class="card"><div class="num">''' + str(total_bugs) + '''</div><div class="label">Bugs Found</div></div>
<div class="card"><div class="num" style="color:#22C55E">''' + str(total_fixed) + '''</div><div class="label">Fixed</div></div>
<div class="card"><div class="num" style="color:#F59E0B">''' + str(total_deferred) + '''</div><div class="label">Deferred</div></div>
</div>'''

if bug_bar or donut_chart:
    html += '<div class="chart-row">'
    if bug_bar:
        html += '<div class="chart-box">' + bug_bar + '</div>'
    if donut_chart:
        html += '<div class="chart-box">' + donut_chart + '</div>'
    html += '</div>'

for s in sessions:
    slug = s['slug']
    bug_count = len(s['bugs'])
    fixed_count = sum(1 for b in s['bugs'].values() if b.get('status') == 'fixed')
    cls = 'fixed' if s['status'] == 'completed' else ''
    html += f'<div class="session {cls}">'
    html += '<div class="session-head">'
    html += f'<div><span class="session-title">{esc(slug)}</span><br><span class="session-meta">{esc(s["rel"])}</span></div>'
    html += f'<span class="session-meta">{fixed_count}/{bug_count} fixed &middot; {esc(s["started_at"][:19])}</span>'
    html += '</div>'
    if s['problem']:
        html += f'<div class="session-problem">{esc(s["problem"])}</div>'

    for bid, bug in s['bugs'].items():
        bcls = bug.get('status', '')
        html += f'<div class="bug {bcls}">'
        html += '<div class="bug-header">'
        html += f'<span class="bug-id">{esc(bid)}</span>'
        html += f'<span class="bug-status {bcls}">{bug.get("status","")}</span>'
        html += '</div>'
        html += f'<div class="bug-desc">{esc(bug.get("description",""))}</div>'
        html += f'<div class="bug-detail"><strong>Root cause:</strong> {esc(bug.get("root_cause",""))}</div>'
        html += f'<div class="bug-detail"><strong>Fix:</strong> {esc(bug.get("fix",""))}</div>'
        html += f'<div class="bug-detail"><strong>Test:</strong> {esc(bug.get("regression_test",""))}</div>'
        if bug.get('knowledge_entry'):
            html += f'<pre>{esc(bug["knowledge_entry"])}</pre>'
        html += '</div>'

    html += '<div class="phases">'
    for pid, pdata in s['phases'].items():
        pstatus = pdata.get('status', '')
        plabel = pid.replace('_', ' ').title()
        html += f'<div class="phase {pstatus}">{esc(plabel)}</div>'
    html += '</div>'

    if s['knowledge']:
        html += '<details><summary style="cursor:pointer;font-size:.8rem;color:#64748B;margin-top:.5rem">Raw report</summary>'
        html += f'<pre>{esc(s["knowledge"])}</pre></details>'
    html += '</div>'

# AGENTS.md entries
agents_entries = []
for s in sessions:
    for b in s['bugs'].values():
        if b.get('knowledge_entry'):
            agents_entries.append(esc(b['knowledge_entry']))

if agents_entries:
    html += '<div class="agents-section">'
    html += '<h2 style="border:none;margin-top:0">AGENTS.md entries</h2>'
    html += '<p style="color:#94A3B8;font-size:.85rem;margin-bottom:1rem">Copy these into your AGENTS.md to prevent similar bugs:</p>'
    html += '<pre>' + '\n\n'.join(agents_entries) + '</pre>'
    html += '</div>'

# Lessons learned
html += '<div class="agents-section" style="margin-top:2rem">'
html += '<h2 style="border:none;margin-top:0">Lessons Learned</h2>'

if layers_chart:
    html += '<h3 style="font-size:1rem;color:#CBD5E1;margin:.5rem 0">Affected Layers</h3>'
    html += '<div class="chart-row" style="grid-template-columns:1fr">'
    html += '<div class="chart-box" style="min-height:180px">' + layers_chart + '</div>'
    html += '</div>'

html += '<h3 style="font-size:1rem;color:#CBD5E1;margin:1rem 0 .5rem">Pattern Analysis</h3>'
html += '<ul style="color:#94A3B8;font-size:.9rem;line-height:1.6;padding-left:1.5rem">'
if dom_cats:
    top = dom_cats[0]
    html += f'<li><strong>Most affected:</strong> {top.capitalize()} layer ({cats[top]} occurrences)</li>'
    if len(dom_cats) > 1:
        sec = dom_cats[1]
        html += f'<li><strong>Secondary:</strong> {sec.capitalize()} layer ({cats[sec]} occurrences)</li>'
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
    html += f'<li><strong>{esc(title)}</strong><br><span style="font-size:.85rem">{esc(desc)}</span></li>'
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
    html += f'<li><strong>{esc(title)}</strong><br><span style="font-size:.85rem">{esc(desc)}</span></li>'
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
        'Mention the Java to Angular field naming convention (camelCase, snake_case if any translation layer).'
    )
if not ctx_items:
    ctx_items.append(
        'Consider adding CONTEXT.md with project module map, key architectural decisions, and common failure patterns.'
    )
for item in ctx_items:
    html += f'<li>{esc(item)}</li>'
html += '</ul>'
html += '</div>'

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
