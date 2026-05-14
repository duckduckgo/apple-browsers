//
//  VisualizeFireSettingsDecider.swift
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
import FeatureFlags
import PrivacyConfig

protocol VisualizeFireSettingsDecider {
    /// Fire animation setting
    var shouldShowFireAnimation: Bool { get }
    var shouldShowFireAnimationPublisher: AnyPublisher<Bool, Never> { get }

    /// Open Fire Window By Default setting
    var isOpenFireWindowByDefaultEnabled: Bool { get }
    var shouldShowOpenFireWindowByDefaultPublisher: AnyPublisher<Bool, Never> { get }
}

final class DefaultVisualizeFireSettingsDecider: VisualizeFireSettingsDecider {
    private let featureFlagger: FeatureFlagger
    private let dataClearingPreferences: DataClearingPreferences

    init(featureFlagger: FeatureFlagger,
         dataClearingPreferences: DataClearingPreferences) {
        self.featureFlagger = featureFlagger
        self.dataClearingPreferences = dataClearingPreferences
    }

    var shouldShowFireAnimation: Bool {
        return dataClearingPreferences.isFireAnimationEnabled
    }

    var shouldShowFireAnimationPublisher: AnyPublisher<Bool, Never> {
        dataClearingPreferences.$isFireAnimationEnabled
            .map { isFireAnimationEnabled in
                return isFireAnimationEnabled
            }
            .eraseToAnyPublisher()
    }

    var isOpenFireWindowByDefaultEnabled: Bool {
        return dataClearingPreferences.shouldOpenFireWindowByDefault
    }

    var shouldShowOpenFireWindowByDefaultPublisher: AnyPublisher<Bool, Never> {
        dataClearingPreferences.$shouldOpenFireWindowByDefault
            .map { openFireWindowByDefault in
                return openFireWindowByDefault
            }
            .eraseToAnyPublisher()
    }
}
