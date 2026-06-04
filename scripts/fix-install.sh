#!/usr/bin/env bash
# fix-install.sh — install a missing CLI tool that the agent has decided to use.
# usage: fix-install.sh <tool> [--dry-run]
#
# Tools supported:
#   vsce     → npm i -g @vscode/vsce
#   twine    → pipx install twine  (or python3 -m pip install --user twine)
#   build    → pipx install build
#   gh       → brew install gh   (or skip if user is on a non-mac / non-brew box)
#
# This script prints what it would do. For destructive commands it shows the
# command and asks before running. Idempotent: re-runs are no-ops if installed.

set -euo pipefail

TOOL="${1:-}"
[[ -n "$TOOL" ]] || { echo "usage: $0 <vsce|twine|build|gh> [--dry-run]" >&2; exit 64; }
DRY_RUN=0
[[ "${2:-}" == "--dry-run" ]] && DRY_RUN=1

bold()  { echo -e "\033[1m▸\033[0m $*"; }
ok()    { echo -e "\033[32m✓\033[0m $*"; }
warn()  { echo -e "\033[33m⚠\033[0m $*" >&2; }
err()   { echo -e "\033[31m✗\033[0m $*" >&2; }

run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "+ $*"
  else
    eval "$@"
  fi
}

# already installed?
case "$TOOL" in
  vsce)
    if command -v vsce >/dev/null 2>&1 || command -v npx >/dev/null 2>&1 && npx @vscode/vsce --version >/dev/null 2>&1; then
      ok "vsce already available"; exit 0
    fi
    bold "installing @vscode/vsce via npm"
    run npm install -g @vscode/vsce
    ;;
  twine)
    if python3 -m twine --version >/dev/null 2>&1; then
      ok "twine already available"; exit 0
    fi
    if command -v pipx >/dev/null 2>&1; then
      bold "installing twine via pipx"
      run pipx install twine
    else
      bold "installing twine via pip (user)"
      warn "no pipx found; falling back to pip --user (may need PATH update)"
      run python3 -m pip install --user twine
    fi
    ;;
  build)
    if python3 -m build --version >/dev/null 2>&1; then
      ok "build already available"; exit 0
    fi
    if command -v pipx >/dev/null 2>&1; then
      bold "installing build via pipx"
      run pipx install build
    else
      bold "installing build via pip (user)"
      run python3 -m pip install --user build
    fi
    ;;
  gh)
    if command -v gh >/dev/null 2>&1; then
      ok "gh already installed"; exit 0
    fi
    if command -v brew >/dev/null 2>&1; then
      bold "installing gh via brew"
      run brew install gh
    else
      err "no brew; install gh manually: https://cli.github.com/"
      exit 1
    fi
    ;;
  *)
    err "unknown tool: $TOOL"
    echo "supported: vsce, twine, build, gh" >&2
    exit 65
    ;;
esac
