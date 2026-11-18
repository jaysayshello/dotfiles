---
name: test
description: "Select and run the smallest set of fast, accurate checks that prove a change works, and show a coloured PASS/FAIL list. Use this skill for /test, \"test this\", \"how do I verify this change\", \"prove this works\", and \"what should I test here\". Also use it when the user asks how to check a Helm, Terraform, Cloudflare rule, container image, script, or code change. The skill finds the context from the diff, the branch, the pull request, and the repo, or uses the target that the user names. Do not use it for a plain \"run the test suite\" or \"npm test\" request, or for test-first work (use tdd)."
---

# /test

`/test` finds the best checks for the change of the user, runs them, and shows the result as a short coloured list. Each check must be fast and accurate. Each check must prove a part of the change, not only that the code compiles.

Read `references/verification-rules.md` one time per session. It gives the rules from the verification article that this skill applies.

## How /test is different from other skills

- `tdd` writes a test before the code, then writes the code to make it pass. It is a loop to build a feature. `/test` starts with a change that exists. It selects the checks that prove the change, runs them, and reports.
- `code-review` and `pr-review` read the code and compare it with standards and a spec. `/test` runs the code and shows evidence.
- `fix` repairs review findings on a pull request. `/test` does not repair the code. If the user asks for a repair, do the repair, then run `/test` again (3 rounds maximum).
- A plain "run the test suite" request is not `/test`. Run the command that the user gave.

## Safety rules

WARNING: Do not change real state. Do not run `apply`, `deploy`, `restart`, `delete`, `rollout`, or a write to an API. Do not post a comment or a message.

- Use local checks first. Use read-only checks and dry runs on live systems only when a local check cannot prove the change.
- Before a check on a live system, read the current context (`kubectl config current-context`, the cloud account, the Terraform workspace). Put it in the log.
- Keep the files of the user. Do not use `git stash`, `git checkout`, or `git reset` in their worktree. Use a separate worktree for the base (see `references/checks.md`, section 1).
- Do not edit or weaken a current test to make it pass. A change must not modify the check that judges it.
- Do not run a failed check again to get a pass. Do not add sleeps. Report the failure.

## Procedure

1. Find the target.
   - If the user names a target (a file, a function, a PR, a behaviour), use it.
   - If not, read the context: `git status --short`, `git diff --stat <base>...HEAD`, the branch name, and `gh pr view --json title,body,files` if a PR exists.
   - Read the project files: `package.json`, `Makefile`, `justfile`, `go.mod`, `pyproject.toml`, `Chart.yaml`, `*.tf`, and the CI workflow. Find the test command of the repo there.
2. Write down what the change must do, in 1 to 3 short statements. Use the PR body, the commit messages, and the diff. Each statement must be a result that a check can see. Example: "the rendered pod uses the signed digest".
3. Select the checks. Read the sections of `references/checks.md` for the file types in the diff.
   - Select 1 check for each statement. Select the fastest check that can see the result.
   - Add a red check for each statement when possible. A red check is the same check on the base. It must fail there.
   - Add cheap checks (format, lint, types) only for the files in the diff.
   - Use 2 to 6 checks in total. More checks make the result slower, not more accurate.
   - If the best check for a statement needs access that you do not have, keep it in the plan with a `skip` reason. The user must see what the run did not prove.
4. If the correct check is not clear, ask the user 1 short question. Use the ask tool if there is one. Give 2 to 4 options and put the recommended option first with "(recommended)". Examples of an unclear check: no test framework, two possible targets, or a slow check is the only accurate check.
5. Write the plan to `${TMPDIR:-/tmp}/test-runs/plan-<time>.json`. Do not put it in the repo. The format is in `scripts/run_checks.py`.
6. If a check needs a new test that is good to keep, add the test to the repo test files.
   - A unit test or a property test that guards the change is good to keep.
   - Put the test file name in the check name.
   - Put a check that you do not keep (a fake CLI, a query, a render diff) in `${TMPDIR:-/tmp}/test-runs/`.
7. Run the plan: `python3 <skill-dir>/scripts/run_checks.py --color <plan.json>`. The runner writes the command output only to the log file.
8. Read the log for each FAIL and each WARN. Replace a detail line that is not clear with plain words in the results JSON. Then print the report again: `python3 <skill-dir>/scripts/report.py --color <results.json>`.
9. Give the report as your full reply. Put it in a `text` code block. Add nothing before it or after it.

## Time limits

- Each check: about 1 minute maximum. The runner stops a check after `timeout` seconds (default 60) and reports WARN.
- The full run: about 5 minutes maximum (`budget`, default 300). The runner reports SKIP for the checks that it cannot start in that time.
- If a check is slower than 1 minute, make it smaller first. Examples: one test file, `-run <name>`, `helm template -s <template>`, `terraform plan -target=<addr>`, a shorter time range in a query.
- If the slow check is the only accurate check, ask the user before you increase its `timeout`. Give the expected time in the question.
- If the cheap checks fail, do not run the slow checks. Report the slow checks as SKIP with the reason "a cheap check failed first".

## Output format

Use this format every time. The scripts make it. Do not write it by hand.

```text
✅ PASS  render diff changes only the sidecar image
✅ PASS  red check: base render still has the old tag
❌ FAIL  sidecar image has a valid signature
         charts/app/values.yaml:14  cosign found no signature for this digest.
⏭️  SKIP  kind cluster test
         Docker is not available.
2 passed · 1 failed · 1 skipped · 18 s · log: /tmp/test-runs/app-20261118-101500.log
```

- One line for each check: the mark, the status, and a short name. The name says what the check proves, in plain words.
- The status colours are green `PASS`, red `FAIL`, yellow `WARN` and `SKIP`.
- Each FAIL has 1 or 2 lines: what failed, and where (`file:line` or the resource name). Do not show stack traces, exit codes, or tool jargon.
- Each WARN and SKIP has 1 line with the reason.
- The last line gives the totals, the run time, and the log path.
- Put nothing else in the reply. The details are in the log.

## Examples

| Change | What the change must do | Checks |
|---|---|---|
| Helm values PR that pins a signed image | The pod uses the new digest. The digest has a valid signature. | Render diff with a `grep` for the digest. Red check on the base render. `cosign verify --insecure-ignore-tlog=true` on the digest. `helm lint`. |
| Cloudflare WAF rule in Terraform | The rule blocks the bad paths. The rule does not block health checks. | `terraform fmt -check`. A targeted `terraform plan` with a `jq` assertion. A log query on 1 day of traffic for each statement. |
| TypeScript change in a small CLI | The new flag changes the output. The old output stays the same. | `tsc --noEmit`. The test file for the module. The CLI end to end with the new flag. The same CLI command on the base as a red check. |
