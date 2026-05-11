---
name: ddg-diagnose-ci-failure
description: Invoke ONLY when the user explicitly runs /ddg-diagnose-ci-failure or names this skill by name (e.g. "use ddg-diagnose-ci-failure on PR 4780"). Do NOT auto-invoke from symptom/intent matching - the skill may query the Apple CI Failing Tests Asana project (Step 3e), which locks other MCPs for the rest of the session under the lethal-trifecta policy, so it must be user-initiated. If the user asks about CI failures, GitHub Actions runs, or flaky tests without naming this skill, answer directly instead. Accepts one optional argument: a GitHub Actions run URL, a PR URL or bare PR number, or an Apple CI Failing Tests Asana task URL - or no argument to use the current branch's open PR.
---

# Diagnose CI Failure

Investigate a GitHub Actions workflow failure, classify it, trace test failures back to the local code, and propose a fix.

## Prerequisites

This skill requires the GitHub CLI (`gh`) to be installed and authenticated. Before doing anything else, run:

```bash
command -v gh >/dev/null && gh auth status
```

If `gh` is not installed, stop and tell the user to install it (`brew install gh` on macOS) - do not attempt to substitute `curl` against the GitHub API. If `gh` is installed but not authenticated, stop and tell the user to run `gh auth login`. Either way, bail out before resolving inputs.

## Inputs

The skill resolves any of the following to a single GitHub Actions run to investigate. `gh` autodetects the repo from the current working directory's git remote, so you don't need to pass `--repo` unless the user supplies a URL pointing at a different repo - in which case extract `<owner>/<repo>` from the URL and pass it explicitly with `--repo <owner>/<repo>`. Resolve the input first, then start at Step 1 with the resulting `run_id` and any optional `job_id` or `attempt_number`.

### Actions run URL

Example: `https://github.com/<owner>/<repo>/actions/runs/25519433222` (optionally with `/job/<id>` or `/attempts/N`).

Extract `run_id`, `job_id` if present, and `attempt_number` if the URL includes `/attempts/N`. Use directly. Do not discard the attempt number: all later `gh run view` commands for this run must include `--attempt {attempt_number}` so logs and status match the supplied attempt instead of defaulting to the latest attempt.

### PR URL

Example: `https://github.com/<owner>/<repo>/pull/4752`.

Extract the PR number, then resolve as below.

### Bare PR number

Example: `4752` or `#4752`.

```bash
gh pr checks <pr_number> --json name,state,link,workflow
```

Pick the most recent failed check's run URL. If multiple checks failed, prefer the broadest test workflow over lint-only or build-only ones (in the apple-browsers monorepo that's `iOS - PR Checks`, `macOS - PR Checks`, `DBP - PR Checks`).

### Apple CI Failing Tests Asana task URL

DDG-monorepo specific. Example: `https://app.asana.com/1/137249556945/project/1205237866452338/task/<gid>`.

Extract the trailing numeric task GID. Fetch the task via the Asana MCP `asana_get_task` tool (pass the GID as `task_id`); the failing test's class and method are typically in the title (`<TestClass>.<testMethod>` or similar). Find the most recent failure:

```bash
gh run list --branch=main --status=failure --limit=20 --json databaseId,workflowName,createdAt
```

For each candidate run download the JUnit XML artifact (`*-unittests.xml`) and grep for a `<failure>` node matching the test name; use the latest matching run.

**Lethal-trifecta note:** querying Asana via MCP locks WebFetch and most other MCP tools for the rest of the session. Confirm with the user before proceeding if they may want unrelated MCPs available later.

### No argument

```bash
git rev-parse --abbrev-ref HEAD
```

If the branch is the repo's default branch, take the most recent failed run:

```bash
gh run list --branch=<default_branch> --status=failure --limit=1 --json databaseId
```

Otherwise, find the open PR for the current branch:

```bash
gh pr list --head <branch> --state open --limit 1 --json number
```

Then resolve as a PR number. If the branch has no open PR, say so and ask.

### When resolution fails

