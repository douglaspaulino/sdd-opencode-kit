#!/usr/bin/env bash
set -euo pipefail

# ── sdd-report — generate HTML execution report from state.json files ──

RUNS_DIR="${1:-.sdd/runs}"
OUTPUT="${2:-.sdd/report.html}"
OPEN_BROWSER="${3:-}"

if [[ ! -d "$RUNS_DIR" ]]; then
    echo "Error: runs directory not found: $RUNS_DIR" >&2
    echo "Usage: sdd-report.sh [.sdd/runs] [output.html] [--open]" >&2
    exit 1
fi

if [[ "${1:-}" == "--open" || "${2:-}" == "--open" || "${3:-}" == "--open" ]]; then
    OPEN_BROWSER="--open"
fi

export SDD_RUNS_DIR="$RUNS_DIR"
export SDD_OUTPUT="$OUTPUT"

python3 << 'PYEOF'
import json, glob, os, re, sys
from datetime import datetime, timezone

RUNS_DIR = os.environ['SDD_RUNS_DIR']
OUTPUT = os.environ['SDD_OUTPUT']

# ── collect data ──────────────────────────────────────────────

tasks = []
state_files = sorted(glob.glob(f'{RUNS_DIR}/**/state.json', recursive=True))
for sf in state_files:
    d = os.path.dirname(sf)
    if not os.path.exists(sf):
        continue
    try:
        state = json.load(open(sf))
    except:
        continue
    tid = os.path.relpath(d, RUNS_DIR)

    # read reports
    def read_report(name):
        p = os.path.join(d, name)
        return open(p).read() if os.path.exists(p) else ''

    impl_report = read_report('implementer-report.md')
    task_review = read_report('task-review.md')
    fixer_report = read_report('fixer-report.md')
    code_review = read_report('code-review.md')
    verifier_report = read_report('verifier-report.md')

    # extract findings from task-review
    findings = []
    if task_review:
        # Parse task-review.md sections:
        #   ### Critical (Must Fix)
        #   #### 1. Title\nDescription
        #   ### Important (Should Fix)
        #   ...
        current_severity = None
        finding_title = None
        finding_text = ''
        for line in task_review.split('\n'):
            # Detect severity section header
            sm = re.match(r'^###\s+(Critical|Important|Minor)\b', line, re.IGNORECASE)
            if sm:
                if current_severity and finding_title:
                    findings.append({
                        'severity': current_severity.lower(),
                        'text': f'{finding_title}: {finding_text.strip()}'[:200]
                    })
                current_severity = sm.group(1)
                finding_title = None
                finding_text = ''
                continue

            # Next section ends current finding
            if line.startswith('## ') or line.startswith('### ') and not re.match(r'^###\s+#', line):
                if finding_title and current_severity:
                    findings.append({
                        'severity': current_severity.lower(),
                        'text': f'{finding_title}: {finding_text.strip()}'[:200]
                    })
                if not re.match(r'^###\s+(Critical|Important|Minor)\b', line, re.IGNORECASE):
                    current_severity = None
                finding_title = None
                finding_text = ''
                continue

            if current_severity:
                # Finding title formats:
                #   #### N. Title
                #   N. **Title** — Description
                fm = re.match(r'^####\s+\d+\.\s*(.+)', line)
                if not fm:
                    fm = re.match(r'^(\d+)\.\s*\*{1,2}(.+?)\*{1,2}', line)
                if fm:
                    if finding_title:
                        findings.append({
                            'severity': current_severity.lower(),
                            'text': f'{finding_title}: {finding_text.strip()}'[:200]
                        })
                    # fm.group(2) for numbered list format, fm.group(1) for #### format
                    finding_title = fm.group(2) if fm.lastindex and fm.lastindex >= 2 else fm.group(1)
                    finding_text = ''
                    # Extract description after — or :
                    rest = line[fm.end():].strip()
                    if rest.startswith('—') or rest.startswith(':'):
                        finding_text = rest[1:].strip() + ' '
                elif finding_title and line.strip():
                    finding_text += line.strip() + ' '

        # Flush last finding
        if current_severity and finding_title:
            findings.append({
                'severity': current_severity.lower(),
                'text': f'{finding_title}: {finding_text.strip()}'[:200]
            })

    # Also parse verdict (some use **verdict**, some use "Verdict: xxx")
    verdict = state['steps'].get('task-reviewer', {}).get('verdict', '')
    if not verdict and task_review:
        vm = re.search(r'\*\*(approved|changes_requested)\*\*', task_review)
        if vm:
            verdict = vm.group(1)
            state['steps'].setdefault('task-reviewer', {})['verdict'] = verdict

    # extract decisions from implementer report
    decisions = []
    in_decisions = False
    if impl_report:
        for line in impl_report.split('\n'):
            if re.match(r'^#+\s*Decisions', line, re.IGNORECASE):
                in_decisions = True
                continue
            if in_decisions and re.match(r'^#+\s', line):
                in_decisions = False
                continue
            if in_decisions and line.strip().startswith('-'):
                decisions.append(line.strip())

    steps = state.get('steps', {})
    total_cost = sum(float(s.get('cost_usd', 0) or 0) for s in steps.values())
    total_execs = sum(int(s.get('executions', 0) or 0) for s in steps.values())

    # duration
    start_ts = None
    end_ts = None
    for s in steps.values():
        sa = s.get('started_at', '')
        fa = s.get('finished_at', '')
        if sa and (start_ts is None or sa < start_ts):
            start_ts = sa
        if fa and (end_ts is None or fa > end_ts):
            end_ts = fa

    duration_str = ''
    if start_ts and end_ts:
        try:
            sdt = datetime.fromisoformat(start_ts.replace('Z', '+00:00'))
            edt = datetime.fromisoformat(end_ts.replace('Z', '+00:00'))
            delta = edt - sdt
            minutes = int(delta.total_seconds() / 60)
            duration_str = f'{minutes // 60}h{minutes % 60}m' if minutes >= 60 else f'{minutes}m'
        except:
            pass

    tasks.append({
        'id': tid,
        'status': state.get('status', '?'),
        'attempts': int(state.get('attempts', 0)),
        'total_cost': total_cost,
        'total_execs': total_execs,
        'steps': steps,
        'duration': duration_str,
        'started': start_ts or '',
        'finished': end_ts or '',
        'findings': findings,
        'decisions': decisions,
        'reports': {
            'implementer': impl_report[:2000],
            'task-review': task_review[:2000],
            'fixer': fixer_report[:1000],
            'code-review': code_review[:1000],
            'verifier': verifier_report[:1000],
        }
    })

