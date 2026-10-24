//
//  WebPushDebugHelper.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import AppKit
import Foundation
import OSLog
import WebKit

private let log = Logger(subsystem: "com.duckduckgo.macos.browser", category: "WebPush")

/// Debug helper for the Web Push PoC. Writes a folder of test artefacts to
/// `~/Desktop/ddg-web-push-testing/` (HTML, SW JS, Python HTTP server, README)
/// and provides a one-shot "fire a synthetic push" action that bypasses
/// WebKit's webpushd / APNs entirely.
///
/// Mirrors the pattern used by `SparkleDebugHelper`.
@available(macOS 13.0, *)
enum WebPushDebugHelper {

    private static let testOrigin = URL(string: "http://localhost:8765/")!
    private static let folderName = "ddg-web-push-testing"

    // MARK: - Public actions

    /// Writes the test environment to `~/Desktop/ddg-web-push-testing/` and
    /// opens the generated README.
    static func setupWebPushTestingEnvironment() {
        let fileManager = FileManager.default
        let folder = fileManager
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
            .appendingPathComponent(folderName)

        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

            let files: [(String, String)] = [
                ("index.html", Resources.indexHTML),
                ("sw.js", Resources.serviceWorkerJS),
                ("serve_push.py", Resources.serverScript),
                ("README.md", Resources.readme)
            ]
            for (name, contents) in files {
                try contents.write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
            }

            // Allow `./serve_push.py` to be executed directly.
            try? fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: 0o755)],
                ofItemAtPath: folder.appendingPathComponent("serve_push.py").path
            )

            NSWorkspace.shared.open(folder.appendingPathComponent("README.md"))
        } catch {
            log.error("WebPushDebugHelper setup failed: \(error.localizedDescription, privacy: .public)")
            let alert = NSAlert()
            alert.messageText = "Failed to set up Web Push testing environment"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    /// Fires a synthetic push at the active tab's origin. Used to verify the
    /// receive path on real sites (Slack, GitHub, etc.) that subscribed via
    /// the JS shim. Grants notification permission to that origin so WebKit's
    /// gate in `NetworkProcessProxy::processPushMessage` accepts the dispatch.
    @MainActor
    static func fireTestPushAtActiveTabOrigin() {
        guard let url = Application.appDelegate.windowControllersManager.lastKeyMainWindowController?
                .mainViewController.tabCollectionViewModel.selectedTabViewModel?.tab.url,
              let scheme = url.scheme,
              let host = url.host else {
            let alert = NSAlert()
            alert.messageText = "No active tab"
            alert.informativeText = "Open a real site (e.g. https://app.slack.com/) in the foreground tab first."
            alert.runModal()
            return
        }

        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = url.port
        components.path = "/"
        guard let scopeURL = components.url else { return }

        // The permission check in WebKit keys by SecurityOriginData.toString(),
        // i.e. scheme://host[:port] with no trailing slash.
        var origin = "\(scheme)://\(host)"
        if let port = url.port { origin += ":\(port)" }

        if #available(macOS 13.3, *) {
            WebPushNotificationDelegate.shared.grantPermission(forOrigin: origin)
        }

        guard WebPushSubscriptionStore.shared.isSubscribed(origin: origin) else {
            let alert = NSAlert()
            alert.messageText = "No active subscription"
            alert.informativeText = "The page at \(origin) hasn't called pushManager.subscribe() yet, or it called unsubscribe(). Subscribe first, then fire."
            alert.alertStyle = .warning
            alert.runModal()
            return
        }

        Task {
            let timestamp = Date.now.formatted(date: .omitted, time: .standard)
            let payload = "Synthetic push at \(timestamp)"
            let wasProcessed = await WKWebsiteDataStore.default().ddg_processPushMessage(
                registrationURL: scopeURL,
                pushData: Data(payload.utf8)
            )

            guard !wasProcessed else { return }
            await MainActor.run {
                let alert = NSAlert()
                alert.messageText = "Push not delivered"
                alert.informativeText = """
                    WebKit returned false for \(scopeURL.absoluteString).
                    Most likely no Service Worker is registered for that scope yet — open the site, wait for its SW to register (\(host) may take a few seconds after first load), then try again.
                    """
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }

    /// Fires a synthetic push at whatever Service Worker is registered for
    /// `testOrigin` in the default data store. Shows an alert with the result.
    static func fireTestPushMessage() {
        let testOriginString = "http://localhost:8765"
        guard WebPushSubscriptionStore.shared.isSubscribed(origin: testOriginString) else {
            let alert = NSAlert()
            alert.messageText = "No active subscription"
            alert.informativeText = "Open \(testOrigin.absoluteString) and click Subscribe before firing."
            alert.alertStyle = .warning
            alert.runModal()
            return
        }

        Task {
            let timestamp = Date.now.formatted(date: .omitted, time: .standard)
            let payload = "Hello from DuckDuckGo at \(timestamp)"
            let wasProcessed = await WKWebsiteDataStore.default().ddg_processPushMessage(
                registrationURL: testOrigin,
                pushData: Data(payload.utf8)
            )

            guard !wasProcessed else { return }
            await MainActor.run {
                let alert = NSAlert()
                alert.messageText = "Push not delivered"
                alert.informativeText = """
                    WebKit returned false. Most likely no Service Worker is registered for \(testOrigin.absoluteString).
                    Make sure the local server is running and that you've loaded the page in this browser.
                    """
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }

    // MARK: - Artefact resources

    private enum Resources {

        static let indexHTML = """
        <!doctype html>
        <html lang="en">
          <head>
            <meta charset="utf-8">
            <title>DDG Web Push PoC</title>
            <style>
              body { font: 16px -apple-system, sans-serif; padding: 2em; max-width: 50em; }
              code, pre { background: #f3f3f3; padding: 0.1em 0.3em; border-radius: 3px; font-size: 0.9em; }
              pre { padding: 0.6em 1em; white-space: pre-wrap; word-break: break-all; }
              .status { padding: 0.5em 1em; border-radius: 6px; margin: 1em 0; }
              .pending { background: #fff7e6; border: 1px solid #f0c36d; }
              .ready   { background: #e6ffed; border: 1px solid #6dcd86; }
              .error   { background: #ffeaea; border: 1px solid #d96565; }
              button { padding: 0.5em 1em; margin-right: 0.5em; font-size: inherit; }
              h2 { margin-top: 1.6em; font-size: 1.1em; }
            </style>
          </head>
          <body>
            <h1>DDG Web Push PoC</h1>

            <h2>1. Service Worker</h2>
            <div id="swStatus" class="status pending">Registering Service Worker…</div>

            <h2>2. Push subscription</h2>
            <div id="subStatus" class="status pending">Waiting for SW…</div>
            <button id="subscribeBtn" disabled>Subscribe</button>
            <button id="getSubBtn" disabled>Get current subscription</button>
            <button id="unsubBtn" disabled>Unsubscribe</button>
            <pre id="subDump"></pre>

            <h2>3. Trigger the push</h2>
            <p>From the menu bar, choose <em>Debug → Web Push → Fire Test Push (localhost:8765)</em>. Your macOS notification should appear with the synthetic payload.</p>

            <script>
              const swStatus  = document.getElementById('swStatus');
              const subStatus = document.getElementById('subStatus');
              const subDump   = document.getElementById('subDump');
              const subscribeBtn = document.getElementById('subscribeBtn');
              const getSubBtn    = document.getElementById('getSubBtn');
              const unsubBtn     = document.getElementById('unsubBtn');

              function setStatus(el, text, cls) { el.textContent = text; el.className = 'status ' + cls; }
              function dumpSubscription(sub) {
                if (!sub) { subDump.textContent = '(none)'; return; }
                subDump.textContent = JSON.stringify(sub.toJSON ? sub.toJSON() : sub, null, 2);
              }

              // Dummy VAPID public key (65-byte uncompressed P-256, 0x04 prefix
              // followed by zeros). Format is what the API accepts; for the PoC
              // the value itself doesn't matter — our shim doesn't look at it.
              const dummyVapid = (() => {
                const buf = new Uint8Array(65);
                buf[0] = 0x04;
                return buf;
              })();

              async function refreshExistingSubscription(reg) {
                try {
                  const existing = await reg.pushManager.getSubscription();
                  dumpSubscription(existing);
                  if (existing) {
                    setStatus(subStatus, 'Already subscribed (cached in this page).', 'ready');
                    unsubBtn.disabled = false;
                  } else {
                    setStatus(subStatus, 'Not subscribed yet — click Subscribe.', 'pending');
                    unsubBtn.disabled = true;
                  }
                } catch (err) {
                  setStatus(subStatus, 'getSubscription failed: ' + err.message, 'error');
                }
              }

              if (!('serviceWorker' in navigator)) {
                setStatus(swStatus, 'Service Workers not supported.', 'error');
              } else {
                navigator.serviceWorker.register('/sw.js', { scope: '/' })
                  .then(async reg => {
                    console.log('SW registered, scope:', reg.scope);
                    await navigator.serviceWorker.ready;
                    setStatus(swStatus, 'Service Worker ready.', 'ready');

                    if (!('PushManager' in window)) {
                      setStatus(subStatus, "'PushManager' not in window — JS shim didn't run.", 'error');
                      return;
                    }
                    subscribeBtn.disabled = false;
                    getSubBtn.disabled = false;

                    subscribeBtn.addEventListener('click', async () => {
                      try {
                        const sub = await reg.pushManager.subscribe({
                          userVisibleOnly: true,
                          applicationServerKey: dummyVapid
                        });
                        dumpSubscription(sub);
                        setStatus(subStatus, 'Subscribed.', 'ready');
                        unsubBtn.disabled = false;
                      } catch (err) {
                        setStatus(subStatus, 'subscribe failed: ' + err.message, 'error');
                      }
                    });

                    getSubBtn.addEventListener('click', () => refreshExistingSubscription(reg));

                    unsubBtn.addEventListener('click', async () => {
                      const existing = await reg.pushManager.getSubscription();
                      if (existing && await existing.unsubscribe()) {
                        dumpSubscription(null);
                        setStatus(subStatus, 'Unsubscribed.', 'pending');
                        unsubBtn.disabled = true;
                      }
                    });

                    refreshExistingSubscription(reg);
                  })
                  .catch(err => {
                    console.error('SW registration failed:', err);
                    setStatus(swStatus, 'SW registration failed: ' + err.message, 'error');
                  });
              }
            </script>
          </body>
        </html>
        """

        static let serviceWorkerJS = """
        // DDG Web Push PoC Service Worker.

        console.log('🟣 [sw] script evaluated, scope:', self.registration && self.registration.scope);

        self.addEventListener('install', event => {
          console.log('🟣 [sw] install');
          event.waitUntil(self.skipWaiting());
        });

        self.addEventListener('activate', event => {
          console.log('🟣 [sw] activate');
          event.waitUntil(self.clients.claim());
        });

        self.addEventListener('push', event => {
          const text = event.data ? event.data.text() : '(no payload)';
          console.log('🟣 [sw] push event received:', text);
          event.waitUntil(
            self.registration.showNotification('DDG Push PoC', {
              body: text,
              tag: 'ddg-poc'
            }).then(
              () => console.log('🟣 [sw] showNotification resolved'),
              err => console.log('🟣 [sw] showNotification REJECTED:', err)
            )
          );
        });

        self.addEventListener('pushsubscriptionchange', event => {
          console.log('🟣 [sw] pushsubscriptionchange');
        });
        """

        static let serverScript = #"""
        #!/usr/bin/env python3
        """Tiny HTTP server for the DDG Web Push PoC.

        Service Workers can register over plain HTTP on `localhost`, so there's
        no TLS / cert setup required. Run from this directory:

            python3 serve_push.py
        """

        import http.server
        import socketserver

        PORT = 8765


        class Handler(http.server.SimpleHTTPRequestHandler):
            def end_headers(self):
                # No caching while iterating on the test page / SW.
                self.send_header('Cache-Control', 'no-store, max-age=0')
                self.send_header('Service-Worker-Allowed', '/')
                super().end_headers()

            def log_message(self, fmt, *args):
                # Keep the console quiet — uncomment for verbose logging.
                pass


        if __name__ == '__main__':
            with socketserver.TCPServer(('127.0.0.1', PORT), Handler) as httpd:
                print(f'Serving DDG Web Push PoC at http://localhost:{PORT}/')
                print('Open this URL in DuckDuckGo, then trigger Debug → Web Push → Fire Test Push.')
                print('Ctrl+C to stop.')
                try:
                    httpd.serve_forever()
                except KeyboardInterrupt:
                    print('\nServer stopped.')
        """#

        static let readme = """
        # Web Push PoC

        This folder lets you verify that the DuckDuckGo macOS browser can deliver
        a synthetic Web Push event to a real Service Worker — without going
        through Apple's APNs / webpushd.

        ## Steps

        1. **Start the local server.** In Terminal:

               cd ~/Desktop/ddg-web-push-testing
               python3 serve_push.py

           Leave the Terminal window open.

        2. **Open the page in DuckDuckGo.** Navigate to:

               http://localhost:8765/

           Wait for the status banner to turn green ("Service Worker ready").

        3. **Fire a test push.** In the DuckDuckGo menu bar:

               Debug → Web Push → Fire Test Push

           A macOS notification should appear titled "DDG Push PoC". On first
           run you'll get a system notification-permission prompt — accept it
           and trigger the push again.

        ## What's happening

        - `sw.js` is a real Service Worker registered against `http://localhost:8765/`.
        - The debug menu item calls `WKWebsiteDataStore._processPushMessage:`, a
          private WebKit SPI, with a synthesised payload scoped to the same URL.
        - WebKit dispatches a real `PushEvent` at the SW; the handler calls
          `self.registration.showNotification(...)`.
        - The browser receives that call via the `_WKWebsiteDataStoreDelegate`
          hook and forwards it to `UNUserNotificationCenter` — what you see as
          the system notification.

        ## Troubleshooting

        - **"Push not delivered" alert.** The SW isn't registered for this
          origin. Reload the page, wait for the green banner, and try again.
        - **No notification appears, but "Push delivered" alert showed up.**
          Check System Settings → Notifications → DuckDuckGo. The first run
          should have prompted; if you dismissed the prompt, re-enable
          notifications manually.
        - **SW won't register.** Make sure you opened `http://localhost:8765/`
          (not `127.0.0.1` — secure-context status is keyed on the host name).
        """
    }
}
