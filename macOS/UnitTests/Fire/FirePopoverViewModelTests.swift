//
//  FirePopoverViewModelTests.swift
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

import Common
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class FirePopoverViewModelTests: XCTestCase {

    @MainActor
    private func makeViewModel(
        with tabCollectionViewModel: TabCollectionViewModel,
        onboardingContextualDialogsManager: ContextualOnboardingStateUpdater = ContextualDialogsManager(trackerMessageProvider: MockTrackerMessageProvider())
    ) -> FirePopoverViewModel {
        let manager = WebCacheManagerMock()
        let historyCoordinator = HistoryCoordinatingMock()
        let permissionManager = PermissionManagerMock()
        let faviconManager = FaviconManagerMock()
        let fire = Fire(cacheManager: manager,
                        historyCoordinating: historyCoordinator,
                        permissionManager: permissionManager,
                        windowControllerManager: Application.appDelegate.windowControllersManager,
                        faviconManagement: faviconManager,
                        tld: Application.appDelegate.tld)
        return FirePopoverViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionViewModel,
            historyCoordinating: HistoryCoordinatingMock(),
            fireproofDomains: FireproofDomains(store: FireproofDomainsStoreMock(), tld: TLD()),
            faviconManagement: FaviconManagerMock(),
            tld: Application.appDelegate.tld,
            onboardingContextualDialogsManager: onboardingContextualDialogsManager
        )
    }

    @MainActor func testOnBurn_OnboardingContextualDialogsManagerFireButtonUsedCalled() {
        // Given
        let tabCollectionVM = TabCollectionViewModel()
        let onboardingContextualDialogsManager = CapturingContextualOnboardingStateUpdater()
        let vm = makeViewModel(with: tabCollectionVM, onboardingContextualDialogsManager: onboardingContextualDialogsManager)
        XCTAssertNil(onboardingContextualDialogsManager.updatedForTab)
        XCTAssertFalse(onboardingContextualDialogsManager.gotItPressedCalled)
        XCTAssertFalse(onboardingContextualDialogsManager.fireButtonUsedCalled)

        // When
        vm.burn()

        // Then
        XCTAssertNil(onboardingContextualDialogsManager.updatedForTab)
        XCTAssertFalse(onboardingContextualDialogsManager.gotItPressedCalled)
        XCTAssertTrue(onboardingContextualDialogsManager.fireButtonUsedCalled)
    }
}

class CapturingContextualOnboardingStateUpdater: ContextualOnboardingStateUpdater {

    var state: ContextualOnboardingState = .onboardingCompleted

    @Published var isContextualOnboardingCompleted: Bool = true
    var isContextualOnboardingCompletedPublisher: Published<Bool>.Publisher { $isContextualOnboardingCompleted }

    var updatedForTab: Tab?
    var gotItPressedCalled = false
    var fireButtonUsedCalled = false

    func updateStateFor(tab: Tab) {
        updatedForTab = tab
    }

    func gotItPressed() {
        gotItPressedCalled = true
    }

    func fireButtonUsed() {
        fireButtonUsedCalled = true
    }

    func turnOffFeature() {}

}
