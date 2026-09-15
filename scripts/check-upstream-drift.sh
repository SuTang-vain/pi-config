#!/usr/bin/env bash
#
# 上游漂移检测器 —— 对照快照账本 scripts/upstream-snapshot.json 报告借鉴件的三类漂移：
#
#   ① 上游有更新   upstream_now ≠ 账本 upstream_sha256_at_capture → 人工评估是否合并
#   ② 本地有改动   local_now    ≠ 账本 local_sha256               → patched=1 是预期补丁；
#                                                                  patched=0 是意外漂移
#   ③ npm 有新版本 registry latest ≠ 账本 installed_version       → pi update 前先读补丁③警告
#
# 用法：
#   bash ~/.pi/agent/scripts/check-upstream-drift.sh             # 检测并报告
#   bash ~/.pi/agent/scripts/check-upstream-drift.sh --refresh   # 重新生成快照账本
#   bash ~/.pi/agent/scripts/check-upstream-drift.sh --help
#
# 环境变量：
#   PI_DRIFT_LEDGER=<path>   覆盖账本位置（默认与本脚本同目录）
#   PI_DRIFT_SKIP_NPM=1      跳过 npm registry 查询（离线/快速自检）
#
# 退出码：0 = 无漂移 · 1 = 有漂移（①②③ 任一命中）· 2 = 环境或账本错误
#
# ── 为什么放 scripts/ 而不是 tools/ ─────────────────────────────────────────
# pi 0.85.1 启动迁移 checkDeprecatedExtensionDirs() 会把 <agentDir>/tools/ 下
# **任何**不以 "." 开头、且不叫 fd/rg/fd.exe/rg.exe 的条目判为「遗留自定义工具」，
# 打印警告并阻塞等按键。它只看条目名，无法区分脚本/数据与真正的扩展。
# 而 tools/ 自 0.85.1 起已不再是扩展目录（fd/rg 由 getBinDir() 落到 bin/，
# getToolsDir() 在源码中已无调用点）。私有运维脚本的正确位置是 scripts/。
# 详见 README「上游更新策略」一节。
#
# ── bash 3.2 陷阱（macOS 自带 /bin/bash 即 3.2.57） ──────────────────────────
# 变量展开后紧邻多字节字符时必须加花括号：`$ver）` 会被解析成变量名 `ver\xef\xbc\x89`，
# 在 set -u 下直接报 unbound variable。本脚本一律写 `${ver}）`。
#
set -uo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" >/dev/null 2>&1 && pwd -P)"
AGENT_DIR="$(cd -- "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd -P)"
LEDGER="${PI_DRIFT_LEDGER:-$SCRIPT_DIR/upstream-snapshot.json}"

usage() {
  cat <<'USAGE'
上游漂移检测器 —— 对照快照账本报告借鉴件的三类漂移

用法：
  bash ~/.pi/agent/scripts/check-upstream-drift.sh            检测并报告（有漂移时退出码 1）
  bash ~/.pi/agent/scripts/check-upstream-drift.sh --refresh  重新生成快照账本
  bash ~/.pi/agent/scripts/check-upstream-drift.sh --help

环境变量：
  PI_DRIFT_LEDGER=<path>   覆盖账本位置（默认与本脚本同目录）
  PI_DRIFT_SKIP_NPM=1      跳过 npm registry 查询

退出码：0 无漂移 · 1 有漂移 · 2 环境或账本错误
USAGE
}

die() { # $1=消息；退出码 2（环境/账本错误）
  echo "错误：$1" >&2
  exit 2
}

# ── 依赖检查 ────────────────────────────────────────────────────────────────
PY=""
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1; then
    PY="$(command -v "$candidate")"
    break
  fi
done
[ -n "$PY" ] || die "需要 python3（用于读写 JSON 账本），未在 PATH 中找到。"

# ── 基础工具函数 ────────────────────────────────────────────────────────────
hash_file() { # $1=本地文件路径 → stdout sha256
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    "$PY" -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"
  fi
}

