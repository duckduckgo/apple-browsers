# Prepare local assisted PIR testing

Use this setup with the DEBUG browser and its PIR Agent stopped. Requires Python
3.12 or later and `gh` authenticated to the internal GitHub host.

1. Set `PRIVACY_CONFIG_URL` to the test macOS privacy-configuration URL.
2. Prepare the dashboard and DEBUG preferences:

   ```sh
   scripts/prepare-pir-assisted-testing.py prepare "$PRIVACY_CONFIG_URL" \
     --refresh-bundled-brokers
   ```

3. Keep the dashboard server running in a terminal:

   ```sh
   scripts/prepare-pir-assisted-testing.py serve
   ```

4. Build the DEBUG browser with FlowDeck and launch the deployed app with the
   same privacy-configuration URL:

   ```sh
   flowdeck build
   /Applications/DEBUG/DuckDuckGo.app/Contents/MacOS/DuckDuckGo \
     -privacyConfigURL "$PRIVACY_CONFIG_URL"
   ```

The script downloads and verifies the pinned FE CI export, then serves `/dbp` at
`http://127.0.0.1:8765`. Pass the same `--cache-dir` and `--port` to both commands
to change those defaults. Each preparation saves the previous values of only the
preference keys it changes. Restore them with the app and Agent stopped:

```sh
scripts/prepare-pir-assisted-testing.py restore <printed-preference-backup.plist>
```

The DEBUG shared setting `dbp.debug.testBrokerURLs` restricts regular scans,
opt-outs, email-confirmation jobs, and assisted candidates to `beenverified.com`.
It takes effect when queues are created. Synthetic debug runners are outside this
setup. Other brokers remain stored, and signed catalog updates continue normally.

The bundled BeenVerified definition is version `0.12.0`. Its normal version upsert
preserves broker identity and history, resets opt-out attempt counts, and can
advance retry dates when that experiment is enabled. Remote version `0.11` cannot
replace it. `--refresh-bundled-brokers` clears the saved local broker-version check
and broker-refresh timestamp so the normal update pipeline runs immediately. It
does not clear the profile, broker records, or job history.
