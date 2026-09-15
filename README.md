# pi-agent-config

我的 [pi](https://github.com/badlogic/pi-mono) 编码代理配置。就地版本化于 `~/.pi/agent/`。

配置本体很小（约 80 KB），但包含若干**体积大、可重装、或不该公开**的目录——
它们由 `.gitignore` 排除，还原方式见下文。

---

## 仓库内容

| 路径 | 说明 |
|---|---|
| `settings.json` | 主配置：默认模型、思考档位、技能白名单、扩展包 |
| `models-store.json` | 自定义 provider 与模型清单（含价格/上下文窗口，**不含密钥**） |
| `agents/` | 三个自定义子代理：`research` / `scout` / `worker` |
| `extensions/productivity/` | 自写的效率扩展套件，6 个模块 |
| `npm/package.json` · `package-lock.json` | 扩展包的精确版本锁定 |
| `run-history.jsonl` | 子代理运行记录（任务已脱敏） |

## 明确排除的内容

| 排除项 | 体积 | 原因 |
|---|---|---|
| `auth.json` | 335 B | **含明文 API 密钥。公开仓库会被爬虫分钟级抓取。绝不提交。** |
| `sessions/` | 75 MB | 私有对话记录 |
| `skills/` · `skills-optional/` | 约 493 MB | 第三方技能库，可重装；体积也不适合入 git |
| `npm/node_modules/` | 19 MB | 第三方包，由 `package-lock.json` 还原 |
| `missions/` | 24 KB | 含本机绝对路径与用户名 |

---

## 还原本配置

### 1. 扩展包

```bash
cd ~/.pi/agent/npm && npm install
```

版本由 `package-lock.json` 锁定。

### 2. 技能

三个来源，全部是第三方仓库，按需 clone 到 `~/.pi/agent/skills/`：

```bash
# herdr（1 个：让 pi 在 Herdr pane 内主动控制 pane/tab/workspace/其他 agent）
# 用已装二进制自带的 release-matched 副本，比 GitHub master 更可靠：
herdr --skill > ~/.pi/agent/skills/herdr/SKILL.md

# pi-skills（保留 6 个：Gmail/Calendar/Drive CLI、transcribe、vscode、youtube-transcript）
git clone https://github.com/badlogic/pi-skills ~/.pi/agent/skills/pi-skills

# 其中两个不需要，用 sparse-checkout **永久排除**（clone 工作区保持干净，git pull 不会带回、
# 也不产生冲突）：
#   browser-tools —— 与 ego-browser 能力完全重叠，却带 120 MB node_modules
#   brave-search  —— 无 BRAVE_API_KEY，无法工作
cd ~/.pi/agent/skills/pi-skills
cat > .git/info/sparse-checkout <<'SPARSE'
/*
!/browser-tools
!/brave-search
SPARSE
git sparse-checkout reapply
rm -rf browser-tools        # sparse 只跳过已跟踪文件；node_modules 未被跟踪，需手动删（120 MB）

# 备注：agent-reach 曾装在 ~/.agents/skills/，因依赖 OpenCLI/twitter-cli/bili-cli
# 三套外部后端 + 浏览器登录态而移除（见 README 末“已移除”一节）

# scientific-agent-skills（163 个科研技能，MIT，v2.64.0）
git clone https://github.com/K-Dense-AI/scientific-agent-skills ~/.pi/agent/skills-optional/scientific-agent-skills

# ego-browser（浏览器自动化，经 skill 管理器安装，带 commit 哈希锁）
# 见 https://github.com/citrolabs/ego-lite
```

**注意**：`settings.json` 里的 `skills` 白名单是 **8 个绝对路径**，指向
`~/.pi/agent/skills-optional/scientific-agent-skills/skills/<name>/SKILL.md`。
换机器或换用户名后需要同步修改。

#### 为什么只白名单 8 个？

`skills-optional/` 里有 163 个科研技能，但历史使用统计显示实际只用到 8 个。
pi 会把**所有**已发现技能的 name + description 注入系统提示——全量时约
**19,300 tokens/会话**，收敛后降到约 **1,770 tokens**（省 91%）。

省下的钱不多（约 $0.024/会话），真正的收益是上下文空间与注意力不被稀释：
163 个化学、量子、实验室自动化技能与日常编码无关。

#### 实际生效的技能（17 个）

```
白名单 8 个 : exa-search · pi-agent · pyhealth · hypothesis-generation
database-lookup · literature-review · paper-lookup · scikit-learn

自动扫描     : ego-browser（~/.agents/skills/）
            : herdr（skills/herdr/）
            : gccli · gdcli · gmcli · transcribe · vscode · youtube-transcript（pi-skills）
            : sg-data-pack（~/.agents/skills/）
```

需要其他技能时按需挂载：

```bash
pi --skill ~/.pi/agent/skills-optional/scientific-agent-skills/skills/qutip/SKILL.md
```

#### 网络检索的分工（避免冗余）

| 角色 | 承担者 | 说明 |
|---|---|---|
| 发现候选 URL | `exa-search` 技能 | 写文件 → 只取 `title+url`（~215 tok），结构化 JSON 可筛 |
| URL → 净正文 | `exa_extract.py`（同技能自带） | 走 Exa `/contents`，支持批量，无需浏览器 |
| 读透真实页面 | `ego-browser` | JS 重、登录墙、需点击的场景 |

已移除的重叠项：`pi-web-access`（Exa 部分与 exa-search 重复，+810 tok/会话）、
`brave-search`（无密钥）、`browser-tools`（120 MB，与 ego-browser 全面重叠）、
`agent-reach`（依赖三套外部后端）。

> ⚠️ 用 `exa-search` 时注意：`/answer` 与 `/search` 是两个端点。
> 不传 `numResults` 才走 `/answer`（Exa 便宜 40% 且返回紧凑合成答案）；
> 传了其他值会走 `/search`（Exa 更贵 + 返回大块拼接文本 + 本地成本翻倍）。

### 3. Herdr 集成（可选）

若在 [Herdr](https://herdr.dev) 的 pane 内使用 pi，安装官方集成以获得
**原生会话恢复 + 生命周期状态上报**：

```bash
herdr integration install pi      # 写入 extensions/herdr-agent-state.ts
herdr integration status          # 验证
```

该文件由 Herdr 生成与管理（重装会覆盖），**不在本仓库内**（见 `.gitignore`）。

⚠️ **集成 ≠ 技能**，两者方向相反，别混：

| | 文件 | 方向 | 作用 |
|---|---|---|---|
| 集成 | `extensions/herdr-agent-state.ts` | pi → Herdr | pi 上报自己的 `idle/working/blocked` |
| 技能 | `skills/herdr/SKILL.md` | Herdr → pi | 教 pi 如何操作 pane/tab/workspace/其他 agent |

只装集成时，Herdr 看得见 pi，但 pi 用不上 Herdr。

它会向 Herdr 的本地 Unix socket 上报 agent 状态（`idle` / `working` / `blocked`）。
权限画像：仅 `import net`，零子进程、零网络、零文件读写，且以 `HERDR_ENV=1`
为门控——不在 Herdr 内运行时完全惰性。

⚠️ **hook 只在 agent 启动时加载。** 装集成**不会**影响当时正在跑的 pi 会话；
已存在的 agent 必须重启才会从「屏幕猜状态」切到权威上报。验证方式：

```bash
herdr agent explain <target>
# 权威：screen_detection_skip_reason: full_lifecycle_hook_authority
# 猜屏：fallback_reason: default_known_agent_idle_fallback
```

Herdr 侧的完整说明——两个集成的差异、实测对照、以及**无损重载已有 agent**
的脚本（保留上下文 / todo / MCP）——见
**[SuTang-vain/herdr-config](https://github.com/SuTang-vain/herdr-config)**。

> 注：无损重载目前只验证了 `kind=kimi`；pi 的退出与恢复参数未实测。

### 4. 密钥

`auth.json` 需手动创建，格式：

```json
{
  "your-provider": { "type": "api_key", "key": "sk-..." }
}
```

配置的 provider（见 `models-store.json`）：

| provider | 模型数 | 用途 |
|---|---|---|
| `zai-coding-cn` | 10 | 默认（`glm-5.3`，思考档 `high`） |
| `deepseek` | 2 | 备选 |
| `opencode-go` | 27 | 聚合网关，含多家模型 |

文件权限建议 `chmod 600 auth.json`。

---

## 扩展套件：`extensions/productivity/`

单目录六模块，可逐个注释关闭。

| 文件 | 功能 | 开关 |
|---|---|---|
| `session-name.ts` | 首次输入时自动命名会话（`/resume` 列表显示任务摘要） | — |
| `auto-commit.ts` | 会话结束时提交**本次被 `edit`/`write` 触及的文件** | `PI_NO_AUTO_COMMIT=1` |
| `notify.ts` | agent 完成时桌面通知（macOS osascript / Kitty OSC 99 / iTerm2 OSC 777） | `PI_NO_NOTIFY=1` |
| `model-status.ts` | 状态栏显示当前模型 | — |
| `todo.ts` | 模型可调用的 `todo` 工具 + `/todos` 面板 | — |
| `footer.ts` | 底部自定义 footer：token/成本/git 分支/模型 | `/footer` |

### `auto-commit` 的设计取舍

**只暂存本次会话中 `edit`/`write` 实际写过的文件，不用 `git add -A`。**

原实现对仓库执行 `git add -A`，会把未跟踪文件（`.env`、构建产物、临时文件）
一并提交，且提交信息取自最后一条助手回复的前 50 字——两者都可能把不该进
版本库的内容写进历史。现行为：无写入则不提交；提交信息为
`[pi] 改动 N 个文件：<文件名>`，可追溯且不含对话内容。

## 子代理：`agents/`

| 代理 | 职责 |
|---|---|
| `research` | 信息调研：用 ego-browser 检索、核实、产出带来源的简报 |
| `scout` | 只读侦察：用最少读取量摸清代码库结构，产出可交接的压缩上下文 |
| `worker` | 实现：按已批准方向做最小正确改动，唯一写入线程 |

三者都声明了工具白名单、`acceptanceRole`（只读/写入）与
`contact_supervisor` 升级路径。

---

## 已移除 / 已淘汰

保留此清单是为了避免重装时又把它们拿回来（每一项都记录了移除理由与恢复方式）。

| 已移除 | 曾占用 | 理由 | 恢复方式 |
|---|---|---|---|
| `pi-web-access` (npm) | 810 tok/会话 + 132 依赖 + 7 MB | Exa 部分与 `exa-search` 完全重复；PDF/YouTube 已被其他技能覆盖 | `pi install npm:pi-web-access` |
| `browser-tools` | 120 MB | 8 个脚本 100% 被 `ego-browser` 覆盖；正文提取由 `exa_extract.py` 替代 | 改 `pi-skills` 的 sparse 规则后 `npm install` |
| `brave-search` | 29 MB | 无 `BRAVE_API_KEY`，无法工作 | 同上（sparse 规则） |
| `agent-reach` | 230 tok | 依赖 OpenCLI / twitter-cli / bili-cli 三套外部后端 + 浏览器登录态；其中 GitHub/YouTube/任意网页/语义搜索四项均已被 `gh` / `youtube-transcript` / `ego-browser` / `exa-search` 覆盖 | `mv ~/.pi/agent/skills-optional/agent-reach ~/.agents/skills/` |
| `@jackwener/opencli` (npm -g) | 29 MB + 228 KB + 14 MB 常驻守护 | 仅 agent-reach 使用；agent-reach 移除后成为孤儿 | `npm i -g @jackwener/opencli` |
| `minimax-cn` provider | 3 个死条目 | 无 API 密钥，选中即报错 | 编辑 `models-store.json` |

> 注：`~/.hermes`（2.7 GB，Hermes Agent v0.17.0）**不是**这些工具的残留，
> 而是一套独立框架，两者双向引用数为 0。清理时切勿混淆。

## 许可

本仓库内容（配置与自写扩展）采用 **MIT**，见 [LICENSE](LICENSE)。

第三方内容遵循各自上游许可，**不因本仓库的 MIT 而改变**：

| 内容 | 许可 |
|---|---|
| 扩展包 `pi-subagents` / `pi-goal-x` / `@juicesharp/rpiv-ask-user-question` | 见各自 npm 包 |
| 技能库 `scientific-agent-skills` | MIT（K-Dense AI） |
| 技能库 `pi-skills` | 见 https://github.com/badlogic/pi-skills |
| `ego-browser` | 见 https://github.com/citrolabs/ego-lite |

（后三者由 `.gitignore` 排除，不在本仓库内。）
