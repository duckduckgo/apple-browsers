//
//  WebPushSubscriptionStore.swift
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
import OSLog
import WebKit

private let log = Logger(subsystem: "com.duckduckgo.macos.browser", category: "WebPush")

/// In-memory subscription registry. Owned by us — WebKit is out of the loop
/// once the JS shim short-circuits `pushManager.subscribe()`. Production would
/// persist this and key delivery on a real channel ID from the DDG autopush
/// backend instead of just origin.
final class WebPushSubscriptionStore: NSObject {

    static let shared = WebPushSubscriptionStore()

    private var subscribed: Set<String> = []
    private let lock = NSLock()

    func recordSubscribe(origin: String) {
        lock.lock(); defer { lock.unlock() }
        subscribed.insert(origin)
        log.debug("WebPushSubscriptionStore: + \(origin, privacy: .public)")
    }

    func recordUnsubscribe(origin: String) {
        lock.lock(); defer { lock.unlock() }
        subscribed.remove(origin)
        log.debug("WebPushSubscriptionStore: - \(origin, privacy: .public)")
    }

    func isSubscribed(origin: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return subscribed.contains(origin)
    }
}

/// Message handler the JS shim posts to on subscribe/unsubscribe/isSubscribed.
/// Uses the frame's `securityOrigin` (not page-supplied data) so the page
/// can't lie about which origin it's subscribing for. With-reply variant so
/// `getSubscription()` can ask "is this origin known to native?" and rehydrate
/// a synthetic subscription after page reload.
final class WebPushBridge: NSObject, WKScriptMessageHandlerWithReply {

    static let shared = WebPushBridge()
    static let messageHandlerName = "ddgWebPushBridge"

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else {
            replyHandler(nil, "invalid message")
            return
        }

        let frame = message.frameInfo.securityOrigin
        var origin = "\(frame.protocol)://\(frame.host)"
        if frame.port != 0 {
            origin += ":\(frame.port)"
        }

        switch action {
        case "subscribe":
            WebPushSubscriptionStore.shared.recordSubscribe(origin: origin)
            // Also grant SW-side notification permission so the worker's
            // `registration.showNotification(...)` call inside its `push`
            // handler isn't rejected by WebKit's `policyForOrigin` check.
            // Pass frame.port as-is — WKSecurityOriginCreate treats 0 as
            // "default port for scheme", matching what `SecurityOriginData::fromURL`
            // produces for URLs without an explicit port.
            WebPushNotificationPermission.grant(scheme: frame.protocol, host: frame.host, port: Int(frame.port))
            replyHandler(true, nil)
        case "unsubscribe":
            WebPushSubscriptionStore.shared.recordUnsubscribe(origin: origin)
            replyHandler(true, nil)
        case "isSubscribed":
            replyHandler(WebPushSubscriptionStore.shared.isSubscribed(origin: origin), nil)
        default:
            replyHandler(nil, "unknown action: \(action)")
        }
    }
}

