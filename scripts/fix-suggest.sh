#!/usr/bin/env bash
# fix-suggest.sh — given an error excerpt, suggest a fix.
# usage: fix-suggest.sh <platform> <error-message>
#
# This is a static error→fix mapping table. Heuristic; not perfect.

set -euo pipefail

PLAT="${1:-}"; ERR="${2:-}"
[[ -n "$PLAT" && -n "$ERR" ]] || {
  echo "usage: $0 <platform> <error-message>" >&2
  exit 64
}

bold()  { echo -e "\033[1m▸\033[0m $*"; }

# case-insensitive substring match
match() {
  echo "$ERR" | grep -qiE "$1"
}

case "$PLAT" in
  npm)
    if match "ENEEDAUTH|401 Unauthorized|not authorized|EOTP|OTP"; then
      bold "→ NODE_AUTH_TOKEN 失效或权限不足"
      echo "  1. https://www.npmjs.com/settings/<user>/tokens → 重新生成 token，scope = Automation"
      echo "  2. export NODE_AUTH_TOKEN=npm_xxxxxxxxxx"
      echo "  3. npm whoami 验证"
    elif match "403 Forbidden|cannot publish over existing|two-factor|2FA"; then
      bold "→ 2FA / 同名包已存在"
      echo "  - 开了 2FA: npm adduser 后用 npm login 再 publish"
      echo "  - 同名包已发: 改 package.json 的 name 字段（或用 scope）"
    elif match "version|already published|duplicate"; then
      bold "→ 版本号已发过"
      echo "  bump 版本: fix-version.sh <new>  或  jq '.version=\"X.Y.Z\"' package.json"
    elif match "provenance|EUNKNOWNPROVENANCE|public"; then
      bold "→ provenance / access 设置"
      echo "  - 私有包：加 --access public"
      echo "  - 无 OIDC：加 --no-provenance"
    else
      bold "→ 通用 npm 排查：npm doctor && npm config get registry"
    fi
    ;;
  vsce)
    if match "401|Unauthorized|PAT|token"; then
      bold "→ VSCE_PAT 失效"
      echo "  1. https://dev.azure.com → User settings → Personal access tokens → 新建 (Marketplace: Manage)"
      echo "  2. export VSCE_PAT=<token>"
    elif match "version already exists|already published"; then
      bold "→ 该版本已存在"
      echo "  bump 版本: fix-version.sh <new>"
    elif match "publisher|not found"; then
      bold "→ publisher 未注册"
      echo "  1. https://marketplace.visualstudio.com/manage → Create publisher"
      echo "  2. package.json: \"publisher\": \"<your-name>\""
    elif match "size|50MB|too large|extension folder size"; then
      bold "→ 包超 50MB"
      echo "  配 .vscodeignore 排除 node_modules / .git / dist / tests / *.map"
    else
      bold "→ 通用 vsce 排查：npx @vscode/vsce --help"
    fi
    ;;
  pypi)
    if match "401|Invalid credentials|csrf"; then
      bold "→ TWINE_API_KEY 失效"
      echo "  1. https://pypi.org/manage/account/token/ → Add API token"
      echo "  2. export TWINE_API_KEY=pypi-xxxxxx"
    elif match "File already exists|already exists"; then
      bold "→ 版本已发过（PyPI 不可重传）"
      echo "  bump 版本: fix-version.sh <new>  然后 python3 -m build && twine upload dist/*"
    elif match "description|long_description|invalid"; then
      bold "→ 包元数据不合规"
      echo "  python3 -m twine check dist/*  看具体哪条不通过"
    else
      bold "→ 通用 pypi 排查：twine check dist/*"
    fi
    ;;
  cargo)
    if match "error: failed to publish|Unauthorized|API token"; then
      bold "→ CARGO_REGISTRY_TOKEN 失效"
      echo "  1. https://crates.io/settings/tokens → New Token"
      echo "  2. export CARGO_REGISTRY_TOKEN=cio..."
    elif match "already uploaded|version.*exists"; then
      bold "→ 版本已发过"
      echo "  bump Cargo.toml 的 [package].version: fix-version.sh <new>"
    elif match "missing.*license|missing.*description|description.*required"; then
      bold "→ 包元数据缺字段"
      echo "  Cargo.toml 必须填 license / description（缺一不发）"
    else
      bold "→ 通用 cargo 排查：cargo package --list"
    fi
    ;;
  gem)
    if match "401|API key|invalid"; then
      bold "→ GEM_HOST_API_KEY 失效"
      echo "  1. https://rubygems.org/settings/edit → API Keys"
      echo "  2. export GEM_HOST_API_KEY=<key>"
    elif match "already exists|already pushed"; then
      bold "→ 版本已发过（RubyGems 72h 锁）"
      echo "  bump gemspec 的 spec.version: fix-version.sh <new>"
    else
      bold "→ 通用 gem 排查：gem build *.gemspec 2>&1 | tail"
    fi
    ;;
  docker)
    if match "denied|access denied|unauthorized|401"; then
      bold "→ docker login 失效或权限不足"
      echo "  docker login  重新登录"
      echo "  确认 DOCKERHUB_USERNAME 是 owner，token 有 push 权限"
    elif match "tag already exists|already exists"; then
      bold "→ 同 tag 已存在（Docker Hub 不可改）"
      echo "  bump 版本 / 改 tag 名"
    else
      bold "→ 通用 docker 排查：docker info / docker buildx ls"
    fi
    ;;
  ghcr)
    if match "denied|insufficient_scope|missing.*write:packages"; then
      bold "→ GITHUB_TOKEN 缺 packages:write"
      echo "  gh auth refresh -s write:packages"
      echo "  或：https://github.com/settings/tokens → Regenerate，加 write:packages"
    elif match "package.*not found|repository.*not found"; then
      bold "→ 包名不对 / repo 不存在"
      echo "  确认 ghcr.io/<owner>/<repo> 里的 owner/repo 正确"
    else
      bold "→ 通用 ghcr 排查：gh auth token 看 scope"
    fi
    ;;
  gh-release)
    if match "tag already exists"; then
      bold "→ tag 已存在"
      echo "  git tag -d vX.Y.Z && git push origin :refs/tags/vX.Y.Z  先清掉"
    elif match "not a git repository|not in repo"; then
      bold "→ 不在 git 仓库"
      echo "  git init && git remote add origin <url> && git push -u origin main"
    else
      bold "→ 通用 gh release 排查：gh release list"
    fi
    ;;
  brew)
    if match "Permission denied|publickey|SHAPSS"; then
      bold "→ SSH key 问题"
      echo "  ssh -T git@github.com  验证 SSH 通了"
      echo "  cat ~/.ssh/config  看 tap 仓库的 Host 配置"
    elif match "sha256 mismatch|Checksum mismatch"; then
      bold "→ formula 的 sha256 跟新 tarball 对不上"
      echo "  shasum -a 256 <tarball-url-downloaded-file>  重新算填进 formula"
    else
      bold "→ 通用 brew 排查：brew tap-info <user>/<tap>"
    fi
    ;;
  amo)
    if match "401|Invalid API key|Unauthorized"; then
      bold "→ AMO_API_KEY / AMO_API_SECRET 错"
      echo "  1. https://addons.mozilla.org/developers/addon/api/key/ 重新生成"
      echo "  2. 确认用 --id <your-addon-id>，不是 slug"
    elif match "version.*already|duplicate version"; then
      bold "→ 版本号已发过"
      echo "  bump manifest.json 的 version: fix-version.sh <new>"
    else
      bold "→ 通用 AMO 排查：npx web-ext sign --help"
    fi
    ;;
  chrome-web-store)
    if match "404|Not Found|extension not found"; then
      bold "→ CWS extension_id 错或没首次上传过"
      echo "  1. 手动去 https://chrome.google.com/webstore/devconsole/ 上传一次 zip"
      echo "  2. 拿到 extension_id 后再自动化"
    elif match "Invalid OAuth|invalid_grant|refresh_token"; then
      bold "→ OAuth refresh_token 失效"
      echo "  重新走 chrome-webstore-upload-cli 的 OAuth flow 拿新 refresh_token"
    else
      bold "→ 通用 CWS 排查：https://chrome.google.com/webstore/devconsole/"
    fi
    ;;
  edge-addons)
    if match "401|Unauthorized|invalid_client"; then
      bold "→ EDGE_CLIENT_ID / EDGE_CLIENT_SECRET 错"
      echo "  Partner Center → 开发者设置 → API credentials 重新生成"
    elif match "404|product not found"; then
      bold "→ product_id 错"
      echo "  Partner Center → Extensions → 拿 product_id"
    else
      bold "→ 通用 Edge 排查：https://partner.microsoft.com/dashboard/microsoftedge/"
    fi
    ;;
  *)
    echo "  (no platform-specific mapping; check REFERENCE.md §-$PLAT)"
    ;;
esac
