# Document template

One template. Drop sections that have nothing to say rather than filling them with
placeholders. Keep each SLI as its own block so a stakeholder can quote and argue with one
in isolation, and keep tables flat - this gets pasted into Asana.

````markdown
# Observability: <feature>

**Platforms**: <iOS | macOS | both>
**Code reviewed**: <relative paths>
**Status**: proposal for review

> **Journey SLI** - the end-to-end indicator for a user journey: did the user get what they
> wanted, and get it well? This is what an SLO is set on, so it is always phrased in user
> terms.
> **Component SLI** - an indicator on one failable part of the same journey, including
> internal components. Used to find which part broke; not committed to.

## Summary

<2-3 sentences: what was reviewed, the headline finding, what we propose to commit to. A
reader should be able to stop here and know whether to read on.>

## Journeys

<One subsection per user intent.>

### <Journey name, phrased as the user's intent>

<One or two sentences on what the user is trying to do.>

**Stages**: <stage 1> → <stage 2> → <stage 3>
**Crosses**: <async boundaries, processes, app launches - anything that can orphan an attempt>
**Can fail by**: <the failure modes that matter to the user>

## Instrumentation today

<What already fires for this feature, and what each signal can or cannot answer. Name the
pixel or wide event and its file. If nothing exists, say so in one line.>

- `<pixel or wide event name>` (`<path>`): <what it observes> - <can it answer an SLI
  question as-is, after aggregation, or not at all>

## SLIs

### Journey SLI: <name, phrased as the user's action>

- **Definition**: <share of X that Y>
- **User pain**: <what the user experiences when this drops>
- **Numerator / denominator**: <success condition / attempt population>
- **Excludes**: <cancellations, expected environment failures, non-user-initiated attempts>
- **Blind spot**: <failures upstream of the denominator that this cannot see, and how it is
  handled - denominator moved earlier, or covered by a separate SLO>
- **Source**: <existing pixel or wide event, or "new: <pixel | wide event>">

### Component SLI: <name>

- **Localises**: <which Journey SLI>
- **Definition**: <share of X that Y, on the same population as the Journey SLI>
- **What it tells us**: <which part of the journey broke when the Journey SLI moves>
- **Source**: <existing, or new>

### Diagnostic dimensions

<Labels to slice the above by. Not SLIs. Must be bounded - no free text, URLs, or user
input.>

- `<dimension>`: <values, and what a skew in it would tell us>

## SLOs

<One block per SLI we propose committing to. Every one must be phrased in user-experience
terms - if it names an internal component, it belongs above as a Component SLI instead.
Targets here are guesses to argue with, not measurements.>

### <SLI name>

- **Provisional target**: <number>
- **Basis**: <why that number is plausible - comparable feature, shape of the operation,
  product tolerance. This is the part stakeholders should push back on.>
- **Window**: <1h | 24h | 7d | 28d, and why>
- **On breach we**: <the action a breach triggers. If there isn't one, this is not an SLO.>
- **Status**: provisional - no production data. Revisit after <trigger>.

## Instrumentation needed

<Ordered checklist. One line per gap, at the signal level - no field names or code.>

- [ ] <pixel | wide event> for `<journey or step>`: <attempt, terminal outcomes, latency,
  bounded categories it must capture>
- [ ] <constraint the implementer must preserve, if any: sampling, per-platform difference,
  privacy>

## Open questions

<Anything the review needs to settle: denominator choices, whether a step deserves its own
SLO, platform differences.>
````

## Notes

- The **blind spot** line on each Journey SLI is the highest-value field in the document.
  If it reads "none", say why the denominator is early enough to catch upstream failure.
- Alert thresholds, paging, routing, dashboards, and ownership do not belong here. They get
  decided when the alerting is wired up.
- Mark provisional targets as provisional in the document itself, not only in a preamble.
  Stage three of this document's life is a durable agreement, and an unmarked guess reads
  as a commitment six months later.
