The repository to change is checked out at {{REPO_DIR}}. Make all changes there. Follow the plan below. Do not copy the plan, task details or links into code, comments or files. You run unattended and nobody can answer questions. If the plan is ambiguous, make the smallest change consistent with it and finish. Besides the file tools, you can run these commands from the repository root, and no others:
- `xc build`: builds the app your change touches for testing (`xc build ios` or `xc build macos` to choose). It takes several minutes, and prints the errors when it fails.
- `xc test [tests]`: runs tests in xcodebuild -only-testing form, or the ones in .agent-evidence/tests.txt when you name none. Build first after changing code.
- `xc lint`: SwiftLint --strict on the Swift files you changed.
- `xc mv <from> <to>` and `xc rm <path>...`: move, rename or delete files in the repository.
- `xc build` and `xc test` print the path of their full log. Use the Grep and Read tools on it when the printed errors aren't enough.
- Read-only git: `git log`, `git show`, `git blame`, `git diff`, `git status` and `git grep`, for the history of the code you're changing.

Before you finish, build your change and run the tests in tests.txt, fix what fails and repeat until the build and the tests pass, then run `xc lint` and fix what it reports. Don't delete, skip or weaken existing tests to make them pass. Builds are slow, so read the code carefully before building rather than building to find out. Build and test again after your last change.

Write an evidence plan in .agent-evidence/ at the repository root, so the PR reviewer can see the fix work:
- tests.txt: up to 5 tests that cover the change, one per line in xcodebuild -only-testing form, using the target name as the test plan spells it (iOS `UnitTests`, macOS `Unit Tests`). List a whole class (UnitTests/SwipeTabsCoordinatorTests) only for test classes you wrote or changed. For existing classes, list just the methods that exercise the code you changed (UnitTests/TabPreviewsSourceTests/testWhenUpdateFullScreenSnapshotThenItCanBeRetrieved), since other tests in those classes can be slow or flaky and the PR checks run the full suite. Add a focused unit test for the fix when you can.
- excluded.txt, only when needed: when a test in tests.txt that you didn't add keeps failing, your change doesn't touch the code it tests, and the failure looks unrelated (for example a timeout), take it out of tests.txt and add a line here in the form `UnitTests/Class/testMethod: why it's unrelated`. The reviewer sees these. If your change mentions the test's class, the worker puts the test back.

Your final message is the summary teammates read alongside the PR, on one page with the build and test results. Tell the story briefly, as short paragraphs in this order:
- **Problem.** What the crash data in the plan shows, in 2 or 3 sentences: the crash type and where it happens, how often (events, users, app versions), and what the user was doing when it happened.
- **Cause.** Why it crashes, and how sure the plan is.
- **Fix.** What you changed. Name any plan step you skipped and why.
- **Why it's safe.**
- **Risk and follow-up.** Say plainly whether the change fixes the root cause or only makes the crash less likely.

Don't open with which plan steps you did. Don't describe your build and test runs, since the worker adds their results to the same page.

{{PR}}

{{PLAN}}
