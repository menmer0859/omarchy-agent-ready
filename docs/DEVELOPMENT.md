---
title: Agent Ready 开发与发布指南
type: development
date: 2026-11-13
status: release-preparation
canonical_path: /home/eclipse/omarchy-agent-ready-release/docs/DEVELOPMENT.md
---

# Agent Ready — 开发与发布指南

## TLDR / 发布现状更正

本文面向维护 CLI、QML 插件与发布流程的开发者：先阅读本节，再按下文原始 19 节理解架构、接口与踩坑记录。发布整理基准为 **1.1.0**，作者为 **menmer0859**，仓库为 https://github.com/menmer0859/omarchy-agent-ready （克隆地址 https://github.com/menmer0859/omarchy-agent-ready.git）；插件 id **保持 `eclipse.agent-ready`**，不随作者名更改。

**发布默认 `agents.allow` 改为 `[]`**，不是历史作者机器的 13 名清单。空列表只表示没有配置自动检测的进程名字，不会禁用 inhibitor、锁屏、DPMS 或其它电源行为；用户必须根据自己的机器配置实际进程名。检测按进程名精确匹配、统计名字种类而非 PID 数；由 node/python 启动且进程名仍是解释器的 Agent 无法识别，可由 hook 通过 `digest set` 提供精确 `agents` 数组。不要为了计数把所有 node/python 进程当成 Agent。**空名单也意味着没有 Agent 的 freeze 白名单保护**。实验性 freeze 默认关闭；启用前必须先配置自己的白名单并核查冻结规则。`set` 只解析 bool/int/string，不支持 JSON 数组，不能用它设置 `agents.allow`；请编辑配置或使用 `/home/eclipse/omarchy-agent-ready-release/docs/CLI.md` 中的 jq 临时文件更新示例。

## 事实与证据 / 阅读约定

- **发布整理基准**：上述作者、URL、版本与空白名单是本次发布要求；对应核对入口为 `/home/eclipse/omarchy-agent-ready-release/manifest.json`、`/home/eclipse/omarchy-agent-ready-release/LICENSE`、`/home/eclipse/omarchy-agent-ready-release/config/config.json` 及 `/home/eclipse/omarchy-agent-ready-release/bin/omarchy-agent-ready`。本次仅整理文档，不据此宣称已完成跨机器或真实电源验收。
- **历史已记录事实**：以下 19 节完整迁移自原 `/home/eclipse/omarchy-agent-ready-release/HANDOFF.md`，保留原始验收结论、待办、行数和作者机器经验；它们是历史快照，不是重新验证的发布现状。原开头“已人工验收”与第 19 节“最近一轮待人工验收”均保留，须按各自记录范围理解。
- **路径约定**：仓库内参考基准为绝对路径 `/home/eclipse/omarchy-agent-ready-release`。用户安装路径使用 `$HOME/...`，其中 `$HOME` 是安装者自己的绝对 home（不是固定 `/home/eclipse`）；文中的命令在 shell 内展开它。第 19 节专列的 `/home/eclipse/...` 是作者机器历史开发位置，不应复制为其他用户的安装位置。
- **当前风险 / 待验证**：截图、Omarchy 兼容范围、机器电源与音频行为及最近一轮人工验收仍需按第 12、16、19 节核对；历史“无已知阻断性缺陷”不是发布质量保证。第 18 节未实现功能与重启状态对账限制仍作为开放问题保留。

## 步骤 / 开发者入口

1. 修改实现前先读第 10、11 节的标识约束和回归红线。
2. 核对第 12 节清单时，作者、URL、版本、白名单以本文发布更正为准；历史值仅作追溯。
3. 第 13、16 节是供维护者选择执行的发布与验证步骤，并非本次已执行的命令。涉及 arm、preview、电源、安装/卸载或真实 state 的步骤必须先获授权，并使用隔离环境。

## 路径索引

- CLI 与配置说明：`/home/eclipse/omarchy-agent-ready-release/docs/CLI.md`。
- 插件内部说明：`/home/eclipse/omarchy-agent-ready-release/docs/PLUGIN.md`。
- 用户入口：`/home/eclipse/omarchy-agent-ready-release/README.md`。
- 原交接文档已迁移至本文；原入口 `/home/eclipse/omarchy-agent-ready-release/HANDOFF.md` 删除，不再作为维护入口。

---

## 原始交接记录（历史快照，保留全部 19 节）

### 原标题：Agent Ready — 项目交接文档（Handoff）

> **给接手本文的 Agent**
> 你的任务：把这个项目整理成 GitHub 仓库并发布，让任何 Omarchy 用户能装得上、用得了。
> 本文是唯一需要读的文档：**设计、架构、全部代码、踩过的坑、发布步骤、待办**都在这里。
> 所有源码已经放在原交接文档所在的目录（`/home/eclipse/omarchy-agent-ready-release`），按可直接 `git init` 的结构组织好。
> 当前项目状态：**功能完整、已通过本机人工验收、无已知阻断性缺陷**。
>
> **30 秒摘要**
> 1. 本目录就是仓库根，`/home/eclipse/omarchy-agent-ready-release/README.md` 面向最终用户，`/home/eclipse/omarchy-agent-ready-release/docs` 是完整技术文档，本文面向你。
> 2. `/home/eclipse/omarchy-agent-ready-release/install.sh` / `/home/eclipse/omarchy-agent-ready-release/uninstall.sh` 已写好并在隔离 HOME 里跑通（幂等、不覆盖用户配置）。
> 3. 发布前**必须**处理第 12 节「发布前清单」里的 6 项（作者信息、仓库 URL、agent 白名单、截图等）。
> 4. 不要改第 10 节列出的硬编码标识，除非同步改所有引用点。
> 5. 全程**不要**修改 `/usr/share/omarchy` 下的任何系统文件——这是项目的核心设计约束。

---

## 目录

