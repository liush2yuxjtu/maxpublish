#!/usr/bin/env bash
# fill-manifest.sh — auto-fill missing manifest fields so the project is publish-ready.
# usage: fill-manifest.sh [--dry-run]
#
# Fills: package.json (description, repository, license, keywords, author),
#        pyproject.toml (description, authors, license),
#        Cargo.toml (description, license, repository),
#        *.gemspec (summary, description, license),
#        Dockerfile (LABEL maintainer, version, description),
#        VS Code extension (displayName, description, categories, keywords).
#
# Uses project name + git remote URL as defaults. Always adds a standard
# keywords list. Leaves existing values alone.

set -euo pipefail

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

MAXPUBLISH_HOME="${MAXPUBLISH_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

bold() { echo -e "\033[1m▸\033[0m $*"; }
ok()   { echo -e "\033[32m✓\033[0m $*"; }
skip() { echo -e "  (skipped) $*"; }

# source project name + git remote once
PROJECT_NAME="$(basename "$(pwd)")"
GIT_REMOTE="$(git remote get-url origin 2>/dev/null | sed -E 's#(git@|https://)github\.com(:|/)([^/]+)/([^/.]+)(\.git)?#\3/\4#' || echo "")"
[[ -z "$GIT_REMOTE" && -n "$GIT_REMOTE" ]] && GIT_REMOTE="${PROJECT_NAME}/${PROJECT_NAME}"

# jq helper: set field if missing/empty
ensure_field() {
  local file="$1" jq_filter="$2" value="$3"
  local current
  current="$(jq -r "$jq_filter // empty" "$file" 2>/dev/null)"
  if [[ -z "$current" || "$current" == "null" || "$current" == '""' ]]; then
    if [[ $DRY_RUN -eq 1 ]]; then
      echo "+ $file: set $(echo "$jq_filter" | sed 's/[.[]//g')=\"$value\""
    else
      jq --arg v "$value" "$jq_filter = \$v" "$file" > "$file.tmp" && mv "$file.tmp" "$file"
      ok "$file: set $(echo "$jq_filter" | sed 's/[.[]//g')"
    fi
    return 0
  fi
  return 1
}

changed=0

# --- package.json ---
if [[ -f package.json ]]; then
  bold "package.json"
  if ensure_field package.json '.description' "$PROJECT_NAME — a Claude skill for multi-registry publish."; then changed=$((changed+1)); fi
  if ensure_field package.json '.license' "MIT"; then changed=$((changed+1)); fi
  if ensure_field package.json '.author' "${GIT_REMOTE:-anonymous}"; then changed=$((changed+1)); fi
  if [[ -n "$GIT_REMOTE" ]]; then
    if ensure_field package.json '.repository.type' "git"; then changed=$((changed+1)); fi
    if ensure_field package.json '.repository.url' "https://github.com/${GIT_REMOTE}.git"; then changed=$((changed+1)); fi
    if ensure_field package.json '.homepage' "https://github.com/${GIT_REMOTE}#readme"; then changed=$((changed+1)); fi
    if ensure_field package.json '.bugs.url' "https://github.com/${GIT_REMOTE}/issues"; then changed=$((changed+1)); fi
  fi
  if ensure_field package.json '.keywords[]' "claude-skill" 2>/dev/null; then :; fi
  # ensure keywords is a non-empty array
  if [[ $(jq -r '.keywords | type' package.json 2>/dev/null) != "\"array\"" ]] || [[ $(jq -r '.keywords | length' package.json 2>/dev/null) -eq 0 ]]; then
    if [[ $DRY_RUN -eq 1 ]]; then
      echo "+ package.json: set keywords=[publish, multi-registry, claude-skill]"
    else
      jq '.keywords = ["publish", "multi-registry", "claude-skill", "release", "one-shot"]' package.json > package.json.tmp && mv package.json.tmp package.json
      ok "package.json: set keywords"
      changed=$((changed+1))
    fi
  fi
fi

# --- pyproject.toml (PEP 621) ---
if [[ -f pyproject.toml ]]; then
  bold "pyproject.toml"
  # only fill if [project] table exists
  if grep -q '^\[project\]' pyproject.toml; then
    # description
    if ! grep -qE '^description[[:space:]]*=' pyproject.toml; then
      if [[ $DRY_RUN -eq 1 ]]; then
        echo "+ pyproject.toml: add description = \"$PROJECT_NAME\""
      else
        sed -i '' "/^\[project\]/a\\
description = \"$PROJECT_NAME\"
" pyproject.toml
        ok "pyproject.toml: added description"
        changed=$((changed+1))
      fi
    fi
    # license
    if ! grep -qE '^license[[:space:]]*=' pyproject.toml; then
      if [[ $DRY_RUN -eq 1 ]]; then
        echo "+ pyproject.toml: add license = {text = \"MIT\"}"
      else
        sed -i '' "/^\[project\]/a\\
