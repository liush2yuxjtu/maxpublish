# REFERENCE — 10 注册表详细矩阵

> SKILL.md 是契约；本文件是渠道细节。agent 在选目标、配置凭证、诊断失败时回查这里。

## 索引

| 渠道 | 适用信号 | 命令 | 凭证 | 失败回滚 |
|---|---|---|---|---|
| [npm](#1-npm) | `package.json` 非 private | `npm publish --provenance` | `NODE_AUTH_TOKEN` | 72h 内 `npm unpublish` |
| [VS Code Marketplace](#2-vs-code-marketplace) | `engines.vscode` | `npx @vscode/vsce publish` | `VSCE_PAT` | 手动删版本 |
| [PyPI](#3-pypi) | `pyproject.toml` / `setup.py` | `twine upload dist/*` | `TWINE_API_KEY` | `twine yank` |
| [crates.io](#4-cratesio) | `Cargo.toml` 且 `publish=true` | `cargo publish` | `CARGO_REGISTRY_TOKEN` | 24h 后 `cargo yank` |
| [RubyGems](#5-rubygems) | `*.gemspec` | `gem push <gem>` | `GEM_HOST_API_KEY` | `gem yank` |
| [Docker Hub](#6-docker-hub) | `Dockerfile` | `docker buildx build --push` | `docker login` | tag 不可删 |
| [GHCR](#7-ghcr) | workflow 引用 GHCR | `docker push ghcr.io/...` | `GITHUB_TOKEN` (write:packages) | 删 package version |
| [GitHub Release](#8-github-release) | git repo + 标签 | `gh release create` | `gh auth` | `gh release delete` + 删 tag |
| [Homebrew tap](#9-homebrew-tap) | `Formula/*.rb` + tap remote | push 公式到 tap 仓库 | SSH key | revert 公式 commit |
| [AMO (Firefox)](#10-amo-firefox-addons) | `manifest.json` 含 gecko | `web-ext sign --api-key ...` | `AMO_API_KEY` + `AMO_API_SECRET` | web UI 删版本 |
| [Chrome Web Store](#11-chrome-web-store) | `manifest.json` (MV3) | 上传 zip 到 CWS dashboard | CWS 开发者账号 | CWS dashboard 删 |
| [Edge Add-ons](#12-edge-addons) | `manifest.json` (MV3) | partners dashboard 上传 | 微软合作伙伴账号 | dashboard 删 |
| [Talk-HTML 公告](#13-talk-html-公告) | 总是可选 | `talk-html/publish.sh` | `gh auth` | gist 不可删，只能新建 |

---

## 1. npm

**适用信号**
- `package.json` 存在且 `private` 不是 `true`
- 推荐 `engines.node` 已写

**凭证**
- `NODE_AUTH_TOKEN`（CI 推荐）或 `NPM_TOKEN`（个人用）
- token 需含 `Automation` 权限

**自检**
```bash
npm whoami              # 验证 token 有效
npm view <name> versions | tail   # 看是否已发过同名版本
```

**命令**
```bash
npm publish --provenance --access public
```

**失败回滚**
- 72 小时内：`npm unpublish <pkg>@<ver> --force`
- 超过 72h：`npm deprecate <pkg>@<ver> "reason"`（不可删，只能标记）
- provenance 失败但已发：当前 npm 会拒绝重发；只能 `deprecate`

**已知坑**
- `--provenance` 需要 GitHub Actions OIDC；本机手发通常拿不到，改 `--no-provenance`
- scoped package 第一次发需要 `--access public`

---

## 2. VS Code Marketplace

**适用信号**
- `package.json` 含 `engines.vscode`（任意版本）
- 有 `publisher` 字段
- `repository` URL 配对
- 推荐 `.vscodeignore` 排除 `node_modules/` 等

**凭证**
- `VSCE_PAT`：Azure DevOps PAT，scope = `Marketplace (Manage)`

**自检**
```bash
npx @vscode/vsce login <publisher>   # 触发 PAT 弹窗
npx @vscode/vsce show <publisher>.<ext>   # 看是否已上架
```

**命令**
```bash
npx --yes @vscode/vsce publish <version> --no-git-tag-version
```

**失败回滚**
- Marketplace UI：<https://marketplace.visualstudio.com/manage> → 选扩展 → 删版本
- CLI 没有 unpublish；只能 UI 删

**已知坑**
- `package.json` 里 `version` 必须和 `--version` 一致，否则报错
- `.vsceignore` 没配会把 `node_modules` 一起打包，超 50MB 拒收
- 第一次发需要 publisher 在 Marketplace 已注册

---

## 3. PyPI

**适用信号**
- `pyproject.toml` 或 `setup.py` 存在
- 推荐用 `pyproject.toml`（PEP 621）
- `python -m build` 能成功跑

**凭证**
- `TWINE_API_KEY`（推荐；PyPI → Account → API tokens）
- 或 `TWINE_USERNAME` + `TWINE_PASSWORD`（legacy）
- 测试用 `TWINE_REPOSITORY_URL=https://test.pypi.org/legacy/`

**自检**
```bash
python3 -m build --version    # 需 pip install build
python3 -m twine check dist/* # 看包是否符合规范
```

**命令**
```bash
rm -rf dist/ build/ *.egg-info
python3 -m build
python3 -m twine upload dist/*
```

**失败回滚**
- 不允许 re-upload 同版本：用 `twine yank <pkg> ==<ver>`（标记但不删）
- 已 yank 的版本仍可 `pip install` 但默认 `pip install` 不再拉
- 永久删除需要联系 PyPI admin

**已知坑**
- 包名全局唯一；先 `pip search <name>` 验证未占用（PyPI 已停 search，需 web 查）
- wheel 和 sdist 都要打
- version 必须符合 PEP 440

---

## 4. crates.io

**适用信号**
- `Cargo.toml` 存在
- `[package].publish` 不为 `false`
- `description` / `license` 至少有一个

**凭证**
- `CARGO_REGISTRY_TOKEN`：<https://crates.io/settings/tokens>

**自检**
```bash
cargo login <token>           # 一次性，写入 ~/.cargo/credentials
cargo package --list          # 看包内容
```

**命令**
```bash
cargo publish
```

**失败回滚**
- 24h 内可 `cargo yank --version <ver> <crate>`（crates.io web 也能 yank）
- yank 后仍可 `cargo install --version <ver>`，但默认锁文件不拉

**已知坑**
- 第一次发会同时上传 crate 源码（git tag 自动建）
- `[package].repository` 强烈推荐；不写会被 crates 警告

---

## 5. RubyGems

**适用信号**
- `*.gemspec` 存在
- 至少填了 `name` / `version` / `summary` / `authors`

**凭证**
- `GEM_HOST_API_KEY`：<https://rubygems.org/settings/edit>

**自检**
```bash
gem signin                    # 一次性，写入 ~/.gem/credentials
gem build *.gemspec           # 生成 .gem 文件
```

**命令**
```bash
gem_file=$(gem build *.gemspec 2>/dev/null | grep -oE 'File: [^ ]+' | awk '{print $2}')
gem push "$gem_file"
```

**失败回滚**
- `gem yank <gem> -v <ver>`（72h 后才能 push 同 ver）

**已知坑**
- gem 名要小写 + 下划线（不是 dash）
- 第一次发会触发 owner 邮件确认

---

## 6. Docker Hub

**适用信号**
- `Dockerfile` 存在
- 推荐多阶段构建 + 显式 `FROM` 基础镜像

**凭证**
- `DOCKERHUB_USERNAME` + `DOCKERHUB_TOKEN`（推荐用 token 不是密码）
- `docker login` 一次性写 `~/.docker/config.json`

**自检**
```bash
docker info                              # 看 daemon 是否在
docker buildx version                    # buildx 必装
docker buildx ls                         # 现有 builder
```

**命令**
```bash
docker buildx build --platform linux/amd64,linux/arm64 \
  -t "${DOCKERHUB_USERNAME}/${NAME}:${VERSION}" \
  -t "${DOCKERHUB_USERNAME}/${NAME}:latest" --push .
```

**失败回滚**
- Docker Hub 不允许删 tag，只能 `docker hub-tag --delete` (新 API) 或 web UI
- 旧 tag 会留痕

**已知坑**
- 默认 builder 不支持多平台；`docker buildx create --use` 先建一个
- `--push` 不能省；缺它等于只 build 不传
- 第一次发要先 `docker login`

---

## 7. GHCR

**适用信号**
- `.github/workflows/*.yml` 引用 `ghcr.io` 或 `packages: write` 权限
- 或 Dockerfile 配置了 `ghcr.io/<owner>/<repo>`

**凭证**
- `GITHUB_TOKEN`（CI 自动注入；本机用 `gh auth token`）
- 需 scope = `write:packages`

**自检**
```bash
gh auth status              # 看是否含 packages:write
```

**命令**
```bash
docker buildx build --platform linux/amd64,linux/arm64 \
  -t "ghcr.io/${OWNER}/${REPO}:${VERSION}" --push .
```

**失败回滚**
- web UI：Package 页面 → 版本 → Delete（不可恢复）

**已知坑**
- GHCR 包默认 private；要设 public 走 package settings
- 同名 tag 推送是 immutable 的；要"更新"必须 `docker buildx imagetools create` 改名

---

## 8. GitHub Release

**适用信号**
- git 仓库（有 `.git/`）
- 默认 branch 已 push

**凭证**
- `gh auth status` 通过（`gh auth login` 一次性）

**自检**
```bash
gh auth status
gh release list
```

**命令**
```bash
git tag -a "v${VERSION}" -m "Release ${VERSION}"
git push origin "v${VERSION}"
gh release create "v${VERSION}" --generate-notes
```

**失败回滚**
- `gh release delete <tag> --yes`
- `git push origin :refs/tags/<tag>`（远端删 tag）
- `git tag -d <tag>`（本地删 tag）

**已知坑**
- tag 已存在会报 `tag already exists`；先 `git tag -d` 再重试
- `--generate-notes` 自动从 PR 拉 changelog；要手动写用 `--notes-file`

---

## 9. Homebrew tap

**适用信号**
- 项目内有 `Formula/<name>.rb`（或根目录 `*.rb` 含 `class XxxFormula`）
- `homebrew-tap` 这个 git remote 已配
- tap 仓库 URL 可达

**凭证**
- tap 仓库的 SSH push 权限（`~/.ssh/config` 配 `github.com`）

**自检**
```bash
git remote get-url homebrew-tap
git ls-remote <tap-url> HEAD
brew tap-info <user/tap>            # 如果 brew 在 PATH
```

**命令**
```bash
# 1. 拉 tap 仓库到临时目录
workdir=$(mktemp -d)
git clone --depth 1 "$tap_url" "$workdir"

# 2. 渲染新 formula：
#    - url 指向新 release tarball
#    - sha256 是新 tarball 的校验和
#    - version 字段更新
# 留 hook：这一步 maxpublish 不替做（避免覆盖自定义逻辑）

# 3. 提交 + push
cd "$workdir"
git add Formula/<name>.rb
git commit -m "<name> <version>"
git push origin main
```

**失败回滚**
- 远端 `git revert` 上一 commit + push

**已知坑**
- formula 的 `url` 和 `sha256` 必须配对；sha256 错了 `brew install` 失败
- 第一次发要建 tap 仓库（`gh repo create <user>/homebrew-tap --public`）

---

## 10. Talk-HTML 公告

**适用信号**
- 总是可选；不依赖项目类型

**凭证**
- `gh auth status` 通过（同 gh-release）

**自检**
```bash
gh gist list
ls ~/.agents/skills/talk-html/publish.sh
```

**命令**
```bash
~/.agents/skills/talk-html/publish.sh <release-notes.html>
```

**失败回滚**
- gist 不能删，只能 `gh gist delete <id>`（删除整个 gist）
- 本地 HTML 还在；重发即可

**已知坑**
- 一页通会被 htmlpreview 缓存；改完要 `?` 加随机串或等几分钟
- 含 secret 的页面不要发；本地留即可


---

## 10. AMO (Firefox addons)

**适用信号**
- 项目根有 `manifest.json` (WebExtension)
- 含 `browser_specific_settings.gecko` 字段
- `manifest_version` 是 2 或 3

**凭证**
- `AMO_API_KEY` + `AMO_API_SECRET`：<https://addons.mozilla.org/developers/addon/api/key/>
- 推荐用 `web-ext` CLI 自动化

**自检**
```bash
npx --yes web-ext --version            # 需 Node 14+
```

**命令**
```bash
# 1. 打包（不含 source map、私有文件）
npx --yes web-ext build --overwrite-dest

# 2. 签名（推荐，让 Firefox 自动接受更新）
npx --yes web-ext sign \
  --api-key "$AMO_API_KEY" \
  --api-secret "$AMO_API_SECRET" \
  --id "<your-addon-id-from-amo>"

# 3. 上传（手动或 programmatic）
# 手动：去 https://addons.mozilla.org/en-US/developers/addon/<slug>/versions/submit/
```

**失败回滚**
- AMO Web UI：选版本 → 取消发布（un-listed）→ 删版本
- 已签的 .xpi 不可改；要重发只能新版本号

**已知坑**
- AMO 审核要 1-7 天；首次发尤其慢
- `browser_specific_settings.gecko.id` 必须在第一次发时定好，之后不能改
- `web-ext sign` 默认输出到 `web-ext-artifacts/`，注意 `.gitignore`

---

## 11. Chrome Web Store

**适用信号**
- `manifest.json` (WebExtension)
- 不含 `browser_specific_settings.gecko`（纯 Chrome / Edge MV3）
- 或含 `browser_specific_settings.edge` 但还没定到 AMO

**凭证**
- CWS 开发者账号：注册费 USD 5 一次性
- 推荐 `chrome-webstore-upload` CLI 自动化

**自检**
```bash
npx --yes chrome-webstore-upload-cli --version 2>&1 | head -3
```

**命令**
```bash
# 1. 打包 zip（去掉 .git、node_modules、source map）
zip -r dist/extension.zip . -x "*.git*" "node_modules/*" "src/*" "*.map"

# 2. 上传到 CWS
npx --yes chrome-webstore-upload-cli upload \
  --source dist/extension.zip \
  --extension-id "<your-extension-id>" \
  --client-id "$CWS_CLIENT_ID" \
  --client-secret "$CWS_CLIENT_SECRET" \
  --refresh-token "$CWS_REFRESH_TOKEN"

# 3. publish（默认 uploaded→draft，需 publish 才上线）
npx --yes chrome-webstore-upload-cli publish \
  --extension-id "<your-extension-id>" \
  --client-id "$CWS_CLIENT_ID" \
  --client-secret "$CWS_CLIENT_SECRET" \
  --refresh-token "$CWS_REFRESH_TOKEN"
```

**凭证获取**（一次性）
```bash
# 1. 在 Google Cloud Console 建 OAuth client
# 2. 用 chrome-webstore-upload-cli 拿 refresh_token：
npx --yes chrome-webstore-upload-cli --help
# 跟着提示走 OAuth flow
```

**失败回滚**
- CWS Dashboard → 选扩展 → Item: Unpublish（不可删，只能 unlist）
- 已发布的版本无法撤回——只能发新版修

**已知坑**
- CWS 审核通常 1-3 天
- `extension_id` 在 CWS dashboard 里查；首次发没有，需手动先上传一次
- MV2 已被 CWS 弃用；新扩展必须 MV3

---

## 12. Edge Add-ons

**适用信号**
- `manifest.json` 含 `browser_specific_settings.edge`
- 或纯 Chrome MV3 同时想上 Edge

**凭证**
- 微软 Partner Center 开发者账号
- 推荐 `microsoft-edge-addons-api` 或 `edge-addons-api` npm 包

**自检**
```bash
npx --yes edge-addons-api --help 2>&1 | head -3
```

**命令**
```bash
# 1. 打包（同 Chrome Web Store 流程）
zip -r dist/extension.zip . -x "*.git*" "node_modules/*"

# 2. 上传 + publish
npx --yes edge-addons-api \
  --product-id "<product-id-from-partner-center>" \
  --client-id "$EDGE_CLIENT_ID" \
  --client-secret "$EDGE_CLIENT_SECRET" \
  --zip-path dist/extension.zip \
  upload
npx --yes edge-addons-api \
  --product-id "$product_id" \
  --client-id "$EDGE_CLIENT_ID" \
  --client-secret "$EDGE_CLIENT_SECRET" \
  --operation-id "<from-upload-response>" \
  publish
```

**凭证获取**
- Partner Center → 开发者设置 → API credentials
- `client_id` + `client_secret` + `product_id`（每个扩展一个）

**失败回滚**
- Partner Center → 扩展 → Unlist（不可删）
- 同 Chrome，已发布版本无法撤回

**已知坑**
- Edge 审核比 CWS 快（通常 24-48h）
- 同一份 zip 可同时上 CWS + Edge；先发 CWS 拿到 extension_id，再发 Edge
- 微软 OAuth 比 Google 严；token 默认 1 年过期

---

## 13. Talk-HTML 公告

（无变化——见原 §10 章节）
