//
//  SubscriptionEventsWakeTests.swift
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

import WebKit
import XCTest
@testable import WebExtensions

/// Checks the WebKit behaviour subscription events depend on: performing a manifest command wakes a non-persistent
/// background that WebKit has unloaded, and the background can then pull queued events.
///
/// It loads a real extension, waits for WebKit to unload its background, which takes 30 seconds of inactivity, then
/// queues an event and performs the command. The extension counts its starts in `storage.session`, so the reply
/// shows whether the event reached a restarted background.
@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class SubscriptionEventsWakeTests: XCTestCase {

    private var extensionDirectory: URL?
    private var controller: WKWebExtensionController?
    private var nativeHost: TestNativeHost?

    override func tearDown() async throws {
        if let controller, let context = controller.extensionContexts.first {
            try? controller.unload(context)
        }
        controller = nil
        nativeHost = nil
        if let extensionDirectory {
            try? FileManager.default.removeItem(at: extensionDirectory)
        }
        try await super.tearDown()
    }

    func testWhenBackgroundIsUnloadedThenPerformingTheEventCommandWakesItToPullEvents() async throws {
        let outbox = WebExtensionEventOutbox()
        let host = TestNativeHost(outbox: outbox)
        nativeHost = host
        let context = try await loadTestExtension(host: host)

        let started = try await host.nextReport(of: "started", timeout: 30)
        XCTAssertEqual(started["starts"] as? Int, 1)

        try await waitForBackgroundToUnload(context)

        outbox.enqueue(WebExtensionSubscriptionEvent(featureName: "test", subscriptionName: "onPing", params: ["n": 1]))
        let command = try XCTUnwrap(context.commands.first { $0.id == WebExtensionSubscriptionEvents.commandIdentifier })
        context.performCommand(command)

        let received = try await host.nextReport(of: "received", timeout: 30)
        XCTAssertEqual(received["starts"] as? Int, 2, "The command should reach a restarted background")
        let events = try XCTUnwrap(received["events"] as? [[String: Any]])
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?["subscriptionName"] as? String, "onPing")
        XCTAssertEqual((events.first?["params"] as? [String: Any])?["n"] as? Int, 1)
    }

    // MARK: - Helpers

    private func loadTestExtension(host: TestNativeHost) async throws -> WKWebExtensionContext {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SubscriptionEventsWakeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        extensionDirectory = directory
        try Self.manifest.write(to: directory.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try Self.backgroundScript.write(to: directory.appendingPathComponent("background.js"), atomically: true, encoding: .utf8)

        let webExtension = try await WKWebExtension(resourceBaseURL: directory)
        let context = WKWebExtensionContext(for: webExtension)
        for permission in webExtension.requestedPermissions {
            context.setPermissionStatus(.grantedExplicitly, for: permission)
        }

        let controller = WKWebExtensionController(configuration: .nonPersistent())
        controller.delegate = host
        self.controller = controller
        try controller.load(context)
        return context
    }

    /// Waits until WebKit unloads the background after its inactivity timeout. Where WebKit exposes the background
    /// web view, this waits for it to go; otherwise it waits out the timeout.
    private func waitForBackgroundToUnload(_ context: WKWebExtensionContext) async throws {
        let selector = NSSelectorFromString("_backgroundWebView")
        guard context.responds(to: selector) else {
            try await Task.sleep(for: .seconds(40))
            return
        }
        let deadline = Date().addingTimeInterval(60)
        while context.value(forKey: "_backgroundWebView") != nil {
            guard Date() < deadline else {
                XCTFail("WebKit did not unload the background within 60 seconds")
                return
            }
            try await Task.sleep(for: .seconds(1))
        }
    }

    /// WebKit wakes service workers and non-persistent background pages through the same path. The embedded extension
    /// uses a service worker, but WebKit does not start service-worker backgrounds in the iOS test process: they fail to
    /// load before running any script. So on iOS the test uses a non-persistent background page instead.
    #if os(iOS)
    private static let background = #"{ "scripts": ["background.js"], "persistent": false }"#
    #else
    private static let background = #"{ "service_worker": "background.js" }"#
    #endif

    private static let manifest = """
    {
        "manifest_version": 3,
        "name": "Subscription Events Wake Test",
        "version": "1.0",
        "background": \(background),
        "permissions": ["nativeMessaging", "storage"],
        "commands": {
            "\(WebExtensionSubscriptionEvents.commandIdentifier)": { "description": "Performed by native when it has events" }
        }
    }
    """

    /// Mirrors the extension's `NativeMessagingTransport`: listen for the command in the first turn, then pull events.
    private static let backgroundScript = """
    const starts = browser.storage.session.get('starts').then(async ({ starts = 0 }) => {
        await browser.storage.session.set({ starts: starts + 1 });
        return starts + 1;
    });
    const report = (method, params) =>
        browser.runtime.sendNativeMessage('test', { context: 'test', featureName: 'test', method, params });

    browser.commands.onCommand.addListener(async (command) => {
        if (command !== '\(WebExtensionSubscriptionEvents.commandIdentifier)') return;
        const reply = await browser.runtime.sendNativeMessage('test', {
            context: 'test',
            featureName: '\(WebExtensionSubscriptionEvents.featureName)',
            method: '\(WebExtensionSubscriptionEvents.drainMethod)',
            id: 'drain',
            params: {},
        });
        await report('received', { starts: await starts, events: reply.result.events });
    });

    starts.then((count) => report('started', { starts: count }));
    """
}

