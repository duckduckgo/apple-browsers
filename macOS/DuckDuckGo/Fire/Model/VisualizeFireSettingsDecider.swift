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
import BrowserServicesKit
import FeatureFlags
import Combine

protocol VisualizeFireSettingsDecider {
    /// Fire animation setting
    var shouldShowFireAnimation: Bool { get }
    var shouldShowFireAnimationPublisher: AnyPublisher<Bool, Never> { get }

    /// Open Fire Window By Default setting
    var isOpenFireWindowByDefaultEnabled: Bool { get }
    var shouldShowOpenFireWindoyByDefaultPublisher: AnyPublisher<Bool, Never> { get }
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
        if featureFlagger.isFeatureOn(.disableFireAnimation) {
            return dataClearingPreferences.isFireAnimationEnabled
        } else {
            return true
        }
    }

    var shouldShowFireAnimationPublisher: AnyPublisher<Bool, Never> {
        dataClearingPreferences.$isFireAnimationEnabled
            .map { [weak self] isFireAnimationEnabled in
                guard let self = self else { return true }

                if self.featureFlagger.isFeatureOn(.disableFireAnimation) {
                    return isFireAnimationEnabled
                } else {
                    return true
                }
            }
            .eraseToAnyPublisher()
    }

    var isOpenFireWindowByDefaultEnabled: Bool {
        if featureFlagger.isFeatureOn(.openFireWindowByDefault) {
            return dataClearingPreferences.openFireWindowByDefault
        } else {
            return false
        }
    }

    var shouldShowOpenFireWindoyByDefaultPublisher: AnyPublisher<Bool, Never> {
        dataClearingPreferences.$openFireWindowByDefault
            .map { [weak self] openFireWindowByDefault in
                guard let self = self else { return true }

                if self.featureFlagger.isFeatureOn(.openFireWindowByDefault) {
                    return openFireWindowByDefault
                } else {
                    return false
                }
            }
            .eraseToAnyPublisher()
    }
}
