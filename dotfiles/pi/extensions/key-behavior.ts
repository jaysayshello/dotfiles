import type { ExtensionAPI, ExtensionContext } from "@wealthsimple/pi-coding-agent";
import { CustomEditor } from "@wealthsimple/pi-coding-agent";

/**
 * Custom key behavior for the input editor:
 *
 *   Ctrl+C   - while a job is running, stop it (abort). When idle, keeps the
 *              default clear/exit behavior.
 *   Escape   - while a job is running, stop it AND put the prompt back into
 *              the editor (restores queued messages too, like the default).
 *   Escape×2 - while idle with text in the editor, clear all typed text.
 *              (An empty editor keeps the default double-escape behavior.)
 *
 * Implemented as a custom editor component because `escape` and `ctrl+c` are
 * reserved keybindings that extension shortcuts cannot override, and because
 * double-press / "restore the in-flight prompt" are stateful behaviors that
 * keybindings.json can't express.
 */
const DOUBLE_ESCAPE_MS = 500;

export default function (pi: ExtensionAPI) {
  let ctxRef: ExtensionContext | null = null;
  let lastPrompt = "";
  let lastEscape = 0;
  let installed = false;

  const isIdle = () => (ctxRef ? ctxRef.isIdle() : true);
  const abort = () => ctxRef?.abort();

  // Remember the most recent submitted prompt so escape can restore it.
  pi.on("input", (event, ctx) => {
    ctxRef = ctx;
    if (event.text && event.text.trim()) lastPrompt = event.text;
  });

  class KeyBehaviorEditor extends CustomEditor {
    handleInput(data: string) {
      // --- Escape (app.interrupt) --------------------------------------
      if (this.keybindings.matches(data, "app.interrupt")) {
        // Let the parent handle escape while the autocomplete popup is open.
        if (this.isShowingAutocomplete()) {
          super.handleInput(data);
          return;
        }

        if (!isIdle()) {
          // Job running: stop it and restore the prompt into the editor.
          // onEscape (the default handler) aborts and restores any queued
          // steering/follow-up messages; if nothing came back, drop in the
          // last submitted prompt.
          this.onEscape?.();
          if (!this.getText().trim() && lastPrompt) this.setText(lastPrompt);
          lastEscape = 0;
          return;
        }

        // Idle with typed text: require a second escape to clear it.
        if (this.getText().length > 0) {
          const now = Date.now();
          if (now - lastEscape < DOUBLE_ESCAPE_MS) {
            this.setText("");
            lastEscape = 0;
          } else {
            lastEscape = now;
          }
          return;
        }

        // Idle and empty: keep the default double-escape behavior.
        lastEscape = Date.now();
        this.onEscape?.();
        return;
      }

      // --- Ctrl+C (app.clear) ------------------------------------------
      if (this.keybindings.matches(data, "app.clear") && !isIdle()) {
        // Job running: stop it instead of clearing/exiting.
        abort();
        return;
      }

      super.handleInput(data);
    }
  }

  const install = (ctx: ExtensionContext) => {
    ctxRef = ctx;
    if (installed || !ctx.ui?.setEditorComponent) return;
    ctx.ui.setEditorComponent(
      (tui, theme, keybindings) => new KeyBehaviorEditor(tui, theme, keybindings)
    );
    installed = true;
  };

  pi.on("session_start", (_event, ctx) => install(ctx));
}
