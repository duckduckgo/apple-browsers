---
name: ddg-debug-options
description: Use or extend the local debug options API. Use only when the user names this skill.
disable-model-invocation: true
---

# Debug options API

Use this skill only when the user explicitly asks for it.

## Use the API

1. Run **iOS Browser** in **Debug** on a simulator. The server starts automatically
   on `127.0.0.1:8475`. Other build configurations cannot start it.
2. Read `url` and `token` from `Library/Caches/DebugOptions/session.json` in the running
   app's data container. Store the token in `DEBUG_OPTIONS_TOKEN`. Do not print or commit it.
3. Discover options before choosing an ID or action. Send the token with every request:

   ```sh
   curl --fail-with-body -H "Authorization: Bearer ${DEBUG_OPTIONS_TOKEN}" \
     http://127.0.0.1:8475/api/v1/debug-options
   ```

4. Use the same action endpoint for every option. Always include `parameters`, even when empty:

   ```sh
   curl --fail-with-body -H "Authorization: Bearer ${DEBUG_OPTIONS_TOKEN}" \
     -H 'Content-Type: application/json' \
     --data '{"id":"featureFlags.sitePermissions","action":"get","parameters":{}}' \
     http://127.0.0.1:8475/api/v1/debug-options/modify
   ```

Read the current value before changing it. Follow the discovered action schema;
`set` takes `parameters.value`. Feature flag and configuration overrides require
`general.internalUser` to be set to `true` through the same endpoint.

Read back the result after a change. Follow any relaunch requirement. Configuration
actions can return HTTP 422 after saving an override; inspect the error details and
current state before retrying. A launch URL override takes precedence over a saved URL.

Filter console logs for `[DebugOptions API]` to follow requests, actions, and results.

## Add an option

- Put the read and mutation logic in a shared provider. Call it from both the debug
  menu and the API. Existing providers live in `SharedPackages/BrowserServicesKit/Sources/BrowserDebugOptions/`.
- Register a stable `DebugOptionDescriptor` ID, action schemas, availability checks,
  and handlers in `DebugOptionRegistry`. Handlers run on the main actor. Declare when
  changes take effect and whether actions are safe to retry.
- Wire the provider into `IOSDebugOptions.swift`. Keep platform services there and
  shared behavior in the packages so macOS can use it later. Keep the two API routes
  unchanged and server startup restricted to Debug builds, loopback, and bearer authentication.

See [the API guide](../../../SharedPackages/DebugServer/README.md) for details and examples.
