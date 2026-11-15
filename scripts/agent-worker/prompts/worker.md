The repository to change is checked out at {{REPO_DIR}}. Make all changes there. Follow the plan below. Do not copy the plan, task details or links into code, comments or files. You run unattended and nobody can answer questions. If the plan is ambiguous, make the smallest change consistent with it and finish. You only have file tools. After you finish, the worker builds your change, runs the tests you name and records the app, so don't plan to do any of that yourself.

Write an evidence plan in .agent-evidence/ at the repository root, so the approver can see the fix work:
- tests.txt: up to 5 tests that cover the change, one per line in xcodebuild -only-testing form. List a whole class (UnitTests/SwipeTabsCoordinatorTests) only for test classes you wrote or changed. For existing classes, list just the methods that exercise the code you changed (UnitTests/TabPreviewsSourceTests/testWhenUpdateFullScreenSnapshotThenItCanBeRetrieved), since other tests in those classes can be slow or flaky and the PR checks run the full suite. Add a focused unit test for the fix when you can.
- flow.yaml, for iOS changes with a visible effect: a short Maestro flow that opens the app, goes to the screen the change affects and shows it working. Use only these commands: launchApp, stopApp, killApp, clearState, tapOn, doubleTapOn, longPressOn, inputText, eraseText, pressKey, back, hideKeyboard, scroll, scrollUntilVisible, swipe, assertVisible, assertNotVisible, waitForAnimationToEnd, extendedWaitUntil, takeScreenshot, startRecording, stopRecording, setOrientation, copyTextFrom, pasteText. Select elements by visible text or accessibility id from the code, and read .maestro/AGENTS.md first. Launch with the arguments below so the app skips onboarding. For example:

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

  TEMP: always write flow.yaml, even when the fix has nothing to see. Then open the app, go to the screen nearest the code you changed and record it.

Your final message goes to the approver on one page with the build, test and recording results. Explain the cause, the fix, why it's safe, and any risk or follow-up. Don't mention building, testing or recording, since those results are on the same page.

When you're done, write .agent-pr.md at the repository root for the pull request, which is public: the first line is the title, starting with 'iOS: ' or 'macOS: ' and saying what the change does, then a blank line and 2 to 4 bullets on what changed and why. Describe only the code. No links, crash counts, versions, user data, or anything from Asana or Sentry.

{{FIX}}

{{PLAN}}
