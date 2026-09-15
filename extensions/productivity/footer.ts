/**
 * Custom Footer extension — tokens / cost / git branch / model.
 *
 * Auto-enabled at session start in TUI mode; /footer toggles it.
 * Token stats come from assistant message usage on the current branch;
 * the git branch comes from footerData (live, updates on branch change).
 */

import type { AssistantMessage } from "@earendil-works/pi-ai";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";

export default function (pi: ExtensionAPI) {
	let enabled = false;

	const enable = (ctx: ExtensionContext) => {
		if (enabled || ctx.mode !== "tui") return;
		enabled = true;

		ctx.ui.setFooter((tui, theme, footerData) => {
			const unsub = footerData.onBranchChange(() => tui.requestRender());

			return {
				dispose: unsub,
				invalidate() {},
				render(width: number): string[] {
					let input = 0;
					let output = 0;
					let cost = 0;
					for (const e of ctx.sessionManager.getBranch()) {
						if (e.type === "message" && e.message.role === "assistant") {
							const m = e.message as AssistantMessage;
							input += m.usage.input;
							output += m.usage.output;
							cost += m.usage.cost.total;
						}
					}

					const branch = footerData.getGitBranch();
					const fmt = (n: number) => (n < 1000 ? `${n}` : `${(n / 1000).toFixed(1)}k`);

					const left = theme.fg("dim", `↑${fmt(input)} ↓${fmt(output)} $${cost.toFixed(3)}`);
					const branchStr = branch ? ` (${branch})` : "";
					const right = theme.fg("dim", `${ctx.model?.id || "no-model"}${branchStr}`);

					const pad = " ".repeat(Math.max(1, width - visibleWidth(left) - visibleWidth(right)));
					return [truncateToWidth(left + pad + right, width)];
				},
			};
		});
	};

	pi.on("session_start", async (_event, ctx) => {
		enable(ctx);
	});

	pi.registerCommand("footer", {
		description: "Toggle the custom footer (tokens / cost / branch / model)",
		handler: async (_args, ctx) => {
			if (!enabled) {
				enable(ctx);
				ctx.ui.notify("Custom footer enabled", "info");
			} else {
				ctx.ui.setFooter(undefined);
				enabled = false;
				ctx.ui.notify("Default footer restored", "info");
			}
		},
	});
}
