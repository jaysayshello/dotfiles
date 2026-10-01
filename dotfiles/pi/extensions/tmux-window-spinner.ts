/**
 * Tmux Window Spinner
 *
 * Renames the tmux window on pi's pane with a braille spinner while the agent
 * is working, then restores the base name when idle. Shows up in the tmux
 * status bar at the top.
 *
 * No-op when not running inside tmux.
 */

import { execFile } from "node:child_process";
import path from "node:path";
import type { ExtensionAPI, ExtensionContext } from "@wealthsimple/pi-coding-agent";

const BRAILLE_FRAMES = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];
const INTERVAL_MS = 120;

const pane = process.env.TMUX_PANE;
const inTmux = Boolean(process.env.TMUX && pane);

function baseName(pi: ExtensionAPI): string {
	return pi.getSessionName() || path.basename(process.cwd());
}

function renameWindow(name: string): void {
	if (!inTmux) return;
	execFile("tmux", ["rename-window", "-t", pane as string, name], () => {});
}

export default function (pi: ExtensionAPI) {
	let timer: ReturnType<typeof setInterval> | null = null;
	let frameIndex = 0;

	function stopAnimation() {
		if (timer) {
			clearInterval(timer);
			timer = null;
		}
		frameIndex = 0;
		renameWindow(baseName(pi));
	}

	function startAnimation() {
		if (!inTmux) return;
		stopAnimation();
		timer = setInterval(() => {
			const frame = BRAILLE_FRAMES[frameIndex % BRAILLE_FRAMES.length];
			renameWindow(`${frame} ${baseName(pi)}`);
			frameIndex++;
		}, INTERVAL_MS);
	}

	pi.on("agent_start", async (_event, _ctx: ExtensionContext) => {
		startAnimation();
	});

	pi.on("agent_end", async (_event, _ctx: ExtensionContext) => {
		stopAnimation();
	});

	pi.on("session_shutdown", async (_event, _ctx: ExtensionContext) => {
		stopAnimation();
		if (inTmux) {
			execFile("tmux", ["set-window-option", "-t", pane as string, "automatic-rename", "on"], () => {});
		}
	});
}
