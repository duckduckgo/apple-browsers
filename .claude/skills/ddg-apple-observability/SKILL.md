---
name: ddg-apple-observability
description: >
  Use when deciding what to measure for an iOS or macOS feature in this monorepo: the user journeys that matter, the SLIs that show whether each journey is working, and which of those SLIs deserve an SLO. Fires on "what SLIs/SLOs should this feature have", "what should we instrument for X", "audit the observability for Y", "how would we know if this feature is healthy in production", and on product-framed versions of the same question. Produces a markdown proposal that the author thinks with, then posts for stakeholder review, then keeps as the feature's documented agreement. Designs instrumentation but does not write it - hand implementation to the pixel rules and the wide-event guidance once the SLIs are agreed. Does not choose alert thresholds, paging behaviour, dashboards, or ownership.
---

# Apple observability: journeys, SLIs, SLOs

## What you are producing

One markdown document that lives three lives:

1. The author works out what success actually means for the feature.
2. The author posts it for stakeholder review, where individual SLIs get argued over.
3. It becomes the documented agreement on what this feature's success is.

Stage 2 dictates the format. Make every SLI a self-contained block carrying its own
rationale, so a stakeholder can quote one and disagree with it without reading the rest.
Avoid nested tables and deep structure - this gets pasted into Asana.

## The model

Everything hangs off a **journey**: one user intent, start to finish. Purchase a
subscription. Get an answer from Duck.ai. Connect the VPN. (The industry term is a
*critical user journey*.) Each journey gets three tiers:

| Tier | What it is | Carries an SLO? |
|---|---|---|
| **Journey SLI** | the single end-to-end indicator: did the user get what they wanted, and get it well? | yes - this is what the SLO sits on |
| **Component SLI** | a real SLI on one failable part of the journey. Localises a breach of the Journey SLI | only if it is itself user-framed |
| **Diagnostic dimension** | error code, OS version, region, device class | never - these are labels you slice by, not indicators |

**User-experience framing is a constraint on SLOs, not on SLIs.** A Journey SLI must always
be phrased as what the user is doing, because that is what carries the SLO. A Component SLI
is free to name an implementation component - "token refresh failure rate", "user script
bridge delivery rate" - and is often more useful for naming it precisely. The rule bites
only at promotion: nothing carries an SLO unless it can be stated in user-experience terms.

An SLO is one SLI plus a target plus a window. There is no such thing as an SLO built from
several SLIs: the SLO sits on the Journey SLI, and the Component SLIs exist to tell you
which part broke. They must therefore be measured over the same population as the Journey
SLI, so the arithmetic lines up when someone goes looking.

Component SLIs come in three flavours, and most journeys use more than one:

- **Per-aspect**: did it error, how long did it take, was the result usable. (Duck.ai:
  error rate, time to first token, response is displayable text.)
- **Per-step**: each stage the user passes through that can fail on its own. (Subscription
  purchase: plan page loaded, App Store purchase succeeded, account activated.)
- **Per-internal-component**: a dependency that can break the journey without being visible
  to the user. (Token refresh, bridge delivery, database write.) Name these precisely - they
  are the fastest route from "the SLO broke" to "here is why".

Define both terms on first use in the document. "Journey SLI" and "Component SLI" are our
house terms rather than standard SRE vocabulary, so a stakeholder may not arrive knowing
them.

## Workflow

### 1. Map the journey

Read the feature's code - entry points and boundaries are enough, you do not need a
complete read. Establish:

- What is the user trying to do? Name each distinct intent; each one is a journey.
- What stages does it pass through, and which can fail independently?
- Where does it cross an async boundary, a process, or an app launch?
- What are the terminal outcomes, including user cancellation and "we never found out"?

### 2. Inventory what exists

Find the pixels and wide events already firing for this feature before proposing
anything. A proposal that misses existing instrumentation loses credibility in review and
recommends work that is already done. `references/repo-instrumentation.md` has the search
paths.

For each signal found, record what user outcome it observes and which SLI question it can
or cannot answer. Prefer reuse.

### 3. Define the SLIs

For each journey, write the Journey SLI first, then the Component SLIs beneath it. For
every one:

- **Definition**: one sentence framed as what the user is trying to do. "Share of
  `<user action>` that `<succeeds / completes within X / is correct>`."
- **User pain**: what the user experiences when this number drops. Required for a Journey
  SLI - if you cannot write it, the SLI cannot carry the SLO and needs reframing. For a
  Component SLI, write what its movement tells you instead.
