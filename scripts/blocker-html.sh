#!/usr/bin/env bash
# blocker-html.sh — open a fix-assist HTML listing all blockers.
# usage: blocker-html.sh
#
# Reads signals.sh --json, finds envs that are false, generates an HTML
# with: platform name, env var, get-token URL, token input, copy buttons.
# Auto-opens in default browser unless MAXPUBLISH_CI=1.

set -euo pipefail

MAXPUBLISH_HOME="${MAXPUBLISH_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SIGNALS="$MAXPUBLISH_HOME/scripts/signals.sh"

# platform → env vars (JSON)
PLATFORMS_JSON='{
  "npm":             { "envs": ["NODE_AUTH_TOKEN","NPM_TOKEN"],                                "url": "https://www.npmjs.com/settings/<user>/tokens (Automation scope)" },
  "vsce":            { "envs": ["VSCE_PAT"],                                                    "url": "Azure DevOps → User settings → PAT (Marketplace: Manage)" },
  "pypi":            { "envs": ["TWINE_API_KEY","TWINE_USERNAME","TWINE_PASSWORD"],            "url": "https://pypi.org/manage/account/token/" },
  "cargo":           { "envs": ["CARGO_REGISTRY_TOKEN"],                                        "url": "https://crates.io/settings/tokens" },
  "gem":             { "envs": ["GEM_HOST_API_KEY"],                                            "url": "https://rubygems.org/settings/edit" },
  "docker":          { "envs": ["DOCKERHUB_TOKEN"],                                             "url": "https://hub.docker.com/settings/security" },
  "ghcr":            { "envs": ["GITHUB_TOKEN"],                                                "url": "https://github.com/settings/tokens (write:packages scope)" },
  "amo":             { "envs": ["AMO_API_KEY","AMO_API_SECRET"],                                "url": "https://addons.mozilla.org/developers/addon/api/key/" },
  "chrome-web-store":{ "envs": ["CWS_CLIENT_ID","CWS_CLIENT_SECRET","CWS_REFRESH_TOKEN"],      "url": "Google Cloud Console + chrome-webstore-upload-cli OAuth" },
  "edge-addons":     { "envs": ["EDGE_CLIENT_ID","EDGE_CLIENT_SECRET"],                        "url": "Partner Center → API credentials" },
  "brew":            { "envs": [],                                                                "url": "https://github.com/<user>/homebrew-<formula> (SSH key)" }
}'

# platform → which manifest signal type means "this platform is a candidate"
SIG_MAP='{
  "npm":"npm","vsce":"vscode-extension","pypi":"pypi","cargo":"cargo","gem":"gem",
  "docker":"docker","ghcr":"ghcr-workflow",
  "amo":"webext-firefox","chrome-web-store":"webext-chrome","edge-addons":"webext-edge"
}'

# gather signals
sig_json="$("$SIGNALS" --json 2>/dev/null)"
gh_authed=false
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then gh_authed=true; fi

