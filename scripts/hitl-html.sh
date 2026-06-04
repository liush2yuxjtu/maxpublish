#!/usr/bin/env python3
"""hitl-html.py — ONE unified human-in-the-loop page for /maxpublish.

Single page that combines: project signals + env blockers + OAuth notes +
publish draft + 4 action buttons. One copy → one paste back to claude code.

Auto-opens in default browser unless MAXPUBLISH_CI=1.
"""
import json
import os
import subprocess
import sys
from pathlib import Path

MAXPUBLISH_HOME = os.environ.get("MAXPUBLISH_HOME", str(Path(__file__).resolve().parent.parent))
SIGNALS = os.path.join(MAXPUBLISH_HOME, "scripts", "signals.sh")

# platform → (envs, token-getting URL)
PLATFORMS = {
    "npm":              (["NODE_AUTH_TOKEN", "NPM_TOKEN"],                                   "https://www.npmjs.com/settings/<user>/tokens (Automation scope)"),
    "vsce":             (["VSCE_PAT"],                                                         "Azure DevOps → User settings → PAT (Marketplace: Manage)"),
    "pypi":             (["TWINE_API_KEY", "TWINE_USERNAME", "TWINE_PASSWORD"],               "https://pypi.org/manage/account/token/"),
    "cargo":            (["CARGO_REGISTRY_TOKEN"],                                             "https://crates.io/settings/tokens"),
    "gem":              (["GEM_HOST_API_KEY"],                                                 "https://rubygems.org/settings/edit"),
    "docker":           (["DOCKERHUB_TOKEN"],                                                  "https://hub.docker.com/settings/security"),
    "ghcr":             (["GITHUB_TOKEN"],                                                     "https://github.com/settings/tokens (write:packages scope)"),
    "amo":              (["AMO_API_KEY", "AMO_API_SECRET"],                                   "https://addons.mozilla.org/developers/addon/api/key/"),
    "chrome-web-store": (["CWS_CLIENT_ID", "CWS_CLIENT_SECRET", "CWS_REFRESH_TOKEN"],         "Google Cloud Console + chrome-webstore-upload-cli OAuth"),
    "edge-addons":      (["EDGE_CLIENT_ID", "EDGE_CLIENT_SECRET"],                             "Partner Center → API credentials"),
    "brew":             ([],                                                                    "github.com/<user>/homebrew-<formula> (SSH key)"),
}

# platform → which signal type means candidate
SIG_MAP = {
    "npm": "npm", "vsce": "vscode-extension", "pypi": "pypi", "cargo": "cargo", "gem": "gem",
    "docker": "docker", "ghcr": "ghcr-workflow",
    "amo": "webext-firefox", "chrome-web-store": "webext-chrome", "edge-addons": "webext-edge",
}

# platforms that need OAuth (skip server/browser open per non-negotiable)
OAUTH_PLATFORMS = {"amo", "chrome-web-store", "edge-addons"}

# optional extra platforms (not auto-detected)
EXTRA_PLATFORMS = ["amo", "chrome-web-store", "edge-addons", "brew", "ghcr", "cargo", "gem", "pypi"]

def detect_blockers(sig):
    """Return list of {platform, env, url} for missing creds on candidate platforms."""
    blockers = []
    for plat, sigtype in SIG_MAP.items():
        if not any(m.get("type") == sigtype for m in sig.get("manifests", [])):
            continue
        envs, url = PLATFORMS[plat]
        for env in envs:
            if not sig.get("envs", {}).get(env, False):
                blockers.append({"platform": plat, "env": env, "url": url})
    return blockers

def detect_oauth(sig):
    """Return list of platforms that would be selected + need OAuth."""
    selected = [c["platform"] for c in sig.get("candidates", [])]
    selected += EXTRA_PLATFORMS  # include extras as OAuth candidates too
    return [p for p in selected if p in OAUTH_PLATFORMS]