# ── aggregate stats ──────────────────────────────────────────

completed = [t for t in tasks if t['status'] == 'completed']
failed = [t for t in tasks if t['status'] == 'failed']
in_progress = [t for t in tasks if t['status'] == 'in_progress']

total_cost_all = sum(t['total_cost'] for t in tasks)
total_steps = sum(len(t['steps']) for t in tasks)
total_execs = sum(t['total_execs'] for t in tasks)

# model usage
model_usage = {}
for t in tasks:
    for s in t['steps'].values():
        m = s.get('model', '')
        if m:
            model_usage[m] = model_usage.get(m, 0) + 1

# verdicts
verdict_counts = {'approved': 0, 'changes_requested': 0, 'pass': 0, 'fail': 0}
for t in tasks:
    for s in t['steps'].values():
        v = s.get('verdict', '')
        if v in verdict_counts:
            verdict_counts[v] += 1

# all findings consolidated
all_findings = []
for t in tasks:
    for f in t.get('findings', []):
        all_findings.append({**f, 'task': t['id']})

# group findings by keyword
from collections import Counter
finding_themes = Counter()
for f in all_findings:
    text = f['text'].lower()
    for theme, keywords in [
        ('test coverage', ['test', 'tdd', 'coverage', 'untest']),
        ('spec compliance', ['spec', 'compliance', 'requirement', 'deviation']),
        ('naming conventions', ['naming', 'rename', 'convention', 'method name']),
        ('type safety', ['enum', 'string', 'type', 'integer', 'long']),
        ('scss/styles', ['scss', 'css', 'style', 'extend', 'class']),
        ('api design', ['endpoint', 'controller', 'api', 'parameter', 'signature']),
        ('error handling', ['error', 'exception', 'catch', 'handle']),
        ('performance', ['performance', 'slow', 'optimize', 'cache']),
    ]:
        if any(kw in text for kw in keywords):
            finding_themes[theme] += 1

# ── AGENTS.md suggestions ─────────────────────────────────────

skill_suggestions = []
ref_suggestions = []

# Based on recurring themes, suggest skills
if finding_themes.get('test coverage', 0) >= 2:
    skill_suggestions.append({
        'name': 'tdd-enforcer',
        'why': f'{finding_themes["test coverage"]} tasks with test coverage issues — a skill to verify RED→GREEN cycles and enforce TDD discipline automatically',
    })
if finding_themes.get('spec compliance', 0) >= 2:
    skill_suggestions.append({
        'name': 'spec-compliance-checker',
        'why': f'{finding_themes["spec compliance"]} tasks with spec divergence — a skill that cross-references implementation against task spec before review',
    })
if finding_themes.get('naming conventions', 0) >= 2:
    skill_suggestions.append({
        'name': 'naming-linter',
        'why': f'{finding_themes["naming conventions"]} naming convention violations — a skill to enforce project naming standards across backend and frontend',
    })
if finding_themes.get('type safety', 0) >= 2:
    skill_suggestions.append({
        'name': 'type-safety-guard',
        'why': f'{finding_themes["type safety"]} type/enum issues — a skill to validate JPA entities, DTOs, and enums match database schema',
    })

