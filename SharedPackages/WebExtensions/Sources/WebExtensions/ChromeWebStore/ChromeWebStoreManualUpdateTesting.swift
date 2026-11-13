//
//  ChromeWebStoreManualUpdateTesting.swift
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

#if DEBUG && os(macOS)
import Combine
import Foundation
import Persistence
import PrivacyConfig
import WebKit

/// A separate extension profile and loopback transport for the manual v1 → v2 update test.
@available(macOS 15.4, *)
@MainActor
public struct ChromeWebStoreManualUpdateTesting {
    public nonisolated static let extensionID = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    nonisolated static let serverPort = 18765
    public nonisolated static var controlPageURL: URL { URL(string: "http://127.0.0.1:\(serverPort)/")! }
    private static let enabledKey = "web-extension-manual-update-testing"
    private static let controllerKey = "manual-update-controller-id"
    private static let websiteDataKey = "manual-update-website-data-id"

    public static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    public let directory: URL
    private let defaults: UserDefaults

    public init(directory: URL? = nil, defaults: UserDefaults? = nil) {
        self.directory = directory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/ddg-extension-update-testing", isDirectory: true)
        let suite = (Bundle.main.bundleIdentifier ?? "com.duckduckgo.browser") + ".extension-update-testing"
        guard let storage = defaults ?? UserDefaults(suiteName: suite) else { preconditionFailure("Cannot create the manual-test preferences") }
        self.defaults = storage
    }

    public var extensionsDirectory: URL { directory.appendingPathComponent("Profile/Extensions", isDirectory: true) }

    public func owns(_ manager: WebExtensionManager) -> Bool {
        manager.extensionsDirectory.standardizedFileURL == extensionsDirectory.standardizedFileURL
    }

    public func offeredVersion() async throws -> String {
        try await serverStatus().version
    }

    func serverStatus() async throws -> (version: String, processIdentifier: Int32) {
        let data = try await localData(at: "status")
        let status = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let version = status?["version"] as? String, ["1.0", "2.0"].contains(version),
              let identifier = status?["pid"] as? NSNumber, identifier.int32Value > 0 else {
            throw CocoaError(.coderReadCorrupt)
        }
        return (version, identifier.int32Value)
    }

