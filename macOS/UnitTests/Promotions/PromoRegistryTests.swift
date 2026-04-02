//
//  PromoRegistryTests.swift
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

import PersistenceTestingUtils
import PrivacyConfig
import RemoteMessaging
import RemoteMessagingTestsUtils
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class PromoRegistryTests: XCTestCase {

    func testWhenPromoServiceCreated_ThenAllStringsAreUnique() async {
        let store = MockRemoteMessagingStore()
        let activeRemoteMessageModel = ActiveRemoteMessageModel(
            remoteMessagingStore: store,
            remoteMessagingAvailabilityProvider: MockRemoteMessagingAvailabilityProvider(),
            openURLHandler: { _ in },
            navigateToFeedbackHandler: { },
            navigateToPIRHandler: { },
            navigateToSoftwareUpdateHandler: { }
        )
        let defaultBrowserAndDockPromptService = DefaultBrowserAndDockPromptService(
            privacyConfigManager: MockPrivacyConfigurationManaging(),
            keyValueStore: InMemoryThrowingKeyValueStore(),
            notificationPresenter: MockDefaultBrowserAndDockPromptNotificationPresenter(),
            uiHosting: { nil },
            isOnboardingCompletedProvider: { true },
            dockCustomization: DockCustomizerMock()
        )
        let dependencies = PromoDependencies(
            keyValueStore: InMemoryThrowingKeyValueStore(),
            isExternallyActivated: false,
            isOnboardingCompletedProvider: { true },
            activeRemoteMessageModel: activeRemoteMessageModel,
            defaultBrowserAndDockPromptService: defaultBrowserAndDockPromptService,
            sessionRestoreCoordinator: SessionRestorePromptCoordinatorMock())
        let promoService = PromoServiceFactory.makePromoService(dependencies: dependencies)

        let ids = promoService.promos.map(\.id)
        let uniqueIds = Set(ids)
        XCTAssertEqual(ids.count, uniqueIds.count, "Promo IDs must be unique. Duplicates: \(ids.filter { id in ids.filter { $0 == id }.count > 1 })")
    }
}
