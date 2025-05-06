//
//  PreferencesIdentityTheftRestorationModel.swift
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

import AppKit
import PreferencesUI_macOS
import Subscription
import Combine

public final class PreferencesIdentityTheftRestorationModel: ObservableObject {

    private let subscriptionManager: SubscriptionAuthV1toV2Bridge
    private let openURLHandler: (URL) -> Void
    private let userEventHandler: (PreferencesSubscriptionModel.UserEvent) -> Void

    @Published public var status: StatusIndicator = .off

    private var cancellables = Set<AnyCancellable>()

    public init(subscriptionManager: SubscriptionAuthV1toV2Bridge,
                openURLHandler: @escaping (URL) -> Void,
                userEventHandler: @escaping (PreferencesSubscriptionModel.UserEvent) -> Void,
                statusUpdates: AnyPublisher<StatusIndicator, Never>) {
        self.subscriptionManager = subscriptionManager
        self.openURLHandler = openURLHandler
        self.userEventHandler = userEventHandler

        statusUpdates
            .assign(to: \.status, onWeaklyHeld: self)
            .store(in: &cancellables)
    }

    @MainActor
    func didAppear() {
        // TODO: should register opening settings?
//        userEventHandler(.openSubscriptionSettingsClick)
    }

    @MainActor
    func openIdentityTheftRestoration() {
        userEventHandler(.openITR)
    }

    @MainActor
    func openFAQ() {
        openURLHandler(subscriptionManager.url(for: .faq))
    }
}
