#!/usr/bin/env python3
"""draft-html.py — generate a publish-draft decision panel.

Reads signals.sh --json, lists candidates, generates HTML with 3 action buttons:
  1. publish        → copy a "publish now" prompt to claude code
  2. add more       → copy a "I want to add <plat>" prompt
  3. deny publish   → copy an "abort" prompt

Auto-opens unless MAXPUBLISH_CI=1.
"""
import json
import os
import subprocess
import sys
from pathlib import Path

MAXPUBLISH_HOME = os.environ.get("MAXPUBLISH_HOME", str(Path(__file__).resolve().parent.parent))
SIGNALS = os.path.join(MAXPUBLISH_HOME, "scripts", "signals.sh")

def main():
    sig = json.loads(subprocess.check_output(["bash", SIGNALS, "--json"], text=True))
    cands = sig.get("candidates", [])
    version = sig.get("version", "0.0.0")
    cwd = os.getcwd()

    if not cands:
        print("no publishable candidates.")
        return

    rows = "\n".join(
        f'<tr><td><span class="{"hi" if c["confidence"]=="high" else "med"}">'
        f'{"✓" if c["confidence"]=="high" else "?"}</span></td>'
        f'<td><code>{c["platform"]}</code></td>'
        f'<td>{c["signal"]["type"]}</td>'
        f'<td>{c["confidence"]}</td></tr>'
        for c in cands
    )
    platforms = ", ".join(c["platform"] for c in cands)
    high_only = ", ".join(c["platform"] for c in cands if c["confidence"] == "high")
    med_only = ", ".join(c["platform"] for c in cands if c["confidence"] == "medium")

    html = f"""<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<title>maxpublish — draft for {Path(cwd).name} v{version}</title>
<style>
:root{{--ink:#101418;--muted:#5b6168;--line:#e6e6ea;--bg:#fbfbfc;--card:#fff;--ok:#16a34a;--warn:#d97706}}
*{{box-sizing:border-box}}html,body{{margin:0;background:var(--bg);color:var(--ink);
  font:15px/1.6 -apple-system,"PingFang SC","Hiragino Sans GB",sans-serif}}
body{{max-width:840px;margin:0 auto;padding:40px 24px 200px}}
h1{{font-size:26px;margin:0 0 4px}}
.sub{{color:var(--muted);margin:0 0 24px}}
table{{width:100%;border-collapse:collapse;margin:18px 0}}
th,td{{padding:10px 12px;text-align:left;border-bottom:1px solid var(--line)}}
th{{background:#fafafa;font-weight:600}}
.hi{{color:var(--ok);font-weight:700}}
.med{{color:var(--warn);font-weight:700}}
code{{background:#f4f4f5;padding:1px 5px;border-radius:3px;font-size:13px}}
.actions{{position:fixed;left:0;right:0;bottom:0;background:#fff;border-top:1px solid var(--line);
         padding:16px 24px;display:flex;gap:10px;justify-content:center;flex-wrap:wrap}}
.actions button{{font:14px var(--sans);background:#101418;color:#fff;border:0;
                border-radius:6px;padding:12px 20px;cursor:pointer}}
.actions .primary{{background:#16a34a}}
.actions .primary:hover{{background:#15803d}}
.actions .add{{background:#2563eb}}
.actions .add:hover{{background:#1d4ed8}}
.actions .deny{{background:#dc2626}}
.actions .deny:hover{{background:#b91c1c}}
.actions .copy{{background:#6366f1;font-size:13px;padding:6px 12px}}
.toast{{position:fixed;bottom:120px;left:50%;transform:translateX(-50%);
       background:#101418;color:#e6e6ea;padding:8px 14px;border-radius:6px;
       font:13px var(--sans);opacity:0;transition:.2s;pointer-events:none}}
.toast.show{{opacity:1}}
.notes{{background:#fef9c3;border:1px solid #facc15;border-radius:6px;padding:12px;margin:18px 0;font-size:13px}}
.add-platforms{{background:#f8fafc;border:1px solid var(--line);border-radius:6px;padding:14px;margin:18px 0}}
.add-platforms label{{display:inline-block;margin:4px 8px;cursor:pointer;font-size:13px}}
.add-platforms input{{margin-right:4px}}
</style>
</head>
<body>
<h1>maxpublish · publish draft</h1>
<p class="sub">cwd: <code>{cwd}</code> · version: <code>{version}</code></p>

<h3>Auto-detected candidates</h3>
<table>
<thead><tr><th></th><th>platform</th><th>signal</th><th>confidence</th></tr></thead>
<tbody>
{rows}
</tbody>
</table>

<div class="notes">
<strong>✓ high</strong> = auto-default, will publish without asking<br>
<strong>? medium</strong> = ambiguous signal (git, GHCR workflow, brew formula), confirm in actions
</div>

<div class="add-platforms">
<strong>Add more platforms (not auto-detected):</strong><br>
<label><input type="checkbox" value="amo"> AMO (Firefox)</label>
<label><input type="checkbox" value="chrome-web-store"> Chrome Web Store</label>
<label><input type="checkbox" value="edge-addons"> Edge Add-ons</label>
<label><input type="checkbox" value="brew"> Homebrew tap</label>
<label><input type="checkbox" value="ghcr"> GHCR</label>
<label><input type="checkbox" value="cargo"> crates.io</label>
<label><input type="checkbox" value="gem"> RubyGems</label>
</div>

<div class="actions">
  <button class="primary" data-action="publish">✅ publish all</button>
  <button class="add" data-action="publish-high">✓ publish high-confidence only</button>
  <button class="add" data-action="add-more">➕ publish with extras</button>
  <button class="deny" data-action="deny">✗ deny publish</button>
</div>

<div class="toast" id="toast">copied ✓</div>

<script>
const data = {{
  cwd: {json.dumps(cwd)},
  version: {json.dumps(version)},
  candidates: {json.dumps([c["platform"] for c in cands])},
  highOnly: {json.dumps(high_only.split(", ") if high_only else [])},
  medOnly: {json.dumps(med_only.split(", ") if med_only else [])},
  all: {json.dumps(platforms)}
}};

function copy(text) {{
  navigator.clipboard.writeText(text);
  const t = document.getElementById('toast');
  t.textContent = 'copied ✓';
  t.classList.add('show');
  setTimeout(() => t.classList.remove('show'), 1500);
}}

document.addEventListener('click', (e) => {{
  const action = e.target.dataset.action;
  if (!action) return;
  const extras = [...document.querySelectorAll('.add-platforms input:checked')].map(i => i.value);
  let msg;
  if (action === 'publish') {{
    const all = [...data.candidates, ...extras];
    msg = `/maxpublish approve: publish v${{data.version}} to: ${{all.join(', ')}}. Run all publishes in parallel, capture each output to a separate file, then run /maxpublish/scripts/record.sh for each. Don't ask again.`;
  }} else if (action === 'publish-high') {{
    const all = [...data.highOnly, ...extras];
    msg = `/maxpublish approve: publish v${{data.version}} to high-confidence only: ${{all.join(', ')}}. Skip medium-confidence candidates.`;
  }} else if (action === 'add-more') {{
    const all = [...data.candidates, ...extras];
    msg = `/maxpublish approve: publish v${{data.version}} to: ${{all.join(', ')}}. (added ${{extras.join(', ') || 'nothing'}})`;
  }} else if (action === 'deny') {{
    msg = `/maxpublish deny: do not publish. Abort.`;
  }}
  copy(msg);
}});
</script>
</body>
</html>
"""

    cache = Path.home() / ".agents/cache/maxpublish"
    cache.mkdir(parents=True, exist_ok=True)
    out = cache / f"draft-{Path(cwd).name}-{version}.html"
    out.write_text(html, encoding="utf-8")
    print(str(out))

    if os.environ.get("MAXPUBLISH_CI", "0") != "1":
        try:
            subprocess.run(["open", str(out)], check=False)
        except FileNotFoundError:
            pass

if __name__ == "__main__":
    main()
