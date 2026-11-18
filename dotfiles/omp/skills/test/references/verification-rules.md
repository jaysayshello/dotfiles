# Verification rules from the article

Source: "How the Claude Code team thinks about verification", Addy Osmani, 16 November 2026.
URL: https://claude.dev/blog/how-the-claude-code-team-thinks-about-verification/

This file gives the rules from the article. It uses only what the article says. `/test` applies these rules.

## What to check

- Run the change. The article says that "Running the app end to end matters more than tests."
- Use an end-to-end (E2E) test when you can do only one type of test. An E2E test is difficult to fool. The full feature works, or it does not work.
- A unit test can pass when the feature is broken. The reason is that the test and the agent do not know the full task.
- Give the agent access to the real system that operates. Examples are a browser through CDP, a simulator, or an API harness.
- Use a property test for edge cases that people do not see. A property is a statement that must always be true. A library such as fast-check, Hypothesis, or proptest makes thousands of inputs to try to break it.
- These properties occur in most projects:
  - Round trip: encode X, then decode it, and you get X again.
  - Invariant: a condition that is always true, for example "a balance is never less than zero".
  - Idempotency: do an action two times, and the result is the same as one time.
  - Equivalence: fast code gives the same result as slow code that is correct.
- Use a differential test for a migration. Give the same inputs to the old system and the new system. A difference is a bug, or a change that breaks the old behaviour.
- For a differential test, use random inputs or a sample of production traffic. Remove differences that are not important, such as whitespace. Keep a list of the differences that you approve.

## How fast and how reliable

- A flaky test teaches the agent to run the test again. The agent does not repair the code.
- A slow test makes the agent run fewer tests. Then it is difficult to find which change caused a problem.
- Run heavy tests before you commit the change.
- Run cheap checks first. The team runs the tests, the build, and the linter before it opens a pull request.
- Make the `verify` skill fast and reliable. It is the smoke test harness of the team.

## How to prove that a change works

- Each check must give evidence. A good E2E failure shows the step that failed, a screenshot, and a description of the problem.
- Select checks from the diff. The team keeps a list of 39 items. Each item has a trigger that you can read from a diff. The agent checks only the items with a trigger that matches, usually 3 to 10.
- A check must say why it failed, so that the reviewer does not have to find the reason in the diff.
- A review or a check on an old commit has no value. Check the commit that you will merge.
- Let each round use the results of the round before it. Do not check everything again from the start.

## When to stop

- Claude runs the checks and tries to repair each failure.
- If a check still fails after 3 rounds, stop and get a human.

## What not to do

- Do not let a change modify the check that judges it. Keep the rules on a branch that the change cannot modify.
- Do not skip a flaky test. Do not add sleeps. Do not run it again until it passes. If you cannot find the root cause, delete the test and write down the reason.
- Do not add a second reviewer to fix a weak reviewer. Tune the first reviewer.
- Do not let the checks and rules grow without limit. Remove the old ones on a schedule.

## How to improve the checks

- Turn each missed bug into a rule or a hook, so that it does not occur again.
- Start a new gate in observe mode. Observe mode logs what it would block, so that you can find false positives.
- Measure the checks against the bugs that were important to you, such as reverts and incidents.
