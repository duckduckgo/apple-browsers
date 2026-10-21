//
//  CPMAppIntegrationSupport.swift
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

import Combine
import Foundation
import ObjectiveC
import FeatureFlags_macOS
import PrivacyConfig
@testable import WebExtensions
import WebKit
import XCTest

@testable import DuckDuckGo_Privacy_Browser

#if DEBUG
@available(macOS 15.4, *)
@MainActor
final class CPMAppDiagnosticFlags: CPMDiagnosticsFeatureFlagsProviding {
    let featureFlagger: MockFeatureFlagger
    init(featureFlagger: MockFeatureFlagger) { self.featureFlagger = featureFlagger }
    var isBackgroundDelegateProxyEnabled: Bool { featureFlagger.isFeatureOn(FeatureFlag.cpmBackgroundDelegateProxy) }
    var isBackgroundGraveyardTreatmentEnabled: Bool { false }
    var updatesPublisher: AnyPublisher<Void, Never> { featureFlagger.updatesPublisher }
}

/// Captures the events produced by the real monitor/recorder, before PixelKit's daily deduplication.
@available(macOS 15.4, *)
final class CPMAppPixelRecorder: WebExtensionPixelFiring, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [WebExtensionPixelEvent] = []

    func fire(_ event: WebExtensionPixelEvent) {
        lock.lock()
        recorded.append(event)
        lock.unlock()
        if let metadata = CPMWebExtensionPixelMetadata(event: event) {
            print("CPM APP PIXEL \(metadata.name) \(metadata.parameters)")
        }
    }

    var events: [WebExtensionPixelEvent] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    var episodes: [CPMMessagingEpisodeReport] {
        events.compactMap {
            guard case .cpmMessagingEpisode(let report) = $0 else { return nil }
            return report
        }
    }

}

/// Records the real monitor's first-failure snapshot; terminal episode pixels arrive only on response/deadline.
@available(macOS 15.4, *)
@MainActor
final class CPMAppFailureRecorder: CPMMessagingDiagnosticsProviding {
    let recorder: CPMMessagingDiagnosticsRecorder
    private(set) var failures: [[String: String]] = []

    init(recorder: CPMMessagingDiagnosticsRecorder) { self.recorder = recorder }

    func collectDiagnostics(tabIdentifier: String) -> CPMMessagingDiagnostics {
        let diagnostics = autoreleasepool { recorder.collectDiagnostics(tabIdentifier: tabIdentifier) }
        failures.append(diagnostics.appEvidence)
        return diagnostics
    }

}

@available(macOS 15.4, *)
@MainActor
final class CPMAppNativeRecorder {
    struct Arrival {
        let method: String
        let url: String?
    }

    private(set) var arrivals: [Arrival] = []
    private(set) var forwardedDashboardURLs: Set<String> = []

    func intercept(_ message: WebExtensionMessage) async -> Bool {
        arrivals.append(Arrival(method: message.method,
                                url: message.params?["url"] as? String))
        return message.method == "sendPixel"
    }

    func forgetDashboard(for url: URL) {
        forwardedDashboardURLs.remove(url.absoluteString)
    }

    func didForward(_ message: WebExtensionMessage) {
        if message.method == "refreshCpmDashboardState", let url = message.params?["url"] as? String {
            forwardedDashboardURLs.insert(url)
        }
    }
}

@available(macOS 15.4, *)
final class CPMAppNativeHandler: WebExtensionMessageHandler {
    private let inner: WebExtensionMessageHandler
    private let native: CPMAppNativeRecorder

    init(_ inner: WebExtensionMessageHandler, native: CPMAppNativeRecorder) {
        self.inner = inner
        self.native = native
    }

    var handledFeatureName: String { inner.handledFeatureName }

    func handleMessage(_ message: WebExtensionMessage) async -> WebExtensionMessageResult {
        if await native.intercept(message) {
            return .success(["response": "ok"])
        }
        let result = await inner.handleMessage(message)
        if case .success = result {
            await native.didForward(message)
        }
        return result
    }
}