fetch_sha() { # $1=url → stdout sha256；网络错误/非 200 时返回 1 且不输出
  local tmp code
  tmp="$(mktemp "${TMPDIR:-/tmp}/pi-drift.XXXXXX")" || return 1
  code="$(curl -sSL --max-time 20 -o "$tmp" -w '%{http_code}' "$1" 2>/dev/null)" || { rm -f "$tmp"; return 1; }
  if [ "$code" != "200" ]; then
    rm -f "$tmp"
    return 1
  fi
  hash_file "$tmp" || { rm -f "$tmp"; return 1; }
  rm -f "$tmp"
}

npm_latest() { # $1=包名 → stdout 最新版本号；失败返回 1
  local out
  if [ "${PI_DRIFT_SKIP_NPM:-0}" = "1" ]; then
    return 1
  fi
  if ! command -v npm >/dev/null 2>&1; then
    return 1
  fi
  if command -v timeout >/dev/null 2>&1; then
    out="$(npm_config_fetch_timeout=25000 npm_config_fetch_retries=1 timeout 30 npm view "$1" version 2>/dev/null)" || return 1
  elif command -v gtimeout >/dev/null 2>&1; then
    out="$(npm_config_fetch_timeout=25000 npm_config_fetch_retries=1 gtimeout 30 npm view "$1" version 2>/dev/null)" || return 1
  else
    out="$(npm_config_fetch_timeout=25000 npm_config_fetch_retries=1 npm view "$1" version 2>/dev/null)" || return 1
  fi
  [ -n "$out" ] || return 1
  printf '%s' "$out"
}

npm_installed() { # $1=包名 → stdout 本地已装版本号；未装/读不到则返回 1
  local out
  out="$("$PY" - "$AGENT_DIR" "$1" <<'PY' 2>/dev/null
import json, os, sys
root, name = sys.argv[1], sys.argv[2]
path = os.path.join(root, "npm", "node_modules", name, "package.json")
if os.path.isfile(path):
    print(json.load(open(path)).get("version", ""))
PY
)" || return 1
  [ -n "$out" ] || return 1
  printf '%s' "$out"
}

# ── 检测模式 ────────────────────────────────────────────────────────────────
# 账本 → TSV；空字段（null）统一输出 "-"，避免与空值混淆
ledger_components() {
  "$PY" - "$LEDGER" 2>/dev/null <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
for c in d.get("components", []):
    row = [
        c.get("local_path") or "-",
        c.get("upstream_url") or "-",
        "1" if c.get("patched") else "0",
        c.get("local_sha256") or "-",
        c.get("upstream_sha256_at_capture") or "-",
    ]
    print("\t".join(row))
PY
}

ledger_npm_packages() {
  "$PY" - "$LEDGER" 2>/dev/null <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
for name, info in (d.get("npm_packages") or {}).items():
    print("\t".join([name, (info or {}).get("installed_version") or "-", "1" if (info or {}).get("patched") else "0"]))
PY
}

