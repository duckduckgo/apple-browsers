The repository to change is checked out at {{REPO_DIR}}. Make all changes there. Follow the plan below. Do not copy the plan, task details or links into code, comments or files. You run unattended and nobody can answer questions. If the plan is ambiguous, make the smallest change consistent with it and finish. Besides the file tools, you can run these commands from the repository root, and no others:
- `xc build`: builds the app your change touches for testing (`xc build ios` or `xc build macos` to choose). It takes several minutes, and prints the errors when it fails.
- `xc test <tests>`: runs the named tests, in xcodebuild -only-testing form with the target name as the test plan spells it (iOS `UnitTests`, macOS `Unit Tests`). Name a whole class (UnitTests/SwipeTabsCoordinatorTests) only for test classes you wrote or changed, and otherwise just the methods that exercise the code you changed (UnitTests/TabPreviewsSourceTests/testWhenUpdateFullScreenSnapshotThenItCanBeRetrieved), since other tests in those classes can be slow or flaky and the PR checks run the full suite. Build first after changing code.
- `xc lint`: SwiftLint --strict on the Swift files you changed.
- `xc mv <from> <to>` and `xc rm <path>...`: move, rename or delete files in the repository.
- `xc build` and `xc test` print the path of their full log. Use the Grep and Read tools on it when the printed errors aren't enough.
- Read-only git: `git log`, `git show`, `git blame`, `git diff`, `git status` and `git grep`, for the history of the code you're changing.

Add or update unit tests that cover your change, and add a focused regression test for the fix when you can. Before you finish, build your change and run those tests with `xc test`, fix what fails and repeat until the build and the tests pass, then run `xc lint` and fix what it reports. Don't delete, skip or weaken existing tests to make them pass. Builds are slow, so read the code carefully before building rather than building to find out. Build and test again after your last change.

For an iOS change with a visible effect, prove it in the app with verify-ios and keep the proof in your decision log.

Your final message is the summary teammates read alongside the PR, on one page with the build and test results. Tell the story briefly, as short paragraphs in this order:
- **Problem.** What the crash data in the plan shows, in 2 or 3 sentences: the crash type and where it happens, how often (events, users, app versions), and what the user was doing when it happened.
- **Cause.** Why it crashes, and how sure the plan is.
- **Fix.** What you changed. Name any plan step you skipped and why.
- **Why it's safe.**
- **Risk and follow-up.** Say plainly whether the change fixes the root cause or only makes the crash less likely.

Don't open with which plan steps you did. Don't describe your build and test runs, since the worker adds their results to the same page.

{{PR}}

{{PLAN}}
