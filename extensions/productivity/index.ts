/**
 * Productivity suite entry point (Plan C).
 *
 * Composes six independent modules so each one can be disabled
 * individually by commenting out its line:
 *
 *   session-name.ts  - auto-names sessions from the first user message
 *   auto-commit.ts   - git commit on session shutdown
 *   notify.ts        - desktop notification when the agent finishes
 *   model-status.ts  - current model in the status bar
 *   todo.ts          - LLM-callable todo tool + /todos UI (official example)
 *   footer.ts        - custom footer: tokens / cost / git branch / model
 *
 * Install: this whole directory lives under ~/.pi/agent/extensions/,
 * so pi auto-discovers it. Use /reload to hot-reload after edits.
 * Kill switches: PI_NO_AUTO_COMMIT=1 (skip auto commit),
 * PI_NO_NOTIFY=1 (skip notifications).
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

import sessionName from "./session-name.ts";
import autoCommit from "./auto-commit.ts";
import notify from "./notify.ts";
import modelStatus from "./model-status.ts";
import todo from "./todo.ts";
import footer from "./footer.ts";

export default function (pi: ExtensionAPI) {
	sessionName(pi);
	autoCommit(pi);
	notify(pi);
	modelStatus(pi);
	todo(pi);
	footer(pi);

	console.log("[productivity] 6 modules loaded (session-name, auto-commit, notify, model-status, todo, footer)");
}