/// The real provider creates the native handler; the wrapper records successful replies and isolates pixel transport.
@available(macOS 15.4, *)
@MainActor
final class CPMAppHandlerProvider: WebExtensionHandlerProviding {
    let production: WebExtensionHandlerProvider
    let native: CPMAppNativeRecorder

    init(production: WebExtensionHandlerProvider, native: CPMAppNativeRecorder) {
        self.production = production
        self.native = native
    }

    func makeHandlers(for context: WKWebExtensionContext) -> [WebExtensionMessageHandler] {
        production.makeHandlers(for: context).map { CPMAppNativeHandler($0, native: native) }
    }
}

@available(macOS 15.4, *)
final class CPMAppInstallationStore: InstalledWebExtensionStoring {
    private(set) var installedExtensions: [InstalledWebExtension] = []

    func markInstalledVersionAsOutdated() {
        installedExtensions = installedExtensions.map {
            InstalledWebExtension(uniqueIdentifier: $0.uniqueIdentifier, filename: $0.filename,
                                  name: $0.name, version: "2000.1.1", embeddedType: $0.embeddedType,
                                  storeIdentity: $0.storeIdentity)
        }
    }

    func add(_ extension: InstalledWebExtension) {
        installedExtensions.append(`extension`)
    }

    func remove(uniqueIdentifier: String) {
        installedExtensions.removeAll { $0.uniqueIdentifier == uniqueIdentifier }
    }

    func installedExtension(withUniqueIdentifier identifier: String) -> InstalledWebExtension? {
        installedExtensions.first { $0.uniqueIdentifier == identifier }
    }
}

/// All injected code is confined to an extracted copy in this test's own directory.
@available(macOS 15.4, *)
final class CPMAppExtensionStorage: WebExtensionStorageProviding {
    let fileManager = FileManager.default
    let extensionsDirectory: URL
    var startupDelayMilliseconds = 0

    init(directory: URL) {
        extensionsDirectory = directory
    }

    func resolveInstalledExtension(identifier: String) -> URL? {
        let production = WebExtensionStorageProvider(extensionsDirectory: extensionsDirectory)
        let result = production.resolveInstalledExtension(identifier: identifier)
        if result == nil {
            let folder = extensionsDirectory.appendingPathComponent(identifier)
            let exists = fileManager.fileExists(atPath: folder.path)
            print("CPM APP STORAGE MISSING \(identifier) folderExists=\(exists) rootExists=\(fileManager.fileExists(atPath: extensionsDirectory.path))")
        }
        return result
    }

    func copyExtension(from sourceURL: URL, identifier: String) throws -> URL {
        try extractExtension(from: sourceURL, identifier: identifier)
    }