/// Plays the native app: routes the extension's messages like `WebExtensionManager` does, and records the reports
/// the test extension sends to its `test` feature.
@available(macOS 15.4, iOS 18.4, *)
@MainActor
private final class TestNativeHost: NSObject, WKWebExtensionControllerDelegate {

    private let router = WebExtensionMessageRouter()
    private let reports = TestReportHandler()

    init(outbox: WebExtensionEventOutbox) {
        super.init()
        router.registerHandler(SubscriptionEventsWebExtensionMessageHandler(outbox: outbox), for: "")
        router.registerHandler(reports, for: "")
    }

    func nextReport(of method: String, timeout: TimeInterval) async throws -> [String: Any] {
        try await reports.next(method, timeout: timeout)
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                sendMessage message: Any,
                                toApplicationWithIdentifier applicationIdentifier: String?,
                                for extensionContext: WKWebExtensionContext) async throws -> Any? {
        guard let dictionary = message as? [String: Any],
              let featureName = dictionary["featureName"] as? String,
              let method = dictionary["method"] as? String else {
            return nil
        }
        let message = WebExtensionMessage(featureName: featureName,
                                          method: method,
                                          id: dictionary["id"] as? String,
                                          params: dictionary["params"] as? [String: Any],
                                          context: dictionary["context"] as? String,
                                          extensionIdentifier: "")
        switch await router.routeMessage(message) {
        case .success(let result):
            return ["featureName": featureName, "result": result ?? [:]]
        case .failure, .noHandler:
            return nil
        }
    }
}

/// Collects `test.<method>` reports from the extension and hands them to the test in order.
@available(macOS 15.4, iOS 18.4, *)
@MainActor
private final class TestReportHandler: WebExtensionMessageHandler {

    private var received: [(method: String, params: [String: Any])] = []

    nonisolated var handledFeatureName: String { "test" }

    nonisolated func handleMessage(_ message: WebExtensionMessage) async -> WebExtensionMessageResult {
        let params = message.params ?? [:]
        await record(message.method, params)
        return .success(nil)
    }

    private func record(_ method: String, _ params: [String: Any]) {
        received.append((method, params))
    }

    func next(_ method: String, timeout: TimeInterval) async throws -> [String: Any] {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if let index = received.firstIndex(where: { $0.method == method }) {
                return received.remove(at: index).params
            }
            guard Date() < deadline else {
                throw MissingReport(method: method, timeout: timeout)
            }
            try await Task.sleep(for: .milliseconds(100))
        }
    }
}

private struct MissingReport: LocalizedError {
    let method: String
    let timeout: TimeInterval

    var errorDescription: String? {
        "No '\(method)' report from the extension within \(Int(timeout)) seconds"
    }
}
