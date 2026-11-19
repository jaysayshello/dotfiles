# Check catalogue

Use this file to select the checks for a change. Find the section for each type of file in the diff. Use the first check in a section that proves the change. Add more checks only when they prove a different part of the change.

Each entry gives:

- the check, with an example command
- the red check: how to show that the check fails without the change
- the usual time
- the safety level: local, read-only, or dry run

All commands are examples. Replace the names in `<angle brackets>`. Use the test command of the repo when it has one.

## Contents

1. Prove the red check
2. Helm charts and Helm values
3. Kubernetes manifests
4. Terraform
5. Cloudflare rules (WAF, rate limits, redirects)
6. Container images and image signatures
7. Scripts that call other CLIs
8. TypeScript and JavaScript
9. Python
10. Go
11. Shell scripts
12. CI workflows
13. Web pages and UI
14. Parsers, encoders, and data transforms
15. Migrations and rewrites
16. Documentation and config with no behaviour

## 1. Prove the red check

A red check is the same check on the base commit. It must fail there, or show a different result. Then you know that the check sees the change.

- Make a copy of the base in a separate worktree. This does not touch the files of the user:
  ```bash
  base=$(git merge-base HEAD origin/main)
  git worktree add --detach "${TMPDIR:-/tmp}/test-base-${base:0:8}" "$base"
  ```
- Run the same check in that worktree with `"expect": "fail"` in the plan.
- Remove the worktree after the run: `git worktree remove --force <path>`.
- Do not use `git stash` or `git checkout` in the worktree of the user. Uncommitted work can be lost.
- A diff check (render diff, plan, differential test) compares base and head in one check. It does not need a separate red check.
- Some checks cannot have a red check, for example a read of live state. Say this in the check name, for example `live read (no red check)`.

## 2. Helm charts and Helm values

| Check | Example | Red check | Time | Safety |
|---|---|---|---|---|
| Render diff, base against head | `diff <(helm template r <base-chart> -f <base-values>) <(helm template r ./chart -f values.yaml)` | Built in: the diff must show only the expected lines | 1-10 s | local |
| Render one template | `helm template r ./chart -s templates/deployment.yaml -f values.yaml \| grep 'image:'` | Same command on the base gives the old value | 1-5 s | local |
| Lint | `helm lint ./chart -f values.yaml` | Usually none | 1-5 s | local |
| Schema | `helm template ... \| kubeconform -strict -summary` | Usually none | 2-10 s | local |
| Server dry run | `helm template ... \| kubectl apply --dry-run=server -f -` | None | 5-30 s | dry run |

- The render diff is the best first check. It shows the exact effect of a values change.
- For a render diff, assert the result. For example, count the changed `image:` lines, or `grep` for the new digest. A diff that a human must read is not a check.
- For a pinned image, check that the rendered image uses a digest (`@sha256:`), and check the signature of that digest (section 6).

CAUTION: A server dry run sends the objects to a live cluster. It does not store them, but admission webhooks run. Confirm the kube context first with `kubectl config current-context`. Never use `kubectl apply` without `--dry-run=server`.

## 3. Kubernetes manifests

| Check | Example | Red check | Time | Safety |
|---|---|---|---|---|
| Schema | `kubeconform -strict -summary <dir>` | Usually none | 1-5 s | local |
| Kustomize render diff | `diff <(kustomize build <base-dir>) <(kustomize build <dir>)` | Built in | 1-5 s | local |
| Live diff | `kubectl diff -f <file>` | Built in | 2-20 s | dry run |
| Live read | `kubectl get <kind> <name> -n <ns> -o jsonpath='{...}'` | None | 1-5 s | read-only |

- Use a live read to prove a precondition, for example that a namespace or a secret exists.

## 4. Terraform

| Check | Example | Red check | Time | Safety |
|---|---|---|---|---|
| Format | `terraform fmt -check -recursive` | None | under 1 s | local |
| Validate | `terraform init -backend=false -input=false && terraform validate` | None | 2-30 s | local |
| Plan, targeted | `terraform plan -input=false -lock=false -target=<addr> -out=<tmp>/p && terraform show -json <tmp>/p \| jq ...` | Built in: the plan shows the change | 10-60 s | read-only |
| Unit test | `terraform test -filter=<file>` | Run on the base | 5-60 s | local, if the test uses mocks |

- The plan is the main proof. Assert the plan with `jq`. For example: "1 resource to update, 0 to destroy, and the expression has the new value".
- Use `-target` to keep the plan under 1 minute.
- Use `-lock=false` so that the plan does not block other users.

CAUTION: Never run `terraform apply`, `terraform destroy`, `terraform import`, or `terraform state` commands. A plan needs read credentials. If you do not have them, report SKIP with the reason.