# Reference suggestions for AGENTS.md
if any('scss' in f.get('text', '').lower() for f in all_findings) or finding_themes.get('scss/styles', 0) >= 1:
    ref_suggestions.append({
        'section': 'Frontend Standards',
        'entry': 'Avoid SCSS @extend self-references. Use mixins or direct class application for shared styles.',
    })

# model diversity
unique_models = set()
for t in tasks:
    for s in t['steps'].values():
        m = s.get('model', '')
        if m: unique_models.add(m)

ref_suggestions.append({
    'section': 'SDD Pipeline',
    'entry': f'Models used across pipeline: {", ".join(sorted(unique_models))}. Task reviewer consistently used flash/plus models. Code reviewer used qwen3.7-plus.',
})

# decisions summary
all_decisions = []
for t in tasks:
    all_decisions.extend(t.get('decisions', []))

if len(all_decisions) > 0:
    ref_suggestions.append({
        'section': 'Architecture Decisions',
        'entry': f'Recorded {len(all_decisions)} implementation decisions across {len(tasks)} tasks. Review for ADR candidates.',
    })

# ── /init prompt generation ────────────────────────────────────

# classify text into codebase areas
BACKEND_KW = ['java', 'spring', 'jpa', 'hibernate', 'repository', 'entity', 'dto', 'mapper',
              'controller', 'service', 'junit', 'mockito', 'mvn', 'maven', 'sql', 'migration',
              'enum', '@enumerated', 'indexer', 'column', 'table', 'endpoint', 'api']
FRONTEND_KW = ['angular', 'component', 'template', 'html', 'scss', 'css', 'i18n', 'typescript',
               'modal', 'snackbar', 'toast', 'checkbox', 'toggle', 'rxjs', 'ng-', 'routing',
               '@component', 'chart', 'legend', 'tooltip', 'card', 'button', 'formcontrol']
DB_KW = ['sql', 'migration', 'postgresql', 'mysql', 'column', 'table', 'index', 'fk', 'constraint',
         'ddl', 'database', 'schema', 'varchar', 'innodb']

def classify_codebase(text):
    text_l = text.lower()
    scores = {'backend': 0, 'frontend': 0, 'database': 0}
    for kw in BACKEND_KW:
        if kw in text_l: scores['backend'] += 1
    for kw in FRONTEND_KW:
        if kw in text_l: scores['frontend'] += 1
    for kw in DB_KW:
        if kw in text_l: scores['database'] += 1
    best = max(scores, key=scores.get)
    return best if scores[best] > 1 else 'general'

# categorize findings
cb_findings = {'backend': [], 'frontend': [], 'database': [], 'general': []}
for f in all_findings:
    cb = classify_codebase(f['text'])
    cb_findings[cb].append(f)

# categorize decisions
cb_decisions = {'backend': [], 'frontend': [], 'database': [], 'general': []}
for d in all_decisions:
    cb = classify_codebase(d)
    cb_decisions[cb].append(d)

# detect technology stack per codebase
stack_backend = []
stack_frontend = []
stack_db = []

all_text = ' '.join(f['text'].lower() for f in all_findings)
for t in tasks:
    for rn, rp in t.get('reports', {}).items():
        all_text += ' ' + rp.lower()[:2000]

if any(kw in all_text for kw in ['java', 'spring', 'jpa', 'hibernate']):
    stack_backend.append('Java 17+')
    stack_backend.append('Spring Boot')
if any(kw in all_text for kw in ['mvn', 'maven']):
    stack_backend.append('Maven')
if any(kw in all_text for kw in ['junit', 'mockito', 'testcontainers']):
    stack_backend.append('JUnit 5 + Mockito')

if any(kw in all_text for kw in ['angular', '@component', 'ng-']):
    stack_frontend.append('Angular')
else:
    stack_frontend.append('Angular/TypeScript')
if any(kw in all_text for kw in ['scss', 'sass']):
    stack_frontend.append('SCSS')
if any(kw in all_text for kw in ['jasmine', 'karma', 'ng test']):
    stack_frontend.append('Jasmine + Karma')

if any(kw in all_text for kw in ['postgresql', 'postgres', 'mysql', 'sql']):
    stack_db.append('PostgreSQL')

stack_backend = stack_backend or ['Java', 'Spring Boot']
stack_frontend = stack_frontend or ['Angular/TypeScript']
stack_db = stack_db or ['(detect from migrations)']

