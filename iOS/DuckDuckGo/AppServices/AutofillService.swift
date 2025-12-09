//
//  AutofillService.swift
//  DuckDuckGo
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
import BrowserServicesKit
import Core
import Common
import Persistence

final class AutofillService {

    private struct Keys {
        static let vaultAccessibilityMigration = "com.duckduckgo.autofill.keystore.accessibility.migrated.v4"
    }

    private let autofillLoginSession = AppDependencyProvider.shared.autofillLoginSession
    private let autofillUsageMonitor = AutofillUsageMonitor()
    private var autofillPixelReporter: AutofillPixelReporter?
    private let keyValueStore: ThrowingKeyValueStoring
    private let featureFlagger: FeatureFlagger

    var syncService: SyncService?

    init(keyValueStore: ThrowingKeyValueStoring,
         featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger) {
        self.keyValueStore = keyValueStore
        self.featureFlagger = featureFlagger

        if AppDependencyProvider.shared.appSettings.autofillIsNewInstallForOnByDefault == nil {
            AppDependencyProvider.shared.appSettings.setAutofillIsNewInstallForOnByDefault()
        }
        autofillPixelReporter = makeAutofillPixelReporter()
        registerForAutofillEnabledChanges()

        migrateVaultAccessibilityIfNeeded()
    }

    private func makeAutofillPixelReporter() -> AutofillPixelReporter {
        return AutofillPixelReporter(
            usageStore: AutofillUsageStore(),
            autofillEnabled: AppDependencyProvider.shared.appSettings.autofillCredentialsEnabled,
            eventMapping: EventMapping<AutofillPixelEvent> { [weak self] event, _, params, _ in
                switch event {
                case .autofillActiveUser:
                    Pixel.fire(pixel: .autofillActiveUser, withAdditionalParameters: params ?? [:])
                case .autofillEnabledUser:
                    Pixel.fire(pixel: .autofillEnabledUser)
                case .autofillOnboardedUser:
                    Pixel.fire(pixel: .autofillOnboardedUser)
                case .autofillToggledOn:
                    guard AutofillSettingStatus.isDeviceAuthenticationEnabled else {
                        return
                    }
                    Pixel.fire(pixel: .autofillToggledOn, withAdditionalParameters: params ?? [:])
                    if let autofillExtensionToggled = self?.autofillUsageMonitor.autofillExtensionEnabled {
                        Pixel.fire(pixel: autofillExtensionToggled ? .autofillExtensionToggledOn : .autofillExtensionToggledOff,
                                   withAdditionalParameters: params ?? [:])
                    }
                case .autofillToggledOff:
                    guard AutofillSettingStatus.isDeviceAuthenticationEnabled else {
                        return
                    }
                    Pixel.fire(pixel: .autofillToggledOff, withAdditionalParameters: params ?? [:])
                    if let autofillExtensionToggled = self?.autofillUsageMonitor.autofillExtensionEnabled {
                        Pixel.fire(pixel: autofillExtensionToggled ? .autofillExtensionToggledOn : .autofillExtensionToggledOff,
                                   withAdditionalParameters: params ?? [:])
                    }
                case .autofillLoginsStacked:
                    Pixel.fire(pixel: .autofillLoginsStacked, withAdditionalParameters: params ?? [:])
                case .autofillCreditCardsStacked:
                    Pixel.fire(pixel: .autofillCreditCardsStacked, withAdditionalParameters: params ?? [:])
                default:
                    break
                }
            },
            installDate: StatisticsUserDefaults().installDate ?? Date()
        )
    }

    private func registerForAutofillEnabledChanges() {
        NotificationCenter.default.addObserver(forName: AppUserDefaults.Notifications.autofillEnabledChange,
                                               object: nil,
                                               queue: nil) { _ in
            self.autofillPixelReporter?.updateAutofillEnabledStatus(AppDependencyProvider.shared.appSettings.autofillCredentialsEnabled)
        }
    }

    // MARK: - Resume

    func resume() {
        guard let syncService else {
            assertionFailure("SyncService must be injected before calling onForeground.")
            return
        }
        let importPasswordsStatusHandler = ImportPasswordsViaSyncStatusHandler(syncService: syncService.sync)
        Task {
            await importPasswordsStatusHandler.checkSyncSuccessStatus()
        }
    }

    // MARK: - Suspend

    func suspend() {
        autofillLoginSession.endSession()
    }

    // MARK: - Vault Accessibility Migration

    private func migrateVaultAccessibilityIfNeeded() {
        guard featureFlagger.isFeatureOn(.migrateKeychainAccessibility),
              (try? keyValueStore.object(forKey: Keys.vaultAccessibilityMigration) as? Bool) != true else {
            return
        }

        let keyStoreProvider = AutofillKeyStoreProvider()
        let completed = keyStoreProvider.migrateKeychainAccessibility()

        if completed {
            try? keyValueStore.set(true, forKey: Keys.vaultAccessibilityMigration)
        }
    }
}
