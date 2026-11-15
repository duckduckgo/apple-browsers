The repository to change is checked out at {{REPO_DIR}}. Make all changes there. Follow the plan below. Do not copy the plan, task details or links into code, comments or files. You run unattended and nobody can answer questions. If the plan is ambiguous, make the smallest change consistent with it and finish. Besides the file tools, you can run these commands from the repository root, and no others:
- `xc build`: builds the app your change touches for testing (`xc build ios` or `xc build macos` to choose). It takes several minutes, and prints the errors when it fails.
- `xc test [tests]`: runs tests in xcodebuild -only-testing form, or the ones in .agent-evidence/tests.txt when you name none. Build first after changing code.
- `xc lint`: SwiftLint --strict on the Swift files you changed.
- `xc mv <from> <to>` and `xc rm <path>...`: move, rename or delete files in the repository.
- `xc build` and `xc test` print the path of their full log. Use the Grep and Read tools on it when the printed errors aren't enough.
- Read-only git: `git log`, `git show`, `git blame`, `git diff`, `git status` and `git grep`, for the history of the code you're changing.

Before you finish, build your change and run the tests in tests.txt, fix what fails and repeat until the build and the tests pass, then run `xc lint` and fix what it reports. Don't delete, skip or weaken existing tests to make them pass. Builds are slow, so read the code carefully before building rather than building to find out. After you finish, the worker builds your change again on a clean machine, runs the tests in tests.txt and records the app, and the approver sees those results.

Write an evidence plan in .agent-evidence/ at the repository root, so the approver can see the fix work:
- tests.txt: up to 5 tests that cover the change, one per line in xcodebuild -only-testing form. List a whole class (UnitTests/SwipeTabsCoordinatorTests) only for test classes you wrote or changed. For existing classes, list just the methods that exercise the code you changed (UnitTests/TabPreviewsSourceTests/testWhenUpdateFullScreenSnapshotThenItCanBeRetrieved), since other tests in those classes can be slow or flaky and the PR checks run the full suite. Add a focused unit test for the fix when you can.
- excluded.txt, only when needed: when a test in tests.txt that you didn't add keeps failing, your change doesn't touch the code it tests, and the failure looks unrelated (for example a timeout), take it out of tests.txt and add a line here in the form `UnitTests/Class/testMethod: why it's unrelated`. The approver sees these. If your change mentions the test's class, the worker puts the test back.
- flow.yaml, for iOS changes with a visible effect: a short Maestro flow that opens the app, goes to the screen the change affects and shows it working. Use only these commands: launchApp, stopApp, killApp, clearState, tapOn, doubleTapOn, longPressOn, inputText, eraseText, pressKey, back, hideKeyboard, scroll, scrollUntilVisible, swipe, assertVisible, assertNotVisible, waitForAnimationToEnd, extendedWaitUntil, takeScreenshot, startRecording, stopRecording, setOrientation, copyTextFrom, pasteText. Read .maestro/AGENTS.md first. You can't run the flow before it's used, so keep it short and only use selectors you can see in the code: prefer accessibility ids, then the app's own English strings. Don't tap or assert on text inside web pages, which changes and can be translated; use web pages only as a backdrop for the app UI. Wait for elements with extendedWaitUntil before acting on them. Launch with the arguments below so the app skips onboarding. For example:

  ```yaml
  appId: com.duckduckgo.mobile.ios
  ---
  - launchApp:
      arguments:
        isOnboardingCompleted: "true"
        isRunningUITests: "true"
  - startRecording: demo
  - tapOn: "Settings"
  - takeScreenshot: settings
  - stopRecording
  ```

Your final message is the summary teammates read before approving, on one page with the build, test and recording results. Tell the story briefly, as short paragraphs in this order:
- **Problem.** What the crash data in the plan shows, in 2 or 3 sentences: the crash type and where it happens, how often (events, users, app versions), and what the user was doing when it happened.
- **Cause.** Why it crashes, and how sure the plan is.
- **Fix.** What you changed. Name any plan step you skipped and why.
- **Why it's safe.**
- **Risk and follow-up.** Say plainly whether the change fixes the root cause or only makes the crash less likely.

Don't open with which plan steps you did. Don't describe your build and test runs, since the worker's results are on the same page.

When you're done, write .agent-pr.md at the repository root for the pull request, which is public: the first line is the title, starting with 'iOS: ' or 'macOS: ' and saying what the change does, then a blank line and 2 to 4 bullets on what changed and why. Describe only the code. No links, crash counts, versions, user data, or anything from Asana or Sentry.

{{PLAN}}
