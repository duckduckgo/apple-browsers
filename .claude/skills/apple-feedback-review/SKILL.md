---
name: apple-feedback-review
description: >-
  Invoke ONLY when the user explicitly runs /apple-feedback-review or names
  this skill by name. Do NOT auto-invoke from symptom/intent matching. If the
  user asks about Apple feedback, iOS or macOS issues, user reports, or
  feedback triage without naming this skill, answer directly instead.
---

# Apple Feedback Review

## Overview

Apple-side feedback is fragmented across five Asana projects (in-app feedback,
Privacy Pro feature requests, Privacy Pro issues, internal product feedback,
and App Store reviews) and split between iOS and macOS. This skill fetches
all relevant sources, deduplicates by task GID, clusters reports into named
issue groups, and presents a per-platform summary with a separate App Store
reviews section. The output is a one-shot snapshot, not a query interface.

**REQUIRED BACKGROUND:** `ddg-required-config:ddg-asana` defines the sensitive
data gating protocol used in this skill. Halt and follow it if any task
contains legal, HR, finance, or security content.

## When NOT to use

- Alerting or monitoring (this is a snapshot, not a watcher).
- Individual task triage (use Asana directly).
- Anything that needs a feedback database or repeated queries against the
  same window (the skill re-fetches from Asana every time).

## Lethal trifecta note

This skill accesses Asana, an internal data source. A session-level hook
blocks WebFetch and most non-allowlisted MCP tools for the rest of the
session once Asana is touched. If the user needs WebFetch, Slack, or other
non-allowlisted tools afterwards, run this skill in a separate session.

## Parameters

This skill accepts optional arguments. Parse them from the free-text args
string passed to the skill.

| Parameter | How to detect | Default |
|-----------|--------------|---------|
| **platform** | The literal token `ios` or `macos` (case-insensitive). If absent, run both. | `both` |
| **days** | A number followed by `d`, `days`, or just a bare number (e.g. `14d`, `30 days`, `14`) | `7` |
| **keywords** | Any remaining words after extracting `platform` and `days`. Multiple keywords separated by commas, or by spaces if no commas are present. | *(none - no text filter)* |

**Examples:**

| Invocation | platform | days | keywords |
|------------|----------|------|----------|
| `/apple-feedback-review` | both | 7 | *(none)* |
| `/apple-feedback-review ios` | ios | 7 | *(none)* |
| `/apple-feedback-review macos 14d` | macos | 14 | *(none)* |
| `/apple-feedback-review 30 days vpn` | both | 30 | `vpn` |
| `/apple-feedback-review ios sync, bookmarks` | ios | 7 | `sync`, `bookmarks` |
| `/apple-feedback-review macos 14d ai chat, tab bar` | macos | 14 | `ai chat`, `tab bar` |

When keywords contain commas, split on commas and trim each keyword. When there
are no commas, treat each remaining word as a separate keyword. Multi-word
keywords must be comma-separated (e.g. `ai chat, dark mode`).

## Asana projects

Feedback is fragmented across multiple projects on the Apple side. The skill
fetches from each relevant source per platform, then merges and dedupes by
task GID.

### iOS feedback bucket (grouped together by issue)

| Project | GID | Filter |
|---------|-----|--------|
| iOS Feedback | `1206584483643184` | none |
| iOS Privacy Pro Feature Request Feedback | `1207941309648065` | none |
| iOS Privacy Pro Issues | `1207941520938527` | none |
| Internal Product Feedback | `1204912272578138` | `Platform (Internal Feedback)` = "iOS Browser" |

To filter Internal Product Feedback to iOS Browser, pass:

```
custom_fields: {"1204912272636857.value":"1204912272636860"}
```

The `.value` suffix on the field GID is required - without it the Asana API
returns `custom_fields.<gid>: Not a valid search parameter for custom fields`.
`1204912272636857` is the Platform (Internal Feedback) field; `1204912272636860`
is the "iOS Browser" option.

### iOS App Store Reviews bucket (separate section, different schema)

| Project | GID | Filter |
|---------|-----|--------|
| iOS App Store Reviews | `807511686726007` | none |

### macOS feedback bucket (grouped together by issue)

