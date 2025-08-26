//
//  DataClearingPreferences.swift
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
import PixelKit
import BrowserServicesKit
import FeatureFlags

final class DataClearingPreferences: ObservableObject, PreferencesTabOpening {

    @Published
    var isLoginDetectionEnabled: Bool {
        didSet {
            persistor.loginDetectionEnabled = isLoginDetectionEnabled
        }
    }

    @Published
    var isAutoClearEnabled: Bool {
        didSet {
            persistor.autoClearEnabled = isAutoClearEnabled
            NotificationCenter.default.post(name: .autoClearDidChange,
                                            object: nil,
                                            userInfo: nil)
            pixelFiring?.fire(SettingsPixel.dataClearingSettingToggled, frequency: .uniqueByName)
        }
    }

    @Published
    var isFireAnimationEnabled: Bool {
        didSet {
            pixelFiring?.fire(GeneralPixel.fireAnimationSetting(enabled: isFireAnimationEnabled))
            persistor.isFireAnimationEnabled = isFireAnimationEnabled
        }
    }

    @Published
    var openFireWindowByDefault: Bool {
        didSet {
            persistor.openFireWindowByDefault = openFireWindowByDefault
        }
    }

    @Published
    var isWarnBeforeClearingEnabled: Bool {
        didSet {
            persistor.warnBeforeClearingEnabled = isWarnBeforeClearingEnabled
        }
    }

    var shouldShowDisableFireAnimationSection: Bool {
        featureFlagger.isFeatureOn(.disableFireAnimation)
    }

    var shouldShowOpenFirewindowByDefaultSection: Bool {
        featureFlagger.isFeatureOn(.openFireWindowByDefault)
    }

    @objc func toggleWarnBeforeClearing() {
        isWarnBeforeClearingEnabled.toggle()
    }

    @MainActor
    func presentManageFireproofSitesDialog() {
        let fireproofDomainsWindowController = FireproofDomainsViewController.create(fireproofDomains: fireproofDomains, faviconManager: faviconManager).wrappedInWindowController()

        guard let fireproofDomainsWindow = fireproofDomainsWindowController.window,
              let parentWindowController = windowControllersManager.lastKeyMainWindowController
        else {
            assertionFailure("DataClearingPreferences: Failed to present FireproofDomainsViewController")
            return
        }

        parentWindowController.window?.beginSheet(fireproofDomainsWindow)
    }

    init(
        persistor: FireButtonPreferencesPersistor = FireButtonPreferencesUserDefaultsPersistor(),
        fireproofDomains: FireproofDomains,
        faviconManager: FaviconManagement,
        windowControllersManager: WindowControllersManagerProtocol,
        featureFlagger: FeatureFlagger,
        pixelFiring: PixelFiring? = nil
    ) {
        self.persistor = persistor
        self.fireproofDomains = fireproofDomains
        self.faviconManager = faviconManager
        self.windowControllersManager = windowControllersManager
        self.pixelFiring = pixelFiring
        self.featureFlagger = featureFlagger
        isLoginDetectionEnabled = persistor.loginDetectionEnabled
        isAutoClearEnabled = persistor.autoClearEnabled
        isWarnBeforeClearingEnabled = persistor.warnBeforeClearingEnabled
        isFireAnimationEnabled = persistor.isFireAnimationEnabled
        openFireWindowByDefault = persistor.openFireWindowByDefault
    }

    private var persistor: FireButtonPreferencesPersistor
    private let fireproofDomains: FireproofDomains
    private let faviconManager: FaviconManagement
    private let windowControllersManager: WindowControllersManagerProtocol
    private let pixelFiring: PixelFiring?
    private let featureFlagger: FeatureFlagger
}

protocol FireButtonPreferencesPersistor {
    var loginDetectionEnabled: Bool { get set }
    var autoClearEnabled: Bool { get set }
    var warnBeforeClearingEnabled: Bool { get set }
    var isFireAnimationEnabled: Bool { get set }
    var openFireWindowByDefault: Bool { get set }
}

struct FireButtonPreferencesUserDefaultsPersistor: FireButtonPreferencesPersistor {

    @UserDefaultsWrapper(key: .loginDetectionEnabled, defaultValue: false)
    var loginDetectionEnabled: Bool

    @UserDefaultsWrapper(key: .autoClearEnabled, defaultValue: false)
    var autoClearEnabled: Bool

    @UserDefaultsWrapper(key: .warnBeforeClearingEnabled, defaultValue: false)
    var warnBeforeClearingEnabled: Bool

    @UserDefaultsWrapper(key: .fireAnimationEnabled, defaultValue: true)
    var isFireAnimationEnabled: Bool

    @UserDefaultsWrapper(key: .openFireWindowByDefault, defaultValue: false)
    var openFireWindowByDefault: Bool

}

extension Notification.Name {
    static let autoClearDidChange = Notification.Name("autoClearDidChange")
}