## 5. Cloudflare rules (WAF, rate limits, redirects)

| Check | Example | Red check | Time | Safety |
|---|---|---|---|---|
| Plan of the rule | Terraform plan, section 4 | Built in | 10-60 s | read-only |
| Expression test on past traffic | Query the HTTP request logs (for example in Athena) with the rule expression as a `WHERE` clause. Count the requests that match. | Run the old expression. The counts must differ as expected. | 10-60 s | read-only |
| Expected hits and expected misses | Two queries: one for traffic that the rule must block, one for traffic that it must not block (for example health checks, known good clients) | Built in | 10-60 s | read-only |
| Live read of the ruleset | `curl -s -H "Authorization: Bearer $TOKEN" https://api.cloudflare.com/client/v4/zones/<zone>/rulesets/<id>` | None | 1-5 s | read-only |

- The query on past traffic is the closest check to the real effect. It shows what the rule would block.
- Limit each query to a short time range and one host, so that it stays fast and cheap.
- A rule that would block known good traffic is a FAIL. Give the count and the host in the detail line.

CAUTION: Never deploy, enable, or change a rule from `/test`. Use only GET requests to the API.

## 6. Container images and image signatures

| Check | Example | Red check | Time | Safety |
|---|---|---|---|---|
| Tag to digest | `crane digest <image>:<tag>` and compare with the pinned digest | The old digest differs | 1-5 s | read-only |
| Signature | `cosign verify --certificate-identity-regexp '<regex>' --certificate-oidc-issuer '<issuer>' --insecure-ignore-tlog=true <image>@<digest>` | An unsigned or wrong digest fails | 2-10 s | read-only |
| Image runs | `docker run --rm <image>@<digest> --version` | The old image gives the old version | 5-30 s | local |
| kind cluster test | `kind create cluster --name test-<x>`, then `kind load docker-image`, `kubectl run`, `kubectl wait`, then `kind delete cluster --name test-<x>` | The old image fails the same test | 1-3 min | local |

- Always check the digest, not the tag. A tag can move.
- Use `--insecure-ignore-tlog=true` when the signature has no transparency log entry, for example a private registry signature.
- A kind test is slow. Use it only when the image must start in Kubernetes to prove the change, or when a rule in `reviewer.md` asks for it. Without a rule, ask the user first if it takes more than 1 minute.

### kind test: the deploy works and no package is missing

Use this test when a change replaces images, for example a move to signed or minimal images. A minimal image often lacks a shell, a tool, or a file capability that the old image had.

1. Make sure that Docker is on: `docker info`. If it is off, report SKIP with the reason "Docker is not on".
2. Make the cluster: `kind create cluster --name test-<x> --wait 60s`. Use 1 control plane. Add workers only if the chart uses anti-affinity.
3. Load the images by digest: `docker pull <image>@<digest>`, then `kind load docker-image <image>@<digest> --name test-<x>`. If the registry needs credentials, make an `imagePullSecret` in the kind cluster.
4. Render the chart with the values of the real environment. Put the parts that kind cannot have in a small overlay file. Examples are cloud IAM annotations, a service mesh, or an SSO connector. Keep the images, the `securityContext`, the commands, and the probes the same as the real values.
5. Apply the render to the kind cluster only: `kubectl --context kind-test-<x> apply -f <render>`.
6. Assert these results. Make each one a separate check:
   - Each pod is Ready with 0 restarts: `kubectl --context kind-test-<x> wait --for=condition=Ready pod --all -A --timeout=180s`, then read the restart counts.
   - Each init container exited 0.
   - The logs have no sign of a missing package. Scan the current and the previous logs for `not found`, `No such file`, `exec format error`, `permission denied`, and `operation not permitted`.
   - Each command that the chart runs exists in its image. Read the commands, the scripts, and the exec probes from the render. Run `kubectl exec <pod> -c <container> -- sh -c 'command -v <cmd>'` for each one. If the image has no shell, use `kubectl debug` with a copy of the pod.
   - A binary has no file capability that the `securityContext` drops. Run `getcap <binary>` in the image, or check the start error `Operation not permitted`.
   - One simple function of the app works, for example a login, a sync, or an HTTP 200 on the health endpoint.
7. Delete the cluster in the same plan, also when a check fails: `kind delete cluster --name test-<x>`.

- Red check: run the same test with the old images. The old images must pass the same assertions. Then a failure comes from the new images, not from the kind setup.
- Give the kind test a `timeout` of about 300 s and the plan a `budget` of about 600 s.
- Write the overlay file and the list of differences from the real environment in the log. A reader must see what kind did not prove.

## 7. Scripts that call other CLIs

Use a fake CLI on `PATH` when a script calls a CLI that needs credentials or that changes state.

