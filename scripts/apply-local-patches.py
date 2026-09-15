#!/usr/bin/env python3
"""本地补丁应用器 —— 从上游拷贝重建我们的定制（幂等，可重放）。

用途：新机器按「借鉴组件」节拷来**上游原版**后，用本脚本把本机定制层打回去；
校验每个目标的最终 sha256 是否等于私有层记录的值。日常不需要跑——
私有层（pi-config-private）里存的是**已打好补丁的成品**，checkout 即得。

为什么补丁正文不在这里：
  上游 amosblomqvist/pi-config 无 LICENSE，正文必须逐字等于上游才能锚定替换，
  内嵌即等于在公开仓库再分发上游源码。故正文存放在私密层的
  `.pi-private/local-patches.json`，公开侧只留 patch id / 目标文件 / 目标
  sha256 / 人类可读描述 —— 重建能力不丢，正文不外泄。

补丁正文来源（按序探测，前者优先）：
  1. --patches <path>
  2. $PI_LOCAL_PATCHES
  3. <agentDir>/.pi-private/local-patches.json      ← 双层仓库的标准位置
  4. ~/.pi-config-private/.pi-private/local-patches.json   ← 独立 clone 的备选
  5. ~/pi-config-private/.pi-private/local-patches.json
缺失时会打印获取命令，不会静默跳过。

用法：
  python3 scripts/apply-local-patches.py              # 应用（已应用则跳过）并校验哈希
  python3 scripts/apply-local-patches.py --check      # 只报告状态，不写文件
  python3 scripts/apply-local-patches.py --list       # 列出补丁清单（含描述）
  python3 scripts/apply-local-patches.py --root /tmp/x   # 在别的树里演练（沙箱）

退出码：0 = 全部到位且校验通过 · 1 = 有失败（缺目标/锚点失配/哈希不符）· 2 = 用法或环境错误
"""
import argparse
import hashlib
import json
import os
import pathlib
import sys

SCRIPT = pathlib.Path(__file__).resolve()
AGENT = SCRIPT.parent.parent
LEDGER = AGENT / "scripts" / "upstream-snapshot.json"

PRIVATE_REPO = "https://github.com/SuTang-vain/pi-config-private.git"


def die(msg, code=2):
    print(f"错误：{msg}", file=sys.stderr)
    sys.exit(code)


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def find_patches(explicit):
    """显式指定的路径不参与回退：给了却不存在就直接报错，避免静默用了别处的旧正文。"""
    if explicit:
        p = pathlib.Path(explicit).expanduser()
        if not p.is_file():
            die(f"--patches 指定的文件不存在：{p}")
        return p, [p]
    env = os.environ.get("PI_LOCAL_PATCHES")
    if env:
        p = pathlib.Path(env).expanduser()
        if not p.is_file():
            die(f"$PI_LOCAL_PATCHES 指定的文件不存在：{p}")
        return p, [p]
    candidates = [
        AGENT / ".pi-private" / "local-patches.json",
        pathlib.Path.home() / ".pi-config-private" / ".pi-private" / "local-patches.json",
        pathlib.Path.home() / "pi-config-private" / ".pi-private" / "local-patches.json",
    ]
    for c in candidates:
        if c.is_file():
            return c, candidates
    return None, candidates


def load_ledger_hashes():
    """从公开账本取「本机定制后」的权威 sha256；缺失不影响运行（仅少一道交叉校验）。"""
    try:
        doc = json.loads(LEDGER.read_text(encoding="utf-8"))
    except Exception:
        return {}
    out = {}
    for c in doc.get("components", []) or []:
        if c.get("patched") and c.get("local_sha256"):
            out[c.get("local_path")] = c["local_sha256"]
    return out


