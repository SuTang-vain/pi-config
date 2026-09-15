/**
 * Auto-Commit on Exit — 安全版
 *
 * 只提交**本次会话中被 `edit` / `write` 实际触及的文件**。
 *
 * 为什么改（原实现的三个风险）：
 *   1. `git add -A` 会把未跟踪文件一并提交——`.env`、构建产物、临时文件
 *      都可能进入版本历史；
 *   2. 提交信息取自「最后一条助手回复的前 50 字」，可能把对话内容
 *      （含敏感信息）永久写进 git 历史；
 *   3. 在任何 git 仓库里都会触发，包括用户并未打算提交的仓库。
 *
 * 现行为：无写入则不提交；提交信息为「改动 N 个文件：<文件名>」，
 * 可追溯且不含对话内容。
 *
 * Kill switch: PI_NO_AUTO_COMMIT=1
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { existsSync } from "node:fs";
import { resolve, relative, isAbsolute } from "node:path";

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

  pi.on("session_shutdown", async (_event, ctx) => {
    if (process.env.PI_NO_AUTO_COMMIT === "1") return;
    if (touched.size === 0) return; // 本次会话没写过文件

    const { stdout: inRepo, code: codeRepo } = await pi.exec(
      "git", ["rev-parse", "--is-inside-work-tree"],
    );
    if (codeRepo !== 0 || inRepo.trim() !== "true") return;

    const { stdout: top, code: codeTop } = await pi.exec(
      "git", ["rev-parse", "--show-toplevel"],
    );
    if (codeTop !== 0) return;
    const root = top.trim();

    // 只保留：仓库内 + 文件仍存在（已删除的文件不自动暂存）
    const paths = [...touched]
      .filter((p) => existsSync(p))
      .filter((p) => {
        const rel = relative(root, p);
        return rel !== "" && !rel.startsWith("..") && !isAbsolute(rel);
      });
    if (paths.length === 0) return;

    await pi.exec("git", ["add", "--", ...paths]);

    const { stdout: staged } = await pi.exec(
      "git", ["diff", "--cached", "--name-only"],
    );
    const names = staged.split("\n").map((s) => s.trim()).filter(Boolean);
    if (names.length === 0) return; // 内容没变化 → 不产生空提交

    const head = names.slice(0, 3).join(", ");
    const more = names.length > 3 ? ` 等 ${names.length} 个文件` : "";
    const message = `[pi] 改动 ${names.length} 个文件：${head}${more}`;

    const { code } = await pi.exec("git", ["commit", "-m", message]);
    if (ctx.hasUI) {
      if (code === 0) {
        ctx.ui.notify(`Auto-committed ${names.length} file(s)`, "info");
      } else {
        // pre-commit hook 失败等 — 暴露而不是吞掉
        ctx.ui.notify("Auto-commit failed; check git state", "error");
      }
    }
  });
}
