# [iOS] Always Show Keyboard on New Tab Page: Requirements and Plan

Compiled on 2026-09-29 from these Asana sources:

- The project task and its comments.
- The problem analysis it links to.
- The user feedback that analysis cites.
- Related projects: Escape Hatch, app-opening settings, NTP Redesign.

Items marked **(confirm)** are proposals to settle at the kick-off.

## At a glance

| | |
|---|---|
| Platform | iOS only. Android already shows the keyboard on every NTP. |
| Objective | O-A Mobile Browser Experience · Tier 2 · critical path |
| People | DRI: Bartosz · Project Advisor: Mariusz · Requester: Chris Thelwell |
| Size | ~5 person days, ~1 week (Mariusz's estimate: T-shirt size S). Scheduled Sep 29 – Oct 5, 2026. |
| Status (Sep 29) | Hack phase in progress. Kick-off planned for Thu Oct 1. |

## 1. Goal and success criteria

**Goal:** honour the keyboard setting so the keyboard always shows when the app opens or launches to a New Tab Page (NTP).

Today the keyboard doesn't show in these cases:
- After the Fire Button.
- When the last used tab is an NTP and the app is reopened after inactivity.
- When the user left the app on the Tab Manager and it reopens to an NTP.

The only case where an NTP should not show the keyboard is when the user dismissed it.

**Success criteria:**
- The NTP always has the keyboard up when it opens, both after the Fire Button and when opening the app.
- The change rolls out gradually to all users (for example over 2 weeks) while feedback volume is monitored.

## 2. Why now

- **Inconsistent experience:**
  - About 40% of daily iOS app opens land on an NTP. About half of those show no keyboard, although the product decision was to open with the keyboard up. That's an estimated 2–4M affected users per day.
  - With the keyboard up, people can start typing straight away. After inactivity, ~60% of iOS users start a new search.
- **User feedback:**
  - Five reports between Jul 23 and Sep 3, 2026 (iPhone, app 7.229–7.235) say the keyboard setting "doesn't work". Their timing matches the Escape Hatch rollout to existing users, which reached 100% on Jul 20.
  - One user had **both** keyboard settings on and still got no keyboard.
  - None of the reports got a reply. One triage note suspected they were really feedback about the Escape Hatch.
- **Android parity:** Android always shows the keyboard on the NTP.

## 3. Settings involved

- **Keyboard on New Tab:** on by default. Shows the keyboard when a new tab is created. Over 90% of users keep it on.
- **Keyboard on App Launch:** off by default. Shows the keyboard when the app launches or returns from background, on any tab. Fewer than 1% of users ever changed it.
- **After Inactivity Open (Escape Hatch):**
  - Options are New Tab (the default) or Last Used Tab.
  - Includes an inactivity timer (30 min by default) and a "Return To" shortcut card.
  - Designed to work independently of the keyboard settings.

The two keyboard settings conflict, and that conflict is the 50/50 split:
- When the app opens to an existing NTP, the App Launch setting (off) decides, so no keyboard appears.
- When the Escape Hatch creates a fresh NTP, the New Tab setting (on) decides, so the keyboard appears.

## 4. Chosen approach

The problem analysis weighed two options: fix each case separately, or apply one standard rule. It chose **the standard rule**, because it's simpler and avoids new edge cases. Mariusz framed it as a ground rule plus a short list of exceptions. The code change is expected to be small; agreeing on the case matrix is the real work.

### Ground rule

> Whenever the user **lands** on an NTP, show the keyboard according to the setting, unless an exception applies.

**Landing** means the NTP becomes the visible content because of one of these:
- **App open:** a cold start, or a return from background after the short background window (~20s today), onto an NTP. This applies to both new and existing NTPs, before or after the inactivity threshold, and whatever "After Inactivity Open" is set to.
- **Fire Button or auto-clear:** a new NTP created by the Fire Button (any entry point, including the Quick Fire shortcut) or by Automatic Data Clearing.
- **New tab:** creating a new tab from any entry point.
- **Switching in the app:** picking an existing NTP in the Tab Manager, closing a tab so an NTP becomes current, or going Back to an NTP. **(confirm; recommended yes. It matches "the only exception is dismissal" and Android.)**

These are not landings, and the current focus state stays as it is:
- Returning within the short background window.
- Rotation or size changes.
- Closing a screen that was presented over the NTP.

### Settings semantics

- **New Tab governs every NTP landing, including app launch.** App Launch being off must no longer hide the keyboard on an NTP. App Launch is off by default and almost nobody changed it, so "off" isn't treated as a choice to hide the keyboard on NTPs.
- **App Launch keeps its current meaning for other tabs**, such as a website at launch. When it's on, it also shows the keyboard on an NTP at launch.
- **No changes** to the settings UI, copy, or defaults.
- **Respect an explicit opt-out:** with New Tab off and App Launch off, the keyboard never appears automatically on an NTP.

| New Tab | App Launch | Opens to an NTP | Opens to a website |
|---|---|---|---|
| on (default) | off (default) | keyboard | no keyboard |
| on | on | keyboard | keyboard |
| off | on | keyboard | keyboard |
| off | off | no keyboard | no keyboard |

### Exceptions (the keyboard stays hidden)

1. **The user dismissed the keyboard** on this NTP, for example with the back arrow, a swipe down, or cancel. It stays dismissed until the next landing, and a new app open resets it. **(confirm)**
2. **Returning from Settings** or another screen that was presented over the NTP. This isn't a landing, so the keyboard doesn't come back. **(confirm)**
3. **A modal prompt or onboarding dialog is showing or about to show.** Examples: "Try AI", the subscription promo, the chat-completion prompt, and other centrally coordinated prompts. The dialog wins. Whether to show the keyboard after it closes is open. **(confirm; default: keep today's behaviour)**
4. **Fire from the Escape Hatch** restores the focus state from before the burn. This is Mariusz's proposal, and it matches an earlier fix that keeps the keyboard up after burning from the "Return to" card. **(confirm)**
5. **Duck.ai:**
   - A Duck.ai chat tab isn't an NTP, so its behaviour doesn't change.
   - Today an AI-chat setting can also suppress the keyboard after a burn. Keep or drop that? **(confirm)**
   - The focused input keeps today's Search/Duck.ai mode.
6. **Existing Escape Hatch exclusions are unchanged:** onboarding, an active voice chat, and iPad (where the Escape Hatch is off by default).

## 5. Case matrix

Assumes default settings (New Tab on, App Launch off) with the feature flag on. With the flag off, every row behaves as "Today". Other setting combinations are in the table in §4.

"Today" comes from the problem analysis, Mariusz's code reading, and the Escape Hatch tech design.

| # | Scenario | Today | Expected |
|---|---|---|---|
| 1 | Cold start; the restored tab is an NTP | No keyboard (App Launch decides) | Keyboard |
| 2 | Return after ~20s or more, before the inactivity threshold; current tab is an NTP | No keyboard (App Launch decides) | Keyboard |
| 3 | Return after inactivity; last tab was a website, search, or Duck.ai chat, so the Escape Hatch creates an NTP | Keyboard (New Tab decides), plus the "Return to" card | Unchanged |
| 4 | Return after inactivity; last tab was already an NTP (with or without the card) | No keyboard, whatever the settings¹ | Keyboard |
| 5 | Return within ~20s | Focus state kept | Unchanged |
| 6 | Fire Button (burn all), landing on a new NTP | No keyboard. This is a bug: the New Tab setting should apply but doesn't. | Keyboard |
| 7 | Fire from the Escape Hatch NTP | Restores the keyboard state from before the burn; ignores the settings | Restore that state **(confirm)** |
| 8 | Quick Fire shortcut (Control+Option+Backspace) | Uses the App Launch setting | Keyboard (New Tab setting decides) |
| 9 | Automatic Data Clearing on launch, landing on an NTP | No keyboard | Keyboard |
| 10 | User left the app on the Tab Manager; app reopens onto an NTP | Sometimes no keyboard | Keyboard |
| 11 | App reopens with the Tab Manager still showing | No keyboard | Unchanged until an NTP is shown |
| 12 | New tab created from any entry point, including when closing all tabs leaves a new NTP | Keyboard. Two users reported failures; not verified. | Keyboard (check every entry point) |
| 13 | Switch to an existing NTP, close a tab onto an NTP, or go Back to an NTP | No keyboard (the setting applies only to newly created tabs) | Keyboard **(confirm)** |
| 14 | User dismisses the keyboard and stays on the NTP | Stays dismissed | Unchanged |
| 15 | Back from Settings or another presented screen | Not documented | Keyboard stays hidden **(confirm)** |
| 16 | Onboarding or promo dialog on the NTP | Keyboard suppressed | Unchanged while the dialog shows; after it closes: **(confirm)** |
| 17 | Lands on a Duck.ai chat tab | Keyboard skipped | Unchanged |
| 18 | Opens to a website tab | App Launch decides | Unchanged |

¹ When the current tab is already an NTP, the Escape Hatch's inactivity step creates nothing. The tech design doesn't say what decides the keyboard in that case. If the App Launch step is also skipped, that would explain the report from the user with both settings on. Verify this in code.

## 6. Rollout and change management

- **Feature flag:** put every behaviour change behind one remotely controlled flag. With the flag off, the app behaves exactly as today, bugs included.
- **Gradual ramp:**
  - Ramp to all users over ~2 weeks, watch feedback volume, and be ready to pause or roll back.
  - The Escape Hatch used 2% → 10% → 25% → 100% steps and waited for the release to reach wide adoption before ramping.
- **No in-app announcement** (no remote message, no What's New):
  - The Escape Hatch's awareness message got very low engagement and didn't prevent negative feedback.
  - This change keeps the same page and only adds the keyboard.
- **Expected pushback:**
  - The change is very visible. About 5–7% of users do something other than search on the NTP, so an estimated ~100k–280k users/day may be negatively affected.
  - On iOS the keyboard covers the toolbar. This is a known issue the redesign is expected to address.
  - 17.4% of NTP keyboard dismissals use the back arrow, which suggests people hiding the keyboard to see the page.
  - Android saw "keyboard always up" complaints after a similar change to address-bar focus.
- **Precedent:** the Escape Hatch drew ~75 negative feedback items, which spiked in the first weeks and settled after ~6 weeks. Users can still turn the setting off.

## 7. Don't regress

- Remote messages on the NTP still show while the keyboard is up. A past bug here blocked the Escape Hatch rollout.
- The Escape Hatch "Return to" card, its menu, and its Fire and tab-switcher buttons still work.
- Onboarding for new users and the coordinated promo prompts behave as today.
- The focused NTP still shows the Search/Duck.ai toggle. O-J will compare toggle exposure before and after this ships (see §8).
- Everything works with the NTP Redesign flag both on and off.
- No new flicker at launch. A screen flash on the post-inactivity NTP is already under investigation, so don't mistake it for a regression.
- Check iPhone in portrait and landscape, and with a hardware keyboard. iPad depends on open question 7.

## 8. Related work and dependencies

- **[iOS] NTP Redesign** is the biggest overlap:
  - Mariusz owns it; it's in progress behind its own flag.
  - Its centred search has been in internal builds since Sep 17, and experiment prep is planned for ~Oct 5–8.
  - Its designs support both keyboard up and keyboard down, and an experiment may test keyboard down.
  - Agree which rule wins for a keyboard-down cohort, and have the redesign use the same decision point.
- **O-J (AI-Browser Integrations) is waiting on this fix:**
  - On today's NTP the Search/Duck.ai toggle is only visible in the focused state. O-J believes low iOS toggle exposure is partly caused by NTPs opening without the keyboard.
  - Chris and Anna Keeton want the next toggle promo to wait until this ships.
  - O-J leans toward testing a shorter inactivity timeout on Android first, partly because of this iOS issue.
  - Tell Aitor and Chris when the ramp starts so they can read their metrics against it.
- **[iOS] Escape Hatch scroll in focused state** (not started) touches the focused NTP and the focus/dismiss handoff. Keep the two projects separate but compatible.
- **App-opening settings evaluation** (on hold) may later merge or remove the keyboard settings; whether to keep "keyboard on New Tab" is an open question there. This project must not change them.
- **Past decisions to respect:**
  - A change to the keyboard default must not override users' keyboard settings.
  - NTP designs must work with the keyboard up or down.
  - The inactivity setting is independent of the keyboard settings.

## 9. Out of scope

- Android and macOS.
- Changing, merging, or removing the keyboard or app-opening settings, or their copy or defaults.
- Which page the app opens to after inactivity, the "Return to" card, and the Escape Hatch focused-state scrolling work.
- NTP Redesign and keyboard-down experiments.
- New pixels. Asana doesn't require any; see open question 8.

## 10. Implementation plan

1. **Map the paths.**
   - List every path that lands the user on an NTP, and every place that decides keyboard focus today:
     - launch and foreground, including the inactivity branch;
     - all Fire variants, Quick Fire, and auto-clear;
     - the Tab Manager, new-tab entry points, closing and switching tabs, and Back navigation;
     - returning from presented screens;
     - onboarding and prompt presentation;
     - Duck.ai.
   - Reproduce matrix rows 1–13 on a device.
   - Find the failure path behind the report from the user with both settings on.
2. **Settle the matrix.** Use §5 as the draft. Resolve the (confirm) items with Chris and Mariusz at the kick-off, using what the hack phase found.
3. **Add one decision point.**
   - Build a single "should this NTP show the keyboard now?" decision that every landing path consults, instead of patching each path.
   - Its inputs: why the NTP appeared, both settings, whether the user dismissed the keyboard, any pending prompt or onboarding, the tab type, and the flag.
   - With the flag off, the old paths stay untouched.
4. **Route every landing path through it.** The Fire, Quick Fire, and "inactivity onto an NTP" fixes should follow from this rather than being separate patches.
5. **Test.**
   - Unit-test the decision against the whole matrix, with the flag on and off. Set the flag state explicitly in each test; don't assert the live remote config.
   - Run device QA on every row:
     - cold start;
     - return under 20s, over 20s, and past the inactivity threshold;
     - both "After Inactivity Open" values;
     - the NTP Redesign flag on and off.
6. **Roll out.** Ship behind the flag, ramp over ~2 weeks, and watch feedback. Once it reaches 100%, remove the flag and the old paths.

### Task breakdown (one task per pull request)

Tasks 2 and 3 reuse the shared keyboard check from task 1, so stack them on it or wait for it to merge. Row numbers refer to §5.

1. **Show keyboard when the app opens onto an NTP** (2–3 days; rows 1–5, 9–11, 18)
   - Add the remote feature flag and one shared check that decides whether an NTP should show the keyboard.
   - Send cold start and return-from-background through that check. The New Tab setting decides on NTPs, so App Launch being off no longer hides the keyboard.
   - Don't show the keyboard while a launch prompt is about to appear.
   - Find the failure path behind the report from the user with both settings on.
   - Unit-test the check across the whole matrix with the flag on and off.
2. **Show keyboard on NTP after the Fire Button** (1–1.5 days; rows 6–8, 16, 17)
   - Send every in-app burn through the same check and fix the Fire Button bug.
   - Switch Quick Fire from the App Launch setting to the New Tab setting.
   - Apply the kick-off's decision on Fire from the Escape Hatch.
   - Keep today's suppression for the Try AI dialog and Duck.ai chat tabs, and for the AI-chat setting if the kick-off keeps it.
3. **Show keyboard on in-app NTP landings** (0.5–1 day; rows 12–15)
   - Check every way of opening a new tab, since two users reported failures there.
   - If the kick-off keeps in-app landings in scope, also cover picking an existing NTP in the Tab Manager, closing a tab onto an NTP, and going Back to an NTP. Returning from Settings doesn't count as a landing.
   - The low end of the estimate applies if only the new-tab check remains.
4. **Roll out the keyboard flag to all users** (0.5–1 day, spread over ~2 weeks)
   - Ramp through remote config once the release with tasks 1–3 is widely adopted, for example 2% → 10% → 25% → 100%.
   - Check feedback volume at each step, and pause or roll back if it spikes. No in-app messaging.
   - Tell Aitor and Chris (O-J) when the ramp starts.
5. **Remove the keyboard feature flag** (0.5–1 day)
   - Once it's at 100% and feedback has been quiet for a while, delete the flag and the old keyboard code paths.
   - Keep only the tests for the new behaviour.

**Totals:** tasks 1–3 come to 3.5–5.5 days, which matches the Asana estimate of ~5 person days. Rollout and cleanup add 1–2 days, spread over several weeks.

Two pieces of work aren't pull requests, so they aren't listed: the kick-off (its subtask already exists), and an optional ~1-day ship review or device test pass before the ramp.

## 11. Open questions for the kick-off

1. Are in-app landings (picking an NTP in the Tab Manager, closing a tab onto an NTP, going Back to an NTP) in scope?
2. How long does a dismissal last: until the next landing, with a new app open resetting it?
3. When returning from Settings or another presented screen, should the keyboard stay hidden?
4. After a Fire from the Escape Hatch, should the app restore the focus state from before the burn, or treat it as a new landing?
5. After an onboarding or promo dialog closes, should the keyboard show?
6. Duck.ai: keep the suppression that comes from the AI-chat setting?
7. Is iPad in scope? All the reports came from iPhones, and the Escape Hatch is off by default on iPad.
8. Measurement: is feedback volume enough, or should the ramp also watch existing metrics: the NTP focused-state share, the starting-experience KPI, and O-J's toggle exposure?
9. If an NTP Redesign experiment variant defaults to keyboard down, which rule wins?

## 12. Sources (Asana)

Project:
- [Project task: [iOS] Always show keyboard on New Tab page](https://app.asana.com/1/137249556945/task/1218357179163026)
- [Problem analysis: Why does the iOS app open to a NTP without keyboard?](https://app.asana.com/1/137249556945/task/1218328294804357)
- [Kick-off task](https://app.asana.com/1/137249556945/task/1218357179352639)

User feedback:
- [Keyboard frequently doesn't open automatically](https://app.asana.com/1/137249556945/task/1216817191216209)
- [Automatic keyboard broken in latest release](https://app.asana.com/1/137249556945/task/1216943731002280)
- [Keyboard option doesn't work on new tab or launch](https://app.asana.com/1/137249556945/task/1216979179414663)
- [Both settings on, no keyboard](https://app.asana.com/1/137249556945/task/1217314562250425)
- [App Store review: Keyboard Doesn't Open](https://app.asana.com/1/137249556945/task/1218120942707013)

Settings and data:
- [[ON HOLD] Evaluate settings and defaults for app opening](https://app.asana.com/1/137249556945/task/1212799511354969)
- [Review data from use](https://app.asana.com/1/137249556945/task/1212937444666558)
- [App Opening Settings: Decide On Next Steps](https://app.asana.com/1/137249556945/task/1212937444666559)
- [Keyboard default experiment (cancelled)](https://app.asana.com/1/137249556945/task/1214072343897609)

Escape Hatch:
- [Design: NTP with Duck.ai entry point and Escape Hatch](https://app.asana.com/1/137249556945/task/1213193786026648)
- [iOS project](https://app.asana.com/1/137249556945/task/1213076120133808)
- [Tech design](https://app.asana.com/1/137249556945/task/1213263289281914)
- [iOS rollout](https://app.asana.com/1/137249556945/task/1216072039855333)
- ["After Inactivity" settings](https://app.asana.com/1/137249556945/task/1215932007136937)
- [Remote messages hidden while keyboard up (fixed)](https://app.asana.com/1/137249556945/task/1216078569376819)
- [Screen flash on post-inactivity NTP (investigation)](https://app.asana.com/1/137249556945/task/1218750279261961)

Related:
- [[iOS] NTP Redesign](https://app.asana.com/1/137249556945/task/1215190650046770)
- [NTP design PFR](https://app.asana.com/1/137249556945/task/1214489348996660)
- [[iOS] Escape Hatch scroll in focused state](https://app.asana.com/1/137249556945/task/1218184648558891)
- [O-J assessment (Sept 2026): Chris's comment on toggle exposure](https://app.asana.com/1/137249556945/task/1217095622571739/comment/1218738359347938)
