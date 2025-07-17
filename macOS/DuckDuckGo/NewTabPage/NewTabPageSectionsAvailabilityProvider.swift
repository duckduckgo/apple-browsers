//
//  NewTabPageSectionsAvailabilityProvider.swift
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

import Foundation
import NewTabPage
import BrowserServicesKit
import Combine
import FeatureFlags

extension Notification.Name {

    static var newTabPageSectionsAvailabilityDidChange = Notification.Name(rawValue: "newTabPageSectionsAvailabilityDidChange")

}

final class NewTabPageSectionsAvailabilityProvider: NewTabPageSectionsAvailabilityProviding {

    private let featureFlagger: FeatureFlagger
    private var cancellables = Set<AnyCancellable>()

    internal init(featureFlagger: any FeatureFlagger) {
        self.featureFlagger = featureFlagger

        subscribeToOmnibarFeatureFlagChanges()
    }

    private func subscribeToOmnibarFeatureFlagChanges() {
        guard let overridesHandler = featureFlagger.localOverrides?.actionHandler as? FeatureFlagOverridesPublishingHandler<FeatureFlag> else {
            return
        }

        overridesHandler.flagDidChangePublisher
            .filter { $0.0 == .newTabPageOmnibar }
            .sink { _ in
                NotificationCenter.default.post(name: .newTabPageSectionsAvailabilityDidChange, object: nil)
            }
            .store(in: &cancellables)
    }

    var isOmnibarAvailable: Bool {
        return featureFlagger.isFeatureOn(.newTabPageOmnibar)
    }

}