- Write a small fake binary in a temporary directory. The fake prints fixed output, for example JSON from a real past run, and records its arguments in a file.
- Run the script with `PATH="<fake-dir>:$PATH"`.
- Assert the output of the script, and the arguments that the fake got.
- Example plan entry:
  ```json
  {"name": "scorer gives 2 points for a signed image",
   "cmd": "PATH=$PWD/fake-bin:$PATH ./score.sh img@sha256:abc | grep -q '^score=2$'"}
  ```
- Red check: run the same fake test on the base. The old script gives the old score.
- This check is local and fast (under 5 s). It also proves the parse of the CLI output.

## 8. TypeScript and JavaScript

| Check | Example | Red check | Time | Safety |
|---|---|---|---|---|
| Type check | `npx tsc --noEmit -p .` | Usually none | 2-30 s | local |
| One test file | `npx vitest run src/x.test.ts`, `bun test src/x.test.ts`, `npx jest src/x.test.ts` | Run the new test on the base | 1-10 s | local |
| CLI end to end | `node dist/cli.js <args>` or `bun src/cli.ts <args>`, then assert the output and the exit code | Same command on the base | 1-5 s | local |
| Property test | fast-check, section 14 | Run on the base | 1-10 s | local |

- For a CLI, the end-to-end run is the best proof. Run the real binary with real arguments, as the user would.
- Run only the test files that the change touches. Run the full suite only when it takes less than 1 minute.

## 9. Python

| Check | Example | Red check | Time | Safety |
|---|---|---|---|---|
| One test | `python -m pytest tests/test_x.py -k <name> -q` | Run on the base | 1-10 s | local |
| CLI end to end | `python -m <pkg> <args>` | Same on the base | 1-5 s | local |
| Types | `mypy <files>` or `pyright <files>` | Usually none | 2-30 s | local |
| Property test | Hypothesis, section 14 | Run on the base | 1-10 s | local |

## 10. Go

| Check | Example | Red check | Time | Safety |
|---|---|---|---|---|
| One package | `go test ./pkg/x/ -run 'TestName' -count=1` | Run on the base | 2-20 s | local |
| Vet | `go vet ./pkg/x/` | None | 2-10 s | local |
| Race | `go test -race ./pkg/x/ -run TestName` | Run on the base | 5-60 s | local |

## 11. Shell scripts

| Check | Example | Red check | Time | Safety |
|---|---|---|---|---|
| Syntax | `bash -n <file>` | None | under 1 s | local |
| Lint | `shellcheck <file>` | None | under 1 s | local |
| Run with fixtures | Run the script on a temporary directory with fake input and a fake `PATH` (section 7) | Run on the base | 1-5 s | local |

## 12. CI workflows

| Check | Example | Red check | Time | Safety |
|---|---|---|---|---|
| Lint | `actionlint <file>` | None | under 1 s | local |
| Local run | `act -j <job> -n` (dry run) | None | 5-60 s | local |

- A CI change is often proved only by the CI run on the pull request. If so, report SKIP with the reason "proved only by the CI run".

## 13. Web pages and UI

| Check | Example | Red check | Time | Safety |
|---|---|---|---|---|
| Browser check | Start the dev server, open the page in a browser tool, do the user steps, and take a screenshot | The base page shows the old behaviour | 10-60 s | local |
| E2E test | `npx playwright test <file> --project=chromium` | Run on the base | 10-60 s | local |

- The article says that E2E is the best check when you can do only one. For a UI change, use the browser check.
- Put the screenshot path in the log.

## 14. Parsers, encoders, and data transforms

Use a property test. It finds edge cases that the author did not think of.

- Round trip: `decode(encode(x)) == x` for all `x`.
- Invariant: for example "the output list is always sorted", or "the total is never negative".
- Idempotency: `f(f(x)) == f(x)`, for example a normalizer or a retry.
- Equivalence: the new fast function gives the same result as the old simple function.
- Libraries: fast-check (TypeScript and JavaScript), Hypothesis (Python), proptest (Rust), `testing/quick` or rapid (Go).
- Limit the number of runs so that the test stays under 10 s.

## 15. Migrations and rewrites

Use a differential test. The old system is the oracle.

- Give the same inputs to the old code and the new code. Compare the outputs.
- Use random inputs or a sample of real inputs.
- Remove differences that are not important, such as whitespace or key order.
- Keep a list of the differences that you approve. Show each approved difference in the log.

## 16. Documentation and config with no behaviour

- For Markdown, check the links and the code blocks that the change touches. Example: run each changed command block once, if it is safe.
- For YAML or JSON, parse the file: `yq . <file> > /dev/null` or `jq . <file> > /dev/null`.
- If no check can prove the change, report one SKIP line with the reason "no behaviour to test".
