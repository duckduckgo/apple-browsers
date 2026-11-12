# Investigate Application Lock UI test failures

Use the temporary experiment branch for manual runs. These controls do not establish a cause or fix the known failures.

1. Dispatch the baseline below, then wait for completion. Runs on the same branch cancel earlier in-progress runs.
2. Repeat with `app_lock_relaunch_gap=2`, keeping the other inputs identical.
3. Compare `app_lock_disable_animations=true` separately, with the gap back at `0`. This uses the existing UIKit animation override from the first app launch. It does not disable system, web, or all SwiftUI animations.
4. Compare `simulator_log_level=info` separately. To compare `job_cap=1`, select multiple eligible classes, devices, or modes so there is more than one matrix job. The single-class, iPhone, production baseline below already has one job. Job caps limit separate CI workers, not simulators sharing one host.

Run from a checkout authenticated to the repository, after creating the temporary PR:

```sh
gh workflow run ios_ui_tests.yml --ref codex/pr4-ui-experiments-20261112 \
  -f single_test_class=ApplicationLockUITests -f devices=iphone -f user_modes=production \
  -f execution_mode=repeat-all -f iterations=10 \
  -f app_lock_relaunch_gap=0 -f app_lock_disable_animations=false \
  -f simulator_log_level=debug -f job_cap=default
```

`repeat-all` requests fixed repetitions without automatic failure retry. `retry` retains the existing retry-on-failure behavior. `iterations` accepts 1 through 20 in either mode. Every repetition relaunches the test runner. Each Application Lock flow also exercises app termination and relaunch. Compare automatic authentication, foreground recovery, Settings navigation, and the complete flow separately.

The defaults remain `retry`, two maximum attempts, zero relaunch gap, normal UIKit animations, General debug logging, and eight production workers or four internal workers. The internal cap never exceeds four. Gap options are 0, 1, 2, and 5 seconds. The gap applies to both state-preserving relaunches in ApplicationLockUITests, including the final disabled-lock check; other test classes use zero delay.

Download the class/device/mode log artifact and inspect:

- `experiment-options.json` for the requested configuration and effective worker cap for the selected mode.
- `TestResults.xcresult` for native repetition counts, failures, phase activities, and kept phase/configuration attachments. Phase attachments include wall time and monotonic uptime; terminate, gap, and launch activities have XCTest timestamps.
- `ui-tests.log` for the full run and existing opt-in app authentication diagnostics. The diagnostics include LocalAuthentication error descriptions and underlying errors.
- `test-attachments` for videos exported on manual runs when XCTest retained them. A timeout can prevent recording or result finalization; export is best effort.

Record executed, passed, failed, and skipped counts per native attempt. Record the automatic-prompt or recovery route and the last completed phase. A successful unlock followed by a Settings timeout is a failed complete flow. The combined report still groups retry histories and can collapse measured repetitions; use native results to count them. An initial failure recovered by retry is not a first-attempt pass.

The existing 45-minute worker timeout and per-test time limits still apply. A request for 20 repetitions can end before all repetitions execute. Record the observed count, Xcode/runtime, device, mode, revision, and configuration with each comparison. Local smoke passes validate the controls; evaluate stability with repeated CI runs before copying selected changes back.