If resolution turns up nothing (PR has no failed checks, branch has no PR, Asana task title doesn't name a test), say so and stop - don't guess.

## Step 1: Fetch Run Data

Once the input is resolved to a `run_id` (see Inputs above; carry `job_id` through if the original URL had one), gather data in two passes. If an `attempt_number` was supplied, define `attempt_arg` as `--attempt {attempt_number}` and include it in every `gh run view` command for this run. Otherwise, omit `attempt_arg`. If a `job_id` was supplied, define `job_arg` as `--job {job_id}` and include it in every `gh run view` log command. Otherwise, omit `job_arg`.

### 1a: Structured overview

```bash
gh run view {run_id} {attempt_arg} --json status,conclusion,name,headBranch,event,jobs,startedAt,updatedAt
```

Identify which jobs failed, the branch/trigger event, and the workflow name (you'll need it for regression timeline lookups in Step 3). If a `job_id` was supplied, treat that job as the selected failure even when other jobs in the run also failed.

### 1b: Failed step logs

```bash
log_file="$(mktemp -t ddg-ci-failed-log.XXXXXX)"
gh run view {run_id} {attempt_arg} {job_arg} --log-failed 2>&1 | tee "$log_file" | tail -n 1000
```

CI logs are organized as `{job-name}\t{step-name}\t{line}`. Errors almost always cluster at the end - 1000 lines is usually enough; bump to 3000 if the failure context is cut off. If `tail` surfaces a test-name inventory rather than failure markers (common when the log is large), grep the persisted log to jump straight to the actual failure context:

```bash
grep -Ein -C 6 'failed|FAIL|XCTAssert|<failure|error:' "$log_file" | head -n 200
```

### 1c: Artifacts (primary source for test failures)

For any non-zero JUnit failure count, the XML is the authoritative source: precise failure counts, exact messages, and (when retries are configured) repeated `<testcase>` entries that disambiguate deterministic vs flaky failures (see Step 3d). Most test runs upload one (e.g. `unittests.xml`, `package-tests.xml`, `dbp-ios-unittests.xml`).

Use the REST API directly (`gh api`) rather than `gh run download` so the flow is stable across gh CLI versions and works correctly for non-latest attempts.

First, resolve the repo from the current working directory (or use the `<owner>/<repo>` extracted from the input URL):

```bash
repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
```

List artifacts:

```bash
gh api "repos/$repo/actions/runs/{run_id}/artifacts" \
  --jq '.artifacts[] | {id, name, created_at}'
```

If `attempt_number` was supplied, the same name may appear once per attempt (re-runs add new artifacts to the same run rather than replacing them). Fetch the attempt's time window and pick the artifact whose `created_at` falls within it:

```bash
gh api "repos/$repo/actions/runs/{run_id}/attempts/{attempt_number}" \
  --jq '{run_started_at, updated_at}'
```

Download by artifact ID - this disambiguates duplicate names and avoids relying on `gh run download`'s name-matching behaviour:

```bash
mkdir -p /tmp/ci-artifacts/{name}
gh api "repos/$repo/actions/artifacts/{artifact_id}/zip" > /tmp/artifact.zip
unzip -o /tmp/artifact.zip -d /tmp/ci-artifacts/{name}/
```

## Step 2: Classify the Failure

| Category | Signals | Action |
|----------|---------|--------|
| **Build** | `error:` from xcodebuild/clang/swiftc, `Undefined symbol`, SPM resolution errors, `No such module` | Quote error lines, point to file:line, name the cause (SPM cache, Xcode mismatch, etc.). Stop. |
| **Test** | `Test Case '...' failed`, `** TEST FAILED **`, `✘ Test ... failed`, non-zero JUnit failure counts | Continue to Step 3. |
| **Infrastructure** | Runner timeouts, simulator boot failures, checkout failures, Xcode selection errors, signing/provisioning, GitHub Actions service errors | Explain the issue, suggest `gh run rerun {run_id} --failed` or flag for CI/infra team. Stop. |
| **Lint / static** | ShellCheck, SwiftLint, `find_private_symbols.sh`, uncommitted `.strings` from translation checks | Explain violation, point to local file, suggest fix. Stop. |
| **Unknown** | None of the above match | Present the most relevant log lines, your best interpretation, ask for context. |

For non-test failures, present diagnosis and stop. For test failures, continue.

## Step 3: Analyze Test Failures

### 3a: Extract failing tests

XCTest: `Test Case '-[ClassName testMethod]' failed (0.452 seconds).`
Swift Testing: `✘ Test testMethod() failed after 0.452 seconds with 1 issue.`

For each failure, capture: test class, method, failure message, and duration (unusually fast = crash; unusually slow = timeout).

### 3b: Map to local files

Test files conventionally use `*Tests` and `*UITests` suffixes. In the apple-browsers monorepo they live under `iOS/`, `macOS/`, and `SharedPackages/*/Tests/`; in other repos, grep from the repo root or whichever subtree is appropriate.

```bash
grep -rn --include='*.swift' "func {testMethodName}" iOS/ macOS/ SharedPackages/
```

If grep misses (parameterized or generated tests), search for the class name. Read both the test and the production code under test - both sides matter.

### 3c: Determine when the test started failing

Whether this is a fresh regression or a long-standing flake changes the diagnosis. Try local git first - it's faster and answers "what changed" directly.

**Local git (deterministic failures):**

```bash
git log --oneline -20 -- {test_file_path}
git log --oneline -20 -- {production_file_under_test}
git blame -L {failing_line_start},{failing_line_end} {test_file_path}
```

If the test or its production target changed in the last few commits, that's almost certainly the regression source.

**Merge-order regression (PR passed its own CI but fails on the default branch):**

When the failing PR's own diff doesn't explain the failure, check whether another PR changed shared test infrastructure (helpers, fixtures, mocks - in the apple-browsers monorepo these live under `iOS/SharedTestUtils/`, `macOS/SharedTestUtils/`, etc.) between this PR's last green run and the default branch's HEAD:

```bash
# Find this PR's last green run for the failed workflow, capture the SHA
gh run list --branch=<pr_branch> --workflow="<workflow_name>" --status=success --limit=1 --json headSha,createdAt

# What landed in main between that SHA and HEAD?
git log --oneline <last_green_sha>..HEAD -- <suspected_shared_paths>
```

Use the workflow name identified in Step 1. A diff in a helper or mock used by the failing test is a strong signal: the PR's CI passed in isolation, but a parallel-merged PR shifted the contract underneath it. The failing test is then often a real test-side mismatch, not a production bug.

**Workflow history (flaky / environmental failures):**

When local git shows no relevant changes, or the failure looks intermittent:

```bash
# Last green runs of the same workflow on the default branch
gh run list --workflow="{workflow_name}" --branch=<default_branch> --status=success --limit=5 --json headSha,createdAt,displayTitle

# Recent runs to see the fail/pass pattern
gh run list --workflow="{workflow_name}" --branch=<default_branch> --limit=20 --json conclusion,headSha,createdAt

# Runs on this PR branch - did the test fail across all pushes (deterministic) or only some (flaky)?
gh run list --branch={pr_branch} --workflow="{workflow_name}" --limit=10
```

The diff between the last green SHA and the failing SHA brackets the regression - useful when git log on individual files doesn't surface the cause (env shifts, indirect dependencies, build-config tweaks).

### 3d: Assess flakiness

Likely flaky if any apply:

| Signal | Why |
|--------|-----|
| Timing-dependent (`waitForExpectations`, `XCTWaiter`, `sleep`, `Task.sleep`, timeouts) | CI runners are slower/less predictable than dev machines |
| Test passed on retry (e.g. `-retry-tests-on-failure` configured in the workflow - in the apple-browsers monorepo this includes `dbp_pr_checks.yml`, `macos_pr_checks.yml`, `macos_sync_end_to_end.yml`) | By definition, intermittent = flaky |
| Only fails on one matrix variant (Sandbox vs Non-Sandbox, sim version, etc.) | Environmental dependency |
| Shared mutable state - singletons, globals, class-level properties | Order/parallelism changes outcome |
| Real network/filesystem/UserDefaults access without isolation | External state varies |
| Failure message shows a race - off-by-one counts, nil optionals, "expected X but got Y" | Classic concurrent-access symptom |
| Workflow history (Step 3c) shows the same test passing then failing without code changes | Environmental, not logic |

**Inverse signal - deterministic, not flaky:** if the JUnit XML shows the same test name in N consecutive `<failure>` entries where N matches the workflow's `-retry-tests-on-failure` count, the test failed on every retry. By definition that's deterministic - skip the flaky framing and treat it as a real regression.

If none apply and the failure looks deterministic, say so - not every CI failure is flaky.

### 3e: Consult the Apple CI Failing Tests project (only if needed)

Use this step only when 3a-3d haven't produced a clear diagnosis, or when you specifically want longer-term failure history for the test (months of pattern, prior investigations, owner). For an obvious failure (timing-dependent test that just changed in 3c, or a clear assertion regression), skip this step.

The team tracks known-flaky and known-broken tests in the [Apple CI Failing Tests project](https://app.asana.com/1/137249556945/project/1205237866452338). Use the Asana MCP `asana_search_tasks` tool with these parameters:

- `workspace`: `137249556945`
- `projects.any`: `1205237866452338`
- `text`: the test method or class name

Outcomes:

- **Open task exists**: known issue with prior root-cause notes - reference it in your diagnosis instead of restarting the investigation.
- **Completed task exists**: previously closed but failing again - flag as a regression of a supposed fix.
- **No task**: continue with what you have.

Note: querying Asana via MCP locks other MCPs for the rest of the session (lethal-trifecta policy). Only invoke when the longer history is worth that tradeoff.

## Step 4: Verify Before Presenting

Cross-check your root cause against evidence. A confident-but-wrong diagnosis wastes more time than "I'm not sure."

- Can you point to specific lines that exhibit the problem you're claiming?
- Does the failure message match your theory? (Timeout → async wait; assertion → wrong state.)
- Are there other failing tests you missed? Multiple `failed` / `TEST FAILED` markers in the log mean multiple independent failures - report all.

If evidence is thin, say so explicitly.

## Step 5: Present Diagnosis (Wait Before Proposing a Fix)

Lead with the diagnosis: what failed, why, what to do. Don't echo metadata the user already gave you (URL, owner, repo, run ID). Scale depth to complexity - a missing translation or lint violation needs 2-3 sentences and a fix; a flaky test needs the deeper analysis below.

State:

1. **What the test does** - one sentence.
2. **What failed** - the specific assertion or expectation.
3. **Why** - root cause mechanism (timing, shared state, environment, genuine bug).
4. **Test or production?** - prefer attributing to the test unless evidence clearly points to a production bug. Flaky tests are almost always a test-level problem.

Then ask: *"Would you like me to propose a fix?"*

**Wait for the user to respond.** Do not propose a fix until they confirm. When the user approves:

- **Prefer fixing the test** unless the failure reveals a real production bug.
- **Explain why** each change addresses the root cause, not just what it does.
- **Present tradeoffs** if multiple valid approaches exist.

## Common Mistakes

- **Reporting only the first failure** - scan the full log; multiple independent failures are common.
- **Jumping to "flaky" without checking signals** - some CI failures are real bugs.
- **Skipping Step 4 (verify)** - false-confident diagnoses waste developer time.
- **Proposing a fix without user approval** - Step 5 ends with a question, not a fix.
- **Hallucinating test paths** - always grep; test directories aren't exhaustively listed.
- **Defaulting to workflow history when git log would answer faster** - check local changes first.
- **Reaching for the Apple CI Failing Tests Asana project too early** - it's an escalation for ambiguous cases (Step 3e), not a default. Querying Asana also locks other MCPs for the rest of the session.
