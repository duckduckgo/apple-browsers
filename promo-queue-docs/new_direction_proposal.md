The problem we're solving
On the New Tab Page, a launch modal and an RMF card can end up on screen at the same time. We want to make sure only one shows. That's it. Everything below is about doing that with as little machinery as possible.
Why the current approach is heavy
The current design works and is tested, but it's big: around 3,600 lines, with one ~980-line coordination service. Most of that isn't spent on "modal vs card." It's spent answering a harder question the design took on: which of the three NTP surfaces is showing the card right now, and how do we hand the card between them.

iOS renders the RMF card from three separate NewTabPageViewController instances (the normal NTP, the suggestion-tray favorites, and the address-bar favorites). To keep exactly one physical card and coordinate it, the current code needs:
a "surface exposure" contract that every host and every overlay has to report into (setPromoSurfaceActive/Renderable/Visible/Covered, ~34 call sites),
renderer selection ("authorize one of the three"),
a handoff/drain state machine to move the card between surfaces,
a logical-session object with session/presentation/removal IDs,

There's also an honest comment in the code that sums up the risk: "Any future host that covers an attached NTP must use this handoff; arbitrary overlays are not detected automatically." In other words, a new screen that covers the NTP and forgets to report in will break coordination silently.
The idea in one sentence
One slot. Either a modal or an RMF holds it. To show anything, you ask the slot. The RMF card is the tricky part: the same card can be drawn by several NTP surfaces, but we don't track which one, we only care that a card is holding the slot.
The design, built up in layers
1. One slot. There's a single slot. It's free, held by a modal, or held by an RMF card. Only the holder can be on screen. That single rule is the whole guarantee.
2. Ask before you show. Before a modal presents, or before a card renders, it asks the slot. The slot says yes only if:
the other kind isn't holding it, and
the cooldown has passed, and
onboarding is done.
If yes, you take the slot. If no, you don't show. The gate checks all three things, so callers don't juggle three separate rules.
3. Give it back when it's done. There are two ways to decide when the slot frees:
(a) Release when the card leaves the screen (more precise). 
A modal releases when it's dismissed. A card releases when it's no longer showing, for either reason: it left the screen (you navigated away, switched tabs, backgrounded) or the message went away (dismissed, expired, replaced).
The model already knows both it listens to remoteMessagesDidChange for the message side and gets viewDidDisappear for the screen side.
Whichever comes first frees the slot.
Upside: the moment you leave the NTP, the slot is free, so a modal is never held up by a card you're not even looking at.
(b) Release when the message goes away (simplest, and what Android does). 
The slot is held while the message is active, and freed when it's dismissed, expired, or replaced.
We don't watch the screen at all. The tradeoff: if you leave the NTP while a message is still active, the slot stays held until that message is gone, which can briefly defer a modal.
Android ships exactly this, and in practice it's fine, modals are only checked at foreground, and we free the slot on background anyway, so a stale hold doesn't usually reach a modal.
I'd lean toward B for simplicity, and treat A as a one-line upgrade if we ever find a modal that needs the extra precision. The model already has both signals, so moving from B to A is small.
4. The three surfaces handle themselves. Either way, the slot is keyed by the message id: if a surface asks for a card whose id already holds the slot, it just joins, same card, another surface. The difference is only in how we let go:
In option (a), we keep a small retain count, so the slot stays held while any surface shows the card and frees when the last one goes. The base NTP → favorites handoff and multiple tabs need no special logic, and the count never hits zero mid-handoff, so a modal can't slip in.
In option (b), there's nothing to count, the slot is held while the message is active, so every surface just shows it and the slot frees when the message goes.
The interfaces
enum Promo { case modal, rmf }

// The one thing callers talk to.
protocol PromoGate {
    /// Ask to show a promo. Returns a lease only if the slot is free of the
    /// other kind, the cooldown has passed, and onboarding is done — OR the
    /// same id already holds it (join). nil = don't show.
    func tryAcquire(_ promo: Promo, id: String) -> PromoLease?
}

