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
| **asana_url** | Any token starting with `https://app.asana.com/`. The destination Asana task to write the report into. | *(none - output inline)* |
| **keywords** | Any remaining words after extracting `platform`, `days`, and `asana_url`. Multiple keywords separated by commas, or by spaces if no commas are present. | *(none - no text filter)* |

Extract `asana_url` first (most specific), then `platform`, then `days`, then
treat what remains as keywords.

**Examples:**

| Invocation | platform | days | asana_url | keywords |
|------------|----------|------|-----------|----------|
| `/apple-feedback-review` | both | 7 | *(none)* | *(none)* |
| `/apple-feedback-review ios` | ios | 7 | *(none)* | *(none)* |
| `/apple-feedback-review macos 14d` | macos | 14 | *(none)* | *(none)* |
| `/apple-feedback-review 30 days vpn` | both | 30 | *(none)* | `vpn` |
| `/apple-feedback-review ios sync, bookmarks` | ios | 7 | *(none)* | `sync`, `bookmarks` |
| `/apple-feedback-review macos 14d ai chat, tab bar` | macos | 14 | *(none)* | `ai chat`, `tab bar` |
| `/apple-feedback-review macos 14d https://app.asana.com/0/123/456` | macos | 14 | `https://app.asana.com/0/123/456` | *(none)* |
| `/apple-feedback-review ios https://app.asana.com/0/111/222 vpn` | ios | 7 | `https://app.asana.com/0/111/222` | `vpn` |

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
> Searching feedback from the last **{days}** days for **{platform}**{keywords ? `, filtered by: **{keywords joined}**` : ""}{asana_url ? `. Report destination: {asana_url} (task GID: {extracted_gid})` : ""}.

Including the extracted task GID lets the user sanity-check it before any
write happens. Extract the GID right now using the rules in step 8.1, even
though the write itself is later.

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

**Expect the response to spill to a file even without `notes`.** iOS Feedback
and macOS Feedback tasks each carry 30+ custom fields (Reporter, Ban Type,
Search Area, etc. - many irrelevant). A single 100-task page with
`custom_fields.name,custom_fields.display_value` is ~110 KB and routinely
exceeds the inline tool-result cap on these two projects. The MCP server
saves spillover to a file at
`/Users/<you>/.claude/projects/<project>/<session>/tool-results/...txt` and
returns the path. When that happens:

1. Don't retry the search with a smaller `limit` - you'll just paginate more.
2. Use `jq` directly on the file to project to a slim shape, e.g.:
   ```
   jq '.data | map({gid, name, created_at, custom_fields: (.custom_fields | map({name, display_value}))})' <path> > /tmp/<bucket>_pN.json
   ```
3. Read the `created_at` of the last element for the next pagination cursor.
4. Merge pages later with `jq -s '.[0] + .[1] + ... | unique_by(.gid) | sort_by(.created_at) | reverse'`.

The Privacy Pro projects, Internal Product Feedback, and App Store Reviews are
small enough that responses come back inline; only iOS Feedback and macOS
Feedback reliably spill.

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

**Generate link lists programmatically.** Hand-copying GIDs into HTML by
typing them out is error-prone (a single mistyped digit breaks the link
silently). After clustering, write the GID list for each group to a small
file and use `jq` or python to emit the `<li><a href="...">name</a></li>`
HTML in one shot:

```
jq -r --arg pgid 1206584483643184 '.[] | select(.gid as $g | $cluster_gids | index($g)) |
  "<li><a href=\"https://app.asana.com/0/" + $pgid + "/" + .gid + "\">" + .name + "</a></li>"' \
  /tmp/<bucket>_all.json
```

This also makes the per-cluster metadata extraction in step 6 cheaper because
the same `cluster_gids` file is reused.

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

### 8. Write report to Asana task (only if `asana_url` was provided)

Skip this step entirely when `asana_url` is empty - the report has already been
rendered inline by steps 5-7 and there is nothing more to do.

When `asana_url` IS provided, the inline render is replaced by a write to the
target task's description. Do not also dump the full report inline - end with a
short confirmation line containing the task link.

#### 8.1 Extract the task GID from the URL

Asana URLs come in two shapes. The task GID is the trailing numeric segment in
the old format, or the segment after `/task/` in the new format:

| URL shape | Task GID |
|-----------|----------|
| `https://app.asana.com/0/<project_gid>/<task_gid>` | last numeric segment |
| `https://app.asana.com/0/<project_gid>/<task_gid>/f` | second-to-last segment |
| `https://app.asana.com/1/<workspace>/project/<project_gid>/task/<task_gid>` | segment after `/task/` |

Strip any trailing `?` query string or `#` fragment before extracting.

