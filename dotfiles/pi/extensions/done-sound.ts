import type { ExtensionAPI } from "@wealthsimple/pi-coding-agent";
import { execFile } from "child_process";
import { basename } from "path";
import { homedir } from "os";
import { join } from "path";

function sessionLabel(sm: {
  getSessionName(): string | undefined;
  getSessionId(): string;
}): string {
  const name = sm.getSessionName();
  if (name) return name;
  const cwd = basename(process.cwd());
  if (cwd) return cwd;
  return sm.getSessionId().slice(0, 8);
}

// Alert when the agent finishes responding (task done):
//   - plays a sound (macOS: afplay + a built-in system sound)
//   - shows a borderless banner at the top-right of the screen
// Swap SOUND to any file in /System/Library/Sounds (Blow, Glass, Hero, Ping, ...).
const SOUND = "/System/Library/Sounds/Blow.aiff";
const BANNER = join(homedir(), ".pi/agent/scripts/banner.js");
const SECONDS = "4";

export default function (pi: ExtensionAPI) {
  pi.on("agent_end", async (_event, ctx) => {
    const message = `✓ Task done · ${sessionLabel(ctx.sessionManager)}`;
    execFile("afplay", [SOUND], () => {});
    execFile("osascript", ["-l", "JavaScript", BANNER, message, SECONDS], () => {});
  });
}
