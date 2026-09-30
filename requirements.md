# [iOS] Always Show Keyboard on New Tab Page: Requirements and Plan

This document was compiled on 2026-09-29 from these Asana sources:

- The project task and its comments.
- The problem analysis it links to.
- The user feedback that analysis cites.
- Related projects: Escape Hatch, app-opening settings, NTP Redesign.

On 2026-09-30 it was reviewed against the code and the sources:
- §5's "Today" column is now checked against the code.
- Claims that no source supports are removed or marked.
- Code references and the plan for each pull request are in `implementation.md`.

Items marked **(confirm)** are proposals to settle at the kick-off.

## At a glance

| | |
|---|---|
| Platform | iOS only. Android already shows the keyboard on every NTP. |
| Objective | O-A Mobile Browser Experience · Tier 2 · critical path |
| People | DRI: Bartosz · Project Advisor: Mariusz · Requester: Chris Thelwell |
| Size | Estimated at ~5 person days and ~1 week (T-shirt size S). After the review: 3.5–4 days of code in 4 pull requests and a ramp over ~3–4 calendar weeks. Flag removal follows about a month after 100%. Scheduled Sep 29 – Oct 5, 2026. |
| Status (Sep 30) | Hack phase and code review done. Kick-off planned for Thu Oct 1. |

## 1. Goal and success criteria

**Goal:** honour the keyboard setting so the keyboard always shows when the app opens or launches to a New Tab Page (NTP).

The project task lists three cases where the keyboard doesn't show today:
- After the Fire Button.
- When the last used tab is an NTP and the app is reopened after inactivity.
- When the user left the app on the Tab Manager and it reopens to an NTP.

The code shows more (§3).

An NTP should show the keyboard unless one of these applies:
- the user dismissed it;
- the user turned the setting off;
- one of the exceptions in §4 applies.

**Success criteria:**
- The NTP has the keyboard up when it opens, both after the Fire Button and when opening the app.
- The change rolls out gradually to all users (for example over 2 weeks) while feedback volume is monitored.

## 2. Why now

- **Inconsistent experience:**
  - About 40% of daily iOS app opens land on an NTP (source not found in the linked tasks; confirm). The problem analysis estimates that about half of those show no keyboard, although the product decision was to open with the keyboard up. That's an estimated 2–4M affected users per day.
  - With the keyboard up, people can start typing straight away. After inactivity, ~60% of iOS users start a new search (source not found in the linked tasks; confirm).
- **User feedback:**
  - Five reports filed between Jul 23 and Sep 3, 2026 (app 7.229–7.235) say the keyboard setting "doesn't work". The four that state a device say iPhone.
  - The problem analysis reads the three July reports as most likely about the keyboard settings not changing Escape Hatch behaviour. It calls the two later ones more bug-like.
  - One user had **both** keyboard settings on and still got no keyboard. The code explains why (§5 row 4).
  - The feedback tasks record no replies.
- **Android parity:** Android always shows the keyboard on the NTP.

## 3. Settings involved

- **Keyboard on New Tab:**
  - On by default. Over 90% of users keep it on.
  - Applies when an NTP opens through a new-tab action. That includes the NTP the Escape Hatch opens.
  - The NTP Redesign's customization sheet has a toggle that changes this same setting.
- **Keyboard on App Launch:**
  - Off by default. Fewer than 1% of users ever changed it.
  - Applies on a cold start, or on a return after more than 20s in the background, on any tab.
- **After Inactivity Open (Escape Hatch):**
  - Options are New Tab or Last Used Tab. New Tab is the default on iPhone; iPad defaults to Last Used Tab.
  - Has an inactivity timer (30 min by default, remotely configurable) and a "Return To" shortcut card.
  - Designed to work independently of the keyboard settings.
- **"Search & Duck.ai" address bar setting** (Settings → AI Features; "Search only" or "Toggle between Search and Duck.ai"):
  - Not a keyboard setting.
  - Today it blocks the keyboard after every Fire (§4, exception 5).