# build per-codebase conventions
def build_conventions(findings_list):
    lines = set()
    for f in findings_list:
        text = f['text'].lower()
        if 'extend' in text and 'scss' in text:
            lines.add('Avoid SCSS @extend self-references — use mixins or direct classes')
        if 'enum' in text and ('string' in text or 'type' in text):
            lines.add('Use enums with @Enumerated(STRING) for bounded domain values — never String')
        if 'uuid' in text and ('exposed' in text or 'route' in text or 'public' in text):
            lines.add('UUID as public identifier; numeric IDs never exposed in API paths/routes')
        if 'toast' in text or 'snackbar' in text:
            lines.add('Show success/error feedback via MatSnackBar (toast) after CRUD operations')
        if 'loading' in text or 'empty' in text or 'error' in text:
            lines.add('Every view must handle loading, empty, and error states')
        if 'toggle' in text and 'checkbox' in text:
            lines.add('Use toggle switches for boolean settings, not plain checkboxes')
        if 'naming' in text or 'rename' in text:
            lines.add('Match existing naming patterns — check conventions before introducing new names')
        if 'i18n' in text:
            lines.add('All user-facing strings must use i18n keys, not hardcoded text')
        if '@responsebody' in text and 'restcontroller' in text:
            lines.add('No redundant @ResponseBody on @RestController methods')
        if 'mapper' in text or 'dto' in text:
            lines.add('Use DTOs with explicit mappers; never expose entities in API responses')
    return sorted(lines)

cb_conventions = {}
for cb_name in ['backend', 'frontend', 'database']:
    cb_conventions[cb_name] = build_conventions(cb_findings[cb_name])

# build per-codebase theme counts
def theme_counts_for(findings_list):
    tc = Counter()
    for f in findings_list:
        text = f['text'].lower()
        for theme, keywords in [
            ('test coverage', ['test', 'tdd', 'coverage', 'untest']),
            ('spec compliance', ['spec', 'compliance', 'requirement', 'deviation']),
            ('type safety', ['enum', 'string', 'type', 'integer', 'long']),
            ('naming conventions', ['naming', 'rename', 'convention', 'method name']),
            ('scss/styles', ['scss', 'css', 'style', 'extend', 'class']),
            ('api design', ['endpoint', 'controller', 'api', 'parameter', 'signature']),
            ('error handling', ['error', 'exception', 'catch', 'handle']),
            ('ui/ux patterns', ['modal', 'toast', 'snackbar', 'loading', 'empty', 'toggle', 'checkbox', 'button', 'card']),
            ('performance', ['performance', 'slow', 'optimize', 'cache']),
        ]:
            if any(kw in text for kw in keywords):
                tc[theme] += 1
    return tc

cb_themes = {}
for cb_name in ['backend', 'frontend', 'database']:
    tc = theme_counts_for(cb_findings[cb_name])
    top = sorted(tc.items(), key=lambda x: -x[1])[:3]
    cb_themes[cb_name] = ', '.join(f'{t} ({c})' for t, c in top) if top else 'none detected'

# build ADR suggestions per codebase
cb_adrs = {}
for cb_name in ['backend', 'frontend', 'database']:
    decs = cb_decisions[cb_name]
    if decs:
        # summarize to keep prompt compact
        short = [d[:120].replace('- ', '').strip() for d in decs]
        cb_adrs[cb_name] = '\n    - ' + '\n    - '.join(short[:6])
    else:
        cb_adrs[cb_name] = ' (none in this run)'

# model assignments
model_roles = {}
for t in tasks:
    for sn, sd in t['steps'].items():
        m = sd.get('model', '')
        if m and sn not in model_roles:
            model_roles[sn] = m
model_text = ', '.join(f'{sn}={m}' for sn, m in sorted(model_roles.items())) if model_roles else 'varies'

# skill list
skill_list = ', '.join(f'@{s["name"]}' for s in skill_suggestions) if skill_suggestions else '(none suggested)'

# build combined /init prompt with per-codebase sections
init_prompt = '/init Analyze .sdd/report.html and the codebase, then enhance AGENTS.md with per-codebase sections:\n'

# Backend section
init_prompt += f'''
### Backend ({", ".join(stack_backend + stack_db)})
- Testing: TDD with RED→GREEN cycles. Run `mvn test` before reporting. Output must be pristine.
- Code review priorities: {cb_themes['backend']}
- Conventions:'''
if cb_conventions['backend']:
    for c in cb_conventions['backend']:
        init_prompt += f'\n  - {c}'
else:
    init_prompt += '\n  - (review findings for patterns)'
init_prompt += f'''
- ADR candidates:{cb_adrs['backend']}'''

# Frontend section
init_prompt += f'''

### Frontend ({", ".join(stack_frontend)})
- Testing: TDD with RED→GREEN cycles. Run `ng test` before reporting. Output must be pristine.
- Code review priorities: {cb_themes['frontend']}
- Conventions:'''
if cb_conventions['frontend']:
    for c in cb_conventions['frontend']:
        init_prompt += f'\n  - {c}'
else:
    init_prompt += '\n  - (review findings for patterns)'
init_prompt += f'''
- ADR candidates:{cb_adrs['frontend']}'''

# Cross-cutting section
init_prompt += f'''

### Cross-cutting (all codebases)
- Auto-load skills: {skill_list}
- Pipeline model assignments: {model_text}
- All tasks: {len(tasks)} total, {len(completed)} completed, {len(failed)} failed, ${total_cost_all:.2f} total cost
- {len(all_findings)} findings across {len(tasks)} tasks — address recurring patterns in AGENTS.md
- {len(all_decisions)} architecture decisions recorded — flag the most impactful as ADRs'''

