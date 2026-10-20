//
//  WebExtensionBackgroundPagePatcherTests.swift
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

import XCTest
import WebKit
import ZIPFoundation
@testable import WebExtensions
#if os(macOS)
import AppKit
#endif

final class WebExtensionBackgroundPagePatcherTests: XCTestCase {

    private var temporaryDirectory: URL!
    private var patcher: WebExtensionBackgroundPagePatcher!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WebExtensionBackgroundPagePatcherTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        patcher = WebExtensionBackgroundPagePatcher(useServiceWorkerWrapper: false)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
        patcher = nil
        try super.tearDownWithError()
    }

    // MARK: - Patching

    func testWhenManifestDeclaresModuleServiceWorker_ThenBackgroundPageIsGeneratedAndManifestIsRewritten() throws {
        let extensionDirectory = try makeExtensionDirectory(manifest: """
        {
            "manifest_version": 3,
            "name": "Test Extension",
            "version": "1.2.3",
            "permissions": ["storage", "nativeMessaging"],
            "background": {
                "service_worker": "background/background.js",
                "type": "module"
            }
        }
        """)

        XCTAssertTrue(patcher.patchIfNeeded(installedExtensionURL: extensionDirectory))

        let background = try backgroundSection(in: extensionDirectory)
        XCTAssertEqual(background["page"] as? String, WebExtensionBackgroundPagePatcher.backgroundPageFilename)
        XCTAssertNil(background["service_worker"])
        XCTAssertNil(background["type"])

        // Other keys survive the rewrite.
        let manifest = try loadManifest(in: extensionDirectory)
        XCTAssertEqual(manifest["manifest_version"] as? Int, 3)
        XCTAssertEqual(manifest["name"] as? String, "Test Extension")
        XCTAssertEqual(manifest["version"] as? String, "1.2.3")
        XCTAssertEqual(manifest["permissions"] as? [String], ["storage", "nativeMessaging"])

        let backgroundPage = try loadBackgroundPage(in: extensionDirectory)
        XCTAssertTrue(backgroundPage.contains("type=\"module\""), backgroundPage)
        XCTAssertTrue(backgroundPage.contains("src=\"/background/background.js\""), backgroundPage)
    }

    func testWhenManifestDeclaresServiceWorkerWithoutType_ThenBackgroundPageUsesClassicScript() throws {
        let extensionDirectory = try makeExtensionDirectory(manifest: """
        {
            "manifest_version": 3,
            "background": {
                "service_worker": "worker.js"
            }
        }
        """)

        XCTAssertTrue(patcher.patchIfNeeded(installedExtensionURL: extensionDirectory))

        let background = try backgroundSection(in: extensionDirectory)
        XCTAssertEqual(background["page"] as? String, WebExtensionBackgroundPagePatcher.backgroundPageFilename)
        XCTAssertNil(background["service_worker"])

        let backgroundPage = try loadBackgroundPage(in: extensionDirectory)
        XCTAssertFalse(backgroundPage.contains("type="), backgroundPage)
        XCTAssertTrue(backgroundPage.contains("src=\"/worker.js\""), backgroundPage)
    }

    func testWhenManifestIsPatchedTwice_ThenSecondRunChangesNothing() throws {
        let extensionDirectory = try makeExtensionDirectory(manifest: """
        {
            "manifest_version": 3,
            "background": {
                "service_worker": "background/background.js",
                "type": "module"
            }
        }
        """)

        XCTAssertTrue(patcher.patchIfNeeded(installedExtensionURL: extensionDirectory))

        let patchedManifest = try Data(contentsOf: manifestURL(in: extensionDirectory))
        let patchedPage = try Data(contentsOf: backgroundPageURL(in: extensionDirectory))

        XCTAssertFalse(patcher.patchIfNeeded(installedExtensionURL: extensionDirectory))

        XCTAssertEqual(try Data(contentsOf: manifestURL(in: extensionDirectory)), patchedManifest)
        XCTAssertEqual(try Data(contentsOf: backgroundPageURL(in: extensionDirectory)), patchedPage)
    }

    // MARK: - importScripts Shim And Webpack Chunks

    func testWhenClassicWorkerHasChunkFiles_ThenShimAndChunksArePreloadedInChunkIdOrder() throws {
        let extensionDirectory = try makeExtensionDirectory(manifest: """
        {
            "manifest_version": 3,
            "background": {
                "service_worker": "background.js"
            }
        }
        """)
        try writeFile(named: "719.background.js", in: extensionDirectory)
        try writeFile(named: "12.background.js", in: extensionDirectory)
        try writeFile(named: "719.background.js.map", in: extensionDirectory)
        try writeFile(named: "vendor.js", in: extensionDirectory)

        XCTAssertTrue(patcher.patchIfNeeded(installedExtensionURL: extensionDirectory))

        let backgroundPage = try loadBackgroundPage(in: extensionDirectory)
        assertScriptSources(["/\(WebExtensionImportScriptsShim.filename)",
                             "/12.background.js",
                             "/719.background.js",
                             "/background.js"],
                            appearInOrderIn: backgroundPage)
        XCTAssertFalse(backgroundPage.contains("719.background.js.map"), backgroundPage)
        XCTAssertFalse(backgroundPage.contains("vendor.js"), backgroundPage)

        XCTAssertEqual(try loadImportScriptsShim(in: extensionDirectory), WebExtensionImportScriptsShim.source)
    }

    func testWhenClassicWorkerHasNoChunkFiles_ThenShimIsStillPreloaded() throws {
        let extensionDirectory = try makeExtensionDirectory(manifest: """
        {
            "manifest_version": 3,
            "background": {
                "service_worker": "background.js"
            }
        }
        """)

        XCTAssertTrue(patcher.patchIfNeeded(installedExtensionURL: extensionDirectory))

        let backgroundPage = try loadBackgroundPage(in: extensionDirectory)
        assertScriptSources(["/\(WebExtensionImportScriptsShim.filename)",
                             "/background.js"],
                            appearInOrderIn: backgroundPage)
        XCTAssertEqual(backgroundPage.components(separatedBy: "<script").count - 1, 2, backgroundPage)
        XCTAssertEqual(try loadImportScriptsShim(in: extensionDirectory), WebExtensionImportScriptsShim.source)
    }

    func testWhenWorkerIsAModule_ThenNeitherShimNorChunksArePreloaded() throws {
        let extensionDirectory = try makeExtensionDirectory(manifest: """
        {
            "manifest_version": 3,
            "background": {
                "service_worker": "background.js",
                "type": "module"
            }
        }
        """)
        try writeFile(named: "719.background.js", in: extensionDirectory)

        XCTAssertTrue(patcher.patchIfNeeded(installedExtensionURL: extensionDirectory))

        let backgroundPage = try loadBackgroundPage(in: extensionDirectory)
        XCTAssertFalse(backgroundPage.contains(WebExtensionImportScriptsShim.filename), backgroundPage)
        XCTAssertFalse(backgroundPage.contains("719.background.js"), backgroundPage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: importScriptsShimURL(in: extensionDirectory).path))
    }

    func testWhenWorkerIsInASubdirectory_ThenChunksArePreloadedFromThatSubdirectory() throws {
        let extensionDirectory = try makeExtensionDirectory(manifest: """
        {
            "manifest_version": 3,
            "background": {
                "service_worker": "background/worker.js"
            }
        }
        """)
        let workerDirectory = extensionDirectory.appendingPathComponent("background")
        try FileManager.default.createDirectory(at: workerDirectory, withIntermediateDirectories: true)
        try writeFile(named: "3.worker.js", in: workerDirectory)

        XCTAssertTrue(patcher.patchIfNeeded(installedExtensionURL: extensionDirectory))

        let backgroundPage = try loadBackgroundPage(in: extensionDirectory)
        assertScriptSources(["/\(WebExtensionImportScriptsShim.filename)",
                             "/background/3.worker.js",
                             "/background/worker.js"],
                            appearInOrderIn: backgroundPage)

        // The shim lives next to the manifest, not next to the worker.
        XCTAssertEqual(try loadImportScriptsShim(in: extensionDirectory), WebExtensionImportScriptsShim.source)
    }

    // MARK: - Manifests Left Untouched

    func testWhenManifestDeclaresBackgroundScripts_ThenManifestIsUntouched() throws {
        try assertManifestIsUntouched("""
        {
            "manifest_version": 3,
            "background": {
                "service_worker": "background/index.js",
                "scripts": ["background/index.js"],
                "persistent": false
            }
        }
        """)
    }

    func testWhenManifestDeclaresBackgroundPage_ThenManifestIsUntouched() throws {
        try assertManifestIsUntouched("""
        {
            "manifest_version": 3,
            "background": {
                "service_worker": "background/index.js",
                "page": "background/index.html"
            }
        }
        """)
    }

    func testWhenManifestIsADuckDuckGoExtensionWithServiceWorker_ThenManifestIsUntouched() throws {
        try assertManifestIsUntouched("""
        {
            "manifest_version": 3,
            "name": "Content Blocker",
            "browser_specific_settings": {
                "duckduckgo": { "id": "com.duckduckgo.content-blocker-extension" }
            },
            "background": {
                "service_worker": "background.js",
                "type": "module"
            }
        }
        """)
    }

    func testWhenManifestHasNoBackgroundKey_ThenManifestIsUntouched() throws {
        try assertManifestIsUntouched("""
        {
            "manifest_version": 3,
            "name": "Content Script Only"
        }
        """)
    }

    // MARK: - Loadable Copies

    private let serviceWorkerManifest = """
    { "manifest_version": 3, "name": "Copied", "version": "1.0", "background": { "service_worker": "background.js" } }
    """

    private let duckDuckGoManifest = """
    { "manifest_version": 3, "name": "Ours", "version": "1.0", "background": { "service_worker": "background.js" },
      "browser_specific_settings": { "duckduckgo": { "id": "com.duckduckgo.test" } } }
    """

    func testWhenArchiveDeclaresServiceWorker_ThenARewrittenCopyIsLoadedAndTheArchiveIsUntouched() throws {
        let archiveURL = try makeArchive(files: ["manifest.json": serviceWorkerManifest, "background.js": "1;"])
        let archiveData = try Data(contentsOf: archiveURL)

        let loadableURL = patcher.loadableExtensionURL(for: archiveURL, installFolder: installFolder(of: archiveURL))

        XCTAssertEqual(loadableURL.standardizedFileURL, loadableFolder(of: archiveURL).standardizedFileURL)
        XCTAssertEqual(try backgroundSection(in: loadableURL)["page"] as? String, WebExtensionBackgroundPagePatcher.backgroundPageFilename)
        XCTAssertTrue(FileManager.default.fileExists(atPath: loadableURL.appendingPathComponent("background.js").path))
        XCTAssertEqual(try Data(contentsOf: archiveURL), archiveData)
    }

    func testWhenArchiveWrapsItsFilesInAFolder_ThenThatFolderOfTheCopyIsLoaded() throws {
        let archiveURL = try makeArchive(files: ["bitwarden/manifest.json": serviceWorkerManifest, "bitwarden/background.js": "1;"])

        let loadableURL = patcher.loadableExtensionURL(for: archiveURL, installFolder: installFolder(of: archiveURL))

        XCTAssertEqual(loadableURL.standardizedFileURL,
                       loadableFolder(of: archiveURL).appendingPathComponent("bitwarden").standardizedFileURL)
        XCTAssertEqual(try backgroundSection(in: loadableURL)["page"] as? String, WebExtensionBackgroundPagePatcher.backgroundPageFilename)
    }

    func testWhenFolderDeclaresServiceWorker_ThenARewrittenCopyIsLoadedAndTheFolderIsUntouched() throws {
        let installFolder = try makeInstallFolder()
        let extensionDirectory = installFolder.appendingPathComponent("extension")
        try writeFiles(["manifest.json": serviceWorkerManifest, "background.js": "1;"], in: extensionDirectory)

        let loadableURL = patcher.loadableExtensionURL(for: extensionDirectory, installFolder: installFolder)

        XCTAssertEqual(loadableURL.standardizedFileURL,
                       installFolder.appendingPathComponent(WebExtensionBackgroundPagePatcher.loadableFolderName).standardizedFileURL)
        XCTAssertEqual(try backgroundSection(in: loadableURL)["page"] as? String, WebExtensionBackgroundPagePatcher.backgroundPageFilename)
        XCTAssertEqual(try backgroundSection(in: extensionDirectory)["service_worker"] as? String, "background.js")
        XCTAssertFalse(FileManager.default.fileExists(atPath: backgroundPageURL(in: extensionDirectory).path))
    }

    func testWhenFolderIsTheInstallFolder_ThenTheCopyLeavesItselfOut() throws {
        let installFolder = try makeInstallFolder()
        try writeFiles(["manifest.json": serviceWorkerManifest, "background.js": "1;"], in: installFolder)

        let loadableURL = patcher.loadableExtensionURL(for: installFolder, installFolder: installFolder)
        _ = patcher.loadableExtensionURL(for: installFolder, installFolder: installFolder)

        let copiedItems = try FileManager.default.contentsOfDirectory(atPath: loadableURL.path)
        XCTAssertFalse(copiedItems.contains(WebExtensionBackgroundPagePatcher.loadableFolderName))
        XCTAssertEqual(try backgroundSection(in: installFolder)["service_worker"] as? String, "background.js")
    }

    func testWhenExtensionIsOneOfOurs_ThenItIsLoadedAsIs() throws {
        let archiveURL = try makeArchive(files: ["manifest.json": duckDuckGoManifest])

        XCTAssertEqual(patcher.loadableExtensionURL(for: archiveURL, installFolder: installFolder(of: archiveURL)), archiveURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: loadableFolder(of: archiveURL).path))
    }

    func testWhenExtensionNeedsNoRewrite_ThenItIsLoadedAsIsAndAnOldCopyIsRemoved() throws {
        let archiveURL = try makeArchive(files: ["manifest.json": """
        { "manifest_version": 3, "name": "Page", "version": "1.0", "background": { "page": "background.html" } }
        """])
        try FileManager.default.createDirectory(at: loadableFolder(of: archiveURL), withIntermediateDirectories: true)

        XCTAssertEqual(patcher.loadableExtensionURL(for: archiveURL, installFolder: installFolder(of: archiveURL)), archiveURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: loadableFolder(of: archiveURL).path))
    }

    func testWhenInstallationIsUnchanged_ThenTheCopyIsReused() throws {
        let archiveURL = try makeArchive(files: ["manifest.json": serviceWorkerManifest, "background.js": "1;"])
        let loadableURL = patcher.loadableExtensionURL(for: archiveURL, installFolder: installFolder(of: archiveURL))
        let markerURL = loadableURL.appendingPathComponent("marker")
        try Data().write(to: markerURL)

        XCTAssertEqual(patcher.loadableExtensionURL(for: archiveURL, installFolder: installFolder(of: archiveURL)), loadableURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: markerURL.path))
    }

    func testWhenInstallationChanges_ThenItIsCopiedAgain() throws {
        let archiveURL = try makeArchive(files: ["manifest.json": serviceWorkerManifest, "background.js": "1;"])
        let loadableURL = patcher.loadableExtensionURL(for: archiveURL, installFolder: installFolder(of: archiveURL))
        let markerURL = loadableURL.appendingPathComponent("marker")
        try Data().write(to: markerURL)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: archiveURL.path)

        XCTAssertEqual(patcher.loadableExtensionURL(for: archiveURL, installFolder: installFolder(of: archiveURL)), loadableURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: markerURL.path))
        XCTAssertEqual(try backgroundSection(in: loadableURL)["page"] as? String, WebExtensionBackgroundPagePatcher.backgroundPageFilename)
    }

    @available(macOS 15.4, iOS 18.4, *)
    func testWhenAFolderInstallHasACopy_ThenTheInstallationIsStillResolved() throws {
        let installFolder = try makeInstallFolder()
        let extensionDirectory = installFolder.appendingPathComponent("extension")
        try writeFiles(["manifest.json": serviceWorkerManifest, "background.js": "1;"], in: extensionDirectory)
        _ = patcher.loadableExtensionURL(for: extensionDirectory, installFolder: installFolder)
        let storage = ExtensionsDirectoryStorage(extensionsDirectory: installFolder.deletingLastPathComponent())

        let resolvedURL = storage.resolveInstalledExtension(identifier: installFolder.lastPathComponent)

        XCTAssertEqual(resolvedURL?.standardizedFileURL, extensionDirectory.standardizedFileURL)
    }

    // MARK: - Service worker experiment

    @available(macOS 15.4, iOS 18.4, *)
    @MainActor
    func testRestoredClassicWorkerStartsWithoutOpeningAPopup() async throws {
        try await probeRestoredWorkerStartup(isModule: false)
    }

    @available(macOS 15.4, iOS 18.4, *)
    @MainActor
    func testRestoredModuleWorkerStartsWithoutOpeningAPopup() async throws {
        try await probeRestoredWorkerStartup(isModule: true)
    }

    @available(macOS 15.4, iOS 18.4, *)
    @MainActor
    private func probeRestoredWorkerStartup(isModule: Bool) async throws {
        let directory = try makeExtensionDirectory(manifest: """
        { "manifest_version": 3, "name": "Restored Worker", "version": "1.0",
          "permissions": ["nativeMessaging"],
          "action": { "default_title": "Restored Worker" },
          "background": { "service_worker": "worker.js"\(isModule ? ", \"type\": \"module\"" : "") } }
        """)
        try """
        chrome.runtime.onStartup.addListener(function() {});
        chrome.action.onClicked.addListener(function() {
            chrome.runtime.sendNativeMessage('worker.probe', { phase: 'clicked' }).catch(function() {});
        });
        chrome.runtime.sendNativeMessage('worker.probe', { phase: 'started' }).catch(function() {});
        """
            .write(to: directory.appendingPathComponent("worker.js"), atomically: true, encoding: .utf8)
        let storage = ExtensionsDirectoryStorage(extensionsDirectory: temporaryDirectory.appendingPathComponent("restored"))
        let identifier = UUID().uuidString
        _ = try storage.copyExtension(from: directory, identifier: identifier)
        let controllerIdentifier = UUID()

        for phase in ["first load", "restart"] {
            let started = expectation(description: "\(phase): restored worker runs without an action click")
            let clicked = expectation(description: "\(phase): toolbar action reaches the worker")
            let delegate = WorkerProbeDelegate { message in
                switch (message as? [String: Any])?["phase"] as? String {
                case "started": started.fulfill()
                case "clicked": clicked.fulfill()
                default: break
                }
            }
            let controller = WKWebExtensionController(configuration: .init(identifier: controllerIdentifier))
            controller.delegate = delegate
            let loader = WebExtensionLoader(storageProvider: storage)
            _ = try await loader.loadWebExtension(identifier: identifier, into: controller)
            await fulfillment(of: [started], timeout: 10)
            let context = try XCTUnwrap(controller.extensionContexts.first)
            XCTAssertNotNil((context.webExtension.manifest["background"] as? [String: Any])?["service_worker"])
            context.performAction(for: nil)
            await fulfillment(of: [clicked], timeout: 10)
            try controller.unloadCopyingErrors(context)
            withExtendedLifetime((loader, delegate)) {}
        }
    }

    @available(macOS 15.4, iOS 18.4, *)
    @MainActor
    func testClassicWorkerWithoutNativePermissionRelaysErrorsThroughAnExtensionPage() async throws {
        try await probeWorkerReportRelay(isModule: false)
    }

    @available(macOS 15.4, iOS 18.4, *)
    @MainActor
    func testModuleWorkerWithoutNativePermissionRelaysErrorsThroughAnExtensionPage() async throws {
        try await probeWorkerReportRelay(isModule: true)
    }

    @available(macOS 15.4, iOS 18.4, *)
    @MainActor
    private func probeWorkerReportRelay(isModule: Bool) async throws {
        let directory = try makeExtensionDirectory(manifest: """
        { "manifest_version": 3, "name": "Worker Report Relay", "version": "1.0",
          "background": { "service_worker": "worker.js"\(isModule ? ", \"type\": \"module\"" : "") } }
        """)
        try "console.error(new TypeError('Symbol.dispose is not defined.'));"
            .write(to: directory.appendingPathComponent("worker.js"), atomically: true, encoding: .utf8)
        try "<!doctype html><title>Report relay</title>"
            .write(to: directory.appendingPathComponent("relay.html"), atomically: true, encoding: .utf8)
        XCTAssertTrue(WebExtensionBackgroundPagePatcher().patchIfNeeded(installedExtensionURL: directory))
        let bundle = try await WKWebExtension.makeCopyingErrors(at: directory)
        let context = WKWebExtensionContext(for: bundle)
        let reported = expectation(description: "Worker API error reaches the host without native messaging permission")
        let reporter = WebExtensionAPICompatibilityReporter { line in
            XCTAssertEqual(line, "missing js:Symbol.dispose ext=Worker Report Relay v=1.0")
            reported.fulfill()
        }
        let handler = WebExtensionAPICompatibilityMessageHandler(reporter: reporter)
        handler.resolveExtension = { _ in ("Worker Report Relay", "1.0") }
        let configuration = WKWebExtensionController.Configuration.nonPersistent()
        configuration.webViewConfiguration.userContentController.addUserScript(WKUserScript(
            source: WebExtensionAPICompatibilityScript.source, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        configuration.webViewConfiguration.userContentController.add(handler, name: WebExtensionAPICompatibilityScript.messageHandlerName)
        let controller = WKWebExtensionController(configuration: configuration)
        try controller.loadCopyingErrors(context)
        defer { try? controller.unloadCopyingErrors(context) }
        try await context.loadBackgroundContentCopyingErrors()
        let page = WKWebView(frame: .zero, configuration: try XCTUnwrap(context.webViewConfiguration))
        page.load(URLRequest(url: context.baseURL.appendingPathComponent("relay.html")))
        await fulfillment(of: [reported], timeout: 10)
        withExtendedLifetime((page, handler)) {}
    }

    @available(macOS 15.4, iOS 18.4, *)
    @MainActor
    func testInstalledExtensionLifecycleAndTabMatrix() async throws {
        guard let path = ProcessInfo.processInfo.environment["DDG_WORKER_PROBE_EXTENSION"] else {
            throw XCTSkip("Set TEST_RUNNER_DDG_WORKER_PROBE_EXTENSION to probe an installed extension bundle.")
        }
        let directory = temporaryDirectory.appendingPathComponent("matrix-extension")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: directory)
        let configuration = WebExtensionConfigurationProvidingMock()
        configuration.applicationNameForUserAgent = "Chrome/140.0.0.0"
        let window = WorkerProbeWindow()
        let provider = window
#if os(macOS)
        let popupHost = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 900, height: 600),
                                 styleMask: [.titled], backing: .buffered, defer: false)
        popupHost.title = "Bitwarden worker presentation test"
        let anchor = NSButton(frame: NSRect(x: 700, y: 550, width: 30, height: 30))
        popupHost.contentView?.addSubview(anchor)
        popupHost.orderFront(nil)
        defer { popupHost.orderOut(nil) }
        provider.onPresentPopup = { action in
            XCTAssertNotNil(action.popupPopover)
            action.popupPopover?.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
        }
