---
name: ddg-sentry-report
description: Invoke ONLY when the user explicitly runs `/ddg-sentry-report` or names this skill by name (e.g. "use ddg-sentry-report for macOS 1.186"). Do NOT auto-invoke from symptom/intent matching — producing a Sentry report writes to a shared Asana task and must be user-initiated. If the user asks about Sentry issues or crash triage without naming this skill, answer directly instead. Accepts four parameters when explicitly invoked: Asana parent task URL (the report is filed as a new subtask under it), project (iOS or macOS), version (e.g. 1.186 or 7.217), and an optional time range (e.g. 24h, 72h, 7d) — defaults to 72h on Mondays (Fri–Sun coverage) or 24h on any other day.
---

# ddg-sentry-report

## Overview

Produces a structured Sentry crash triage report for a DuckDuckGo Apple release and files it as a new subtask under a user-supplied parent Asana task. Distinguishes pre-existing issues from new-in-version regressions, sorts by severity, attributes likely authors via git blame (initials + PR links only — never full names).

## Parameters

| Param | Example | Notes |
|---|---|---|
| Asana parent task URL | `https://app.asana.com/1/137249556945/task/1214175611004136` | Extract the task GID from the URL path — this is the **parent** task. The summary report is created as a **new subtask** under it (never written to the parent itself). Subtask name: `Sentry summary - <platform> <version> - <YYYY-MM-DD>`. |
| Project | `iOS` or `macOS` | Maps to Sentry project slug `apple-ios` / `apple-macos`. A single version ships under multiple release strings (main app + extensions) — see Non-obvious constants. |
| Version | `1.186.0`, `1.186.*`, or `1.186` (macOS) / `7.216.x` (iOS) | Pass-through: an exact version (`1.186.0`) goes to `app_version:1.186.0`; a series (`1.186` or `1.186.*`) becomes the wildcard `app_version:1.186.*`. Always use the wildcard form when the user supplies a series. |
| Time range (optional) | `24h`, `72h`, `7d`, `14d` | Sentry-style relative time. **Default when omitted:** `72h` when the skill runs on a Monday (covers Friday–Sunday), `24h` on any other day. Determine today's weekday via `date +%u` (Bash; `1`=Monday … `7`=Sunday). The resolved value is used in two places: appended to step-3 `list_issues` queries as `lastSeen:-<range>` (e.g. `lastSeen:-24h`), and substituted into the rewritten query URLs as `&statsPeriod=<range>`. **Does NOT apply** to the step-2 crash-free short-circuit check (that confirmation remains a global "is there any data for this version" query — adding a time filter would cause false crash-free readings for versions whose only events fall outside the window). |

## Non-obvious constants

- **Sentry org slug:** `ddg`
- **Sentry self-hosted host:** `errors.duckduckgo.com` (do NOT pass `regionUrl` to the MCP — it rejects non-sentry.io hosts; the MCP returns `ddg.sentry.io` URLs which you must rewrite)
- **One version → multiple release strings.** A given version (e.g. `1.186.1`) ships as several Sentry releases, one per target:
  - macOS main app: `DuckDuckGo@1.186.1`
  - macOS VPN extension: `com.duckduckgo.macos.vpn.network-extension@1.186.1` (and similar for other extensions)
  - iOS main app: `ios@7.216.0`
  - Filtering by a single release prefix (`release:DuckDuckGo@...`) silently drops extension crashes. Use the `app_version` tag instead — it's set by the SDK on every event regardless of target, so a single `app_version:1.186.*` (or exact `app_version:1.186.0`) catches main app + extensions in one query. Keep the explicit release list only for `firstRelease:` (see below), and include **all** releases returned by `find_releases(query="<version>")`, not just the main-app prefix.
- **Project filter in URLs:** macOS uses numeric `project=6`. For iOS, `project=apple-ios` (slug) works on the Sentry self-hosted host. If numeric is needed, look it up via `find_projects`.
- **iOS SIGKILL noise:** Most iOS SIGKILL crashes with culprit `main` are Jetsam memory-pressure kills, not app bugs. Group these under LOW unless volume spikes or the culprit frame names specific app code. Don't attempt blame on them.
- **`Sentry Crash Reports` Asana project (GID `1214294661819890`) is partitioned by platform.** Look up and create per-issue tracking tasks scoped to the section that matches the run's project:
  - macOS section: `1214291024165659`
  - iOS section: `1214290879396596`
  - Fallback (`Untitled section`, no platform): `1214294661819891` — older tasks predating the split live here; query as a fallback when the platform section returns no match, but always **create** new tasks in the platform section.
- **Sentry MCP `list_issues` query uses Sentry's native syntax**, not natural language. Key filters:
  - `app_version:1.186.*` — events tagged with any version in the `1.186.x` series (wildcard, unquoted); use `app_version:1.186.0` for an exact version. Works across main app + extensions.
  - `firstRelease:[DuckDuckGo@1.186.0,com.duckduckgo.macos.vpn.network-extension@1.186.0,...]` — issues *first seen* in these releases (new regressions); list must include every release string for the version, not just the main-app prefix
  - `is:unresolved` — exclude resolved