# ── HTML generation ───────────────────────────────────────────

def esc(s):
    if not s: return ''
    return str(s).replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;').replace('"', '&quot;')

def fmt_cost(c):
    return f'${float(c):.4f}'

def badge(status):
    colors = {
        'completed': '#22c55e', 'pass': '#22c55e', 'approved': '#22c55e',
        'in_progress': '#f59e0b', 'pending': '#6b7280',
        'failed': '#ef4444', 'changes_requested': '#f59e0b', 'fail': '#ef4444',
    }
    c = colors.get(status, '#6b7280')
    return f'<span style="background:{c};color:#fff;padding:2px 8px;border-radius:4px;font-size:12px">{status}</span>'

def step_duration(started, finished):
    if not started or not finished: return ''
    try:
        s = datetime.fromisoformat(started.replace('Z', '+00:00'))
        e = datetime.fromisoformat(finished.replace('Z', '+00:00'))
        d = (e - s).total_seconds()
        return f'{d/60:.0f}m' if d < 3600 else f'{d/3600:.1f}h'
    except:
        return ''

# chart data
task_labels = json.dumps([t['id'][:25] for t in tasks])
task_costs = json.dumps([round(t['total_cost'], 4) for t in tasks])

model_labels = json.dumps([k for k, _ in sorted(model_usage.items(), key=lambda x: -x[1])[:8]])
model_counts = json.dumps([v for _, v in sorted(model_usage.items(), key=lambda x: -x[1])[:8]])

verdict_labels = json.dumps(list(verdict_counts.keys()))
verdict_counts_json = json.dumps(list(verdict_counts.values()))

cost_by_step = {'implementer': 0, 'task-reviewer': 0, 'fixer': 0, 'code-reviewer': 0, 'verifier': 0}
for t in tasks:
    for sn, sd in t['steps'].items():
        if sn in cost_by_step:
            cost_by_step[sn] += float(sd.get('cost_usd', 0) or 0)
step_labels = json.dumps(list(cost_by_step.keys()))
step_costs_json = json.dumps([round(v, 4) for v in cost_by_step.values()])

