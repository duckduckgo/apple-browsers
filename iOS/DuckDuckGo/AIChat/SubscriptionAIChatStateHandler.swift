//
//  SubscriptionAIChatStateHandler.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

/// Manages AI Chat refresh state when subscription status changes.
///
/// When a user's subscription changes (sign-in, sign-out, or plan change),
/// AI Chat needs to reload to reflect the new subscription features and limits.
protocol SubscriptionAIChatStateHandling {
    /// Indicates if AI Chat should refresh due to subscription changes.
    ///
    /// Becomes `true` when subscription status changes.
    var shouldForceAIChatRefresh: Bool { get }

    /// Clears the refresh flag after AI Chat has been reloaded.
    func reset()
}

final class SubscriptionAIChatStateHandler: SubscriptionAIChatStateHandling {
    private(set) var shouldForceAIChatRefresh: Bool = false
    private var subscriptionCancellables = Set<AnyCancellable>()

    init() {
        setupSubscriptionStateObservers()
    }

    private func setupSubscriptionStateObservers() {
        NotificationCenter.default.publisher(for: .subscriptionDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleSubscriptionStateChange(notification)
            }
            .store(in: &subscriptionCancellables)

        NotificationCenter.default.publisher(for: .accountDidSignIn)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleSubscriptionStateChange(notification)
            }
            .store(in: &subscriptionCancellables)

        NotificationCenter.default.publisher(for: .accountDidSignOut)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleSubscriptionStateChange(notification)
            }
            .store(in: &subscriptionCancellables)
    }

    private func handleSubscriptionStateChange(_ notification: Notification, ) {
        shouldForceAIChatRefresh = true
    }

    func reset() {
        shouldForceAIChatRefresh = false
    }
}
