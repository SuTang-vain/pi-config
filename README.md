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
| `auth.json` | 468 B | **含明文 API 密钥。公开仓库会被爬虫分钟级抓取。绝不提交。** |
| `sessions/` | 98 MB | 私有对话记录（日增，数字为 2026-09-15 实测） |
| `skills/` · `skills-optional/` | 约 0.5 GB（大头是 scientific 的 git 对象） | 第三方技能库，可重装；体积也不适合入 git |
| `npm/node_modules/` | 20 MB | 第三方包，由 `package-lock.json` 还原 |
| `missions/` | 24 KB | 含本机绝对路径与用户名 |

---

## 还原本配置

### 1. 扩展包

```bash
cd ~/.pi/agent/npm && npm install
```

版本由 `package-lock.json` 锁定。

### 2. 技能

四个来源（含本机二进制生成），按需取用到 `~/.pi/agent/skills/`：

```bash
# herdr（1 个：让 pi 在 Herdr pane 内主动控制 pane/tab/workspace/其他 agent）
# 用已装二进制自带的 release-matched 副本，比 GitHub master 更可靠：
herdr --skill > ~/.pi/agent/skills/herdr/SKILL.md

# pi-skills（保留 1 个：vscode；其余 7 个零调用排除，统计口径见「为什么只注入 8 个技能」）
git clone https://github.com/badlogic/pi-skills ~/.pi/agent/skills/pi-skills

# 其中 7 个经 sparse-checkout **永久排除**（工作区干净，git pull 不带回；理由见末尾「已移除」表）：
#   browser-tools / brave-search / gccli / gdcli / gmcli / transcribe / youtube-transcript
cd ~/.pi/agent/skills/pi-skills
cat > .git/info/sparse-checkout <<'SPARSE'
/*
!/browser-tools
!/brave-search
!/gccli
!/gdcli
!/gmcli
!/transcribe
!/youtube-transcript
SPARSE
git sparse-checkout reapply
rm -rf browser-tools youtube-transcript   # sparse 只跳过已跟踪文件；未被跟踪的 node_modules 需手动删

# 备注：agent-reach 曾装在 ~/.agents/skills/，因依赖 OpenCLI/twitter-cli/bili-cli
# 三套外部后端 + 浏览器登录态而移除（见 README 末“已移除”一节）

# scientific-agent-skills（MIT，v2.64.0，上游 160+ 技能）——partial clone + sparse
# 两坑警告：① 非 cone 模式 ! 是「排除」，!/skills/技能名 会把要留的删掉（先 !/skills/*
#   再 /skills/<name>/ 白名单回来）；② --depth 1 不减 .git（tip 提交引用全部 blob），
#   必须 --filter=blob:none 才按需取
git clone --depth 1 --filter=blob:none --no-checkout \
  https://github.com/K-Dense-AI/scientific-agent-skills \
  ~/.pi/agent/skills-optional/scientific-agent-skills
cd ~/.pi/agent/skills-optional/scientific-agent-skills
git sparse-checkout init --no-cone
cat > .git/info/sparse-checkout <<'SPARSE'
/*
!/skills/*
/skills/exa-search/
/skills/pi-agent/
/skills/literature-review/
/skills/paper-lookup/
/skills/pyhealth/
/skills/hypothesis-generation/
/skills/database-lookup/
/skills/scikit-learn/
SPARSE
git checkout main
# 上例白名单 4 项常驻 + 4 项按需（--skill 时 blob 按需拉取，磁盘即时生效）

# ego-browser（浏览器自动化，经 skill 管理器安装，带 commit 哈希锁）
# 见 https://github.com/citrolabs/ego-lite
```

**注意**：`settings.json` 里的 `skills` 白名单（当前 **4** 项，见下方清单）指向
`~/.pi/agent/skills-optional/scientific-agent-skills/skills/<name>/SKILL.md`。
换机器或换用户名后需同步修改（含 sparse 白名单同步）。

#### 为什么只注入 8 个技能？

`skills-optional/` 上游有 160+ 个科研技能（统计口径：128 个会话的调用记录，
2026-09-15 实测，下同），实际高频仅 4 个。
pi 会把**所有**已发现技能的 name + description 注入系统提示——全量时约
**19,300 tokens/会话**；当前 8 技能（白名单 4 + 自动扫描 4）约 **3.7k 字符**。

省下的钱不多（约 $0.024/会话），真正的收益是上下文空间与注意力不被稀释：
163 个化学、量子、实验室自动化技能与日常编码无关。

#### 实际生效的技能（8 个）

```
白名单 4 个 : exa-search · pi-agent（pi 自身文档，配置工作高频）
            · literature-review · paper-lookup

自动扫描 4 个 : ego-browser（~/.agents/skills/）
             : herdr（skills/herdr/）
             : analyze-sessions（skills/，amos 借鉴件）
             : vscode（pi-skills，唯一保留项）

```