#endif
        let manager = WebExtensionManager(
            configuration: configuration,
            windowTabProvider: provider,
            storageProvider: WebExtensionStorageProvider(extensionsDirectory: temporaryDirectory.appendingPathComponent("installed")),
            installationStore: InstalledWebExtensionStoringMock())
        let webViewConfiguration = WKWebViewConfiguration()
        webViewConfiguration.webExtensionController = manager.controller
        window.tab.view = WKWebView(frame: .zero, configuration: webViewConfiguration)
        window.tab.view?.loadHTMLString("<!doctype html><title>Worker probe tab</title>", baseURL: URL(string: "https://example.com"))
        try await manager.installExtension(from: directory)
        defer { manager.unloadAllExtensions() }
        manager.controller.didOpenWindow(window)
        let identifier = try XCTUnwrap(manager.loadedExtensions.first?.uniqueIdentifier)

        for phase in ["fresh", "reload", "idle"] {
            if phase == "reload" {
                manager.unloadAllExtensions()
                await manager.loadInstalledExtensions()
            } else if phase == "idle" {
                // Allow WebKit's observed 30-second background idle interval to elapse.
                try await Task.sleep(for: .seconds(35))
            }
            let context = try XCTUnwrap(manager.loadedExtensions.first { $0.uniqueIdentifier == identifier })
            try await context.loadBackgroundContentCopyingErrors()
            try await Task.sleep(for: .seconds(1))
            for selectedTab in [false, true] {
                let tab: (any WKWebExtensionTab)? = selectedTab ? window.tab : nil
                let label = "WORKER_MATRIX \(phase), \(selectedTab ? "selected-tab" : "default")"
                provider.presentPopupCalled = false
                context.performAction(for: tab)
                let deadline = Date().addingTimeInterval(15)
                while !provider.presentPopupCalled && Date() < deadline {
                    try await Task.sleep(for: .milliseconds(100))
                }
                let errors = context.errors.map { NSError.webKitSafe($0).localizedDescription }
                XCTContext.runActivity(named: "\(label): popup=\(provider.presentPopupCalled), errors=\(errors)") { _ in }
                XCTAssertTrue(provider.presentPopupCalled, label)
                guard provider.presentPopupCalled else { continue }
                let action = try XCTUnwrap(context.action(for: tab))
                let webView = try XCTUnwrap(action.popupWebView)
#if os(macOS)
                XCTAssertEqual(action.popupPopover?.isShown, true, label)
                XCTAssertNotNil(webView.window, label)
#endif
                let document = expectation(description: "\(label): popup document completes")
                webView.evaluateJavaScript("JSON.stringify({href:location.href,ready:document.readyState})") { result, error in
                    XCTContext.runActivity(named: "\(label): document=\(String(describing: result)), error=\(String(describing: error))") { _ in }
                    XCTAssertNil(error, label)
                    XCTAssertTrue((result as? String)?.contains("/popup/index.html") == true, label)
                    document.fulfill()
                }
                await fulfillment(of: [document], timeout: 15)
                action.closePopup()
            }
        }
    }

    @available(macOS 15.4, iOS 18.4, *)
    @MainActor
    func testInstalledExtensionWorkerStartup() async throws {
        guard let path = ProcessInfo.processInfo.environment["DDG_WORKER_PROBE_EXTENSION"] else {
            throw XCTSkip("Set TEST_RUNNER_DDG_WORKER_PROBE_EXTENSION to probe an installed extension bundle.")
        }
        let directory = temporaryDirectory.appendingPathComponent("installed-extension")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: directory)
        let background = try backgroundSection(in: directory)
        XCTAssertNil(background["type"])
        let wrapperURL = directory.appendingPathComponent("ddg-service-worker.js")
        let originalWrapper = try String(contentsOf: wrapperURL, encoding: .utf8)
        let diagnostics = """
        const probeAPI = globalThis.browser || globalThis.chrome;
        function workerProbeReport(phase, error) {
            probeAPI.runtime.sendNativeMessage("worker.probe", {
                phase, message: String(error && error.message || error || ""),
                stack: String(error && error.stack || "")
            }).catch(function() {});
        }
        self.addEventListener("error", function(event) { workerProbeReport("error", event.error || event.message); });
        self.addEventListener("unhandledrejection", function(event) { workerProbeReport("rejection", event.reason); });
        workerProbeReport("user-agent", navigator.userAgent);
        try {
        \(originalWrapper)
        } catch (error) {
            workerProbeReport("startup-error", error);
        }
        workerProbeReport("loaded", null);
        """
        try diagnostics.write(to: wrapperURL, atomically: true, encoding: .utf8)

        let bundle = try await WKWebExtension.makeCopyingErrors(at: directory)
        let context = WKWebExtensionContext(for: bundle)
        context.setPermissionStatus(.grantedExplicitly, for: .nativeMessaging)
        for permission in bundle.requestedPermissions {
            context.setPermissionStatus(.grantedExplicitly, for: permission)
        }
        for pattern in bundle.allRequestedMatchPatterns {
            context.setPermissionStatus(.grantedExplicitly, for: pattern)
        }
        let loaded = expectation(description: "Installed extension worker imports complete")
        let popup = expectation(description: "Installed extension action reaches the popup delegate")
        let popupDocument = expectation(description: "Installed extension popup document can execute JavaScript")
        var errors: [String] = []
        let delegate = WorkerProbeDelegate { message in
            guard let payload = message as? [String: Any], let phase = payload["phase"] as? String else { return }
            let details = "\(phase): \(payload["message"] ?? "") \(payload["stack"] ?? "")"
            XCTContext.runActivity(named: "INSTALLED_WORKER_PROBE \(details)") { _ in }
            if phase == "loaded" {
                loaded.fulfill()
            } else if phase != "user-agent" {
                errors.append(details)
            }
        }
        let configuration = WKWebExtensionController.Configuration.nonPersistent()
        configuration.webViewConfiguration.applicationNameForUserAgent = "Chrome/140.0.0.0"
        let controller = WKWebExtensionController(configuration: configuration)
        delegate.presentPopup = { action in
            XCTContext.runActivity(named: "INSTALLED_WORKER_PROBE popup: presents=\(action.presentsPopup), webView=\(action.popupWebView != nil)") { _ in }
            action.popupWebView?.evaluateJavaScript("JSON.stringify({ready:document.readyState,href:location.href})") { result, error in
                XCTContext.runActivity(named: "INSTALLED_WORKER_PROBE popup document: \(String(describing: result)), error=\(String(describing: error))") { _ in }
                popupDocument.fulfill()
            }
            popup.fulfill()
        }
        controller.delegate = delegate
        try controller.loadCopyingErrors(context)
        defer { try? controller.unloadCopyingErrors(context) }
        context.loadBackgroundContent { error in
            if let error {
                XCTContext.runActivity(named: "INSTALLED_WORKER_PROBE background load: \(error)") { _ in }
            }
        }
        await fulfillment(of: [loaded], timeout: 15)
        try await Task.sleep(for: .seconds(2))
        context.performAction(for: nil)
        await fulfillment(of: [popup], timeout: 10)
        await fulfillment(of: [popupDocument], timeout: 10)
        let contextErrors = context.errors.map { NSError.webKitSafe($0).localizedDescription }
        XCTContext.runActivity(named: "INSTALLED_WORKER_PROBE context errors: \(contextErrors)") { _ in }
        XCTAssertTrue(errors.isEmpty, "Worker startup errors: \(errors)")
        withExtendedLifetime(delegate) {}
    }

    func testWhenWorkerModeChanges_ThenTheLoadableCopyIsRebuilt() throws {
        let archive = try makeArchive(files: [
            "manifest.json": """
            {
                "manifest_version": 3,
                "name": "Worker Probe",
                "version": "1.0",
                "background": { "service_worker": "worker.js" }
            }
            """,
            "worker.js": "// Worker probe"
        ])
        let workerPatcher = WebExtensionBackgroundPagePatcher()
        let workerURL = workerPatcher.loadableExtensionURL(for: archive, installFolder: installFolder(of: archive))
        XCTAssertEqual(try backgroundSection(in: workerURL)["service_worker"] as? String, "ddg-service-worker.js")

        let pageURL = patcher.loadableExtensionURL(for: archive, installFolder: installFolder(of: archive))
        XCTAssertEqual(try backgroundSection(in: pageURL)["page"] as? String, WebExtensionBackgroundPagePatcher.backgroundPageFilename)

        let reloadedWorkerURL = workerPatcher.loadableExtensionURL(for: archive, installFolder: installFolder(of: archive))
        XCTAssertEqual(try backgroundSection(in: reloadedWorkerURL)["service_worker"] as? String, "ddg-service-worker.js")
        XCTAssertNil(try backgroundSection(in: reloadedWorkerURL)["page"])
    }

    @available(macOS 15.4, iOS 18.4, *)
    @MainActor
    func testClassicWorkerWrapperStartsAndRepliesThroughNativeMessaging() async throws {
        try await probeWorkerWrapper(isModule: false)
    }

    @available(macOS 15.4, iOS 18.4, *)
    @MainActor
    func testModuleWorkerWrapperStartsAndRepliesThroughNativeMessaging() async throws {
        try await probeWorkerWrapper(isModule: true)
    }

    @available(macOS 15.4, iOS 18.4, *)
    @MainActor
    private func probeWorkerWrapper(isModule: Bool) async throws {
        let directory = try makeExtensionDirectory(manifest: """
        {
            "manifest_version": 3,
            "name": "Worker Probe",
            "description": "Validates real WebKit extension service workers.",
            "version": "1.0",
            "permissions": ["nativeMessaging"],
            "action": { "default_popup": "popup.html" },
            "background": { "service_worker": "worker.js"\(isModule ? ", \"type\": \"module\"" : "") }
        }
        """)
        let worker = """
        (async function() {
            const api = globalThis.chrome || globalThis.browser;
            api.runtime.onMessage.addListener(function(message, sender, sendResponse) {
                sendResponse({ echo: message.probe, worker: true });
            });
            api.runtime.onConnect.addListener(function(port) {
                port.onMessage.addListener(function(message) {
                    port.postMessage({ echo: message.probe, worker: true, port: true });
                });
            });
            \(ProcessInfo.processInfo.environment["DDG_WORKER_PROBE_WEBSOCKET"] == "1"
              ? "globalThis.workerProbeSocket = new WebSocket('wss://127.0.0.1:65534');" : "")
            const report = {
                worker: typeof ServiceWorkerGlobalScope !== "undefined" && self instanceof ServiceWorkerGlobalScope,
                clients: typeof clients,
                imported: globalThis.workerProbeImported === true,
                stub: typeof api.notifications.onClicked.addListener,
                pageBridge: !!(globalThis.webkit && globalThis.webkit.messageHandlers),
                document: typeof document
            };
            const pageHandler = globalThis.webkit && globalThis.webkit.messageHandlers
                && globalThis.webkit.messageHandlers.workerProbe;
            if (pageHandler) {
                report.pageBridgeReply = await pageHandler.postMessage({ probe: true });
            }
            try {
                report.clientCount = (await clients.matchAll()).length;
            } catch (error) {
                report.clientsError = String(error);
            }
            try {
                await api.offscreen.createDocument({ url: "offscreen.html", reasons: ["CLIPBOARD"], justification: "Worker probe" });
            } catch (error) {
                report.offscreenError = String(error);
            }
            try {
                const database = await new Promise(function(resolve, reject) {
                    const open = indexedDB.open("ddg-worker-storage-probe", 1);
                    open.onupgradeneeded = function() { open.result.createObjectStore("records"); };
                    open.onsuccess = function() { resolve(open.result); };
                    open.onerror = function() { reject(open.error); };
                });
                const write = database.transaction("records", "readwrite");
                const committed = new Promise(function(resolve, reject) {
                    write.oncomplete = resolve;
                    write.onabort = function() { reject(write.error); };
                });
                write.objectStore("records").put({ ok: true }, "probe");
                await committed;
                report.indexedDB = await new Promise(function(resolve, reject) {
                    const read = database.transaction("records").objectStore("records").get("probe");
                    read.onsuccess = function() { resolve(read.result.ok); };
                    read.onerror = function() { reject(read.error); };
                });
                const cancelled = database.transaction("records", "readwrite");
                const aborted = new Promise(function(resolve) { cancelled.onabort = resolve; });
                cancelled.abort();
                await aborted;
                const probe = globalThis.__ddgWorkerPortProbeInstalled;
                report.abortDiagnosed = !!probe && probe.events.some(function(event) {
                    return event.event === "indexedDB.transaction-aborted" && !event.detail.includes("ddg-worker-storage-probe");
                });
                database.close();
            } catch (error) {
                report.indexedDBError = error.name;
            }
            const reply = await api.runtime.sendNativeMessage("worker.probe", { phase: "started", report });
            await api.runtime.sendNativeMessage("worker.probe", { phase: "roundtrip", echo: reply.echo });
        })();
        """
        let imported = "globalThis.workerProbeImported = true;"
        try "<!doctype html><html><body>Worker messaging probe</body></html>".write(
            to: directory.appendingPathComponent("popup.html"), atomically: true, encoding: .utf8)
        try imported.write(to: directory.appendingPathComponent("chunk.js"), atomically: true, encoding: .utf8)
        let importLine = isModule ? "import './chunk.js';\n" : "importScripts('chunk.js');\n"
        try (importLine + worker).write(to: directory.appendingPathComponent("worker.js"), atomically: true, encoding: .utf8)
        let workerPatcher = WebExtensionBackgroundPagePatcher(useServiceWorkerWrapper: true)
        XCTAssertTrue(workerPatcher.patchIfNeeded(installedExtensionURL: directory))
        let background = try backgroundSection(in: directory)
        XCTAssertEqual(background["service_worker"] as? String, "ddg-service-worker.js")
        XCTAssertNil(background["page"])

        let extensionBundle = try await WKWebExtension.makeCopyingErrors(at: directory)
        let context = WKWebExtensionContext(for: extensionBundle)
        context.isInspectable = true
        context.setPermissionStatus(.grantedExplicitly, for: .nativeMessaging)
        let roundtrip = expectation(description: "\(isModule ? "Module" : "Classic") worker native-message round trip")
        let delegate = WorkerProbeDelegate { message in
            guard let payload = message as? [String: Any] else {
                XCTFail("Unexpected worker message")
                return
            }
            if payload["phase"] as? String == "started" {
                let report = payload["report"] as? [String: Any] ?? [:]
                XCTContext.runActivity(named: "WORKER_PROBE \(isModule ? "module" : "classic"): \(report)") { _ in }
                XCTAssertEqual(report["worker"] as? Bool, true)
                XCTAssertEqual(report["clients"] as? String, "object")
                XCTAssertNotNil(report["clientCount"] as? Int)
                XCTAssertEqual(report["imported"] as? Bool, true)
                XCTAssertEqual(report["stub"] as? String, "function")
                XCTAssertEqual(report["document"] as? String, "undefined")
                XCTAssertEqual(report["indexedDB"] as? Bool, true, "Worker storage error: \(report["indexedDBError"] ?? "none")")
#if DEBUG
                XCTAssertEqual(report["abortDiagnosed"] as? Bool, true)
#endif
                if report["pageBridge"] as? Bool == true {
                    XCTAssertEqual(report["pageBridgeReply"] as? String, "page-bridge-reply")
                }
            } else if payload["phase"] as? String == "roundtrip" {
                XCTAssertEqual(payload["echo"] as? String, "worker-probe-reply")
                roundtrip.fulfill()
            }
        }
        let configuration = WKWebExtensionController.Configuration.nonPersistent()
        configuration.webViewConfiguration.userContentController.addScriptMessageHandler(delegate, contentWorld: .page, name: "workerProbe")
        let controller = WKWebExtensionController(configuration: configuration)
        controller.delegate = delegate
        try controller.loadCopyingErrors(context)
        defer { try? controller.unloadCopyingErrors(context) }
        let popupRoundtrip = expectation(description: "Popup receives a reply from the worker")
        delegate.presentPopup = { action in
            guard let webView = action.popupWebView else {
                XCTFail("Worker probe popup has no web view")
                popupRoundtrip.fulfill()
                return
            }
            Task { @MainActor in
                do {
                    let reply = try await webView.callAsyncJavaScript(
                        """
                        const api = globalThis.chrome || globalThis.browser;
                        await api.runtime.sendMessage({ probe: "popup-to-worker" });
                        const port = api.runtime.connect({ name: "worker-probe" });
                        return await new Promise(function(resolve, reject) {
                            const timer = setTimeout(function() { reject(new Error("Worker port reply timed out")); }, 5000);
                            port.onMessage.addListener(function(reply) {
                                clearTimeout(timer);
                                resolve(reply);
                                port.disconnect();
                            });
                            port.onDisconnect.addListener(function() {
                                clearTimeout(timer);
                                reject(new Error(api.runtime.lastError?.message || "Worker port disconnected"));
                            });
                            port.postMessage({ probe: "popup-to-worker" });
                        });
                        """,
                        arguments: [:], in: nil, contentWorld: .page)
                    let payload = reply as? [String: Any]
                    XCTAssertEqual(payload?["echo"] as? String, "popup-to-worker")
                    XCTAssertEqual(payload?["worker"] as? Bool, true)
                    XCTAssertEqual(payload?["port"] as? Bool, true)
                } catch {
                    XCTFail("Popup-to-worker messaging failed: \(error)")
                }
                popupRoundtrip.fulfill()
            }
        }
        context.performAction(for: nil)
        await fulfillment(of: [roundtrip, popupRoundtrip], timeout: 15)
        let errors = context.errors.map { error in
            let nativeError = NSError.webKitSafe(error)
            return "\(nativeError.domain) \(nativeError.code): \(nativeError.localizedDescription) \(nativeError.userInfo)"
        }
        XCTContext.runActivity(named: "WORKER_PROBE context errors: \(errors)") { _ in }
        XCTAssertTrue(errors.isEmpty, "Unexpected WebKit errors: \(errors)")
        withExtendedLifetime(delegate) {}
    }

    // MARK: - Helpers

    private func assertManifestIsUntouched(_ manifest: String,
                                           file: StaticString = #filePath,
                                           line: UInt = #line) throws {
        let extensionDirectory = try makeExtensionDirectory(manifest: manifest)
        let originalManifest = try Data(contentsOf: manifestURL(in: extensionDirectory))

        XCTAssertFalse(patcher.patchIfNeeded(installedExtensionURL: extensionDirectory), file: file, line: line)

        XCTAssertEqual(try Data(contentsOf: manifestURL(in: extensionDirectory)),
                       originalManifest,
                       file: file,
                       line: line)
        XCTAssertFalse(FileManager.default.fileExists(atPath: backgroundPageURL(in: extensionDirectory).path),
                       file: file,
                       line: line)
        XCTAssertFalse(FileManager.default.fileExists(atPath: importScriptsShimURL(in: extensionDirectory).path),
                       file: file,
                       line: line)
    }

    /// Asserts that `<script src="…">` tags for `sources` appear in the page, in the given order.
    private func assertScriptSources(_ sources: [String],
                                     appearInOrderIn backgroundPage: String,
                                     file: StaticString = #filePath,
                                     line: UInt = #line) {
        var searchStart = backgroundPage.startIndex
        for source in sources {
            guard let range = backgroundPage.range(of: "src=\"\(source)\"", range: searchStart..<backgroundPage.endIndex) else {
                XCTFail("Expected 'src=\"\(source)\"' after position \(backgroundPage.distance(from: backgroundPage.startIndex, to: searchStart)) in:\n\(backgroundPage)",
                        file: file,
                        line: line)
                return
            }
            searchStart = range.upperBound
        }
    }

    private func makeInstallFolder() throws -> URL {
        let installFolder = temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: installFolder, withIntermediateDirectories: true)
        return installFolder
    }

    private func writeFiles(_ files: [String: String], in directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, contents) in files {
            try Data(contents.utf8).write(to: directory.appendingPathComponent(name))
        }
    }

    /// An archive in its own install folder, like the ones the Chrome Web Store flow stores.
    private func makeArchive(files: [String: String]) throws -> URL {
        let archiveURL = try makeInstallFolder().appendingPathComponent("extension.zip")
        let archive = try Archive(url: archiveURL, accessMode: .create)
        for (path, contents) in files.sorted(by: { $0.key < $1.key }) {
            let data = Data(contents.utf8)
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count)) { position, size in
                data.subdata(in: Int(position)..<Int(position) + size)
            }
        }
        return archiveURL
    }

    private func installFolder(of archiveURL: URL) -> URL {
        archiveURL.deletingLastPathComponent()
    }

    private func loadableFolder(of archiveURL: URL) -> URL {
        installFolder(of: archiveURL).appendingPathComponent(WebExtensionBackgroundPagePatcher.loadableFolderName)
    }

    private func makeExtensionDirectory(manifest: String) throws -> URL {
        let directory = temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try write(manifest: manifest, to: directory)
        return directory
    }

    private func write(manifest: String, to directory: URL) throws {
        try manifest.write(to: directory.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
    }

    private func writeFile(named filename: String, in directory: URL) throws {
        try "// \(filename)".write(to: directory.appendingPathComponent(filename), atomically: true, encoding: .utf8)
    }

    private func manifestURL(in directory: URL) -> URL {
        directory.appendingPathComponent("manifest.json")
    }

    private func backgroundPageURL(in directory: URL) -> URL {
        directory.appendingPathComponent(WebExtensionBackgroundPagePatcher.backgroundPageFilename)
    }

    private func loadManifest(in directory: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: manifestURL(in: directory))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func backgroundSection(in directory: URL) throws -> [String: Any] {
        try XCTUnwrap(try loadManifest(in: directory)["background"] as? [String: Any])
    }

    private func loadBackgroundPage(in directory: URL) throws -> String {
        try String(contentsOf: backgroundPageURL(in: directory), encoding: .utf8)
    }

    private func importScriptsShimURL(in directory: URL) -> URL {
        directory.appendingPathComponent(WebExtensionImportScriptsShim.filename)
    }

    private func loadImportScriptsShim(in directory: URL) throws -> String {
        try String(contentsOf: importScriptsShimURL(in: directory), encoding: .utf8)
    }
}

