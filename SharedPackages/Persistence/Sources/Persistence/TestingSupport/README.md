#  Testing support

In-memory `KeyValueStoring` implementations for tests. They live in the `Persistence` target rather
than in a separate testing-utilities target on purpose, and they are hidden behind `@_spi(Testing)`
so production code cannot reach them.

## Why they are not a separate target

A `PersistenceTestingUtils` target inside this package could only depend on the `Persistence`
*target*, and Xcode links target-to-target package dependencies statically into every client. When
Xcode also builds the `Persistence` *product* as a dynamic framework — which it does as soon as more
than one image needs it — an app-hosted test bundle ends up with a second static copy of
Persistence. Two copies in one process break type metadata lookups: boxing the result of
`keyedStoring()` into an `any KeyedStoring<Keys>` faults on a null metadata pointer, which crashed
the iOS test host on every test in `OnboardingIntroViewModelTests` and
`DarkReaderFeatureSettingsTests`. Xcode 26.6 does not dedupe this case; swift-build commit
`8698d7a7` fixes it upstream.

Keeping these files inside the `Persistence` target removes the extra module entirely, so there is
only ever one copy of Persistence in the process.

## How to use them

Import with the SPI group:

```swift
@_spi(Testing) import Persistence
```

A plain `import Persistence` does not see these declarations, which is what keeps them out of
production code. When a helper of your own exposes one of these types in its signature, mark that
helper `@_spi(Testing)` too and let its callers opt in the same way. XCTest-dependent helpers do not
belong here: this target must not link XCTest.
