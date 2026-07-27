//
//  Utils.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
import Common
import FoundationExtensions
import Persistence
import SwiftUI
@testable import DataBrokerProtection_iOS
import DataBrokerProtectionCore
import DataBrokerProtectionCoreTestsUtils

struct IOSManagerTestDependencies {
    let manager: DataBrokerProtectionIOSManager
    let queueManager: MockJobQueueManager
    let database: MockDatabase
    let eventsHandler: MockOperationEventsHandler
    let continuedProcessingCoordinator: MockContinuedProcessingCoordinator
    let authenticationManager: MockAuthenticationManager
    let freemiumDBPUserStateManager: MockFreemiumDBPUserStateManager
    let profileStateManager: DBPProfileStateManaging
}

final class LockedCount {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    @discardableResult
    func increment() -> Int {
        lock.withLock {
            count += 1
            return count
        }
    }
}

@MainActor
enum DBPIOSManagerTestUtils {
    static func makeTestIOSManager(
        featureFlagger: MockDBPFeatureFlagger = MockDBPFeatureFlagger(),
        continuedProcessingCoordinator: MockContinuedProcessingCoordinator = MockContinuedProcessingCoordinator(),
        freemiumDBPUserStateManagerOverride: FreemiumDBPUserStateManaging? = nil
    ) -> (DataBrokerProtectionIOSManager, IOSManagerTestDependencies) {
        return IOSManagerTestDependenciesStore().makeTestIOSManager(
            featureFlagger: featureFlagger,
            continuedProcessingCoordinator: continuedProcessingCoordinator,
            freemiumDBPUserStateManagerOverride: freemiumDBPUserStateManagerOverride
        )
    }

    static func makeDeferredTestIOSManager(
        featureFlagger: MockDBPFeatureFlagger = MockDBPFeatureFlagger(),
        continuedProcessingCoordinator: MockContinuedProcessingCoordinator = MockContinuedProcessingCoordinator(),
        freemiumDBPUserStateManagerOverride: FreemiumDBPUserStateManaging? = nil,
        provider: @escaping (DBPVaultResources) -> (() throws -> DBPVaultResources)
    ) -> (DataBrokerProtectionIOSManager, IOSManagerTestDependencies) {
        return IOSManagerTestDependenciesStore().makeDeferredTestIOSManager(
            featureFlagger: featureFlagger,
            continuedProcessingCoordinator: continuedProcessingCoordinator,
            freemiumDBPUserStateManagerOverride: freemiumDBPUserStateManagerOverride,
            provider: provider
        )
    }

    static func makeBrokerProfileQueryData(
        brokerId: Int64,
        profileQueryId: Int64,
        scanPreferredRunDate: Date? = .now,
        optOutJobData: [OptOutJobData] = []
    ) -> BrokerProfileQueryData {
        BrokerProfileQueryData(
            dataBroker: .mock(withId: brokerId),
            profileQuery: ProfileQuery(id: profileQueryId, firstName: "A", lastName: "B", city: "C", state: "D", birthYear: 1980),
            scanJobData: .init(brokerId: brokerId, profileQueryId: profileQueryId, preferredRunDate: scanPreferredRunDate, historyEvents: []),
            optOutJobData: optOutJobData
        )
    }

    static func makeProfile() -> DataBrokerProtectionProfile {
        DataBrokerProtectionProfile(
            names: [
                .init(firstName: "A", lastName: "B")
            ],
            addresses: [
                .init(city: "C", state: "D")
            ],
            phones: [],
            birthYear: 1980
        )
    }

    @MainActor
    private final class IOSManagerTestDependenciesStore {
        let database = MockDatabase()
        let queueManager: MockJobQueueManager
        let jobDependencies = MockBrokerProfileJobDependencies()
        let authenticationManager = MockAuthenticationManager()
        let freemiumDBPUserStateManager = MockFreemiumDBPUserStateManager()
        let profileStateManager = DefaultDBPProfileStateManager(keyValueStore: UserDefaults(suiteName: UUID().uuidString)!)
        let eventsHandler = MockOperationEventsHandler()

        init() {
            queueManager = MockJobQueueManager(
                jobQueue: MockBrokerProfileJobQueue(),
                jobProvider: MockDataBrokerOperationsCreator(),
                emailConfirmationJobProvider: MockEmailConfirmationJobProvider(),
                mismatchCalculator: MockMismatchCalculator(database: database, pixelHandler: MockDataBrokerProtectionPixelsHandler()),
                pixelHandler: MockDataBrokerProtectionPixelsHandler()
            )
        }

        func makeTestIOSManager(
            featureFlagger: MockDBPFeatureFlagger,
            continuedProcessingCoordinator: MockContinuedProcessingCoordinator,
            freemiumDBPUserStateManagerOverride: FreemiumDBPUserStateManaging? = nil
        ) -> (DataBrokerProtectionIOSManager, IOSManagerTestDependencies) {
            let manager = makeManager(
                featureFlagger: featureFlagger,
                continuedProcessingCoordinator: continuedProcessingCoordinator,
                freemiumDBPUserStateManagerOverride: freemiumDBPUserStateManagerOverride
            )
            reset(manager: manager)

            return (
                manager,
                IOSManagerTestDependencies(
                    manager: manager,
                    queueManager: queueManager,
                    database: database,
                    eventsHandler: eventsHandler,
                    continuedProcessingCoordinator: continuedProcessingCoordinator,
                    authenticationManager: authenticationManager,
                    freemiumDBPUserStateManager: freemiumDBPUserStateManager,
                    profileStateManager: profileStateManager
                )
            )
        }

