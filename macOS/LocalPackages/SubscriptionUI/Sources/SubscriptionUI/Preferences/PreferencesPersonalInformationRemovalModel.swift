//
//  PreferencesPersonalInformationRemovalModel.swift
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

public final class PreferencesPersonalInformationRemovalModel: ObservableObject {

    public enum UserEvent {
        case openPIR,
             openURL(SubscriptionURL),
             didOpenPIRPreferencePane
    }

    @Published public var status: StatusIndicator = .off

    private let userEventHandler: (PreferencesPersonalInformationRemovalModel.UserEvent) -> Void
    private var cancellables = Set<AnyCancellable>()

    public init(userEventHandler: @escaping (PreferencesPersonalInformationRemovalModel.UserEvent) -> Void,
                statusUpdates: AnyPublisher<StatusIndicator, Never>) {
        self.userEventHandler = userEventHandler

        statusUpdates
            .assign(to: \.status, onWeaklyHeld: self)
            .store(in: &cancellables)
    }

    @MainActor
    func didAppear() {
        userEventHandler(.didOpenPIRPreferencePane)
    }

    @MainActor
    func openPersonalInformationRemoval() {
        userEventHandler(.openPIR)
    }

    @MainActor
    func openFAQ() {
        userEventHandler(.openURL(.faq))
    }
}