run_check() {
  local captured drift=0 missing=0 unknown_up=0 components=0
  captured="$("$PY" - "$LEDGER" 2>/dev/null <<'PY'
import json, sys
print(json.load(open(sys.argv[1], encoding="utf-8")).get("captured_at", "?"))
PY
)" || die "账本 JSON 解析失败（不是合法 JSON）：$LEDGER"

  echo "== 上游漂移报告（$(date '+%F %T')）=="
  echo "快照时点: $captured"
  echo "账本路径: $LEDGER"
  echo

  # --- 文件型组件 ---
  while IFS=$'\t' read -r local_path upstream_url patched snap_local snap_up; do
    [ -n "$local_path" ] || continue
    components=$((components + 1))

    local lp now_local up_state loc_state
    lp="$AGENT_DIR/$local_path"

    if [ -f "$lp" ]; then
      now_local="$(hash_file "$lp")"
    else
      now_local=""
    fi

    if now_up="$(fetch_sha "$upstream_url")" && [ -n "$now_up" ]; then
      if [ "$snap_up" = "-" ]; then
        up_state="❓ 账本无上游哈希"
        unknown_up=$((unknown_up + 1))
      elif [ "$now_up" = "$snap_up" ]; then
        up_state="  上游未动"
      else
        up_state="⬆ 上游有更新"
        drift=1
      fi
    else
      up_state="❓ 上游查询失败"
      unknown_up=$((unknown_up + 1))
    fi

    if [ -z "$now_local" ]; then
      loc_state="⛔ 本机未安装"
      missing=$((missing + 1))
    elif [ "$snap_local" = "-" ]; then
      loc_state="🆕 新装（账本缺本地哈希）"
    elif [ "$now_local" = "$snap_local" ]; then
      if [ "$patched" = "1" ]; then
        loc_state="🔧 补丁在位（快照后未变）"
      else
        loc_state="✅ 本地一致"
      fi
    else
      if [ "$patched" = "1" ]; then
        loc_state="🔧 补丁后又变（对照源码 Local patch N: 重审）"
      else
        loc_state="⚠ 本地意外漂移"
      fi
      drift=1
    fi

    printf "%s  %s  %s\n" "$up_state" "$loc_state" "$local_path"
  done < <(ledger_components)

  [ "$components" -gt 0 ] || echo "  （账本内无文件型组件）"

  # --- npm 包 ---
  echo
  while IFS=$'\t' read -r name ver patched; do
    [ -n "$name" ] || continue
    local latest st
    if latest="$(npm_latest "$name")"; then
      if [ "$ver" = "-" ]; then
        st="❓ 账本无本地版本（registry 最新 ${latest}）"
      elif [ "$latest" = "$ver" ]; then
        st="  已是最新（${ver}）"
      else
        st="⬆ npm 有新版 ${latest}（本地装 ${ver}）"
        drift=1
      fi
    else
      st="❓ npm 查询失败或已跳过"
    fi
    if [ "$patched" = "1" ]; then
      st="$st · 🔧 补丁会被覆写，更新后需重打"
    fi
    printf "%s  %s\n" "$st" "$name"
  done < <(ledger_npm_packages)

  echo
  echo "── 汇总 ──"
  echo "文件型组件 $components 个：其中未安装 $missing 个，上游状态未知 $unknown_up 个"
  if [ "$drift" -eq 0 ]; then
    echo "结论：未检测到漂移。"
  else
    echo "结论：检测到漂移（详见上方 ⬆ / ⚠ / 🔧 行）。"
  fi

  echo
  echo "处理策略：无补丁组件→按 README「借鉴组件」节重建命令重拷；"
  echo "  bash-guard→优先改私有层 .pi-private/local-patches.json 再跑 scripts/apply-local-patches.py 重放（P1/P3/P4/P6 + sha256 校验）；"
  echo "    锚点失配才按源码内 Local patch 标记人工重做，并跑测试（sudo 拦截 / git status 直通 / 对话框交互链）；"
  echo "  npm 有补丁→pi update 后重打补丁（filechanges 的 showWidget 一行改）；"
  echo "  本机未安装→按 README 重建命令补齐后跑 --refresh 重签账本。"

  return "$drift"
}

# ── 刷新模式 ────────────────────────────────────────────────────────────────
# 临时文件用全局名（不用 local）：EXIT trap 在函数返回后触发，
# 引用已出作用域的 local 变量会触发 set -u 的 unbound variable。
DRIFT_SPEC=""
DRIFT_ROWS=""
DRIFT_OUT=""
trap 'rm -f "${DRIFT_SPEC:-}" "${DRIFT_ROWS:-}" "${DRIFT_OUT:-}"' EXIT