        func makeDeferredTestIOSManager(
            featureFlagger: MockDBPFeatureFlagger,
            continuedProcessingCoordinator: MockContinuedProcessingCoordinator,
            freemiumDBPUserStateManagerOverride: FreemiumDBPUserStateManaging? = nil,
            provider: @escaping (DBPVaultResources) -> (() throws -> DBPVaultResources)
        ) -> (DataBrokerProtectionIOSManager, IOSManagerTestDependencies) {
            let manager = makeDeferredManager(
                featureFlagger: featureFlagger,
                continuedProcessingCoordinator: continuedProcessingCoordinator,
                freemiumDBPUserStateManagerOverride: freemiumDBPUserStateManagerOverride,
                provider: provider
            )
            reset(manager: manager)

            return (
                manager,
                IOSManagerTestDependencies(
                    manager: manager,
                    queueManager: queueManager,
                    database: database,
                    eventsHandler: eventsHandler,
                    continuedProcessingCoordinator: continuedProcessingCoordinator,
                    authenticationManager: authenticationManager,
                    freemiumDBPUserStateManager: freemiumDBPUserStateManager,
                    profileStateManager: profileStateManager
                )
            )
        }

        private func makeManager(
            featureFlagger: MockDBPFeatureFlagger,
            continuedProcessingCoordinator: MockContinuedProcessingCoordinator,
            freemiumDBPUserStateManagerOverride: FreemiumDBPUserStateManaging? = nil
        ) -> DataBrokerProtectionIOSManager {
            let vaultResources = makeVaultResources()

            return DataBrokerProtectionIOSManager.withVaultResources(
                vaultResources,
                authenticationManager: authenticationManager,
                userNotificationService: MockDataBrokerProtectionUserNotificationService(),
                sharedPixelsHandler: MockDataBrokerProtectionPixelsHandler(),
                iOSPixelsHandler: EventMapping<IOSPixels> { _, _, _, _ in },
                privacyConfigManager: PrivacyConfigurationManagingMock(),
                quickLinkOpenURLHandler: { _ in },
                feedbackViewCreator: { EmptyView() },
                featureFlagger: featureFlagger,
                settings: DataBrokerProtectionSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!),
                subscriptionManager: MockDataBrokerProtectionSubscriptionManaging(),
                wideEvent: nil,
                eventsHandler: eventsHandler,
                freemiumDBPUserStateManager: (freemiumDBPUserStateManagerOverride ?? freemiumDBPUserStateManager),
                profileStateManager: profileStateManager,
                continuedProcessingCoordinator: continuedProcessingCoordinator,
                shouldRegisterBackgroundTaskHandler: false
            )
        }

        private func makeDeferredManager(
            featureFlagger: MockDBPFeatureFlagger,
            continuedProcessingCoordinator: MockContinuedProcessingCoordinator,
            freemiumDBPUserStateManagerOverride: FreemiumDBPUserStateManaging? = nil,
            provider: @escaping (DBPVaultResources) -> (() throws -> DBPVaultResources)
        ) -> DataBrokerProtectionIOSManager {
            let vaultResources = makeVaultResources()

            return DataBrokerProtectionIOSManager.withDeferredVaultResources(
                provider: provider(vaultResources),
                contentScopeProperties: vaultResources.jobDependencies.contentScopeProperties,
                authenticationManager: authenticationManager,
                userNotificationService: MockDataBrokerProtectionUserNotificationService(),
                sharedPixelsHandler: MockDataBrokerProtectionPixelsHandler(),
                iOSPixelsHandler: EventMapping<IOSPixels> { _, _, _, _ in },
                privacyConfigManager: PrivacyConfigurationManagingMock(),
                quickLinkOpenURLHandler: { _ in },
                feedbackViewCreator: { EmptyView() },
                featureFlagger: featureFlagger,
                settings: DataBrokerProtectionSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!),
                subscriptionManager: MockDataBrokerProtectionSubscriptionManaging(),
                wideEvent: nil,
                eventsHandler: eventsHandler,
                freemiumDBPUserStateManager: (freemiumDBPUserStateManagerOverride ?? freemiumDBPUserStateManager),
                profileStateManager: profileStateManager,
                continuedProcessingCoordinator: continuedProcessingCoordinator,
                shouldRegisterBackgroundTaskHandler: false
            )
        }

        private func makeVaultResources() -> DBPVaultResources {
            jobDependencies.database = database
            return DBPVaultResources(
                database: database,
                queueManager: queueManager,
                jobDependencies: jobDependencies,
                emailConfirmationDataService: MockEmailConfirmationDataServiceProvider(),
                brokerUpdaterProvider: { nil },
                engagementPixelsRepository: MockDataBrokerProtectionEngagementPixelsRepository()
            )
        }

        private func reset(manager: DataBrokerProtectionIOSManager) {
            database.clear()
            queueManager.reset()
            queueManager.delegate = manager
            jobDependencies.database = database
            authenticationManager.reset()
            eventsHandler.reset()
            freemiumDBPUserStateManager.didActivate = false
        }
    }
}