    public func setUp(serverDirectory: URL? = nil) throws {
        let directory = serverDirectory ?? self.directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = Self.serverScript
            .replacingOccurrences(of: "__EXTENSION_ID__", with: Self.extensionID)
            .replacingOccurrences(of: "__PORT__", with: String(Self.serverPort))
        try script.write(to: directory.appendingPathComponent("serve_updates.py"), atomically: true, encoding: .utf8)
        try Self.instructions.write(to: directory.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
    }

    public func makeManager(configuration: WebExtensionConfigurationProviding,
                            windowTabProvider: WebExtensionWindowTabProviding,
                            permissionPrompter: WebExtensionPermissionPrompting,
                            enforcesPermissions: Bool,
                            presenter: ChromeWebStorePresenting,
                            internalSiteHandler: (any WebExtensionInternalSiteHandling)? = nil,
                            isUpdateDiscoveryEnabled: @escaping @MainActor @Sendable () -> Bool = { true },
                            updateApplicationPolicy: ((WebExtensionManager) -> (@MainActor (String) -> Bool))? = nil,
                            updateApplicationActivityUpdates: AnyPublisher<Void, Never>? = nil) -> WebExtensionManager {
        let installed = InstalledWebExtensionStore(storage: defaults.keyedStoring())
        let permissions = enforcesPermissions
            ? WebExtensionPermissionController(store: WebExtensionPermissionStore(keyValueStore: defaults),
                                               installationStore: installed, prompter: permissionPrompter) : nil
        let controller = WKWebExtensionController.Configuration(identifier: persistentIdentifier(for: Self.controllerKey))
        controller.defaultWebsiteDataStore = WKWebsiteDataStore(forIdentifier: persistentIdentifier(for: Self.websiteDataKey))
        let manager = WebExtensionManager(configuration: configuration, controllerConfiguration: controller,
                                         windowTabProvider: windowTabProvider,
                                         storageProvider: WebExtensionStorageProvider(extensionsDirectory: extensionsDirectory),
                                         installationStore: installed, permissionController: permissions,
                                         internalSiteHandler: internalSiteHandler, keyValueStore: defaults)
        let catalog = ManualUpdateCatalog()
        let pending = ChromeWebStorePendingUpdateStore(persistentDirectory: extensionsDirectory.appendingPathComponent(".pending-updates"))
        let installer = ChromeWebStoreUpdateInstaller(manager: manager, pendingUpdates: pending,
                                                     isEnabled: isUpdateDiscoveryEnabled, isCatalogExtension: { catalog.contains($0) },
                                                     canApplyWhileInactive: updateApplicationPolicy?(manager))
        manager.chromeWebStore = ChromeWebStoreService(
            manager: manager, catalog: catalog, downloader: ChromeWebStoreDownloader(), presenter: presenter,
            verifier: ChromeWebStorePackageVerifier(allowUnsignedManualTestFixture: true),
            isUpdateDiscoveryEnabled: isUpdateDiscoveryEnabled, updateApplicationActivityUpdates: updateApplicationActivityUpdates,
            keyValueStore: defaults, pendingUpdates: pending, updateInstaller: installer,
            updateDownload: { try await ChromeWebStoreUpdateDownloader(configuration: Self.sessionConfiguration()).download($0) },
            updateCheck: { await ChromeWebStoreUpdateChecker(configuration: Self.sessionConfiguration()).check(extensionID: $0, installedVersion: $1) })
        return manager
    }

    public func installVersionOne(in manager: WebExtensionManager) async throws {
        guard owns(manager) else { throw TestingError.restartRequired }
        guard !manager.installationStore.installedExtensions.contains(where: { $0.storeIdentity?.id == Self.extensionID }) else {
            throw TestingError.alreadyInstalled
        }
        let package = try await localData(at: "manual-extension-test/v1.zip")
        let archive = try ChromeWebStorePackageVerifier(allowUnsignedManualTestFixture: true)
            .verifiedArchive(in: package, extensionID: Self.extensionID)
        guard archive.version == "1.0" else { throw TestingError.invalidFixture }
        let archiveURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("zip")
        defer { try? FileManager.default.removeItem(at: archiveURL) }
        try archive.data.write(to: archiveURL, options: .atomic)
        try await manager.installExtension(from: archiveURL, storeIdentity: .init(store: .chromeWebStore, id: Self.extensionID))
    }

    private func localData(at path: String) async throws -> Data {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 1
        configuration.timeoutIntervalForResource = 1
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(from: Self.controlPageURL.appendingPathComponent(path))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }

    nonisolated static func sessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ManualUpdateURLProtocol.self]
        return configuration
    }

    private func persistentIdentifier(for key: String) -> UUID {
        if let value = defaults.string(forKey: key), let identifier = UUID(uuidString: value) { return identifier }
        let identifier = UUID()
        defaults.set(identifier.uuidString, forKey: key)
        return identifier
    }

    private enum TestingError: LocalizedError {
        case restartRequired, alreadyInstalled, invalidFixture
        var errorDescription: String? {
            switch self {
            case .restartRequired: return "Restart the app to use the isolated extension test profile."
            case .alreadyInstalled: return "Remove the existing test extension from its Debug submenu before installing v1 again."
            case .invalidFixture: return "The local server did not provide a valid v1 test fixture."
            }
        }
    }
}

@available(macOS 15.4, *)
@MainActor
private struct ManualUpdateCatalog: ChromeWebStoreCatalogProviding {
    var extensionIDs: [String] { [ChromeWebStoreManualUpdateTesting.extensionID] }
    var learnMoreURL: URL? { nil }
    func listing(of subfeature: ExtensionsCatalogSubfeature) -> ChromeWebStoreListing? { nil }
}

