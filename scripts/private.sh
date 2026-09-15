#!/usr/bin/env bash
# 私密层 git 包装器：与公共库共享工作树的第二个 git
#
#   git-dir   = ~/.pi/agent-private.git
#   work-tree = ~/.pi/agent        （与公共库同一棵树）
#
# 用法：bash scripts/private.sh status|diff|add <路径…>|commit -m …|push|pull|log
#
# ⚠ 为什么 add 被加了闸门：
# 私密层的 index 只跟踪私密路径，而工作树是整个 ~/.pi/agent —— 对私密层的 git 来说，
# auth.json（明文密钥）、sessions/（私有对话）、npm/node_modules、skills-optional/ 大仓
# 全都显示为「未跟踪」。一次 `add -A` 就会把它们吞进历史（README 承诺它们永不入库，
# 但架构本身挡不住）。所以本包装器拒绝 -A/--all/-a 与根级路径，只接受显式子路径。
#
# 环境变量：PRIVATE_GIT_DIR 可覆盖 git-dir 位置（默认为 ~/.pi/agent-private.git）
set -uo pipefail

GIT_DIR="${PRIVATE_GIT_DIR:-$HOME/.pi/agent-private.git}"
AGENT_DIR="$HOME/.pi/agent"

usage() {
  cat >&2 <<'USAGE'
私密层 git 包装器

用法：bash scripts/private.sh <git 子命令> [参数…]
  bash scripts/private.sh status
  bash scripts/private.sh diff --stat
  bash scripts/private.sh add .pi-private/local-patches.json extensions/bash-guard
  bash scripts/private.sh commit -m "…"
  bash scripts/private.sh push
  bash scripts/private.sh pull

add 只接受显式子路径：拒绝 -A / --all / -a / --no-ignore-removal 与根级路径（. / ./ / 工作树根），
以免把 auth.json、sessions/、node_modules 等卷进私密层历史。
USAGE
}

if [ ! -d "$GIT_DIR" ]; then
  echo "错误：找不到私密层 git-dir：$GIT_DIR" >&2
  echo "接入命令（详见 README「双层仓库架构」节）：" >&2
  echo "  git clone --bare https://github.com/SuTang-vain/pi-config-private.git \"$GIT_DIR\"" >&2
  echo "  git --git-dir=\"$GIT_DIR\" config core.worktree \"$AGENT_DIR\"" >&2
  echo "  git --git-dir=\"$GIT_DIR\" config --bool core.bare false" >&2
  echo "  git --git-dir=\"$GIT_DIR\" checkout -f main" >&2
  exit 2
fi

if [ "$#" -eq 0 ]; then
  usage
  exit 2
fi

# ── add 闸门 ────────────────────────────────────────────────────────────────
if [ "$1" = "add" ]; then
  shift
  paths=()
  for arg in "$@"; do
    case "$arg" in
      -A|--all|-a|--no-ignore-removal|--intent-to-add)
        echo "错误：私密层禁止 '$arg'（会把 auth.json / sessions/ / node_modules 一并卷入）。" >&2
        echo "      请列出显式子路径，例如：add extensions/bash-guard skills/analyze-sessions" >&2
        exit 2
        ;;
      -*) ;;                                    # 其余选项放行（-f/-p/-u 等）
      .|./|"$AGENT_DIR"|"$AGENT_DIR"/)
        echo "错误：私密层禁止根级路径 '$arg'。请指明具体子路径。" >&2
        exit 2
        ;;
      *) paths+=("$arg") ;;
    esac
  done
  if [ "${#paths[@]}" -eq 0 ]; then
    echo "错误：add 未给出任何显式路径（拒绝空 add，避免 sweep）。" >&2
    exit 2
  fi
  exec git --git-dir="$GIT_DIR" add "$@"
fi

if [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "help" ]; then
  usage
  exit 0
fi

exec git --git-dir="$GIT_DIR" "$@"