def main():
    sig = json.loads(subprocess.check_output(["bash", SIGNALS, "--json"], text=True))
    cands = sig.get("candidates", [])
    version = sig.get("version", "0.0.0")
    project = Path(os.getcwd()).name
    blockers = detect_blockers(sig)
    oauth = detect_oauth(sig)

    # 4 status: ok | warn | skip | missing
    clis = sig.get("clis", {})
    cli_status = [{"name": k, "ok": v} for k, v in clis.items() if not k.startswith("_")]
    cli_ok = sum(1 for c in cli_status if c["ok"])
    cli_total = len(cli_status)

    # envs status (only show envs relevant to candidate platforms)
    rel_envs = []
    for plat in [c["platform"] for c in cands]:
        envs, _ = PLATFORMS.get(plat, ([], ""))
        for env in envs:
            if sig.get("envs", {}).get(env) is not None:
                rel_envs.append({"env": env, "ok": sig["envs"][env], "platform": plat})
    rel_envs_dedup = {e["env"]: e for e in rel_envs}.values()
    envs_ok = sum(1 for e in rel_envs_dedup if e["ok"])
    envs_total = len(list(rel_envs_dedup))

    git = sig.get("git", {})
    git_str = "no git repo"
    if git.get("is_repo"):
        git_str = f"branch {git.get('branch', '?')} · {'dirty' if git.get('dirty') else 'clean'}"

    # candidate list
    cand_rows = []
    for c in cands:
        plat = c["platform"]
        is_high = c["confidence"] == "high"
        cand_rows.append({
            "platform": plat,
            "signal": c["signal"]["type"],
            "confidence": c["confidence"],
            "checked": True,
            "needs_oauth": plat in OAUTH_PLATFORMS,
        })

    # blockers HTML
    if blockers:
        blocker_cards = "\n".join(
            f'''<div class="card blocker">
  <div class="card-head">
    <span class="plat">{b["platform"]}</span>
    <code class="env">{b["env"]}</code>
  </div>
  <div class="card-body">
    <div class="hint">{b["url"]}</div>
    <div class="input-row">
      <input type="text" data-env="{b["env"]}" data-platform="{b["platform"]}" placeholder="paste token here" />
      <button data-action="copy-export" data-platform="{b["platform"]}" data-env="{b["env"]}">copy export</button>
    </div>
  </div>
</div>'''
            for b in blockers
        )
        blocker_section = f'''<section class="block">
  <h2><span class="num">2</span> Blocker tokens <span class="count">{len(blockers)}</span></h2>
  <p class="lead">Paste each token below, then click the action at the bottom. The skill will copy a single ready-to-paste prompt back to Claude Code.</p>
  {blocker_cards}
</section>'''
    else:
        blocker_section = '''<section class="block">
  <h2><span class="num">2</span> Blocker tokens <span class="ok-pill">none</span></h2>
  <p class="lead">All relevant tokens already in env. You're clear to publish.</p>
</section>'''

    # OAuth section
    if oauth:
        oauth_cards = "\n".join(
            f'''<div class="card oauth">
  <div class="card-head">
    <span class="plat">{p}</span>
    <span class="badge">OAuth</span>
  </div>
  <div class="card-body">
    <div class="hint">Requires OAuth dance. The skill will <strong>not</strong> open a browser or run a server — use your existing CLI or skill:</div>
    <pre class="cli">{oauth_cli_hint(p)}</pre>
  </div>
</div>'''
            for p in oauth
        )
        oauth_section = f'''<section class="block">
  <h2><span class="num">3</span> OAuth-required platforms <span class="count">{len(oauth)}</span></h2>
  <p class="lead">Run these CLIs yourself (or use your existing skill); the skill will detect the resulting env vars on next run.</p>
  {oauth_cards}
</section>'''
    else:
        oauth_section = ""

    # draft candidates
    cand_rows_html = "\n".join(
        f'''<tr>
  <td><input type="checkbox" class="plat-check" data-platform="{c["platform"]}" {'checked' if c["checked"] else ''}/></td>
  <td><code class="plat-code">{c["platform"]}</code></td>
  <td><span class="sig">{c["signal"]}</span></td>
  <td><span class="badge {'hi' if c["confidence"]=='high' else 'med'}">{c["confidence"]}</span>{' <span class="badge oauth-mini">OAuth</span>' if c["needs_oauth"] else ''}</td>
</tr>'''
        for c in cand_rows
    )

    extra_checks = "\n".join(
        f'''<label><input type="checkbox" class="extra-check" data-platform="{p}"/> {p}</label>'''
        for p in EXTRA_PLATFORMS
    )

    draft_section = f'''<section class="block">
  <h2><span class="num">4</span> Publish draft <span class="count">{len(cand_rows)} candidates</span></h2>
  <p class="lead">Auto-detected candidates. Uncheck to skip. Add extras below if you want to ship elsewhere.</p>
  <table class="cands">
    <thead><tr><th>✓</th><th>platform</th><th>signal</th><th>confidence</th></tr></thead>
    <tbody>
{cand_rows_html}
    </tbody>
  </table>
  <div class="extras">
    <div class="extras-label">Add more (not auto-detected):</div>
    {extra_checks}
  </div>
</section>'''

    # action bar
    actions_section = '''<section class="actions">
  <button class="primary" data-action="publish">publish selected</button>
  <button data-action="publish-high">publish high only</button>
  <button class="add" data-action="add-extras">publish with checked extras</button>
  <button class="deny" data-action="deny">deny — do not publish</button>
</section>'''

    html = f"""<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<title>maxpublish · {project} v{version}</title>
<style>
:root {{
  --ink:#101418; --muted:#5b6168; --line:#e6e6ea; --line-2:#d4d4d8;
  --bg:#fafaf9; --surface:#fff; --card:#fff; --card-bg:#f8fafc;
  --ok:#16a34a; --warn:#d97706; --err:#dc2626; --accent:#4f46e5; --accent-soft:#eef2ff;
  --serif:"Noto Serif SC","Songti SC",Georgia,serif;
  --sans:-apple-system,BlinkMacSystemFont,"PingFang SC","Hiragino Sans GB","Noto Sans CJK SC",sans-serif;
  --mono:"SF Mono",SFNSMono,Menlo,"Liberation Mono",monospace;
}}
*{{box-sizing:border-box;margin:0;padding:0}}
html,body{{background:var(--bg);color:var(--ink);
  font:15px/1.65 var(--sans);-webkit-font-smoothing:antialiased}}
body{{max-width:920px;margin:0 auto;padding:64px 32px 200px}}
header{{margin-bottom:48px;padding-bottom:24px;border-bottom:1px solid var(--line)}}
.eyebrow{{font:500 11px/1 var(--sans);letter-spacing:.14em;text-transform:uppercase;color:var(--muted);margin-bottom:14px}}
h1{{font:600 36px/1.15 var(--serif);letter-spacing:-.02em;color:var(--ink);margin-bottom:8px}}
.meta{{font:13px/1.5 var(--sans);color:var(--muted)}}
.meta code{{font:12px var(--mono);color:var(--ink);background:#f4f4f5;padding:1px 5px;border-radius:3px}}
.status-row{{display:flex;gap:24px;margin-top:14px;flex-wrap:wrap}}
.status{{display:flex;align-items:center;gap:6px;font-size:13px}}
.status .dot{{width:8px;height:8px;border-radius:50%;background:var(--ok)}}
.status .dot.warn{{background:var(--warn)}}
.status .dot.err{{background:var(--err)}}
section.block{{margin:48px 0}}
h2{{font:600 20px/1.3 var(--serif);color:var(--ink);margin-bottom:6px;display:flex;align-items:center;gap:10px}}
.num{{font:500 12px/1 var(--mono);color:var(--muted);background:var(--card-bg);
     padding:4px 8px;border-radius:4px;letter-spacing:.04em}}
.count{{font:500 12px/1 var(--sans);color:var(--muted);background:var(--card-bg);
       padding:4px 10px;border-radius:999px}}
.count.ok-pill,.ok-pill{{background:#dcfce7;color:#166534}}
h2 .ok-pill{{margin-left:auto}}
.lead{{color:var(--muted);font-size:14px;margin:8px 0 16px;max-width:60ch}}
table.cands{{width:100%;border-collapse:collapse;margin:8px 0}}
table.cands th,table.cands td{{padding:12px;border-bottom:1px solid var(--line);text-align:left;font-size:14px}}
table.cands th{{font:500 11px/1 var(--sans);letter-spacing:.1em;text-transform:uppercase;color:var(--muted);font-weight:500}}
table.cands input{{transform:scale(1.3);cursor:pointer}}
.plat-code{{font:13px var(--mono);color:var(--ink);background:var(--card-bg);padding:2px 8px;border-radius:3px}}
.sig{{font:13px var(--mono);color:var(--muted)}}
.badge{{display:inline-block;font:500 11px/1 var(--sans);padding:3px 8px;border-radius:3px;letter-spacing:.04em}}
.badge.hi{{background:#dcfce7;color:#166534}}
.badge.med{{background:#fef3c7;color:#92400e}}
.badge.oauth-mini{{background:var(--accent-soft);color:var(--accent);margin-left:4px}}
.badge{{background:#f4f4f5;color:#5b6168}}
.extras{{margin-top:18px;padding:14px 18px;background:var(--card-bg);border-radius:8px;border:1px solid var(--line)}}
.extras-label{{font:500 12px/1 var(--sans);color:var(--muted);letter-spacing:.06em;text-transform:uppercase;margin-bottom:10px}}
.extras label{{display:inline-flex;align-items:center;margin:4px 12px 4px 0;font-size:13px;cursor:pointer;color:var(--ink)}}
.extras input{{margin-right:6px;transform:scale(1.1);cursor:pointer}}
.card{{background:var(--card);border:1px solid var(--line);border-radius:8px;padding:18px 20px;margin:12px 0;transition:.15s}}
.card.blocker{{border-left:3px solid var(--err)}}
.card.oauth{{border-left:3px solid var(--accent);background:var(--accent-soft)}}
.card-head{{display:flex;align-items:center;gap:10px;margin-bottom:10px}}
.plat{{font:600 16px/1 var(--serif);color:var(--ink)}}
.env{{font:13px var(--mono);color:var(--err);background:#fef2f2;padding:3px 8px;border-radius:3px;letter-spacing:.02em}}
.hint{{font:13px/1.5 var(--sans);color:var(--muted);margin-bottom:10px}}
.cli{{font:12px/1.55 var(--mono);background:var(--surface);border:1px solid var(--line);padding:10px 12px;border-radius:5px;color:var(--ink);white-space:pre-wrap;overflow-x:auto}}
.input-row{{display:flex;gap:8px;align-items:stretch}}
.input-row input{{flex:1;font:13px var(--mono);padding:9px 12px;border:1px solid var(--line-2);border-radius:5px;background:var(--surface);color:var(--ink)}}
.input-row input:focus{{outline:none;border-color:var(--accent);box-shadow:0 0 0 3px rgba(79,70,229,.12)}}
.input-row button{{font:13px var(--sans);background:var(--ink);color:#fff;border:0;border-radius:5px;padding:9px 16px;cursor:pointer;white-space:nowrap}}
.input-row button:hover{{background:#262a30}}
.actions{{position:fixed;left:0;right:0;bottom:0;background:rgba(255,255,255,.96);backdrop-filter:blur(10px);
         border-top:1px solid var(--line);padding:18px 32px;display:flex;gap:12px;justify-content:center;flex-wrap:wrap;z-index:10}}
.actions button{{font:14px var(--sans);border:0;border-radius:6px;padding:12px 22px;cursor:pointer;background:var(--ink);color:#fff}}
.actions button:hover{{transform:translateY(-1px);box-shadow:0 4px 12px rgba(0,0,0,.08)}}
.actions button.primary{{background:var(--ok)}}
.actions button.primary:hover{{background:#15803d}}
.actions button.add{{background:var(--accent)}}
.actions button.add:hover{{background:#4338ca}}
.actions button.deny{{background:var(--err)}}
.actions button.deny:hover{{background:#b91c1c}}
.toast{{position:fixed;bottom:90px;left:50%;transform:translateX(-50%);
       background:var(--ink);color:#fff;padding:10px 18px;border-radius:6px;
       font:13px var(--sans);opacity:0;transition:.2s;pointer-events:none;z-index:11}}
.toast.show{{opacity:1}}
.empty{{padding:32px;text-align:center;color:var(--muted);background:var(--card-bg);border-radius:8px;border:1px dashed var(--line-2)}}
</style>
</head>
<body>
<header>
  <div class="eyebrow">maxpublish · publish panel</div>
  <h1>{project}</h1>
  <div class="meta">
    version <code>{version}</code> · cwd <code>{os.getcwd()}</code>
  </div>
  <div class="status-row">
    <div class="status"><span class="dot{'' if not git.get('dirty') else ' warn'}"></span>{git_str}</div>
    <div class="status"><span class="dot{' warn' if blockers else ''}"></span>envs {envs_ok}/{envs_total} ready</div>
    <div class="status"><span class="dot{'' if cli_ok == cli_total else ' warn'}"></span>clis {cli_ok}/{cli_total} installed</div>
  </div>
</header>

<section class="block">
  <h2><span class="num">1</span> Auto-detected signals <span class="count">{len(sig.get('manifests', []))}</span></h2>
  {render_signals(sig)}
</section>

{blocker_section}

{oauth_section}

{draft_section}

{actions_section}

<div class="toast" id="toast">copied to clipboard ✓</div>

<script>
const meta = {{
  project: {json.dumps(project)},
  version: {json.dumps(version)},
  cwd: {json.dumps(os.getcwd())},
  blockers: {json.dumps(blockers)},
  candidates: {json.dumps([c["platform"] for c in cands])},
  oauth: {json.dumps(oauth)},
  extraPlatforms: {json.dumps(EXTRA_PLATFORMS)},
}};

function copy(text) {{
  navigator.clipboard.writeText(text);
  const t = document.getElementById('toast');
  t.classList.add('show');
  setTimeout(() => t.classList.remove('show'), 1800);
}}

function gatherTokens() {{
  const lines = [];
  document.querySelectorAll('.card.blocker input').forEach(inp => {{
    const v = inp.value.trim();
    if (v) lines.push(`export ${{inp.dataset.env}}="${{v}}"`);
  }});
  return lines;
}}

function gatherSelected() {{
  const plats = [...document.querySelectorAll('.plat-check:checked')].map(i => i.dataset.platform);
  const extras = [...document.querySelectorAll('.extra-check:checked')].map(i => i.dataset.platform);
  return [...new Set([...plats, ...extras])];
}}

document.addEventListener('click', (e) => {{
  const action = e.target.dataset.action;
  if (!action) return;

  if (action === 'copy-export') {{
    const card = e.target.closest('.card');
    const env = e.target.dataset.env;
    const inp = card.querySelector('input');
    const v = inp.value.trim();
    copy(v ? `export ${{env}}="${{v}}"` : `export ${{env}}=""`);
    return;
  }}

  const tokens = gatherTokens();
  const selected = gatherSelected();
  let msg;

  if (action === 'publish' || action === 'add-extras') {{
    msg = `/maxpublish approve: publish v${{meta.version}} to: ${{selected.join(', ') || 'nothing selected'}}.`;
  }} else if (action === 'publish-high') {{
    const high = selected.filter(p => meta.candidates.includes(p));
    msg = `/maxpublish approve (high only): publish v${{meta.version}} to: ${{high.join(', ') || 'nothing'}} (skipping medium + extras).`;
  }} else if (action === 'deny') {{
    msg = `/maxpublish deny: do not publish. Abort.`;
  }}

  if (tokens.length) {{
    msg += '\\n\\nEnv vars (paste into your shell first):\\n' + tokens.join('\\n');
  }}
  if (meta.oauth.length) {{
    msg += '\\n\\nOAuth dance still required for: ' + meta.oauth.join(', ') + '. Run the CLI I listed in section 3, then re-run /maxpublish.';
  }}
  msg += '\\n\\nWhen done: paste this whole message back to Claude Code, or just type "go".';
  copy(msg);
}});
</script>
</body>
</html>
"""

    cache = Path.home() / ".agents/cache/maxpublish"
    cache.mkdir(parents=True, exist_ok=True)
    out = cache / f"hitl-{project}-{version}.html"
    out.write_text(html, encoding="utf-8")
    print(str(out))

    if os.environ.get("MAXPUBLISH_CI", "0") != "1":
        try:
            subprocess.run(["open", str(out)], check=False)
        except FileNotFoundError:
            pass

def render_signals(sig):
    if not sig.get("manifests"):
        return '<div class="empty">no publishable manifests detected in this project</div>'
    rows = "\n".join(
        f'''<div class="status" style="margin:4px 0"><span class="dot"></span>
             <code class="plat-code">{m.get("type")}</code>
             <span class="sig">{m.get("path")}</span>
             <span class="sig">v{m.get("version", "?")}</span></div>'''
        for m in sig["manifests"]
    )
    return f'<div style="background:var(--card-bg);border:1px solid var(--line);border-radius:8px;padding:14px 18px">{rows}</div>'

def oauth_cli_hint(platform):
    hints = {
        "amo": "npx --yes web-ext sign --api-key $AMO_API_KEY --api-secret $AMO_API_SECRET",
        "chrome-web-store": "npx --yes chrome-webstore-upload-cli upload --source ext.zip --extension-id <id> ...",
        "edge-addons": "npx --yes edge-addons-api --product-id <id> --client-id $EDGE_CLIENT_ID ... upload",
    }
    return hints.get(platform, "(see REFERENCE.md)")

if __name__ == "__main__":
    main()