// What you hold while your promo is on screen.
final class PromoLease {
    /// Call from the card's onAppear. Returns true the FIRST time for this id
    /// (record the impression + start the cooldown once); later surfaces get false.
    @discardableResult func markShown() -> Bool

    /// Call when the promo is done. Frees the slot when the last holder of this id releases.
    func release()
}

How the model uses it (the view stays dumb — it only forwards onAppear):// when the NTP decides to show a card (before it's on screen -> no flash)
if let lease = gate.tryAcquire(.rmf, id: message.id) {
    self.lease = lease
    // publish the card into the view
}

// card's onAppear -> model.cardDidAppear()
if lease?.markShown() == true {
    config.didAppear(message)   // record impression once
}

// released on the trigger chosen in step 3 (message gone, and/or surface gone)
lease?.release(); lease = nil
Under the hood, the lease just holds closures the gate handed it. The gate holds them weakly, so a surface torn down without a clean release is reclaimed automatically. That weak-token safety net already exists in today's arbiter.

What we delete vs. what we keep
Delete
Keep
The setPromoSurface* exposure contract (~34 sites)
The arbiter (the slot) — already small
Renderer selection ("authorize one")
The cooldown policy — already small
Handoff / drain / transfer state machine
The gate, as a thin facade over those two
Logical-session + session/presentation/removal IDs
The model, now doing tryAcquire/release
The 9-method renderer registration protocol
id-key (+ retain count in Option A) — a few lines
Real-UIKit host tests + the lifecycle-observer

The mutual-exclusion and cooldown parts, the correctness-critical bits, stay exactly as they are today. We're only changing how the RMF side decides it's on screen.
The trade: less precision for a lot less code
We give up some precision. In return we delete most of the machinery. Here's exactly what we give up, and why it doesn't hurt:
Fire tab / landscape. 
We take the slot when the NTP shows a message, before we know the layout won't actually draw the card (fire-mode empty state, or landscape with no room).
So the slot is briefly held with no visible card. It self-corrects when you leave that state, and we free it on background too.
Worth noting: Android doesn't handle this either, it claims at the same point with no visibility check.
A brief double-mount. 
During a handoff the same card can sit mounted on two overlapping surfaces for a moment.
Only the front one is visible, and it's the same card, so nothing overlaps a modal.
This is already true today without coordination, the three surfaces already render independently. We're not introducing it.
A small over-hold, only under Option B. 
The slot can stay held while a message is active but you're off the NTP.
Android lives with this; we free the slot on background so it rarely reaches a modal. Option A removes it entirely for one extra signal.

The theme: the coverage tracking buys precision in a handful of transient states. We trade that precision for a much smaller, more maintainable system, and every imprecision is short-lived and self-correcting.
Questions
What if a modal is showing when a card wants to appear? 
The card asks the gate, the slot is held by the modal, the gate says no, the card is never published. No overlap.

Won't the card flash for a frame before it's pulled? 
No. We check the gate before we put the card in the view. If it's blocked, the card is never mounted, so there's nothing to flash.

How do you coordinate three NTP surfaces without tracking them?
We don't track them. Same id → join. Whoever is showing the card is irrelevant; only "is any card holding the slot" matters. (In Option A a retain count answers that; in Option B the message's own lifecycle does.)

Tab switch — could the slot briefly open and let a modal in? 
Modals only evaluate at foreground, not on a tab switch, so nothing tries to grab the slot mid-switch. In Option A, UIKit also fires the new viewDidAppear before the old viewDidDisappear, so the count stays above zero, and re-showing the same id skips the cooldown.

Message replaced or expires while it's showing? 
The store already tells us via remoteMessagesDidChange. Same id → the card stays. Different id → old releases, new asks fresh. Expired → card released. No special logic; it's the same signals we already use.

Why not gate at the store when we fetch the message? 
That's exactly Option B, and it's what Android does. The only cost is the small over-hold (the store knows a message exists, not whether it's on screen). Option A adds the on-screen signal to remove that. Neither is wrong — it's the precision knob.

Does this match Android? 
Yes. one slot, ask to show, release when done, cooldown for spacing. Option B is Android's model. Option A is one step more precise on release (release when the card leaves the screen, not just when the message goes away).