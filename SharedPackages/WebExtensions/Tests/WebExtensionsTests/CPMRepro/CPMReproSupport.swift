//
//  CPMReproSupport.swift
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

import Foundation
import WebKit
@testable import WebExtensions

/// Timestamped, thread-safe event log printed to stdout so `swift test` output shows the timeline.
final class CPMReproLog: @unchecked Sendable {

    private let start = Date()
    private let lock = NSLock()
    private(set) var lines: [String] = []

    var elapsed: TimeInterval { Date().timeIntervalSince(start) }

    func add(_ line: String) {
        let stamped = String(format: "[cpm-repro +%7.3fs] ", elapsed) + line
        lock.lock()
        lines.append(stamped)
        lock.unlock()
        FileHandle.standardError.write(Data((stamped + "\n").utf8))
    }
}

/// Records pixels that the real health monitor fires.
@available(macOS 15.4, iOS 18.4, *)
final class CPMReproPixelRecorder: WebExtensionPixelFiring, @unchecked Sendable {

    private let lock = NSLock()
    private let log: CPMReproLog
    private(set) var events: [WebExtensionPixelEvent] = []

    init(log: CPMReproLog) {
        self.log = log
    }

    func fire(_ event: WebExtensionPixelEvent) {
        lock.lock()
        events.append(event)
        lock.unlock()
        log.add("pixel \(event)")
    }

    func count(where predicate: (WebExtensionPixelEvent) -> Bool) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return events.filter(predicate).count
    }
}

/// Forwards to the production autoconsent handler after an optional test interceptor runs.
///
/// The interceptor models a slow or blocked native side (or any action timed to a native message,
/// such as pausing a WebKit process) without changing the production handler.
@available(macOS 15.4, iOS 18.4, *)
final class CPMReproNativeHandler: WebExtensionMessageHandler {

    typealias Interceptor = @MainActor (WebExtensionMessage) async -> Void

    private let inner: WebExtensionMessageHandler
    private let log: CPMReproLog
    var interceptor: Interceptor?

    var handledFeatureName: String { inner.handledFeatureName }

    init(inner: WebExtensionMessageHandler, log: CPMReproLog) {
        self.inner = inner
        self.log = log
    }

    func handleMessage(_ message: WebExtensionMessage) async -> WebExtensionMessageResult {
        let tabId = message.params?["tabId"] ?? "-"
        let url = message.params?["url"] ?? "-"
        log.add("native <- \(message.method) tabId=\(tabId) url=\(url)")
        if let interceptor {
            await interceptor(message)
        }
        return await inner.handleMessage(message)
    }
}

/// Receives `cpmRepro.log` notifications sent by the injected background prelude.
@available(macOS 15.4, iOS 18.4, *)
final class CPMReproJSLogHandler: WebExtensionMessageHandler {

    private let log: CPMReproLog
    var handledFeatureName: String { "cpmRepro" }

    init(log: CPMReproLog) {
        self.log = log
    }

    func handleMessage(_ message: WebExtensionMessage) async -> WebExtensionMessageResult {
        let text = message.params?["message"] as? String ?? message.method
        log.add("bg-js \(text)")
        return .success(["response": "ok"])
    }
}

@available(macOS 15.4, iOS 18.4, *)
final class CPMReproHandlerProvider: WebExtensionHandlerProviding {

    private let makeAutoconsentHandler: () -> WebExtensionMessageHandler
    private let log: CPMReproLog
    private(set) var nativeHandlers: [CPMReproNativeHandler] = []
    var interceptor: CPMReproNativeHandler.Interceptor? {
        didSet { nativeHandlers.forEach { $0.interceptor = interceptor } }
    }

    init(log: CPMReproLog, makeAutoconsentHandler: @escaping () -> WebExtensionMessageHandler) {
        self.log = log
        self.makeAutoconsentHandler = makeAutoconsentHandler
    }

    func makeHandlers(for context: WKWebExtensionContext) -> [WebExtensionMessageHandler] {
        guard context.duckDuckGoWebExtensionType == .embedded else { return [] }
        let handler = CPMReproNativeHandler(inner: makeAutoconsentHandler(), log: log)
        handler.interceptor = interceptor
        nativeHandlers.append(handler)
        return [handler, CPMReproJSLogHandler(log: log)]
    }
}

