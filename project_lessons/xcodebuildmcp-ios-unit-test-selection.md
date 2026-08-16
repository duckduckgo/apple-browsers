# Use the iOS Unit Tests scheme and UnitTests bundle prefix for focused iOS tests

## Lesson
With XcodeBuildMCP in this repository, run focused app unit tests using the `iOS Unit Tests` scheme and `-only-testing:UnitTests/<SuiteName>`. The default `ios` profile uses `iOS Browser Alpha`, which builds the app but has no test bundle, and the source directory name `DuckDuckGoTests` is not the test bundle name.

## Why it matters
Using the app scheme or the `DuckDuckGoTests/` prefix can compile successfully but fail before execution with either “There are no test bundles available to test” or a test-plan membership error.

## Evidence
The Phase 0 focused run executed 45 tests successfully after selecting `iOS Unit Tests` and changing the selection prefix to `UnitTests/`.