#### 8.2 Read the current task description

Fetch the task with `asana_get_task` to inspect its existing description:

```
task_id: <task_gid>
opt_fields: "name,notes,html_notes,tags,tags.name"
```

(`tags` and `tags.name` are required by the data protection hook.)

#### 8.3 Warn before overwriting

If `notes` is non-empty (treat whitespace-only as empty), the task description
is already populated and writing the report will overwrite it. **Stop and ask
the user to confirm before proceeding**, even in auto mode - this is a
visible-to-others write that can destroy data.

Show:
- The task's `name`.
- The first ~500 characters of the existing `notes`, plus `(...truncated, N
  more characters)` if longer.
- An explicit prompt: "Overwrite this with the generated report? (yes/no)"

If the user declines (or anything other than an explicit yes), output the
report inline as if no `asana_url` had been provided and skip the write. Do not
fall back to appending or to creating a comment - those weren't requested.

If `notes` is empty, proceed without prompting.

#### 8.4 Format the report as Asana HTML

**REQUIRED SUB-SKILL:** Use the `asana-formatting:asana-formatting` skill to
convert the markdown report into Asana-compatible HTML. Asana rejects standard
HTML tags like `<p>`, `<br>`, `<b>`, `<i>` with a 400 error - the formatting
skill defines the supported subset and conversions for headings, lists, tables,
and links.

**Use Write or python to assemble the HTML, not a quoted bash heredoc.** The
asana-formatting skill says "use `\n` for line breaks" - that means a literal
newline byte, not the two-character escape sequence `\n`. A
`cat << 'EOF'` heredoc preserves `\n` as literal text, which Asana renders as
the visible characters `\n` rather than a line break. Either:

- Use the `Write` tool to write the HTML to `/tmp/report.html` directly (real
  newlines in your input become real newlines on disk), then read it back to
  pass to `asana_update_task`, **or**
- Use a python heredoc (`python3 << 'PY' ... PY`) where `\n` inside string
  literals becomes a real newline at runtime.

Avoid the unquoted `cat << EOF` form too - it triggers shell expansion on `$`
and backticks inside the report.

**Asana's plain-text rendering of `<table>` is flat.** The `notes` plain-text
view (and the email/notification preview that derives from it) renders each
table cell on its own line with no separator - so a deep-dive table looks like
`Factor / Finding / OS / Heavily concentrated... / App version / ...` to anyone
reading the preview. The HTML view in the Asana web UI renders the table
correctly, so use tables anyway, but be aware the preview will look ugly. If
preview readability matters more than HTML structure, switch to definition-list
style prose (`<strong>OS:</strong> Heavily concentrated...\n\n<strong>App
version:</strong> ...`) instead of `<table>`.

If the rendered HTML approaches Asana's note-size limit (~64 KB), trim the
long-tail / count-only group link lists first (their cap is already ~50);
preserve the Top 3 deep-dive tables intact.

#### 8.5 Update the task

Call `asana_update_task` with:

```
task_id: <task_gid>
html_notes: <Asana-formatted HTML report>
```

Use `html_notes` (not `notes`) so the structure is preserved.

#### 8.6 Confirm to the user

Output a single line confirming the write, with a clickable link back to the
task. Do NOT also paste the full report inline - the user asked for it to live
in Asana.

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
- **Overwriting an existing Asana task description without asking.** Step 8.3
  is mandatory when `notes` is non-empty - even in auto mode. Writes to shared
  tasks affect other people, so warn-then-confirm is not optional.
- **Calling `asana_update_task` with raw markdown or standard HTML.** Asana
  rejects `<p>`, `<br>`, `<b>`, `<i>` and friends with a 400 error. Always
  route through the `asana-formatting:asana-formatting` skill before writing
  `html_notes`.
- **Dumping the full report inline AND writing it to Asana.** When `asana_url`
  is provided, the inline render is replaced by a one-line confirmation. Only
  fall back to inline output if the user declined the overwrite in step 8.3.
- **Assembling the report HTML in a quoted bash heredoc.** `cat << 'EOF'`
  preserves `\n` as the literal two-character escape sequence, which Asana
  renders as visible `\n` in the task description. Use the `Write` tool or a
  python heredoc instead - see step 8.4.
- **Hand-typing GIDs into the link list HTML.** A single mistyped digit gives
  a broken link that looks correct at a glance. Generate the link list from
  the per-cluster GID file with `jq` (snippet in step 5).
- **Retrying a search with a smaller `limit` after the response spilled to a
  file.** Smaller pages just mean more pagination rounds; the per-task payload
  is the bottleneck. Read the spilled file with `jq` and continue.

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
