//
//  ContentScopePreferences.swift
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
import Common

protocol ContentScopePreferencesPersistor {
    var debugModeEnabled: Bool { get set }
}

struct ContentScopePreferencesUserDefaultsPersistor: ContentScopePreferencesPersistor {

    @UserDefaultsWrapper(key: .contentScopeDebugModeEnabled, defaultValue: false)
    var debugModeEnabled: Bool

}

extension NSNotification.Name {
    static let contentScopeDebugModeDidChange = NSNotification.Name("contentScopeDebugModeDidChange")
}

final class ContentScopePreferences: ObservableObject, PreferencesTabOpening {

    static let shared = ContentScopePreferences()

    @Published
    var isDebugModeEnabled: Bool {
        didSet {
            persistor.debugModeEnabled = isDebugModeEnabled
        }
    }

    init(persistor: ContentScopePreferencesPersistor = ContentScopePreferencesUserDefaultsPersistor()) {
        self.persistor = persistor
        isDebugModeEnabled = persistor.debugModeEnabled
    }

    private var persistor: ContentScopePreferencesPersistor
}
