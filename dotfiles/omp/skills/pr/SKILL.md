---
name: pr
description: "End-to-end PR workflow for your work repos. Use this skill whenever the user says '/pr', 'open a PR', 'make a PR', 'create a PR', 'fix this in a PR', 'raise a PR', 'submit a PR', or shares a Jira ticket or GitHub issue and wants code changes made. Covers the full flow: understand the problem, work in the repo clone on a feature branch, implement, push, open a draft PR fast, then backfill Jira (ticket + PR body) in the background. Trigger on any intent to turn a problem or ticket into a pull request."
---

# PR Workflow

End-to-end flow: understand, locate repo, branch, implement, push, draft PR, async Jira backfill.

The user's goal when they invoke `/pr` is the PR URL on their screen, fast. Anything that does not block PR creation (Jira ticket creation, ticket description, the Jira link inside the PR body) gets moved into a background subagent that runs *after* the PR is already open. The clipboard gets the Slack-ready link the moment `gh pr create` returns, not at the end of the workflow.

Work happens directly in the repo clone under `<repos_root>/<repo>`, on a feature branch cut from the default branch. Do not commit to `main`/`master`. Do not use Conductor or git worktrees.

---

## Phase 1: Understand the Problem

Accept input in any form:
- **Inline description**: user pastes or types the problem directly
- **Jira ticket**: key like `PROJ-123` or a full `<JIRA_BASE_URL>/browse/...` URL, fetch with `acli jira workitem view <KEY> --fields "*all"`
- **GitHub link**: issue or PR URL, fetch with `gh issue view <URL>` or `gh pr view <URL>`

Extract:
- What is broken or missing?
- Which service, file, or infrastructure component is affected?
- Any constraints (backwards compatibility, security, infra-only change)?

If the problem is ambiguous, ask one focused clarifying question before proceeding.

If the user passed a Jira key, capture it now as `<KEY>` so Phase 6 can include the link in the PR body at create time. If not, leave `<KEY>` unset: Phase 6 will spawn a background subagent that creates the ticket and edits the PR body afterward. Do not spawn the Jira subagent here. The PR opens first and Jira fills in behind it.

---

## Phase 2: Locate the Repo

### Locate the repos directory