# build blockers: list of {platform, env, url} for every (candidate platform) × (env that is false)
blockers_json="$(echo "$sig_json" | jq --argjson platforms "$PLATFORMS_JSON" --argjson sigmap "$SIG_MAP" -c '
  .manifests as $manifests |
  .envs as $envmap |
  [$sigmap | to_entries[] | .key as $plat | .value as $sigtype |
    if any($manifests[]?; .type == $sigtype) then
      ($platforms[$plat].envs // []) as $envs |
      [$envs[] | . as $env_name | select($envmap[$env_name] == false) |
        {platform:$plat, env:$env_name, url:$platforms[$plat].url}]
    else empty
    end
  ] | add
')"

if [[ "$(echo "$blockers_json" | jq 'length')" -eq 0 ]]; then
  echo "no blockers detected." >&2
  exit 0
fi

# render HTML
CACHE_DIR="$HOME/.agents/cache/maxpublish"
mkdir -p "$CACHE_DIR"
TS="$(date +%Y%m%d-%H%M%S)"
HTML="$CACHE_DIR/blockers-$TS.html"
n_blockers="$(echo "$blockers_json" | jq 'length')"

# build blocker cards HTML — escape double-quotes for jq string syntax
JQ_FILTER='
.[] |
  "<div class=\"b\" data-platform=\(.platform) data-env=\(.env)>
    <h3>\(.platform) — <code>\(.env)</code></h3>
    <p class=\"hint\">Get a token: \(.url)</p>
    <input type=\"text\" data-platform=\(.platform) data-env=\(.env) placeholder=\"paste token here\" />
    <button data-action=\"copy-export\">📋 copy export</button>
  </div>"
'
CARDS="$(echo "$blockers_json" | jq -r "$JQ_FILTER")"

cat > "$HTML" <<HTML
<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<title>maxpublish — fix ${n_blockers} blockers</title>
<style>
:root{--ink:#101418;--muted:#5b6168;--line:#e6e6ea;--bg:#fbfbfc;--card:#fff;--err:#dc2626}
*{box-sizing:border-box}html,body{margin:0;background:var(--bg);color:var(--ink);
  font:15px/1.6 -apple-system,"PingFang SC","Hiragino Sans GB",sans-serif}
body{max-width:780px;margin:0 auto;padding:40px 24px 120px}
h1{font-size:24px;margin:0 0 4px}
.sub{color:var(--muted);margin:0 0 24px}
.b{background:var(--card);border:1px solid var(--line);border-left:4px solid var(--err);
   border-radius:8px;padding:14px 16px;margin:12px 0}
.b h3{margin:0 0 6px;font-size:15px}
.b code{background:#f4f4f5;padding:1px 5px;border-radius:3px;font-size:13px}
.b .hint{margin:4px 0 8px;color:var(--muted);font-size:13px}
.b input{width:100%;padding:8px 10px;border:1px solid var(--line);border-radius:6px;
        font:13px ui-monospace,SF Mono,Menlo,monospace;margin-bottom:6px}
.b button{font:13px var(--sans);background:#101418;color:#fff;border:0;
          border-radius:5px;padding:6px 12px;cursor:pointer;margin-right:6px}
.b button:hover{background:#262a30}
.actions{position:fixed;left:0;right:0;bottom:0;background:#fff;border-top:1px solid var(--line);
         padding:12px 24px;display:flex;gap:10px;justify-content:center}
.actions button{font:14px var(--sans);background:#101418;color:#fff;border:0;
                border-radius:6px;padding:10px 18px;cursor:pointer}
.actions .primary{background:#16a34a}
.actions .primary:hover{background:#15803d}
.toast{position:fixed;bottom:80px;left:50%;transform:translateX(-50%);
       background:#101418;color:#e6e6ea;padding:8px 14px;border-radius:6px;
       font:13px var(--sans);opacity:0;transition:.2s;pointer-events:none}
.toast.show{opacity:1}
</style>
</head>
<body>
<h1>maxpublish · <span style="color:var(--err)">${n_blockers} blockers</span></h1>
<p class="sub">$([ "$gh_authed" = "true" ] && echo "gh: ✅ authed · " || echo "gh: ❌ run <code>gh auth login</code> · ")cwd: <code>$(pwd)</code></p>

${CARDS}

<div class="actions">
  <button class="primary" onclick="copyAll()">📋 copy prompt back to claude code</button>
  <button onclick="copyAll(true)">⏭ skip & let me fix in claude</button>
</div>

<div class="toast" id="toast">copied ✓</div>

<script>
function copy(text) {
  navigator.clipboard.writeText(text);
  const t = document.getElementById('toast');
  t.textContent = 'copied ✓';
  t.classList.add('show');
  setTimeout(() => t.classList.remove('show'), 1500);
}

document.addEventListener('click', (e) => {
  if (e.target.dataset.action === 'copy-export') {
    const card = e.target.closest('.b');
    const env = card.dataset.env;
    const input = card.querySelector('input');
    const v = input.value.trim();
    copy(v ? 'export ' + env + '="' + v + '"' : 'export ' + env + '=""');
  }
});

function gatherExports() {
  const exps = [];
  document.querySelectorAll('.b').forEach(card => {
    const env = card.dataset.env;
    const v = card.querySelector('input').value.trim();
    if (v) exps.push('export ' + env + '="' + v + '"');
  });
  return exps.join('\n');
}

function copyAll(skip) {
  const exps = gatherExports();
  const filled = exps.split('\n').filter(Boolean).length;
  const total = document.querySelectorAll('.b').length;
  let msg;
  if (skip) {
    msg = '/maxpublish has ' + total + ' blockers (see ' + location.href + '). I want to fix them in claude code directly, not via the form. Please tell me the fix steps.';
  } else if (filled === 0) {
    msg = '/maxpublish blockers: ' + total + ' env vars missing. Open this URL to see them: ' + location.href + '. Please walk me through the fix steps.';
  } else {
    msg = '/maxpublish: I have set these env vars (pasted into the form):\n' + exps + '\nPlease re-run /maxpublish.';
  }
  copy(msg);
}
</script>
</body>
</html>
HTML

echo "$HTML"
echo "$blockers_json" | jq -c 'group_by(.platform)'

# auto-open unless CI
if [[ "\${MAXPUBLISH_CI:-0}" != "1" ]]; then
  if command -v open >/dev/null 2>&1; then
    open "$HTML"
  fi
fi
