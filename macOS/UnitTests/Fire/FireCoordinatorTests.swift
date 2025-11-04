//
//  FireCoordinatorTests.swift
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

import Testing
@testable import DuckDuckGo_Privacy_Browser
import PixelKitTestingUtilities
import Common

@MainActor
struct FireCoordinatorTests {

    let pixelFiring = PixelKitMock()
    let tabCollectionViewModel = TabCollectionViewModel(isPopup: false)
    let tld = TLD()
    let historyCoordinator = HistoryCoordinatingMock()
    let windowControllersManager = MockWindowControllerManager()
    let faviconManagement = FaviconManagerMock()

    private func makeCoordinator() -> FireCoordinator {
        let fire = Fire(cacheManager: WebCacheManagerMock(),
                        historyCoordinating: historyCoordinator,
                        permissionManager: PermissionManagerMock(),
                        windowControllersManager: windowControllersManager,
                        faviconManagement: faviconManagement,
                        tld: tld,
                        isAppActiveProvider: { true })

        let fireViewModel = FireViewModel(fire: fire)
        return FireCoordinator(tld: tld,
                               featureFlagger: MockFeatureFlagger(),
                               historyCoordinating: historyCoordinator,
                               visualizeFireAnimationDecider: nil,
                               onboardingContextualDialogsManager: nil,
                               fireproofDomains: MockFireproofDomains(),
                               faviconManagement: faviconManagement,
                               windowControllersManager: windowControllersManager,
                               pixelFiring: pixelFiring,
                               historyProvider: MockHistoryViewDataProvider(),
                               fireViewModel: fireViewModel,
                               tabViewModelGetter: ({ _ in tabCollectionViewModel }),
                               fireDialogViewFactory: { _ in TestPresenter() })
    }

    @Test func testHandleDialogResult_FiresExpectedPixels_ForCurrentTab_IncludingChatHistory() async throws {
        let coordinator = makeCoordinator()
        pixelFiring.expectedFireCalls = [
            .init(pixel: AIChatPixel.aiChatDeleteHistoryRequested, frequency: .dailyAndCount),
            .init(pixel: GeneralPixel.fireButtonFirstBurn, frequency: .legacyDailyNoSuffix),
            .init(pixel: GeneralPixel.fireButton(option: .tab), frequency: .standard)
        ]

        let result = FireDialogResult(clearingOption: .currentTab,
                                      includeHistory: true,
                                      includeTabsAndWindows: true,
                                      includeCookiesAndSiteData: true,
                                      includeChatHistory: true)
        await coordinator.handleDialogResult(result, tabCollectionViewModel: tabCollectionViewModel, isAllHistorySelected: true)

        #expect(pixelFiring.actualFireCalls == pixelFiring.expectedFireCalls)
    }

    @Test func testHandleDialogResult_FiresExpectedPixels_ForCurrentTab_NotIncludingChatHistory() async throws {
        let coordinator = makeCoordinator()
        pixelFiring.expectedFireCalls = [
            .init(pixel: GeneralPixel.fireButtonFirstBurn, frequency: .legacyDailyNoSuffix),
            .init(pixel: GeneralPixel.fireButton(option: .tab), frequency: .standard)
        ]

        let result = FireDialogResult(clearingOption: .currentTab,
                                      includeHistory: true,
                                      includeTabsAndWindows: true,
                                      includeCookiesAndSiteData: true,
                                      includeChatHistory: false)
        await coordinator.handleDialogResult(result, tabCollectionViewModel: tabCollectionViewModel, isAllHistorySelected: true)

        #expect(pixelFiring.actualFireCalls == pixelFiring.expectedFireCalls)
    }

    @Test func testHandleDialogResult_FiresExpectedPixels_ForCurrentWindow_IncludingChatHistory() async throws {
        let coordinator = makeCoordinator()
        pixelFiring.expectedFireCalls = [
            .init(pixel: AIChatPixel.aiChatDeleteHistoryRequested, frequency: .dailyAndCount),
            .init(pixel: GeneralPixel.fireButtonFirstBurn, frequency: .legacyDailyNoSuffix),
            .init(pixel: GeneralPixel.fireButton(option: .window), frequency: .standard)
        ]

        let result = FireDialogResult(clearingOption: .currentWindow,
                                      includeHistory: true,
                                      includeTabsAndWindows: true,
                                      includeCookiesAndSiteData: true,
                                      includeChatHistory: true)
        await coordinator.handleDialogResult(result, tabCollectionViewModel: tabCollectionViewModel, isAllHistorySelected: true)

        #expect(pixelFiring.actualFireCalls == pixelFiring.expectedFireCalls)
    }

    @Test func testHandleDialogResult_FiresExpectedPixels_ForCurrentWindow_NotIncludingChatHistory() async throws {
        let coordinator = makeCoordinator()
        pixelFiring.expectedFireCalls = [
            .init(pixel: GeneralPixel.fireButtonFirstBurn, frequency: .legacyDailyNoSuffix),
            .init(pixel: GeneralPixel.fireButton(option: .window), frequency: .standard)
        ]

        let result = FireDialogResult(clearingOption: .currentWindow,
                                      includeHistory: true,
                                      includeTabsAndWindows: true,
                                      includeCookiesAndSiteData: true,
                                      includeChatHistory: false)
        await coordinator.handleDialogResult(result, tabCollectionViewModel: tabCollectionViewModel, isAllHistorySelected: true)

        #expect(pixelFiring.actualFireCalls == pixelFiring.expectedFireCalls)
    }

    @Test func testHandleDialogResult_FiresExpectedPixels_ForAllData_IncludingChatHistory_WhenAllHistoryIsSelected() async throws {
        let coordinator = makeCoordinator()
        pixelFiring.expectedFireCalls = [
            .init(pixel: AIChatPixel.aiChatDeleteHistoryRequested, frequency: .dailyAndCount),
            .init(pixel: GeneralPixel.fireButtonFirstBurn, frequency: .legacyDailyNoSuffix),
            .init(pixel: GeneralPixel.fireButton(option: .allSites), frequency: .standard)
        ]

        let result = FireDialogResult(clearingOption: .allData,
                                      includeHistory: true,
                                      includeTabsAndWindows: true,
                                      includeCookiesAndSiteData: true,
                                      includeChatHistory: true)
        await coordinator.handleDialogResult(result, tabCollectionViewModel: tabCollectionViewModel, isAllHistorySelected: true)

        #expect(pixelFiring.actualFireCalls == pixelFiring.expectedFireCalls)
    }

    @Test func testHandleDialogResult_FiresExpectedPixels_ForAllData_NotIncludingChatHistory() async throws {
        let coordinator = makeCoordinator()
        pixelFiring.expectedFireCalls = [
            .init(pixel: GeneralPixel.fireButtonFirstBurn, frequency: .legacyDailyNoSuffix),
            .init(pixel: GeneralPixel.fireButton(option: .allSites), frequency: .standard)
        ]

        let result = FireDialogResult(clearingOption: .allData,
                                      includeHistory: true,
                                      includeTabsAndWindows: true,
                                      includeCookiesAndSiteData: true,
                                      includeChatHistory: false)
        await coordinator.handleDialogResult(result, tabCollectionViewModel: tabCollectionViewModel, isAllHistorySelected: true)

        #expect(pixelFiring.actualFireCalls == pixelFiring.expectedFireCalls)
    }

}

private final class TestPresenter: FireDialogViewPresenting {
    func present(in window: NSWindow, completion: (() -> Void)?) { }
}