Read `references/repos.md` (relative to this skill's directory). You need three settings from it:

- `repos_root`: where the main clones live (e.g. `~/Github/<org>`)
- `JIRA_BASE_URL`: the base URL of your Jira site (e.g. `https://jira.example.com`), used for ticket links
- `JIRA_PROJECT`: the Jira project key for new tickets (e.g. `PROJ`)

If one is missing or still has its placeholder value, ask the user for it and save it back to `references/repos.md`. This only happens once.

### Find the right repo

```bash
ls <repos_root>/
```

Use clues from the ticket/description to narrow down: service name, file paths, Terraform module, Helm chart, EKS cluster, etc. If the repo is not found locally but was referenced via a GitHub URL, clone it into `<repos_root>/` first. If multiple repos could be relevant, name them and ask the user to confirm before proceeding.

### Check the current state

```bash
cd <repos_root>/<repo>
git fetch origin -q
default=$(git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@')
branch=$(git rev-parse --abbrev-ref HEAD)
git status -s
```

- If the working tree already has changes that match what the user described, jump to Phase 4 (or Phase 5 if the work looks complete).
- If the tree is clean and you are on a feature branch, check whether a PR already exists before doing anything:

```bash
git log "origin/$default".. --oneline   # any commits ahead of the base?
gh pr list --head "$branch" --json url,state --jq '.[0]'
```

  - PR exists and is open: print the URL and stop. The user is asking "where's my PR?".
  - PR exists and is merged/closed: print the URL with its state and ask whether to branch off, reopen, or stop.
  - No PR and there are commits ahead: ask whether to open one for the existing commits or do more work first.

Otherwise continue to Phase 3.

---

## Phase 3: Create a Branch

Cut a feature branch from the up-to-date default branch. Never commit directly to `main`/`master`.

**Branch names must never include the user's name or GitHub handle.** Use a short, lowercase, hyphen-separated slug describing the change (~3-5 words).

Example slugs:
- `static-cache-header`
- `drop-metrics-exporter`
- `fix-config-lookup`

```bash
cd <repos_root>/<repo>
git fetch origin -q
git switch -c <slug> "origin/$default"
branch="<slug>"
```

If the slug already exists as a branch, pick a different one or ask the user whether to resume work on it. After this step, `<repo>` and `<branch>` are the confirmed values for the rest of the skill.

---

## Phase 4: Implement the Changes

Skip this phase if the user's intent is to ship changes already sitting in the working tree. Run `git status` first: if there are already staged or unstaged changes that match what the user described, jump to Phase 5.

Work in the repo clone. Read the relevant files before touching them. Follow the code style of the file: do not reformat or clean up unrelated code.

Primary languages in this codebase:
- **Terraform / Terragrunt**: `*.tf`, `*.hcl`
- **Helm / Kubernetes**: `*.yaml` under `charts/`, `values/`, `helmfile.d/`
- **Python**: `*.py`
- **Shell**: `*.sh`

Make only the changes directly needed to address the problem. If you notice something adjacent that looks wrong, mention it to the user rather than fixing it in the same PR.

### Comment hygiene

Do not litter the code with comments. Add a comment only when the code cannot explain itself: a non-obvious *why*, a workaround, a gotcha, a link to context. Then keep it short.

- No comments that narrate what the next line does or restate the code in prose.
- No section-divider banners or decorative comment blocks.
- No multi-line rationale essays inside code. Long rationale belongs in the Jira ticket or an ADR, not in the PR body or scattered through the file.
- Match the existing comment density of the file. When in doubt, leave it out.

**Never commit yet.** Phase 6 handles the commit.

---

## Phase 5: Show Diff

Once changes are in place, run `git diff` (and `git diff --staged` if anything is already staged) and output the result so the user can see exactly what changed:

```bash
cd <repos_root>/<repo> && git diff && git diff --staged
```

Briefly note:
- What files were changed and why
- Any trade-offs or decisions you made
- Anything they should verify after the fact

Then continue immediately to Phase 6. Do not pause to ask "should I create the PR?": the user invoked `/pr` precisely because they want a PR. They can interrupt if they want to stop.

---

## Phase 6: Commit, Push, Open PR Fast, Then Async Jira

The order in this phase is load-bearing for perceived speed. Do them in exactly this sequence:

0. **Voice gate.** Read `~/.claude/skills/_voice.md` now, before drafting anything. The PR title, body, and the Jira description all run through this voice. If you skip this step you will produce text in the wrong voice and the user will have to ask you to rewrite it. It is not optional. (If that file does not exist on this machine, use the rules inlined in "Voice for the PR title and body" below.)
1. Draft the PR title and body in the user's voice (see "Voice for the PR title and body" below). Do this *before* running any git command, so the body is ready to pass straight into `gh pr create`.
2. Commit (if there's anything to commit)
3. Push
4. `gh pr create --draft` with the voice-applied body
5. `slackpr` to copy the Slack-ready link to the clipboard
6. Return the PR URL to the user as the first line of your response
7. Spawn the background subagent that handles Jira (and PR body backfill if needed). Brief it with the voice-applied body verbatim so it doesn't clobber the voice when it appends the Jira link.

Steps 2-6 happen in the foreground and finish in roughly the time of `git push` plus `gh pr create`. Step 7 fires and forgets so the user never waits on Jira.

### Voice for the PR title and body

**Read `~/.claude/skills/_voice.md` if you haven't already.** That's the canonical voice doc (warm but brief, plain words, concrete details, no em dashes, banned words list). Apply it to the title, the body, and the Jira description before any text leaves this skill.

Critical rules inlined here so the body shape stays right even if `_voice.md` got skipped:

- **Body shape: 1-2 sentence tl;dr at top, then `## Changes`, then 3-4 short bullets, then bare Jira URL.** Not `## Summary`. No test logs, no long explanations. The intro sentences are the headline; the bullets are the supporting detail. A reviewer reading only the intro should know what's going on.
- **No em dashes** in the title, body, or Jira description. Ever. Use a colon, comma, parentheses, or restructure. The user's strongest style rule.
- **Banned words:** "robust", "thorough", "comprehensive", "new" (when describing a change), "improved", "enhanced", "seamless", "nuanced", "multifaceted". Do not use them.
- **No marketing voice.** "This PR introduces...", "This change provides...", "Better support for...", "To better enable..." are filler. Say what the change does in plain words ("Adds X", "Drops Y", "Suppresses Z").
- **No AI attribution** anywhere.

PR-specific voice patterns on top of the shared voice:

- **Say what the change does, not that it exists.** "Adds X" / "Updates Y" / "Removes Z" works. "This PR adds...", "This change introduces...", "This commit makes it so that..." are filler. Cut them.
- **Reviewer-aware.** If something is non-obvious (a trade-off, an intentional omission, a follow-up), call it out in one bullet. The reviewer's job is easier when you flag the thing they'd otherwise have to ask about.
- **Imperative title, declarative bullets.** Title says "Block X" / "Drop Y" / "Fix Z". Bullets describe what the diff does in the present tense.

**Good body:**

```
Adds a one-day cache header for `/static/*` on `app.example.com`. Every page load was fetching all the assets again, and the file names are already hashed, so a long cache is safe.

## Changes

- Set `Cache-Control: public, max-age=86400` on `/static/*` responses
- Skip the header on `preview.example.com` so preview builds always load fresh files
- Follow-up: `docs.example.com` serves its own assets and still needs the header, will add in a separate PR

https://jira.example.com/browse/PROJ-123
```

**Bad body** (what to avoid):

```
## Summary

- This PR introduces comprehensive improvements to our caching posture by adding a new header
- Robust handling of edge cases in asset delivery
- Various other enhancements to make the site faster
```

The bad version is longer, vaguer, and tells the reviewer nothing actionable. It uses banned words ("comprehensive", "robust", "new"), the marketing opener ("This PR introduces..."), and the wrong heading. The good version names the header, the path, the exception, and a known follow-up.

**Title examples:**

Good:
- `Cache /static/* for one day on app.example.com`
- `Drop the deprecated metrics-exporter chart`
- `Fix config lookup when the service name has a dot`

Bad:
- `Improvements to caching` (vague, banned word)
- `Update metrics-exporter chart` (doesn't say what)
- `Fix bug` (says nothing)
- `feat(cache): comprehensive asset delivery hardening` (jargony + banned word)

### Step 1-2: Commit and push

Stage everything, write a semantic commit message based on the change, and push the branch. Don't ask first: the user invoked `/pr` to get a PR; the commit is part of that.

```bash
cd <repos_root>/<repo>

if [ -n "$(git status --porcelain)" ]; then
  git add -A
  git commit -m "<semantic commit message under 80 chars>"
fi

if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
  git push
else
  git push -u origin "$branch"
fi
```

If the commit fails (e.g. transient GPG/1Password signing failure), retry once. If `git add -A` would pull in unexpected files (look at `git status` first), stage explicit paths instead. Never use `--no-verify`.

### Step 3: Open the PR immediately, no waiting on Jira

Open the draft PR right after the push completes. If `<KEY>` is set from Phase 1, include the Jira link in the body at create time. If not, omit it: the background subagent in Step 6 will inject the link via `gh pr edit` once the ticket exists.

```bash
# $body must already be voice-applied from Step 1 above. Do NOT write the body
# inline in this bash block; that's how voice gets skipped. The shape is:
# 1-2 sentence tl;dr, blank line, `## Changes`, blank line, bullets, blank line,
# bare Jira URL (if KEY is set).
if [ -n "${KEY:-}" ]; then
  body="$(cat <<EOF
<one or two voice-applied sentences: what changed and why>

## Changes

- <voice-applied bullet>
- <voice-applied bullet>
- <voice-applied bullet>

${JIRA_BASE_URL}/browse/${KEY}
EOF
)"
else
  body="$(cat <<EOF
<one or two voice-applied sentences: what changed and why>

## Changes

- <voice-applied bullet>
- <voice-applied bullet>
- <voice-applied bullet>
EOF
)"
fi

pr_url=$(gh pr create --draft --title "<voice-applied title>" --body "$body")
```

PR title and body rules:
- No Jira key prefix in the title
- Imperative mood, sentence case, under 80 chars
- Title describes what changes, not why
- Body shape: 1-2 sentence tl;dr at top, blank line, then `## Changes` heading, then 3-4 short bullets. NOT `## Summary`. No test logs, no long explanations. The tl;dr is the headline; bullets are supporting detail.
- Jira ticket URL on its own line at the bottom (added at create time if `<KEY>` was known, otherwise injected by the background subagent)
- No AI attribution, no "Created with Claude Code"
- No em dashes in the title or body. Use a colon, comma, parentheses, or restructure. This is the user's strongest style rule.

(The "Voice for the PR title and body" section earlier in this phase is the source of truth for tone and phrasing. These rules are the structural shape.)

### Step 4: Copy a Slack-ready link to the clipboard

Run `slackpr` immediately after the PR is created so the user can paste the link without waiting on anything else.

```bash
zsh -ic "slackpr $pr_url"
```

`slackpr` is a zsh alias and isn't available in non-interactive shells by default, hence `zsh -ic`. If the alias isn't found, fall back to `echo "$pr_url" | pbcopy` and tell the user `slackpr` wasn't on PATH.

### Step 5: Return the PR URL to the user, then ADHD-shaped summary

The very first line of your final message must be the PR URL: that's the artifact they came for. Then briefly note that the Jira ticket and PR body Jira link are being handled in the background.

Right after the PR is created, print a summary of the PR for the user to review in the terminal, shaped by the `i-have-adhd` skill. Read `~/.pi/agent/skills/i-have-adhd/SKILL.md` first and apply it to this summary: lead with what changed, number the files/changes, keep it scannable, and make it easy to understand exactly what's being committed. (That skill is optional: if the file does not exist, apply those same rules directly.) This summary is for the user's review, so it is separate from the PR body (do not put ADHD formatting in the PR body itself).

### Step 6: Spawn the background Jira + PR backfill subagent

After the PR URL has been returned to the user, spawn one background subagent (`subagent_type=general-purpose`, `run_in_background=true`) that handles everything Jira-related. Do not await it; the user already has what they need.

The subagent's responsibilities, in order:

1. **Ticket creation or lookup.**
   - If `<KEY>` was unset, create a ticket with `acli jira workitem create -p "$JIRA_PROJECT" -t Task -s "<title>" -a "@me" --json` and parse the key from the JSON.
   - If `<KEY>` was passed in by the user, fetch it with `acli jira workitem view <KEY> --fields "*all"` and decide whether the description is empty/stub-y enough to need a backfill.

2. **Description backfill.** Write the ADF JSON below to `/tmp/jira_desc_<KEY>.json` and apply with `acli jira workitem edit --from-json /tmp/jira_desc_<KEY>.json -y`, then `rm` the temp file.

3. **PR body backfill (only if the PR body did not already contain the Jira link).** Run:
   ```bash
   gh pr edit "$pr_url" --body "$(cat <<EOF
   <existing summary bullets, preserved verbatim>

   ${JIRA_BASE_URL}/browse/<KEY>
   EOF
   )"
   ```

The subagent must **not** run `slackpr` again. The clipboard already has the right link from Step 4, and the PR URL itself does not change when the body is edited.

Brief the subagent with everything it needs to work without asking back:
- The full problem statement from Phase 1 (so the description has real content)
- A suggested verb-first ticket title under 80 chars
- The PR URL (for `gh pr edit`)
- The current PR body verbatim, voice-applied (so it can preserve voice and bullets when appending the Jira link). Do NOT brief the subagent with a pre-voice draft; if you do, it will preserve that draft and clobber the voice when it edits the PR body.
- The existing Jira key, if any, plus a flag noting whether the PR body already includes the link
- A mandatory instruction to read `~/.claude/skills/_voice.md` first (if it exists) and apply that voice to every prose field of the Jira description (Context, Scope bullets, Technical notes). The subagent is a fresh general-purpose agent that has not seen the voice doc, so this only happens if you brief it explicitly. The description must be voice-applied, never a raw dump or marketing voice.
- The `JIRA_BASE_URL` and `JIRA_PROJECT` values from `references/repos.md`
- The instruction to print the ticket URL on its final line for traceability

The description is built from Phase 1 context plus the implementation diff. The subagent is welcome to run `git log -1 -p` against the PR's commit to enrich the **Technical notes** section, since by the time it runs the commit is already on the remote.

### Jira description ADF template

```json
{
  "issues": ["<KEY>"],
  "description": {
    "version": 1,
    "type": "doc",
    "content": [
      { "type": "heading", "attrs": { "level": 2 }, "content": [{ "type": "text", "text": "Context" }] },
      { "type": "paragraph", "content": [{ "type": "text", "text": "1-3 sentences: what is broken or missing, why this work matters, what triggered it." }] },
      { "type": "heading", "attrs": { "level": 2 }, "content": [{ "type": "text", "text": "Scope" }] },
      { "type": "paragraph", "content": [{ "type": "text", "text": "In scope:", "marks": [{ "type": "strong" }] }] },
      { "type": "bulletList", "content": [
        { "type": "listItem", "content": [{ "type": "paragraph", "content": [{ "type": "text", "text": "Specific change 1" }] }] },
        { "type": "listItem", "content": [{ "type": "paragraph", "content": [{ "type": "text", "text": "Specific change 2" }] }] }
      ]},
      { "type": "paragraph", "content": [{ "type": "text", "text": "Out of scope:", "marks": [{ "type": "strong" }] }] },
      { "type": "bulletList", "content": [
        { "type": "listItem", "content": [{ "type": "paragraph", "content": [{ "type": "text", "text": "What this ticket deliberately does not cover" }] }] }
      ]},
      { "type": "heading", "attrs": { "level": 2 }, "content": [{ "type": "text", "text": "Technical notes" }] },
      { "type": "paragraph", "content": [{ "type": "text", "text": "Files changed, services affected, any caveats for reviewers." }] }
    ]
  }
}
```

Description writing guidelines:

**Voice gate (mandatory).** Read `~/.claude/skills/_voice.md` (if it exists) and apply it to every prose field of the description (Context, Scope bullets, Technical notes) before writing the ADF JSON. This is not optional: the description is held to the same voice as the PR body. The Jira ticket is the long-form home for the change, so it can be slightly fuller than the PR body, but it should never read like a press release.

- **Context**: Synthesize from the problem statement. Be specific: name the service, the error, the request. One to three sentences. Avoid vague "improvements", "enhancements", or "to better support". Lead with what is broken or missing, then why it matters.
- **In scope**: List the actual changes (files, resources, rules). Use `code` marks for file paths and resource names. Bullets, not paragraphs.
- **Out of scope**: Mention related work that was deliberately excluded so the reader knows it's been considered. If nothing was excluded, write "N/A".
- **Technical notes**: Mention files changed, any non-obvious implementation choices, and things a reviewer should pay attention to. If there's a trade-off, name it.

**Good Context paragraph:**

> Every page load on `app.example.com` fetches all the files under `/static/*` again, because the responses have no cache header. We saw it in the load time graphs after the last release. The file names are hashed, so a deploy never reuses an old name, and a long cache is safe.

**Bad Context paragraph:**

> We need to make our asset delivery more comprehensive by addressing gaps in our caching strategy. This work will provide robust coverage of the request path and enable better performance outcomes for the platform team.

The bad version uses no specific nouns, no numbers, no service names. It reads like a strategy deck. The good version names the host, the path, the cause, and how the gap was found.

---

## Summary of Rules

| Rule | Detail |
|------|--------|
| PR-first | Push and `gh pr create` happen before Jira. Jira ticket creation, description, and PR body link backfill all run in a background subagent after the URL is returned. |
| Work in the clone | Work directly in `<repos_root>/<repo>` on a feature branch cut from the default branch. No Conductor, no worktrees. |
| Never commit to main | Always branch first. Never commit to `main`/`master`. |
| Auto-commit and auto-PR | Show diff, then commit, push, and open the PR without asking. User can interrupt. |
| Always draft | `gh pr create --draft` |
| Jira default: create | If the user didn't pass a ticket key, the background subagent creates one and edits the PR body to add the link. |
| Clipboard timing | Run `zsh -ic "slackpr <pr_url>"` immediately after `gh pr create`, in the foreground. The background Jira subagent does not run `slackpr` again. |
| Title format | `<description>`, no ticket prefix |
| Body format | 1-2 sentence tl;dr, then `## Changes`, then 3-4 short bullets, then bare Jira URL. No test logs, no long explanations. Voice-applied per `_voice.md`. |
| Post-create summary | After `gh pr create`, print a terminal summary of the PR for the user, shaped by the `i-have-adhd` skill (`~/.pi/agent/skills/i-have-adhd/SKILL.md`, optional). Review aid only, not part of the PR body. |
| Jira description voice | The background subagent reads `_voice.md` and applies it to the ticket description (Context/Scope/Technical notes). Mandatory, same standard as the PR body. |
| Scope | Only changes needed for the task |
| Minimal comments | Don't litter code with comments. Comment only a non-obvious *why*, a workaround, or a gotcha, and keep it short. No narration, no banners, no rationale essays (that goes in the Jira ticket). Match the file's existing comment density. |
| No name in branch | Branch names must never include the user's name or GitHub handle. Use a bare descriptive slug. |
