---
name: slack-writer
description: >
  Write, draft, or reformat messages for Slack using correct Slack mrkdwn syntax,
  at a chosen level from 1 (quite verbose, full context) to 5 (extremely simple,
  fewest words), with any explanation written in ASD-STE100 Simplified Technical
  English. Use this skill whenever the user asks you to write, draft, compose,
  format, shorten, expand, or rewrite anything for Slack: announcements, incident
  updates, standups, team messages, release notes, retrospectives, status updates,
  replies that explain a cause or a decision, or any other content destined for a
  Slack channel or DM. Triggers on phrases like "write this for Slack", "draft a
  Slack message", "level 4 slack post", "make this slack message simpler", "how
  would I post this in Slack", or any time the target audience/medium is Slack.
  Always use this skill proactively when Slack is the destination.
---

# Slack Writer

## Read this first (non-negotiable)

**Before drafting a single line, read these in full:**

1. `~/.claude/skills/_voice.md`: the canonical voice doc. Warm but brief, plain words, concrete details, no em dashes, banned-words list, patterns to avoid. (Optional: if that file does not exist on this machine, use the hard rules and the voice section in this file.)
2. `~/.claude/tropes.md`: the AI writing tropes to avoid (negative parallelism, punchy fragments, preambles, compulsive counting, rule of three, and the rest). Check the draft against it before saving. (Optional: skip it if the file does not exist.)
3. `references/ste100.md` (in this skill's directory), if any part of the message explains something. See "Explanations: ASD-STE100" below.

Every Slack message you write must follow these. This is not optional and not a "if you have time" step. Skipping them produces messages that miss the voice and get rejected. Read them, then draft.

**Precedence.** If anything in this file conflicts with `_voice.md`, `_voice.md` wins, with one exception: in explanation text, STE wins. That means no contractions and no fragments in explanation sentences, even though `_voice.md` allows both. Every other `_voice.md` rule (no em dashes, banned words, no hype, Canadian spelling) still applies to STE text.

---

Write Slack messages using correct **mrkdwn** syntax. Slack's own dialect differs from standard Markdown in important ways. The output should be paste-ready with no reformatting needed.

## Level (1 to 5)

Every message has a level. The level sets how much to write and how simple to keep it. 5 is extremely simple. 1 is quite verbose.

**Find the level:**

- An explicit number wins: "level 4", "L2", "a 5", "4/5", "simplicity 3", or a bare number right after the skill name.
- Clear length words map to a level when there is no number: "one-liner", "tl;dr", "super short" → 5. "short", "brief" → 4. "detailed", "more context" → 2. "full write-up", "explain everything" → 1.
- Otherwise use **3**. Do not pick a level from the message type; the user wants the default to be predictable and to move it themselves.

| Level | Feel | Length (prose words, excluding code, commands, URLs) | Sentence cap | What goes in |
|---|---|---|---|---|
| 5 | Extremely simple | 1 to 2 sentences, 30 words or fewer | 12 words | The one fact the reader must know and the one thing they must do. No background, no reason unless the action makes no sense without it. Only the most common words; spell out or drop acronyms that the channel might not know. |
| 4 | Simple | 60 words or fewer | 15 words | The fact, who it affects, and the action. A one-sentence reason if it changes what the reader does. |
| 3 | Balanced (default) | 120 words or fewer | STE caps (20 procedural, 25 descriptive) | The templates below as written. A short reason where it helps. |
| 2 | Detailed | 200 words or fewer | STE caps | Level 3 plus background, the reason for the change or decision, what happens next, and the useful links. |
| 1 | Quite verbose | 350 words or fewer | STE caps | Full context: background, reason, options that were considered, steps, risks, links, timeline. Still one message. If it cannot fit in 350 words, write a short Slack message that links a Canvas or Notion doc, and tell the user. |

How the level changes things:

- **Verbose means more content, not longer sentences.** At levels 1 and 2 add more facts and more sentences. The sentence cap stays at the STE limit. A level 1 message must still be easy to read; it just answers more questions up front. The extra content comes from what the user gave you: expand their facts, reasons, and steps. Do not add facts, files, steps, or advice they did not mention, even good advice. The message goes out under the user's name, so every claim in it must be one they made. If you think something is missing, say so in your note to the user, not in the message.
- **Simple means fewer things, not shorthand.** At levels 4 and 5 cut whole ideas, not articles or verbs. "Checkout is down Saturday 2 to 4am ET." is level 5. "Checkout down Sat 2-4" is just compressed.
- **Templates flex with the level.** At 4 and 5, drop optional fields (`Owner`, `Call`, `Timeline`, `Monitoring`, `Revert`) unless the reader needs them to act. Level 5 usually collapses a template to one or two plain sentences with no labels. At 1 and 2, add fields or a short paragraph where the content earns them.
- **Casual messages follow the level too.** A level 5 reply is one line. A level 1 reply can be a few short paragraphs.

## Explanations: ASD-STE100

When any part of a message explains something, write that part in ASD-STE100 Simplified Technical English. Read `references/ste100.md` for the rules and the word list.

**What counts as an explanation:** a sentence whose job is to make the reader understand something or do something. That covers the cause of a problem, the reason for a change or decision, how something works, what the reader must do, and steps to follow. In the templates, `Cause`, `What we did`, `Impact`, and any call to action are explanation text.

**What does not:** greetings, thanks, banter, label names, status values (`Looking into it`, `Done`), and timeline entries that only state an event. These keep the normal Slack voice. A message that thanks someone and then explains a fix uses the normal voice for the thanks and STE for the fix. The first sentence of a message follows the same test: if it explains (a cause, a change, an action), it is STE.

Why STE: people read Slack quickly, during incidents, and often in their second language. STE gives each sentence one meaning on the first read. That is the goal; do not apply the rules so mechanically that the message stops sounding like a person.

The short version of the rules (the reference file has the details and examples):

- Simple, common words with one meaning. Use the same word for the same thing each time. Technical names and technical verbs are fine.
- No phrasal verbs ("look into" → "examine"), no "-ing" verb forms, no contractions.
- Keep "the", "a", "this". Do not drop words to save space.
- Sentence caps: 20 words for instructions, 25 for descriptions, or the level's cap if it is shorter.
- One instruction per sentence. Imperative for instructions. Active voice.
- A warning goes before the instruction it applies to.
- Steps go in a `1.` / `2.` / `3.` list.

## Output format

1. Write the Slack message to a file at `~/Desktop/slack-message.txt` (plain text, no code fences).
2. Copy the file contents to the clipboard using `pbcopy < ~/Desktop/slack-message.txt`.
3. Confirm to the user that the message was saved and copied. Include the file path and the level you used, e.g. "Level 3 (default)" or "Level 5 (you asked for it)", so the user can ask for a different one.

After confirming, add a brief note only if there is something the user needs to action (e.g., replace a placeholder mention, fill in a time). Skip the note if the message is complete as-is.

## Hard rules

- **Never use em dashes (—) anywhere.** Not in the message, not in the skill, not ever. Use a colon, a comma, parentheses, or restructure into two sentences. This is the user's strongest style rule. If you catch yourself reaching for one, rewrite the sentence.
- Never sign off with the user's name or a closing signature. Slack is not email.
- Always use `-` for bullets. Never `•`, `*`, or any other bullet character.
- Always use `[display text](https://url)` for hyperlinks. The user pastes into Slack's rich text composer, which auto-converts this to a proper Slack hyperlink. Never use the `<url|text>` mrkdwn form.
- **No headings.** Do not start a message with a title line: no emoji plus bold phrase (`:white_check_mark: *CI is fixed*`), no bold phrase alone, no "Fixed: X" banner. Do not put a bold label alone on a line above a section (`*Why:*`, `*Steps:*`, `*Timeline:*`). The user reads these as a document pasted into chat, and has rejected them. Start with a full sentence that says the main thing; that sentence does the job a headline would. Inline labels that start a line and carry their value on the same line (`*Owner:* @owner`, `*Status:* Fixing`) are fine.

## Voice

The shared voice rules live in `_voice.md`, and the patterns to avoid live in `tropes.md` (see the top of this file). The Slack-specific things on top of those:

- **Greetings are optional and usually unnecessary.** Most channels don't need "Hey team!" or "Hi all,". Open with the substance.
- **Slack is conversational by default.** Lean further toward fragments and casual phrasing here than you would in a PR description. A heads-up to a coworker is closer to speech than to writing. This applies to the non-explanation parts; explanation sentences are full STE sentences (see above).
- **Match the channel tone.** If the channel is an ops or status channel, be terse and factual. If it's `#random` or a DM, you can be warmer and looser. Tone is separate from the level: a level 2 incident update is still factual.

---

## mrkdwn syntax rules

These are the rules Slack actually follows. Deviating from them causes text to render incorrectly.

| Effect | Correct syntax | Common wrong syntax |
|---|---|---|
| Bold | `*text*` | `**text**` (renders literally) |
| Italic | `_text_` | `*text*` or `__text__` |
| Strikethrough | `~text~` | `~~text~~` |
| Inline code | `` `code` `` | |
| Code block | ` ```\ncode\n``` ` | indented blocks (don't work) |
| Block quote | `> text` | |
| Link with label | `[display text](https://url)` | `<https://url\|display text>` |
| Bare link | `https://url` | |

**Formatting marks must be flush against the text.** `*bold*` works. `* bold *` does not.

### What Slack does NOT support

Never use these. They render as plain text or symbols:

- Headers (`#`, `##`, `###`): do not replace them with bold title lines either; see "No headings" above
- `**double asterisks**` for bold: renders literally
- Nested/indented lists: renders flat
- Tables: use a code block with aligned columns if essential
- HTML tags

### Mentions

Use these in your output so the user just needs to fill in the right name:

- `@here`: active members in the channel right now
- `@channel`: all members (use sparingly, only for urgent/critical things)
- `@username`: individual, typed as-is when writing for the client composer

---

## Message types and templates

Every template starts with a plain sentence, never a title line (see "No headings"). Placeholders in `[brackets]` show what goes where.

### Announcement

Two shapes work. Pick the one that fits.

**Prose-first** (default for most announcements, feels human):

```
[First sentence: what is changing and when, so the reader knows at once if it affects them.] [One or two sentences: who it affects and what happens.]

[Optional: what you'd like them to do, or "Questions in thread."]
```

**Label-style** (use when there's genuinely structured info to scan, e.g. a migration with multiple distinct fields):

```
[First sentence: what is changing and who it affects.]

*When:* Date, time, timezone.
*Impact:* What changes for users.
*Owner:* @owner

[Call to action or "Questions in thread."]
```

Either way, front-load it: the first sentence should be enough to tell the reader whether it affects them. Default to prose. Labels feel corporate when there isn't much to label.

### Outage / service status update

```
[First sentence: what is broken and since when, with HH:MM TZ.]

*Status:* Looking into it / Found it / Fixing / Done
*Impact:* [What's not working, which users or requests are affected]
*Service:* `service-name` ([region/env])
*Call:* [Video call](https://meet.example.com) (optional)
- [HH:MM] [Event]
- [HH:MM] [Event]
*Next update:* [HH:MM TZ] or when status changes
```

Use `inline code` for service names and system identifiers. Keep the timeline factual and timestamped; the timestamps show what the lines are, so they need no heading. The `Impact` line is explanation text, so write it in STE.

### All-clear / fixed

```
[First sentence: what is fixed and when, with HH:MM TZ.]

*Duration:* [Start time] to [End time]
*Cause:* [One sentence.]
*What we did:* [One sentence.]
*Follow-up:* [Doc link, ticket, or "TBD"]
```

`Cause` and `What we did` are explanation text: write them in STE.

### Release / deployment

```
[Service/feature] v[X.Y.Z] is live in [env]. [One sentence: what it changes for people.]

- [Change 1]
- [Change 2]

*Revert:* `[command or link]`
*Monitoring:* [Dashboard](https://grafana.example.com)
*Owner:* @owner
```

### Team standup / async update

Keep these short and plain. Use light formatting only when it genuinely helps scan. Three short paragraphs or a three-item bulleted list is ideal. Heavy formatting on casual updates reads as stiff.

```
*Done:* [What shipped or completed yesterday.]
*Today:* [What you're working on.]
*Blocked:* [Anything blocking you, or "nothing."]
```

### Steps inside any message

Introduce a step list with a plain sentence, not a bold label: "Do these steps before November 30:" then `1.`, `2.`, `3.` lines.

A warning goes inside the list, as the line directly before the risky step, or as the start of that step. People follow steps in order and act as they read, so a warning below the list reaches them after they have already done the damage.

```
5. Make sure that the output shows your SSO role.
6. Do not delete your old access keys before step 5 works. Then delete your old access keys.
```

### Casual message

No formatting. Plain prose. Write it the way you'd actually say it out loud.

This is where the voice matters most. Most Slack messages are casual: a question, a heads-up, a thanks, a "hey can you look at this". They should never read like a content generator made them.

**Good:**
- "thanks for catching that, fix is in https://github.com/.../pull/123"
- "heads up, the staging cluster is acting weird, looking into it now"
- "can you take a look at this when you get a sec? https://... I think the IAM role is the issue but want a second pair of eyes"

**Bad:**
- "Hey team! Just wanted to give a quick update that..." (greeting + filler)
- "I'd like to kindly request your review of the following PR." (formal-corporate)
- "Excited to share that the fix is now live! 🎉🚀✨" (hype + emoji pile-up)

If the message is a question or a request, ask plainly. If it's a thanks, mean it and be specific about what you're thanking them for. If the casual message also explains something (why a bug happened, how to fix a setup), the explanation part is STE; the rest stays casual.

---

## Formatting principles

**Use bold to anchor the reader's eye, not as decoration.** Bolding every phrase removes the emphasis from everything. Reserve it for: inline labels (the key in a key/value pair) and critical actions. Never for a title.

**No leading emoji.** An emoji at the very start of a message reads as the first half of a title line, so do not open with one. An emoji inside a sentence is fine when it adds something the words do not. One after every sentence is noise.

**One message, not many.** A wall of sequential short messages triggers many notifications. Compose one well-structured message instead.

**Appropriate length.** The level sets the length (see "Level (1 to 5)"). If the content needs headers and structured sections even at the level asked, consider whether it should be a Slack Canvas or a Notion doc linked from a short Slack message instead.

**`@channel` vs `@here`.** Prefer `@here` for non-critical announcements (it pings active users only). Reserve `@channel` for things that genuinely require everyone's attention regardless of timezone.