| Project | GID | Filter |
|---------|-----|--------|
| macOS Feedback | `1199178362774117` | none |
| MacOS Privacy Pro Feature Request Feedback | `1207941308245573` | none |
| MacOS Privacy Pro Issues | `1207941519901927` | none |
| Internal Product Feedback | `1204912272578138` | `Platform (Internal Feedback)` = "macOS Browser" |

To filter Internal Product Feedback to macOS Browser, pass:

```
custom_fields: {"1204912272636857.value":"1204912272636859"}
```

(Same `.value` suffix requirement as above.)

### macOS App Store Reviews bucket (separate section, different schema)

| Project | GID | Filter |
|---------|-----|--------|
| macOS App Store Reviews | `1203758364504327` | none |

## Steps

### 1. Parse parameters and calculate the date window

Extract **platform**, **days**, and **keywords** from the args string using the
rules above. Compute the ISO 8601 date for `days` days ago from today. Use this
as the `created_at_after` filter.

Echo the parsed parameters back to the user before fetching:
> Searching feedback from the last **{days}** days for **{platform}**{keywords ? `, filtered by: **{keywords joined}**` : ""}.

Decide which buckets to fetch:
- `platform = ios`: iOS feedback bucket + iOS App Store Reviews
- `platform = macos`: macOS feedback bucket + macOS App Store Reviews
- `platform = both`: all four buckets

### 2. Fetch recent feedback tasks (with pagination)

For each project in each selected bucket, use `asana_search_tasks`. The API
returns at most 100 results per call, so paginate to collect all tasks within
the time window.

If **keywords** were provided, make one search request **per keyword** using
the `text` parameter, then merge and deduplicate results by task GID. This is
necessary because `asana_search_tasks` accepts only a single text query.

The `opt_fields` below intentionally **excludes `notes`** - the macOS Feedback
project alone returns ~80+ tasks per day and the full notes blob blows past the
tool-result token cap. Fetch `notes` only on a task-by-task basis in step 3
when needed for grouping.

**First request (per project, per keyword, or once if no keywords):**

```
projects_any: <project GID>
created_at_after: <days ago in ISO 8601, e.g. "2026-04-24T00:00:00.000Z">
text: <keyword, or omit if no keywords>
custom_fields: <platform filter for Internal Product Feedback only, otherwise omit>
sort_by: "created_at"
sort_ascending: false
limit: 100
opt_fields: "name,created_at,completed,custom_fields.name,custom_fields.display_value"
```

**Pagination loop (per project, per keyword query):**

After each response, check whether exactly 100 results were returned. If so,
there are likely more tasks to fetch. To get the next page, take the
`created_at` timestamp of the **oldest** (last) task in the current batch and
use it as the `created_at_before` filter for the next request, keeping
`created_at_after` unchanged:

```
projects_any: <project GID>
created_at_after: <days ago>
created_at_before: <created_at of the last task from the previous batch>
text: <keyword, or omit if no keywords>
custom_fields: <platform filter for Internal Product Feedback only, otherwise omit>
sort_by: "created_at"
sort_ascending: false
limit: 100
opt_fields: "name,created_at,completed,custom_fields.name,custom_fields.display_value"
```

Repeat until:
- A batch returns fewer than 100 results (you have reached the end), **or**
- You have fetched 10 pages per project per keyword (1000 tasks) as a safety
  cap. macOS Feedback alone can return 400+ tasks in a 5-day window, so a
  14-day or 30-day query needs the higher cap. If the cap is hit, note
  prominently in the output that results were truncated and the deep dive may
  be biased toward recent items.

After all queries for a bucket complete, merge all tasks within the bucket and
deduplicate by task GID. Each bucket is processed independently.

### 3. Read task details where needed

For tasks whose names alone are not descriptive enough to classify, use
`asana_get_task` to read the full description (`notes` or `html_notes` field).
Only do this selectively to avoid excessive API calls - start by grouping on
task names first.

When calling `asana_get_task`, the data protection hook requires tag fields in
`opt_fields`. Use:

```
opt_fields: "name,notes,html_notes,custom_fields,custom_fields.name,custom_fields.display_value,tags,tags.name"
```

