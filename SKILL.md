---
name: maxpublish
description: >-
  Multi-registry publish with one-shot HITL decision panel. The skill detects
  the project (npm / vsce / pypi / cargo / gem / docker / ghcr / AMO / Chrome
  Web Store / Edge Add-ons / Homebrew / GitHub Release), shows ALL blockers
  + OAuth notes + draft candidates on a single editorial-style HTML page, and
  copies a single ready-to-paste prompt back to Claude Code. Agent (or user)
  decides platforms; skill fixes blockers (installs CLIs, prompts for creds,
  bumps version), records results, and runs official CLIs in parallel.
  ALWAYS use this skill when the user wants to ship a release to one or more
  package registries, mentions publishing / 发版 / 推到注册表 / release v…,
  asks "can I publish this?", or says /maxpublish — even if they only mention
  one registry. Do NOT use for CI-only publishing (release-please etc.),
  single-platform quick publish (just run npm publish directly), or QA/bug
  reports.
---

# /maxpublish — one-shot multi-registry publish with single HITL

**目标：发到尽可能多的平台。** 一个 HTML 页搞定所有决策——signals + blockers + OAuth + draft 候选 + 4 按钮，copy 一次粘贴回 Claude Code。

## 入口

```bash
# 默认：检测 + 打开 HITL HTML + 弹出浏览器
/maxpublish

# CI：跳过 HTML，inline 输出
MAXPUBLISH_CI=1 /maxpublish

# 只看评估（不开页）
/maxpublish --eval
```

## 5 步流程（**单 HITL**）

```
1. ASSESS
   scripts/signals.sh --json
   → 候选清单（auto-default high-confidence + 列 medium-confidence）
   → envs / clis / git 状态
   → 当前版本号

2. OPEN HITL  ← 唯一的人类介入点
   scripts/hitl-html.sh
   → 一个 HTML 页（含 4 段）：
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

4. RECORD  scripts/record.sh <plat> <ver> ok|failed "<url|err>"

5. ANNOUNCE  scripts/announce.sh <ver> <name> '<results-json>' → talk-html
```

## auto-default 规则

| 检测到 | 候选 | confidence |
|---|---|---|
| `package.json` 非 private | **npm** | high |
| `package.json` 含 `engines.vscode` | **vsce** | high |
| `pyproject.toml` / `setup.py` | **pypi** | high |
| `Cargo.toml` 且 `publish=true` | **cargo** | high |
| `*.gemspec` | **gem** | high |
| `Dockerfile` | **docker** | high |
| `manifest.json` 含 gecko | **amo** | high |
| `manifest.json` (MV3, no gecko) | **chrome-web-store** | high |
| `manifest.json` 含 edge key | **edge-addons** | high |
| git repo + gh authed | **gh-release** | medium |
| `.github/workflows/*` 引用 ghcr | **ghcr** | medium |
| `Formula/*.rb` + `homebrew-tap` remote | **brew** | medium |

high → auto-default（除非 HITL 页用户去掉）· medium → HITL 页默认勾选但用户可去

## User Wants, Tools, Outputs

| # | User wants | Tool | Output |
|---|---|---|---|
| 1 | 这项目能发到哪？ | `signals.sh` | manifests / clis / envs / git |
| 2 | 缺什么？ | `hitl-html.sh` | HTML：signals + blockers + OAuth + draft + 4 按钮 |
| 3 | OAuth 怎么办？ | HITL §3 提示 | 用户用已有 CLI / skill 走，skill 不开浏览器、不用服务端 |
| 4 | 真发哪几个？ | HITL §4 候选 | 4 按钮 copy 一个 prompt 粘回 |
| 5 | 怎么真发？ | agent bash 并发 | 每平台 `&` 子 shell + `tee logs/<plat>.<ver>.log` |
| 6 | 失败怎么修？ | `fix-suggest.sh` | 错误→修复映射（10 平台） |
| 7 | 怎么记？ | `record.sh` | index.jsonl 一行 |
| 8 | 怎么出 release notes？ | `announce.sh` | gist + htmlpreview 一页通 |

## Non-Negotiables

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
├── REFERENCE.md        13 平台详细矩阵（命令/凭证/回滚/坑）
├── EVAL.md             阻塞目录 + 修法助手调用 + 错误→修复映射
├── package.json        npm-publishable 形态
├── evals/
│   └── evals.json      trigger eval queries
└── scripts/
    ├── bin/maxpublish.js     npm-bin wrapper
    ├── signals.sh            ASSESS：项目信号 + auto-default
    ├── hitl-html.sh          ⭐ 唯一 HITL 入口
    ├── fix-install.sh        装缺失 CLI
    ├── fix-credentials.sh    检查凭证
    ├── fix-version.sh        bump manifest 版本
    ├── fix-suggest.sh        错误→修复建议（10 平台）
    ├── record.sh             写 index.jsonl
    └── announce.sh           调 talk-html 出 release notes
```

（`blocker-html.sh` / `draft-html.sh` 保留为 legacy 入口；新流程走 `hitl-html.sh`）

## 加新平台

5 个文件要改：

1. `scripts/signals.sh` — 加 manifest 探测
2. `scripts/fix-install.sh` — 加 CLI 安装 case
3. `scripts/fix-credentials.sh` — 加凭证检查
4. `scripts/hitl-html.sh` — `PLATFORMS` / `SIG_MAP` / `OAUTH_PLATFORMS` 加平台
5. `REFERENCE.md` — 加详细矩阵 + 更新 auto-default 表
6. `EVAL.md` — 加阻塞行 + 错误→修复映射
