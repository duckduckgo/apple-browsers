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
| Project | `iOS` or `macOS` | Maps to Sentry project slug `apple-ios` / `apple-macos`. Release prefix differs — see Non-obvious constants. |
| Version | `1.186` (macOS) or `7.216` (iOS) | Can be a series (`1.186`) to match all `1.186.x`, or an exact release. |

## Non-obvious constants

- **Sentry org slug:** `ddg`
- **Sentry self-hosted host:** `errors.duckduckgo.com` (do NOT pass `regionUrl` to the MCP — it rejects non-sentry.io hosts; the MCP returns `ddg.sentry.io` URLs which you must rewrite)
- **Sentry release format differs by project:**
  - macOS: `DuckDuckGo@<version>` (e.g. `DuckDuckGo@1.186.1`)
  - iOS: `ios@<version>` (e.g. `ios@7.216.0`)
  - Always confirm via `find_releases(query="<version>")` before composing `release:` / `firstRelease:` queries — a wrong prefix returns zero results silently.
- **Project filter in URLs:** macOS uses numeric `project=6`. For iOS, `project=apple-ios` (slug) works on the Sentry self-hosted host. If numeric is needed, look it up via `find_projects`.
- **iOS SIGKILL noise:** Most iOS SIGKILL crashes with culprit `main` are Jetsam memory-pressure kills, not app bugs. Group these under LOW unless volume spikes or the culprit frame names specific app code. Don't attempt blame on them.
- **Sentry MCP `list_issues` query uses Sentry's native syntax**, not natural language. Key filters:
  - `release:[DuckDuckGo@1.186.0,DuckDuckGo@1.186.1]` — events in any of these releases
  - `firstRelease:[DuckDuckGo@1.186.0,DuckDuckGo@1.186.1]` — issues *first seen* in these releases (new regressions)
  - `is:unresolved` — exclude resolved
- **Short-IDs (e.g. `APPLE-MACOS-BE7`) resolve on both `ddg.sentry.io` and `errors.duckduckgo.com`** — no need to fetch numeric issue IDs.

## Workflow

1. **Load MCP tools** via ToolSearch:
   - `mcp__sentry__find_projects`, `mcp__sentry__find_releases`, `mcp__sentry__list_issues`
   - `mcp__plugin_asana_asana__asana_get_task`, `mcp__plugin_asana_asana__asana_update_task`
2. **Resolve the release list.** Call `find_releases` with `query="<version>"` (e.g. `1.186`) to enumerate all `<version>.x` patch releases. Build the release list: `[<prefix>@<v>.0, <prefix>@<v>.1, ...]` using the correct prefix per project.
3. **Two Sentry queries, sorted by `freq`:**
   - All unresolved in the series: `is:unresolved release:[<releases>]` — limit 30+
   - New-in-series only: `is:unresolved firstRelease:[<releases>]` — limit 50+ (iOS routinely hits 60–70 new issues)
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
7. **Write to Asana via `asana_update_task` with `html_notes`.** Structure below.
8. **PII: initials + PR links only, never full names.** The DDG asana-exfiltration hook scans task writes and blocks full employee names — even when the user approves in chat (the hook can't see chat). Use first-letter-of-first-name + first-letter-of-last-name initials, and link the PR so the author is one click away on GitHub. If even initials get blocked, fall back to PR-number-only attribution.

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
• <a href="...">SHORT-ID</a> — <signal> · <code>culprit</code> (U users, E events) — likely: {INITIALS} (<a href="...">#PR title</a>)

<strong>🟡 MEDIUM — Other new issues</strong>
• ...

<strong>🟢 LOW — OS-level / low signal / Jetsam OOM</strong>
• ...

<hr>

<strong>⚠️ Pre-existing (not new, but high-volume)</strong>
• <a href="...">SHORT-ID</a> — <signal> · <code>culprit</code> — U users, E events

<hr>

<strong>Recommended next step</strong>
{pointer to start with highest-severity cluster, and strongest prior on root-cause PR}

<strong>Initials legend</strong>
{initials} — see PR links for authors.
</body>
```

## Quick reference

**Resolve task GID from Asana URL:** the numeric segment after `/task/` (e.g. `.../task/1214175611004136` → `1214175611004136`).

**`asana_get_task` requires `opt_fields="tags,tags.name"`** — the data-protection hook rejects queries without it with a `RETRY REQUIRED` error. Include it on every get call.

**Asana `html_notes` must be wrapped in `<body>...</body>`.** Use `<a href="...">` for plain links (not @-mentions). `<strong>`, `<em>`, `<code>`, `<hr>` supported.

## Common mistakes

| Mistake | Fix |
|---|---|
| Passing `regionUrl=https://errors.duckduckgo.com` to Sentry MCP | Omit `regionUrl`. MCP only allows `sentry.io` hosts; it returns `ddg.sentry.io` URLs you rewrite client-side. |
| Using `list_issues` with `query="release:1.186.0"` (string) for a series | Use array syntax: `release:[DuckDuckGo@1.186.0,DuckDuckGo@1.186.1]`. Resolve the list via `find_releases` first. |
| Using the wrong release prefix | macOS = `DuckDuckGo@`, iOS = `ios@`. A wrong prefix returns zero results silently — confirm via `find_releases` first. |
| Confusing `release:` vs `firstRelease:` | `release:` = events seen in that release (includes old issues still firing). `firstRelease:` = issue's *first-ever* event was in that release (true regressions). |
| Writing full employee names to Asana | Hook blocks it. Use initials + PR links. If the hook blocks even initials, fall back to PR-number-only. |
| Retrying a BLOCKED Asana response with different params | Never. The Asana data-protection policy says: accept the block. Ask the user how to proceed. |
| Trusting the "culprit" field for blame when generic | Symbols like `value`, `NSBundle.module`, `__pthread_kill`, `objc_release`, `main` are not attributable. Skip them. |
| Treating every iOS SIGKILL as a bug | Most SIGKILL+`main` crashes on iOS are Jetsam memory kills, not app bugs. LOW severity unless volume spikes or culprit is specific app code. |
| Forgetting `&project=<filter>` in errors.duckduckgo.com query URLs | The project filter is required for listing pages to render correctly; optional but recommended for single-issue URLs. |

## Example invocation

> "Fill {asana_url} with Sentry info for macOS 1.186 — severity, new issues, blame."

1. Extract task GID `1214175611004136`, project `apple-macos`, version series `1.186`.
2. `find_releases(query="1.186")` → `DuckDuckGo@1.186.0`, `DuckDuckGo@1.186.1`.
3. `list_issues(query="is:unresolved release:[DuckDuckGo@1.186.0,DuckDuckGo@1.186.1]", sort="freq", limit=30)`.
4. `list_issues(query="is:unresolved firstRelease:[DuckDuckGo@1.186.0,DuckDuckGo@1.186.1]", sort="freq", limit=50)`.
5. For each new issue: grep culprit symbol → `git blame` → capture PR from commit `(#NNNN)`.
6. Rewrite all `ddg.sentry.io` URLs to `errors.duckduckgo.com/organizations/ddg/issues/<SHORT_ID>/?project=6`.
7. `asana_update_task(task_id="1214175611004136", html_notes="<body>...</body>")`.