- **Short-IDs (e.g. `APPLE-MACOS-BE7`) resolve on both `ddg.sentry.io` and `errors.duckduckgo.com`** — no need to fetch numeric issue IDs.
- **Sentry Crash Group ID custom field (`1214294661819893`) is comma-separated.** A single tracking task can claim multiple Sentry short-IDs by listing them in the custom field separated by commas (e.g. `APPLE-IOS-D6MW,APPLE-IOS-D6N6,APPLE-IOS-D7YC`). Use this to merge sibling Sentry issues (same culprit / same root cause) into one tracking task instead of one task per Sentry short-ID. The Asana custom-field search is substring-match, so searching for any one of the listed short-IDs will return the merged task.
- **Tracking-task fix-version tags.** When a tracking task is closed because the fix shipped, the closer adds a tag of the form `<platform>-app-release-X.Y.Z` (e.g. `macos-app-release-1.188.0`, `ios-app-release-7.220.0`). Multiple tags may accumulate over time if the issue regressed and was fixed again. The **highest** version among these tags is the most recent claimed fix. The pre-flight lookup in step 5 uses these tags to decide whether to skip, reopen, or proceed with culprit investigation.

## Workflow

1. **Load MCP tools** via ToolSearch:
   - `mcp__sentry__find_projects`, `mcp__sentry__find_releases`, `mcp__sentry__list_issues`, `mcp__sentry__get_sentry_resource`
   - `mcp__plugin_asana_asana__asana_get_task`, `mcp__plugin_asana_asana__asana_update_task`, `mcp__plugin_asana_asana__asana_search_tasks`, `mcp__plugin_asana_asana__asana_create_task`

   **Resolve the time range.** If the user supplied one, use it verbatim (validate it's a Sentry-style relative duration: `<integer><h|d|w>`). If omitted, run `date +%u` via Bash to get today's weekday number; `1` (Monday) → default to `72h`, anything else (`2`–`7`) → default to `24h`. Hold the resolved value as `<TIME_RANGE>` for use in steps 3 and 7, and surface it in the report body. The time range never affects step 2's crash-free check.
2. **Resolve releases + version filter.** Call `find_releases` with `query="<version>"` (e.g. `1.186`) to enumerate all release strings matching the series — needed for `firstRelease:` in step 3. Keep **all** of them (main app + extensions — do not filter down to a single prefix). For event matching, build the `app_version` filter directly from the user input: a series like `1.186` becomes `app_version:1.186.*`, an exact version like `1.186.0` stays `app_version:1.186.0`.

   **Match the user-supplied version literally.** The version parameter is authoritative. Never substitute a different version (e.g. falling back to a previously-shipped release because the requested one looks "wrong" or returns no data). If you suspect a typo, ask the user; do not silently retarget.

   **Crash-free release short-circuit (runs before step 3).** If `find_releases(query="<version>")` returns no releases **and** a confirmation query `list_issues(query="is:unresolved app_version:<version_filter>", sort="freq", limit=1)` returns zero issues, the version is a **crash-free release** — typically an internal-testing or code-frozen build that has no events in Sentry yet. **Do not add `lastSeen:-<TIME_RANGE>` to this query** — the short-circuit asks "does this version have *any* Sentry data ever?", not "any data in the last X hours." Filtering by time would mark older releases with stale events as falsely crash-free. This is a valid outcome of the check, not an error: pre-release runs exist specifically to verify there are no new crashes in internal testing. File the "Crash-free release" report (template below) as a **new subtask** of the user-supplied parent task via `asana_create_task(parent="<PARENT_GID>", name="Sentry summary - <platform> <version> - <YYYY-MM-DD>", html_notes="<body>...</body>")`, and **STOP** — do not run steps 3–11. Do not query a previous version's data, do not file tracking tasks, do not dispatch subagents.
3. **Two Sentry queries, sorted by `freq`, scoped to the resolved time range:**
   - All unresolved in the series: `is:unresolved app_version:1.186.* lastSeen:-<TIME_RANGE>` (wildcard) or `is:unresolved app_version:1.186.0 lastSeen:-<TIME_RANGE>` (exact) — limit 30+. Pass the values unquoted; quoting (e.g. `app_version:"1.186.*"` or `lastSeen:"-24h"`) breaks matching.
   - New-in-series only: `is:unresolved firstRelease:[<all releases from step 2>] lastSeen:-<TIME_RANGE>` — limit 50+ (iOS routinely hits 60–70 new issues). Include extension releases in the list or you'll miss extension regressions.

   `<TIME_RANGE>` is the value resolved in step 1 (e.g. `24h`, `72h`, `7d`). The `lastSeen:-Xh` filter restricts to issues whose latest event falls inside the window — exactly what we want for "what crashed in the last X hours" triage. Note: `list_issues` has no separate `statsPeriod` parameter; the filter must live inside `query`.
4. **Classify severity** (use both user count and new-vs-pre-existing):
   - 🔴 HIGH: new-in-version AND a visible cluster (≥3 issues in same subsystem) OR new-in-version with ≥10 users
   - 🟡 MEDIUM: new-in-version, single occurrence, app-code culprit
   - 🟢 LOW: new-in-version but OS-level, Swift-runtime internals, Jetsam OOM on `main`, or symbol-less
   - ⚠️ Pre-existing: still firing but not new — list by user count, do not attribute blame
5. **Pre-flight: existing tracking-task lookup — runs BEFORE culprit investigation and gates the rest of the workflow.** For each new-in-version issue (or cluster sibling, after the culprit-grouping in step 9), look up the matching tracking task in `Sentry Crash Reports` keyed on the **Sentry Crash Group ID** custom field. Use the same search shape documented in step 9:
   ```
   asana_search_tasks(workspace="137249556945",
     projects.any="1214294661819890",
     sections.any="<PLATFORM_SECTION>",
     custom_fields.1214294661819893.value="<SHORT_ID>",
     opt_fields="name,permalink_url,custom_fields,memberships.section.gid,tags,tags.name,completed")
   ```
   `completed` and `tags.name` are required fields for the gating logic. Split the returned `custom_fields` value on commas and require an **exact element match** (substring matches are false positives — see step 9). Fall back to `sections.any="1214294661819891"` only if the platform section misses.

   Five outcomes per cluster:
   - **No existing task** → continue with steps 6–8 (culprit investigation + subagent) and create the tracking task in step 9.
   - **Existing task is open (incomplete)** → work is already in flight. Capture `permalink_url` for the main report; **skip culprit investigation and subagents** for this cluster.
   - **Existing task is completed AND tagged with a `<platform>-app-release-X.Y.Z` whose version is greater than the analysed version** (e.g. tracking task tagged `macos-app-release-1.188.0` while analysing `1.187.0`) → fix already shipped in a later release; the issue is expected to keep firing for users still on the analysed version. **Skip culprit investigation and subagents.** Capture `permalink_url`; classify under a 🟡 MEDIUM "Fix already shipped in vX.Y.Z" bucket in the main report (no work to track for this release).
   - **Existing task is completed AND the highest fix-version tag is ≤ the analysed version (or there is no version tag at all)** → this is a regression: the supposed fix didn't hold. **Reopen the existing task** with `asana_update_task(task_id=<gid>, completed=false)`, then proceed with steps 6–8 (full culprit investigation) so step 9 can append a fresh root-cause analysis to the reopened task's body. Treat the issue as new-in-version for severity purposes.
   - **Existing task is completed AND its name starts with `[Duplicate]`** → a team member has marked this issue as a duplicate of another tracking task. The duplicate task's description typically contains a link to the canonical (parent) task. Look up the parent task via `asana_get_task` (with `opt_fields="tags,tags.name,completed,permalink_url"`), then apply the same gating logic against the **parent task's** fix-version tags and completion status — i.e. treat the parent task as if it were the lookup result and evaluate the four outcomes above. This prevents investigating culprits for issues whose root cause is already tracked and potentially already fixed under a different Sentry short-ID.

   **Tag parsing.** Tag names look like `macos-app-release-1.188.0` or `ios-app-release-7.220.0`. Strip the `<platform>-app-release-` prefix; parse the remainder as semver-ish (`MAJOR.MINOR.PATCH`); compare numerically against the analysed version. If multiple version tags exist on one task, use the **highest** for the gating decision.
6. **Git blame each new issue that survived step 5's gate** (i.e. no existing task, or an existing task that was just reopened). For each culprit symbol (e.g. `TabBarViewController.tabCollectionViewModel`):
   - `grep` the symbol to find the file + line
   - `git blame -L <line-range>` on that region
   - `git log -n 5 --since=<~2 months ago>` on the file for recent PRs
   - Capture PR numbers from commit subjects (GitHub auto-appends `(#NNNN)`)
   - If the culprit is too generic (`value`, `NSBundle.module`, `main`, OS symbols) — skip attribution
7. **Compose URL-rewritten issue links.** Every `https://ddg.sentry.io/issues/<SHORT_ID>` becomes `https://errors.duckduckgo.com/organizations/ddg/issues/<SHORT_ID>/?project=<PROJECT_FILTER>`. Query links use `/organizations/ddg/issues/?project=<PROJECT_FILTER>&query=...&statsPeriod=<TIME_RANGE>` — substitute the value resolved in step 1 (e.g. `statsPeriod=24h`, `statsPeriod=72h`) so the linked Sentry view matches the analysis window. Single-issue URLs remain unfiltered (no `statsPeriod`).
8. **Root-cause analysis (subagents) — for each new issue with an informative stacktrace that survived step 5's gate.** Especially worth investigating: unhandled exceptions where the message itself encodes the contract violation (e.g. `NSInternalInconsistencyException: Invalid update: ...`), or app-code culprits with a deep first-party call chain.

   **Eligibility rule (count first-party frames, don't eyeball the leaf).** Count the DuckDuckGo / first-party frames in the stacktrace. If there are **≥3 first-party frames**, the issue is eligible — dispatch the subagent. The fact that the *leaf* (deepest frame, where the fault occurred) is in libobjc, UIKit, Swift runtime, libsystem, JavaScriptCore, or other OS/runtime code does **not** disqualify the issue. SIGBUS/SIGSEGV inside `__sel_registerName`, `objc_msgSend`, `_swift_release`, `bmalloc`, `WKWebView` internals, etc. routinely have first-party root causes (renamed `@IBAction`, over-released object, retain-cycle break, allocation pressure from a specific code path) — the subagent's job is to investigate and either confirm or rule that out.

   **Legitimate skips (the only ones).** Skip *only* when:
   - Culprit is a generic symbol with no useful attribution: `value`, `NSBundle.module`, `__pthread_kill`, `objc_release`, `main` (when the rest of the trace is also OS-frames-only).
   - The stacktrace contains **no first-party frames at all** (pure OS/runtime trace — "OS-frames-only" means literally zero DuckDuckGo frames, not "leaf is in OS code").
   - Crash is Jetsam OOM SIGKILL on `main` (LOW classification — see step 4).
   - Step 5 routed the issue to the "fix already shipped in vX.Y.Z" bucket.

   Dispatch one **general-purpose** subagent per qualifying issue **in parallel** (single message, multiple Agent tool calls). Brief each subagent with: short-ID, exception class + message, the full stacktrace from `get_sentry_resource`, the suspect PR(s) from step 6, and a concrete instruction to (a) trace the call chain backward to its origin in this repo, (b) identify the invariant being violated *or* explicitly rule out an app-code root cause if the evidence points elsewhere, and (c) return a short structured report (root-cause summary, numbered call chain 4–8 steps, likely category, optional fix sketch). Cap responses ("under 250 words"). A "we investigated and concluded this is OS-runtime / hardware noise — not actionable" finding is a valid result; **an empty Root Cause Analysis section in the tracking task is not.** Use the analyses to populate the per-issue tracking tasks in step 9.
9. **Per-issue tracking task in `Sentry Crash Reports` (create-if-missing, section-scoped, with sibling merging).** Pick `<PLATFORM_SECTION>` for the run: macOS → `1214291024165659`, iOS → `1214290879396596`. **Group new issues into clusters by culprit symbol** before this step (the cluster-grouping must happen before step 5's lookup so the lookup runs once per cluster, not once per short-ID) — multiple Sentry short-IDs with the same culprit (e.g. four SIGABRTs in `TabViewCell.updatePreviewToDisplay`) become **one** tracking task whose custom field lists all the sibling short-IDs comma-separated. Different culprits → different tasks, even if they share a root cause. Different exception types with meaningfully different call chains can also get separate tasks (e.g. `_ArrayBuffer._consumeAndCreateNew` SIGABRT vs `WKUserScript.init` bmalloc SIGTRAP — both OOM but distinct allocation sites).

   The lookup itself was already performed in step 5. Outcomes:
   - **Found in step 5 (open task or completed-with-future-fix-tag):** capture `permalink_url`; reference it in the main report's per-issue line as `· <a href="...">tracking</a>`. If the existing task lacks one of the new sibling short-IDs you would otherwise file under it, you may extend its custom field with the missing IDs (`asana_update_task` with `custom_fields={"1214294661819893": "<existing>,<new1>,<new2>"}`); otherwise leave it alone. Do **not** rewrite the body of an existing task.
   - **Found in step 5 (completed-and-reopened as regression):** the task already has a body; append a regression note to it via `asana_update_task` with an `html_notes` that preserves the existing content and adds a "Regression seen in <version>" section with the fresh root-cause analysis from step 8 (read the existing `html_notes` first via `asana_get_task` so you can preserve it). Capture `permalink_url`.
   - **Not found in step 5:** create one task with `asana_create_task`. **Always create in the platform section, never the fallback:**
     - `name`: `<error type> <culprit>` — mirrors the convention in existing tasks (e.g. `EXC_CRASH TabBarViewController.tabCollectionViewModel`, `NSInternalInconsistencyException CollectionView.reloadItems`).
     - `project_id`: `1214294661819890`
     - `section_id`: `<PLATFORM_SECTION>` (macOS or iOS — required so the task lands in the right column)
     - `custom_fields`: `{"1214294661819893": "<SHORT_ID_1>,<SHORT_ID_2>,..."}` — comma-separated list of every Sentry short-ID in the cluster so future runs dedupe against any of them.
     - `html_notes`: per-issue template (see "Per-issue tracking task body" below)
     - Capture the new task's `permalink_url` and reference it in the main report — every per-issue line in the main report (whether parent or sibling) points at the same merged tracking task.

   Look up the search shape:
   ```
   asana_search_tasks(workspace="137249556945",
     projects.any="1214294661819890",
     sections.any="<PLATFORM_SECTION>",
     custom_fields.1214294661819893.value="<SHORT_ID>",
     opt_fields="name,permalink_url,custom_fields,memberships.section.gid,tags,tags.name,completed")
   ```
   The `value` filter is substring-match. The custom field is comma-separated, so a returned task may contain multiple short-IDs (e.g. `APPLE-IOS-D6MW,APPLE-IOS-D6N6,APPLE-IOS-D7YC`). **Split the returned value on commas and verify the queried short-ID matches one of the elements exactly** (substring matches like `APPLE-IOS-D6N` matching `APPLE-IOS-D6N6` are false positives). If not an exact element match, consider it not found.
10. **File the main report as a new subtask of the user-supplied parent task** via `asana_create_task(parent="<PARENT_GID>", name="Sentry summary - <platform> <version> - <YYYY-MM-DD>", html_notes="<body>...</body>")` — structure below. `<platform>` is `iOS` or `macOS` exactly as supplied; `<version>` is the user's input (e.g. `1.186` or `1.186.0`); `<YYYY-MM-DD>` is today's date. **Never write to the parent task itself** (no `asana_update_task` on the parent — its body is owned by humans). Each HIGH/MEDIUM line in the body **leads with the tracking-task link** captured in step 9, then lists the Sentry short-ID(s), then stats (users + events), then a 1–2 sentence description with inline PR links. Lead-with-tracking is the readability win — readers scanning the list jump to the per-issue triage doc in one click instead of hunting at the end of a paragraph. LOW and Pre-existing entries skip the tracking link (no task created) and lead with the Sentry short-ID. Issues that step 5 routed to the "Fix already shipped in vX.Y.Z" bucket get their own MEDIUM sub-section in the main report and a one-line note explaining no further action is needed for this release.
11. **PII: initials + PR links only, never full names.** The DDG asana-exfiltration hook scans task writes and blocks full employee names — even when the user approves in chat (the hook can't see chat). Use first-letter-of-first-name + first-letter-of-last-name initials, and link the PR so the author is one click away on GitHub. If even initials get blocked, fall back to PR-number-only attribution. This applies to both the main report **and** the per-issue tracking task bodies created in step 9.

## Asana task structure (html_notes)

```html
<body>
<strong>{iOS|macOS} Sentry review — releases {version}.x</strong>

Reviewed on {today}. Scope: unresolved issues with events in {release list} whose latest event falls within the last <code>{TIME_RANGE}</code>.

<strong>Totals</strong>
• N unresolved issues with events in {version}.x in the last {TIME_RANGE}
• M issues first seen in {version}.x (new regressions) with events in the last {TIME_RANGE}

Full list in Sentry: <a href="...">unresolved in {version}.x</a>
New-in-{version}.x only: <a href="...">firstRelease filter</a>

<em>Each entry below: <strong>tracking task</strong> · Sentry short-ID(s) · stats · description. Blame uses initials + PR links — the PR page shows the author.</em>

<hr>

<strong>🔴 HIGH — {cluster name or "new high-volume"}</strong>
• <a href="...">Tracking</a> · <a href="...">SHORT-ID</a>[, <a href="...">SHORT-ID-2</a>, ...] · {U} users, {E} events · {signal} in <code>culprit</code> — {1–2 sentence description}. Likely caused by <a href="...">#NNNN</a> ({INITIALS}).

<strong>🟡 MEDIUM — Other new issues</strong>
• <a href="...">Tracking</a> · <a href="...">SHORT-ID</a> · ...

<strong>🟡 MEDIUM — Fix already shipped in v{later-version}</strong>
• <a href="...">Tracking</a> · <a href="...">SHORT-ID</a> · {U} users, {E} events · {signal} in <code>culprit</code> — {one-line description}. Tracking task tagged <code>{platform}-app-release-{later-version}</code>; users on {analysed-version} will continue to see this until they update. No further action needed for this release.

<strong>🟢 LOW — OS-level / low signal / Jetsam OOM</strong>
• <a href="...">SHORT-ID</a> · {U} users · {signal} <code>culprit</code> — {one-liner; no tracking task created for LOW}

<hr>

<strong>⚠️ Pre-existing (not new, but high-volume)</strong>
• <a href="...">SHORT-ID</a> · {U} users, {E} events · {signal} <code>culprit</code> — {one-liner; no tracking task}

<hr>

<strong>Recommended next step</strong>
{Numbered priority list. Each item should link directly to the corresponding tracking task in the `Sentry Crash Reports` Asana project (captured in step 9) so the reader can jump from the recommendation to the per-issue triage doc in one click. Where a recommendation covers a family of crashes spanning multiple tracking tasks, link each tracking task inline (e.g. "Tracked across <a href="...">D6N7+D7RR</a>, <a href="...">D8BH</a>, <a href="...">D7SV</a>"). Include a brief pointer to the suspected root-cause PR.}

<strong>Initials legend</strong>
{initials} — see PR links for authors.
</body>
```

## Crash-free release report (html_notes)

Used by step 2's short-circuit when `find_releases` returns no releases and `list_issues` returns zero issues for the requested version. File this as a new subtask of the user-supplied parent task (same `asana_create_task(parent=..., name="Sentry summary - <platform> <version> - <YYYY-MM-DD>", html_notes=...)` call as step 10) and stop — no tracking tasks, no subagents, no fallback to a prior version.

```html
<body>
<strong>{iOS|macOS} Sentry review — release {version}</strong>

Reviewed on {today}. Scope: unresolved issues with events in <code>app_version:{version_filter}</code>.

<strong>Result: crash-free release</strong>
• <code>find_releases(query="{version}")</code> returned no releases on the <code>{apple-ios|apple-macos}</code> project.
• <code>list_issues(query="is:unresolved app_version:{version_filter}")</code> returned zero issues.

This outcome is expected for builds that are still in internal testing or code freeze: no events have reached Sentry yet, so there are no new regressions to triage for this version.

<strong>Recommended next step</strong>
Re-run <code>/ddg-sentry-report {project} {version} {asana_url}</code> once the build has shipped to a wider audience and Sentry has accumulated events.
</body>
```

## Per-issue tracking task body (html_notes)

Derived from task `1214265935091414`. Created in step 9 when no existing task is found for the short-ID (or when reopening a regressed task — in the regression case, append a "Regression seen in <version>" section to the existing body rather than rewriting it). Omit the **Pull request** section — these tasks are filed during triage, before any fix is in flight. Include the `Likely caused by` line only if step 6 produced a confident attribution; drop the **Root Cause Analysis** + **Call chain** + **Likely category** + **Fix sketch** sections only when a subagent legitimately did not run per step 8's skip rules (just keep the Sentry link header). If the subagent *did* run, its output is required — even a "not actionable, OS-runtime noise" conclusion goes in as a one-paragraph RCA + brief call chain + likely category.

Match the existing-task layout exactly — the leading content has intentional newlines around the `<a>` block; the analysis section is compacted (no newlines between tags) per `asana-rich-text` rules:

```html
<body>Sentry crash:
<a href="https://errors.duckduckgo.com/organizations/ddg/issues/<SHORT_ID>/?project=<PROJECT_FILTER>">https://errors.duckduckgo.com/organizations/ddg/issues/<SHORT_ID>/?project=<PROJECT_FILTER></a>

Likely caused by <a href="https://github.com/duckduckgo/apple-browsers/pull/<NNNN>">https://github.com/duckduckgo/apple-browsers/pull/<NNNN></a>
<hr/>
<h2>Root Cause Analysis</h2>{1–2 sentence summary from the subagent — either the violated invariant, or "not an app bug; here's why" if the subagent ruled out an app-code root cause}
<h2>Call chain</h2><ol><li>{step 1}</li><li>{step 2}</li>...</ol>
<h2>Likely category</h2>{one of: real bug worth fixing | hardware/OS-runtime noise | environmental/data-shape edge case | unclear, watch for repeats}
<h2>Fix sketch</h2>{optional — concrete code change if obvious; otherwise "None warranted" or recommendation to monitor}</body>
```

## Quick reference

**Resolve parent task GID from Asana URL:** the numeric segment after `/task/` (e.g. `.../task/1214175611004136` → `1214175611004136`). This is the **parent** under which the summary subtask is created — never the write target.

**Subtask name format:** `Sentry summary - <platform> <version> - <YYYY-MM-DD>` (e.g. `Sentry summary - macOS 1.186 - 2026-04-30`). Platform matches the user-supplied param (`iOS` / `macOS`); version is the user-supplied value verbatim; date is today.

**`asana_get_task` requires `opt_fields="tags,tags.name"`** — the data-protection hook rejects queries without it with a `RETRY REQUIRED` error. Include it on every get call.

**Asana `html_notes` must be wrapped in `<body>...</body>`.** Use `<a href="...">` for plain links (not @-mentions). `<strong>`, `<em>`, `<code>`, `<hr>` supported.

## Common mistakes

| Mistake | Fix |
|---|---|
| Passing `regionUrl=https://errors.duckduckgo.com` to Sentry MCP | Omit `regionUrl`. MCP only allows `sentry.io` hosts; it returns `ddg.sentry.io` URLs you rewrite client-side. |
| Using `list_issues` with `query="release:1.186.0"` (string) | Prefer `app_version:1.186.0` (exact) or `app_version:1.186.*` (series) for event matching. |
| Quoting the `app_version` value (e.g. `app_version:"1.186.*"`) | Breaks wildcard matching. Pass the value unquoted. |
| Substituting a different version when the requested one returns no events | The user-supplied version is authoritative — match it literally. If `find_releases` returns no releases AND `list_issues` returns zero issues, take the step 2 short-circuit: write the "Crash-free release" report and stop. Do NOT silently retarget to a previously-shipped version (e.g. querying `7.217.0` when the user asked for `7.218.0`). Pre-release runs exist specifically to verify that internal-testing builds have no new crashes; substituting a different version files redundant tracking tasks against the wrong Asana task and defeats the check. If a version looks like a typo, ask the user. |
| Investigating culprits for a `[Duplicate]` tracking task without checking the parent task's tags | When a tracking task is marked `[Duplicate]`, look up the parent task it points to and use that task's fix-version tags for the skip/reopen/investigate gating decision. |
| Filtering events by `release:DuckDuckGo@...` (single prefix) | Silently drops extension crashes (e.g. `com.duckduckgo.macos.vpn.network-extension@...`). Use `app_version:` for the event-matching query; use the full multi-prefix release list only for `firstRelease:`. |
| Confusing `app_version:` vs `firstRelease:` | `app_version:` = events whose version tag matches (cross-target). `firstRelease:` = issue's *first-ever* event was in one of these release strings (true regressions) — needs explicit release strings, so include all targets. |
| Writing full employee names to Asana | Hook blocks it. Use initials + PR links. If the hook blocks even initials, fall back to PR-number-only. |
| Retrying a BLOCKED Asana response with different params | Never. The Asana data-protection policy says: accept the block. Ask the user how to proceed. |
| Trusting the "culprit" field for blame when generic | Symbols like `value`, `NSBundle.module`, `__pthread_kill`, `objc_release`, `main` are not attributable. Skip them. |
| Forgetting the time-range filter on step-3 queries | Both `list_issues` calls in step 3 must include `lastSeen:-<TIME_RANGE>` (the value resolved in step 1 — `24h` non-Monday default, `72h` Monday default, or the user-supplied override). Without it, the queries return all-time data and the report becomes a mixed history dump instead of "what crashed this window." |
| Quoting the `lastSeen` value (e.g. `lastSeen:"-24h"`) | Same trap as `app_version`. Pass the value unquoted: `lastSeen:-24h`. |
| Applying the time-range filter to the step-2 crash-free check | The crash-free short-circuit (`find_releases` empty + `list_issues` zero) is a global "is there any data for this version" question. Adding `lastSeen:-<TIME_RANGE>` causes false crash-free readings when a version has events outside the window. Keep step 2's confirmation query unfiltered by time. |
| Hard-coding `&statsPeriod=7d` in URLs | Use the resolved `<TIME_RANGE>` value in the rewritten query URLs (step 7) so the linked Sentry view matches what the report analyzed. Single-issue URLs stay unfiltered. |
| Computing the Monday default from the wrong clock | Use `date +%u` via Bash (the runtime's local time) — not the hard-coded date in the conversation context. The user runs this skill from various time zones and sessions can cross day boundaries. |
| Treating every iOS SIGKILL as a bug | Most SIGKILL+`main` crashes on iOS are Jetsam memory kills, not app bugs. LOW severity unless volume spikes or culprit is specific app code. |
| Forgetting `&project=<filter>` in errors.duckduckgo.com query URLs | The project filter is required for listing pages to render correctly; optional but recommended for single-issue URLs. |
| Skipping the find-or-create lookup and creating a duplicate tracking task | Always run the step 5 `asana_search_tasks` lookup against `Sentry Crash Reports` filtered by `custom_fields.1214294661819893.value=<SHORT_ID>` first. The custom field is comma-separated, so split the returned value on `,` and require an **exact element** match — substring matches like `APPLE-MACOS-BD7` matching `APPLE-MACOS-BD70` (or matching `APPLE-MACOS-BD7,APPLE-MACOS-XYZ`) are false positives. |
| Investigating culprits before checking for an existing tracking task | The step 5 pre-flight lookup gates everything. If a completed task tagged with a later release exists (e.g. `macos-app-release-1.188.0` while analysing `1.187.0`), skip culprit investigation entirely — fix already shipped, expected to keep firing on the analysed version. If a completed task tagged with the analysed release or earlier (or no version tag) exists, **reopen** it (`asana_update_task` with `completed=false`) and treat as a regression. Only run git blame + subagents for issues that survived this gate. |
| Forgetting `completed` and `tags.name` in the step 5 search `opt_fields` | Without these, you can't tell whether an existing task is open vs. closed, or read the fix-version tag. Always include `opt_fields="name,permalink_url,custom_fields,memberships.section.gid,tags,tags.name,completed"`. |
| Misreading the fix-version tag (e.g. ignoring older tags when newer ones exist) | Multiple `<platform>-app-release-X.Y.Z` tags can accumulate over time. The **highest** version is the most recent claimed fix; that's the one to compare against the analysed version. |
| Filing one tracking task per Sentry short-ID for sibling clusters | Cluster siblings (same culprit, same root cause) collapse into ONE tracking task. Put all the short-IDs comma-separated in the `Sentry Crash Group ID` custom field (e.g. `APPLE-IOS-D6MW,APPLE-IOS-D6N6,APPLE-IOS-D7YC,APPLE-IOS-D8KC`). The substring-match dedupe lookup still finds the merged task on any of the listed IDs. |
| Forgetting to set `custom_fields` on the new tracking task | Without `{"1214294661819893": "<SHORT_ID>[,<SHORT_ID>...]"}`, future runs of this skill will create duplicates because the dedupe lookup will miss. |
| Running root-cause subagents serially | Dispatch them in parallel (single message, multiple Agent tool calls) — they're independent and waiting serially is wasteful. Skip subagents entirely when the culprit is generic or OS-only — there's nothing to analyze. Also skip when step 5 routed the issue to the "fix already shipped" bucket. |
| Skipping the step-8 subagent because the crash leaf is in libobjc / UIKit / Swift runtime | Look at the *full* trace, not just the leaf. If the trace has ≥3 first-party (DuckDuckGo) frames before reaching the OS leaf, dispatch the subagent — the root cause can absolutely be in app code (renamed `@IBAction`, over-released object, retain-cycle break, allocation pressure from a specific path) even when the fault surfaces inside `__sel_registerName`, `objc_msgSend`, `bmalloc`, or `WKWebView` internals. The "OS-frames-only" skip applies only when there are *no* first-party frames at all. |
| Creating a tracking task with no Root Cause Analysis section | If a subagent ran for the issue, its output must populate the tracking-task body. If you decide to skip the subagent under one of the legitimate skip rules in step 8, that's fine — but never create a tracking task with just a Sentry link and nothing else when a subagent should have run. A "concluded not actionable, here's why" RCA is a valid result; an empty body is not. |
| Searching across the whole `Sentry Crash Reports` project instead of the platform section | Always scope the primary search to the platform section (`sections.any=<PLATFORM_SECTION>`). Only fall back to the `Untitled section` (`1214294661819891`) when the platform-section search misses — that's where pre-split tasks still live. |
| Creating a new tracking task in the `Untitled section` (the fallback) | The fallback is read-only for *new* tasks. New tasks always go in the platform section (`section_id=1214291024165659` for macOS, `1214290879396596` for iOS). |
| Burying the tracking-task link at the end of the per-issue line (`SHORT-ID — signal · culprit (U users) · tracking`) | Hard to scan when descriptions wrap across multiple visual lines. Lead with `Tracking · SHORT-ID(s) · stats · description` so the actionable link is the first thing the reader sees. LOW and Pre-existing entries (no tracking task) lead with the Sentry short-ID instead. |

## Example invocation

> "Post a Sentry summary subtask under {asana_url} for macOS 1.186 — severity, new issues, blame." (no explicit time range — the skill picks the default)

1. Extract parent task GID `1214175611004136`, project `apple-macos`, version series `1.186`. No time range supplied → run `date +%u` via Bash. If today is Monday (`1`), use `72h`; otherwise `24h`. Hold this as `<TIME_RANGE>`. The summary will be filed as a new subtask under the parent.
2. `find_releases(query="1.186")` → `DuckDuckGo@1.186.0`, `DuckDuckGo@1.186.1`, `com.duckduckgo.macos.vpn.network-extension@1.186.0`, `com.duckduckgo.macos.vpn.network-extension@1.186.1`, ... (keep all — needed for `firstRelease:`).
3. `list_issues(query="is:unresolved app_version:1.186.* lastSeen:-24h", sort="freq", limit=30)` — wildcard catches main app + extensions in one query, scoped to the resolved window. (For an exact version: `app_version:1.186.0`. For Monday: `lastSeen:-72h`.)
4. `list_issues(query="is:unresolved firstRelease:[DuckDuckGo@1.186.0,DuckDuckGo@1.186.1,com.duckduckgo.macos.vpn.network-extension@1.186.0,com.duckduckgo.macos.vpn.network-extension@1.186.1,...] lastSeen:-24h", sort="freq", limit=50)`.
5. **Pre-flight lookup (gates the rest).** Group new issues into clusters by culprit. For each cluster: `asana_search_tasks(workspace="137249556945", projects.any="1214294661819890", sections.any="1214291024165659", custom_fields.1214294661819893.value="<SHORT_ID>", opt_fields="name,permalink_url,custom_fields,memberships.section.gid,tags,tags.name,completed")`. For each result, check `completed` and the highest `<platform>-app-release-X.Y.Z` tag. Branch: not-found → continue; open → skip culprit work, just link; completed-with-tag-greater-than-1.186 → "fix shipped" bucket, skip culprit work; completed-with-tag-≤-1.186-or-no-tag → reopen via `asana_update_task(completed=false)` and treat as regression.
6. For each new issue that survived step 5: grep culprit symbol → `git blame` → capture PR from commit `(#NNNN)`.
7. Rewrite all `ddg.sentry.io` URLs to `errors.duckduckgo.com/organizations/ddg/issues/<SHORT_ID>/?project=6`.
8. For each new issue that survived step 5 with ≥3 first-party frames in the stacktrace (regardless of whether the crash leaf is in app code, libobjc, UIKit, Swift runtime, etc.), dispatch a parallel general-purpose subagent (single message, multiple Agent tool calls) to produce a root-cause summary + numbered call chain + likely category. Skip *only* under the four legitimate skip rules in the step 8 description (generic culprit, no first-party frames at all, Jetsam OOM, fix-already-shipped bucket).
9. For clusters that step 5 found no task for: `asana_create_task` with `name`, `project_id="1214294661819890"`, `section_id="1214291024165659"` (macOS), `custom_fields={"1214294661819893":"<SHORT_ID_1>,<SHORT_ID_2>,..."}` (all sibling short-IDs comma-separated), and `html_notes` from the per-issue template. For reopened-regression clusters: append a "Regression seen in 1.186.x" section to the existing `html_notes`. Capture `permalink_url`.
10. `asana_create_task(parent="1214175611004136", name="Sentry summary - macOS 1.186 - 2026-04-30", html_notes="<body>...</body>")` — files the main report as a new subtask of the user-supplied parent task. Never write to the parent itself. **Lead each HIGH/MEDIUM line with the tracking-task link**, then the Sentry short-ID(s), then stats, then the description — e.g. `• <a href="...task/14310448135804">Tracking</a> · <a href="...issues/APPLE-IOS-D6FM/...">D6FM</a> · 153 users, 263 events · SIGABRT in <code>TabViewController.ViewSettings?</code> — NSInternalInconsistencyException ...`. Issues from step 5's "fix already shipped" bucket get their own MEDIUM sub-section. LOW and Pre-existing lines lead with the Sentry short-ID (no tracking task).