/// Installs the production extension unchanged unless a background prelude is supplied.
///
/// A prelude is prepended to the background service worker of the installed copy. It can wrap
/// WebExtension APIs to delay or withhold their replies, which models a WebKit reply that is late
/// or never arrives while leaving the CPM code itself untouched.
@available(macOS 15.4, iOS 18.4, *)
final class CPMReproStorageProvider: WebExtensionStorageProviding {

    static let backgroundPath = "public/js/background-embedded.js"
    static let contentPath = "public/js/content-scripts/cpm.js"

    let fileManager: FileManager = .default
    let extensionsDirectory: URL
    var backgroundPrelude: String?

    init(extensionsDirectory: URL) {
        self.extensionsDirectory = extensionsDirectory
    }

    func copyExtension(from sourceURL: URL, identifier: String) throws -> URL {
        guard let backgroundPrelude, sourceURL.pathExtension.lowercased() == "zip" else {
            return try copyExtensionUnchanged(from: sourceURL, identifier: identifier)
        }
        let folder = try extractExtension(from: sourceURL, identifier: identifier)
        let background = folder.appendingPathComponent(Self.backgroundPath)
        let original = try String(contentsOf: background, encoding: .utf8)
        try (backgroundPrelude + "\n" + original).write(to: background, atomically: true, encoding: .utf8)
        let content = folder.appendingPathComponent(Self.contentPath)
        let originalContent = try String(contentsOf: content, encoding: .utf8)
        try (CPMReproPrelude.contentScript + "\n" + originalContent).write(to: content, atomically: true, encoding: .utf8)
        return folder
    }

    private func copyExtensionUnchanged(from sourceURL: URL, identifier: String) throws -> URL {
        let folder = extensionsDirectory.appendingPathComponent(identifier)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(sourceURL.lastPathComponent)
        try fileManager.copyItem(at: sourceURL, to: destination)
        return destination
    }
}

/// Reads WebKit process identifiers and drives real process lifecycle through WebKit test SPI.
@available(macOS 15.4, iOS 18.4, *)
@MainActor
enum CPMReproWebKitSPI {

    static func backgroundWebView(of context: WKWebExtensionContext) -> WKWebView? {
        guard context.responds(to: NSSelectorFromString("_backgroundWebView")) else { return nil }
        return context.value(forKey: "_backgroundWebView") as? WKWebView
    }

    static func processIdentifier(of webView: WKWebView?) -> pid_t? {
        guard let number = webView?.value(forKey: "_webProcessIdentifier") as? NSNumber else { return nil }
        let pid = number.int32Value
        return pid > 0 ? pid : nil
    }

    static func networkProcessIdentifier(of webView: WKWebView?) -> pid_t? {
        let store = webView?.configuration.websiteDataStore
        guard let number = store?.value(forKey: "_networkProcessIdentifier") as? NSNumber else { return nil }
        let pid = number.int32Value
        return pid > 0 ? pid : nil
    }

    /// A fault that WebKit cannot inject must fail the test, not leave it passing without a fault.
    struct SPIUnavailable: Error, CustomStringConvertible {
        let selector: String
        var description: String { "WebKit SPI \(selector) is unavailable; the fault was not injected" }
    }

    static func terminateServiceWorkers(of webView: WKWebView) throws {
        let pool = webView.configuration.processPool
        let selector = NSSelectorFromString("_terminateServiceWorkers")
        guard pool.responds(to: selector) else { throw SPIUnavailable(selector: "_terminateServiceWorkers") }
        _ = pool.perform(selector)
    }

    static func killWebContentProcess(of webView: WKWebView) throws {
        let selector = NSSelectorFromString("_killWebContentProcessAndResetState")
        guard webView.responds(to: selector) else { throw SPIUnavailable(selector: "_killWebContentProcessAndResetState") }
        _ = webView.perform(selector)
    }

    /// Freezes a WebKit process for `duration`, then resumes it. Nothing inside WebKit changes; the
    /// process simply stops being scheduled, as it would under heavy load or OS suspension.
    static func freeze(pid: pid_t, for duration: TimeInterval) async {
        kill(pid, SIGSTOP)
        try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        kill(pid, SIGCONT)
    }
}