/// Reuses the production checker/downloader, including URL, size and hash validation, over a loopback transport.
@available(macOS 15.4, *)
private final class ManualUpdateURLProtocol: URLProtocol, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var networkTask: URLSessionDataTask?
    private var stopped = false

    override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url, url.scheme == "https", url.host == "clients2.google.com" else { return false }
        if url.path == "/service/update2/crx" {
            return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                .first(where: { $0.name == "x" })?.value?.contains("id=" + ChromeWebStoreManualUpdateTesting.extensionID) == true
        }
        return ["/manual-extension-test/v1.zip", "/manual-extension-test/v2.zip"].contains(url.path)
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let original = request.url, var components = URLComponents(url: original, resolvingAgainstBaseURL: false) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = ChromeWebStoreManualUpdateTesting.serverPort
        guard let destination = components.url else { return }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        let download = session.dataTask(with: destination) { [weak self] data, response, error in
            defer { session.finishTasksAndInvalidate() }
            guard let self, !self.lock.withLock({ self.stopped }) else { return }
            if let error {
                self.client?.urlProtocol(self, didFailWithError: error)
                return
            }
            guard let response = response as? HTTPURLResponse, let data,
                  let forwarded = HTTPURLResponse(url: original, statusCode: response.statusCode,
                                                  httpVersion: "HTTP/1.1", headerFields: response.allHeaderFields as? [String: String]) else {
                self.client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            self.client?.urlProtocol(self, didReceive: forwarded, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: data)
            self.client?.urlProtocolDidFinishLoading(self)
        }
        let shouldStart = lock.withLock {
            networkTask = download
            return !stopped
        }
        if shouldStart { download.resume() } else { session.invalidateAndCancel() }
    }

    override func stopLoading() {
        let download = lock.withLock {
            stopped = true
            return networkTask
        }
        download?.cancel()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // The local source needs no redirects; never relay a fixture request outside loopback.
        completionHandler(nil)
    }
}

@available(macOS 15.4, *)
extension ChromeWebStoreManualUpdateTesting {
    private static let instructions = """
    Manual extension update test (Debug DMG build)

    1. Enable Use Test Profile under Debug > Web Extensions > Local Update Testing.
    2. Restart the app.
    3. Select Start Local Server… from the same menu.
    4. Select Install Test Extension v1 from the same menu.
    5. Open its toolbar popup.
    6. Click Add 1 to save a counter value.
    7. Open http://127.0.0.1:18765 and select Offer v2 (2.0).
    8. Open Debug > Web Extensions > Check for Updates….
    9. Click Check for Updates in the window.
       Expect: Extension update preparation: <id> verified
    10. Restart the app.
    11. Open the popup.
        Expect: version 2.0 and the saved counter value.

    Console filter: s:WebExtensions m:update
    Stop Local Server, closing the app, or releasing the menu stops the server and removes its temporary files.
    The installed test extension and its data survive restarting the app. Start the server again to resume checks.
    Restore normal extensions by disabling the local test profile and restarting.
    This mode uses separate extension files, preferences and WebKit data.
    Only the fixture's publisher signature is bypassed; update size, hash, version and ZIP validation run normally.
    No UI automation, failure scenarios or real Chrome Web Store requests are included.
    """

    private static let serverScript = #"""
    #!/usr/bin/env python3
    """Local source for the manual extension update test. Uses only Python's standard library."""
    import argparse
    import hashlib
    import http.server
    import json
    import os
    from pathlib import Path
    import struct
    import urllib.parse
    import zipfile
    import zlib

