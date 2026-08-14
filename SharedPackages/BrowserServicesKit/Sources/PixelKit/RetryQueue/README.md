# PixelKit retry queue

A pixel that fails to send is normally lost. The retry queue lets a pixel opt into being persisted on
failure and replayed later, so a send that failed because the device was offline still arrives.

It is **opt-in per pixel and off by default**. A pixel that does not opt in behaves exactly as if the
queue were not there: it is sent once, and a failure is dropped.

## Opting in

```swift
pixelKit.fire(MyPixel.somethingImportant, options: .withRetry)

// or, composed with other options, since `Options` is a value type
var options = PixelKit.Options.parameters(["source": "menu"])
options.retryOnFailure = true
pixelKit.fire(MyPixel.somethingImportant, options: options)
```

## What a replay sends

A replayed pixel carries the original request unchanged — same name, headers, parameters and
`allowedQueryReservedCharacters` — plus two extra parameters:

| Parameter | Value |
|---|---|
| `originalPixelTimestamp` | ISO 8601 (`.withInternetDateTime`) timestamp of the send that failed |
| `retriedPixel` | `"1"` |

They let the backend tell a replay from an organic send and de-duplicate it against the original
attempt. The same two names are used by the iOS `PersistentPixel` system, so both produce identical
data. Neither parameter is attached to the original (organic) send, only to a replay.

**These parameters are why the opt-in exists.** `originalPixelTimestamp` reintroduces exactly the
time-based correlation that PETAL removes, so a pixel must be privacy triaged for both parameters
before it sets `retryOnFailure`. They also have to be declared in the pixel's definition, or live
validation will reject the replay as having additional properties. An earlier version of this queue
retried every PixelKit pixel and attached both parameters globally, which is what
[this report](https://app.asana.com/1/137249556945/task/1215895717530162) caught.

## Mechanics

- **Persistence.** A failed opted-in send is written to `pixelkit-retry-queue-<session>.json` in
  Application Support. `<session>` is the `session` string passed to `PixelKit.setUp`, so the browser,
  the VPN agent and the packet tunnel each keep their own queue even when they share a `UserDefaults`
  suite.
- **Draining.** *Any* successful send triggers a drain, whether or not that pixel opted in. Gating the
  drain on the opt-in too would mean a queued pixel had to wait for another opted-in pixel to succeed
  before being retried. For a launching app the first successful pixel is usually enough to flush the
  queue.
- **Throttle.** Drains happen at most once an hour (once a minute in `DEBUG`). An empty drain does not
  advance the throttle, so a failure queued right after one is still replayed promptly.
- **Expiry.** Items older than 28 days are dropped without being sent. Expired items are also pruned
  when a new failure is enqueued, so a long offline stretch cannot keep known-dead pixels queued.
- **Cap.** The store holds 100 items, oldest dropped first.
- **Replays don't re-enter the queue.** A replay goes straight to the network closure, so a failed
  replay leaves the item queued for the next drain rather than queueing a duplicate.
- **Dry run.** `PixelKit(dryRun: true)` creates no queue at all.

## Items queued before retry was opt-in

Builds that queued every failed pixel baked `originalPixelTimestamp` into the persisted parameters.
That key's presence therefore identifies an item queued without its caller having opted in, and those
items are dropped rather than replayed — they were never triaged for retry. Nothing writes that key
into stored parameters any more, so the case disappears as those queues age out.

## Related

- `PixelKit.Options.retryOnFailure` — the caller-facing switch.
- `iOS/Core/PersistentPixel.swift` — the older, iOS-only system this is a port of. It is deprecated;
  new pixels should use PixelKit.
