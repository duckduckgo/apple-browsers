# iOS Promo Queue Maestro coverage

These flows drive the Alpha app entirely through shipping UI plus existing
internal debug screens. They intentionally do not pass `isRunningUITests`:
`NewAddressBarPickerDisplayValidator` rejects UI-test and WebDriver sessions,
which would invalidate the modal-exclusion checkpoint.

## Pinned fixtures

The checked-in files under `fixtures/` are byte-for-byte copies of:

- `remote-messaging-config-metrics.json` from commit
  `2cedeeb5add3fd62ee4a438ce775fded8442d149`, SHA-256
  `c9f594ca2446f29455b107580b7438428365fb149ccf110c207404f5b60b7451`.
- `remote-messaging-config-cards-list-items.json` from commit
  `6b117715492a8ca0bdb3135eb65965fa3e0b6f22`, SHA-256
  `5755daedac5b7c6062fd2c4b0e22cf70759c676926ca97474eb988c9696e044d`.

`run_with_fixtures.sh` verifies both pinned checksums, serves the files from
loopback, validates both HTTP responses as JSON, prints the URLs, traps
success/failure/interruptions, and waits for the server process so it cannot be
orphaned. Each artifact directory includes `run.log` with the exact command,
elapsed time, and exit status.

## Isolation and invocation

The team entry point needs no simulator identifier or preinstalled app:

```sh
./.maestro/promo_queue/test.sh
```

It verifies the required CLIs, chooses a supported four-iPhone runtime, replaces
four Maestro-named simulators with fresh devices, builds and launches the Alpha
Debug app through XcodeBuildMCP, installs that exact app on the other three, and
runs one flow per device. It prefers the certified iOS 18.6 device set. If that
runtime is unavailable, it selects a supported newer four-device set and prints
a warning. `PROMO_QUEUE_DEVICE_OS` can optionally pin another installed runtime.

The Simulator frontend remains open and the four devices are retained for
post-run inspection. A later invocation recreates the same Maestro-named
devices, so runs start clean without accumulating more simulators. Setup logs,
XcodeBuildMCP results, screenshots, fixture logs, and Maestro output are saved
under `artifacts/team-<UTC timestamp>/`.

The script propagates Maestro's exit status and never suppresses a failed flow.
Feature-off legacy parity intentionally expects `shown | scheduled` immediately
after the fixture is mapped, even while Settings covers the message. This is
the eager accounting behavior on `main`; coordinated mode separately verifies
that appearance is recorded only after a genuinely visible presentation.

An iPhone 16 Plus / iOS 18.6 experiment on 2026-08-17 seeded a genuinely visible,
appearance-confirmed coordinated RMF and then launched with Maestro
`clearState: true` and `clearKeychain: false`. The reset restored onboarding,
removed the local coordination override (`Mode: Legacy`), cleared the confirmed
RMF timestamp (`Last RMF Appearance: Never`), and left no owner or cooldown
boundaries. The Internal User reset domain was not proven: the experimental
label selector did not toggle the Alpha-default ON switch before the reset.

That probe did not cover every shared app-group, modal-provider, address-picker,
or Remote Messaging persistence domain. Keep the conservative fresh-simulator
isolation requirement for each scenario rather than relying on `clearState`,
Remote Messaging `Delete All`, or cooldown resets.

For focused development, run one flow against an already dedicated simulator:

```sh
PROMO_QUEUE_DEVICE_ID=<dedicated-uuid> \
  .maestro/promo_queue/run_with_fixtures.sh \
  .maestro/promo_queue/01_feature_off_legacy_parity.yaml
```

The low-level equivalent for an already prepared four-device set is:

```sh
PROMO_QUEUE_DEVICE_ID=<uuid-1>,<uuid-2>,<uuid-3>,<uuid-4> \
  .maestro/promo_queue/run_with_fixtures.sh \
  --shard-split=4 \
  .maestro/promo_queue
```

Do not run the active directory serially on one simulator: each scenario needs
the broader reset boundary supplied by a freshly erased dedicated simulator.

The simulator currently exposes the unified address input only. Scenario 1
therefore activates a generated local URL suggestion from that surface; there
is no separate alternate suggestion host UI on this configuration.

The control path for the cached-NTP regression is
`../shared/promo_queue/control_apply_ntp_fixture.yaml`. It performs the same
delete/override/fetch sequence from a normal webpage without first focusing the
unified address input.
