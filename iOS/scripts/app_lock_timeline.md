# Application Lock activation timeline experiment

On a manual `ios_ui_tests.yml` run, select `ApplicationLockUITests` and enable
`collect_xcode_diagnostics`. The caller forwards `diagnostics-mode: default` to
the worker, which wraps only this class with `capture_app_lock_timeline.py`.
PR and scheduled runs retain `never` and do not start this capture.

The existing always-uploaded test-log artifact includes `app-lock-timeline/`:

- `simulator.log` contains selected-simulator `log stream --style ndjson` output,
  including the tool's initial filtering banner. It selects authentication
  processes, the app's Application Lock diagnostic markers, and authentication,
  scene, activation, or DuckDuckGo messages from SpringBoard and process managers.
  Native event records include wall timestamps, mach timestamps, process paths,
  and PIDs. `--level debug` requests available events without changing log config.
- `capture-status.jsonl` records UTC wall time, host monotonic time, selected UDID,
  capture availability/errors, limits, command exit status, and start/end service
  PID snapshots with process start times. Crash inventories contain filenames,
  modification times and sizes only; host reports are not attributed to this
  simulator merely because they appear in the inventory.
- `stream.stderr` retains stream errors, including simulator launch failures.

App request/completion markers also record wall epoch seconds, uptime, PID,
application state, authentication controller/window identity, key/hidden flags,
scene identity and scene activation state. Raw UIKit state values follow Apple's
application and scene activation state enums. This work runs only in DEBUG UI
launches with `UITEST_APP_LOCK_DIAGNOSTICS=1`.

The wrapper runs the original command and preserves its exit code. It stops only
its own stream on completion, SIGINT, or SIGTERM. Capture stops at 35 minutes or
64 MiB, checked once a second, while the test command can continue. Output may
exceed the byte threshold between checks. Forced runner termination can prevent
cleanup or artifact upload; the stream also has a native 35-minute timeout.

Filtered, dropped, private/redacted, unavailable, or missing logs do not establish
that an event did not happen. Start/end snapshots can miss a short-lived host
between snapshots. They do not provide a complete process lifecycle or establish
that every repeated PID refers to the same process. Interpret stream PID records
with paths, timestamps, snapshots, and available process-launch events.

This is an observation experiment, not a fix or an efficacy measurement. Keep the
current comparison settings and test flow unchanged when collecting evidence.
