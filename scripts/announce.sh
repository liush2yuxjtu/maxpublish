#!/usr/bin/env bash
# announce.sh — render a release-notes HTML one-pager and publish via talk-html.
# usage: announce.sh <version> <project-name> <results-json>
#
# <results-json> is a JSON array of {platform, status, url} objects.
# Example:
#   announce.sh 1.2.3 mypkg '[{"platform":"npm","status":"ok","url":"https://..."}]'

set -euo pipefail

VERSION="${1:-}"; NAME="${2:-}"; RESULTS="${3:-[]}"
[[ -n "$VERSION" && -n "$NAME" ]] || {
  echo "usage: $0 <version> <project-name> <results-json>" >&2
  exit 64
}

CACHE_DIR="$HOME/.agents/cache/maxpublish"
mkdir -p "$CACHE_DIR"
HTML="$CACHE_DIR/release-$NAME-$VERSION.html"

# build result rows
ROWS="$(echo "$RESULTS" | jq -r '.[] | "  <tr><td><span class=\"\(if .status == "ok" then "ok" else "err" end)\">\(if .status == "ok" then "✓" else "✗" end)</span></td><td>\(.platform)</td><td>\(.url // "")</td></tr>"')"

cat > "$HTML" <<HTML
<!doctype html>
<html lang="zh-CN"><head>
<meta charset="utf-8">
<title>Release $NAME $VERSION</title>
<style>
body{font:15px/1.6 -apple-system,BlinkMacSystemFont,"PingFang SC","Hiragino Sans GB",sans-serif;
     max-width:780px;margin:48px auto;padding:0 24px;color:#1a1a1a}
h1{font-size:32px;margin:0 0 8px}
.sub{color:#666;margin-bottom:32px}
table{border-collapse:collapse;width:100%;margin:24px 0}
th,td{text-align:left;padding:10px 12px;border-bottom:1px solid #eee}
th{background:#fafafa;font-weight:600}
.ok{color:#16a34a;font-weight:700}
.err{color:#dc2626;font-weight:700}
code{background:#f4f4f5;padding:2px 6px;border-radius:4px;font-size:13px}
.meta{background:#fafafa;border:1px solid #eee;border-radius:8px;padding:16px;margin:24px 0}
</style></head>
<body>
<h1>$NAME <code>$VERSION</code></h1>
<div class="sub">发布于 $(date -u +%Y-%m-%dT%H:%M:%SZ) · 由 /maxpublish 编排</div>

<h2>目标状态</h2>
<table>
<thead><tr><th style="width:60px">结果</th><th>平台</th><th>URL</th></tr></thead>
<tbody>
$ROWS
</tbody>
</table>

<div class="meta">
<strong>说明：</strong>本页面由 <code>/maxpublish</code> 自动生成。
</div>
</body></html>
HTML

echo "release notes page: $HTML"

TALK_PUBLISH="$HOME/.agents/skills/talk-html/publish.sh"
if [[ -x "$TALK_PUBLISH" ]]; then
  "$TALK_PUBLISH" "$HTML" || echo "talk-html publish failed; page kept at $HTML" >&2
else
  echo "talk-html not found; open $HTML manually" >&2
fi