html = f'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>SDD Pipeline Report</title>
<script src="https://cdn.jsdelivr.net/npm/chart.js@4"></script>
<style>
  * {{ margin:0;padding:0;box-sizing:border-box; }}
  body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #0f1117; color: #e1e4e8; line-height:1.6; }}
  .container {{ max-width:1400px; margin:0 auto; padding:24px; }}
  h1 {{ font-size:28px; margin-bottom:4px; color:#fff; }}
  h2 {{ font-size:20px; margin:32px 0 16px; color:#c9d1d9; border-bottom:1px solid #30363d; padding-bottom:8px; }}
  h3 {{ font-size:16px; margin:16px 0 8px; color:#adbac7; }}
  .subtitle {{ color:#8b949e; margin-bottom:24px; font-size:14px; }}
  .cards {{ display:grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap:16px; margin-bottom:32px; }}
  .card {{ background:#161b22; border:1px solid #30363d; border-radius:8px; padding:20px; }}
  .card-label {{ font-size:12px; color:#8b949e; text-transform:uppercase; letter-spacing:0.5px; }}
  .card-value {{ font-size:28px; font-weight:700; color:#fff; margin-top:4px; }}
  .card-value.green {{ color:#22c55e; }} .card-value.yellow {{ color:#f59e0b; }} .card-value.red {{ color:#ef4444; }}
  .charts {{ display:grid; grid-template-columns: repeat(auto-fit, minmax(400px, 1fr)); gap:24px; margin-bottom:32px; }}
  .chart-box {{ background:#161b22; border:1px solid #30363d; border-radius:8px; padding:20px; }}
  .chart-box canvas {{ max-height:300px; }}
  table {{ width:100%; border-collapse:collapse; font-size:14px; }}
  th {{ text-align:left; padding:10px 12px; border-bottom:2px solid #30363d; color:#8b949e; font-weight:600; font-size:12px; text-transform:uppercase; }}
  td {{ padding:10px 12px; border-bottom:1px solid #21262d; }}
  tr:hover {{ background:rgba(255,255,255,0.03); }}
  .task-row {{ cursor:pointer; }}
  .task-detail {{ display:none; background:#0d1117; border:1px solid #30363d; border-radius:6px; padding:16px; margin:8px 0 16px 0; }}
  .task-detail.active {{ display:block; }}
  .step-grid {{ display:grid; grid-template-columns: repeat(5, 1fr); gap:12px; margin-top:12px; }}
  .step-card {{ background:#161b22; border:1px solid #21262d; border-radius:6px; padding:12px; font-size:13px; }}
  .step-card .step-name {{ font-weight:600; color:#58a6ff; text-transform:capitalize; margin-bottom:8px; }}
  .step-card .step-stat {{ margin:4px 0; }}
  .step-card .step-stat span {{ color:#8b949e; }}
  .findings {{ margin-top:16px; }}
  .finding {{ background:#161b22; border-left:3px solid #f59e0b; padding:8px 12px; margin:8px 0; border-radius:0 4px 4px 0; font-size:13px; }}
  .finding.critical {{ border-left-color:#ef4444; }}
  .finding.important {{ border-left-color:#f59e0b; }}
  .finding.minor {{ border-left-color:#6b7280; }}
  .suggestions {{ display:grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap:16px; margin-top:16px; }}
  .suggestion {{ background:#161b22; border:1px solid #30363d; border-radius:8px; padding:16px; }}
  .suggestion h4 {{ color:#58a6ff; margin-bottom:8px; }}
  .suggestion p {{ font-size:14px; color:#8b949e; }}
  .ref {{ background:#161b22; border-left:3px solid #58a6ff; padding:8px 12px; margin:8px 0; border-radius:0 4px 4px 0; font-size:13px; }}
  .ref strong {{ color:#58a6ff; }}
  .report-preview {{ max-height:300px; overflow-y:auto; background:#0d1117; border:1px solid #21262d; border-radius:4px; padding:12px; font-family:monospace; font-size:12px; white-space:pre-wrap; color:#8b949e; }}
  .timeline {{ display:flex; align-items:center; gap:4px; margin:8px 0; flex-wrap:wrap; }}
  .timeline-dot {{ width:10px; height:10px; border-radius:50%; display:inline-block; }}
  .timeline-dot.completed {{ background:#22c55e; }}
  .timeline-dot.in_progress {{ background:#f59e0b; animation:pulse 1.5s infinite; }}
  .timeline-dot.pending {{ background:#6b7280; }}
  .timeline-dot.failed {{ background:#ef4444; }}
  @keyframes pulse {{ 0%,100%{{ opacity:1; }} 50%{{ opacity:0.4; }} }}
  .empty-state {{ text-align:center; padding:40px; color:#6b7280; }}
  footer {{ text-align:center; padding:32px 0; color:#484f58; font-size:12px; border-top:1px solid #21262d; margin-top:40px; }}
</style>
</head>
<body>
<div class="container">

<h1>SDD Pipeline Report</h1>
<div class="subtitle">Generated {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')} · {len(tasks)} tasks · {total_execs} step executions</div>

<!-- DASHBOARD CARDS -->
<div class="cards">
  <div class="card">
    <div class="card-label">Tasks</div>
    <div class="card-value">{len(completed)} <span style="font-size:14px;color:#22c55e">done</span></div>
    <div style="margin-top:8px;font-size:13px;color:#8b949e">{len(failed)} failed · {len(in_progress)} in progress</div>
  </div>
  <div class="card">
    <div class="card-label">Total Cost</div>
    <div class="card-value green">${total_cost_all:.2f}</div>
    <div style="margin-top:8px;font-size:13px;color:#8b949e">${total_cost_all/len(tasks):.2f} avg / task</div>
  </div>
  <div class="card">
    <div class="card-label">Verdicts</div>
    <div class="card-value">{verdict_counts["approved"]} <span style="font-size:14px;color:#22c55e">approved</span></div>
    <div style="margin-top:8px;font-size:13px;color:#8b949e">{verdict_counts["changes_requested"]} changes · {verdict_counts["pass"]} passed</div>
  </div>
  <div class="card">
    <div class="card-label">Models Used</div>
    <div class="card-value">{len(unique_models)}</div>
    <div style="margin-top:8px;font-size:13px;color:#8b949e">{len(model_usage)} step assignments</div>
  </div>
</div>

<!-- CHARTS -->
<div class="charts">
  <div class="chart-box">
    <h3>Cost by Task</h3>
    <canvas id="costByTask"></canvas>
  </div>
  <div class="chart-box">
    <h3>Cost by Step Type</h3>
    <canvas id="costByStep"></canvas>
  </div>
  <div class="chart-box">
    <h3>Model Usage</h3>
    <canvas id="modelUsage"></canvas>
  </div>
  <div class="chart-box">
    <h3>Verdict Distribution</h3>
    <canvas id="verdicts"></canvas>
  </div>
</div>

<!-- TASK TABLE -->
<h2>Tasks</h2>
<table>
<thead><tr>
  <th>Task</th>
  <th>Status</th>
  <th>Cost</th>
  <th>Steps</th>
  <th>Duration</th>
  <th>Started</th>
</tr></thead>
<tbody>
'''

for t in tasks:
    steps_html = ''.join(
        f'<span class="timeline-dot {sd["status"]}" title="{sn}: {sd["status"]}"></span> '
        for sn, sd in t['steps'].items()
    )
    st = t['started'][:16].replace('T', ' ') if t['started'] else '-'
    cost_class = 'green' if t['total_cost'] > 0.5 else ('yellow' if t['total_cost'] > 0 else '')
    html += f'''<tr class="task-row" onclick="toggleDetail('{t["id"]}')">
  <td><strong>{esc(t['id'])}</strong></td>
  <td>{badge(t["status"])}</td>
  <td style="color:{'#22c55e' if cost_class == 'green' else '#f59e0b' if cost_class == 'yellow' else '#8b949e'}">{fmt_cost(t["total_cost"])}</td>
  <td>{steps_html}</td>
  <td>{t["duration"]}</td>
  <td style="font-size:12px;color:#8b949e">{st}</td>
</tr>
<tr id="detail-{t['id']}" class="task-detail"><td colspan="6">
  <div class="step-grid">
'''

    for sn in ['implementer', 'task-reviewer', 'fixer', 'code-reviewer', 'verifier']:
        sd = t['steps'].get(sn, {})
        dur = step_duration(sd.get('started_at', ''), sd.get('finished_at', ''))
        html += f'''    <div class="step-card">
      <div class="step-name">{sn}</div>
      <div class="step-stat"><span>Status:</span> {badge(sd.get('status', '?'))}</div>
      <div class="step-stat"><span>Cost:</span> {fmt_cost(sd.get('cost_usd', 0))}</div>
      <div class="step-stat"><span>Model:</span> {esc(sd.get('model', '-'))}</div>
      <div class="step-stat"><span>Exec:</span> {sd.get('executions', '-')}x</div>
      <div class="step-stat"><span>Duration:</span> {dur or '-'}</div>
      {f'<div class="step-stat"><span>Verdict:</span> {badge(sd.get("verdict",""))}</div>' if sd.get('verdict') else ''}
    </div>
'''

    # findings for this task
    if t['findings']:
        html += '  </div><div class="findings"><strong style="color:#f59e0b">Review Findings</strong>'
        for f in t['findings']:
            html += f'<div class="finding {f["severity"]}"><strong>{f["severity"].title()}:</strong> {esc(f["text"])}</div>'
        html += '</div>'

    # decisions
    if t['decisions']:
        decisions_txt = '<br>'.join(esc(d) for d in t['decisions'])
        html += f'<div class="findings"><strong style="color:#58a6ff">Implementation Decisions</strong><div style="margin-top:8px;font-size:13px;color:#8b949e">{decisions_txt}</div></div>'

    # report preview
    impl_rp = t['reports'].get('implementer', '')
    if impl_rp.strip():
        preview = esc(impl_rp[:1500])
        html += f'<details style="margin-top:12px"><summary style="color:#58a6ff;cursor:pointer;font-size:13px">Implementer Report</summary><div class="report-preview" style="margin-top:8px">{preview}</div></details>'

    tr = t['reports'].get('task-review', '')
    if tr.strip():
        preview = esc(tr[:1000])
        html += f'<details style="margin-top:8px"><summary style="color:#f59e0b;cursor:pointer;font-size:13px">Task Review</summary><div class="report-preview" style="margin-top:8px">{preview}</div></details>'

    html += '\n</td></tr>\n'

html += '</tbody></table>\n'

# ── CONSOLIDATED ANALYSIS ──

html += '<h2>Consolidated Analysis</h2>'

if finding_themes:
    html += '<div class="cards">'
    for theme, count in sorted(finding_themes.items(), key=lambda x: -x[1])[:8]:
        html += f'''<div class="card">
  <div class="card-label">{theme}</div>
  <div class="card-value yellow">{count}</div>
  <div style="font-size:13px;color:#8b949e">occurrences</div>
</div>
'''
    html += '</div>'

# all findings list
if all_findings:
    html += '<h3>All Findings</h3>'
    for f in sorted(all_findings, key=lambda x: {'critical': 0, 'important': 1, 'minor': 2}.get(x['severity'], 3)):
        html += f'<div class="finding {f["severity"]}"><strong>{f["severity"].title()}</strong> [{esc(f["task"])}]: {esc(f["text"])}</div>'
else:
    html += '<div class="empty-state">No findings detected in task reviews.</div>'

# ── AGENTS.md SUGGESTIONS ──

html += '<h2>Suggestions for AGENTS.md</h2>'

if skill_suggestions:
    html += '<h3>New Skills to Consider</h3><div class="suggestions">'
    for s in skill_suggestions:
        html += f'<div class="suggestion"><h4>@skill: {esc(s["name"])}</h4><p>{esc(s["why"])}</p></div>'
    html += '</div>'

if ref_suggestions:
    html += '<h3>References to Add</h3>'
    for r in ref_suggestions:
        html += f'<div class="ref"><strong>[{esc(r["section"])}]</strong> {esc(r["entry"])}</div>'

if not skill_suggestions and not ref_suggestions:
    html += '<div class="empty-state">Not enough data to generate suggestions. Run more tasks through the pipeline.</div>'

# ── /init PROMPT ──
html += '<h2>Prompt for /init</h2>'
html += '<p style="color:#8b949e;font-size:14px;margin-bottom:12px">Copy this prompt into opencode to increment AGENTS.md with per-codebase sections — conventions, test rules, ADR candidates, and skill assignments extracted from the pipeline findings.</p>'
html += '<div style="background:#0d1117;border:1px solid #30363d;border-radius:8px;padding:16px;position:relative">'
html += '<button onclick="copyInitPrompt()" style="position:absolute;top:8px;right:8px;background:#30363d;color:#c9d1d9;border:none;border-radius:4px;padding:4px 12px;cursor:pointer;font-size:12px" id="copyBtn">Copy</button>'
html += f'<pre style="white-space:pre-wrap;font-family:monospace;font-size:13px;color:#e1e4e8;line-height:1.6;margin:0;padding-top:8px" id="initPrompt">{esc(init_prompt)}</pre>'
html += '</div>'

html += f'''
<footer>
  Generated by sdd-report · SDD Pipeline · {datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")}
</footer>
</div><!-- container -->

<script>
function toggleDetail(id) {{
  var el = document.getElementById('detail-' + id);
  if (el) el.classList.toggle('active');
}}

function copyInitPrompt() {{
  var pre = document.getElementById('initPrompt');
  var btn = document.getElementById('copyBtn');
  navigator.clipboard.writeText(pre.textContent).then(function() {{
    btn.textContent = 'Copied!';
    setTimeout(function() {{ btn.textContent = 'Copy'; }}, 2000);
  }});
}}

// CHART: Cost by Task
new Chart(document.getElementById('costByTask'), {{
  type: 'bar',
  data: {{
    labels: {task_labels},
    datasets: [{{
      label: 'Cost (USD)',
      data: {task_costs},
      backgroundColor: '#58a6ff88',
      borderColor: '#58a6ff',
      borderWidth: 1
    }}]
  }},
  options: {{
    responsive: true,
    plugins: {{ legend: {{ display: false }} }},
    scales: {{
      y: {{ ticks: {{ color: '#8b949e', callback: v => '$' + v.toFixed(2) }}, grid: {{ color: '#21262d' }} }},
      x: {{ ticks: {{ color: '#8b949e', maxRotation: 45, font: {{ size: 10 }} }}, grid: {{ display: false }} }}
    }}
  }}
}});

// CHART: Cost by Step Type
new Chart(document.getElementById('costByStep'), {{
  type: 'bar',
  data: {{
    labels: {step_labels},
    datasets: [{{
      label: 'Cost (USD)',
      data: {step_costs_json},
      backgroundColor: ['#ef444488','#f59e0b88','#22c55e88','#58a6ff88','#a855f788'],
      borderColor: ['#ef4444','#f59e0b','#22c55e','#58a6ff','#a855f7'],
      borderWidth: 1
    }}]
  }},
  options: {{
    responsive: true,
    plugins: {{ legend: {{ display: false }} }},
    scales: {{
      y: {{ ticks: {{ color: '#8b949e', callback: v => '$' + v.toFixed(2) }}, grid: {{ color: '#21262d' }} }},
      x: {{ ticks: {{ color: '#8b949e' }}, grid: {{ display: false }} }}
    }}
  }}
}});

// CHART: Model Usage
new Chart(document.getElementById('modelUsage'), {{
  type: 'doughnut',
  data: {{
    labels: {model_labels},
    datasets: [{{
      data: {model_counts},
      backgroundColor: ['#58a6ff','#22c55e','#f59e0b','#ef4444','#a855f7','#ec4899','#14b8a6','#f97316'],
      borderColor: '#161b22',
      borderWidth: 2
    }}]
  }},
  options: {{
    responsive: true,
    plugins: {{ legend: {{ position: 'right', labels: {{ color: '#8b949e', font: {{ size: 11 }} }} }} }}
  }}
}});

// CHART: Verdict Distribution
new Chart(document.getElementById('verdicts'), {{
  type: 'doughnut',
  data: {{
    labels: {verdict_labels},
    datasets: [{{
      data: {verdict_counts_json},
      backgroundColor: ['#22c55e','#f59e0b','#58a6ff','#ef4444'],
      borderColor: '#161b22',
      borderWidth: 2
    }}]
  }},
  options: {{
    responsive: true,
    plugins: {{ legend: {{ position: 'right', labels: {{ color: '#8b949e', font: {{ size: 11 }} }} }} }}
  }}
}});
</script>
</body>
</html>
'''

with open(OUTPUT, 'w') as f:
    f.write(html)

print(f'Report generated: {os.path.abspath(OUTPUT)}')
print(f'  {len(tasks)} tasks · {len(completed)} completed · ${total_cost_all:.2f} total cost')
print(f'  {len(all_findings)} findings · {len(skill_suggestions)} skill suggestions · {len(ref_suggestions)} AGENTS.md entries')
PYEOF

if [[ "$OPEN_BROWSER" == "--open" ]]; then
    if command -v xdg-open &>/dev/null; then
        xdg-open "$OUTPUT" 2>/dev/null || true
    elif command -v open &>/dev/null; then
        open "$OUTPUT" 2>/dev/null || true
    fi
fi
