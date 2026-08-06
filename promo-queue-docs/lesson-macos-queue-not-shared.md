# macOS promo queue is app-target code, not a shared package

Despite the Asana framing ("mobile can adapt the proven pattern") suggesting a reusable framework, the entire macOS promo queue lives in `macOS/DuckDuckGo/Promotions/` — the macOS app target. Nothing under `SharedPackages/` and nothing importable from iOS (confirmed by repo-wide search for `PromoService`/`import Promotions` under `iOS/`).

Some policy types use largely portable Combine/Foundation abstractions, but extraction is not mechanical integration. `PromoTrigger` builds publishers from AppKit lifecycle notifications; the factory, flags, delegates, and lifecycle wiring are macOS-specific; and moving the core still requires a shared module boundary, access-control changes, macOS migration, and regression testing.

The larger cost is the missing iOS adapter contract. An internal promo needs synchronous/current eligibility, an async `show()` result, active visibility, and idempotent `hide()`. The iOS modal manager exposes none of those, provider eligibility can have side effects, and provider-specific shown state cannot be generically rolled back. One wrapper around the manager is therefore insufficient; registering each provider separately would require six adapters plus changes to eligibility, dismissal/outcome plumbing, and priority/cooldown ownership.

The behavior also differs. macOS external RMF can retract a visible internal promo, while iOS iteration 1 should keep a committed modal until normal dismissal. `PromoResult.noChange` only adjusts `PromoService` history and does not undo iOS provider state. Two external promos may coexist, and removing an external blocker does not itself retry a skipped internal promo. macOS cooldown is based on qualifying dismissal history; iOS records the last modal presentation, despite both using a 24-hour default.

Why it mattered: `PromoService` remains a credible iteration-3 option if a shared client-side or hybrid queue is selected, but extraction is not justified by the iteration-1 overlap alone. Reuse its principles—observed state, explicit commitment, and no consumption while blocked—without moving the service now.