license = {text = \"MIT\"}
" pyproject.toml
        ok "pyproject.toml: added license"
        changed=$((changed+1))
      fi
    fi
    # authors
    if ! grep -qE '^authors[[:space:]]*=' pyproject.toml; then
      if [[ $DRY_RUN -eq 1 ]]; then
        echo "+ pyproject.toml: add authors = [{name = \"$PROJECT_NAME\"}]"
      else
        sed -i '' "/^\[project\]/a\\
authors = [{name = \"$PROJECT_NAME\"}]
" pyproject.toml
        ok "pyproject.toml: added authors"
        changed=$((changed+1))
      fi
    fi
  fi
fi

# --- Cargo.toml ---
if [[ -f Cargo.toml ]]; then
  bold "Cargo.toml"
  if ! grep -qE '^description[[:space:]]*=' Cargo.toml; then
    if [[ $DRY_RUN -eq 1 ]]; then
      echo "+ Cargo.toml: add description = \"$PROJECT_NAME\""
    else
      sed -i '' "/^\[package\]/a\\
description = \"$PROJECT_NAME\"
" Cargo.toml
      ok "Cargo.toml: added description"
      changed=$((changed+1))
    fi
  fi
  if ! grep -qE '^license[[:space:]]*=' Cargo.toml; then
    if [[ $DRY_RUN -eq 1 ]]; then
      echo "+ Cargo.toml: add license = \"MIT\""
    else
      sed -i '' "/^\[package\]/a\\
license = \"MIT\"
" Cargo.toml
      ok "Cargo.toml: added license"
      changed=$((changed+1))
    fi
  fi
  if [[ -n "$GIT_REMOTE" ]] && ! grep -qE '^repository[[:space:]]*=' Cargo.toml; then
    if [[ $DRY_RUN -eq 1 ]]; then
      echo "+ Cargo.toml: add repository = \"https://github.com/$GIT_REMOTE\""
    else
      sed -i '' "/^\[package\]/a\\
repository = \"https://github.com/$GIT_REMOTE\"
" Cargo.toml
      ok "Cargo.toml: added repository"
      changed=$((changed+1))
    fi
  fi
fi

# --- *.gemspec ---
for gs in *.gemspec; do
  [[ -f "$gs" ]] || continue
  bold "$gs"
  if ! grep -qE 'spec\.summary[[:space:]]*=' "$gs"; then
    if [[ $DRY_RUN -eq 1 ]]; then
      echo "+ $gs: add spec.summary"
    else
      sed -i '' "/^Gem::Specification\.do/a\\
  spec.summary       = \"$PROJECT_NAME — a Claude skill\"
" "$gs"
      ok "$gs: added spec.summary"
      changed=$((changed+1))
    fi
  fi
  if ! grep -qE 'spec\.description[[:space:]]*=' "$gs"; then
    if [[ $DRY_RUN -eq 1 ]]; then
      echo "+ $gs: add spec.description"
    else
      sed -i '' "/^Gem::Specification\.do/a\\
  spec.description   = \"Auto-published via maxpublish.\"
" "$gs"
      ok "$gs: added spec.description"
      changed=$((changed+1))
    fi
  fi
  if ! grep -qE 'spec\.license[[:space:]]*=' "$gs"; then
    if [[ $DRY_RUN -eq 1 ]]; then
      echo "+ $gs: add spec.license = \"MIT\""
    else
      sed -i '' "/^Gem::Specification\.do/a\\
  spec.license       = \"MIT\"
" "$gs"
      ok "$gs: added spec.license"
      changed=$((changed+1))
    fi
  fi
done

# --- Dockerfile ---
if [[ -f Dockerfile ]]; then
  bold "Dockerfile"
  # insert LABELs after the first FROM line
  if ! grep -qE '^LABEL[[:space:]]+(org\.opencontainers\.image\.|maintainer=|version=)' Dockerfile; then
    if [[ $DRY_RUN -eq 1 ]]; then
      echo "+ Dockerfile: add LABEL maintainer / version / description"
    else
      # find first FROM line
      line="$(grep -n '^FROM' Dockerfile | head -1 | cut -d: -f1)"
      sed -i '' "${line}a\\
LABEL maintainer=\"maxpublish@local\"\\
LABEL version=\"0.0.0\"\\
LABEL description=\"$PROJECT_NAME — auto-configured by maxpublish\"
" Dockerfile
      ok "Dockerfile: added LABELs"
      changed=$((changed+1))
    fi
  fi
fi

# --- VS Code extension (package.json with engines.vscode) ---
if [[ -f package.json ]] && jq -e '.["engines"]["vscode"]' package.json >/dev/null 2>&1; then
  bold "VS Code extension fields"
  if ensure_field package.json '.displayName' "$PROJECT_NAME"; then changed=$((changed+1)); fi
  if ensure_field package.json '.description' "$PROJECT_NAME — auto-configured by maxpublish"; then changed=$((changed+1)); fi
  if [[ $(jq -r '.categories | type' package.json 2>/dev/null) != "\"array\"" ]] || [[ $(jq -r '.categories | length' package.json 2>/dev/null) -eq 0 ]]; then
    if [[ $DRY_RUN -eq 1 ]]; then
      echo "+ package.json: set categories=[\"Other\"]"
    else
      jq '.categories = ["Other"]' package.json > package.json.tmp && mv package.json.tmp package.json
      ok "package.json: set categories"
      changed=$((changed+1))
    fi
  fi
fi

# summary
if [[ $changed -eq 0 ]]; then
  echo "no changes needed — already publish-ready"
else
  echo "$changed field(s) $(( $DRY_RUN == 1 ? "would be " : ""))filled"
fi