### 4. Group by distinct issue (per bucket)

Analyse the task names (and descriptions where read) and cluster them into
distinct issue groups. Use your judgement to identify common themes such as:

- Same error message or symptom described in different words
- Same feature area (e.g. "AI Chat", "VPN", "Sync", "Bookmarks", "Privacy Pro")
- Same user action triggering the problem
- Exact or near-duplicate reports

For each group, choose a short, descriptive label (e.g. "AI Chat fails to
respond", "Privacy Pro VPN disconnects on cellular").

Group the iOS feedback bucket separately from the iOS App Store Reviews bucket
(and same for macOS). The two have different schemas and should be presented
separately.

**Handling high-volume long tails:** A single platform-bucket can return
hundreds of tasks per week. Most cluster into a small number of named groups,
but a long tail of one-off reports (specific website breakage, niche feature
requests, generic praise/dissatisfaction) typically remains. When more than
~40 tasks remain unclustered after named groups are formed:

- Roll them into a single trailing group called **"Miscellaneous / long-tail
  user feedback"** with a one-paragraph theme summary and a sample of links
  (cap the link list at ~50 entries; note "(...remaining N items truncated)"
  if there are more).
- Do not include this group in the Top 3 deep dive.

**Known low-signal clusters to call out as count-only groups:**

- **Quit Time Survey submissions** (macOS) - tasks named "Via First Quit Time
  Survey", "Feedback submitted via quit time survey", or similar. These are
  auto-generated when a user closes the app and answers the survey without
  free-text. They can total ~70+ in a 5-day window. Group them as count-only,
  do not enumerate every link, and do not include in the Top 3 deep dive
  (they have no narrative to deep-dive into).
- **Data Import failures** (macOS) - tasks whose body starts with `Import
  source: <browser/manager>` and `Error: DuckDuckGo_Privacy_Browser.<importer>`
  / `BrowserServicesKit.<importer>`. These are auto-generated by the importer
  on failure. Worth grouping by importer family (Chromium / Firefox / CSV /
  HTML Bookmarks / 1Password) since the failing module is itself the signal.
  Eligible for the Top 3 deep dive when volume warrants it.

### 5. Present the summary

Output is structured per platform. If `platform = both`, render the iOS
sections first, then the macOS sections.

For each bucket, output a section per group with:

- **Heading**: short descriptive label for the issue, with the count in
  parentheses (e.g. `### Privacy Pro VPN disconnects on cellular (8)`)
- **Date range**: earliest and latest creation date in the group
- **Links**: a bullet list of every task in the group (cap at ~50 links per
  group; if more, list the first 50 by recency and note "(...remaining N
  items truncated)"). Format each link as a clickable Asana link using the
  project GID the task came from and the task GID:
  `- [Task name](https://app.asana.com/0/<project_gid>/<task_gid>)`.
  When a task appears in multiple projects of the bucket (rare due to dedup),
  link to the primary project. Do NOT include Asana user names or assignees in
  the task name - anonymise per data protection policy.
- For the count-only noise clusters above (Quit Time Survey, etc.), skip the
  link list entirely and just show the count plus a one-line description.

Sort groups by count descending (most-reported issues first).

After all groups in a bucket, add a brief bucket summary:
- Total feedback items in the window
- Number of distinct issue groups identified
- Top 3 issues by volume

### 6. Top 3 deep dive (per platform feedback bucket)

For the **3 highest-count actionable issue groups** in each platform's
feedback bucket (not the App Store Reviews bucket - see below), perform a
deeper analysis of the tasks' custom field metadata to surface environmental
patterns. **Skip count-only noise clusters** (Quit Time Survey, miscellaneous
long-tail) when picking the top 3 - even if they have the highest counts,
they have no narrative to deep-dive into. Note in the bucket summary if the
top-by-count group was skipped for this reason.

If fewer than 3 actionable groups exist (or fewer remain after skipping
noise clusters), do as many as you have - just one is fine. Drop the section
entirely if there are zero.

Extract these fields from each task in the group (when present):

- **Version** (app version, e.g. `7.216.0.3` on iOS, `1.187.0` on macOS)
- **OS Version** (e.g. `iOS 26.4.2`, `macOS 15.6.0`)
- **Sentiment** (e.g. `frustrated`, `disappointed`, `confused`)
- **Dealbreaker** (True/False)
- **Source** (where applicable)

Present a breakdown table:

| Factor | Finding |
|--------|---------|
| **OS** | Distribution across major OS versions, specific build numbers |
| **App version** | Which app versions are affected - single regression or multi-version? |
| **Sentiment** | Distribution of sentiment values across the reports |
| **Symptom pattern** | Common recovery steps or trigger actions described across reports |
| **Dealbreaker** | How many users flagged this as a dealbreaker |

After the table, add a **Key takeaway** paragraph summarising:
- Whether the issue is concentrated on a specific OS version or app version
- Whether it appears to be a regression in a single release or a persistent
  issue
- Any suggested investigation direction based on the pattern (e.g. "iOS 26.x
  regression", "Privacy Pro subscription state confusion")

### 7. Top 3 deep dive (per platform App Store Reviews bucket)

App Store Reviews tasks have a different schema (Rating, Version, Store - no
Sentiment, no Dealbreaker, no OS Version). For the **3 highest-count issue
groups** in each platform's App Store Reviews bucket, present a smaller
breakdown. Same fewer-than-3 fallback as step 6: do as many as you have.

| Factor | Finding |
|--------|---------|
| **Rating** | Distribution of star ratings (1-5) across the reports |
| **App version** | Which app versions are affected |
| **Store / locale** | Which country stores the reviews came from (the country flag emoji in the task name is the locale signal) |
| **Symptom pattern** | Common complaints or praise points across reports |

Then a **Key takeaway** paragraph summarising the rating skew and any version
or locale concentration.

## Privacy and data protection

- Do **not** include user names, emails, assignees, or any PII in the output.
- Use anonymised references ("User A", "a user reported") if quoting task
  descriptions.
- App Store review tasks often embed the reviewer's display name in the task
  title. Treat these as PII and replace with "App Store reviewer" in link
  labels, even though they are public on the App Store.
- Do **not** write any Asana data to disk.
- Do **not** make web searches or external API calls after accessing Asana
  data.
- If any task contains sensitive content (legal, HR, finance, security), halt
  and follow the sensitive data gating protocol from `ddg-required-config:ddg-asana`.

## Common mistakes

- **Including `notes` in the bulk-fetch `opt_fields`.** macOS Feedback alone
  returns 80+ tasks/day; the notes blob blows past the tool-result token cap.
  Fetch `notes` only on a per-task basis in step 3.
- **Forgetting the `.value` suffix on custom field GIDs.** Without it the API
  returns `custom_fields.<gid>: Not a valid search parameter for custom fields`.
- **Calling `asana_get_task` without `tags` and `tags.name` in `opt_fields`.**
  The data protection hook requires the tag fields to be requested - without
  them the call is denied.
- **Treating App Store Reviews like the feedback bucket.** Different schema
  (Rating, Store - no Sentiment, no Dealbreaker, no OS Version) and a separate
  deep-dive table (step 7).
- **Picking a count-only noise cluster for the Top 3 deep dive.** Quit Time
  Survey and Miscellaneous long-tail have no narrative; skip them and pick
  the next-highest actionable group.
- **Using the same pagination cursor across keywords or projects.**
  `created_at_before` is set per (project, keyword) query - resetting between
  queries is required, otherwise pages get skipped.

## What to skip

- Completed tasks (filter with `completed: false` if a project mixes open and
  closed items)
- Tasks that are clearly not user feedback. Most show up in Internal Product
  Feedback. Skip during grouping when the title matches any of these patterns:
  - Starts with `PR:` (PR-mirror tasks - e.g. `PR: Tab dividers are gone after
    recent update (apple-browsers)`)
  - Starts with `[Action Required]` (administrative checklists - e.g.
    `[Action Required] Update Desktop Browser Feature description if needed`)
  - Internal tracking tasks ("Testing Steps", "How to resolve X breakage?")
  - Milestone tasks (`resource_subtype: milestone`)
- Subtasks (unless they contain distinct feedback - use `is_subtask: false`
  if needed)
