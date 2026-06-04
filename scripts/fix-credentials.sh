#!/usr/bin/env bash
# fix-credentials.sh — check what credentials are present + tell user which env
# vars to set for the platforms the agent has chosen to publish to.
# usage: fix-credentials.sh <platform> [<platform> ...]
#
# Platforms: npm, vsce, pypi, cargo, gem, docker, ghcr, gh-release, brew
#
# This script never writes tokens. It only checks env and prints instructions.

set -euo pipefail

bold()  { echo -e "\033[1m▸\033[0m $*"; }
ok()    { echo -e "\033[32m✓\033[0m $*"; }
warn()  { echo -e "\033[33m⚠\033[0m $*"; }
err()   { echo -e "\033[31m✗\033[0m $*"; }

if [[ $# -eq 0 ]]; then
  err "usage: $0 <platform> [<platform> ...]"
  echo "supported: npm vsce pypi cargo gem docker ghcr gh-release brew" >&2
  exit 64
fi

# validate auth for platforms that have a CLI check
check_cli_auth() {
  case "$1" in
    npm)
      npm whoami >/dev/null 2>&1 && ok "npm: whoami ok ($(npm whoami 2>/dev/null))" \
        || err "npm: whoami failed — check NODE_AUTH_TOKEN / NPM_TOKEN"
      ;;
    gh)
      gh auth status >/dev/null 2>&1 && ok "gh: auth ok ($(gh api user -q .login 2>/dev/null))" \
        || err "gh: not authed — run 'gh auth login'"
      ;;
    gh-release) check_cli_auth gh ;;
    ghcr)        check_cli_auth gh ;;
    docker)
      if docker info 2>/dev/null | grep -q Username; then
        ok "docker: logged in as $(docker info 2>/dev/null | awk '/Username:/ {print $2}')"
      else
        err "docker: not logged in — 'docker login' first"
      fi
      ;;
    cargo)
      if [[ -f "$HOME/.cargo/credentials.toml" || -f "$HOME/.cargo/credentials" ]]; then
        ok "cargo: credentials file present"
      else
        err "cargo: no credentials — 'cargo login <token>' first"
      fi
      ;;
    pypi)
      if python3 -m twine check dist/* >/dev/null 2>&1; then
        ok "pypi: twine can read dist/"
      else
        warn "pypi: dist/ not built yet (run 'python3 -m build')"
      fi
      ;;
  esac
}

# platform → env var hints
for plat in "$@"; do
  echo
  bold "── $plat ──"
  case "$plat" in
    npm)
      for v in NODE_AUTH_TOKEN NPM_TOKEN; do
        if [[ -n "${!v:-}" ]]; then ok "$v set"; else warn "$v NOT set (CI uses NODE_AUTH_TOKEN; personal use NPM_TOKEN)"; fi
      done
      echo "  → get token: https://www.npmjs.com/settings/<user>/tokens (Automation scope)"
      check_cli_auth npm
      ;;
    vsce)
      for v in VSCE_PAT; do
        if [[ -n "${!v:-}" ]]; then ok "$v set"; else warn "$v NOT set"; fi
      done
      echo "  → get PAT: https://dev.azure.com → User settings → PAT (Marketplace: Manage scope)"
      check_cli_auth vsce
      ;;
    pypi)
      for v in TWINE_USERNAME TWINE_PASSWORD TWINE_API_KEY; do
        if [[ -n "${!v:-}" ]]; then ok "$v set"; else warn "$v NOT set"; fi
      done
      echo "  → API token: https://pypi.org/manage/account/token/"
      check_cli_auth pypi
      ;;
    cargo)
      if [[ -n "${CARGO_REGISTRY_TOKEN:-}" ]]; then ok "CARGO_REGISTRY_TOKEN set"
      else warn "CARGO_REGISTRY_TOKEN NOT set"
      fi
      echo "  → get token: https://crates.io/settings/tokens"
      check_cli_auth cargo
      ;;
    gem)
      if [[ -n "${GEM_HOST_API_KEY:-}" ]]; then ok "GEM_HOST_API_KEY set"
      else warn "GEM_HOST_API_KEY NOT set"
      fi
      echo "  → get API key: https://rubygems.org/settings/edit"
      ;;
    docker)
      for v in DOCKERHUB_USERNAME DOCKERHUB_TOKEN; do
        if [[ -n "${!v:-}" ]]; then ok "$v set"; else warn "$v NOT set (optional if 'docker login' state exists)"; fi
      done
      check_cli_auth docker
      ;;
    ghcr)
      if [[ -n "${GITHUB_TOKEN:-}" ]]; then ok "GITHUB_TOKEN set"
      elif gh auth token >/dev/null 2>&1; then ok "gh auth token available"
      else warn "no GITHUB_TOKEN and gh not authed"
      fi
      echo "  → use gh auth token (has packages:write) or a fine-grained PAT"
      check_cli_auth ghcr
      ;;
    gh-release)
      check_cli_auth gh
      ;;
    brew)
      echo "  → needs SSH key on the tap remote (e.g. github.com/<user>/homebrew-<formula>)"
      if command -v ssh >/dev/null && ssh -T -o BatchMode=yes git@github.com 2>&1 | grep -qi 'success'; then
        ok "github SSH works"
      else
        warn "github SSH not confirmed; 'ssh -T git@github.com' to test"
      fi
      ;;
    *)
      err "unknown platform: $plat"
      echo "supported: npm vsce pypi cargo gem docker ghcr gh-release brew" >&2
      ;;
  esac
done
