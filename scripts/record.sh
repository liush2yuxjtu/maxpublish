#!/usr/bin/env bash
# record.sh — append a publish event to ~/.agents/maxpublish/index.jsonl
# usage: record.sh <platform> <version> <status> [note]
#
# status: ok | failed | skipped
# note:   free text (e.g. url, error excerpt) — will be truncated

set -euo pipefail

PLATFORM="${1:-}"; VERSION="${2:-}"; STATUS="${3:-ok}"; NOTE="${4:-}"
[[ -n "$PLATFORM" && -n "$VERSION" ]] || {
  echo "usage: $0 <platform> <version> <status> [note]" >&2
  exit 64
}

INDEX="$HOME/.agents/maxpublish/index.jsonl"
mkdir -p "$(dirname "$INDEX")"

jq -nc \
  --arg platform "$PLATFORM" \
  --arg version  "$VERSION" \
  --arg status   "$STATUS" \
  --arg note     "$NOTE" \
  --arg cwd      "$(pwd)" \
  --arg ts       "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{platform:$platform, version:$version, status:$status, note:$note, cwd:$cwd, ts:$ts}' \
  >> "$INDEX"

echo "recorded → $INDEX"
