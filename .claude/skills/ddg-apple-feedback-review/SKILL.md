---
name: ddg-apple-feedback-review
description: >-
  Invoke ONLY when the user explicitly runs /ddg-apple-feedback-review or names
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

**Sensitive data halt:** An organization-level instruction requires you to
stop and surface a `⚠️ SENSITIVE DATA` warning if any task surfaced by this
skill contains legal (SILO, ACP, attorney-client privilege), HR
(performance, compensation, terminations, PIPs), finance (M&A, budget
details), or security (audits, incidents) content. List the triggers and
ask for explicit confirmation before continuing - do not include such tasks
in the report unsolicited.

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

The hook in this environment is also stricter about **Bash**: once Asana
has been touched, Bash calls that look like they're "preparing report
content to post back" are denied, including `python3`, `jq`, and `rm` on
scratch files. This skill is therefore designed to run **without Bash
post-Asana** - all task data stays in tool-call context, the report HTML
is built in-message, and there are no scratch files to clean up.

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
| `/ddg-apple-feedback-review` | both | 7 | *(none)* | *(none)* |
| `/ddg-apple-feedback-review ios` | ios | 7 | *(none)* | *(none)* |
| `/ddg-apple-feedback-review macos 14d` | macos | 14 | *(none)* | *(none)* |
| `/ddg-apple-feedback-review 30 days vpn` | both | 30 | *(none)* | `vpn` |
| `/ddg-apple-feedback-review ios sync, bookmarks` | ios | 7 | *(none)* | `sync`, `bookmarks` |
| `/ddg-apple-feedback-review macos 14d ai chat, tab bar` | macos | 14 | *(none)* | `ai chat`, `tab bar` |
| `/ddg-apple-feedback-review macos 14d https://app.asana.com/0/123/456` | macos | 14 | `https://app.asana.com/0/123/456` | *(none)* |
| `/ddg-apple-feedback-review ios https://app.asana.com/0/111/222 vpn` | ios | 7 | `https://app.asana.com/0/111/222` | `vpn` |

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

**No scratch directory.** This skill keeps all task data in tool-call context
across steps 2-7 and assembles the final report HTML directly in step 8.5's
`asana_update_task` call. There is no `mktemp` / `$scratch_dir`, no on-disk
JSON dumps, no `jq` pipelines, and no cleanup step. If a step here ever
suggests writing Asana data to disk, treat that as a bug in the skill and
ignore it.

The `opt_fields` below intentionally **excludes `notes`** - the macOS Feedback
project alone returns ~80+ tasks per day and the full notes blob blows past the
tool-result token cap. Fetch `notes` only on a task-by-task basis in step 3
when needed for grouping.

**Use slim `opt_fields` for iOS Feedback and macOS Feedback.** These two
projects carry 30+ custom fields per task (Reporter, Ban Type, Search Area,
SAM Severity values, etc. - most irrelevant to clustering). A 100-task page
with `custom_fields.name,custom_fields.display_value` is ~110 KB and reliably
exceeds the inline tool-result cap. Drop the custom fields from the bulk fetch
on these two projects; cluster from task titles alone; then in step 6 sample
5-10 representative tasks per Top-3 cluster and fetch *those* with full custom
fields via `asana_get_task` for the deep dive. Other projects (Privacy Pro,
Internal Product Feedback, App Store Reviews) carry fewer fields and fit
comfortably with full custom fields at `limit=100`.

| Project | `limit` | `opt_fields` |
|---------|---------|--------------|
| iOS Feedback (`1206584483643184`) | `100` | `name,created_at,completed` |
| macOS Feedback (`1199178362774117`) | `100` | `name,created_at,completed` |
| Privacy Pro / Internal / App Store Reviews | `100` | `name,created_at,completed,custom_fields.name,custom_fields.display_value` |

Tradeoff: the Top-3 deep dive runs against a *sample* (5-10 tasks per cluster)
rather than the full population. Annotate "sampled N of M" in the deep-dive
output so the reader knows. Net win: ~3-4x fewer pagination rounds on the heavy
projects (a 3-day window fits in ~2 pages instead of ~9), and a higher safety
ceiling on long windows.