- **Numerator and denominator**: what counts as success, what counts as an attempt.
- **Source**: the existing pixel or wide event, or the gap that needs new instrumentation.
- **Tier**: Journey SLI, or Component SLI and which Journey SLI it localises.

### 4. Check what the denominator hides

For each Journey SLI, name the failures that happen *before* the denominator is counted.
Those are invisible to the SLO: they shrink the denominator instead of failing the
numerator, so the number stays green while the feature is broken.

Worked case: "share of users who selected a plan and ended with an activated account"
cannot see a plan page that fails to load, because a user who never sees the page never
selects a plan.

Two ways out. Say in the document which one you took:

- Move the denominator earlier (purchase flow opened) and separate abandonment from
  failure with a cancelled outcome.
- Keep the later denominator and promote the upstream Component SLI to its own SLO,
  because the Journey SLI structurally cannot cover it.

Do this for every Journey SLI. It is the check most likely to change the proposal.

### 5. Pick the SLOs

Selection, not calibration: which of these do we want to be told about when they break?
Every Journey SLI is a candidate. Two gates decide the rest:

- **User experience.** An SLO states what the user gets, so a Component SLI is promotable
  only if it is user-visible in its own right - "plan page loads" can carry an SLO, "token
  refresh succeeds" cannot, however important it is.
- **Action.** Promote nothing you cannot say what the team would do about. An SLI nobody
  would act on is not an SLO, however good the metric.

In practice a Component SLI earns an SLO when it sits outside its Journey SLI's denominator
or is owned by a different team.

Guess the target. A number provokes the argument that a "TBD" does not - but give the
reasoning, because a bare number is an assertion while a justified one is arguable
("99.5%: a single network round trip with retry, comparable to search"). Mark it
`provisional` and name when to revisit it, so the guess cannot harden into a commitment
nobody agreed to.

Leave alert thresholds, paging, routing, and dashboards alone. Those get decided when the
alerting is wired up.

### 6. Name the instrumentation, then write it up

For each SLI existing instrumentation cannot answer, say what needs to exist: pixel or
wide event, the attempt and outcome it must capture, latency if delay is part of the pain,
the bounded categories needed for drilldown, and any constraint the implementer must
preserve. `references/repo-instrumentation.md` covers the choice and what it costs.

Write the document with `references/output-template.md`. Keep prose tight: a senior
engineer should skim it in three minutes, a PM should read it end to end in ten.

## Rules that come up every time

- **Anything carrying an SLO is framed in user experience.** Journey SLIs always; Component
  SLIs only when promoted. If an SLO's name contains *API, database, request, queue, bridge,
  endpoint, backend, handler*, ask "what user-visible action breaks when this breaks?" That
  action is the SLO; the component stays a Component SLI beneath it. Latency is the
  exception - "time to first token" is a wait the user genuinely feels.
- **No vanity SLIs.** If a 10% regression would not indicate real user pain, cut it.
- **A raw count is not an SLI.** The share of attempts that succeeded is.
- **Bounded categories, never free text**, for failure drilldowns. Separate user
  cancellation, expected environment failure, timeout, and unknown from real failures.
- **Latency as percentiles, never averages.**
- **Split per platform when the iOS and macOS journeys genuinely differ.** One product
  concept, two definitions, rather than forcing one measurement onto both.
- **Privacy is a hard gate.** No URLs, user input, file paths, location, or unbounded
  identifiers. Use bounded categories for context.
- **Do not over-aggregate.** A journey SLO is useful; a feature-wide health score rolled
  up from thirty signals is not, because nothing tells you what broke.

## Out of scope

Alert thresholds, paging behaviour, alert routing, dashboards, and ownership: all decided
later by the developer or team. Writing the instrumentation: if the user asks to apply the
recommendations, hand the checklist to the wide-event guidance or `.cursor/rules/pixels.mdc`
and stop once the code emits what the SLIs need. Do not inline library APIs, field names,
validation commands, or code snippets in the document.

## References

- `references/repo-instrumentation.md` - pixels and wide events in this repo: what each
  can measure, how to choose, what constrains them, where to find existing ones.
- `references/defining-slis-and-slos.md` - the team-facing guide to the same canon, with
  worked examples. Read it when you want an example or the fuller reasoning.
- `references/output-template.md` - the document template.
