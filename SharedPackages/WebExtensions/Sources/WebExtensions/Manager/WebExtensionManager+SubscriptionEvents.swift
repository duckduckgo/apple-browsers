//
//  WebExtensionManager+SubscriptionEvents.swift
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
import WebKit

@available(macOS 15.4, iOS 18.4, *)
extension WebExtensionManager {

    /// Sends a message to the embedded extension's `NativeMessaging.subscribe` listeners.
    ///
    /// The event waits in an outbox, and the extension is told to pull it by performing
    /// `WebExtensionSubscriptionEvents.commandIdentifier`, which wakes its background if it is asleep. If the
    /// extension is not loaded, the event stays queued and the extension pulls it when its background starts.
    @MainActor
    public func sendSubscriptionEvent(_ event: WebExtensionSubscriptionEvent) {
        subscriptionEventOutbox.enqueue(event)
        let name = "\(event.featureName).\(event.subscriptionName)"
        guard let context = embeddedBackgroundContextForNavigation, context.isLoaded else {
            Logger.webExtensions.debug("📬 Queued \(name, privacy: .public) until the embedded extension loads")
            return
        }
        guard let command = context.commands.first(where: { $0.id == WebExtensionSubscriptionEvents.commandIdentifier }) else {
            Logger.webExtensions.debug("📬 Queued \(name, privacy: .public), but the embedded extension has no event command")
            return
        }
        Logger.webExtensions.debug("📬 Sending \(name, privacy: .public) to the embedded extension")
        context.performCommand(command)
    }

    /// Lets an extension pull its subscription events. Only the embedded extension receives them.
    func registerSubscriptionEventsHandler(identifier: String, context: WKWebExtensionContext) {
        guard context.duckDuckGoWebExtensionType == .embedded else { return }
        messageRouter.registerHandler(SubscriptionEventsWebExtensionMessageHandler(outbox: subscriptionEventOutbox),
                                      for: identifier)
    }
}