**Spillover fallback (if a Privacy Pro / Internal / App Store Reviews query
spills).** Uncommon at `limit=100` for those projects, but possible on a
30-day window or after schema bloat. When the MCP server reports a
tool-result spillover for those projects, drop
`custom_fields.name,custom_fields.display_value` from their `opt_fields`
to match the slim-default treatment used for iOS / macOS Feedback, and
sample per-cluster in step 6 the same way. Do **not** attempt to recover
the spilled file via `jq`, `cat`, or any other shell tool - this skill
does not assume Bash is available post-Asana, and Bash will likely be
denied at this point in the session even if it appears to exist. iOS
Feedback / macOS Feedback already use slim `opt_fields` by default, so
this only affects the other projects when they spill.

**First request (per project, per keyword, or once if no keywords):**

```
workspace: "137249556945"
projects_any: <project GID>
created_at_after: <days ago in ISO 8601, e.g. "2026-04-24T00:00:00.000Z">
completed: false
text: <keyword, or omit if no keywords>
custom_fields: <platform filter for Internal Product Feedback only, otherwise omit>
sort_by: "created_at"
sort_ascending: false
limit: 100
opt_fields: <project-specific - see table above>
```

`workspace` is a **required** parameter on `asana_search_tasks`; `137249556945`
is the DDG workspace GID (visible in any DDG Asana URL of the form
`https://app.asana.com/1/137249556945/...`). Omitting it returns a validation
error.

`completed: false` is a **filter** that excludes resolved tasks at the API level
- without it, completed feedback consumes pagination slots against the per-page
`limit` and the 1000-task safety cap, and resolved issues can leak into the
grouped output. The `completed` field also stays in `opt_fields` so the value
is readable on each task as a sanity check.

**Pagination loop (per project, per keyword query):**

After each response, check whether the result count equals the request's
`limit`. If so, there are likely more tasks to fetch. To get the next page,
take the `created_at` timestamp of the **oldest** (last) task in the current
batch and use it as the `created_at_before` filter for the next request,
keeping `created_at_after` unchanged:

```
workspace: "137249556945"
projects_any: <project GID>
created_at_after: <days ago>
created_at_before: <created_at of the last task from the previous batch>
completed: false
text: <keyword, or omit if no keywords>
custom_fields: <platform filter for Internal Product Feedback only, otherwise omit>
sort_by: "created_at"
sort_ascending: false
limit: 100
opt_fields: <same project-specific value as the first request>
```

Repeat until:
- A batch returns fewer than 100 (you have reached the end), **or**
- You have fetched **1000 tasks per project per keyword** (10 pages) as a
  safety cap. macOS Feedback alone can return 400+ tasks in a 5-day window;
  a 14-day or 30-day query may approach this. If the cap is hit, note
  prominently in the output that results were truncated and the deep dive
  may be biased toward recent items.

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
- **Links**: a bullet list of **5-10 representative tasks** by recency (not
  every task in the group). For groups with more than 10 tasks, list the
  most recent 5-10 and note "(...remaining N items, see Asana project view)".
  The full enumeration belongs in Asana's project filter, not the snapshot.
  Format each link as a clickable Asana link using the project GID the task
  came from and the task GID:
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

**Don't hand-type GIDs from memory.** A single mistyped digit breaks the link
silently. The GIDs you need are already in the JSON tool-result text returned
by `asana_search_tasks` (step 2) and `asana_get_task` (step 6). When you emit
each `<li><a href="https://app.asana.com/0/<project_gid>/<task_gid>"><name></a></li>`,
transcribe the GID and name verbatim from those tool results - copy the digits,
do not paraphrase or abbreviate. HTML-escape `&`, `<`, `>`, and `"` in the name;
everything else (Unicode, emoji, punctuation, apostrophes) passes through. There
is no scratch-file step here - the tool results are still in your context, so
build the link list directly in the same `asana_update_task` call.

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

**Sample per cluster.** For iOS Feedback / macOS Feedback the bulk fetch in
step 2 used slim `opt_fields`, so custom fields are not on the bucket-level
records. Instead:

1. Pick **5-10 representative tasks** by recency from each Top-3 cluster.
2. Issue all sample fetches in parallel within the same message - they are
   independent. Use `asana_get_task` per task with:
   ```
   opt_fields: "name,notes,custom_fields,custom_fields.name,custom_fields.display_value,tags,tags.name"
   ```
   (`tags` and `tags.name` are required by the data protection hook.)
3. Build the deep-dive table from the sample.
4. Annotate "sampled N of M" in the table footer or Key takeaway, so the
   reader knows the metadata is not full-population.

