---
name: ddg-sentry-report
description: Invoke ONLY when the user explicitly runs `/ddg-sentry-report` or names this skill by name (e.g. "use ddg-sentry-report for macOS 1.186"). Do NOT auto-invoke from symptom/intent matching — producing a Sentry report writes to a shared Asana task and must be user-initiated. If the user asks about Sentry issues or crash triage without naming this skill, answer directly instead. Accepts three parameters when explicitly invoked: Asana task URL, project (iOS or macOS), and version (e.g. 1.186 or 7.217).
---

# ddg-sentry-report

## Overview

Produces a structured Sentry crash triage report for a DuckDuckGo Apple release and writes it into a target Asana task. Distinguishes pre-existing issues from new-in-version regressions, sorts by severity, attributes likely authors via git blame (initials + PR links only — never full names).

## Parameters

| Param | Example | Notes |
|---|---|---|
| Asana task URL | `https://app.asana.com/1/137249556945/task/1214175611004136` | Extract the task GID from the URL path. |
| Project | `iOS` or `macOS` | Maps to Sentry project slug `apple-ios` / `apple-macos`. A single version ships under multiple release strings (main app + extensions) — see Non-obvious constants. |
| Version | `1.186.0`, `1.186.*`, or `1.186` (macOS) / `7.216.x` (iOS) | Pass-through: an exact version (`1.186.0`) goes to `app_version:1.186.0`; a series (`1.186` or `1.186.*`) becomes the wildcard `app_version:1.186.*`. Always use the wildcard form when the user supplies a series. |

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

## Workflow

1. **Load MCP tools** via ToolSearch:
   - `mcp__sentry__find_projects`, `mcp__sentry__find_releases`, `mcp__sentry__list_issues`, `mcp__sentry__get_sentry_resource`
   - `mcp__plugin_asana_asana__asana_get_task`, `mcp__plugin_asana_asana__asana_update_task`, `mcp__plugin_asana_asana__asana_search_tasks`, `mcp__plugin_asana_asana__asana_create_task`
2. **Resolve releases + version filter.** Call `find_releases` with `query="<version>"` (e.g. `1.186`) to enumerate all release strings matching the series — needed for `firstRelease:` in step 3. Keep **all** of them (main app + extensions — do not filter down to a single prefix). For event matching, build the `app_version` filter directly from the user input: a series like `1.186` becomes `app_version:1.186.*`, an exact version like `1.186.0` stays `app_version:1.186.0`.
3. **Two Sentry queries, sorted by `freq`:**
   - All unresolved in the series: `is:unresolved app_version:1.186.*` (wildcard) or `is:unresolved app_version:1.186.0` (exact) — limit 30+. Pass the value unquoted; quoting (e.g. `app_version:"1.186.*"`) breaks wildcard matching.
   - New-in-series only: `is:unresolved firstRelease:[<all releases from step 2>]` — limit 50+ (iOS routinely hits 60–70 new issues). Include extension releases in the list or you'll miss extension regressions.
4. **Classify severity** (use both user count and new-vs-pre-existing):
   - 🔴 HIGH: new-in-version AND a visible cluster (≥3 issues in same subsystem) OR new-in-version with ≥10 users
   - 🟡 MEDIUM: new-in-version, single occurrence, app-code culprit
   - 🟢 LOW: new-in-version but OS-level, Swift-runtime internals, Jetsam OOM on `main`, or symbol-less
   - ⚠️ Pre-existing: still firing but not new — list by user count, do not attribute blame
5. **Git blame each new issue.** For each culprit symbol (e.g. `TabBarViewController.tabCollectionViewModel`):
   - `grep` the symbol to find the file + line
   - `git blame -L <line-range>` on that region
   - `git log -n 5 --since=<~2 months ago>` on the file for recent PRs
   - Capture PR numbers from commit subjects (GitHub auto-appends `(#NNNN)`)
   - If the culprit is too generic (`value`, `NSBundle.module`, `main`, OS symbols) — skip attribution
