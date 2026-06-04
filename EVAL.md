# EVAL — 阻塞目录 + auto-fix 助手

> SKILL.md 是契约；REFERENCE.md 是平台细节；**本文件是阻塞修复目录**。agent 跑 `signals.sh` 拿到状态后，按这张表调修法助手。

## 一、按平台分组的阻塞目录

> 每行 = 一个阻塞；**修法**列直接是 skill 助手的调用。Agent 看到阻塞就调对应助手。

### npm / VS Code Marketplace（同一份 package.json）

| 阻塞 | 信号 | 修法 |
|---|---|---|
| 缺 `npm` CLI | `signals.sh: clis.npm=false` | `fix-install.sh vsce` 顺带装 npm（如缺）；或 `brew install node` |
| 缺 `vsce` CLI | `signals.sh: clis.vsce=false` | `fix-install.sh vsce` |
| `package.json` 有 `private:true` | `signals.sh: manifests.npm.private=true` | agent 提示用户：发 npm 必须改 false |
| 缺 `NODE_AUTH_TOKEN` / `NPM_TOKEN` | `signals.sh: envs.NODE_AUTH_TOKEN=false` | `fix-credentials.sh npm` 看获取链接 |
| 缺 `VSCE_PAT` | `signals.sh: envs.VSCE_PAT=false` | `fix-credentials.sh vsce` 看获取链接 |
| `npm whoami` 失败 | 调 publish 时报错 | `fix-credentials.sh npm` 重新检查 |
| `--provenance` 失败 | CI 无 OIDC | 改用 `npm publish --no-provenance`（牺牲供应链证据） |

### PyPI

| 阻塞 | 信号 | 修法 |
|---|---|---|
| 缺 `python3` | `signals.sh: clis.*` 缺 | `brew install python@3.12`（skill 不自动装系统） |
| 缺 `twine` | `signals.sh: clis.twine=false` | `fix-install.sh twine` |
| 缺 `build` | `python3 -m build` 报 ModuleNotFoundError | `fix-install.sh build` |
| 缺 `TWINE_API_KEY` 等 | `signals.sh: envs.TWINE_API_KEY=false` | `fix-credentials.sh pypi` |
| `dist/` 没 build | `python3 -m twine check` 报错 | agent 跑 `rm -rf dist/ build/ && python3 -m build` |
| 包名已占用 | `twine upload` 报 403 | 换名（agent 不自动改） |
| 版本重复 | `twine upload` 报 400 File already exists | bump 版本：`fix-version.sh <new>` |

### crates.io

| 阻塞 | 信号 | 修法 |
|---|---|---|
| 缺 `cargo` | `signals.sh: clis.cargo=false` | `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \| sh`（skill 不自动） |
| `Cargo.toml` 缺 `[package].publish=true` | `signals.sh: manifests.cargo.publish=false` | agent 提示用户：手改或设 publish=true |
| 缺 `CARGO_REGISTRY_TOKEN` | `signals.sh: envs.CARGO_REGISTRY_TOKEN=false` | `fix-credentials.sh cargo` 看获取链接 |
| 版本重复 | `cargo publish` 报 version already exists | `fix-version.sh <new>` |

### RubyGems

| 阻塞 | 信号 | 修法 |
|---|---|---|
| 缺 `gem` | `signals.sh: clis.gem=false` | 系统级 ruby（skill 不自动） |
| 缺 `GEM_HOST_API_KEY` | `signals.sh: envs.GEM_HOST_API_KEY=false` | `fix-credentials.sh gem` |
| gem 名含大写或 dash | publish 报错 | agent 提示：手改 gemspec 的 `spec.name`（gems 不允许大写/特殊字符） |
| 第一次发没 owner | 邮箱确认未点 | agent 提示：收邮件、点链接 |

### Docker Hub

| 阻塞 | 信号 | 修法 |
|---|---|---|
| 缺 `docker` | `signals.sh: clis.docker=false` | `brew install --cask docker` 或 `brew install docker`（skill 不自动） |
| 缺 `docker buildx` | `docker buildx version` 报错 | 装新版 docker（buildx 1.20+ 自带） |
| daemon 没起 | `docker info` 报 Cannot connect | agent 提示：开 Docker Desktop |
| 没 `docker login` | `docker info` 无 Username | agent 提示：跑 `docker login`（不要把密码存 env） |
| 缺 `DOCKERHUB_USERNAME` | `signals.sh: envs.DOCKERHUB_USERNAME=false` | `fix-credentials.sh docker`（可选；`docker login` 已带账号） |