Bump from 5 to 10 if a cluster looks borderline (mixed signals across
versions, sentiment, etc.). Other-bucket clusters (Privacy Pro, Internal
Product Feedback) carry custom fields on the bulk fetch already - no
sampling needed.

Extract these fields from each sampled task (when present):

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
convert the markdown report into Asana-compatible HTML. Asana's `html_notes`
field accepts a restricted subset of HTML and rejects standard tags like
`<p>`, `<br>`, `<b>`, `<i>`, `<div>` with a 400 error. The MCP schema lists
`<body>`, `<strong>`, `<em>`, `<u>`, `<s>`, `<code>`, `<ol>`, `<ul>`, `<li>`,
`<a>`, `<blockquote>`, `<pre>`, `<h1>`, `<h2>`, `<hr/>`, `<img>` as the
explicitly accepted set. Let the formatting skill choose how to emit any
given markdown construct (headings, lists, tables, links, paragraph breaks)
- don't hand-craft HTML based on assumptions about what Asana renders.

**Pass the HTML directly as `html_notes` in the same tool call.** Real
newlines in the `html_notes` argument round-trip through the MCP layer to
Asana correctly. Build the HTML in-message and call `asana_update_task`
with the assembled string in one shot.

Do **not**:

- Write the HTML to a file and read it back. The roundtrip is unnecessary
  for any report size that fits in Asana's `html_notes` field, and writing
  Asana data to disk violates the persistence rules in the privacy section.
- Assemble the HTML in a bash heredoc (`cat << EOF` or `cat << 'EOF'`).
  The unquoted form expands `$` and backticks inside the report; the quoted
  form preserves `\n` as the literal two-character escape sequence, which
  Asana renders as visible `\n`. More fundamentally, Bash will likely be
  denied at this point in the session, so heredocs are not a path forward.
- Shell out to `python` or any other interpreter to render the HTML. Same
  Bash-denial reason. Build the HTML in tool-call arguments instead.

**Do not insert blank lines between block-level tags.** Asana already renders
block elements (`<h1>`, `<h2>`, `<ul>`, `<ol>`, `<pre>`, `<blockquote>`) with
built-in vertical separation. Inserting `\n\n` between them - whether
hand-written for source readability or carried over from a pretty-printed
asana-formatting conversion - gets rendered as an extra blank line on top of
that built-in spacing, producing visibly double-spaced output (an empty line
between every heading and its following list, between every list and the
next heading, etc.). Join block tags with no separator (e.g. `</h2><ul>`) or
at most a single real newline. After running the asana-formatting conversion,
scan its output and collapse any `\n\n` (or longer runs of newlines) that
appears immediately before or after a block tag down to a single real newline
or nothing.

`\n\n` between **purely inline content** (plain text, `<strong>`, `<em>`,
`<a>`, `<code>` with no surrounding block tag on either side) is a different
case - it is the only way to produce a paragraph break in `html_notes` since
Asana rejects `<p>`. The block-tag rule above does not apply to those.

**`\n` escape sequences in tool-call XML parameters are literal text, not
newlines.** Claude Code passes parameter content to MCP tools without
processing JSON-style escape sequences. If you type `text.\n<h1>Heading</h1>`
inside the `html_notes` XML parameter, Asana stores those characters
verbatim - the `\n` is two literal characters (backslash + n), and the
HTML view renders them as visible `\n` text before the heading. The fix:

- Between **block tags**, use no separator at all (`</h2><ul>`). Block
  elements have their own vertical spacing in Asana. This is the safest
  default and avoids the escape-sequence trap entirely.
- Where you genuinely need a real newline (paragraph break between inline
  content - the `\n\n` case above), break the parameter content across
  physical lines in the XML. Real line breaks in the parameter source pass
  through as real newlines.
- The asana-formatting skill's documented `\n` / `\n\n` syntax assumes
  JSON-encoded tool calls, where `\n` is processed to a newline. Inside a
  Claude Code `<parameter>...</parameter>` block, that processing does not
  happen, so do not literally type the two-character `\n` sequence and
  expect a newline.

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

### 9. Done

This skill keeps all Asana data in tool-call context only - no scratch
files, no temp directories, nothing on disk. There is no cleanup step.

