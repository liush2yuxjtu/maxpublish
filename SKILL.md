---
name: maxpublish
description: >-
  Multi-registry publish with one-shot HITL decision panel. Detects 22
  manifest types (npm, vsce, pypi, cargo, gem, docker, ghcr, AMO, Chrome
  Web Store, Edge Add-ons, Homebrew, GitHub Release, pub, swiftpm, maven,
  packagist, hex, helm, luarocks, shards, nix-flake), auto-FILLS missing
  manifest fields (description, repository, license, keywords) before
  showing blockers, then opens a single editorial-style HTML page with
  per-platform brand colors, ALL blockers + OAuth notes + draft candidates
  + 4 action buttons (publish / high-only / with-extras / deny). Copies a
  single ready-to-paste prompt back to Claude Code. Agent (or user) decides
  platforms; skill records results, runs official CLIs in parallel.
  **Try to fill everything and publish it** — never stop at "detect only".
  ALWAYS use this skill when the user wants to ship a release to one or
  more package registries, mentions publishing / 发版 / 推到注册表 / release
  v…, asks "can I publish this?", or says /maxpublish — even if they only
  mention one registry. Do NOT use for CI-only publishing (release-please
  etc.), single-platform quick publish (just run npm publish directly), or
  QA/bug reports.
---

# /maxpublish — one-shot multi-registry publish with single HITL

**目标：发到尽可能多的平台。** 一个 HTML 页搞定所有决策——signals + blockers + OAuth + draft 候选 + 4 按钮，copy 一次粘贴回 Claude Code。

## 入口

```bash
# 默认：检测 + 自动填缺字段 + 打开 HITL HTML + 弹出浏览器
/maxpublish

# CI：跳过 HTML，inline 输出
MAXPUBLISH_CI=1 /maxpublish

# 跳过自动 fill（只诊断）
MAXPUBLISH_SKIP_FILL=1 /maxpublish --eval
```

## 5 步流程（**单 HITL** + try-to-fill-everything）

```
0. FILL  ← 新增
   scripts/fill-manifest.sh
   → 主动填 package.json / pyproject.toml / Cargo.toml / *.gemspec /
     Dockerfile / vsce 缺的字段（description, repository, license, keywords）
   → 已有则不动；用 git remote URL 推断 repository
   → 这一步在 HITL 之前，目标是让"缺字段"不再成为 blocker

1. ASSESS
   scripts/signals.sh --json
   → 22 个 manifest 探测（npm, vsce, pypi, cargo, gem, docker, ghcr,
     AMO, CWS, Edge, brew, gh-release, pub, swiftpm, maven, packagist,
     hex, helm, luarocks, shards, nix-flake）
   → envs / clis / git 状态
   → 当前版本号

2. OPEN HITL  ← 唯一的人类介入点
   scripts/hitl-html.sh
   → 一个 HTML 页（含 4 段 + 22 平台品牌色）：
     §1  signals detected
     §2  blocker tokens（每平台 + env + URL + token input + copy export 按钮）
     §3  OAuth-required platforms（每平台：跳过服务端，给 CLI 提示让用户自己跑）
     §4  publish draft（候选清单 + "add more" 复选框）
   → 4 按钮（每个 copy 一个 prompt 粘回 Claude Code）：
     ✓ publish selected
     ✓ publish high only
     + publish with extras
     ✗ deny

3. PUBLISH（agent bash，每个平台单独子 shell & 并发跑，输出 tee 到 logs/）
   → 失败用 scripts/fix-suggest.sh 找修复
   → 不阻塞其他

4. RECORD  scripts/record.sh <plat> <ver> ok|failed "<url|err>" 每个一条

5. ANNOUNCE  scripts/announce.sh <ver> <name> '<results-json>' → talk-html
```

## auto-default 规则

| 检测到 | 候选 | confidence | 品牌色 |
|---|---|---|---|
| `package.json` 非 private | **npm** | high | `#cb3837` |
| `package.json` 含 `engines.vscode` | **vsce** | high | `#0078d4` |
| `pyproject.toml` / `setup.py` | **pypi** | high | `#3776ab` |
| `Cargo.toml` 且 `publish=true` | **cargo** | high | `#dea584` |
| `*.gemspec` | **gem** | high | `#cc342d` |
| `Dockerfile` | **docker** | high | `#0db7ed` |
| `manifest.json` 含 gecko | **amo** | high | `#ff7139` |
| `manifest.json` (MV3, no gecko) | **chrome-web-store** | high | `#4285f4` |
| `manifest.json` 含 edge key | **edge-addons** | high | `#0078d4` |
| `pubspec.yaml` | **pub** | high | `#0175c2` |
| `Package.swift` | **swiftpm** | high | `#f05138` |
| `pom.xml` / `build.gradle*` | **maven** | high | `#b41e31` |
| `composer.json` | **packagist** | high | `#4f5d95` |
| `mix.exs` | **hex** | high | `#a174c0` |
| `Chart.yaml` | **helm** | high | `#0f1689` |
| `*.rockspec` | **luarocks** | high | `#1f5b94` |
| `shard.yml` | **shards** | high | `#10b981` |
| `flake.nix` | **nix-flake** | high | `#5277c3` |
| git repo + gh authed | **gh-release** | medium | — |
| `.github/workflows/*` 引用 ghcr | **ghcr** | medium | — |
| `Formula/*.rb` + `homebrew-tap` remote | **brew** | medium | — |