6. **Compose URL-rewritten issue links.** Every `https://ddg.sentry.io/issues/<SHORT_ID>` becomes `https://errors.duckduckgo.com/organizations/ddg/issues/<SHORT_ID>/?project=<PROJECT_FILTER>`. Query links use `/organizations/ddg/issues/?project=<PROJECT_FILTER>&query=...&statsPeriod=7d`.
7. **Root-cause analysis (subagents) — for each new issue with an informative stacktrace.** Especially worth investigating: unhandled exceptions where the message itself encodes the contract violation (e.g. `NSInternalInconsistencyException: Invalid update: ...`), or app-code culprits with a deep first-party call chain. Skip when the culprit is generic (`value`, `__pthread_kill`, `objc_release`, `main`), when the trace is OS-frames-only, or when the crash is Jetsam OOM. Dispatch one **general-purpose** subagent per qualifying issue **in parallel** (single message, multiple Agent tool calls). Brief each subagent with: short-ID, exception class + message, the full stacktrace from `get_sentry_resource`, the suspect PR(s) from step 5, and a concrete instruction to (a) trace the call chain backward to its origin in this repo, (b) identify the invariant being violated, and (c) return a short structured report (root-cause summary, numbered call chain 4–8 steps, optional fix sketch). Cap responses ("under 250 words"). Use the analyses to populate the per-issue tracking tasks in step 8.
8. **Per-issue tracking task in `Sentry Crash Reports` (find-or-create, section-scoped, with sibling merging).** Pick `<PLATFORM_SECTION>` for the run: macOS → `1214291024165659`, iOS → `1214290879396596`. **Before creating tasks, group new issues into clusters by culprit symbol** — multiple Sentry short-IDs with the same culprit (e.g. four SIGABRTs in `TabViewCell.updatePreviewToDisplay`) become **one** tracking task whose custom field lists all the sibling short-IDs comma-separated. Different culprits → different tasks, even if they share a root cause. Different exception types with meaningfully different call chains can also get separate tasks (e.g. `_ArrayBuffer._consumeAndCreateNew` SIGABRT vs `WKUserScript.init` bmalloc SIGTRAP — both OOM but distinct allocation sites).

   For each cluster (or singleton), look up an existing task in project `1214294661819890` keyed on the **Sentry Crash Group ID** custom field (GID `1214294661819893`):
   ```
   # Primary search — the platform section (scoped lookup is faster).
   asana_search_tasks(workspace="137249556945",
     projects.any="1214294661819890",
     sections.any="<PLATFORM_SECTION>",
     custom_fields.1214294661819893.value="<SHORT_ID>",
     opt_fields="name,permalink_url,custom_fields,memberships.section.gid,tags,tags.name")
   ```
   The `value` filter is substring-match. The custom field is comma-separated, so a returned task may contain multiple short-IDs (e.g. `APPLE-IOS-D6MW,APPLE-IOS-D6N6,APPLE-IOS-D7YC`). **Split the returned value on commas and verify the queried short-ID matches one of the elements exactly** (substring matches like `APPLE-IOS-D6N` matching `APPLE-IOS-D6N6` are false positives). If not an exact element match, consider it not found.
   - **Found (in either platform section or `Untitled section` fallback):** capture `permalink_url`; reference it in the main report's per-issue line as `· <a href="...">tracking</a>`. If the existing task lacks one of the new sibling short-IDs you would otherwise file under it, you may extend its custom field with the missing IDs (`asana_update_task` with `custom_fields={"1214294661819893": "<existing>,<new1>,<new2>"}`); otherwise leave it alone.
   - **Not found for any short-ID in the cluster:** create one task with `asana_create_task`. **Always create in the platform section, never the fallback:**
     - `name`: `<error type> <culprit>` — mirrors the convention in existing tasks (e.g. `EXC_CRASH TabBarViewController.tabCollectionViewModel`, `NSInternalInconsistencyException CollectionView.reloadItems`).
     - `project_id`: `1214294661819890`
     - `section_id`: `<PLATFORM_SECTION>` (macOS or iOS — required so the task lands in the right column)
     - `custom_fields`: `{"1214294661819893": "<SHORT_ID_1>,<SHORT_ID_2>,..."}` — comma-separated list of every Sentry short-ID in the cluster so future runs dedupe against any of them.
     - `html_notes`: per-issue template (see "Per-issue tracking task body" below)
     - Capture the new task's `permalink_url` and reference it in the main report — every per-issue line in the main report (whether parent or sibling) points at the same merged tracking task.
