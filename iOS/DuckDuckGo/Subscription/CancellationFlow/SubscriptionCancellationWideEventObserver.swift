//
//  SubscriptionCancellationWideEventObserver.swift
//  DuckDuckGo
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
import Common
import Subscription
import WideEvent

protocol SubscriptionCancellationWideEventObserving: AnyObject {
    func startObservingSubscriptionChanges()
}

final class SubscriptionCancellationWideEventObserver: SubscriptionCancellationWideEventObserving {

    private typealias CancellationData = SubscriptionCancellationWideEventData

    private let wideEvent: WideEventManaging
    private let notificationCenter: NotificationCenter
    private let subscriptionFetcher: () async throws -> DuckDuckGoSubscription?
    private let now: () -> Date
    private var subscriptionObserver: NSObjectProtocol?

    init(wideEvent: WideEventManaging,
         notificationCenter: NotificationCenter = .default,
         subscriptionFetcher: @escaping () async throws -> DuckDuckGoSubscription?,
         now: @escaping () -> Date = Date.init) {
        self.wideEvent = wideEvent
        self.notificationCenter = notificationCenter
        self.subscriptionFetcher = subscriptionFetcher
        self.now = now
    }

    deinit {
        if let subscriptionObserver {
            notificationCenter.removeObserver(subscriptionObserver)
        }
    }

    func startObservingSubscriptionChanges() {
        guard subscriptionObserver == nil else { return }

        subscriptionObserver = notificationCenter.addObserver(forName: .subscriptionDidChange, object: nil, queue: .main) { [weak self] notification in
            Task {
                await self?.handleSubscriptionChange(notification)
            }
        }
    }

    func handleSubscriptionChange(_ notification: Notification) async {
        let pendingFlows = wideEvent.getAllFlowData(CancellationData.self)
        guard !pendingFlows.isEmpty else { return }

        let subscription: DuckDuckGoSubscription?
        if let subscriptionFromPayload = notification.userInfo?[UserDefaultsCacheKey.subscription] as? DuckDuckGoSubscription {
            subscription = subscriptionFromPayload
        } else {
            do {
                subscription = try await subscriptionFetcher()
            } catch {
                return
            }
        }

        let now = now()
        for data in pendingFlows {
            let reason: CancellationData.StatusReason? = data.hasTimedOut(at: now)
                ? .timeout
                : CancellationData.statusReason(for: subscription, subscriptionIdentifier: data.subscriptionIdentifier)
            guard let reason else { continue }
            await complete(data, reason: reason)
        }
    }

    private func complete(_ data: CancellationData, reason: CancellationData.StatusReason) async {
        data.statusReason = reason
        _ = try? await wideEvent.completeFlow(data, status: CancellationData.status(for: reason))
    }
}