**Why about half of NTP opens have no keyboard.** This was checked in code; file references are in `implementation.md` §1.
- An app open onto an existing NTP uses App Launch, which is off by default.
- After inactivity, when the current tab is already an NTP, neither setting is checked. This also happens on a cold start, because the inactivity check uses the last time the app went to the background, even across restarts.
- After Fire, the keyboard is skipped when "Search & Duck.ai" is on.
- Close All Tabs, closing the last tab and the Home button all create an NTP without the keyboard.
- Only an NTP opened through a new-tab action, including the Escape Hatch's, uses the New Tab setting.

## 4. Chosen approach

The problem analysis weighed two options: fix each case separately, or apply one standard rule. It leaned toward the standard rule as the simpler one, and the project adopted it. Mariusz framed it as a ground rule plus a short list of exceptions. The code change is expected to be small; agreeing on the case matrix is the real work.

### Ground rule

> Whenever the user **lands** on an NTP, show the keyboard according to the setting, unless an exception applies.

**Landing** means the NTP becomes the visible content because of one of these:
- **App open:** a cold start, or a return after more than 20s in the background, onto an NTP.
  - It covers both new and existing NTPs, before or after the inactivity threshold, and whatever "After Inactivity Open" is set to.
- **Fire Button or auto-clear:** a burn that leaves a new NTP. That covers:
  - the toolbar or iPad tab bar;
  - the Fire widget or Control Center control;
  - the Tab Manager;
  - the Quick Fire shortcut;
  - Automatic Data Clearing.
- **New tab:** any entry point, including Close All Tabs, closing the last tab and the Home button.
- **Switching in the app:** picking a *different* NTP in the Tab Manager, or closing the current tab onto an NTP. **(confirm; recommended yes. It matches the ground rule and Android.)**

These are not landings, and the current focus state stays as it is:
- Returning within 20s.
- Rotation or size changes.
- Closing a screen that was presented over the NTP, including tapping Done in the Tab Manager or picking the same NTP.
- Swiping between tabs onto an NTP. **(confirm; recommended. A keyboard that pops up mid-swipe is jarring.)**

Going Back can't reach an NTP. An NTP isn't in the page history, so it isn't in the rules.

### Settings semantics

- **New Tab governs every NTP landing, including app launch.** App Launch being off must no longer hide the keyboard on an NTP. App Launch is off by default and almost nobody changed it, so "off" isn't treated as a choice to hide the keyboard on NTPs.
- **App Launch keeps its current meaning for other tabs**, such as a website at launch. When it's on, it also shows the keyboard on an NTP at launch.
- **No changes** to the settings UI, copy, or defaults.
- **Respect an explicit opt-out:** with New Tab off and App Launch off, the keyboard never appears automatically on an NTP.

The table below is this project's proposal. The sources say "honour the keyboard setting", and the project task frames the problem as App Launch overriding New Tab.

| New Tab | App Launch | Opens to an NTP | Opens to a website |
|---|---|---|---|
| on (default) | off (default) | keyboard | no keyboard |
| on | on | keyboard | keyboard |
| off | on | keyboard | keyboard |
| off | off | no keyboard | no keyboard |

### Exceptions (the keyboard stays hidden)

1. **The user dismissed the keyboard** on this NTP, for example with the back arrow, a swipe down, or Cancel.
   - It stays dismissed until the next landing, and a new app open resets it.
   - No state needs storing, because the keyboard is only decided when the user lands.
   - **(confirm)**
