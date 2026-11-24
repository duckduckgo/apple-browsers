# Gate 1: merge with the flag off

The user-assist stack must not change anything for existing users. Run each scenario on this branch and on a `main`
build, and compare the two. The `main` build comes from a worktree of `anh/shared/pir/verify-pir-extras`, which is
`main` plus ddg-check-pir and its `--broker` option.

Scheduler scenarios scan five brokers whose scans finished cleanly on this machine: searchpeoplefree.com,
freepeopledirectory.com and floridaparcels.com (matches), and spydialer.com and cyberbackgroundchecks.com (no match).
A full broker list takes over 30 minutes per seed and mostly adds broker noise. Seeds are always signed-out Freemium runs, so
the scheduler scenarios cover Freemium eligibility only; the opt-out scenarios use a token and cover the subscriber's
scan and opt-out steps.

This branch differs from `main` in two inputs besides the code:

- C-S-S is pinned to revision `ff7ceedd`, a build of C-S-S
  [#3196](https://github.com/duckduckgo/content-scope-scripts/pull/3196) that carries `userAssist` from
  [#3161](https://github.com/duckduckgo/content-scope-scripts/pull/3161). Neither is in a C-S-S release yet. `main`
  pins 21.4.0.
- The bundled BeenVerified JSON is version 0.12.0, which adds `userAssist` steps to the opt-out. `main` bundles 0.11.0.
  BeenVerified is therefore the one expected difference: iOS doesn't load it, and macOS scans it but skips its opt-out.

## Scheduled scans match main

- tags: gate1, scheduler, scan, live
- platform: iOS, macOS
- setup: `john-smith-houston`, `fresh-simulator` on iOS, `empty-store` on macOS
- action: `scheduler seed` with `--broker searchpeoplefree.com --broker freepeopledirectory.com --broker floridaparcels.com --broker spydialer.com --broker cyberbackgroundchecks.com`, once on this branch and once on the `main` build
- expect:
  - Exactly those five brokers are planned, and each gets a fresh `scanStarted` and reaches a terminal event.
  - Each broker's outcome matches the `main` run. A `transient` outcome on either build is a rerun, not a difference.

## A regular opt-out with email confirmation completes

PeopleFinders' opt-out (bundled version 0.17.1) runs expectations, form fills, clicks and an `emailConfirmation`
step. Run it on this branch's C-S-S pin, then again once the app pins a C-S-S release that includes #3161, since every
opt-out then runs on the new page scripts.

- tags: gate1, optout, live, irreversible
- platform: macOS
- setup: `john-smith-houston`, `peoplefinders.com`, `staging-token`, a matched `profileUrl` from the scan
- action: `run`, `"optOut": true`, `"emailConfirmation": true`
- expect:
  - The opt-out for the pinned record is requested, then confirmed.
  - No action times out.

## A regular opt-out on iOS is unchanged

- tags: gate1, optout, live, irreversible
- platform: iOS
- setup: `john-smith-houston`, `peoplefinders.com`, `staging-token`, `fresh-simulator`, a matched `profileUrl` from the scan
- action: `run`, `"optOut": true`, `"emailConfirmation": true`
- expect:
  - The opt-out for the pinned record is requested, then confirmed, as on `main`.
  - No action times out.
