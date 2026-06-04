#!/usr/bin/env bash
# fix-version.sh — bump the version field in detected manifest files.
# usage: fix-version.sh <new-version> [--dry-run]
#
# Detects: package.json, pyproject.toml, Cargo.toml, *.gemspec
# Skips files that don't have a version field. Prints diffs.

set -euo pipefail

NEW="${1:-}"
[[ -n "$NEW" ]] || { echo "usage: $0 <new-version> [--dry-run]" >&2; exit 64; }
DRY_RUN=0
[[ "${2:-}" == "--dry-run" ]] && DRY_RUN=1

bold()  { echo -e "\033[1m▸\033[0m $*"; }
ok()    { echo -e "\033[32m✓\033[0m $*"; }
warn()  { echo -e "\033[33m⚠\033[0m $*"; }

changed=0

# package.json
if [[ -f package.json ]]; then
  cur="$(jq -r '.version // empty' package.json 2>/dev/null)"
  if [[ -n "$cur" && "$cur" != "$NEW" ]]; then
    bold "package.json: $cur → $NEW"
    if [[ $DRY_RUN -eq 1 ]]; then echo "+ jq '.version = \"$NEW\"' package.json"
    else jq --arg v "$NEW" '.version = $v' package.json > package.json.tmp && mv package.json.tmp package.json
    fi
    changed=$((changed+1))
  fi
fi

# pyproject.toml
if [[ -f pyproject.toml ]]; then
  if grep -qE '^version[[:space:]]*=' pyproject.toml; then
    cur="$(grep -m1 -oE 'version[[:space:]]*=[[:space:]]*["'\'']?[^"'\'' ]+' pyproject.toml | sed -E 's/.*["'\'']?([^"'\'']+)["'\'']?.*/\1/')"
    if [[ -n "$cur" && "$cur" != "$NEW" ]]; then
      bold "pyproject.toml: $cur → $NEW"
      if [[ $DRY_RUN -eq 1 ]]; then
        echo "+ sed -i '' 's/^version = \"$cur\"/version = \"$NEW\"/' pyproject.toml"
      else
        sed -i '' "s/^version = \"$cur\"/version = \"$NEW\"/" pyproject.toml
      fi
      changed=$((changed+1))
    fi
  fi
fi

# Cargo.toml
if [[ -f Cargo.toml ]]; then
  if grep -qE '^version[[:space:]]*=' Cargo.toml; then
    cur="$(grep -m1 '^version' Cargo.toml | sed -E 's/^version[[:space:]]*=[[:space:]]*"(.*)".*/\1/')"
    if [[ -n "$cur" && "$cur" != "$NEW" ]]; then
      bold "Cargo.toml: $cur → $NEW"
      if [[ $DRY_RUN -eq 1 ]]; then
        echo "+ sed -i '' 's/^version = \"$cur\"/version = \"$NEW\"/' Cargo.toml"
      else
        sed -i '' "s/^version = \"$cur\"/version = \"$NEW\"/" Cargo.toml
      fi
      changed=$((changed+1))
    fi
  fi
fi

# *.gemspec
for gs in *.gemspec; do
  [[ -f "$gs" ]] || continue
  if grep -qE 'spec\.version' "$gs"; then
    cur="$(grep -m1 -oE "spec\.version[[:space:]]*=[[:space:]]*['\"][^'\"]+" "$gs" | sed -E "s/.*['\"]([^'\"]+).*/\1/")"
    if [[ -n "$cur" && "$cur" != "$NEW" ]]; then
      bold "$gs: $cur → $NEW"
      if [[ $DRY_RUN -eq 1 ]]; then
        echo "+ sed -i '' \"s/spec.version = ['\\\"]$cur['\\\"]/spec.version = ['\\\"$NEW['\\\"]/\" $gs"
      else
        sed -i '' "s/spec.version = ['\"]$cur['\"]/spec.version = '$NEW'/" "$gs"
      fi
      changed=$((changed+1))
    fi
  fi
done

if [[ $changed -eq 0 ]]; then
  warn "no version fields needed changing (already $NEW or not found)"
else
  ok "$changed file(s) updated → $NEW"
fi
