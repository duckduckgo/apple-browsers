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

The wrapper also attempts one asynchronous, one-second `/usr/bin/sample` when
RunningBoard reports a newly launched `com.apple.LocalAuthenticationUIService`
PID running. A separate observer tails the existing stream every 50 milliseconds;
it does not delay the test command. It excludes PIDs present in the initial
selected-simulator snapshot and consumes only one new-host event, even if
identity validation or attachment fails. It never selects a host by name across
simulators.

Before sampling, the selected simulator's `launchctl list` must identify that PID
as the exact service, and host `ps` must identify its start time and executable
path in a simulator runtime. The same checks run after sampling. Status records
retain the source event timestamp, detection time, sample start/end times,
before/after identities, exit codes and errors. `host-sample.txt` contains the
sample, with tool output in `host-sample.stdout` and `host-sample.stderr`.
Identity commands have one-second timeouts. Sampling has a three-second process
limit, then terminates only its owned sample process, with a one-second grace
before killing it. Capture completion or cancellation interrupts sampling and
joins the observer before closing the shared status file.

Sampling can perturb scheduling. Event delivery and identity checks can make the
sample late, and PID reuse between a check and attachment remains possible.
Use actual timestamps to assess overlap with the unresolved startup interval;
a late sample, failed attachment, changed lifetime or missing matched sampled
control is inconclusive. A host's first log does not establish when its
initialization began. The sample is diagnostic evidence, not a cause or fix.
