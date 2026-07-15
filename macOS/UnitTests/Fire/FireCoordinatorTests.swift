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

import AppKit
import Common
import FoundationExtensions
import PixelKitTestingUtilities
import PrivacyConfig
import SharedTestUtilities
import Testing

@testable import DuckDuckGo_Privacy_Browser

@MainActor
struct FireCoordinatorTests {

    let pixelFiring = PixelKitMock()
    let tabCollectionViewModel = TabCollectionViewModel(isPopup: false)
    let tld = TLD()
    let historyCoordinator = HistoryCoordinatingMock()
    let windowControllersManager = MockWindowControllerManager()
    let faviconManagement = FaviconManagerMock()

    private func makeCoordinator(
        onboardingFireReporting: (() -> OnboardingFireReporting)? = nil,
        fireDialogViewFactory: FireDialogViewFactory? = nil
    ) -> FireCoordinator {
        let fire = Fire(cacheManager: WebCacheManagerMock(),
                        historyCoordinating: historyCoordinator,
                        permissionManager: PermissionManagerMock(),
                        windowControllersManager: windowControllersManager,
                        faviconManagement: faviconManagement,
                        tld: tld,
                        isAppActiveProvider: { true },
                        tabCleanupPreparer: MockTabCleanupPreparer())

        let fireViewModel = FireViewModel(fire: fire)
        return FireCoordinator(tld: tld,
                               featureFlagger: MockFeatureFlagger(),
                               historyCoordinating: historyCoordinator,
                               visualizeFireAnimationDecider: nil,
                               onboardingContextualDialogsManager: nil,
                               fireproofDomains: MockFireproofDomains(),
                               faviconManagement: faviconManagement,
                               windowControllersManager: windowControllersManager,
                               dataClearingPreferences: Application.appDelegate.dataClearingPreferences,
                               pixelFiring: pixelFiring,
                               wideEventManaging: WideEventMock(),
                               historyProvider: MockHistoryViewDataProvider(),
                               fireViewModel: fireViewModel,
                               tabViewModelGetter: ({ _ in tabCollectionViewModel }),
                               fireDialogViewFactory: fireDialogViewFactory ?? { _ in TestPresenter() },
                               onboardingFireReporting: onboardingFireReporting)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1))) func testHandleDialogResult_FiresExpectedPixels_ForCurrentTab_IncludingChatHistory() async throws {
        let coordinator = makeCoordinator()
        let currentTime = CACurrentMediaTime()
        pixelFiring.expectedFireCalls = [
            .init(pixel: AIChatPixel.aiChatDeleteHistoryRequested, frequency: .dailyAndCount),
            .init(pixel: GeneralPixel.fireButton(option: .tab), frequency: .standard),
            .init(
                pixel: FireDialogPixel.burn(
                    .currentTab(
                        .init(pinned: false, closeTab: true, clearHistory: true, clearSiteData: true)
                    )
                ),
                frequency: .dailyAndCount,
                doNotEnforcePrefix: true
            ),
            .init(pixel: GeneralPixel.fireButtonFirstBurn, frequency: .legacyDailyNoSuffix),
            .init(pixel: FireDialogPixel.fireStarted, frequency: .dailyAndCount, doNotEnforcePrefix: true),
            .init(pixel: FireDialogPixel.fireStartedInSession, frequency: .dailyAndCount, doNotEnforcePrefix: true)
        ]

        let result = FireDialogResult(clearingOption: .currentTab,
                                      includeHistory: true,
                                      includeTabsAndWindows: true,
                                      includeCookiesAndSiteData: true,
                                      includeChatHistory: true)
        await coordinator.handleDialogResult(result, tabCollectionViewModel: tabCollectionViewModel, isAllHistorySelected: true, from: currentTime)

        #expect(pixelFiring.actualFireCalls == pixelFiring.expectedFireCalls)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1))) func testHandleDialogResult_FiresExpectedPixels_ForCurrentTab_NotIncludingChatHistory() async throws {
        let coordinator = makeCoordinator()
        pixelFiring.expectedFireCalls = [
            .init(pixel: GeneralPixel.fireButton(option: .tab), frequency: .standard),
            .init(
                pixel: FireDialogPixel.burn(
                    .currentTab(
                        .init(pinned: false, closeTab: true, clearHistory: true, clearSiteData: true)
                    )
                ),
                frequency: .dailyAndCount,
                doNotEnforcePrefix: true
            ),
            .init(pixel: GeneralPixel.fireButtonFirstBurn, frequency: .legacyDailyNoSuffix),
            .init(pixel: FireDialogPixel.fireStarted, frequency: .dailyAndCount, doNotEnforcePrefix: true),
            .init(pixel: FireDialogPixel.fireStartedInSession, frequency: .dailyAndCount, doNotEnforcePrefix: true)
        ]

        let result = FireDialogResult(clearingOption: .currentTab,
                                      includeHistory: true,
                                      includeTabsAndWindows: true,
                                      includeCookiesAndSiteData: true,
                                      includeChatHistory: false)
        await coordinator.handleDialogResult(result, tabCollectionViewModel: tabCollectionViewModel, isAllHistorySelected: true)

        #expect(pixelFiring.actualFireCalls == pixelFiring.expectedFireCalls)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1))) func testHandleDialogResult_FiresExpectedPixels_ForCurrentWindow_IncludingChatHistory() async throws {
        let coordinator = makeCoordinator()
        pixelFiring.expectedFireCalls = [
            .init(pixel: AIChatPixel.aiChatDeleteHistoryRequested, frequency: .dailyAndCount),
            .init(pixel: GeneralPixel.fireButton(option: .window), frequency: .standard),
            .init(
                pixel: FireDialogPixel.burn(
                    .currentWindow(
                        .init(hasPinnedTabs: !tabCollectionViewModel.pinnedTabs.isEmpty, closeWindow: true, clearHistory: true, clearSiteData: true)
                    )
                ),
                frequency: .dailyAndCount,
                doNotEnforcePrefix: true
            ),
            .init(pixel: GeneralPixel.fireButtonFirstBurn, frequency: .legacyDailyNoSuffix),
            .init(pixel: FireDialogPixel.fireStarted, frequency: .dailyAndCount, doNotEnforcePrefix: true),
            .init(pixel: FireDialogPixel.fireStartedInSession, frequency: .dailyAndCount, doNotEnforcePrefix: true)
        ]

        let result = FireDialogResult(clearingOption: .currentWindow,
                                      includeHistory: true,
                                      includeTabsAndWindows: true,
                                      includeCookiesAndSiteData: true,
                                      includeChatHistory: true)
        await coordinator.handleDialogResult(result, tabCollectionViewModel: tabCollectionViewModel, isAllHistorySelected: true)

        #expect(pixelFiring.actualFireCalls == pixelFiring.expectedFireCalls)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1))) func testHandleDialogResult_FiresExpectedPixels_ForCurrentWindow_NotIncludingChatHistory() async throws {
        let coordinator = makeCoordinator()
        pixelFiring.expectedFireCalls = [
            .init(pixel: GeneralPixel.fireButton(option: .window), frequency: .standard),
            .init(
                pixel: FireDialogPixel.burn(
                    .currentWindow(
                        .init(hasPinnedTabs: !tabCollectionViewModel.pinnedTabs.isEmpty, closeWindow: true, clearHistory: true, clearSiteData: true)
                    )
                ),
                frequency: .dailyAndCount,
                doNotEnforcePrefix: true
            ),
            .init(pixel: GeneralPixel.fireButtonFirstBurn, frequency: .legacyDailyNoSuffix),
            .init(pixel: FireDialogPixel.fireStarted, frequency: .dailyAndCount, doNotEnforcePrefix: true),
            .init(pixel: FireDialogPixel.fireStartedInSession, frequency: .dailyAndCount, doNotEnforcePrefix: true)
        ]

        let result = FireDialogResult(clearingOption: .currentWindow,
                                      includeHistory: true,
                                      includeTabsAndWindows: true,
                                      includeCookiesAndSiteData: true,
                                      includeChatHistory: false)
        await coordinator.handleDialogResult(result, tabCollectionViewModel: tabCollectionViewModel, isAllHistorySelected: true)

        #expect(pixelFiring.actualFireCalls == pixelFiring.expectedFireCalls)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1))) func testHandleDialogResult_FiresExpectedPixels_ForAllData_IncludingChatHistory_WhenAllHistoryIsSelected() async throws {
        let coordinator = makeCoordinator()
        pixelFiring.expectedFireCalls = [
            .init(pixel: AIChatPixel.aiChatDeleteHistoryRequested, frequency: .dailyAndCount),
            .init(pixel: GeneralPixel.fireButton(option: .allSites), frequency: .standard),
            .init(
                pixel: FireDialogPixel.burn(
                    .allData(
                        .init(hasPinnedTabs: !windowControllersManager.pinnedTabsManagerProvider.arePinnedTabsEmpty, closeWindows: true, clearHistory: true, clearSiteData: true, clearAIChats: true)
                    )
                ),
                frequency: .dailyAndCount,
                doNotEnforcePrefix: true
            ),
            .init(pixel: GeneralPixel.fireButtonFirstBurn, frequency: .legacyDailyNoSuffix),
            .init(pixel: FireDialogPixel.fireStarted, frequency: .dailyAndCount, doNotEnforcePrefix: true),
            .init(pixel: FireDialogPixel.fireStartedInSession, frequency: .dailyAndCount, doNotEnforcePrefix: true)
        ]

        let result = FireDialogResult(clearingOption: .allData,
                                      includeHistory: true,
                                      includeTabsAndWindows: true,
                                      includeCookiesAndSiteData: true,
                                      includeChatHistory: true)
        await coordinator.handleDialogResult(result, tabCollectionViewModel: tabCollectionViewModel, isAllHistorySelected: true)

        #expect(pixelFiring.actualFireCalls == pixelFiring.expectedFireCalls)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1))) func testHandleDialogResult_FiresExpectedPixels_ForAllData_NotIncludingChatHistory() async throws {
        let coordinator = makeCoordinator()
        pixelFiring.expectedFireCalls = [
            .init(pixel: GeneralPixel.fireButton(option: .allSites), frequency: .standard),
            .init(
                pixel: FireDialogPixel.burn(
                    .allData(
                        .init(hasPinnedTabs: !windowControllersManager.pinnedTabsManagerProvider.arePinnedTabsEmpty, closeWindows: true, clearHistory: true, clearSiteData: true, clearAIChats: false)
                    )
                ),
                frequency: .dailyAndCount,
                doNotEnforcePrefix: true
            ),
            .init(pixel: GeneralPixel.fireButtonFirstBurn, frequency: .legacyDailyNoSuffix),
            .init(pixel: FireDialogPixel.fireStarted, frequency: .dailyAndCount, doNotEnforcePrefix: true),
            .init(pixel: FireDialogPixel.fireStartedInSession, frequency: .dailyAndCount, doNotEnforcePrefix: true)
        ]

        let result = FireDialogResult(clearingOption: .allData,
                                      includeHistory: true,
                                      includeTabsAndWindows: true,
                                      includeCookiesAndSiteData: true,
                                      includeChatHistory: false)
        await coordinator.handleDialogResult(result, tabCollectionViewModel: tabCollectionViewModel, isAllHistorySelected: true)

        #expect(pixelFiring.actualFireCalls == pixelFiring.expectedFireCalls)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1))) func testPresentFireDialog_whenUserDismisses_thenMeasureFireDialogDismissedCalled() async throws {
        let mockFireReporting = MockOnboardingFireReporting()
        let factory: FireDialogViewFactory = { config in
            CallbackFireDialogPresenter {
                config.onConfirm(.noAction)
            }
        }
        let coordinator = makeCoordinator(onboardingFireReporting: { mockFireReporting }, fireDialogViewFactory: factory)

        _ = await coordinator.presentFireDialog(mode: .fireButton, in: MockWindow(isVisible: false), settings: nil)

        #expect(mockFireReporting.measureFireDialogDismissedCallCount == 1)
        #expect(mockFireReporting.measureFireDialogBurnActionCallCount == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1))) func testPresentFireDialog_whenUserConfirmsBurn_thenMeasureFireDialogBurnActionCalled() async throws {
        let mockFireReporting = MockOnboardingFireReporting()
        let burnResult = FireDialogResult(clearingOption: .currentWindow,
                                          includeHistory: true,
                                          includeTabsAndWindows: true,
                                          includeCookiesAndSiteData: true,
                                          includeChatHistory: false)
        let factory: FireDialogViewFactory = { config in
            CallbackFireDialogPresenter {
                config.onConfirm(.burn(options: burnResult))
            }
        }
        let coordinator = makeCoordinator(onboardingFireReporting: { mockFireReporting }, fireDialogViewFactory: factory)

        _ = await coordinator.presentFireDialog(mode: .fireButton, in: MockWindow(isVisible: false), settings: nil)

        #expect(mockFireReporting.measureFireDialogBurnActionCallCount == 1)
        #expect(mockFireReporting.measureFireDialogDismissedCallCount == 0)
    }

}

private final class MockTabCleanupPreparer: TabCleanupPreparing {
    func prepareTabsForCleanup(_ tabs: [any TabDataClearing]) async {}
}

private final class TestPresenter: FireDialogViewPresenting {
    func present(in window: NSWindow, completion: (() -> Void)?) { }
}

private final class CallbackFireDialogPresenter: FireDialogViewPresenting {
    private let onPresent: () -> Void

    init(onPresent: @escaping () -> Void) {
        self.onPresent = onPresent
    }

    func present(in window: NSWindow, completion: (() -> Void)?) {
        onPresent()
    }
}

private final class MockOnboardingFireReporting: OnboardingFireReporting {
    var measureFireButtonPressedCallCount = 0
    var measureFireDialogBurnActionCallCount = 0
    var measureFireDialogDismissedCallCount = 0

    func measureFireButtonPressed() {
        measureFireButtonPressedCallCount += 1
    }

    func measureFireDialogBurnAction() {
        measureFireDialogBurnActionCallCount += 1
    }

    func measureFireDialogDismissed() {
        measureFireDialogDismissedCallCount += 1
    }
}