high → auto-default · medium → HITL 页默认勾选但用户可去

## User Wants, Tools, Outputs

| # | User wants | Tool | Output |
|---|---|---|---|
| 1 | 这项目能发到哪？ | `signals.sh` (22 渠道) | manifests / clis / envs / git |
| 2 | 缺字段？ | `fill-manifest.sh` | 主动填 description/repo/license/keywords |
| 3 | 缺什么 token？ | `hitl-html.sh` | HTML：signals + blockers + OAuth + draft + 4 按钮 |
| 4 | OAuth 怎么办？ | HITL §3 提示 | 用户用已有 CLI / skill 走，skill 不开浏览器、不用服务端 |
| 5 | 真发哪几个？ | HITL §4 候选 | 4 按钮 copy 一个 prompt 粘回 |
| 6 | 怎么真发？ | agent bash 并发 | 每平台 `&` 子 shell + `tee logs/<plat>.<ver>.log` |
| 7 | 失败怎么修？ | `fix-suggest.sh` | 错误→修复映射（10 平台） |
| 8 | 怎么记？ | `record.sh` | index.jsonl 一行 |
| 9 | 怎么出 release notes？ | `announce.sh` | gist + htmlpreview 一页通 |
| 10 | SEO / share preview？ | `hitl-html.sh` | Open Graph + Twitter Card + JSON-LD |

## Non-Negotiables

- **Try to fill everything** before showing blockers（fill-manifest.sh 先跑）
- **一个 HITL 页 = 一个决策 = 一个 copy**——不分散到 blocker.html / draft.html
- signals.sh 只读、不会改文件
- fix-credentials.sh 永远不写 token——只报告
- fix-install.sh 直接装（不二次确认）
- 真 publish 由 agent 用 bash 调官方 CLI；skill 不替你发
- 多平台**并发推**，每个子 shell 输出 `tee` 到 `<plat>.<ver>.log`，**不混日志**
- 失败不阻塞其他；记录里标 `failed`，继续
- 错误信息**后面跟 fix-suggest.sh 的修复建议**
- **OAuth 不开浏览器 / 不用服务端**——HITL §3 给 CLI 提示让用户自处理
- 不加 `.maxpublish.json` 配置；不加 `init` / `pack`；不加 duration_ms
- 英文输出；不加 skill 版本字段；不加测试 fixture

## 目录

```
maxpublish/
├── SKILL.md            契约：本文件
├── REFERENCE.md        22 平台详细矩阵
├── EVAL.md             阻塞目录 + 修法助手 + 错误→修复
├── package.json        npm-publishable（含 keywords/repository 等 SEO 字段）
├── evals/
│   └── evals.json      trigger eval queries
└── scripts/
    ├── bin/maxpublish.js     npm-bin wrapper
    ├── signals.sh            ASSESS：22 渠道探测
    ├── fill-manifest.sh      ⭐ FILL：主动填缺字段
    ├── hitl-html.sh          ⭐ HITL：唯一人类介入点（品牌色 + SEO meta）
    ├── fix-install.sh        装缺失 CLI
    ├── fix-credentials.sh    检查凭证
    ├── fix-version.sh        bump manifest 版本
    ├── fix-suggest.sh        错误→修复建议
    ├── record.sh             写 index.jsonl
    └── announce.sh           调 talk-html 出 release notes
```

## 加新平台

6 个文件要改：

1. `scripts/signals.sh` — 加 manifest 探测
2. `scripts/fix-install.sh` — 加 CLI 安装 case（如有）
3. `scripts/fix-credentials.sh` — 加凭证检查
4. `scripts/hitl-html.sh` — `PLATFORMS` / `SIG_MAP` / `EXTRA_PLATFORMS` 加平台 + 品牌色 + 22 个 CSS rule
5. `scripts/fill-manifest.sh` — 加平台特有字段（如 pubspec.yaml 的 `name:` 等）
6. `REFERENCE.md` + `EVAL.md` — 加详细矩阵 + auto-default + 阻塞
