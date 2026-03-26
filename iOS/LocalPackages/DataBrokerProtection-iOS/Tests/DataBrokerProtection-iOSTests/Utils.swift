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
}

@MainActor
enum DBPContinuedProcessingTestUtils {
    static func makeTestIOSManager(
        featureFlagger: MockDBPFeatureFlagger = MockDBPFeatureFlagger(),
        continuedProcessingCoordinator: MockContinuedProcessingCoordinator = MockContinuedProcessingCoordinator()
    ) -> (DataBrokerProtectionIOSManager, IOSManagerTestDependencies) {
        return IOSManagerTestDependenciesStore().makeTestIOSManager(
            featureFlagger: featureFlagger,
            continuedProcessingCoordinator: continuedProcessingCoordinator
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
            continuedProcessingCoordinator: MockContinuedProcessingCoordinator
        ) -> (DataBrokerProtectionIOSManager, IOSManagerTestDependencies) {
            let manager = makeManager(
                featureFlagger: featureFlagger,
                continuedProcessingCoordinator: continuedProcessingCoordinator
            )
            reset(manager: manager)

            return (
                manager,
                IOSManagerTestDependencies(
                    manager: manager,
                    queueManager: queueManager,
                    database: database,
                    eventsHandler: eventsHandler,
                    continuedProcessingCoordinator: continuedProcessingCoordinator
                )
            )
        }

        private func makeManager(
            featureFlagger: MockDBPFeatureFlagger,
            continuedProcessingCoordinator: MockContinuedProcessingCoordinator
        ) -> DataBrokerProtectionIOSManager {
            jobDependencies.database = database

            return DataBrokerProtectionIOSManager(
                queueManager: queueManager,
                jobDependencies: jobDependencies,
                emailConfirmationDataService: MockEmailConfirmationDataServiceProvider(),
                authenticationManager: authenticationManager,
                userNotificationService: MockDataBrokerProtectionUserNotificationService(),
                sharedPixelsHandler: MockDataBrokerProtectionPixelsHandler(),
                iOSPixelsHandler: EventMapping<IOSPixels> { _, _, _, _ in },
                privacyConfigManager: PrivacyConfigurationManagingMock(),
                database: database,
                quickLinkOpenURLHandler: { _ in },
                feedbackViewCreator: { EmptyView() },
                featureFlagger: featureFlagger,
                settings: DataBrokerProtectionSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!),
                subscriptionManager: MockDataBrokerProtectionSubscriptionManaging(),
                wideEvent: nil,
                eventsHandler: eventsHandler,
                engagementPixelsRepository: MockDataBrokerProtectionEngagementPixelsRepository(),
                continuedProcessingCoordinator: continuedProcessingCoordinator,
                shouldRegisterBackgroundTaskHandler: false
            )
        }

        private func reset(manager: DataBrokerProtectionIOSManager) {
            database.clear()
            queueManager.reset()
            queueManager.delegate = manager
            jobDependencies.database = database
            authenticationManager.reset()
            eventsHandler.reset()
        }
    }
}
