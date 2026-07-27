# Defining SLIs and SLOs - an Apple Team guide

**Audience:** any Apple Team developer working out what a feature's success means and what
to instrument to prove it.

**Status:** guidance, not gospel. The `ddg-apple-observability` skill applies this when you
ask it to propose SLIs and SLOs for a feature.

> This is the reasoning-and-examples companion to `../SKILL.md`, which holds the rules in
> short form. Keep the two consistent; put worked examples here rather than there.

## The shape

Everything hangs off a **journey**: one user intent, start to finish. The industry term is a
*critical user journey*.

- A **Journey SLI** is the end-to-end indicator for that journey. Did the user get what they
  wanted, and get it well? This is the one an SLO commits to.
- **Component SLIs** are real indicators on the failable parts of the same journey. They
  are not committed to. Their job is to tell you which part broke when the Journey SLI
  moves, so they must be measured over the same population. They are free to name
  implementation components, and are often more useful for doing so precisely.
- **Diagnostic dimensions** - error code, OS version, region - are labels you slice by.
  Not indicators. Bounded values only.

An SLO is one SLI plus a target plus a window. An SLO is never "made of" several SLIs; it
sits on the Journey SLI, and the rest explain it.

Component SLIs split two ways, and most journeys need both. **Per-aspect**: did it error,
how long did it take, was the result usable. **Per-step**: each stage that can fail on its
own.

## What makes a Journey SLI good

User-experience framing is a constraint on **SLOs**, not on SLIs. Component SLIs may name a
database write or a bridge, and naming it precisely is what makes them useful. The
requirement lands on whatever carries a target, which is always the Journey SLI and
occasionally a promoted Component SLI.

So: write the Journey SLI as a sentence a PM would have an opinion about. *"Share of
`<user action>` that `<succeeds / completes within X / is correct>`."*

Then check you can write the user-pain sentence: what does the user experience when this
number drops? If you cannot, it is not a Journey SLI. "Bookmark creation failure rate"
passes; "database write failure rate" does not, and belongs a tier down as a Component SLI -
where it is perfectly good, just not something to commit to.

Latency is the exception. "Time to first token" and "time to tunnel established" sound
technical and are waits the user genuinely feels.

Infrastructure features still get a user-framed Journey SLI - the user is another engineer
or team. Name them: *"share of analytics queries returning complete data over 24h"*, not
*"aggregation job success rate"*.

## The denominator trap

**The most common way an SLO lies to you.** Anything that fails *upstream* of your
denominator is invisible: it shrinks the denominator instead of failing the numerator, so
the number holds steady while the feature is broken.

Subscription purchase makes it concrete. Define the Journey SLI as *"share of users who
selected a plan and ended with an activated account"*, and a plan page that fails to load
cannot register at all - a user who never sees the page never selects a plan. Purchases
collapse; the SLO stays green.

Two ways out, and you have to pick one deliberately:

1. **Move the denominator earlier** - intent becomes "opened the purchase flow". This now
   includes people who were only browsing, so you need a cancelled outcome to separate
   abandonment from failure.
2. **Keep the later denominator and give the upstream step its own SLO**, accepting that the
   Journey SLI structurally cannot cover it.

Run this check on every Journey SLI. It changes the proposal more often than any other step.

## Targets are provisional, and that is fine

Most of the time you are proposing SLOs for something that has not shipped, so there is no
baseline. Guess anyway. A number provokes the argument a "TBD" does not - someone will say
"no, 98%, we drop connections on cellular constantly", and that argument is the point of
the review.

Three things make a guess useful rather than reckless:

- **State the basis.** "99.5%: one network round trip with retry, comparable to search" is
  arguable. A bare 99.5% is an assertion.
- **Mark it provisional in the document**, not in a preamble. This document becomes a
  durable agreement, and an unmarked guess reads as a commitment months later.
- **Name a revisit trigger.** "After four weeks of production data." Otherwise nothing ever
  prompts the correction.

Promote an SLI to an SLO only if you can say what a breach makes the team do. Alert
thresholds, paging, routing, and dashboards are decided later, when the alerting is wired.

## Other things that bite

- **A raw count is not an SLI.** `m_chat_submitted` is a metric; the share of submissions
  that get a response is the SLI.
- **Separate cancellations, expected environment failures, and unknowns from real
  failures.** A user in flight mode is not a service failure.
- **Latency as percentiles, never averages**, and tie the bound to what the user feels.
- **Split per platform when the journeys genuinely differ.** One product concept, two
  definitions, rather than forcing one measurement onto both.
- **Low volume is a real constraint.** macOS counts, especially from a sampled wide event,
  can be small enough that swings are noise. Say so rather than proposing a tight
  percentile that cannot be measured.
- **Privacy is a hard gate.** No URLs, user input, file paths, location, or unbounded IDs.
- **Don't over-aggregate.** A journey SLO is useful. A feature health score rolled up from
  thirty signals moves without telling you what broke.
- **Cut vanity SLIs.** If a 10% regression would not indicate real user pain, it is not an
  indicator worth having.

## Worked examples

### Duck.ai prompt submission - aspects, not steps

**Journey SLI**: share of prompt submissions where the user receives a usable response.
**User pain**: taps send, gets nothing, or a spinner that never resolves.

**Component SLIs**, per-aspect on the same submissions: error rate, time to first token,
response is displayable text. Plus one per-internal-component: user script bridge delivery
rate, which localises a break invisible from the outside. **Dimensions**: failure category
(network, timeout, parse, backend, cancelled, unknown), platform.

Teaching point: one journey, one clear success condition, and the components are qualities
of the same attempt rather than stages of a funnel. Note that the bridge SLI names a
component openly and is the right shape - it simply never carries a target.

### Subscription purchase - steps, and the denominator trap

**Journey SLI**: share of purchase intents that end with an activated account.
**User pain**: pays and cannot use what they paid for, or gets stuck part-way.

**Component SLIs**, per-step: plan page loaded, App Store purchase succeeded, account
activated. Note that plan-page load sits outside the denominator if intent is defined as
"selected a plan" - see the denominator trap above.

Teaching point: a multi-stage journey crossing StoreKit, the backend, and possibly an app
restart. Needs one row per attempt with a terminal outcome, which is what a wide event is
for.

### VPN connection - the denominator is the whole problem

**Journey SLI**: share of user-initiated connection attempts that establish a working
tunnel within a bound the user tolerates.
**User pain**: toggles VPN on and is not protected, or waits long enough that it feels
broken.

**Watch out**: on-demand and wake-triggered reconnections can flood the attempt count with
connections the user never initiated. Count those and the SLI stops describing user
experience entirely. The denominator has to be user-initiated attempts specifically.
