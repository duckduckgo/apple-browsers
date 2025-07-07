//
//  PrivacyProtectionStatus.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import SwiftUI
import Combine
import BrowserServicesKit
import PreferencesUI_macOS

final class PrivacyProtectionStatus: ObservableObject {

    var statusSubscription: AnyCancellable?
    @Published var status: StatusIndicator?

    // Initializer for observable properties
    init<T: Publisher>(statusPublisher: T,
                       initialValue: StatusIndicator? = nil,
                       transform: @escaping (T.Output) -> StatusIndicator?) where T.Failure == Never {
        self.status = initialValue

        statusSubscription = statusPublisher
            .map(transform)
            .sink { [weak self] newStatus in
                self?.status = newStatus
            }
    }

    // Initializer for items without a status
    init() {
        self.status = nil
    }

    // Initializer for items with static status
    init(statusIndicator: StatusIndicator) {
        self.status = statusIndicator
    }
}
