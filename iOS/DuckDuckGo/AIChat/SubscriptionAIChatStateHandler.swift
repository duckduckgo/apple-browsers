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

/// Notifies when AI Chat needs to reload because the subscription changed.
///
/// Sign-in, sign-out and plan changes all alter the features and limits AI Chat must reflect.
protocol SubscriptionAIChatStateHandling: AnyObject {
    /// Called when subscription state changes. Set this to react to changes immediately.
    var onSubscriptionStateChanged: (() -> Void)? { get set }
}

final class SubscriptionAIChatStateHandler: SubscriptionAIChatStateHandling {
    var onSubscriptionStateChanged: (() -> Void)?
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

    private func handleSubscriptionStateChange(_ notification: Notification) {
        onSubscriptionStateChanged?()
    }
}
