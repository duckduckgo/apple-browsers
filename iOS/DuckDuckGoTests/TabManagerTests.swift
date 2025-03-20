//
//  TabManagerTests.swift
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

import XCTest
import Core
@testable import DuckDuckGo
import SubscriptionTestingUtilities

@MainActor
final class TabManagerTests: XCTestCase {

    func testWhenAppBecomesActiveAndExcessPreviewsThenCleanUpHappens() async throws {
        let mock = MockTabPreviewsSource(totalStoredPreviews: 4)
        let tabsModel = TabsModel(desktop: false)
        tabsModel.add(tab: Tab())
        tabsModel.add(tab: Tab())
        let manager = makeManager(tabsModel, previewsSource: mock)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        try await Task.sleep(interval: 0.5)
        XCTAssertEqual(1, mock.removePreviewsWithIdNotInCalls.count)

        // This is just to keep a reference to the manager to supress the unused warning and keep it from being deinit
        manager.removeAll()
    }

    func makeManager(_ model: TabsModel, previewsSource: TabPreviewsSource) -> TabManager {
        return TabManager(model: model,
                          previewsSource: previewsSource,
                          interactionStateSource: TabInteractionStateDiskSource(),
                          bookmarksDatabase: MockBookmarksDatabase.make(prepareFolderStructure: false),
                          historyManager: MockHistoryManager(),
                          syncService: MockDDGSyncing(),
                          privacyProDataReporter: MockPrivacyProDataReporter(),
                          contextualOnboardingPresenter: ContextualOnboardingPresenterMock(),
                          contextualOnboardingLogic: ContextualOnboardingLogicMock(),
                          onboardingPixelReporter: OnboardingPixelReporterMock(),
                          featureFlagger: MockFeatureFlagger(),
                          subscriptionCookieManager: SubscriptionCookieManagerMock(),
                          appSettings: AppSettingsMock(),
                          textZoomCoordinator: MockTextZoomCoordinator(),
                          websiteDataManager: MockWebsiteDataManager(),
                          fireproofing: MockFireproofing(),
                          maliciousSiteProtectionManager: MockMaliciousSiteProtectionManager(),
                          maliciousSiteProtectionPreferencesManager: MockMaliciousSiteProtectionPreferencesManager())
    }

}
