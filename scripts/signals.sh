#!/usr/bin/env bash
# signals.sh — list what the current project looks like. NO platform decisions.
# usage: signals.sh [--json] [--guide]
#
#   --json   machine-readable output for agent
#   --guide  print first-run guide (candidates + prompt) — honors MAXPUBLISH_CI=1
#
# This is a diagnostic tool. It reports what files/CLIs/envs exist.
# The agent (or the user) decides which registries are appropriate.
# Auto-default rules are in SKILL.md / REFERENCE.md.

set -euo pipefail

JSON_MODE=0
GUIDE_MODE=0
for arg in "$@"; do
  case "$arg" in
    --json)  JSON_MODE=1 ;;
    --guide) GUIDE_MODE=1 ;;
  esac
done

# helpers
has_file()  { [[ -f "$1" ]]; }
has_dir()   { [[ -d "$1" ]]; }
has_cmd()   { command -v "$1" >/dev/null 2>&1; }
has_secret(){ [[ -n "${!1:-}" ]]; }

# ----- manifests -----
manifests=()
if has_file "package.json"; then
  v="$(jq -r '.version // empty' package.json 2>/dev/null || true)"
  is_ext="$(jq -r 'if .["engines"]["vscode"] then true else false end' package.json 2>/dev/null || echo false)"
  is_priv="$(jq -r '.private // false' package.json 2>/dev/null || echo false)"
  manifests+=("{\"type\":\"npm\",\"path\":\"package.json\",\"version\":\"$v\",\"private\":$is_priv}")
  [[ "$is_ext" == "true" ]] && manifests+=("{\"type\":\"vscode-extension\",\"path\":\"package.json\",\"version\":\"$v\"}")
