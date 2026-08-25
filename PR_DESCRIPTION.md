### Description

With the floating UI flag on, the contextual onboarding dialogs rendered behind the browser chrome instead of below it.

Floating UI lets page content run underneath the translucent address bar and toolbar, using a mechanism only the web view understands. The onboarding dialogs sit alongside the web view rather than inside it, so nothing pushed them clear of the chrome — their titles ended up hidden behind the status bar and the address bar. The new tab page's end-of-journey dialog had the same problem against the focused input card.

Both dialogs are now offset below whatever chrome is floating above them, and the web view no longer double-counts that space. The offset follows the chrome as it hides, resizes, and rotates. Nothing changes when the flag is off.

### Testing Steps

Needs an iPhone (or simulator) on iOS 26 or later — floating UI is unavailable elsewhere.

1. Settings → Debug → All debug options → turn on **Internal User**, then filter for `floating` and enable **floatingUIAugust2026**
2. On the same Debug screen: **Onboarding** → **Reset All Onboarding**, then kill and relaunch the app
3. Settings → Appearance → Address Bar Position → **Top**
4. Go through the onboarding intro until the new tab page shows the "try a search" dialog → dialog is fully visible below the address bar
5. Run the suggested search, then open one of the suggested sites → the trackers dialog appears above the page, fully below the address bar (before this change its title was hidden behind the bar)
6. Scroll the page down until the address bar hides → dialog holds its position, page content scrolls beneath it
7. Rotate to landscape and back → dialog stays clear of the bar in both orientations
8. Continue through the fire button dialog to the final "You've got this!" dialog on the new tab page → title fully visible below the focused input card
9. With that dialog showing, tap **Duck.ai** then **Search** in the input card, and type into the field → the dialog tracks the card's changing height, never overlapping it
10. Repeat steps 2–8 with Address Bar Position set to **Bottom** → dialogs clear the status bar; nothing sits behind the toolbar
11. Turn **floatingUIAugust2026** back off, relaunch, and repeat steps 2–8 → identical to `main`

### Impact

Low — a layout fix confined to a feature flag that is internal-only today.

#### What could go wrong?

Two changes sit outside the flag gate, so they need the step 11 pass:

- A dialog dismissed while another was being presented could clear the wrong reference, orphaning the visible dialog → now guarded by an identity check; this was already possible on `main`.
- A tab built its own floating-UI check instead of reusing the one it already had, which could disagree with the rest of its layout → now shares a single instance; the two can only differ under injected test doubles.

### Quality Considerations

- Covered by unit tests on the two new layout decisions, including the flag-off case, the landscape height cap, and the hidden-chrome pose.
- While a dialog is up, the space behind the top chrome shows the page background rather than scrolling content. Intentional — the alternative resizes the web view on every frame of the bar animation.
- No privacy, data, or performance impact. The extra work is a constraint update, and only while a dialog is on screen.

---
###### Internal references:
[Definition of Done](https://app.asana.com/0/1202500774821704/1207634633537039/f) | [Engineering Expectations](https://app.asana.com/0/59792373528535/199064865822552) | [Tech Design Template](https://app.asana.com/0/59792373528535/184709971311943)
