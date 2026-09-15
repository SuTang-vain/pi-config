#!/usr/bin/env bash
# 上游漂移检测器：对照 tools/upstream-snapshot.json 检查三态
#   ① 上游有更新（upstream_now ≠ snapshot）→ 需人工评估是否合并
#   ② 本地有改动（local_now ≠ snapshot.local）→ 补丁（正常）或意外漂移
#   ③ npm 上游有新版本 → pi update 前先读补丁③警告
# 用法：bash ~/.pi/agent/tools/check-upstream-drift.sh [--refresh]
set -uo pipefail
AGENT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LEDGER="$AGENT_DIR/tools/upstream-snapshot.json"
PY="$(command -v python3)"

fetch_sha() { curl -sL --max-time 15 "$1" | shasum -a 256 | cut -d' ' -f1; }

echo "== 上游漂移报告（$(date '+%F %T')）=="
echo "快照时点: $($PY -c "import json;print(json.load(open('$LEDGER'))['captured_at'])")"
echo

# --- 文件型组件 ---
$PY - <<'PYEOF' > /tmp/drift_items.tsv
import json
for c in json.load(open("tools/upstream-snapshot.json"))["components"]:
    print(f"{c['local_path']}\t{c['upstream_url']}\t{c['patched']}\t{c['local_sha256']}\t{c['upstream_sha256_at_capture']}")
PYEOF

while IFS=$'\t' read -r local url patched snap_local snap_up; do
  lp="$AGENT_DIR/$local"
  now_local=$([ -f "$lp" ] && shasum -a 256 "$lp" | cut -d' ' -f1 || echo MISSING)
  now_up=$(fetch_sha "$url")
  if [ "$now_up" != "$snap_up" ]; then up="⬆ 上游有更新"; else up="  上游未动"; fi
  if [ "$now_local" != "$snap_local" ]; then
    if [ "$patched" = "True" ]; then loc="🔧 补丁后又变（对照标记重审）"; else loc="⚠ 本地意外漂移"; fi
  else
    if [ "$patched" = "True" ]; then loc="🔧 补丁在位（快照后未变）"; else loc="  本地一致"; fi
  fi
  printf "%s %s  %s\n" "$up" "$loc" "$local"
done < /tmp/drift_items.tsv
rm -f /tmp/drift_items.tsv

# --- npm 包 ---
echo
$PY - <<'PYEOF' > /tmp/npm_items.tsv
import json
for name, info in json.load(open("tools/upstream-snapshot.json"))["npm_packages"].items():
    print(f"{name}\t{info['installed_version']}\t{info['patched']}")
PYEOF
while IFS=$'\t' read -r name ver patched; do
  latest=$(npm view "$name" version 2>/dev/null || echo "?")
  if [ "$latest" = "$ver" ]; then st="  npm 最新";
  else st="⬆ npm 有新版 $latest（装 $ver）"; fi
  [ "$patched" = "True" ] && st="$st · 🔧 补丁③会被覆写，更新后需重打"
  printf "%s  %s\n" "$st" "$name"
done < /tmp/npm_items.tsv
rm -f /tmp/npm_items.tsv
echo
echo "处理策略：无补丁组件→按 README 重建命令重拷；bash-guard→对照补丁①-⑥标记重应用并跑测试；"
echo "npm 有补丁→pi update 后重打补丁（filechanges 的 showWidget 一行改）；git 克隆→直接 pull（sparse 保护）。"