fi
if has_file "pyproject.toml" || has_file "setup.py"; then
  v=""
  [[ -f pyproject.toml ]] && v="$(grep -m1 -oE 'version[[:space:]]*=[[:space:]]*["'\'']?[^"'\'' ]+' pyproject.toml | sed -E 's/.*["'\'']?([^"'\'']+)["'\'']?.*/\1/' || true)"
  manifests+=("{\"type\":\"pypi\",\"path\":\"pyproject.toml\",\"version\":\"$v\"}")
fi
if has_file "Cargo.toml"; then
  v="$(grep -m1 '^version' Cargo.toml | sed -E 's/^version[[:space:]]*=[[:space:]]*"(.*)".*/\1/' || true)"
  pub="$(grep -m1 '^publish' Cargo.toml | sed -E 's/^publish[[:space:]]*=[[:space:]]*(true|false).*/\1/' || echo true)"
  manifests+=("{\"type\":\"cargo\",\"path\":\"Cargo.toml\",\"version\":\"$v\",\"publish\":$pub}")
fi
if ls *.gemspec >/dev/null 2>&1; then
  v="$(grep -h -m1 -oE 'spec\.version[[:space:]]*=[[:space:]]*["'\''][^"'\'']+' *.gemspec 2>/dev/null | sed -E 's/.*["'\'']([^"'\'']+)["'\''].*/\1/' | head -1 || true)"
  manifests+=("{\"type\":\"gem\",\"path\":\"*.gemspec\",\"version\":\"$v\"}")
fi
if has_file "Dockerfile"; then
  manifests+=("{\"type\":\"docker\",\"path\":\"Dockerfile\"}")
fi
if has_dir ".github/workflows"; then
  if grep -lqrE 'ghcr\.io|packages:[[:space:]]*write|actions/.*package' .github/workflows/ 2>/dev/null; then
    manifests+=("{\"type\":\"ghcr-workflow\",\"path\":\".github/workflows/\"}")
  fi
fi
if has_dir "Formula" && ls Formula/*.rb >/dev/null 2>&1; then
  manifests+=("{\"type\":\"brew-formula\",\"path\":\"Formula/\"}")
fi
# WebExtension (manifest.json): AMO if gecko, Chrome Web Store if no gecko,
# Edge Add-ons if explicit edge key
if has_file "manifest.json"; then
  if jq -e '.browser_specific_settings.gecko' manifest.json >/dev/null 2>&1; then
    manifests+=("{\"type\":\"webext-firefox\",\"path\":\"manifest.json\"}")
  fi
  if jq -e '.browser_specific_settings.edge' manifest.json >/dev/null 2>&1; then
    manifests+=("{\"type\":\"webext-edge\",\"path\":\"manifest.json\"}")
  fi
  if ! jq -e '.browser_specific_settings.gecko' manifest.json >/dev/null 2>&1; then
    manifests+=("{\"type\":\"webext-chrome\",\"path\":\"manifest.json\"}")
  fi
fi

# ----- clis -----
clis=()
for c in npm npx cargo gem docker gh; do
  if has_cmd "$c"; then clis+=("\"$c\":true"); else clis+=("\"$c\":false"); fi
done
# twine / build (Python)
if has_cmd python3 && python3 -m twine --version >/dev/null 2>&1; then
  clis+=("\"twine\":true")
else
  clis+=("\"twine\":false")
fi
# vsce
if has_cmd vsce || has_cmd npx; then clis+=("\"vsce\":true"); else clis+=("\"vsce\":false"); fi

# ----- envs -----
envs=()
for v in NODE_AUTH_TOKEN NPM_TOKEN VSCE_PAT TWINE_USERNAME TWINE_PASSWORD TWINE_API_KEY \
         CARGO_REGISTRY_TOKEN GEM_HOST_API_KEY DOCKERHUB_USERNAME DOCKERHUB_TOKEN \
         GITHUB_TOKEN AMO_API_KEY AMO_API_SECRET CWS_CLIENT_ID CWS_CLIENT_SECRET \
         CWS_REFRESH_TOKEN EDGE_CLIENT_ID EDGE_CLIENT_SECRET; do
  if has_secret "$v"; then envs+=("\"$v\":true"); else envs+=("\"$v\":false"); fi
done

# ----- git -----
git_is_repo=false; git_branch=""; git_dirty=false
if git rev-parse --git-dir >/dev/null 2>&1; then
  git_is_repo=true
  git_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
  [[ -n "$(git status --porcelain 2>/dev/null)" ]] && git_dirty=true
fi

# ----- version -----
if [[ ${#manifests[@]} -gt 0 ]]; then
  version="$(printf '%s,' "${manifests[@]}" | head -c 4000 | jq -r 'map(select(.version != null and .version != "")) | .[0].version // "0.0.0"' 2>/dev/null || echo "0.0.0")"
else
  version="0.0.0"
fi
if [[ -z "$version" || "$version" == "null" ]]; then version="0.0.0"; fi

# ----- output JSON -----
if [[ ${#manifests[@]} -gt 0 ]]; then
  _joined="$(printf '%s,' "${manifests[@]}")"
  man_json="[${_joined%,}]"
else
  man_json="[]"
fi
if [[ ${#clis[@]} -gt 0 ]]; then
  _joined="$(printf '%s,' "${clis[@]}")"
  clis_json="{${_joined%,}}"
else
  clis_json="{}"
fi
if [[ ${#envs[@]} -gt 0 ]]; then
  _joined="$(printf '%s,' "${envs[@]}")"
  envs_json="{${_joined%,}}"
else
  envs_json="{}"
fi
unset _joined

out="$(jq -nc \
  --arg v "$version" \
  --argjson manifests "$man_json" \
  --argjson clis "$clis_json" \
  --argjson envs "$envs_json" \
  --argjson git_is_repo "$git_is_repo" \
  --arg git_branch "$git_branch" \
  --argjson git_dirty "$git_dirty" \
  '{version:$v, manifests:$manifests, clis:$clis, envs:$envs, git:{is_repo:$git_is_repo, branch:$git_branch, dirty:$git_dirty}}')"

# ----- derive auto-default candidates (from SKILL.md) -----
candidates_json="$(printf '%s' "$out" | jq -c '
  [.manifests[] as $m |
    if   $m.type == "npm"                 then {platform:"npm",  signal:$m, confidence:"high"}
    elif $m.type == "vscode-extension"    then {platform:"vsce", signal:$m, confidence:"high"}
    elif $m.type == "pypi"                then {platform:"pypi", signal:$m, confidence:"high"}
    elif $m.type == "cargo"               then {platform:"cargo",signal:$m, confidence:"high"}
    elif $m.type == "gem"                 then {platform:"gem",  signal:$m, confidence:"high"}
    elif $m.type == "docker"              then {platform:"docker",signal:$m,confidence:"high"}
    elif $m.type == "webext-firefox"      then {platform:"amo",  signal:$m, confidence:"high"}
    elif $m.type == "webext-chrome"       then {platform:"chrome-web-store", signal:$m, confidence:"high"}
    elif $m.type == "webext-edge"         then {platform:"edge-addons",     signal:$m, confidence:"high"}
    else empty
    end
  ] as $high |
  (.git.is_repo) as $is_git |
  ([
    (if $is_git then {platform:"gh-release", signal:{type:"git"}, confidence:"medium"} else empty end),
    (if any(.manifests[]; .type == "ghcr-workflow") then {platform:"ghcr", signal:{type:"ghcr-workflow"}, confidence:"medium"} else empty end),
    (if any(.manifests[]; .type == "brew-formula") then {platform:"brew", signal:{type:"brew-formula"}, confidence:"medium"} else empty end)
  ]) as $medium |
  ($high + $medium) | unique_by(.platform)
')"

# ----- first-run guide mode -----
if [[ $GUIDE_MODE -eq 1 ]]; then
  echo -e "\033[1m── /maxpublish · $(date -u +%Y-%m-%dT%H:%M:%SZ) ──\033[0m"
  echo "  cwd: $(pwd)"
  echo
  if [[ $(printf '%s' "$candidates_json" | jq 'length') -eq 0 ]]; then
    echo "── detected ──"
    echo "  (no publishable manifest found)"
    echo
    echo "  nothing to publish. add package.json / pyproject.toml / Cargo.toml /"
    echo "  *.gemspec / Dockerfile / manifest.json to opt in."
    exit 0
  fi
  echo "── detected (auto-default candidates) ──"
  printf '%s' "$candidates_json" | jq -r '.[] | "  \(if .confidence == "high" then "✓" else "?" end) \(.platform)\t\(.signal.type)"'
  echo
  echo "  ✓ = high-confidence auto-default"
  echo "  ? = medium-confidence (medium? signal — confirm or skip)"
  echo

  # candidate platform list
  cand_list="$(printf '%s' "$candidates_json" | jq -r '[.[].platform] | join(", ")')"
  echo "about to publish: $cand_list"

  if [[ "${MAXPUBLISH_CI:-0}" == "1" ]]; then
    echo "(MAXPUBLISH_CI=1 → auto-confirm, no prompt)"
    echo
    printf '%s' "$out" | jq -c --argjson cands "$candidates_json" '. + {candidates:$cands}'
    exit 0
  fi

  read -r -p "publish all? [Y/n] " ans
  ans="${ans:-Y}"
  if [[ ! "$ans" =~ ^[Yy]$ ]]; then
    echo "aborted. re-run with --only <plat> to pick a subset."
    exit 130
  fi
  echo
  printf '%s' "$out" | jq -c --argjson cands "$candidates_json" '. + {candidates:$cands, confirmed:true}'
  exit 0
fi

# ----- default output -----
if [[ $JSON_MODE -eq 1 ]]; then
  printf '%s' "$out" | jq --argjson cands "$candidates_json" '. + {candidates:$cands}'
else
  echo "version:  $version"
  echo
  echo "manifests:"
  if [[ "$man_json" == "[]" ]]; then
    echo "  (none detected)"
  else
    printf '%s\n' "$man_json" | jq -r '.[] | "  • \(.type)\t\(.path)\tv=\(.version // "-")"' 2>/dev/null
  fi
  echo
  echo "clis:"
  echo "$clis_json" | jq -r 'to_entries[] | "  \(.key) \(if .value then "✅" else "❌" end)"'
  echo
  echo "envs:"
  echo "$envs_json" | jq -r 'to_entries[] | "  \(.key) \(if .value then "✅" else "❌" end)"'
  echo
  echo "git:"
  if [[ "$git_is_repo" == "true" ]]; then
    echo "  • repo: yes · branch: $git_branch · dirty: $git_dirty"
  else
    echo "  • not a git repository"
  fi
  echo
  echo "candidates (auto-default):"
  if [[ $(printf '%s' "$candidates_json" | jq 'length') -eq 0 ]]; then
    echo "  (none — no publishable manifest found)"
  else
    printf '%s' "$candidates_json" | jq -r '.[] | "  \(if .confidence == "high" then "✓" else "?" end) \(.platform)  (\(.signal.type))"'
  fi
fi