    func extractExtension(from sourceURL: URL, identifier: String) throws -> URL {
        let production = WebExtensionStorageProvider(extensionsDirectory: extensionsDirectory)
        let folder = try production.extractExtension(from: sourceURL, identifier: identifier)
        let background = folder.appendingPathComponent("public/js/background-embedded.js")
        let content = folder.appendingPathComponent("public/js/content-scripts/cpm.js")
        let delay = startupDelayMilliseconds > 0
            ? "const until = Date.now() + \(startupDelayMilliseconds); while (Date.now() < until) {};\n"
            : ""
        let backgroundSource = try String(contentsOf: background, encoding: .utf8)
        let storageProbe = #"""
        (globalThis.browser || globalThis.chrome).runtime.onMessage.addListener((message, sender, reply) => {
            if (!message.cpmAppStorage) return;
            const { key, value } = message.cpmAppStorage;
            const storage = (globalThis.browser || globalThis.chrome).storage.local;
            (async () => {
                if (value !== undefined) await storage.set({ [key]: value });
                return (await storage.get(key))[key] ?? null;
            })().then(value => reply({ value }));
            return true;
        });
        """#
        try (delay + storageProbe + "\n" + backgroundSource).write(to: background, atomically: true, encoding: .utf8)
        let contentSource = try String(contentsOf: content, encoding: .utf8)
        let initResponseCase = "case \"initResp\":"
        guard contentSource.components(separatedBy: initResponseCase).count == 2 else {
            throw NSError(domain: "CPMResearchInstrumentation", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Expected exactly one production initResp handler"])
        }
        let observedContent = contentSource.replacingOccurrences(
            of: initResponseCase,
            with: initResponseCase + "\n globalThis.__cpmAppInitResponseObserved?.();"
        )
        try (CPMAppIntegrationBridge.content + "\n" + observedContent).write(to: content, atomically: true, encoding: .utf8)
        print("CPM APP INSTRUMENTED \(folder.path)")
        return folder
    }
}

@available(macOS 15.4, *)
@MainActor
enum CPMAppWebKit {
    static func background(_ context: WKWebExtensionContext?) -> WKWebView? {
        autoreleasepool {
            guard let context, context.responds(to: NSSelectorFromString("_backgroundWebView")) else { return nil }
            return context.value(forKey: "_backgroundWebView") as? WKWebView
        }
    }

    static func process(_ webView: WKWebView?) -> Int32? {
        autoreleasepool {
            let identifier = (webView?.value(forKey: "_webProcessIdentifier") as? NSNumber)?.int32Value
            return identifier.flatMap { $0 > 0 ? $0 : nil }
        }
    }

    static func network(_ webView: WKWebView?) -> Int32? {
        autoreleasepool {
            let identifier = (webView?.configuration.websiteDataStore.value(forKey: "_networkProcessIdentifier") as? NSNumber)?.int32Value
            return identifier.flatMap { $0 > 0 ? $0 : nil }
        }
    }

}

// Raw local evidence, independent of the privacy allowlist used by production episode pixels.
extension CPMMessagingDiagnostics {
    var appEvidence: [String: String] {
        var result = backgroundLoadParameters
        let facts: [String: Bool?] = ["context_loaded": extensionContextLoaded, "bg_view_alive": backgroundWebViewAlive,
                                      "bg_process_alive": backgroundWebProcessAlive, "tab_in_context": tabKnownToWebKit,
                                      "handler_registered": nativeMessageHandlerRegistered, "tab_controller_match": tabControllerMatchesContext,
                                      "tab_has_ext_scripts": tabHasExtensionUserScripts]
        for (name, value) in facts { result[name] = value.map(String.init) }
        result["bg_events"] = backgroundEvents.map(\.token).joined(separator: ">")
        return result
    }
}

/// Observes the real WebKit migration call without delaying it or changing its arguments/completion.
@available(macOS 15.4, *)
@MainActor
final class CPMAppOriginMigrationRecorder {
    private typealias Migration = @convention(c) (AnyObject, Selector, NSURL, NSURL, NSSet, AnyObject) -> Void
    private let method: Method
    private let original: IMP
    private var replacement: IMP?
    private(set) var migrations: [[String: String]] = []

    init(storeIdentifier: UUID) throws {
        let selector = NSSelectorFromString("_renameOrigin:to:forDataOfTypes:completionHandler:")
        guard let method = class_getInstanceMethod(WKWebsiteDataStore.self, selector) else {
            throw NSError(domain: "CPMAppOriginMigration", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "This WebKit does not expose the origin-migration observation SPI"])
        }
        self.method = method
        original = method_getImplementation(method)
        let invoke = unsafeBitCast(original, to: Migration.self)
        let block: @convention(block) (WKWebsiteDataStore, NSURL, NSURL, NSSet, AnyObject) -> Void = { [weak self] store, from, to, types, completion in
            MainActor.assumeIsolated {
                if store.identifier == storeIdentifier {
                    self?.migrations.append(["from": from.absoluteString ?? "", "to": to.absoluteString ?? ""])
                }
            }
            invoke(store, selector, from, to, types, completion)
        }
        let replacement = imp_implementationWithBlock(block)
        self.replacement = replacement
        method_setImplementation(method, replacement)
    }

    func stop() {
        guard let replacement else { return }
        method_setImplementation(method, original)
        imp_removeBlock(replacement)
        self.replacement = nil
    }
}

#endif