run_refresh() {
  local carried_local=0 carried_up=0 carried_npm=0 missing_local=0 failed_up=0
  DRIFT_SPEC="$(mktemp "${TMPDIR:-/tmp}/pi-drift-spec.XXXXXX")" || die "无法创建临时文件"
  DRIFT_ROWS="$(mktemp "${TMPDIR:-/tmp}/pi-drift-rows.XXXXXX")" || die "无法创建临时文件"
  DRIFT_OUT="$(mktemp "${TMPDIR:-/tmp}/pi-drift-ledger.XXXXXX")" || die "无法创建临时文件"

  # 0) 先校验旧账本：坏 JSON 直接拒绝重签，避免洗成空账本
  "$PY" -c 'import json,sys; json.load(open(sys.argv[1], encoding="utf-8"))' "$LEDGER" 2>/dev/null \
    || die "旧账本 JSON 解析失败，拒绝重签（原文件未动）：$LEDGER"

  echo "== 重签快照账本 =="
  echo "账本: $LEDGER"
  echo

  # 1) 采集：旧值一并带出（旧值用于「本机未安装/拉取失败」时无损失地沿用）
  "$PY" - "$LEDGER" 2>/dev/null <<'PY' > "$DRIFT_SPEC" || die "读取旧账本失败"
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
for c in d.get("components", []):
    print("\t".join(["c", c.get("local_path") or "-", c.get("upstream_url") or "-",
                     "1" if c.get("patched") else "0",
                     c.get("local_sha256") or "-", c.get("upstream_sha256_at_capture") or "-"]))
for name, info in (d.get("npm_packages") or {}).items():
    print("\t".join(["n", name, "-", "1" if (info or {}).get("patched") else "0",
                     (info or {}).get("installed_version") or "-", "-"]))
PY

  while IFS=$'\t' read -r kind f1 f2 f3 old_a old_b; do
    [ -n "$kind" ] || continue
    if [ "$kind" = "c" ]; then
      local local_path="$f1" upstream_url="$f2" patched="$f3"
      local local_sha="-" upstream_sha="-" note=""
      if [ -f "$AGENT_DIR/$local_path" ]; then
        local_sha="$(hash_file "$AGENT_DIR/$local_path")"
      else
        missing_local=$((missing_local + 1))
        if [ "$old_a" != "-" ]; then
          local_sha="$old_a"
          carried_local=$((carried_local + 1))
          note="  ⛔ 本机未安装，⤵ 沿用旧快照的本地哈希（勿在本机 --refresh 后据此判断其他机器）"
        else
          note="  ⛔ 本机未安装，旧账本也无本地哈希 → 记 null"
        fi
      fi
      if upstream_sha="$(fetch_sha "$upstream_url")" && [ -n "$upstream_sha" ]; then
        :
      else
        failed_up=$((failed_up + 1))
        if [ "$old_b" != "-" ]; then
          upstream_sha="$old_b"
          carried_up=$((carried_up + 1))
          note="${note}  ❓ 上游拉取失败，⤵ 沿用旧上游哈希"
        else
          note="${note}  ❓ 上游拉取失败，旧账本也无上游哈希 → 记 null"
        fi
      fi
      echo "  · ${local_path}${note}"
      printf 'c\t%s\t%s\t%s\t%s\t%s\n' "$local_path" "$upstream_url" "$patched" "$local_sha" "$upstream_sha" >> "$DRIFT_ROWS"
    elif [ "$kind" = "n" ]; then
      local name="$f1" patched="$f3" installed="" note=""
      installed="$(npm_installed "$name")" || installed=""
      if [ -z "$installed" ]; then
        if [ "$old_a" != "-" ]; then
          installed="$old_a"
          carried_npm=$((carried_npm + 1))
          note="  ⤵ 本机未装该包，沿用旧账本版本"
        else
          installed="$(npm_latest "$name")" || installed="-"
          if [ "$installed" = "-" ]; then
            note="  ❓ 本地与 registry 均不可得 → 记 null"
          fi
        fi
      fi
      echo "  · npm   ${name} (本地 ${installed})${note}"
      printf 'n\t%s\t-\t%s\t%s\t-\n' "$name" "$patched" "$installed" >> "$DRIFT_ROWS"
    fi
  done < "$DRIFT_SPEC"

  # 采集为空说明账本结构异常，宁可不写也不洗白
  if [ ! -s "$DRIFT_ROWS" ]; then
    die "采集结果为空（旧账本里既无组件也无 npm 包？），拒绝写出空账本"
  fi

  echo
  # 2) 由采集结果重新生成 JSON（kinds 顺序：组件在前，npm 在后）
  "$PY" - "$DRIFT_ROWS" "$(date '+%Y-%m-%dT%H:%M:%S')" > "$DRIFT_OUT" <<'PY' || die "生成账本失败"
import json, sys

rows_path, captured_at = sys.argv[1], sys.argv[2]
components, npm_packages = [], {}

with open(rows_path, encoding="utf-8") as fh:
    for line in fh:
        parts = line.rstrip("\n").split("\t")
        if len(parts) < 6:
            continue
        kind, f1, f2, patched, sha_a, sha_b = parts[:6]
        if kind == "c":
            components.append({
                "local_path": f1,
                "upstream_url": f2,
                "patched": patched == "1",
                "local_sha256": None if sha_a == "-" else sha_a,
                "upstream_sha256_at_capture": None if sha_b == "-" else sha_b,
            })
        elif kind == "n":
            npm_packages[f1] = {
                "installed_version": None if sha_a == "-" else sha_a,
                "patched": patched == "1",
            }

doc = {"captured_at": captured_at, "components": components, "npm_packages": npm_packages}
print(json.dumps(doc, ensure_ascii=False, indent=2))
PY

  # 3) 校验后才落地（原子替换），避免写坏账本
  "$PY" -c 'import json,sys; json.load(open(sys.argv[1], encoding="utf-8"))' "$DRIFT_OUT" 2>/dev/null \
    || die "新账本 JSON 校验失败，已保留原文件"
  # mktemp 建的是 600，mv 会把它带成新权限；先对齐旧账本的权限位再替换
  local old_mode
  old_mode="$(stat -f '%Lp' "$LEDGER" 2>/dev/null || stat -c '%a' "$LEDGER" 2>/dev/null || echo 644)"
  chmod "$old_mode" "$DRIFT_OUT" 2>/dev/null || true
  mv "$DRIFT_OUT" "$LEDGER" || die "写入 $LEDGER 失败"

  echo "已重签：$LEDGER"
  echo "  captured_at = $(date '+%Y-%m-%dT%H:%M:%S')"
  echo "  patched 标记沿用旧账本（人工判断），本脚本不会自动改写。"
  if [ "$missing_local" -gt 0 ] || [ "$failed_up" -gt 0 ]; then
    echo "  ⚠ 未安装 $missing_local 个组件 · 上游拉取失败 $failed_up 个" >&2
    echo "  ⚠ 这些条目沿用旧快照值（本地哈希 ${carried_local} · 上游哈希 ${carried_up} · npm 版本 ${carried_npm}），" >&2
    echo "     而非记 null——账本是多机共享的，别让缺组件的机器把别人的基准洗掉。" >&2
    echo "     要拿到本机真实值：先按 README 重建缺失组件，再在本机重跑 --refresh。" >&2
  fi
  return 0
}

# ── 入口 ────────────────────────────────────────────────────────────────────
case "${1:-}" in
  ""|--check) MODE="check" ;;
  --refresh) MODE="refresh" ;;
  -h|--help) usage; exit 0 ;;
  *) echo "错误：未知参数 $1" >&2; echo >&2; usage >&2; exit 2 ;;
esac

[ -f "$LEDGER" ] || die "找不到账本：$LEDGER"

if [ "$MODE" = "refresh" ]; then
  run_refresh
  exit $?
fi

run_check
exit $?