### GHCR

| 阻塞 | 信号 | 修法 |
|---|---|---|
| 缺 `.github/workflows/*.yml` 配 GHCR | `signals.sh: manifests.ghcr-workflow` 不存在 | agent 提示：写 workflow（GHCR 通常在 CI 推） |
| 缺 `gh` CLI 或 `GITHUB_TOKEN` | `signals.sh: envs.GITHUB_TOKEN=false` 且 `clis.gh=false` | `fix-install.sh gh` + `gh auth login` |
| `gh` 没 `packages:write` 权限 | `docker push ghcr.io/...` 403 | 重新 `gh auth refresh -s write:packages` |

### GitHub Release

| 阻塞 | 信号 | 修法 |
|---|---|---|
| 不是 git repo | `signals.sh: git.is_repo=false` | agent 提示：`git init` + 远端 |
| 缺 `gh` CLI | `signals.sh: clis.gh=false` | `fix-install.sh gh` |
| `gh` 没 auth | `gh auth status` 失败 | `gh auth login`（agent 提示） |
| 已有同名 tag | `git tag` 报 already exists | agent 提示：`git tag -d` 本地 + `git push origin :refs/tags/X` 远端 |
| 脏工作区 | `signals.sh: git.dirty=true` | agent 提示：commit / stash |

### Homebrew tap

| 阻塞 | 信号 | 修法 |
|---|---|---|
| 没 `Formula/<name>.rb` | `signals.sh: manifests.brew-formula` 不存在 | agent 提示：写 formula（url / sha256 / version） |
| 没 `homebrew-tap` git remote | `git remote get-url homebrew-tap` 失败 | agent 提示：建 tap 仓库、加 remote |
| tap 仓库不可达 | `git ls-remote <tap-url>` 失败 | agent 提示：检查 SSH key、tap 仓库 visibility |
| sha256 错 | `brew install` 失败 | agent 提示：`shasum -a 256 <tarball>` 重新算 |

### 通用（项目层）

| 阻塞 | 信号 | 修法 |
|---|---|---|
| 版本不一致 | signals 显示多个 manifest 但 version 不同 | `fix-version.sh <new>` 一次同步 |
| 缺 `CHANGELOG` | 不在 signals 里（信号不报） | agent 提示用户：写一份 |
| 缺 `LICENSE` | 不在 signals 里 | agent 提示用户：补 |
| 旧 tag 还在 | `git tag --list` 显示 | agent 提示：`git tag -d` + `git push origin :refs/tags/X` |

## 二、Definition of Done（agent 跑完应满足）

agent 在 RECORD 前应自检：

- [ ] signals.sh 报告的所有 manifest 版本号 = 目标版本
- [ ] signals.sh 报告的 clis 包含 agent 选定平台所需的全部
- [ ] signals.sh 报告的 envs 包含 agent 选定平台所需的全部
- [ ] signals.sh 报告的 git.dirty = false
- [ ] 每个失败的 platform 都 `record.sh <plat> <ver> failed "<err>"` 记过
- [ ] 每个成功的 platform 都 `record.sh <plat> <ver> ok "<url>"` 记过

## 三、什么时候不用 /maxpublish

- **单渠道**：直接调官方 CLI（`npm publish`），不要绕一圈
- **CI 自动发版**：用 release-please / semantic-release
- **内部 registry**：走你公司的发布流水线
- **beta / RC tag**：直接手敲 `npm publish --tag next`

## 四、加新平台的清单

要支持新平台（如 `conda-forge`）：

1. **`scripts/signals.sh`** 在 `manifests` 探测里加一条（如 `meta.yaml` → `conda-forge`）
2. **`scripts/fix-install.sh`** 加 `conda` case（如有对应包管理）
3. **`scripts/fix-credentials.sh`** 加 `conda-forge` case（指明 env / 登录路径）
4. **`scripts/fix-version.sh`** 在合适文件类型里加 bump（如 `meta.yaml` 的 `version` 字段）
5. **`REFERENCE.md`** 加一节详细矩阵
6. **本文件第一节** 加阻塞行
7. **SKILL.md** 描述里加触发词
