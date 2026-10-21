#  Testing support

Mocks and expectation helpers for code that fires pixels. They live in the `PixelKit` target rather
than in a separate testing-utilities target on purpose, and they are hidden behind
`@_spi(Testing)` so production code cannot reach them.

## Why they are not a separate target

A `PixelKitTestingUtilities` target inside this package could only depend on the `PixelKit`
*target*, and Xcode links target-to-target package dependencies statically into every client. When
Xcode also builds the `PixelKit` *product* as a dynamic framework — which it does as soon as more
than one image needs it — an app-hosted test bundle ends up with a second static copy of PixelKit,
including a second `PixelKit.shared`. Tests then configure one copy while app code reads the other,
and pixels are silently dropped. Xcode 26.6 does not dedupe this case; swift-build commit
`8698d7a7` fixes it upstream.

Keeping these files inside the `PixelKit` target removes the extra module entirely, so there is only
ever one copy of PixelKit in the process.

## How to use them

Import with the SPI group:

```swift
@_spi(Testing) import PixelKit
```

A plain `import PixelKit` does not see these declarations, which is what keeps them out of
production code. When a helper of your own exposes one of these types in its signature, mark that
helper `@_spi(Testing)` too and let its callers opt in the same way — see
`SharedTestUtilities/XCTestCase+PixelKit.swift` for an example. XCTest-dependent helpers do not
belong here: this target must not link XCTest.
