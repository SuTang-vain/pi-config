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
| `skills/` · `skills-optional/` | 642 MB | 第三方技能库，可重装；体积也不适合入 git |
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

# pi-skills（8 个：brave-search / exa 搜索、浏览器工具、Gmail/Calendar/Drive CLI 等）
git clone https://github.com/badlogic/pi-skills ~/.pi/agent/skills/pi-skills

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
pi 会把**所有**已发现技能的 name + description 注入系统提示——165 个技能约
**19,300 tokens/会话**，白名单后降到约 **2,060 tokens**（省 89%）。

省下的钱不多（约 $0.024/会话），真正的收益是上下文空间与注意力不被稀释：
163 个化学、量子、实验室自动化技能与日常编码无关。

需要其他技能时按需挂载：

```bash
pi --skill ~/.pi/agent/skills-optional/scientific-agent-skills/skills/qutip/SKILL.md
```

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
