/**
 * Auto-Commit on Exit — 安全版 v2
 *
 * 只提交**本次会话中被 `edit` / `write` 实际触及的文件**，并**按这些文件各自所在的
 * 仓库分别提交**。
 *
 * 为什么从「会话 cwd 的仓库」改成「文件所在仓库」：
 *   原实现用会话 cwd 解析仓库（`git rev-parse`），于是
 *     - cwd 不是仓库时直接 return ⇒ 从不提交（实测：从非仓库目录跑 pi 去改
 *       ~/.pi/agent 里的配置，仓库历史里 `[pi] 改动` 提交数为 0）；
 *     - 只有 cwd 仓库内的文件会被提交，跨仓库的改动被静默丢弃。
 *   现在对每个被触及文件各自向上找 toplevel，按仓库分组提交；不在任何仓库里的文件跳过。
 *
 * 一如既往避免的三个风险（仍然不做 `git add -A`）：
 *   1. `git add -A` 会把未跟踪文件一并提交——`.env`、构建产物、临时文件都进历史；
 *   2. 提交信息取自「最后一条助手回复的前 50 字」，可能把对话内容永久写进 git 历史；
 *   3. 在任何 git 仓库里都会触发，包括用户并未打算提交的仓库。
 *
 * 现行为：
 *   - 无写入则不提交；
 *   - 每个仓库各提交一次，信息为 `[pi] 改动 N 个文件：<文件名>`（可追溯、不含对话内容）；
 *   - `git add` 被拒（例如路径被 .gitignore 忽略）→ 跳过该仓库并提示，**不用 `-f` 强加**；
 *   - 该仓库正在 merge / rebase（存在 MERGE_HEAD / REBASE_HEAD）→ 跳过，避免插入提交打乱序列。
 *
 * Kill switch: PI_NO_AUTO_COMMIT=1
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { existsSync } from "node:fs";
import { dirname, isAbsolute, resolve } from "node:path";

export default function (pi: ExtensionAPI) {
  /** 本次会话中被 edit/write 触及的文件的绝对路径 */
  const touched = new Set<string>();

  pi.on("tool_call", async (event) => {
    if (event.toolName !== "edit" && event.toolName !== "write") return;
    const p = (event.input as { path?: unknown } | undefined)?.path;
    if (typeof p === "string" && p.trim()) {
      touched.add(isAbsolute(p) ? p : resolve(process.cwd(), p));
    }
  });

  /** 向上找文件所在仓库的 toplevel；不在任何仓库里则返回 undefined（按目录缓存）。 */
  const rootCache = new Map<string, string | undefined>();
  async function repoRootFor(filePath: string): Promise<string | undefined> {
    const dir = dirname(filePath);
    if (rootCache.has(dir)) return rootCache.get(dir);
    const { stdout, code } = await pi.exec("git", ["-C", dir, "rev-parse", "--show-toplevel"]);
    const root = code === 0 && stdout.trim() ? stdout.trim() : undefined;
    rootCache.set(dir, root);
    return root;
  }

  /** merge / rebase 进行中不插入提交，避免打乱序列。 */
  async function hasPendingOperation(root: string): Promise<boolean> {
    for (const ref of ["MERGE_HEAD", "REBASE_HEAD", "CHERRY_PICK_HEAD"]) {
      const { code } = await pi.exec("git", ["-C", root, "rev-parse", "-q", "--verify", ref]);
      if (code === 0) return true;
    }
    return false;
  }

  pi.on("session_shutdown", async (_event, ctx) => {
    if (process.env.PI_NO_AUTO_COMMIT === "1") return;

    // 只保留仍存在的文件（已删除的文件不自动暂存）
    const paths = [...touched].filter((p) => existsSync(p));
    if (paths.length === 0) return;

    // 按「文件所在仓库」分组
    const byRepo = new Map<string, string[]>();
    for (const p of paths) {
      const root = await repoRootFor(p);
      if (!root) continue; // 不在任何 git 仓库里
      const list = byRepo.get(root);
      if (list) list.push(p);
      else byRepo.set(root, [p]);
    }
    if (byRepo.size === 0) return;

    for (const [root, repoPaths] of byRepo) {
      if (await hasPendingOperation(root)) {
        if (ctx.hasUI) ctx.ui.notify(`Auto-commit skipped ${root}: merge/rebase in progress`, "warning");
        continue;
      }

      const { code: codeAdd } = await pi.exec("git", ["-C", root, "add", "--", ...repoPaths]);
      if (codeAdd !== 0) {
        if (ctx.hasUI) {
          ctx.ui.notify(`Auto-commit skipped ${root}: git add refused (路径被忽略？未用 -f 强加)`, "error");
        }
        continue;
      }

      const { stdout: staged } = await pi.exec("git", ["-C", root, "diff", "--cached", "--name-only"]);
      const names = staged.split("\n").map((s) => s.trim()).filter(Boolean);
      if (names.length === 0) continue; // 内容没变化 → 不产生空提交

      const head = names.slice(0, 3).join(", ");
      const more = names.length > 3 ? ` 等 ${names.length} 个文件` : "";
      const message = `[pi] 改动 ${names.length} 个文件：${head}${more}`;

      const { code } = await pi.exec("git", ["-C", root, "commit", "-m", message]);
      if (ctx.hasUI) {
        if (code === 0) ctx.ui.notify(`Auto-committed ${names.length} file(s) in ${root}`, "info");
        else ctx.ui.notify(`Auto-commit failed in ${root}; check git state`, "error");
      }
    }
  });
}
