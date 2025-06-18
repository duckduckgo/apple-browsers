//
//  HistoryViewOnboardingViewModel.swift
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
import SwiftUI
import Persistence
import PixelKit

protocol HistoryViewOnboardingViewSettingsPersisting: AnyObject {
    var didShowOnboardingView: Bool { get set }
}

final class UserDefaultsHistoryViewOnboardingViewSettingsPersistor: HistoryViewOnboardingViewSettingsPersisting {
    enum Keys {
        static let didShowOnboardingView = "history.view.onboarding.did-show"
    }

    private let keyValueStore: KeyValueStoring

    init(_ keyValueStore: KeyValueStoring = UserDefaults.standard) {
        self.keyValueStore = keyValueStore
    }

    var didShowOnboardingView: Bool {
        get { return keyValueStore.object(forKey: Keys.didShowOnboardingView) as? Bool ?? false }
        set { keyValueStore.set(newValue, forKey: Keys.didShowOnboardingView) }
    }
}

final class HistoryViewOnboardingViewModel: ObservableObject {
    let settingsStorage: HistoryViewOnboardingViewSettingsPersisting
    let ctaCallback: (Bool) -> Void

    internal init(settingsStorage: any HistoryViewOnboardingViewSettingsPersisting = UserDefaultsHistoryViewOnboardingViewSettingsPersistor(),
                  ctaCallback: @escaping (Bool) -> Void) {
        self.settingsStorage = settingsStorage
        self.ctaCallback = ctaCallback
    }

    func markAsShown() {
        settingsStorage.didShowOnboardingView = true
    }

    func notNow() {
        ctaCallback(false)
    }

    func showHistory() {
        ctaCallback(true)
    }
}