The MCP server's own tool-result spillover under
`~/.claude/projects/.../tool-results/` is managed by the harness and should
not be touched.

## Privacy and data protection

- Do **not** include user names, emails, assignees, or any PII in the output.
- Use anonymised references ("User A", "a user reported") if quoting task
  descriptions.
- App Store review tasks often embed the reviewer's display name in the task
  title. Treat these as PII and replace with "App Store reviewer" in link
  labels, even though they are public on the App Store.
- Do **not** persist Asana data beyond the session.
  - **Allowed (ephemeral, in-session):** task data held in tool-call context
    while the skill runs, plus the MCP server's own tool-result spillover
    under `~/.claude/projects/<project>/<session>/tool-results/` (managed
    by the harness, not by this skill).
  - **Not allowed:** writing Asana data to disk in any form - no scratch
    directories, no `/tmp/` files, no Write-tool dumps under `.claude/` or
    elsewhere, no `Write` of the rendered report HTML. Also not allowed:
    committing Asana data to the repo, saving it to memory, pasting it
    into other Asana tasks beyond the report destination, or including it
    in any chat output beyond the report itself.
- Web searches and external API calls after accessing Asana are blocked by
  the session-level lethal-trifecta hook, not by this skill. If you hit a
  block, that's the hook doing its job - do not retry. See
  `~/.claude/rules/lethal-trifecta.md` for the policy.
- If any task contains sensitive content (legal, HR, finance, security), halt
  per the org-level sensitive-data instruction described in the overview -
  surface a `⚠️ SENSITIVE DATA` warning, list the triggers, and wait for
  explicit user confirmation before continuing.

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
- **Trying to render the HTML via `python3` or any other Bash command.** Bash
  calls that look like report-rendering are denied after Asana access in this
  environment. Build the HTML directly in the `asana_update_task` argument -
  see step 8.4.
- **Pretty-printing `html_notes` with blank lines between block tags.** Asana
  treats `\n\n` between block elements like `</h2>` and `<ul>` as an extra
  blank line on top of each block's natural vertical spacing, producing
  visibly double-spaced output. Use no separator or at most a single real
  newline between block tags. `\n\n` between purely inline content (text,
  `<strong>`, `<a>`, etc. with no surrounding block tag) is correct and is
  the only way to get a paragraph break since Asana forbids `<p>`. See step
  8.4.
- **Typing literal `\n` escape sequences inside the `html_notes` XML
  parameter.** Claude Code does not process JSON-style escape sequences in
  tool-call XML parameters - `\n` is two literal characters (backslash + n)
  and Asana renders them as visible `\n` text in the HTML view. Default to
  no separator between block tags (`</h2><ul>`); where you need a real
  newline (paragraph break between inline content), break the parameter
  across physical lines in the XML. See step 8.4.
- **Hand-typing GIDs into the link list HTML from memory.** A single mistyped
  digit gives a broken link that looks correct at a glance. Transcribe each
  GID character-by-character from the `asana_search_tasks` / `asana_get_task`
  tool result that's still in your context - do not retype from memory or
  paraphrase. See step 5.
- **Including `custom_fields` in the bulk-fetch `opt_fields` for iOS Feedback
  or macOS Feedback.** These two projects carry 30+ custom fields per task and
  a 100-task page with full custom fields reliably spills. Use slim `opt_fields`
  (`name,created_at,completed`) for the bulk fetch; sample 5-10 tasks per Top-3
  cluster via `asana_get_task` in step 6 to populate the deep dive. See step 2.
- **Forgetting to annotate "sampled N of M" on the deep-dive output.** With the
  slim-default for the heavy projects, the deep dive runs against a per-cluster
  sample, not the full population. Make the sample size explicit so the reader
  knows the limit.
- **Writing the report HTML to a file (anywhere on disk) before posting.**
  This skill keeps Asana data in tool-call context only. Pass the assembled
  HTML directly as `html_notes` - no `Write` to `/tmp/`, no `Write` under
  `.claude/`, nothing on disk. Real newlines round-trip through MCP fine.
  See step 8.4 and the privacy section.
- **Enumerating every task in a cluster's link list.** Cap at 5-10 representative
  tasks by recency. The full list belongs in Asana's project filter, not the
  snapshot. See step 5.

## What to skip

- Completed tasks (already excluded at the API level by `completed: false` in
  step 2 - listed here as a reminder if the filter is ever dropped)
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
