//
//  WebTrackingProtectionPreferences.swift
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

protocol WebTrackingProtectionPreferencesPersistor {
    var gpcEnabled: Bool { get set }
}

struct WebTrackingProtectionPreferencesUserDefaultsPersistor: WebTrackingProtectionPreferencesPersistor {

    @UserDefaultsWrapper(key: .gpcEnabled, defaultValue: true)
    var gpcEnabled: Bool

}

public final class WebTrackingProtectionPreferences: ObservableObject, PreferencesTabOpening {

    @Published
    var isGPCEnabled: Bool {
        didSet {
            persistor.gpcEnabled = isGPCEnabled
        }
    }

    init(
        persistor: WebTrackingProtectionPreferencesPersistor = WebTrackingProtectionPreferencesUserDefaultsPersistor(),
        windowControllersManager: WindowControllersManagerProtocol
    ) {
        self.persistor = persistor
        self.windowControllersManager = windowControllersManager
        isGPCEnabled = persistor.gpcEnabled
    }

    let windowControllersManager: WindowControllersManagerProtocol
    private var persistor: WebTrackingProtectionPreferencesPersistor
}