> 零调用淘汰记录（统计口径见上节）：sg-data-pack、gccli、gdcli、
> gmcli、transcribe、youtube-transcript 六项从未被真实调用，已移出扫描路径
> （见末尾「已移除」清单）。pyhealth / hypothesis-generation / scikit-learn /
> database-lookup 四项零调用，2026-09-15 转按需挂载（见上）。

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

它会向 Herdr 的本地 Unix socket 上报 agent 状态。
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
| `kimi-coding` | 4 | Kimi 网关（`k3` / `kimi-for-coding` 等，思考档已配） |

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

## 借鉴组件（来自 [amosblomqvist/pi-config](https://github.com/amosblomqvist/pi-config)）

> 上游无 LICENSE，故这三个目录**不入库**（见 .gitignore），仅本地使用。
> 需要重建时按下述命令再取；bash-guard 含本地补丁，见注释。

| 组件 | 位置 | 作用 |
|---|---|---|
| `analyze-sessions/` | `skills/` | 会话审计：`cost.py --since 7d --by project\|model\|session\|day` 成本汇总（含子代理）、`prompts.py` 提示词挖掘、跨会话检索。stdlib 零依赖 |
| `bash-guard/` | `extensions/` | bash 拦截双层：主会话弹 Run/Abort 对话框（git 全系/管道/重定向/rm/sudo…，60s 防重试）；子代理硬阻断灾难清单（rm -rf/sudo/mkfs/git commit 等），无 UI 时安全失败为 abort |
| `prompt-snippets/` | `extensions/` | 一次性行为规则：`alt+s` 勾选 snippet 随消息注入，发送后自动重置。自带 verify-not-assume 等 6 条 |
| `context.ts` | `extensions/` | `/context` 上下文经济可视化：彩色网格按类别（系统提示/用户/助手/thinking/各工具结果/压缩/图片/剩余）分解 token 用量 + 缓存统计与优化建议 |
| `pdf-reader/` | `skills-optional/`（**按需挂载**，零注入成本） | 视觉混合 PDF 解析：`pdf_info`/`pdf_extract` 文本 + `pdf_render` 页面渲染成 PNG 走视觉（公式/图表友好）。用法：`pi --skill ~/.pi/agent/skills-optional/pdf-reader/SKILL.md`；venv 已建（pymupdf 1.27.2）；`--pages` 从 1 起 |
| `md-link.ts` | `extensions/` | Obsidian 协作桥：`/link-md` 链接 md 文件，agent 终答自动追加进文件（Obsidian 可渲染阅读）；用户直接改文件后 `/sd` 把编辑差异作为消息回传。适配注意：`/context` 的浮层会吞后续按键，操作前先 esc |

```bash
# 再获取（仓库无 LICENSE，仅限个人使用；勿并入本 MIT 仓库）
curl -sL https://github.com/amosblomqvist/pi-config/archive/refs/heads/main.tar.gz | tar xz --strip-components=1 -C /tmp/amos-src
cp -R /tmp/amos-src/skills/analyze-sessions ~/.pi/agent/skills/
cp -R /tmp/amos-src/extensions/bash-guard ~/.pi/agent/extensions/ && cd ~/.pi/agent/extensions/bash-guard && npm install
cp -R /tmp/amos-src/extensions/prompt-snippets ~/.pi/agent/extensions/
cp /tmp/amos-src/deprecated/extensions/context.ts ~/.pi/agent/extensions/
cp /tmp/amos-src/deprecated/extensions/md-link.ts ~/.pi/agent/extensions/
cp -R /tmp/amos-src/skills/pdf-reader ~/.pi/agent/skills-optional/ && cd ~/.pi/agent/skills-optional/pdf-reader && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
# bash-guard 需重打本地补丁①②（见下方「bash-guard 本地补丁」说明）
```

**bash-guard 本地补丁**（上游按 `PI_SUBAGENT_DEPTH` 识别子代理，但本机两个子代理引擎
均不注入该变量）：改为三重检测 `PI_SUBAGENT_ID`（@maplezzk pane 子代理）/
`PI_SUBAGENT_RUNNER_CONFIG`（pi-subagents 无头 runner）/ `!stdin.isTTY`（通用无头）。

**bash-guard 本地补丁 ④（主会话仅拦 HIGH）**：主会话原对任何 git 命令/管道/重定向都弹
Run/Abort。改为 MEDIUM（git status/diff/log、管道、重定向、mv -f 等）静默直通，
HIGH（sudo / rm -rf / find -delete / git rm|clean -f|reset --hard|push --force / curl|sh / 磁盘工具）
仍弹对话框；无 UI 时 HIGH 照旧 abort。子代理硬阻断清单不变。
实测：git status 静默直通；rm -r* 复合命令弹「HIGH risk」对话框（含理由）。
注：pi 会热加载扩展到运行中的会话——扩展装入后行为即生效。

