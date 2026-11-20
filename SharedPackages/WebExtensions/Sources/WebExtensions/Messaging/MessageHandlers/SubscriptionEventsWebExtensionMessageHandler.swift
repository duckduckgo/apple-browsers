//
//  SubscriptionEventsWebExtensionMessageHandler.swift
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
import os.log

/// Names shared with the extension's `NativeMessaging.subscribe` implementation.
///
/// Native has no public API to push data into an extension's background, so subscription events go through an
/// outbox: native queues the event and performs `commandIdentifier`, a manifest command with no shortcut. WebKit
/// wakes a sleeping background to deliver the command, and the extension then pulls the queued events with a
/// `drainMethod` request to `featureName`.
public enum WebExtensionSubscriptionEvents {
    public static let featureName = "nativeEvents"
    public static let drainMethod = "drainEvents"
    public static let commandIdentifier = "ddg-native-event"
}

/// A message native sends to an extension's `subscribe(subscriptionName, callback)` listeners for `featureName`.
public struct WebExtensionSubscriptionEvent {
    public let featureName: String
    public let subscriptionName: String
    /// Must be serializable as JSON.
    public let params: [String: Any]

    public init(featureName: String, subscriptionName: String, params: [String: Any] = [:]) {
        self.featureName = featureName
        self.subscriptionName = subscriptionName
        self.params = params
    }

    var payload: [String: Any] {
        ["featureName": featureName, "subscriptionName": subscriptionName, "params": params]
    }
}

/// Holds subscription events until the extension pulls them.
///
/// A newer event for the same feature and subscription replaces the queued one, so subscriptions carry state
/// ("the allowlist is now X") rather than a history, and the queue stays bounded while the extension is not loaded.
/// Delivery is at most once: drained events are gone even if the extension stops before handling them.
public final class WebExtensionEventOutbox: @unchecked Sendable {

    private var events: [WebExtensionSubscriptionEvent] = []
    private let lock = NSLock()

    public init() {}

    public func enqueue(_ event: WebExtensionSubscriptionEvent) {
        lock.lock()
        defer { lock.unlock() }
        events.removeAll { $0.featureName == event.featureName && $0.subscriptionName == event.subscriptionName }
        events.append(event)
    }

    public func drain() -> [WebExtensionSubscriptionEvent] {
        lock.lock()
        defer { lock.unlock() }
        let drained = events
        events = []
        return drained
    }
}

/// Answers the extension's `drainEvents` requests from an outbox.
@available(macOS 15.4, iOS 18.4, *)
public final class SubscriptionEventsWebExtensionMessageHandler: WebExtensionMessageHandler {

    private let outbox: WebExtensionEventOutbox

    public var handledFeatureName: String { WebExtensionSubscriptionEvents.featureName }

    public init(outbox: WebExtensionEventOutbox) {
        self.outbox = outbox
    }

    public func handleMessage(_ message: WebExtensionMessage) async -> WebExtensionMessageResult {
        guard message.method == WebExtensionSubscriptionEvents.drainMethod else {
            return .failure(WebExtensionMessageHandlerError.unknownMethod(message.method))
        }
        let events = outbox.drain()
        if !events.isEmpty {
            Logger.webExtensions.debug("📬 Delivering \(events.count, privacy: .public) subscription event(s)")
        }
        return .success(["events": events.map(\.payload)])
    }
}
