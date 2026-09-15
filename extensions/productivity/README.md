# Productivity Suite(方案 C)

个人效率扩展套件,安装在 `~/.pi/agent/extensions/productivity/`,pi 启动时自动加载。

## 模块

| 文件 | 功能 | 开关 |
| --- | --- | --- |
| `session-name.ts` | 首次输入时自动命名会话(截断 40 字符,跳过 `/` 命令);`/session-name [名字]` 手动设置/查看 | — |
| `auto-commit.ts` | 会话关闭时自动 `git add -A && git commit`,提交信息取最后一条助手回复首行(50 字符) | `PI_NO_AUTO_COMMIT=1` |
| `notify.ts` | agent 完成时桌面通知(macOS 用 osascript,兼容任何终端;Kitty/iTerm2/Ghostty 用 OSC 协议) | `PI_NO_NOTIFY=1` |
| `model-status.ts` | 状态栏常驻当前模型,切换模型时通知 | — |
| `todo.ts` | 官方 todo 扩展:模型可调用的 `todo` 工具 + `/todos` 可视化面板(状态存会话内,分支安全) | — |
| `footer.ts` | TUI 底部自定义 footer:本会话 token 用量 / 成本 / git 分支 / 模型,`/footer` 开关 | — |

## 日常用法

- 启动 `pi` 后,future 底部自动显示 `↑3.2k ↓1.1k $0.042 deepseek-v4-pro (main)`
- 直接说"帮我列个待办"——模型会调用 `todo` 工具;`/todos` 查看面板
- 每次 agent 跑完,系统弹通知;退出会话时工作区改动自动提交
- `/resume` 列表里会话名是任务摘要而不是原始长 prompt

## 调整

- 想关掉某个模块:编辑 `index.ts`,注释掉对应行,`/reload` 热重载
- 单独调试:`pi -e ~/.pi/agent/extensions/productivity/index.ts`
- 全局关闭自动提交:`export PI_NO_AUTO_COMMIT=1`(写进 `~/.zshrc` 可永久生效)

## 注意

- 扩展以你的完整用户权限运行(本套件仅调用 git / osascript / 通知协议,无网络请求)
- `auto-commit` 在 git hook 失败时会在状态栏提示,不会静默吞掉错误
