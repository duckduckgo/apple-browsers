//
//  CookiePopupProtectionPreferences.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import AppKit
import Bookmarks
import Common
import FoundationExtensions
import WebExtensions

protocol CookiePopupProtectionPreferencesPersistor {
    var autoconsentEnabled: Bool { get set }
    var cookiePopupPreferenceRawValue: String? { get set }
    var didMigrateCookiePopupPreference: Bool { get set }
}

struct CookiePopupProtectionPreferencesUserDefaultsPersistor: CookiePopupProtectionPreferencesPersistor {

    @UserDefaultsWrapper(key: .autoconsentEnabled, defaultValue: true)
    var autoconsentEnabled: Bool

    @UserDefaultsWrapper(key: .cookiePopupPreference, defaultValue: nil)
    var cookiePopupPreferenceRawValue: String?

    @UserDefaultsWrapper(key: .didMigrateCookiePopupPreference, defaultValue: false)
    var didMigrateCookiePopupPreference: Bool

}

final class CookiePopupProtectionPreferences: ObservableObject, PreferencesTabOpening {

    @Published
    var cookiePopupPreference: CookiePopupPreference {
        didSet {
            persistor.cookiePopupPreferenceRawValue = cookiePopupPreference.rawValue
        }
    }

    var isAutoconsentEnabled: Bool {
        get { cookiePopupPreference.isBlockingEnabled }
        set { cookiePopupPreference = newValue ? .default : .off }
    }

    init(
        persistor: CookiePopupProtectionPreferencesPersistor = CookiePopupProtectionPreferencesUserDefaultsPersistor(),
        windowControllersManager: WindowControllersManagerProtocol
    ) {
        self.persistor = persistor
        self.windowControllersManager = windowControllersManager

        if persistor.didMigrateCookiePopupPreference,
           let rawValue = persistor.cookiePopupPreferenceRawValue,
           let preference = CookiePopupPreference(rawValue: rawValue) {
            cookiePopupPreference = preference
        } else {
            let migratedPreference: CookiePopupPreference = persistor.autoconsentEnabled ? .default : .off
            cookiePopupPreference = migratedPreference
            self.persistor.cookiePopupPreferenceRawValue = migratedPreference.rawValue
            self.persistor.didMigrateCookiePopupPreference = true
        }
    }

    let windowControllersManager: WindowControllersManagerProtocol
    private var persistor: CookiePopupProtectionPreferencesPersistor
}

extension CookiePopupProtectionPreferences: AutoconsentPreferencesProviding {}