**bash-guard 本地补丁 ⑤（选项区可读性）**：选项区原仅箭头+着色区分，描述被宽度截断。
改为：选项前分隔线（choose an action）、标签带图标（Run ⏎ / Abort ✕）与更明确描述、
选中项加粗、底部按键提示行（↑↓ move · ⏎ confirm · esc = abort）、
宽度 70%→85%（minWidth 56）、高度上限 60%→80%（矮 pane 曾把 Abort 行裁掉）、
命令显示截断 160→120 字符。实测矮 pane 下双选项+提示完整渲染，↓+Enter 拦截生效。

**pi-filechanges 本地补丁（默认关闭 widget）**：npm 包 `extensions/index.ts` 的
`showWidget` 硬编码 true 且无配置机制，本地改为 `false`——Δ 文件清单默认不显示，
`/filechanges` 会话内仍可开；状态栏槽位（有改动时的一行摘要）保留。
⚠ `pi update npm:@johnnywu/pi-filechanges` 会还原此补丁，更新后需重打。

**bash-guard 本地补丁 ②（UI 稳定化）**：对话框原为裸 `overlay: true`，居中锚点随命令长度
漂移且与部件堆栈（filechanges/subagents/prompt-snippets）显示冲突。改为
`anchor: top-center + margin 2 + width 70% + maxHeight 60%` + 命令显示截断 160 字符 +
显式 `handle.focus()`。实测短/长命令对话框标题行均钉在第 4 行，不再侵入编辑器区域。

**子代理加载 bash-guard 的引擎配置**（仅 interactive-subagents 分支需要；该引擎
spawn 子进程用 `--no-extensions` + 显式白名单）：见
`extensions/pi-interactive-subagents/config.json` 的 `subagentExtensions` 字段。

## 已移除 / 已淘汰

保留此清单是为了避免重装时又把它们拿回来（每一项都记录了移除理由与恢复方式）。

| 已移除 | 曾占用 | 理由 | 恢复方式 |
|---|---|---|---|
| `pi-web-access` (npm) | 810 tok/会话 + 132 依赖 + 7 MB | Exa 部分与 `exa-search` 完全重复；PDF/YouTube 已被其他技能覆盖 | `pi install npm:pi-web-access` |
| `browser-tools` | 120 MB | 8 个脚本 100% 被 `ego-browser` 覆盖；正文提取由 `exa_extract.py` 替代 | 改 `pi-skills` 的 sparse 规则后 `npm install` |
| `brave-search` | 29 MB | 无 `BRAVE_API_KEY`，无法工作 | 同上（sparse 规则） |
| `agent-reach` | 230 tok | 依赖 OpenCLI / twitter-cli / bili-cli 三套外部后端 + 浏览器登录态；其中 GitHub/YouTube/任意网页/语义搜索四项均已被 `gh` / `youtube-transcript` / `ego-browser` / `exa-search` 覆盖。**已归档**于 `skills-optional/agent-reach/`（不在扫描路径，零注入） | `mv ~/.pi/agent/skills-optional/agent-reach ~/.agents/skills/` |
| `@jackwener/opencli` (npm -g) | 29 MB + 228 KB + 14 MB 常驻守护 | 仅 agent-reach 使用；agent-reach 移除后成为孤儿 | `npm i -g @jackwener/opencli` |
| `minimax-cn` provider | 3 个死条目 | 无 API 密钥，选中即报错 | 编辑 `models-store.json` |
| `moonshotai-cn` provider | 4 个死条目 | 无 API 密钥（Kimi 模型由 kimi-coding 网关正常提供），选中即报错 | 编辑 `models-store.json` |
| `sg-data-pack` 技能 | 符号链接 | 零调用（口径见技能节）；真身在 `~/.zcode/skills/`（zcode 自用），不受影响 | `ln -s ~/.zcode/skills/sg-data-pack ~/.agents/skills/sg-data-pack` |
| `gccli`/`gdcli`/`gmcli`/`transcribe`/`youtube-transcript` 技能 | 各 4–108 KB | 零真实调用（口径见技能节）（历史"调用"均为 ls 列表误配） | 改 pi-skills sparse 规则；youtube-transcript 恢复后需 `npm install` |
| `~/.hermes`（Hermes Agent 2.7 GB） | 2.7 GB | 框架休眠 2 个月；曾**藏有系统默认 node**，换血到 `/opt/homebrew/bin/node` v26 后整体删除 | 重跑 upstream 安装器；数据备份在 `~/Backups/hermes/` |

> 注：`~/.hermes`（2.7 GB，Hermes Agent v0.17.0）曾是一套独立框架，但其 `node/`
> **曾被当作系统默认 node**（`~/.local/bin/node` 指向它）。已先换血到
> `/opt/homebrew/bin/node` v26、验证 pi-subagents 的 execPath 降级逻辑后才整体删除。
> 教训：目录名判断不了归属，删除前先查双向引用与 PATH 入口。

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