2. **Returning from Settings or another presented screen** isn't a landing, so the keyboard doesn't come back. Nothing re-focuses today, so this needs no code. **(confirm)**
3. **A modal prompt or onboarding dialog is showing or about to show.** The dialog wins.
   - Examples: "Try AI", the subscription promo, the chat-completion prompt, and the prompts shown at launch.
   - Today this only partly holds. At launch the keyboard is scheduled before the launch prompt, so the prompt opens over it. When an NTP opens, only the subscription promo and the chat-completion prompt are checked. This project fixes app open and Fire.
   - While onboarding is in progress, app opens onto an NTP show no keyboard. This matches the Escape Hatch.
   - Whether to show the keyboard after the dialog closes is open. **(confirm; default: keep today's behaviour, no keyboard)**
4. **Fire from the Escape Hatch** restores the focus state from before the burn.
   - This burns only the "Return to" tab, and the user stays on the NTP.
   - It's how the code has worked since the Escape Hatch "hide" change (#5327).
   - Mariusz proposes keeping it. **(confirm)**
5. **Duck.ai:**
   - A Duck.ai chat tab isn't an NTP, so its behaviour doesn't change.
   - The "AI-chat setting" is the "Search & Duck.ai" address bar setting.
     - Today it blocks the keyboard after *every* Fire, which is the Fire Button bug. Users who chose the Search/Duck.ai toggle never get the keyboard after Fire.
     - The block was added for the last onboarding step.
     - **(confirm; recommended: keep the block only during onboarding)**
   - The focused input opens in the last used Search/Duck.ai mode, as today.
6. **Existing Escape Hatch exclusions are unchanged:**
   - onboarding;
   - an active voice chat;
   - iPad, where After Inactivity defaults to Last Used Tab.

**Entry points that keep their own behaviour** (out of scope):
- These always show the keyboard, whatever the settings:
  - the search widget;
  - Lock Screen and Control Center search;
  - Siri "Open DuckDuckGo";
  - onboarding completion.
- The Favorites widget and control never show it.

## 5. Case matrix

Defaults: New Tab on, App Launch off, feature flag on. With the flag off, every row behaves as "Today". Other setting combinations are in the table in §4.

"Today" was checked against the code on 2026-09-30. File references are in `implementation.md`.

| # | Scenario | Today (code) | Expected |
|---|---|---|---|
| 1a | Cold start within the inactivity threshold; the restored tab is an NTP | No keyboard (App Launch decides; the 20s rule doesn't apply on a cold start) | Keyboard |
| 1b | Cold start after the inactivity threshold; the restored tab is an NTP | No keyboard, whatever the settings (same path as row 4) | Keyboard |
| 2 | Return after more than 20s, before the inactivity threshold; current tab is an NTP | No keyboard (App Launch decides) | Keyboard |
| 3 | Return after inactivity; last tab was a website, search, or Duck.ai chat, so the Escape Hatch opens an NTP | Keyboard (New Tab decides), plus the "Return to" card | Unchanged. With New Tab off and App Launch on: keyboard (§4 table) |
| 4 | Return after inactivity; current tab is already an NTP | No keyboard, whatever the settings¹ | Keyboard. If Settings or the Tab Manager is open, it stays open, with no keyboard **(confirm, question 10)** |
| 5 | Return within 20s | Nothing runs; the focus state isn't touched | Unchanged |
| 6 | Fire (toolbar, iPad tab bar, Fire widget or control, Tab Manager), landing on a new NTP | Keyboard after 0.3s if New Tab is on. Skipped when "Search & Duck.ai" is on, on a Duck.ai tab, when "Try AI" is due, or in fire mode (the Tab Manager stays open) | Keyboard, also with "Search & Duck.ai" on, outside onboarding **(confirm)** |
| 7 | Fire from the Escape Hatch card | Restores the keyboard state from before the burn; ignores the settings | Unchanged **(confirm)** |
| 8 | Quick Fire shortcut (Control+Option+Backspace) | Same as row 6. Its App Launch check runs, but the burn undoes it | Same as row 6 |
| 9 | Automatic Data Clearing, landing on an NTP | As rows 1a, 1b and 2 | As rows 1a, 1b and 2 |
| 10 | User left the app on the Tab Manager; app reopens | Cold start: rows 1a/1b. After inactivity with a website tab: the Tab Manager closes and the keyboard shows. After inactivity with an NTP: the Tab Manager stays open (row 11) | Keyboard wherever the NTP ends up visible |
| 11 | App reopens with the Tab Manager still showing | No keyboard | Unchanged until an NTP is shown |
| 12 | New tab: explicit new-tab actions, Close All Tabs, closing the last tab, the Home button | Keyboard for explicit new-tab actions; none for the other three | Keyboard for all |
| 13 | Pick a different NTP in the Tab Manager, or close the current tab onto an NTP | No keyboard | Keyboard **(confirm)**. Swiping onto an NTP: unchanged **(confirm)** |
| 14 | User dismisses the keyboard and stays on the NTP | Stays dismissed | Unchanged |
| 15 | Back from Settings or another presented screen | Nothing re-focuses | Keyboard stays hidden **(confirm)** |
| 16 | Onboarding dialog, promo, or launch prompt | Partly suppressed; a launch prompt opens over the keyboard | The dialog wins; after it closes: **(confirm)** |
| 17 | Lands on a Duck.ai chat tab | Search isn't focused | Unchanged |
| 18 | Opens to a website tab | App Launch decides | Unchanged |
| 19 | Search widget, Lock Screen or Control Center search, Siri "Open DuckDuckGo" | Keyboard, whatever the settings | Unchanged |
| 20 | Favorites widget or control | No keyboard | Unchanged |
| 21 | App lock (Face ID) at launch | Keyboard after unlock when a rule applies. Probably lost if the first Face ID prompt is cancelled (not checked on a device) | Keyboard after unlock (verify) |

¹ Confirmed in code:
- After inactivity with the New Tab option, the launch handler skips its keyboard step.
- The coordinator then returns early when the current tab is already an NTP. It does the same during a voice chat.
- So neither setting is checked. That explains the report from the user with both settings on.
- The Escape Hatch design chose this on purpose, to avoid bouncing the keyboard, and a unit test covers it.

## 6. Rollout and change management

- **Feature flag:**
  - Put every behaviour change behind one remote flag, `alwaysShowKeyboardOnNewTabPage` (an `iOSBrowserConfig` subfeature).
  - With the flag off, the app behaves exactly as today, bugs included.
  - Enable it for internal users first.
- **Gradual ramp:**
  - Ramp to all users over ~2 weeks, watch feedback volume, and be ready to pause or roll back.
  - The Escape Hatch used 2% → 10% → 25% → 100% steps. It waited for the release to reach wide adoption before ramping.
  - Set `minSupportedVersion` to the first release with the change, and don't raise it later. Raising it turns the feature off for older versions.
  - Don't ramp while another NTP change is rolling out, such as an NTP Redesign experiment, because feedback becomes hard to attribute. The Escape Hatch ramp was delayed for the same reason.
- **No in-app announcement** (no remote message, no What's New):
  - The Escape Hatch's awareness message got very low engagement and didn't prevent negative feedback.
  - This change keeps the same page and only adds the keyboard.
- **Expected pushback:**
  - The change is very visible. About 5–7% of users do something other than search on the NTP, so an estimated ~100k–280k users/day may be negatively affected.
  - On iOS the keyboard covers the toolbar. The redesign is expected to address this (source not found in the linked tasks; confirm).
  - In early data from the cancelled keyboard-default experiment (April 2026), 17.4% of NTP dismissals used the back button.
- **Precedent:** the Escape Hatch drew ~75 negative feedback items. They spiked in the first weeks and settled after ~6 weeks. Users can still turn the setting off.

## 7. Don't regress

- Remote messages on the NTP still show while the keyboard is up. A past bug here blocked the Escape Hatch rollout.
- The Escape Hatch "Return to" card and its menu (Return to Tab, Close Tab, Delete Tab, Hide These Shortcuts) still work.
- Onboarding for new users and the coordinated promo prompts behave as today.
- The focused NTP still shows the Search/Duck.ai toggle. O-J wants to read toggle exposure before and after this ships (see §8).
- Everything works with the NTP Redesign flag both on and off. The redesign hides the address bar until it's focused, so check for flicker when the keyboard appears at launch.
- No new flicker at launch. There's an open task to investigate a screen flash on the post-inactivity NTP (not started), so don't mistake that flash for a regression.
- Check:
  - iPhone in portrait and landscape;
  - a hardware keyboard;
  - VoiceOver, where focus moves to the address bar on each landing;
  - app lock.

  iPad depends on open question 7.

## 8. Related work and dependencies

- **[iOS] NTP Redesign** is the biggest overlap:
  - Mariusz owns it; it's in progress behind its own flag.
  - Its centred search has been in internal builds since Sep 17, and experiment prep is planned for ~Oct 5–8.
  - Its designs support both keyboard up and keyboard down, and an experiment may test keyboard down.
  - It shows the Search/Duck.ai toggle in the unfocused state too.
  - For an earlier keyboard-down experiment, Chris said a keyboard-down variant should apply only at launch, and explicitly created tabs should keep the keyboard up.
  - Agree which rule wins for a keyboard-down cohort, and have the redesign use the same decision point.
- **O-J (AI-Browser Integrations):**
  - In the O-J assessment, Chris suggests that low iOS toggle numbers may be partly because NTPs open without the keyboard, so users don't see the toggle. He would wait for this project before reading the data.
  - Users who chose "Search & Duck.ai" are also the ones who get no keyboard after Fire today.
  - Proposal: tell O-J when the ramp starts, so they can read their metrics against it.
- **[iOS] Escape Hatch scroll in focused state** (not started) touches the focused NTP and the hand-off between focusing and dismissing. Keep the two projects separate but compatible.
- **App-opening settings evaluation** (on hold) may later merge or remove the keyboard settings. Its proposal leans toward removing "keyboard on New Tab". This project must not change them.
- **Past decisions to respect:**
  - A change to the keyboard default must not override users' keyboard settings.
  - NTP designs must work with the keyboard up or down.
  - The inactivity setting is independent of the keyboard settings.

## 9. Out of scope

- Android and macOS.
- Changing, merging, or removing the keyboard or app-opening settings, or their copy or defaults.
- Which page the app opens to after inactivity, the "Return to" card, and the Escape Hatch focused-state scrolling work.
- NTP Redesign and keyboard-down experiments.
- The entry points in §4 that keep their own behaviour.
- New pixels. Asana doesn't require any; see open question 8.

## 10. Implementation plan

The full plan is in `implementation.md`. In short:

1. **One decision point:** a small shared keyboard rule, `NewTabPageKeyboardPolicy`, that every flag-on landing path consults. With the flag off, the old paths stay untouched.
2. **Inputs:**
   - why the NTP appeared (app open, in-app landing, or after Fire);
   - time spent in the background;
   - both settings;
   - whether the current tab is an NTP;
   - pending prompts and onboarding;
   - Duck.ai tabs and "Search & Duck.ai" (after Fire only);
   - the flag.

   Dismissal needs no stored state.
3. **Tests:** unit-test the rule and the launch routing with the flag on and off. Set the flag state explicitly in each test, and don't assert the live remote config. Device QA covers every §5 row, with the NTP Redesign flag on and off.
4. **Roll out:** ship behind the flag and ramp over ~2 weeks. Removing the flag and the old paths is a later follow-up, about a month after 100%.

### Task breakdown (one task per pull request)

Four stacked pull requests. Rows refer to §5. Remote config changes are made in the privacy-configuration repository, so they aren't counted here.

1. **Show keyboard when the app opens onto an NTP** (2 days; rows 1a, 1b, 2–5, 9–11, 18)
   - Add the flag and the shared rule.
   - Send cold starts and returns from the background through the rule, including an inactivity return onto an existing NTP.
   - Apply the §4 table to the NTP the Escape Hatch opens.
   - No keyboard during onboarding.
2. **Hold the launch keyboard while a launch prompt is pending** (0.5 day; rows 16, 18)
   - Reuse the prompt coordinator's existing "a prompt is on its way" state.
   - Separate because it touches the prompt coordination code.
3. **Show keyboard on the NTP after Fire** (0.5 day; rows 6–8, 16, 17)
   - Keep the "Search & Duck.ai" block only during onboarding.
   - Quick Fire needs no code.
4. **Show keyboard on in-app NTP landings** (1 day, or 0.5 if question 1 is "no"; rows 12–15)
   - Close All Tabs, closing the last tab and the Home button.
   - If question 1 is "yes", also picking a different NTP in the Tab Manager and closing a tab onto an NTP.

**Totals:** tasks 1–4 come to 3.5–4 days, in line with the ~5 person-day estimate. The ramp itself is remote config only, and takes ~3–4 calendar weeks after merge, because it waits for release adoption.

Some work doesn't need a pull request:
- the kick-off (its subtask already exists);
- a device check of the assumptions that come from reading the code (row 21, Quick Fire, ⌘T on an NTP);
- the remote config ramp;
- removing the flag, about a month after 100% (a separate pull request later);
- an optional ~1-day ship review or device test pass before the ramp.

## 11. Open questions for the kick-off

Each question shows the recommended answer.

1. Are in-app landings in scope: picking a different NTP in the Tab Manager, and closing a tab onto an NTP? *Recommended: yes. Swiping onto an NTP is not a landing.*
2. How long does a dismissal last? *Recommended: until the next landing, with a new app open resetting it. No code is needed.*
3. When returning from Settings or another presented screen, should the keyboard stay hidden? *Recommended: yes, as today. No code is needed.*
4. After a Fire from the Escape Hatch, should the app restore the focus state from before the burn? *Recommended: yes, as today.*
5. After an onboarding dialog or launch prompt closes, should the keyboard show? *Recommended: no, as today.*
6. Should the "Search & Duck.ai" setting still block the keyboard after Fire? *Recommended: only during onboarding, which is what it was added for.*
7. Is iPad in scope? *Recommended: yes, with no iPad-specific code. No report mentions iPad, and After Inactivity defaults to Last Used Tab there.*
8. Measurement: is feedback volume enough, or should the ramp also watch the NTP focused-state share, the starting-experience KPI, and O-J's toggle exposure?
   - The NTP session event records the keyboard state before the launch keyboard appears, so app opens are logged as keyboard down.
   - If we rely on it, fix that first (~0.5 day).
9. If an NTP Redesign experiment variant defaults to keyboard down, which rule wins, and when does each ramp run?
10. After inactivity, when the current tab is already an NTP and Settings or the Tab Manager is open, should the app close it?
    - When the current tab is a website, the app already closes it and shows the NTP. The After Inactivity spec says "no matter where you were".
    - *Recommended: keep today's behaviour here and track it as an Escape Hatch follow-up.*

## 12. Sources (Asana)

Project:
- [Project task: [iOS] Always show keyboard on New Tab page](https://app.asana.com/1/137249556945/task/1218357179163026)
  - [Chris: App Launch overriding New Tab](https://app.asana.com/1/137249556945/task/1218357179163026/comment/1218357179163031)
  - [Mariusz: current behaviour from the code](https://app.asana.com/1/137249556945/task/1218357179163026/comment/1218359865688017)
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
  - [Chris: the inactivity setting is independent of the keyboard settings](https://app.asana.com/1/137249556945/task/1212799511354969/comment/1213585898289074)
- [Review data from use](https://app.asana.com/1/137249556945/task/1212937444666558)
- [App Opening Settings: Decide On Next Steps](https://app.asana.com/1/137249556945/task/1212937444666559)
- [Keyboard default experiment (cancelled)](https://app.asana.com/1/137249556945/task/1214072343897609)
  - [Project scope: don't override users' keyboard settings](https://app.asana.com/1/137249556945/task/1214074639816242)
  - [Chris: keyboard-down only at launch](https://app.asana.com/1/137249556945/task/1214072343897609/comment/1214077293399946)

Escape Hatch:
- [Design: NTP with Duck.ai entry point and Escape Hatch](https://app.asana.com/1/137249556945/task/1213193786026648)
  - [Inactivity setting independent of keyboard settings](https://app.asana.com/1/137249556945/task/1213193786026648/comment/1213254656925341)
  - [An unused NTP is reused with no card](https://app.asana.com/1/137249556945/task/1213193786026648/comment/1213279742635301)
- [iOS project](https://app.asana.com/1/137249556945/task/1213076120133808)
- [Tech design](https://app.asana.com/1/137249556945/task/1213263289281914)
- [iOS rollout](https://app.asana.com/1/137249556945/task/1216072039855333)
  - [Raising the minimum version turns the feature off](https://app.asana.com/1/137249556945/task/1216072039855333/comment/1216168444735691)
- [Rollout ramp record](https://app.asana.com/1/137249556945/task/1216337926172567)
- ["After Inactivity" settings](https://app.asana.com/1/137249556945/task/1215932007136937)
- [Remote messages hidden while keyboard up (fixed)](https://app.asana.com/1/137249556945/task/1216078569376819)
- [Screen flash on post-inactivity NTP (investigation)](https://app.asana.com/1/137249556945/task/1218750279261961)

Related:
- [[iOS] NTP Redesign](https://app.asana.com/1/137249556945/task/1215190650046770)
- [NTP design PFR](https://app.asana.com/1/137249556945/task/1214489348996660)
- [[iOS] Escape Hatch scroll in focused state](https://app.asana.com/1/137249556945/task/1218184648558891)
- [O-J assessment (Sept 2026): Chris's comment on toggle exposure](https://app.asana.com/1/137249556945/task/1217095622571739/comment/1218738359347938)