    ROOT = Path(__file__).resolve().parent
    EXTENSION_ID = "__EXTENSION_ID__"
    PORT = __PORT__
    STATE = ROOT / "offered-version.json"
    HTML = """<!doctype html><html><head><meta charset="utf-8"><style>
    :root{color-scheme:light dark;--background:#f5f8ff;--text:#202631;--muted:#526078;--accent:#175ad2}
    body{box-sizing:border-box;margin:0;width:300px;padding:20px;font:14px system-ui;
         background:var(--background);color:var(--text)}
    header{display:flex;align-items:center;gap:10px;margin-bottom:18px}h1{font-size:16px;margin:0}
    p{color:var(--muted);margin:12px 0}b{color:var(--text);font-variant-numeric:tabular-nums}
    #version{color:var(--accent)}body[data-version="2.0"]{--accent:#17713d}
    button{border:0;border-radius:8px;background:#175ad2;color:#fff;font:inherit;font-weight:600;
           padding:8px 14px;cursor:pointer}button:hover{background:#1146a5}button:focus-visible{outline:2px solid var(--accent);outline-offset:3px}
    #status{min-height:18px;margin-bottom:0}
    @media(prefers-color-scheme:dark){:root{--background:#222731;--text:#f2f5fc;--muted:#b5bfd0;--accent:#91baff}
      body[data-version="2.0"]{--accent:#81d5a0}}
    </style></head><body><header><img src="icon.png" width="32" height="32" alt=""><h1>Extension Update Test</h1></header>
    <p>Version: <b id="version"></b></p><p>Saved counter: <b id="counter"></b></p><button id="increment">Add 1</button>
    <p id="status" role="status"></p><script src="popup.js"></script></body></html>"""
    SCRIPT = """(async () => {
      const api = globalThis.browser || globalThis.chrome;
      const version = api.runtime.getManifest().version;
      document.body.dataset.version = version;
      document.getElementById('version').textContent = version;
      let {counter = 0} = await api.storage.local.get('counter');
      const output = document.getElementById('counter');
      output.textContent = counter;
      document.getElementById('increment').addEventListener('click', async () => {
        await api.storage.local.set({counter: ++counter});
        output.textContent = counter;
        document.getElementById('status').textContent = 'Saved';
      });
    })().catch(error => { document.getElementById('status').textContent = error.message; });"""

    CONTROL_PAGE = """<!doctype html><html lang="en"><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1"><title>Extension Update Testing</title>
    <style>
    :root{color-scheme:light dark}body{max-width:560px;margin:64px auto;padding:24px;
      font:16px/1.5 system-ui;background:Canvas;color:CanvasText}h1{font-size:26px}
    .version{font-size:40px;font-weight:700;margin:8px 0 24px}.buttons{display:flex;gap:12px;flex-wrap:wrap}
    button{font:inherit;font-weight:600;padding:10px 18px;border:0;border-radius:8px;
      background:#175ad2;color:#fff;cursor:pointer}button:hover{background:#1146a5}
    button:focus-visible{outline:2px solid Highlight;outline-offset:3px}code{font-size:14px}
    </style></head><body><h1>Extension Update Testing</h1><p>Currently offered version</p>
    <p class="version">__OFFERED_VERSION__</p><form class="buttons" method="post" action="/offer">
    <button name="version" value="1.0">Offer v1 (1.0)</button><button name="version" value="2.0">Offer v2 (2.0)</button>
    </form><p>This controls what the local server offers. It does not install an update.</p>
    <p>After offering v2, open <code>Debug → Web Extensions → Check for Updates…</code>,
    then click <code>Check for Updates</code> in the window.
    Restart the app after the download is verified.</p></body></html>"""

