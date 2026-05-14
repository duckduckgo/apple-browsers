//
//  AutofillPreferences.swift
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
import Common
import Persistence
import WebExtensions

protocol AutofillPreferencesPersistor {
    var isAutoLockEnabled: Bool { get set }
    var autoLockThreshold: AutofillAutoLockThreshold { get set }
    var askToSaveUsernamesAndPasswords: Bool { get set }
    var askToSaveAddresses: Bool { get set }
    var askToSavePaymentMethods: Bool { get set }
    var autolockLocksFormFilling: Bool { get set }
    var passwordManager: PasswordManager { get set }
    var debugScriptEnabled: Bool { get set }
    var showInMenuBar: Bool { get set }
}

enum PasswordManager: String, CaseIterable {
    case duckduckgo
    case bitwarden
}

enum PasswordManagementSource: String {
    case settings
    case overflow = "overflow_menu"
    case shortcut = "menu_bar_shortcut"
    case manage = "manage_button"
    case sync
}

enum AutofillAutoLockThreshold: String, CaseIterable {
    case oneMinute
    case fiveMinutes
    case fifteenMinutes
    case thirtyMinutes
    case oneHour
    case twelveHours

    var title: String {
        switch self {
        case .oneMinute: return UserText.autoLockThreshold1Minute
        case .fiveMinutes: return UserText.autoLockThreshold5Minutes
        case .fifteenMinutes: return UserText.autoLockThreshold15Minutes
        case .thirtyMinutes: return UserText.autoLockThreshold30Minutes
        case .oneHour: return UserText.autoLockThreshold1Hour
        case .twelveHours: return UserText.autoLockThreshold12Hours
        }
    }

    var seconds: TimeInterval {
        switch self {
        case .oneMinute: return 60
        case .fiveMinutes: return 60 * 5
        case .fifteenMinutes: return 60 * 15
        case .thirtyMinutes: return 60 * 30
        case .oneHour: return 60 * 60
        case .twelveHours: return 60 * 60 * 12
        }
    }
}

extension NSNotification.Name {
    static let autofillAutoLockSettingsDidChange = NSNotification.Name("autofillAutoLockSettingsDidChange")
    static let autofillUserSettingsDidChange = NSNotification.Name("autofillUserSettingsDidChange")
    static let autofillScriptDebugSettingsDidChange = NSNotification.Name("autofillScriptDebugSettingsDidChange")
    static let autofillShowInMenuBarDidChange = NSNotification.Name("autofillShowInMenuBarDidChange")
}

final class AutofillPreferences: AutofillPreferencesPersistor {

    enum Key: String {
        case showPasswordsInMenuBar = "preferences.passwords.show-in-menu-bar"
    }

    public var isAutoLockEnabled: Bool {
        get {
            return statisticsStore.autoLockEnabled
        }

        set {
            let oldValue = statisticsStore.autoLockEnabled
            statisticsStore.autoLockEnabled = newValue

            if oldValue != newValue {
                NotificationCenter.default.post(name: .autofillAutoLockSettingsDidChange, object: nil)
            }
        }
    }

    var autoLockThreshold: AutofillAutoLockThreshold {
        get {
            if let rawValue = statisticsStore.autoLockThreshold, let threshold = AutofillAutoLockThreshold(rawValue: rawValue) {
                return threshold
            } else {
                return .fifteenMinutes
            }
        }

        set {
            statisticsStore.autoLockThreshold = newValue.rawValue
        }
    }

    @UserDefaultsWrapper(key: .askToSaveUsernamesAndPasswords, defaultValue: true)
    var askToSaveUsernamesAndPasswords: Bool

    @UserDefaultsWrapper(key: .askToSaveAddresses, defaultValue: true)
    var askToSaveAddresses: Bool

    @UserDefaultsWrapper(key: .askToSavePaymentMethods, defaultValue: true)
    var askToSavePaymentMethods: Bool

    @UserDefaultsWrapper(key: .autolockLocksFormFilling, defaultValue: false)
    var autolockLocksFormFilling: Bool

    var showInMenuBar: Bool {
        get {
            return (try? keyValueStore.object(forKey: Key.showPasswordsInMenuBar.rawValue) as? Bool) ?? false
        }
        set {
            let oldValue = showInMenuBar
            try? keyValueStore.set(newValue, forKey: Key.showPasswordsInMenuBar.rawValue)
            if oldValue != newValue {
                NotificationCenter.default.post(name: .autofillShowInMenuBarDidChange, object: nil)
            }
        }
    }

    var passwordManager: PasswordManager {
        get {
            guard AppVersion.isAppStoreBuild else {
                return PasswordManager(rawValue: selectedPasswordManager) ?? .duckduckgo
            }
            guard #available(macOS 15.4, *), WebExtensionManager.areExtensionsEnabled else {
                // Roll back to original behavior if web extensions are not supported
                // (mostly as a safety measure for disabling the feature flag)
                return .duckduckgo
            }

            let passwordManager = PasswordManager(rawValue: selectedPasswordManager) ?? .duckduckgo

            guard passwordManager != .bitwarden else {
                return .duckduckgo
            }

            return passwordManager
        }
        set {
            if AppVersion.isAppStoreBuild {
                guard #available(macOS 15.4, *), WebExtensionManager.areExtensionsEnabled else {
                    // Roll back to original behavior if web extensions are not supported
                    // (mostly as a safety measure for disabling the feature flag)
                    return
                }
            }

            selectedPasswordManager = newValue.rawValue
        }
    }

    @UserDefaultsWrapper(key: .selectedPasswordManager, defaultValue: PasswordManager.duckduckgo.rawValue)
    private(set) var selectedPasswordManager: String

    @UserDefaultsWrapper(key: .autofillDebugScriptEnabled, defaultValue: false)
    private var debugScriptEnabledWrapped: Bool

    var debugScriptEnabled: Bool {
        get {
            return debugScriptEnabledWrapped
        }

        set {
            if debugScriptEnabledWrapped != newValue {
                debugScriptEnabledWrapped = newValue
            }
        }
    }

    private var statisticsStore: StatisticsStore {
        return injectedDependencyStore ?? defaultDependencyStore
    }

    private let injectedDependencyStore: StatisticsStore?
    private let keyValueStore: ThrowingKeyValueStoring
    private lazy var defaultDependencyStore: StatisticsStore = {
#if DEBUG
        // To prevent an assertion failure deep within dependencies in Database.makeDatabase
        if [.unitTests, .xcPreviews].contains(AppVersion.runType) {
            return StubStatisticsStore()
        }
#endif
        return LocalStatisticsStore()
    }()

    init(statisticsStore: StatisticsStore? = nil,
         keyValueStore: ThrowingKeyValueStoring = UserDefaults.standard) {
        self.injectedDependencyStore = statisticsStore
        self.keyValueStore = keyValueStore
    }

}
