# PixelKit

This package is meant to provide basic support for firing pixel across different targets.

This package was designed to not really know specific pixels.  Those can be defined
individually by each target importing this package, or through more specialized
shared packages. 

This design decision is meant to make PixelKit lean and to make it possible to use it
for future apps we may decide to make, without it having to carry over all of the business
domain logic for any single app.

## Retry on failure

A pixel that fails to send is dropped, unless it opts into the retry queue:

```swift
pixelKit.fire(MyPixel.somethingImportant, options: .withRetry)
```

Opting in persists a failed send and replays it later, with two extra parameters
(`originalPixelTimestamp` and `retriedPixel`) that the pixel must be privacy triaged for first. It is
off by default for exactly that reason. See [RetryQueue/README.md](RetryQueue/README.md).
