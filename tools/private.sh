#!/usr/bin/env bash
# 私密层 git 包装器：与公共库共享工作树的第二个 git
# 用法：bash tools/private.sh <git 子命令>   如 bash tools/private.sh status
exec git --git-dir="$HOME/.pi/agent-private.git" "$@"
