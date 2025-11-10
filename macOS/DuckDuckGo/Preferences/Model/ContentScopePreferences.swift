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
    var debugStateEnabled: Bool { get set }
}

struct ContentScopePreferencesUserDefaultsPersistor: ContentScopePreferencesPersistor {

    @UserDefaultsWrapper(key: .contentScopeDebugStateEnabled, defaultValue: false)
    var debugStateEnabled: Bool

}

extension NSNotification.Name {
    static let contentScopeDebugStateDidChange = NSNotification.Name("contentScopeDebugStateDidChange")
}

final class ContentScopePreferences: ObservableObject, PreferencesTabOpening {

    @Published
    var isDebugStateEnabled: Bool {
        didSet {
            persistor.debugStateEnabled = isDebugStateEnabled
            NotificationCenter.default.post(name: .contentScopeDebugStateDidChange, object: nil)
        }
    }

    init(
        persistor: ContentScopePreferencesPersistor = ContentScopePreferencesUserDefaultsPersistor(),
        windowControllersManager: WindowControllersManagerProtocol
    ) {
        self.persistor = persistor
        self.windowControllersManager = windowControllersManager
        isDebugStateEnabled = persistor.debugStateEnabled
    }

    let windowControllersManager: WindowControllersManagerProtocol
    private var persistor: ContentScopePreferencesPersistor
}