1. [项目是什么 / 为什么做](#1-项目是什么--为什么做)
2. [架构总览](#2-架构总览)
3. [完整文件清单](#3-完整文件清单)
4. [状态机与运行时数据](#4-状态机与运行时数据)
5. [配置全表](#5-配置全表)
6. [CLI 命令全表](#6-cli-命令全表)
7. [status-json 契约](#7-status-json-契约)
8. [QML 组件结构](#8-qml-组件结构)
9. [i18n 机制](#9-i18n-机制)
10. [硬编码标识与改名约束](#10-硬编码标识与改名约束)
11. [关键设计决策与踩过的坑](#11-关键设计决策与踩过的坑)
12. [发布前清单](#12-发布前清单)
13. [发布到 GitHub 的步骤](#13-发布到-github-的步骤)
14. [外部依赖与 Omarchy 集成点](#14-外部依赖与-omarchy-集成点)
15. [安装 / 卸载方案](#15-安装--卸载方案)
16. [验证清单](#16-验证清单)
17. [已知限制与机器特定假设](#17-已知限制与机器特定假设)
18. [未完成 / 待办](#18-未完成--待办)
19. [附录：演进历史与验收记录](#19-附录演进历史与验收记录)

---

## 1. 项目是什么 / 为什么做

### 起因

Omarchy 自带一个 **Stay Awake** 开关（`/usr/share/omarchy/shell/bar/indicators/StayAwake.qml` + `/usr/share/omarchy/shell/plugins/services/idle/Service.qml`），实现是往
`$HOME/.local/state/omarchy/indicators/stay-awake` 写一个 marker file，idle 服务热加载它来跳过 150 s 屏保 / 300 s 自动锁屏。

它只有两态：

| 态 | 行为 |
|---|---|
| Stay Awake | 不屏保、不锁屏，**但也没有阻止系统 suspend** |
| Allow Idle Lock | 正常屏保 / 锁屏 / 休眠 |

用户的需求是加**第三态「PI Agent Ready」**：机器上跑着一批后台编码 Agent（pi / Cindy / Codex / magpie / OpenCode / Hermes …），
希望**离开电脑后 Agent 继续跑**，但把非必要的东西降到低功耗——显示器、键盘背光、音频、电源档位——
并且回来时能立刻看到一个「值班摘要」。

### 关键调研结论（决定了整个架构）

1. Stay Awake marker **只控制 idle/screensaver**，不阻止 suspend。要真正"合盖也不睡"，必须自己持有
   `systemd-inhibit --what=sleep:idle --mode=block`。
2. 系统里已有 magpie 的 inhibitor（"Agents are working through magpie"）、`pi-agent-home`、
   `eclipse.agents` 插件等基础设施；但都是各自独立机制，**没有统一的电源场景编排**。
3. `/usr/share/omarchy/shell/plugins/...` 是系统文件，升级会被覆盖。**结论：不改系统文件，纯用户态实现**。
4. Omarchy 支持用户插件：`$HOME/.config/omarchy/plugins/<id>/manifest.json` + `bar-widget` 入口，
   通过 `$HOME/.config/omarchy/shell.json` 的 `bar.layout` 注册。这是 UI 的正确落点。

### 最终形态

一个 **bash CLI（唯一状态权威）** + 一个 **Quickshell/QML bar-widget 插件（纯渲染与调度）** + 两个 **共享 i18n catalog**。
CLI 复用 Omarchy 自己的 Stay Awake 开关和 `omarchy-*` 辅助命令，自己持有 systemd-inhibit。
不 fork、不 patch 任何 Omarchy 组件。

### 目标用户

Omarchy 桌面用户，尤其是跑后台编码 Agent / 长时间任务、希望"人走机不睡、屏幕不烧、回来有交代"的人。
**不是**通用 Linux 电源管理工具（见 [第 17 节](#17-已知限制与机器特定假设)）。

---

## 2. 架构总览

```
┌────────────────────────────── 用户交互 ──────────────────────────────┐
│  状态栏图标 (WidgetButton)                                            │
│    左键 → toggle / 右键 → 设置面板 / 中键 → 同右键                     │
└───────────────┬──────────────────────────────────────────────────────┘
                │ 全部通过 argv-vector Quickshell.Io.Process 调用
                │ （串行命令队列，绝不用 execDetached / bash -lc）
                ▼
┌──────────────────────── CLI: $HOME/.local/bin/omarchy-agent-ready ───────┐
│  • 唯一状态权威：state.json / pending.json / digest.json / history.json│
│  • 电源动作：systemd-inhibit / Stay Awake / powerprofilesctl / DPMS /  │
│    pactl / 键盘背光 / 可选 SIGSTOP 冻结                                │
│  • 语言解析（唯一权威）→ status-json.language                          │
│  • 通知文案 t() 从共享 i18n catalog 读取                              │
└───────────────┬──────────────────────────────────────────────────────┘
                │ status-json（每 0.5–5 s 轮询一次，纯 JSON）
                ▼
┌──────────────────────── QML bar-widget 插件 ─────────────────────────┐
│  • 三张 face 共用一个 PopupCard：arming / digest / settings           │
│  • 拥有倒计时（每秒轮询，到点调 _arm-fire <token>）                    │
│  • 拥有独立的 IdleMonitor（auto-arm）                                  │
│  • 2 s reconcile tick（自愈，带速率限制）                              │
│  • PluginI18n（可写 language）驱动全部 UI 文案                        │
└───────────────────────────────────────────────────────────────────────┘

共享资源：/home/eclipse/omarchy-agent-ready-release/i18n/{en,zh-CN}.json —— CLI 通知与 QML UI 的单一文案源
```

### 三条设计原则

1. **CLI 是唯一状态与语言权威**。Widget 不自己算状态、不自己解析语言，只消费 `status-json`。
   所以「面板中文、通知英文」这类不一致不可能发生。
2. **Widget 不 spawn 长生命周期子进程**。早期用 `Quickshell.execDetached` + `bash -lc` 会在
   Surface 机器上产生可听见的 codec pop（见 [11.2](#112-为什么全部走-argv-vector-process)）。
3. **状态全部落在文件里**，CLI 每次调用都是无状态进程；`flock` 保证并发安全（双显示器会有两个
   widget 实例同时发同一条解锁命令）。

### 进入 / 离开的执行顺序

`do_on()`：
1. 快照现场（Stay Awake 是否已存在、电源档、sink、静音态、亮度）
2. `systemd-inhibit` 起 `sleep infinity`（带独特 argv[0] 便于存活检测）
3. 联动 Stay Awake（`omarchy-toggle-idle stay-awake`，失败则直接写 marker）
4. 电源档 → `balanced`（可配）
5. 音频静音 / 挂起 sink（默认都关）
6. 可选冻结非 agent 进程
7. 键盘背光关、可选亮度调暗
8. **锁屏 → 一次性 DPMS off**（锁屏失败则完整回滚到 off，并排程有限重试）
9. 跑 `$HOME/.config/omarchy/agent-ready/enter.d/` hooks、`refresh_digest`、发通知

`do_off()`：反向恢复（先亮屏 → 恢复亮度/键盘背光 → 音频 → 电源档 → unfreeze → 停 inhibitor →
恢复 Stay Awake），保存 `watch_since` / `trigger`，刷新当前 digest，**追加一条 history 记录**，
跑 `$HOME/.config/omarchy/agent-ready/leave.d/` hooks，发通知。

---

## 3. 完整文件清单

仓库根（不是本文所在的 docs 目录）= `/home/eclipse/omarchy-agent-ready-release`。**根目录同时就是 Omarchy 插件目录**
（`/home/eclipse/omarchy-agent-ready-release/manifest.json` + `/home/eclipse/omarchy-agent-ready-release/Widget.qml` + `/home/eclipse/omarchy-agent-ready-release/PluginI18n.qml` + `/home/eclipse/omarchy-agent-ready-release/i18n` 在根，这样
`omarchy plugin add <url>` 能直接把整个仓库当插件装）。

| 仓库内路径 | 行数 | 职责 | 安装到 |
|---|---:|---|---|
| `/home/eclipse/omarchy-agent-ready-release/bin/omarchy-agent-ready` | 1399 | **核心 CLI**（bash）：状态机、电源动作、通知、digest/history、语言解析、doctor | `$HOME/.local/bin/omarchy-agent-ready` (0755) |
| `/home/eclipse/omarchy-agent-ready-release/Widget.qml` | 1152 | **bar-widget 插件**：三张 face、倒计时、IdleMonitor、reconcile、命令队列、ShellIpc | `$HOME/.config/omarchy/plugins/eclipse.agent-ready/Widget.qml` |
| `/home/eclipse/omarchy-agent-ready-release/PluginI18n.qml` | 81 | 可写 `language` 的 `Commons.Translations` 孪生组件 | `$HOME/.config/omarchy/plugins/eclipse.agent-ready/PluginI18n.qml` |
| `/home/eclipse/omarchy-agent-ready-release/manifest.json` | 36 | Omarchy 插件清单（`schemaVersion:1`, `kinds:["bar-widget"]`, id, 版本, `panelWidth` schema） | `$HOME/.config/omarchy/plugins/eclipse.agent-ready/manifest.json` |
| `/home/eclipse/omarchy-agent-ready-release/i18n/en.json` | 133 | 英文 catalog（127 keys：UI + 通知 + 摘要 + 语言） | `$HOME/.config/omarchy/plugins/eclipse.agent-ready/i18n/en.json` |
| `/home/eclipse/omarchy-agent-ready-release/i18n/zh-CN.json` | 133 | 简体中文 catalog（与 en 严格同 key） | `$HOME/.config/omarchy/plugins/eclipse.agent-ready/i18n/zh-CN.json` |
| `/home/eclipse/omarchy-agent-ready-release/config/config.json` | 46 | **默认配置模板**（`language:auto`, `digest.enabled:true`, `labels:{}`） | `$HOME/.config/omarchy/agent-ready/config.json`（仅首次） |
| `/home/eclipse/omarchy-agent-ready-release/config/enter.d/README.md` | 19 | hook 约定说明 | `$HOME/.config/omarchy/agent-ready/enter.d/README.md` |
| `/home/eclipse/omarchy-agent-ready-release/config/enter.d/example-digest.sh.disabled` | 23 | 示例：进入时写 digest（默认禁用） | `$HOME/.config/omarchy/agent-ready/enter.d/example-digest.sh.disabled` |
| `/home/eclipse/omarchy-agent-ready-release/config/leave.d/README.md` | 19 | hook 约定说明 | `$HOME/.config/omarchy/agent-ready/leave.d/README.md` |
| `/home/eclipse/omarchy-agent-ready-release/config/leave.d/example-bark.sh.disabled` | 23 | 示例：离开时推 Bark（默认禁用） | `$HOME/.config/omarchy/agent-ready/leave.d/example-bark.sh.disabled` |
| `/home/eclipse/omarchy-agent-ready-release/docs/CLI.md` | 409 | **完整 CLI/配置文档**（原 `$HOME/.config/omarchy/agent-ready/README.md`，仅修正了仓库内交叉引用） | 文档，不安装 |
| `/home/eclipse/omarchy-agent-ready-release/docs/PLUGIN.md` | 209 | **完整 widget 内部文档**（原插件 README，仅修正了仓库内交叉引用） | 文档，不安装 |
| `/home/eclipse/omarchy-agent-ready-release/README.md` | 138 | 面向最终用户：功能、要求、安装、用法、配置摘要、卸载、限制 | 文档 |
| `/home/eclipse/omarchy-agent-ready-release/docs/DEVELOPMENT.md` | 本文 | 开发指南（由原 HANDOFF.md 迁移） | 文档 |
| `/home/eclipse/omarchy-agent-ready-release/install.sh` | ~145 | 一键安装（幂等、备份 shell.json、doctor、重启） | 文档/工具 |
| `/home/eclipse/omarchy-agent-ready-release/uninstall.sh` | ~75 | 卸载（默认保留 config/history，`--purge` 全删） | 文档/工具 |
| `/home/eclipse/omarchy-agent-ready-release/LICENSE` | 21 | MIT | 文档 |
| `/home/eclipse/omarchy-agent-ready-release/.gitignore` | 9 | 排除运行时 state/log/bak | 文档 |

**不发布（运行时生成，在 `$HOME/.local/state/omarchy/agent-ready/`）**：
`$HOME/.local/state/omarchy/agent-ready/state.json`, `$HOME/.local/state/omarchy/agent-ready/pending.json`, `$HOME/.local/state/omarchy/agent-ready/notify.id`, `$HOME/.local/state/omarchy/agent-ready/digest.json`, `$HOME/.local/state/omarchy/agent-ready/history.json`, `$HOME/.local/state/omarchy/agent-ready/inhibit.pid`,
`$HOME/.local/state/omarchy/agent-ready/frozen.pids`, `$HOME/.local/state/omarchy/agent-ready/lock`, `$HOME/.local/state/omarchy/agent-ready/log`。安装脚本会 `mkdir -p` 这个目录，但**不写任何初始数据**。

> 备注：`/home/eclipse/omarchy-agent-ready-release/bin/omarchy-agent-ready` 顶部定义了 `AUTO_STATE_FILE="$STATE_DIR/auto.json"`，
> 但全文没有使用，是早期设计残留的**死常量**；可安全删除（见 [12 节](#12-发布前清单) 可选项）。

---

## 4. 状态机与运行时数据

### phase（CLI `$HOME/.local/state/omarchy/agent-ready/state.json` 字段，widget 读 `status-json.phase`）

```
off → arming → applying → active → restoring → off
```

中间态的作用是防止锁屏 / DPMS 动作在飞行途中被重复点击。
`do_on` 是**可重入**的：已 enabled 时再调 `on` 只修复丢失的 inhibitor，不会二次锁屏。

### 文件契约

| 文件 | 内容 |
|---|---|
| `$HOME/.local/state/omarchy/agent-ready/state.json` | `enabled, since, snapshot, phase` + 可选 `trigger, monitorIds, previewActive, previewUntil, healthLockFailed, retryAt, retryCount, lastOffAt` |
| `$HOME/.local/state/omarchy/agent-ready/pending.json` | 倒计时：`token, until, delay, startedAt, autoTriggered, preview`（token 防失效/重复 fire） |
| `$HOME/.local/state/omarchy/agent-ready/notify.id` | 桌面通知 id，取消时用来替换成「已取消」 |
| `$HOME/.local/state/omarchy/agent-ready/digest.json` | 当前/上一次值守：内置 `agentsOnline, uptimeMin, lastEvent` + 外部 `completed, failed, pending, note, agents` |
| `$HOME/.local/state/omarchy/agent-ready/history.json` | **全部已完成值守**（数组，最新在最后，上限 200 条） |
| `$HOME/.local/state/omarchy/agent-ready/inhibit.pid` | systemd-inhibit 子进程 pid |
| `$HOME/.local/state/omarchy/agent-ready/frozen.pids` | 被 SIGSTOP 的 pid 列表（仅 freeze 开启时） |
| `$HOME/.local/state/omarchy/agent-ready/lock` | `flock` 文件锁（`-w 3`） |
| `$HOME/.local/state/omarchy/agent-ready/log` | 带时间戳的运行日志 |

### history 记录结构（**语言无关**，UI 负责格式化/翻译）

```json
{
  "seq": 12,
  "since": "2026-11-13T10:00:00+08:00",
  "until": "2026-11-13T12:30:00+08:00",
  "durationSec": 9000,
  "trigger": "manual | auto | preview",
  "agents": ["pi", "cindy", "codex"],
  "agentsOnline": 3,
  "actions": ["inhibit", "idle", "lock", "dpms", "mute", "power", "agents"],
  "powerProfile": "balanced",
  "completed": 3, "failed": 1, "pending": ["..."], "note": "...", "lastEvent": "..."
}
```

`agents` 优先取 hook 通过 `digest set` 提供的精确数组，否则取 `agent_names()` 检测到的进程名。
`actions` 存的是 catalog key，UI 用 `strings.t("summary." + key)` 渲染——所以切换语言时历史一起重渲染。

### 锁屏失败回滚

`omarchy-system-lock` 失败 → 立即撤销 inhibitor / unfreeze / Stay Awake / 电源档 / 键盘背光，
`write_state false`，排程最多 3 次重试（`enter.retrySec`，由 widget reconcile 执行）。
**绝不留半 enabled 状态**。回滚是就地执行，不走 `do_off`（会自锁 flock）。

---

## 5. 配置全表

> **发布更正**：下表为历史配置快照；`agents.allow` 发布默认是 `[]`，旧 13 名只保留作作者机器历史记录。电源行为不依赖检测名字数量，用户须按机器配置。

`$HOME/.config/omarchy/agent-ready/config.json`，面板写入即生效（多数下次进入时生效，
`language` 与 `digest.enabled` 即时生效）。完整说明见 `/home/eclipse/omarchy-agent-ready-release/docs/CLI.md` 的 Configuration 段。

| Key | 默认 | 含义 |
|---|---|---|
| `label` | `"Agent Ready"` | 通知标题 / app-name |
| `icons.active/inactive` | `󰊚` | 状态栏字形（需 Nerd Font） |
| `notify` | `true` | 进入/退出桌面通知 |
| `arm.enabled` | `true` | `false` = 点一下立即进入，无倒计时 |
| `arm.delaySec` | `3` | 倒计时秒数（面板 3–60） |
| `arm.notify` | `false` | 准备阶段的桌面通知（默认关，用 bar 卡片） |
| `arm.allowEnterNow` | `true` | 卡片上显示「立即进入」 |
| `arm.notifyCancel` | `true` | 取消时把通知替换成「已取消」 |
| `arm.bark.*` | disabled | Bark 推送（url/title，GET query） |
| `auto.enabled` | `true` | 空闲自动进入 |
| `auto.armAfterSec` | `null` | `null` = 跟随系统；否则固定秒数 |
| `auto.cooldownSec` | `60` | 离开后冷却，防止立刻二次自动 arm |
| `auto.disarmOnInput` | `true` | 自动倒计时期间有输入即取消 |
| `auto.requireInhibitorsClear` | `true` | IdleMonitor 尊重 Wayland idle inhibitor |
| `auto.barkNotify` | `false` | 自动触发时额外推 Bark |
| `preview.countdownSec` / `.durationSec` | `3` / `20` | 「试一下」彩排 |
| `enter.retrySec` | `60` | 锁屏失败重试间隔 |
| `language` | `"auto"` | `auto` / `en` / `zh-CN`，**仅本插件** |
| `digest.enabled` | `true` | 记录历史 + 解锁自动展开摘要 + 显示按钮 |
| `labels` | `{}` | 可选：逐条覆盖通知文案（原样使用，兼容旧 `%S`/`%A`） |
| `inhibit.enabled/what/mode/why` | `true` / `sleep:idle` / `block` / … | systemd-inhibit 参数 |
| `idle.linkStayAwake` | `true` | 联动 Omarchy Stay Awake |
| `powerProfile.enabled/.profile` | `true` / `balanced` | 进入时电源档，退出恢复原档 |
| `screen.lock/.dpmsOff/.keyboardBacklightOff/.dimPercent` | `true/true/true/0` | 屏幕动作 |
| `audio.mute/.suspendSinks` | `false/false` | 静音默认关，原因见 [17 节](#17-已知限制与机器特定假设) |
| `freeze.enabled/.patterns` | `false/[]` | 实验性 SIGSTOP 非 agent 进程 |
| `agents.allow` | 历史：13 个名字；发布：`[]` | 被识别为 agent 运行时的**进程名**；**发布时必须说明这是作者机器的清单** |

### 自动进入阈值的算法（`auto_threshold()`）

`auto.armAfterSec` 为 `null` 时：

```
base      = min($HOME/.config/omarchy/shell.json idle.screensaver (默认150), idle.lock (默认300))
minimum   = arm.delaySec + 60
threshold = max(30, base - arm.delaySec - 30)
```

即保证倒计时在系统屏保启动**之前**结束。若 `base < minimum`，返回
`available:false`（面板显示「自动进入不可用」，不抢跑）。

---

## 6. CLI 命令全表

```
status | --status         Waybar 风格 JSON（legacy）
status-json               完整状态（widget 使用）
config-json               整个 config
on / enable               立即进入
off / disable             离开并恢复
toggle                    arm / 取消倒计时 / 离开（状态栏左键）
arm [seconds]             通知 + 倒计时 → 进入
auto-arm                  内部：idle monitor 触发
preview                   彩排：短倒计时 → 进入 → 定时自动恢复
reblank                   内部：显示器集合变化后重新熄屏
disarm / cancel           取消倒计时
enter-now                 跳过剩余倒计时
digest get                当前/上一次值守
digest set '<json>'       写外部 digest 字段（hooks 用）
digest history            全部值守记录（JSON）
digest clear              清空 digest + history
set <path> <value>        改一个配置值
reset-config              恢复默认 $HOME/.config/omarchy/agent-ready/config.json
doctor | check             依赖 + 计划动作（只读，不改动系统）
lang                      打印生效语言码
edit | config             用 $EDITOR 打开 config
_arm-worker / _arm-fire   内部（旧 worker 兼容 / 倒计时 fire）
-h | --help | help
```

### 环境变量覆盖（测试 / 沙盒用，正式安装不需要）

| 变量 | 作用 |
|---|---|
| `AGENT_READY_CONFIG_DIR` | 覆盖 config 目录 |
| `AGENT_READY_STATE_DIR` | 覆盖 state 目录 |
| `AGENT_READY_I18N_DIR` | 覆盖 catalog 目录 |
| `OMARCHY_LANGUAGE_FILE` | 钉死系统语言文件（优先级高于 `config.language`，**测试专用**） |

`doctor`、`set`、`reset-config`、`digest` 都是纯配置/只读操作，适合集成测试。

> **发布更正**：原句表示不执行电源动作，不表示全都只读。`set` / `reset-config` 写配置，`digest set/clear` 写或删除摘要与历史；测试必须隔离配置和 state。`set` 仅解析 bool/int/string，不支持数组，`agents.allow` 须编辑配置或用 jq 安全更新。

---

## 7. status-json 契约

Widget 完全依赖这个 JSON；**任何字段改名都要同步改 `/home/eclipse/omarchy-agent-ready-release/Widget.qml` 的 `applyState()`**。

```
enabled, pending, remainingSec, delaySec, uptimeMin, inhibitAlive,
pendingToken, locked (true|false|null), phase, autoTriggered,
language, languageMode,
preview:  { active, until },
retry:    null | { at, count, failed },
auto:     { thresholdSec, available, source, baseSec?, reason?, enabled, cooldownRemainingSec },
health:   { inhibitor, lock, dpms, audio, auto, dpmsLit, monitorsChanged },
digest:   { agentsOnline, uptimeMin, lastEvent, completed?, failed?, pending?, note?, agents? },
digestHistory: [ …history 记录… ],     // 旧 → 新，widget 反转成新 → 旧显示
config:   { …整个 $HOME/.config/omarchy/agent-ready/config.json… }
```

`health` 枚举：`inhibitor: ok|lost`、`lock: ok|unknown|failed`、
`dpms: ok|degraded`（**只在显示器集合变化时** degraded）、`audio: ok`、
`auto: ok|degraded`；`dpmsLit` 仅信息用，`monitorsChanged` 才驱动 `reblank`。

---

## 8. QML 组件结构

`BarWidget { id: root; moduleName: "eclipse.agent-ready" }`

### 顶层对象

| 对象 | 作用 |
|---|---|
| `PluginI18n { id: strings }` | 可写 `language: root.language`，加载 `/home/eclipse/omarchy-agent-ready-release/i18n/*.json` |
| `Process { id: commandProc }` | 串行 argv-vector 命令队列（`runCommand` / `drainQueue`） |
| `Process { id: stateProc }` | 跑 `status-json`，`StdioCollector.waitForEnd` → `applyState()` |
| `Timer`（轮询） | active 500 ms / arming·面板·digest 1 s / 空闲 5 s |
| `Timer { id: refreshTimer }` | 命令结束后 600 ms 刷新 |
| `Timer { id: reconcileTimer }` | 2 s 自愈 tick |
| `IdleMonitor { id: autoIdle }` | 独立 idle 源（`respectInhibitors`），到阈值调 `auto-arm` |
| `ShellIpc` | `omarchy-shell eclipse.agent-ready open\|close\|toggle` |
| `WidgetButton` | 状态栏图标（arming 时显示剩余秒数） |
| `PopupCard { id: popup }` | **一张卡，三张 face** |

### 三张 face（共用一个 `PopupCard`，保证 one-popup-at-a-time）

| face | 显示条件 | 内容 |
|---|---|---|
| `armingCard` | `showArming` | 倒计时、将要执行的动作摘要、取消 / 立即进入 |
| `digestCard` | `showDigest` | 固定 Hero + **可滚动的全部值守历史**（最新在上）+ 返回 / 重新指派 |
| `settingsFace` | `showSettings` | **固定 Hero 信息栏** + 可滚动的分区设置 |

`contentHeight` 用 `popup.fittedContentHeight(...)`：
arming 用 `armingCard.implicitHeight`；digest 用
`Math.min(digestCard.desiredHeight, Style.space(430))`；settings 用 `Style.space(430)`。
（早期按英文行数写死 215/250/430 导致中文裁切/留白，已改为自适应 + 上限。）

### 关键函数

`cfgGet`, `armSummary`, `fmtTime`, `fmtDuration`, `actionLabels`, `digestRecordLines`,
`digestBack`, `healthSummary`, `runCommand`, `drainQueue`, `actOnce`, `setCfg`, `refresh`,
`applyState`, `triggerAutoArm`, `cancelAutoArmOnInput`, `reconcile`。

### digest 的「返回」逻辑

`digestOrigin`（`"settings"` / `"bar"`）在打开时记录：
- 设置面板的「值班摘要」按钮 → `"settings"`，**「返回」重新打开设置面板**
- 解锁自动展开 → `"bar"`，**「返回」关闭卡片回到状态栏**

`digestBack()` 实现：`digestOpen = false; if (origin === "settings") popupOpen = true`。

### settings 的固定 Hero

`settingsHero` 是 `contentRoot` 的**直接子项**（与 `ScrollView` 平级），
`settingsHeroSep` 分隔线，ScrollView 从 `settingsHeroSep.bottom` 到 `parent.bottom`。
所以向下滚动时「Agent Ready / 当前状态」这一行不动。这个做法**没有增加嵌套层**，括号数不变。

### reconcile（2 s，带 `actOnce` 速率限制）

- `health.inhibitor === "lost"` → 调 `on` 重挂（可重入）
- `health.monitorsChanged === true` → 调 `reblank`
- preview 到期 → `off`
- 锁屏失败重试到期 → `on`

---

## 9. i18n 机制

### 单一文案源

`/home/eclipse/omarchy-agent-ready-release/i18n/en.json`（base）+ `/home/eclipse/omarchy-agent-ready-release/i18n/<lang>.json`（overlay）。127 个 key，两份严格同 key。
key 分组：`tooltip.*`, `hero.*`, `button.*`, `section.*`, `field.*`, `toggle.*`,
`profile.*`, `auto.*`, `arming.*`, `digest.*`, `health.*`, `summary.*`,
`lang.*`, `notify.*`, `status.*`。

- **QML UI** → `PluginI18n.t("key")`
- **CLI 通知** → `t("key")`（bash），读同一批文件到关联数组 `declare -A _I18N`
- `%1`/`%2` 占位符，用哨兵法替换（防止参数里的 `%N` 被二次替换）

### 语言解析优先级（CLI 是唯一权威）

```
OMARCHY_LANGUAGE_FILE（测试钉死，最高）
  → config.language 是具体 code（en / zh-CN / …）
  → $HOME/.config/omarchy/language（Setup > Language；缺失即 en）
  → 区域码回落基础语言 → $HOME/.config/omarchy/plugins/eclipse.agent-ready/i18n/en.json → key 本身
```

结果通过 `status-json.language` 报给 widget，widget 直接喂给 `PluginI18n.language`
（**不在 QML 里重复解析规则**），所以 UI 与通知永远一致，切换约 0.6–1 s 生效、无需重启。
`status-json.languageMode` 报告用户的 `auto/en/zh-CN` 选择。

### 为什么自己写 `/home/eclipse/omarchy-agent-ready-release/PluginI18n.qml`

系统的 `/usr/share/omarchy/shell/Commons/Translations.qml` 里
`readonly property string language: I18n.language` 是只读且**绑死系统全局语言**，
无法让单个插件覆盖。自造版唯一区别是 `language` 可写，其余（en/base/region 三层合并、
`FileView` 热重载、缺 key 回落）逐行对齐。语言切换时 `language` 变 → `FileView.path` 变 →
重载 → 所有 `t()` 绑定重渲染。`PluginI18n` 只实现 `t()`（本项目不用复数 `tn()`），无外部 JS 依赖。

### 加一种语言

1. 复制 `/home/eclipse/omarchy-agent-ready-release/i18n/en.json` → `/home/eclipse/omarchy-agent-ready-release/i18n/<code>.json`，翻译值（保持 `%1` 完整）。
2. 在 `/home/eclipse/omarchy-agent-ready-release/Widget.qml` **Advanced 底部**的 `languageRow` 加一个 Button，`cellWidth` 除以 3 → 4。
3. 语言名用**母语自称**（`English` / `简体中文` 两种 catalog 里值相同）以便任何 UI 语言下都认得出。
4. 无需改 CLI：`lang_code()` 自动按 catalog 文件存在性回落。

---

## 10. 硬编码标识与改名约束

**发布时建议保留以下标识不变。** 若必须改名，需同步修改所有列出位置：

| 标识 | 值 | 出现位置 |
|---|---|---|
| 插件 id | `eclipse.agent-ready` | `/home/eclipse/omarchy-agent-ready-release/manifest.json` id；`/home/eclipse/omarchy-agent-ready-release/Widget.qml` `moduleName`、`ShellIpc.target`；`/home/eclipse/omarchy-agent-ready-release/install.sh`/`/home/eclipse/omarchy-agent-ready-release/uninstall.sh` `PLUGIN_ID`；`$HOME/.config/omarchy/shell.json` 的 `{"id":...}`；CLI `I18N_DIR` 路径 |
| 插件目录 | `$HOME/.config/omarchy/plugins/eclipse.agent-ready/` | CLI `I18N_DIR`（**硬编码**）、widget `Qt.resolvedUrl("i18n")` 解析基准、两个安装脚本 |
| CLI 路径 | `$HOME/.local/bin/omarchy-agent-ready` | `/home/eclipse/omarchy-agent-ready-release/Widget.qml` `readonly property string cli`（**硬编码**）；CLI 里 `omarchy-notification-send --action omarchy-agent-ready ...`；hooks 与文档 |
| config 目录 | `$HOME/.config/omarchy/agent-ready` | CLI `CONFIG_DIR`；安装脚本；hooks 环境变量 |
| state 目录 | `$HOME/.local/state/omarchy/agent-ready` | CLI `STATE_DIR`；hooks 环境变量 |
| 系统语言文件 | `$HOME/.config/omarchy/language` | CLI `LANGUAGE_FILE`；Omarchy 全局 |
| Stay Awake marker | `$HOME/.local/state/omarchy/indicators/stay-awake` | CLI `STAY_AWAKE_FILE` |
| `$HOME/.config/omarchy/shell.json` | `$HOME/.config/omarchy/shell.json` | CLI `SHELL_JSON`（读 `idle.*`）；安装脚本（写 `bar.layout`） |

另外：`omarchy-shell lock status` 是 Qt 程序，`LC_ALL=C` 下会往 stdout 打 locale 警告，
代码里用 `LC_ALL=C.UTF-8 timeout 1 ... | grep -m1 '^{'` 只取 JSON 行——**不要删掉这个 locale 前缀**。

---

## 11. 关键设计决策与踩过的坑

> 这一节是本项目最值钱的部分。改代码前请先读，很多"看起来多余"的写法都是被真实 bug 逼出来的。

### 11.1 不改系统文件
所有 Omarchy 系统文件（`/usr/share/omarchy/...`）只读引用。升级 Omarchy 不会破坏本插件；
本插件也不会破坏别人。

### 11.2 为什么全部走 argv-vector `Process`
早期用 `Quickshell.execDetached` + `bash -lc` 起倒计时 worker，在 Surface 机器上每次点击
都会产生**可听见的 codec pop**（音频设备被重新初始化）。改成：
- 所有 CLI 调用 = `Process { command: [argv...] }`，**无 shell、无 login shell**
- 串行命令队列 `runCommand` / `drainQueue`，快速连点配置不会互相踩
- 倒计时**由 widget 拥有**（每秒轮询 `status-json`，到点调 `_arm-fire <token>`），
  不再有 detached 长生命周期子进程

回归红线：**熄屏与解锁两个瞬间必须无尖锐声**。任何改回 `execDetached` / `bash -lc` 的改动都会复现。

### 11.3 `audio.mute` 默认 false
本机 sink 的 Flags 含 `HARDWARE HW_MUTE_CTRL`，`pactl set-sink-mute` 会切 codec 的
amp/mute GPIO 并爆音。默认关闭；需要静音时用 `pactl set-sink-volume 0%`（不走硬件控制）。

### 11.4 DPMS 与红外人脸解锁（`surface.lock`）的冲突 ★
曾出现「按键后短暂亮屏又随机熄灭、红外相机仍工作、有时回不到桌面」。
根因：早期 `reconcile` 用 `health.dpmsLit > 0`（有显示器亮着）判据每 2 s 补一次 DPMS off，
把锁屏插件为**人脸扫描而合法 wake** 的屏幕当成异常关掉，两边抢 DPMS 控制权。

**修复（现在的写法，不要回退）**：
- 判据改为 `health.monitorsChanged`——只在**显示器集合（name 列表）变化**时 reblank 一次，
  `do_reblank` 里刷新 `monitorIds` 快照使其自动清零
- `health.dpmsLit` 降级为**纯信息字段**，绝不驱动 reblank 或 degraded 徽标
- `do_on` 里的 DPMS off 是**一次性**的；会话锁激活期间显示状态归锁屏插件管
- active 时轮询 1 s → 500 ms，缩短解锁 → `off` 的交接延迟

结论：**该修的是 Agent Ready（外部编排器越权），不是锁屏插件**。
`surface.lock` 是用户自己定制的插件，代码里**不硬依赖它**，只假定"会话锁期间由锁屏插件管理 DPMS"。

### 11.5 `tr()` 函数遮蔽 coreutils `tr` ★
本地化函数最初命名为 `tr()`，会遮蔽外部 `tr` 命令，而脚本有 3 处用到
（`token=$(... | tr -d ' \n')`、两处 `tr '\0' ' ' < /proc/$pid/cmdline`），
真实环境会破坏 inhibitor 存活检测与 token 生成。**已改名 `t()`**（对齐 Omarchy `I18n.t`）。
切勿改回 `tr`。

### 11.6 `uptimeMin` 永远 0
`do_off` 原本在 `write_state false`（清空 `state.since`）之后才 `refresh_digest()`，
导致 `uptime_minutes()` 读到空 since。现在在清空前捕获 `watch_since` / `watch_trigger`
并**传参**给 `refresh_digest` 与 `record_digest_history`。

### 11.7 agent 计数
最早用 `pgrep -f` 词边界统计 cmdline，把路径片段（`codex-home`、`/pi/`）和 Electron
多进程都算进去，得出 52 个误报。现在 `agent_names()` 只按**进程名精确匹配**
`agents.allow`，`agent_count()` 取数组长度（=种类数），稳定且诚实。
node/python 拉起的 agent 检测不到——hook 可用 `digest set '{"agents":[...]}'` 覆盖。

### 11.8 UI 自适应（中文布局）
- `contentHeight` 曾按英文行数写死 215/250/430 → 中文换行多会裁切、少会大片留白 → 改 `implicitHeight` / 上限
- 并排 `Button` 曾强制 `(parent.width - spacing)/2` 且缺 `bordered: true` → 中文短文本变宽条、没标准 chrome → 补 `bordered`；互斥选项组改 `Row + Repeater + cellWidth 均分`（照内置 power 面板）
- hero 文本补 `width: parent.width` + `wrapMode: Text.WordWrap`

### 11.9 通知语言跟随系统 → 插件级可选
CLI 通知最早中英混排写死。现全部进共享 catalog，且支持**插件级**
`config.language`（`auto`/`en`/`zh-CN`），**不改系统语言**（`$HOME/.config/omarchy/language` 保持原值）。

### 11.10 并发与其它
- `flock -w 3`：双显示器各有一个 widget 实例，解锁时会同时发同一条 `off`，
  等待而非报 `ERROR`
- `systemd-inhibit` 子进程用 `exec -a omarchy-agent-ready-inhibit sleep infinity` 起，
  `inhibit_alive()` 同时校验 pid 存活 + `/proc/<pid>/cmdline` 含该标记，避免 pid 复用误判
- `do_on` 锁屏失败**就地完整回滚**（不走 `do_off`，会自锁 flock），并排程最多 3 次重试
- `preview` 是自成一体彩排：不发桌面通知，到时自动 `off`
- `.labels.*` 覆盖是**原样使用、不自动翻译**（刻意的显式覆盖）

---

## 12. 发布前清单

> **发布更正**：原清单保留以便追溯。作者现为 menmer0859；URL 已规范为 https://github.com/menmer0859/omarchy-agent-ready.git；版本为 1.1.0；插件 id 保持 eclipse.agent-ready；白名单发布默认 `[]`。原 ★1 的 eclipse 和 ★3 的 13 名是历史值；★2 的旧占位 URL 已替换，不再作为操作目标。

> 接手 Agent：**发布前逐项确认**。带 ★ 的是必须项。

| # | 项 | 说明 |
|---|---|---|
| ★1 | **作者 / 版权** | `/home/eclipse/omarchy-agent-ready-release/LICENSE` 与 `/home/eclipse/omarchy-agent-ready-release/manifest.json` 的 `author` 目前是 `eclipse`；换成真实 GitHub 用户名/组织 |
| ★2 | **仓库 URL** | `/home/eclipse/omarchy-agent-ready-release/README.md` 与 `/home/eclipse/omarchy-agent-ready-release/install.sh` 注释里的旧占位地址全部替换（现统一为 `https://github.com/menmer0859/omarchy-agent-ready.git`）；`/home/eclipse/omarchy-agent-ready-release/docs/*.md` 里若有也一并替换 |
| ★3 | **`agents.allow` 本机化** | **历史作者机器清单** 13 个名字（`pi, oh-my-pi, pyagent, py-agent, hermes, opencode, cindy, codex, chatgpt, magpie, claude, grok, omp`）是**作者机器上的 agent 名**。在 README「Configuration」和 `/home/eclipse/omarchy-agent-ready-release/docs/CLI.md` 明确写「按自己机器改」，或改成更中性的默认集 |
| ★4 | **截图 / 演示** | README 需要至少 1 张状态栏图标 + 1 张设置面板 + 1 张值班摘要截图（本项目目前**没有任何图片资源**）。可标注 "screenshot TBD" 但最好补上 |
| ★5 | **版本号** | `/home/eclipse/omarchy-agent-ready-release/manifest.json` 现在是 `1.1.0`；与 GitHub Release tag 保持一致 |
| ★6 | **manifest description** | 当前描述偏旧（只提 countdown + settings panel），建议补上 auto-arm / digest history / 语言 / 开关 |
| 7 | 死代码清理（可选） | `/home/eclipse/omarchy-agent-ready-release/bin/omarchy-agent-ready` 的 `AUTO_STATE_FILE` 常量未使用，可删 |
| 8 | 语言选项位置 | 语言三档在 **Advanced 最底部**（用户明确要求），不要挪回顶部 |
| 9 | 固定 Hero | 设置面板 Hero 是**固定信息栏**，不要放回 ScrollView 里 |
| 10 | 运行时数据 | 确认仓库里**没有** `$HOME/.local/state/omarchy/agent-ready/state.json` / `$HOME/.local/state/omarchy/agent-ready/digest.json` / `$HOME/.local/state/omarchy/agent-ready/history.json` / `*.log`（`$HOME/.local/state/...` 下的真实数据不要复制进来） |
| 11 | Omarchy 版本 | 代码针对当前 Omarchy（Quickshell + `Commons.*` kit + plugin schemaVersion 1）。README 写明兼容范围 / 已知版本 |

> **安全更正**：以下为历史建议命令，未在本次执行。仅隔离 HOME 不能隔离 DBus、Hyprland、systemd 或电源硬件；安装/卸载可能调用 `off`。必须另用命令 stub 或完全隔离测试环境，不能直接视为真实桌面上的安全测试。

**发布前请再跑一次**（在隔离 HOME，不要污染真实系统）：
```bash
bash -n /home/eclipse/omarchy-agent-ready-release/install.sh /home/eclipse/omarchy-agent-ready-release/uninstall.sh /home/eclipse/omarchy-agent-ready-release/bin/omarchy-agent-ready
omarchy plugin validate /home/eclipse/omarchy-agent-ready-release
T=$(mktemp -d); mkdir -p "$T/.config/omarchy"
echo '{"bar":{"layout":{"center":[],"right":[]}},"idle":{"screensaver":150,"lock":300}}' > "$T/.config/omarchy/shell.json"
HOME="$T" /home/eclipse/omarchy-agent-ready-release/install.sh --no-restart
HOME="$T" "$T/.local/bin/omarchy-agent-ready" doctor
HOME="$T" /home/eclipse/omarchy-agent-ready-release/uninstall.sh --no-restart --purge
rm -rf "$T"
```

---

## 13. 发布到 GitHub 的步骤

1. **建仓库**（建议名 `omarchy-agent-ready`），visibility public，初始化时**不要**勾选
   `/home/eclipse/omarchy-agent-ready-release/README.md` / `/home/eclipse/omarchy-agent-ready-release/LICENSE`（本地已有，避免冲突）。
2. 在本目录执行：
   ```bash
   cd /home/eclipse/omarchy-agent-ready-release
   git init -b main
   git add -A
   git commit -m "Initial release: Agent Ready for Omarchy"
   git remote add origin https://github.com/menmer0859/omarchy-agent-ready.git
   git push -u origin main
   ```
3. **仓库设置**：Description 写「Agents-on-duty power scene for Omarchy」；
   Topics：`omarchy`, `hyprland`, `quickshell`, `power-management`, `linux-desktop`, `agents`。
4. **Release**：tag `v1.1.0`（与 manifest 对齐），写 changelog（见第 19 节演进历史）。
5. **可选增强**（按性价比排序）：
   - 提交到 Omarchy 官方 plugin catalog（若该项目接受第三方插件收录）
   - 提供 Arch `PKGBUILD` / AUR 包（`/home/eclipse/omarchy-agent-ready-release/install.sh` 逻辑可直接复用）
   - GitHub Actions：只对 `/home/eclipse/omarchy-agent-ready-release/install.sh`/`/home/eclipse/omarchy-agent-ready-release/uninstall.sh`/CLI 跑 `bash -n`、`jq -e` 校验两份 i18n key parity、
     `omarchy plugin validate`（后者需要 Omarchy 环境，可用容器或跳过）
   - 补一张架构图（本文第 2 节的 ASCII 图可转成 mermaid）
6. **README 徽章**（可选）：License、Release version、Omarchy。

---

## 14. 外部依赖与 Omarchy 集成点

### 命令依赖（`doctor` 会检查）

`jq`, `pactl`, `powerprofilesctl`, `systemd-inhibit`, `hyprctl`, `brightnessctl`,
`flock`, `nohup`, `omarchy-system-lock`, `omarchy-brightness-display`,
`omarchy-brightness-keyboard`, `omarchy-toggle-idle`, `omarchy-audio-output-sink`,
`omarchy-notification-send`。`curl` 仅 Bark 用（缺失只告警，不阻塞）。

### Omarchy 集成点

| 点 | 用法 |
|---|---|
| 插件发现 | `$HOME/.config/omarchy/plugins/<id>/manifest.json`，`schemaVersion: 1`，`kinds:["bar-widget"]`，`entryPoints.barWidget: "Widget.qml"` |
| 插件校验 | `omarchy plugin validate <dir>`（发布前用）；本机已通过 |
| bar 注册 | `$HOME/.config/omarchy/shell.json` → `bar.layout.<section>` 里 `{"id":"eclipse.agent-ready"}` |
| 安装（官方） | `omarchy plugin add <git-url> --enable` / `omarchy plugin install`；`omarchy plugin enable <id> --section right` |
| 重载 | `omarchy restart shell`（新插件必须重启才注册）；`omarchy-shell shell rescanPlugins` 只重载已改动文件 |
| 共享 UI kit | `qs.Ui`（`PopupCard`, `WidgetButton`, `PanelSeparator`, `PanelSectionHeader`, `Toggle`, `NumberField`, `Button`）、`qs.Commons`（`Color`, `I18n` 等）、`Style` tokens |
| IPC | `ShellIpc { target: "eclipse.agent-ready" }` → `omarchy-shell eclipse.agent-ready open\|close\|toggle` |
| 状态栏移动 | `omarchy bar move eclipse.agent-ready --section <section>` |
| Stay Awake | `omarchy-toggle-idle stay-awake` / marker file `$HOME/.local/state/omarchy/indicators/stay-awake` |
| 语言 | `$HOME/.config/omarchy/language`（Setup > Language）；系统 i18n 见 `/usr/share/omarchy/default/i18n/` |
| idle 阈值 | `$HOME/.config/omarchy/shell.json` 的 `idle.screensaver` / `idle.lock` |

### 与周边组件的关系

- **magpie / pi-agent / eclipse.agents / pi-agent-home**：同机器上已有的 agent 基础设施。
  本项目**不调用、不依赖、不修改**它们；只是各自独立持有 inhibitor（`--who=omarchy-agent-ready`）。
- **surface.lock（用户定制的红外人脸解锁插件）**：不硬依赖，但设计上把会话锁期间的
  DPMS 控制权交给它（见 [11.4](#114-dpms-与红外人脸解锁surface-lock的冲突-)）。
  普通 Omarchy 没这个插件也能正常工作。
- **多显示器**：每个屏幕一个 widget 实例；`ShellIpc` 的 "handler already registered" 日志是预期且无害；
  `flock -w 3` 吸收并发命令。

---

## 15. 安装 / 卸载方案

`/home/eclipse/omarchy-agent-ready-release/install.sh`（已实测）做 8 件事：
1. 校验仓库文件齐全、`$HOME/.config/omarchy` 存在、`jq` 可用；缺失的运行时命令只告警
2. `install -m 755 /home/eclipse/omarchy-agent-ready-release/bin/omarchy-agent-ready → $HOME/.local/bin/`
3. `/home/eclipse/omarchy-agent-ready-release/config/config.json → $HOME/.config/omarchy/agent-ready/`（**仅首次**；`--force` 才覆盖）
4. `$HOME/.config/omarchy/agent-ready/enter.d/` / `$HOME/.config/omarchy/agent-ready/leave.d/` 的 README 与 `.disabled` 示例（`cp -n`，不覆盖用户已启用的 hook）
5. `/home/eclipse/omarchy-agent-ready-release/manifest.json` / `/home/eclipse/omarchy-agent-ready-release/Widget.qml` / `/home/eclipse/omarchy-agent-ready-release/PluginI18n.qml` / `/home/eclipse/omarchy-agent-ready-release/i18n/*.json` → 插件目录（可覆盖更新）
6. 幂等注册 `$HOME/.config/omarchy/shell.json`（先备份 `$HOME/.config/omarchy/shell.json.agent-ready.bak`；默认 `right`，`--section` 可改）
7. `omarchy-plugin-validate` + `omarchy-agent-ready doctor`
8. `omarchy restart shell`（`--no-restart` 可跳过）

`/home/eclipse/omarchy-agent-ready-release/uninstall.sh`：先调 `off` 恢复正常状态 → 从 `$HOME/.config/omarchy/shell.json` 各 section 移除 id →
删 CLI 与插件目录 → 默认**保留** config/state（`--purge` 才删）→ 重启 shell。

两种安装途径（README 里都写了）：
- **推荐**：`git clone` + `/home/eclipse/omarchy-agent-ready-release/install.sh`（一步到位）
- **仅插件**：`omarchy plugin add <url> --enable`，再跑 `/home/eclipse/omarchy-agent-ready-release/install.sh --no-restart` 补 CLI/config

---

## 16. 验证清单

发布前 / 用户安装后按此验收（本机已全部通过）：

**静态**
- `bash -n` 三个脚本；所有 JSON `jq -e .`；`omarchy plugin validate /home/eclipse/omarchy-agent-ready-release`
- 两份 i18n key parity（`en` = `zh-CN`，当前 127/127）
- `/home/eclipse/omarchy-agent-ready-release/Widget.qml` 括号平衡、无重复 id

**CLI 沙盒**（`AGENT_READY_*_DIR` 指向临时目录，禁用所有真实电源动作）
- 完整状态机 `arm / disarm / auto-arm / preview / on / off` 的 `phase` 流转
- `digest set/get/history/clear`、`digest.enabled=false` 不记录、`digest clear` 清空
- `uptimeMin` 非 0；`trigger` 为 manual/auto/preview；`agents` 是名字数组
- 语言优先级矩阵（`auto`/`en`/`zh-CN` × 系统 en/zh-CN/de + `OMARCHY_LANGUAGE_FILE` 覆盖）
- 端到端抓通知（stub `omarchy-notification-send`）：en 与 zh-CN 各一遍

**运行时**
- `omarchy restart shell` 后无 QML 错误（`journalctl _PID=<quickshell>`）
- 语言切换日志 `Agent Ready language: zh-CN · 语言` / `en · Language`
- 渲染 0 / 3 / 20 条历史都不报 `Binding loop` 或其它 QML 错误

**人工（红线）**
- 熄屏、解锁两个瞬间**无尖锐声**
- 熄屏 → 隔几分钟按键 → 稳定亮屏 → 人脸/密码解锁 → 稳定回桌面（重复 3–4 轮）
- 空闲约 2 分钟自动 arm；倒计时期间敲键盘自动取消；解锁后 60 s 内不二次自动 arm
- 解锁后值班摘要自动展开；「返回」回到来源；「试一下」20 s 自动恢复
- 中英切换后面板无裁切/留白，按钮是带边框的标准 chip

---

## 17. 已知限制与机器特定假设

> **发布更正**：第 2 项描述的是历史作者机器清单；当前发布默认 `agents.allow: []`，用户必须自行配置，并保留 node/python 检测限制。

> **发布时请在 README 明确保留这些说明**，否则别人装了会困惑。

1. **只支持 Omarchy**。依赖 `omarchy-*` 辅助命令、`$HOME/.config/omarchy/shell.json`、Quickshell bar-widget API、
   `Commons.*` UI kit、Nerd Font 字形。不是通用 Linux 工具。
2. **`agents.allow` 是作者机器专属清单**（pi / Cindy / Codex / magpie / OpenCode / Hermes …）。
   别人必须按自己机器改；node/python 拉起的 agent 检测不到。
3. **`audio.mute` 默认 `false`** 是因为作者机器（Surface）的 `HW_MUTE_CTRL` 会爆音。
   别的机器可能想打开；面板里可切。
4. **绝不 spawn `execDetached` / `bash -lc`**（Surface 音频 pop，见 11.2）。
5. **`surface.lock` 不是依赖**，但 11.4 的 DPMS 让权逻辑是围绕"会话锁插件会自己 wake 做人脸"
   设计的；普通 Omarchy 无此插件也正常。
6. **只有 `en` / `zh-CN` 两份 catalog**；其它语言回落到英文（不会报错）。
7. **自动进入依赖系统 idle 时间足够长**；太短时面板显示「自动进入不可用」而非抢跑。
8. 图标 `󰊚` 需要 Nerd Font（Omarchy 自带）；若显示方框，改 `icons.*`。
9. `omarchy-shell lock status` 需要 UTF-8 locale 才能拿到干净 JSON（代码已处理，别删）。
10. `freeze`（SIGSTOP 非 agent 进程）与 `audio.suspendSinks` 是**实验性**功能，默认关。
11. 历史文件上限 200 条（防止 `status-json` 变大）；超出后丢弃最旧的。

---

## 18. 未完成 / 待办

> **发布更正**：第 1 项中的作者、URL、默认白名单已有本文开头的发布基准；原待办不删除，截图及实际文件一致性仍需核对，不将历史任务重复认作当前值。

按优先级：

1. **机器无关化**：`agents.allow` 默认值、截图、作者信息、仓库 URL（第 12 节 ★ 项）。
2. **cover 模式 + 输入即锁屏**：曾规划为「第二阶段」——进入时不完全熄屏而是盖一层应用遮罩，
   以及"有输入立即锁屏"。**未实现**，当前是 session lock + 一次性 DPMS off。
3. **开机状态对账**：机器在 Agent Ready 激活时重启/关机后，下次开机的状态一致性**尚未处理**
   （state 文件可能残留 enabled=true 但 inhibitor 已不存在）。建议加启动时的 reconcile / 清理。
4. **更精确的 agent 检测**：目前只按进程名；可考虑读 agent 会话目录或用 hook 注入。
5. **更多语言 catalog**（社区贡献入口已在 `/home/eclipse/omarchy-agent-ready-release/docs/PLUGIN.md` 写好）。
6. **CI / PKGBUILD / 官方插件收录**（第 13 节）。

没有已知的阻断性缺陷。

---

## 19. 附录：演进历史与验收记录

### 开发阶段（可作为 Release changelog）

| 阶段 | 内容 |
|---|---|
| 1 | 调研 Stay Awake / inhibitor / agent 基础设施；确定「纯用户态 CLI + bar-widget 插件」架构 |
| 2 | 基础电源场景：inhibit、Stay Awake、电源档、熄屏、锁屏、键盘背光、音频、可选冻结；进出现场快照与恢复 |
| 3 | arm 倒计时、桌面通知 / Bark、enter-now、token 防重 |
| 4 | 自动进入（独立 IdleMonitor）、阈值跟随系统、输入即取消、冷却 |
| 5 | 值班摘要 digest、解锁 0 秒交接、hooks、`digest set/get` |
| 6 | 状态机 phase、2 s reconcile、锁屏失败回滚+有限重试、preview、flock 并发 |
| 7 | 修 DPMS/红外人脸解锁冲突；UI 自适应（contentHeight / bordered / 均分） |
| 8 | 通知本地化：共享 catalog + `t()`；修 `tr()` 遮蔽 coreutils 的 bug |
| 9 | 插件级语言选择（`PluginI18n`，`config.language`），不改系统语言 |
| 10 | 语言选项移入 Advanced 底部、设置面板 Hero 固定、digest 返回逻辑、全历史 + 详细描述、`digest.enabled` 开关 |

### 用户验收记录

- 冲突与 UI 问题：**已解决**；熄屏与解锁**无尖锐声**
- 语言更新：**已确认正确**（用户把插件语言留在 `zh-CN`，系统语言仍 `en`）
- 最近一轮（Hero 固定 / 返回 / 全历史 / 开关）：**代码与自动验证已通过，待用户人工验收**

### 源码索引（本机原始路径，交接前的开发位置）

```
/home/eclipse/.local/bin/omarchy-agent-ready                          → /home/eclipse/omarchy-agent-ready-release/bin/omarchy-agent-ready
/home/eclipse/.config/omarchy/agent-ready/config.json                 → /home/eclipse/omarchy-agent-ready-release/config/config.json（模板已重置为默认值）
/home/eclipse/.config/omarchy/agent-ready/README.md                   → /home/eclipse/omarchy-agent-ready-release/docs/CLI.md
/home/eclipse/.config/omarchy/agent-ready/{enter,leave}.d/*           → /home/eclipse/omarchy-agent-ready-release/config/{enter,leave}.d
/home/eclipse/.config/omarchy/plugins/eclipse.agent-ready/*           → /home/eclipse/omarchy-agent-ready-release（/home/eclipse/omarchy-agent-ready-release/manifest.json / /home/eclipse/omarchy-agent-ready-release/Widget.qml / /home/eclipse/omarchy-agent-ready-release/PluginI18n.qml / /home/eclipse/omarchy-agent-ready-release/i18n）
/home/eclipse/.config/omarchy/plugins/eclipse.agent-ready/README.md   → /home/eclipse/omarchy-agent-ready-release/docs/PLUGIN.md
/home/eclipse/.config/omarchy/shell.json                              → bar.layout.center 含 {"id":"eclipse.agent-ready"}
```

**运行时数据不在仓库内**：作者机器历史位置 `/home/eclipse/.local/state/omarchy/agent-ready/`（用户已有真实值守历史，未复制）；其他用户对应 `$HOME/.local/state/omarchy/agent-ready/`。

---

*本文由参与开发的 Agent 编写，用于完整交接。所有代码均为本目录内的真实文件副本，未做删改。*
