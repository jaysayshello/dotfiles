# Third-party files

Two files here are modified copies of MIT-licensed upstream work, vendored so
local fixes survive a package update. Both keep their upstream copyright.

## extensions/session-recap.ts

From [@tmustier/pi-session-recap](https://www.npmjs.com/package/@tmustier/pi-session-recap)
0.5.0, MIT. Local changes:

- recap text uses ANSI palette white instead of the theme's `dim` token, which
  reads much darker than Claude Code beside the same prompt border
- away delay cut from 90s to 10s
- drafting model defaults to `litellm/deepseek-v4.1-flash`
- an unresolvable `recap-model` override falls through to automatic selection
  rather than the session's active model, so a typo cannot draft every recap on
  a large model
- a zero-width-space row pads the bottom of the widget

## scripts/cc-patches/status-line.ts

From [better-claude-code-ui](https://www.npmjs.com/package/better-claude-code-ui)
0.1.7, MIT. The status line is repainted with ANSI palette colours (bright
magenta model, bright cyan path, green/yellow/red context by how much is left)
instead of hardcoded hex, so it tracks the terminal theme the way Claude Code's
own bar does.

This copy exists because the file lives in `node_modules` and is overwritten by
`pi update --extensions`. Run `cc-patches/reapply.sh` after an update.