9. **Write the main report to the user's task** via `asana_update_task` with `html_notes` — structure below. Each per-issue line should end with the per-issue tracking-task link captured in step 8 (find-or-create).
10. **PII: initials + PR links only, never full names.** The DDG asana-exfiltration hook scans task writes and blocks full employee names — even when the user approves in chat (the hook can't see chat). Use first-letter-of-first-name + first-letter-of-last-name initials, and link the PR so the author is one click away on GitHub. If even initials get blocked, fall back to PR-number-only attribution. This applies to both the main report **and** the per-issue tracking task bodies created in step 8.

## Asana task structure (html_notes)

```html
<body>
<strong>{iOS|macOS} Sentry review — releases {version}.x</strong>

Reviewed on {today}. Scope: unresolved issues with events in {release list}.

<strong>Totals</strong>
• N unresolved issues with events in {version}.x
• M issues first seen in {version}.x (new regressions)

Full list in Sentry: <a href="...">unresolved in {version}.x</a>
New-in-{version}.x only: <a href="...">firstRelease filter</a>

<em>Blame attributions are best-effort from git blame + recent commits. Initials + PR links used (not full names) — PR page shows the author.</em>

<hr>

<strong>🔴 HIGH — {cluster name or "new high-volume"}</strong>
• <a href="...">SHORT-ID</a> — <signal> · <code>culprit</code> (U users, E events) — likely: {INITIALS} (<a href="...">#PR title</a>) · <a href="...">tracking</a>

<strong>🟡 MEDIUM — Other new issues</strong>
• ...

<strong>🟢 LOW — OS-level / low signal / Jetsam OOM</strong>
• ...

<hr>

<strong>⚠️ Pre-existing (not new, but high-volume)</strong>
• <a href="...">SHORT-ID</a> — <signal> · <code>culprit</code> — U users, E events

<hr>

<strong>Recommended next step</strong>
{Numbered priority list. Each item should link directly to the corresponding tracking task in the `Sentry Crash Reports` Asana project (captured in step 8) so the reader can jump from the recommendation to the per-issue triage doc in one click. Where a recommendation covers a family of crashes spanning multiple tracking tasks, link each tracking task inline (e.g. "Tracked across <a href="...">D6N7+D7RR</a>, <a href="...">D8BH</a>, <a href="...">D7SV</a>"). Include a brief pointer to the suspected root-cause PR.}

<strong>Initials legend</strong>
{initials} — see PR links for authors.
</body>
```

## Per-issue tracking task body (html_notes)

Derived from task `1214265935091414`. Created in step 8 when no existing task is found for the short-ID. Omit the **Pull request** section — these tasks are filed during triage, before any fix is in flight. Include the `Likely caused by` line only if step 5 produced a confident attribution; drop the **Root Cause Analysis** + **Call chain** sections if no subagent ran for this issue (just keep the Sentry link header).

Match the existing-task layout exactly — the leading content has intentional newlines around the `<a>` block; the analysis section is compacted (no newlines between tags) per `asana-rich-text` rules:

```html
<body>Sentry crash:
<a href="https://errors.duckduckgo.com/organizations/ddg/issues/<SHORT_ID>/?project=<PROJECT_FILTER>">https://errors.duckduckgo.com/organizations/ddg/issues/<SHORT_ID>/?project=<PROJECT_FILTER></a>

Likely caused by <a href="https://github.com/duckduckgo/apple-browsers/pull/<NNNN>">https://github.com/duckduckgo/apple-browsers/pull/<NNNN></a>
<hr/>
<h2>Root Cause Analysis</h2>{1–2 sentence summary of the violated invariant from the subagent}
<h2>Call chain</h2><ol><li>{step 1}</li><li>{step 2}</li>...</ol></body>
```

## Quick reference

**Resolve task GID from Asana URL:** the numeric segment after `/task/` (e.g. `.../task/1214175611004136` → `1214175611004136`).

**`asana_get_task` requires `opt_fields="tags,tags.name"`** — the data-protection hook rejects queries without it with a `RETRY REQUIRED` error. Include it on every get call.

**Asana `html_notes` must be wrapped in `<body>...</body>`.** Use `<a href="...">` for plain links (not @-mentions). `<strong>`, `<em>`, `<code>`, `<hr>` supported.

## Common mistakes

| Mistake | Fix |
|---|---|
| Passing `regionUrl=https://errors.duckduckgo.com` to Sentry MCP | Omit `regionUrl`. MCP only allows `sentry.io` hosts; it returns `ddg.sentry.io` URLs you rewrite client-side. |
| Using `list_issues` with `query="release:1.186.0"` (string) | Prefer `app_version:1.186.0` (exact) or `app_version:1.186.*` (series) for event matching. |
| Quoting the `app_version` value (e.g. `app_version:"1.186.*"`) | Breaks wildcard matching. Pass the value unquoted. |
| Filtering events by `release:DuckDuckGo@...` (single prefix) | Silently drops extension crashes (e.g. `com.duckduckgo.macos.vpn.network-extension@...`). Use `app_version:` for the event-matching query; use the full multi-prefix release list only for `firstRelease:`. |
| Confusing `app_version:` vs `firstRelease:` | `app_version:` = events whose version tag matches (cross-target). `firstRelease:` = issue's *first-ever* event was in one of these release strings (true regressions) — needs explicit release strings, so include all targets. |
| Writing full employee names to Asana | Hook blocks it. Use initials + PR links. If the hook blocks even initials, fall back to PR-number-only. |
| Retrying a BLOCKED Asana response with different params | Never. The Asana data-protection policy says: accept the block. Ask the user how to proceed. |
| Trusting the "culprit" field for blame when generic | Symbols like `value`, `NSBundle.module`, `__pthread_kill`, `objc_release`, `main` are not attributable. Skip them. |
| Treating every iOS SIGKILL as a bug | Most SIGKILL+`main` crashes on iOS are Jetsam memory kills, not app bugs. LOW severity unless volume spikes or culprit is specific app code. |
| Forgetting `&project=<filter>` in errors.duckduckgo.com query URLs | The project filter is required for listing pages to render correctly; optional but recommended for single-issue URLs. |
| Skipping the find-or-create lookup and creating a duplicate tracking task | Always run `asana_search_tasks` against `Sentry Crash Reports` filtered by `custom_fields.1214294661819893.value=<SHORT_ID>` first. The custom field is comma-separated, so split the returned value on `,` and require an **exact element** match — substring matches like `APPLE-MACOS-BD7` matching `APPLE-MACOS-BD70` (or matching `APPLE-MACOS-BD7,APPLE-MACOS-XYZ`) are false positives. |
| Filing one tracking task per Sentry short-ID for sibling clusters | Cluster siblings (same culprit, same root cause) collapse into ONE tracking task. Put all the short-IDs comma-separated in the `Sentry Crash Group ID` custom field (e.g. `APPLE-IOS-D6MW,APPLE-IOS-D6N6,APPLE-IOS-D7YC,APPLE-IOS-D8KC`). The substring-match dedupe lookup still finds the merged task on any of the listed IDs. |
| Forgetting to set `custom_fields` on the new tracking task | Without `{"1214294661819893": "<SHORT_ID>[,<SHORT_ID>...]"}`, future runs of this skill will create duplicates because the dedupe lookup will miss. |
| Running root-cause subagents serially | Dispatch them in parallel (single message, multiple Agent tool calls) — they're independent and waiting serially is wasteful. Skip subagents entirely when the culprit is generic or OS-only — there's nothing to analyze. |
| Searching across the whole `Sentry Crash Reports` project instead of the platform section | Always scope the primary search to the platform section (`sections.any=<PLATFORM_SECTION>`). Only fall back to the `Untitled section` (`1214294661819891`) when the platform-section search misses — that's where pre-split tasks still live. |
| Creating a new tracking task in the `Untitled section` (the fallback) | The fallback is read-only for *new* tasks. New tasks always go in the platform section (`section_id=1214291024165659` for macOS, `1214290879396596` for iOS). |

## Example invocation

> "Fill {asana_url} with Sentry info for macOS 1.186 — severity, new issues, blame."

1. Extract task GID `1214175611004136`, project `apple-macos`, version series `1.186`.
2. `find_releases(query="1.186")` → `DuckDuckGo@1.186.0`, `DuckDuckGo@1.186.1`, `com.duckduckgo.macos.vpn.network-extension@1.186.0`, `com.duckduckgo.macos.vpn.network-extension@1.186.1`, ... (keep all — needed for `firstRelease:`).
3. `list_issues(query="is:unresolved app_version:1.186.*", sort="freq", limit=30)` — wildcard catches main app + extensions in one query. (For an exact version: `app_version:1.186.0`.)
4. `list_issues(query="is:unresolved firstRelease:[DuckDuckGo@1.186.0,DuckDuckGo@1.186.1,com.duckduckgo.macos.vpn.network-extension@1.186.0,com.duckduckgo.macos.vpn.network-extension@1.186.1,...]", sort="freq", limit=50)`.
5. For each new issue: grep culprit symbol → `git blame` → capture PR from commit `(#NNNN)`.
6. Rewrite all `ddg.sentry.io` URLs to `errors.duckduckgo.com/organizations/ddg/issues/<SHORT_ID>/?project=6`.
7. For each new issue with an informative stacktrace (e.g. `NSInternalInconsistencyException` with a clear message, or a deep first-party call chain), dispatch a parallel general-purpose subagent (single message, multiple Agent tool calls) to produce a root-cause summary + numbered call chain. Skip when the culprit is generic or OS-only.
8. Group new issues by culprit (siblings → one task). For each cluster: `asana_search_tasks(workspace="137249556945", projects.any="1214294661819890", sections.any="1214291024165659", custom_fields.1214294661819893.value="<SHORT_ID>", opt_fields="name,permalink_url,custom_fields,memberships.section.gid,tags,tags.name")` (macOS section). Split the returned `custom_fields` value on commas and require an **exact element match** (the field is comma-separated; substring matches are false positives). If no match in the platform section, retry with `sections.any="1214294661819891"` (Untitled-section fallback) — link any hit there as-is. If still no match, `asana_create_task` with `name`, `project_id="1214294661819890"`, `section_id="1214291024165659"` (macOS), `custom_fields={"1214294661819893":"<SHORT_ID_1>,<SHORT_ID_2>,..."}` (all sibling short-IDs comma-separated), and `html_notes` from the per-issue template. Capture `permalink_url`.
9. `asana_update_task(task_id="1214175611004136", html_notes="<body>...</body>")` with the main report; each per-issue line ends with `· <a href="...">tracking</a>` linking to the task from step 8.
