//
//  SyncCreditCardsAdapter.swift
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
import Combine
import Common
import DDGSync
import Foundation
import Persistence
import PixelKit
import PrivacyConfig
import SyncDataProviders

final class SyncCreditCardsAdapter {

    private(set) var provider: CreditCardsProvider?
    let databaseCleaner: CreditCardsDatabaseCleaner
    let syncErrorHandler: SyncErrorHandling
    let syncDidCompletePublisher: AnyPublisher<Void, Never>
    private var featureAvailabilityCancellable: AnyCancellable?

    init(secureVaultFactory: AutofillVaultFactory = AutofillSecureVaultFactory,
         syncErrorHandler: SyncErrorHandling) {
        syncDidCompletePublisher = syncDidCompleteSubject.eraseToAnyPublisher()
        self.syncErrorHandler = syncErrorHandler
        databaseCleaner = CreditCardsDatabaseCleaner(
            secureVaultFactory: secureVaultFactory,
            secureVaultErrorReporter: SecureVaultReporter.shared,
            errorEvents: CreditCardsCleanupErrorHandling()
        )
    }

    func cleanUpDatabaseAndUpdateSchedule(shouldEnable: Bool) {
        databaseCleaner.cleanUpDatabaseNow()
        if shouldEnable {
            databaseCleaner.scheduleRegularCleaning()
        } else {
            databaseCleaner.cancelCleaningSchedule()
        }
    }

    func setUpProviderIfNeeded(
        secureVaultFactory: AutofillVaultFactory,
        metadataStore: SyncMetadataStore,
        metricsEventsHandler: EventMapping<MetricsEvent>? = nil,
        privacyConfigurationManager: PrivacyConfigurationManaging = Application.appDelegate.privacyFeatures.contentBlocking.privacyConfigurationManager
    ) {
        guard provider == nil else {
            return
        }

        do {
            let provider = try CreditCardsProvider(
                secureVaultFactory: secureVaultFactory,
                secureVaultErrorReporter: SecureVaultReporter.shared,
                metadataStore: metadataStore,
                metricsEvents: metricsEventsHandler,
                syncDidUpdateData: { [weak self] in
                    self?.syncDidCompleteSubject.send()
                    self?.syncErrorHandler.syncCreditCardsSucceded()
                }, syncDidFinish: { _ in }
            )

            syncErrorCancellable = provider.syncErrorPublisher
                .sink { [weak self] error in
                    self?.syncErrorHandler.handleCreditCardsError(error)
                }

            self.provider = provider

            featureAvailabilityCancellable = privacyConfigurationManager.updatesPublisher
                .prepend(())
                .receive(on: DispatchQueue.main)
                .sink { [weak provider] in
                    let isEnabled = privacyConfigurationManager.privacyConfig.isSubfeatureEnabled(SyncSubfeature.syncCreditCards)
                    provider?.setSyncFeatureEnabled(isEnabled)
                }

        } catch let error as NSError {
            let processedErrors = CoreDataErrorsParser.parse(error: error)
            let params = processedErrors.errorPixelParameters
            PixelKit.fire(DebugEvent(GeneralPixel.syncCreditCardsProviderInitializationFailed, error: error), withAdditionalParameters: params)
        }
    }

    private var syncDidCompleteSubject = PassthroughSubject<Void, Never>()
    private var syncErrorCancellable: AnyCancellable?
}