    def make_icon():
        rows = bytearray()
        for y in range(64):
            rows.append(0)  # PNG scanline filter.
            for x in range(64):
                corner_x = max(13 - x, 0, x - 50)
                corner_y = max(13 - y, 0, y - 50)
                opaque = corner_x ** 2 + corner_y ** 2 <= 13 ** 2
                top = (20 <= x <= 43 and 17 <= y <= 22) or (37 <= x <= 49 and abs(y - 19.5) <= 49 - x)
                bottom = (20 <= x <= 43 and 41 <= y <= 46) or (14 <= x <= 26 and abs(y - 43.5) <= x - 14)
                rows.extend((255, 255, 255, 255) if top or bottom else (30, 102, 225, 255 if opaque else 0))
        def chunk(kind, data):
            return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
        header = struct.pack(">IIBBBBB", 64, 64, 8, 6, 0, 0, 0)
        return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b"")

    def make_packages():
        icon = make_icon()
        for version, filename in [("1.0", "v1.zip"), ("2.0", "v2.zip")]:
            manifest = {"manifest_version": 3, "name": "Extension Update Test", "version": version,
                        "permissions": ["storage"], "icons": {"64": "icon.png"},
                        "action": {"default_popup": "popup.html", "default_icon": "icon.png"}}
            with zipfile.ZipFile(ROOT / filename, "w", zipfile.ZIP_DEFLATED) as archive:
                archive.writestr("manifest.json", json.dumps(manifest))
                archive.writestr("popup.html", HTML)
                archive.writestr("popup.js", SCRIPT)
                archive.writestr("icon.png", icon)

    def offer(version):
        temporary = STATE.with_suffix(".tmp")
        temporary.write_text(json.dumps({"version": version}))
        temporary.replace(STATE)

    class Handler(http.server.BaseHTTPRequestHandler):
        def send(self, data, content_type):
            self.send_response(200)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            request = urllib.parse.urlparse(self.path)
            if request.path == "/status":
                version = json.loads(STATE.read_text())["version"]
                self.send(json.dumps({"version": version, "pid": os.getpid()}).encode(), "application/json")
            elif request.path == "/":
                version = json.loads(STATE.read_text())["version"]
                self.send(CONTROL_PAGE.replace("__OFFERED_VERSION__", version).encode(), "text/html; charset=utf-8")
            elif request.path == "/service/update2/crx":
                query = urllib.parse.parse_qs(request.query)
                values = urllib.parse.parse_qs(query.get("x", [""])[0])
                if values.get("id") != [EXTENSION_ID]:
                    self.send_error(404)
                    return
                version = json.loads(STATE.read_text())["version"]
                installed = values.get("v", ["0"])[0]
                if tuple(map(int, installed.split("."))) >= tuple(map(int, version.split("."))):
                    update = '<updatecheck status="noupdate"/>'
                else:
                    filename = "v1.zip" if version == "1.0" else "v2.zip"
                    package = (ROOT / filename).read_bytes()
                    url = "https://clients2.google.com/manual-extension-test/" + filename
                    update = (f'<updatecheck status="ok" version="{version}" codebase="{url}" '
                              f'size="{len(package)}" hash_sha256="{hashlib.sha256(package).hexdigest()}"/>')
                xml = (f'<gupdate xmlns="http://www.google.com/update2/response" protocol="2.0">'
                       f'<app appid="{EXTENSION_ID}" status="ok">{update}</app></gupdate>')
                self.send(xml.encode(), "application/xml")
            elif request.path in ["/manual-extension-test/v1.zip", "/manual-extension-test/v2.zip"]:
                self.send((ROOT / request.path.rsplit("/", 1)[1]).read_bytes(), "application/zip")
            else:
                self.send_error(404)

        def do_POST(self):
            if self.path != "/offer":
                self.send_error(404)
                return
            if self.headers.get("Origin") not in [None, f"http://127.0.0.1:{PORT}"]:
                self.send_error(403)
                return
            try:
                length = int(self.headers.get("Content-Length", "0"))
            except ValueError:
                self.send_error(400)
                return
            if not 0 < length <= 128:
                self.send_error(400)
                return
            values = urllib.parse.parse_qs(self.rfile.read(length).decode("utf-8", errors="replace"))
            if values.get("version") not in [["1.0"], ["2.0"]]:
                self.send_error(400)
                return
            offer(values["version"][0])
            self.send_response(303)
            self.send_header("Location", "/")
            self.send_header("Content-Length", "0")
            self.end_headers()

    def main():
        parser = argparse.ArgumentParser(description=__doc__)
        parser.add_argument("command", choices=["serve", "prepare", "offer"], nargs="?", default="serve")
        parser.add_argument("version", choices=["1.0", "2.0"], nargs="?")
        arguments = parser.parse_args()
        if arguments.command == "offer":
            if arguments.version is None:
                parser.error("offer requires 1.0 or 2.0")
            offer(arguments.version)
            print("Offering version " + arguments.version)
            return
        make_packages()
        if arguments.command == "prepare":
            offer("1.0")
            print("Prepared v1.zip and v2.zip")
            return
        if not STATE.exists():
            offer("1.0")
        print(f"Serving extension updates at http://127.0.0.1:{PORT}", flush=True)
        print(f"Choose the offered version at http://127.0.0.1:{PORT}", flush=True)
        try:
            http.server.HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
        except KeyboardInterrupt:
            pass

    if __name__ == "__main__":
        main()
    """#
}
#endif
