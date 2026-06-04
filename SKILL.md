---
name: maxpublish
description: >-
  Agent-driven multi-registry publish with auto-fix helpers. The agent (or user)
  decides which platforms to ship to based on project signals; the skill provides
  the knowledge, the fixers (install missing CLIs, prompt for credentials, bump
  version), the record helper, and the release-notes publisher. No hardcoded
  target list — agent reads signals.sh, picks platforms, runs official CLIs.
  Use when user says "/maxpublish", "publish to registries", "max publish",
  "release v…", "发版", "推到注册表", "npm + vsce + pypi 一起发", or wants the
  agent to detect the project, fix blockers, and ship to chosen platforms in
  one workflow.
---

# /maxpublish — agent-driven publish, skill-assisted

**目标：发到尽可能多的平台。** 阻塞 → pop open HTML 让用户修。OAuth 不用服务端、用用户已有的 skill/CLI。

## FINAL STEP（用户拍板的流程）

```
/maxpublish
   │
   ├── 1. signals.sh --guide
   │     → 候选清单（high confidence auto-default，medium confidence 列出来）
   │
   ├── 2. blocker-html.sh
   │     → 列出所有缺 env（npm 缺 NODE_AUTH_TOKEN、vsce 缺 VSCE_PAT ...）
   │     → 每行：platform + env 名 + URL + token 输入框 + copy export 按钮
   │     → 底部按钮：📋 copy prompt back to claude code / ⏭ skip
   │     → 用户填 token → copy 一个 prompt 粘到 claude code
   │     → 用户说"用 CWS 需要 OAuth dance，我用 chrome-webstore-upload-cli 走"
   │     → 用户自己找 skill / CLI / 工具（不让 skill 开浏览器 OAuth）
   │
   ├── 3. fix-credentials.sh <platform>    （可选；再确认一次）
   │     → 重跑检测；可能仍有 block
   │
   ├── 4. draft-html.sh
   │     → publish draft 页：
   │         - 候选清单（auto-default + medium）
   │         - "Add more platforms" 复选框（AMO / CWS / Edge / brew / ghcr / cargo / gem）
   │         - 4 按钮：
   │             ✓ publish all          → copy "/maxpublish approve: publish vX to: A, B, C"
   │             ✓ publish high-only    → copy "/maxpublish approve: publish vX to: A (high only)"
   │             + publish with extras  → copy "/maxpublish approve: ... A+B, added X"
   │             ✗ deny publish         → copy "/maxpublish deny"
   │     → 用户选 → copy 粘回 claude code
   │
   ├── 5. PUBLISH  (agent bash)
   │     - 每个平台单独的子 shell `&` 并发跑（不混日志）
   │     - 每个子 shell 输出 `tee` 到单独 log 文件：`logs/<plat>.<ver>.log`
   │     - 失败不阻塞其他
   │     - 出错时 fix-suggest.sh <plat> "<error excerpt>" 给修复提示
   │
   ├── 6. RECORD   record.sh <plat> <ver> ok|failed "<url or err>" 每个一条
   │
   ├── 7. ANNOUNCE announce.sh <ver> <name> '<results-json>' → talk-html
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

high → auto-default（除非 draft 页用户去掉）
medium → draft 页默认勾选但用户可去掉

## CI 模式

`MAXPUBLISH_CI=1`：

- 跳过所有 HTML 弹窗，直接打印 blocker 列表和 draft 候选
- 不 `open` 浏览器
- 不 prompt
- 失败立即 exit 非 0

## User Wants, Tools, Outputs

| # | User wants | Tool | Output |
|---|---|---|---|
| 1 | 这项目能发到哪？ | `signals.sh` | manifests / clis / envs / git |
| 2 | 缺什么？ | `blocker-html.sh` | HTML：每平台 + env + URL + input + copy |
| 3 | OAuth 怎么办？ | 不开浏览器；用户走已有 skill / CLI（自己找） | — |
| 4 | 候选有哪些？ | `draft-html.sh` | HTML：候选 + 4 按钮 → copy 提示 |
| 5 | 怎么真发？ | agent bash 并发子 shell | 真实推送 + 每平台单独 log |
| 6 | 失败怎么修？ | `fix-suggest.sh` | 错误→修复映射 |
| 7 | 怎么记？ | `record.sh` | index.jsonl 一行 |
| 8 | 怎么出 release notes？ | `announce.sh` | gist + htmlpreview |

## Non-Negotiables

- signals.sh 只读、不会改文件
- fix-credentials.sh 永远不写 token——只报告
- fix-install.sh 直接装（不二次确认）
- 真 publish 由 agent 用 bash 调官方 CLI；skill 不替你发
- 错误信息**后面跟 fix-suggest.sh 的修复建议**（agent 自己读 stack trace，不落盘）
- **OAuth 不开浏览器 / 不用服务端**——用户用已有 skill 或 CLI 走
- 多平台并发推（不混日志）——每个子 shell 输出 `tee` 到 `<plat>.<ver>.log`
- 失败不阻塞其他；记录里标 `failed`，继续
- 不加 `.maxpublish.json` 配置；不加 `init` / `pack`；不加 duration_ms
- 英文输出；不加 skill 版本字段

## 目录

```
maxpublish/
├── SKILL.md            契约：FINAL STEP 流程
├── REFERENCE.md        13 平台详细矩阵
├── EVAL.md             阻塞目录 + 修法助手调用
├── package.json        npm-publishable 形态
├── scripts/
│   ├── bin/maxpublish.js     npm-bin wrapper
│   ├── signals.sh            ASSESS：项目信号 + auto-default
│   ├── blocker-html.sh       缺 env HTML（fix 助手）
│   ├── draft-html.sh         publish draft HTML（4 按钮决策）
│   ├── fix-install.sh        装缺失 CLI
│   ├── fix-credentials.sh    检查凭证
│   ├── fix-version.sh        bump manifest 版本
│   ├── fix-suggest.sh        错误→修复建议（10 平台）
│   ├── record.sh             写 index.jsonl
│   └── announce.sh           调 talk-html 出 release notes
```

## 加新平台

5 个文件要改：

1. `scripts/signals.sh` — 加 manifest 探测
2. `scripts/fix-install.sh` — 加 CLI 安装 case
3. `scripts/fix-credentials.sh` — 加凭证检查
4. `scripts/blocker-html.sh` — 在 PLATFORMS_JSON 加平台
5. `REFERENCE.md` — 加详细矩阵 + 更新 auto-default 表
6. `EVAL.md` — 加阻塞行 + 错误→修复映射
