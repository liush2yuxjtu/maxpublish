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

**谁决定发到哪些平台？** Agent（按 REFERENCE.md 的"auto-default"规则自动选高信号 manifest，再让用户确认）。

**skill 提供什么？** 知识（REFERENCE.md）、诊断（signals.sh）、自动修阻塞（fix-install / fix-credentials / fix-version）、记录（record.sh）、公告（announce.sh）、错误→修复建议。不替你 publish。

## 5 步工作流

```
1. ASSESS   signals.sh → 报告 manifests/clis/envs/git
2. AUTO-DEFAULT  按 REFERENCE.md §-1 把高信号 manifest 直接映射成平台候选
3. CONFIRM  首次跑：列候选 + "全部发吗？[y/N]"；MAXPUBLISH_CI=1 跳过
4. FIX      调 fix-* 助手修阻塞（缺 CLI、缺凭证、版本没 bump）
5. PUBLISH  agent 用 bash 调各注册表的官方 CLI
6. RECORD   record.sh 把每条结果写到 index.jsonl
7. ANNOUNCE announce.sh 出 release notes 一页通
```

## 自动默认平台（auto-default 规则）

| 检测到 | 默认候选 | 备注 |
|---|---|---|
| `package.json` 且 `private != true` | **npm** | 信号强，默认 |
| `package.json` 含 `engines.vscode` | **vsce** | 跟 npm 一起 |
| `pyproject.toml` / `setup.py` | **pypi** | |
| `Cargo.toml` 且 `publish=true` | **cargo** | |
| `*.gemspec` | **gem** | |
| `Dockerfile` | **docker** | |
| git repo + gh authed | **gh-release** | 信号模糊，问用户 |
| `.github/workflows/*` 引用 `ghcr.io` / `packages:write` | **ghcr** | 信号模糊 |
| `Formula/*.rb` + `homebrew-tap` remote | **brew** | 信号模糊 |
| `manifest.json` (webextension) 含 `browser_specific_settings.gecko` | **amo** | |
| `manifest.json` (webextension) 无 gecko | **chrome-web-store** | MV3 也能上 edge |
| `manifest.json` (webextension) 含 `browser_specific_settings.edge` | **edge-addons** | |

**信号模糊的（ghcr/brew/amo/chrome-web-store/edge-addons）第一次跑必问**，记到 `~/.agents/maxpublish/decisions.jsonl`，下次同项目直接用。

## CI 模式

设 `MAXPUBLISH_CI=1`：

- 跳过所有 `read -p` 提示
- 跳过首次引导
- 直接按 auto-default + decisions.jsonl 跑
- 失败立刻 exit 非 0

```
# 本地
MAXPUBLISH_CI=1 maxpublish           # GH Actions 用
```

## 首次引导

第一次跑某个项目时（没在 `decisions.jsonl` 见过）：

```
▸ /maxpublish · 2026-06-04
  cwd: /Users/me/proj

── detected ──
  npm      ✓ (package.json)
  gh-release  ? (git repo + gh authed)

about to publish: npm, gh-release
publish all? [Y/n]
```

## User Wants, Tools, Outputs

| # | User wants | Tool | Output |
|---|---|---|---|
| 1 | 这项目能发到哪？ | `signals.sh` | manifests / clis / envs / git |
| 2 | 默认选哪几个？ | auto-default 规则 | 候选平台列表 |
| 3 | 缺 CLI 怎么装？ | `fix-install.sh` | 装好 / dry-run 命令 |
| 4 | 缺 token 怎么办？ | `fix-credentials.sh` | 缺哪个 env、获取链接 |
| 5 | 失败怎么修？ | `fix-suggest.sh` | 错误→修复映射 |
| 6 | 怎么 bump 版本？ | `fix-version.sh` | 改好的 manifest + diff |
| 7 | 怎么真发？ | agent bash | 真实推送（agent 控制命令） |
| 8 | 怎么记？ | `record.sh` | index.jsonl 一行 |
| 9 | 怎么出 release notes？ | `announce.sh` | gist + htmlpreview 一页通 |

## Non-Negotiables

- signals.sh 只读、不会改文件
- fix-credentials.sh 永远不写 token——只报告
- fix-install.sh 和 fix-version.sh **会改文件系统**——默认实跑；`--dry-run` 预览
- fix-install.sh 默认**自动装**（已 `--dry-run` 预览过）；`MAXPUBLISH_FORCE_PROMPT=1` 才每次问
- 真 publish 由 agent 用 bash 调官方 CLI——skill 不替你发
- 错误信息**后面跟修复建议**（fix-suggest.sh 映射表）
- 不改 CHANGELOG、不动 git
- 不加 `.maxpublish.json` 配置——auto-default + decisions.jsonl 足够
- 不加多项目记忆——decisions.jsonl 是单项目决定缓存（路径哈希键），不"记住"全局
- 不加 `init` / `pack` 子命令——纯诊断+修复+记录
- rollback 仍只对 gh-release 自动实现（其它给操作清单）

## 目录

```
maxpublish/
├── SKILL.md           # 本文件，契约
├── REFERENCE.md       # 平台矩阵 + auto-default 规则
├── EVAL.md            # 阻塞目录 + 修法助手调用 + 错误→修复映射
└── scripts/
    ├── signals.sh          # ASSESS：项目信号
    ├── fix-install.sh      # FIX：装缺失 CLI
    ├── fix-credentials.sh  # FIX：检查凭证
    ├── fix-version.sh      # FIX：bump manifest 版本号
    ├── fix-suggest.sh      # FIX：错误→修复建议
    ├── record.sh           # RECORD：写 index.jsonl
    └── announce.sh         # ANNOUNCE：调 talk-html 出 release notes
```

无 `publish.sh`、无 `targets/`、无 work 脚本。PUBLISH 这一步 agent 用 bash 自己写命令。

## 加新平台（agent 手动）

5 个文件要改（无 `new-platform` 脚手架）：

1. `scripts/signals.sh` — 加 manifest 探测
2. `scripts/fix-install.sh` — 加 CLI 安装 case（如有）
3. `scripts/fix-credentials.sh` — 加凭证检查 case
4. `REFERENCE.md` — 加一节详细 + 更新 auto-default 规则表
5. `EVAL.md` — 加阻塞行 + 错误→修复映射行

## See also

- [REFERENCE.md](REFERENCE.md) — 平台矩阵 + auto-default
- [EVAL.md](EVAL.md) — 阻塞目录 + 错误→修复