def main():
    ap = argparse.ArgumentParser(
        description="从上游重放本机定制补丁（幂等 + sha256 校验）",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument("--check", action="store_true", help="只报告状态，不写文件")
    ap.add_argument("--list", action="store_true", help="列出补丁清单后退出")
    ap.add_argument("--root", default=str(AGENT), help="目标树根（默认 agent 目录；可用于沙箱演练）")
    ap.add_argument("--patches", default=None, help="直接指定 local-patches.json")
    args = ap.parse_args()

    patches_path, candidates = find_patches(args.patches)
    if patches_path is None:
        print("找不到补丁正文（local-patches.json）。已探测：", file=sys.stderr)
        for c in candidates:
            print(f"  - {c}", file=sys.stderr)
        print("\n私密层需要先接入（标准做法：独立 git-dir + 共享工作树）：", file=sys.stderr)
        print(f"  git clone --bare {PRIVATE_REPO} ~/.pi/agent-private.git", file=sys.stderr)
        print("  git --git-dir=~/.pi/agent-private.git config core.worktree ~/.pi/agent", file=sys.stderr)
        print("  git --git-dir=~/.pi/agent-private.git config --bool core.bare false", file=sys.stderr)
        print("  git --git-dir=~/.pi/agent-private.git checkout -f main", file=sys.stderr)
        return 2

    try:
        doc = json.loads(patches_path.read_text(encoding="utf-8"))
    except Exception as exc:
        die(f"补丁文件无法解析：{patches_path}（{exc}）")

    patches = doc.get("patches") or []
    targets = {t.get("file"): t.get("sha256_after") for t in (doc.get("targets") or [])}
    if not patches:
        die(f"补丁文件里没有 patches 条目：{patches_path}")

    root = pathlib.Path(args.root).expanduser().resolve()
    print(f"补丁正文: {patches_path}")
    print(f"目标树  : {root}")
    print(f"补丁数  : {len(patches)}\n")

    if args.list:
        for p in patches:
            print(f"  {p.get('id'):24} {p.get('file')}")
            if p.get("desc"):
                print(f"      {p['desc']}")
        return 0

    # 逐条打补丁，同时按目标文件聚合状态（哈希校验必须等一个文件的补丁全到位才有意义）
    state = {}
    totals = {"applied": 0, "skipped": 0, "pending": 0, "runtime": 0, "failed": 0}
    for p in patches:
        pid = p.get("id", "?")
        rel = p.get("file", "")
        st = state.setdefault(rel, {"applied": 0, "skipped": 0, "pending": 0, "runtime": 0, "failed": 0})
        fp = root / rel
        if not fp.is_file():
            # node_modules 下的目标需先跑 npm install / pi install —— 刚接入的新机器上必然缺失，
            # 报成失败会让人以为接入坏了。归入「运行时未安装」信息态，不计入失败。
            if "node_modules/" in rel:
                print(f"⏳ {pid}: 目标未安装 {rel}（运行时依赖，先跑 npm install / pi install）")
                st["runtime"] += 1
                totals["runtime"] += 1
            else:
                print(f"✗ {pid}: 目标不存在 {rel}（先按 README「借鉴组件」节拷上游）")
                st["failed"] += 1
                totals["failed"] += 1
            continue
        text = fp.read_text(encoding="utf-8")
        if p.get("marker") and p["marker"] in text:
            print(f"✓ {pid}: 已应用（跳过）")
            st["skipped"] += 1
            totals["skipped"] += 1
            continue
        if p.get("find") not in text:
            print(f"✗ {pid}: 上游锚点失配 —— 上游可能已更新，需按 README「本地补丁」各节人工重做")
            st["failed"] += 1
            totals["failed"] += 1
            continue
        if args.check:
            print(f"? {pid}: 待应用")
            st["pending"] += 1
            totals["pending"] += 1
            continue
        fp.write_text(text.replace(p["find"], p["replace"], 1), encoding="utf-8")
        print(f"✓ {pid}: 已应用")
        st["applied"] += 1
        totals["applied"] += 1

    # ── 哈希校验：仅对「全部补丁位」的目标做，避免 --check 下把未打补丁的原版误报为失败 ──
    ledger = load_ledger_hashes()
    print()
    failed = totals["failed"]
    verified = 0
    for rel, expect in targets.items():
        st = state.get(rel)
        fp = root / rel
        if st is None or not fp.is_file():
            continue
        if st["runtime"]:
            print(f"· {rel}: 运行时未安装，未做校验（补装后重跑即可）")
            continue
        if st["failed"]:
            print(f"· {rel}: 因目标缺失或锚点失配，未做校验")
            continue
        if st["pending"]:
            print(f"· {rel}: 尚有 {st['pending']} 条待应用（--check 只报告），未做校验")
            continue
        if not expect:
            print(f"· {rel}: 私有层未记录 sha256，跳过校验")
            continue
        got = sha256(fp)
        if got != expect:
            print(f"✗ 校验失败 {rel}\n    期望 {expect}\n    实际 {got}")
            failed += 1
            continue
        verified += 1
        extra = ""
        if rel in ledger:
            extra = "（与公开账本一致）" if ledger[rel] == expect else "（⚠ 与公开账本不一致，需重签账本）"
        print(f"✓ 校验通过 {rel}{extra}")

    print(f"\n应用 {totals['applied']} · 跳过 {totals['skipped']} · 待应用 {totals['pending']} · "
          f"未安装(运行时) {totals['runtime']} · 校验通过 {verified} · 失败 {failed}")
    if totals["runtime"]:
        print("注意：「未安装(运行时)」不是错误——先 cd extensions/bash-guard && npm install；"
              "filechanges 需先 pi install 该包，补装后重跑本脚本。")
    if failed:
        print("提示：锚点失配时不要硬改——先跑 scripts/check-upstream-drift.sh 看上游是否已更新。")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