@available(macOS 15.4, iOS 18.4, *)
@MainActor
private final class WorkerProbeDelegate: NSObject, WKWebExtensionControllerDelegate, WKScriptMessageHandlerWithReply {
    let receive: (Any) -> Void
    var presentPopup: ((WKWebExtension.Action) -> Void)?

    init(receive: @escaping (Any) -> Void) {
        self.receive = receive
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                sendMessage message: Any,
                                toApplicationWithIdentifier applicationIdentifier: String?,
                                for extensionContext: WKWebExtensionContext) async throws -> Any? {
        receive(message)
        return ["echo": "worker-probe-reply"]
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        replyHandler("page-bridge-reply", nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                presentActionPopup action: WKWebExtension.Action,
                                for extensionContext: WKWebExtensionContext) async throws {
        presentPopup?(action)
    }
}

@available(macOS 15.4, iOS 18.4, *)
@MainActor
private final class WorkerProbeWindow: NSObject, WKWebExtensionWindow, WebExtensionWindowTabProviding {
    let tab = WorkerProbeTab()
    var presentPopupCalled = false
    var onPresentPopup: ((WKWebExtension.Action) -> Void)?

    override init() {
        super.init()
        tab.hostWindow = self
    }

    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] { [tab] }
    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? { tab }
    func openWindows(for context: WKWebExtensionContext) -> [any WKWebExtensionWindow] { [self] }
    func focusedWindow(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? { self }

    func openNewWindow(using configuration: WKWebExtension.WindowConfiguration,
                       for context: WKWebExtensionContext) async throws -> (any WKWebExtensionWindow)? { nil }

    func openNewTab(using configuration: WKWebExtension.TabConfiguration,
                    for context: WKWebExtensionContext) async throws -> (any WKWebExtensionTab)? { nil }

    func presentPopup(_ action: WKWebExtension.Action, for context: WKWebExtensionContext) async throws {
        onPresentPopup?(action)
        presentPopupCalled = true
    }
}

@available(macOS 15.4, iOS 18.4, *)
@MainActor
private final class WorkerProbeTab: NSObject, WKWebExtensionTab {
    weak var hostWindow: WorkerProbeWindow?
    var view: WKWebView?

    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? { hostWindow }
    func webView(for context: WKWebExtensionContext) -> WKWebView? { view }
    func url(for context: WKWebExtensionContext) -> URL? { URL(string: "https://example.com") }
    func title(for context: WKWebExtensionContext) -> String? { "Worker probe tab" }
}

/// The default storage behavior over a given extensions directory.
@available(macOS 15.4, iOS 18.4, *)
private final class ExtensionsDirectoryStorage: WebExtensionStorageProviding {
    let fileManager = FileManager.default
    let extensionsDirectory: URL

    init(extensionsDirectory: URL) {
        self.extensionsDirectory = extensionsDirectory
    }
}
