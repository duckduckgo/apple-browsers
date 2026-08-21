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
import Combine
import Common
import FeatureFlags_macOS
import FoundationExtensions
@_spi(Testing) import PixelKit
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
    @Test(.timeLimit(.minutes(1))) func testHandleDialogResult_ForCurrentTab_ShowsTabScopedDeletingDataMessage() async throws {
        let messages = await deletingDataMessages(for: makeDialogResult(clearingOption: .currentTab), isAllHistorySelected: true)

        #expect(messages == [UserText.fireDialogDeletingDataFromThisTab])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1))) func testHandleDialogResult_ForAllData_ShowsAllDataDeletingDataMessage() async throws {
        let messages = await deletingDataMessages(for: makeDialogResult(clearingOption: .allData), isAllHistorySelected: true)

        #expect(messages == [UserText.fireDialogDeletingAllData])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1))) func testHandleDialogResult_ForAllDataKeepingTabsAndWindows_ShowsAllDataDeletingDataMessage() async throws {
        // This burns all windows as an entity instead of burning all data.
        let result = makeDialogResult(clearingOption: .allData, includeTabsAndWindows: false)
        let messages = await deletingDataMessages(for: result, isAllHistorySelected: true)

        #expect(messages == [UserText.fireDialogDeletingAllData])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1))) func testHandleDialogResult_ForCurrentWindow_ShowsGenericDeletingDataMessage() async throws {
        let messages = await deletingDataMessages(for: makeDialogResult(clearingOption: .currentWindow), isAllHistorySelected: true)

        #expect(messages == [UserText.fireDialogDeletingData])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1))) func testBurnVisitsFromToday_ShowsGenericDeletingDataMessage() async throws {
        // Burning today's visits burns all windows, but it only deletes the selected visits.
        let messages = await deletingDataMessages { coordinator in
            await coordinator.fireViewModel.fire.burnVisits([],
                                                            except: coordinator.fireViewModel.fire.fireproofDomains,
                                                            isToday: true,
                                                            closeWindows: true,
                                                            clearSiteData: true,
                                                            clearChatHistory: false)
        }

        #expect(messages == [UserText.fireDialogDeletingData])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1))) func testHandleDialogResult_WhenFireDialogIsNotSimplified_ShowsGenericDeletingDataMessage() async throws {
        let messages = await deletingDataMessages(for: makeDialogResult(clearingOption: .currentTab),
                                                  isAllHistorySelected: true,
                                                  isFireDialogSimplified: false)

        #expect(messages == [UserText.fireDialogDeletingData])
    }

    private func makeDialogResult(clearingOption: FireDialogViewModel.ClearingOption, includeTabsAndWindows: Bool = true) -> FireDialogResult {
        FireDialogResult(clearingOption: clearingOption,
                         includeHistory: true,
                         includeTabsAndWindows: includeTabsAndWindows,
                         includeCookiesAndSiteData: true,
                         includeChatHistory: false)
    }

    /// Collects the text of the burning progress dialog for all burns started by `result`.
    private func deletingDataMessages(for result: FireDialogResult,
                                      isAllHistorySelected: Bool,
                                      isFireDialogSimplified: Bool = true) async -> [String] {
        await deletingDataMessages(isFireDialogSimplified: isFireDialogSimplified) { coordinator in
            await coordinator.handleDialogResult(result,
                                                 tabCollectionViewModel: tabCollectionViewModel,
                                                 isAllHistorySelected: isAllHistorySelected)
        }
    }

    /// Collects the text of the burning progress dialog for all burns started by `burn`.
    private func deletingDataMessages(isFireDialogSimplified: Bool = true,
                                      during burn: @MainActor (FireCoordinator) async -> Void) async -> [String] {
        let coordinator = makeCoordinator()
        let featureFlagger = MockFeatureFlagger(featuresStub: [FeatureFlag.fireDialogSimplified.rawValue: isFireDialogSimplified])
        var messages = [String]()
        let cancellable = coordinator.fireViewModel.fire.burningDataPublisher
            .compactMap { $0?.deletingDataMessage(featureFlagger: featureFlagger) }
            .sink { messages.append($0) }
        defer { cancellable.cancel() }

        await burn(coordinator)

        return messages
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

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1))) func testPresentFireDialog_whenTabIsAddedWhileDialogIsOpen_thenDialogIsClosed() async throws {
        // Scenario: A link opened from another app adds a tab to the window while the dialog is open.
        // Expectation: The dialog is closed, and it deletes nothing, because what it shows was read
        // when it opened and no longer matches the tabs of the window.

        var presenter: SheetLikeFireDialogPresenter?
        var wasClosedByTabsChange = false
        let factory: FireDialogViewFactory = { _ in
            let sheetLikePresenter = SheetLikeFireDialogPresenter { [self] in
                _ = tabCollectionViewModel.append(tab: Tab(content: .newtab))
                wasClosedByTabsChange = (presenter?.dismissCallCount ?? 0) >= 1
                // Finish the presentation, so that a regression fails here and not on the time limit.
                presenter?.complete()
            }
            presenter = sheetLikePresenter
            return sheetLikePresenter
        }
        let coordinator = makeCoordinator(fireDialogViewFactory: factory)

        let response = await coordinator.presentFireDialog(mode: .fireButton, in: MockWindow(isVisible: false), settings: nil)

        #expect(wasClosedByTabsChange, "The dialog should be closed when a tab is added")
        if case .burn = response {
            Issue.record("A closed dialog should delete nothing")
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1))) func testPresentFireDialog_whenTabIsAddedAfterDialogIsClosed_thenNothingIsDismissed() async throws {
        // Scenario: The tabs of the window change after the dialog was closed, which is what burning
        // the data does itself.
        // Expectation: The closed dialog no longer watches the tabs.

        var presenter: SheetLikeFireDialogPresenter?
        let factory: FireDialogViewFactory = { config in
            let sheetLikePresenter = SheetLikeFireDialogPresenter {
                config.onConfirm(.noAction)
            }
            presenter = sheetLikePresenter
            return sheetLikePresenter
        }
        let coordinator = makeCoordinator(fireDialogViewFactory: factory)

        _ = await coordinator.presentFireDialog(mode: .fireButton, in: MockWindow(isVisible: false), settings: nil)
        _ = tabCollectionViewModel.append(tab: Tab(content: .newtab))

        #expect(presenter?.dismissCallCount == 0, "The dialog was closed by the user, so nothing should dismiss it again")
    }

}

private final class MockTabCleanupPreparer: TabCleanupPreparing {
    func prepareTabsForCleanup(_ tabs: [any TabDataClearing]) async {}
}

private final class TestPresenter: FireDialogViewPresenting {
    func present(in window: NSWindow, completion: (() -> Void)?) { }
    func dismiss() { }
}

private final class CallbackFireDialogPresenter: FireDialogViewPresenting {
    private let onPresent: () -> Void

    init(onPresent: @escaping () -> Void) {
        self.onPresent = onPresent
    }

    func present(in window: NSWindow, completion: (() -> Void)?) {
        onPresent()
    }

    func dismiss() { }
}

/// A presenter that stays presented until it is dismissed, like the sheet of the real dialog does.
private final class SheetLikeFireDialogPresenter: FireDialogViewPresenting {
    private let onPresent: () -> Void
    private var completion: (() -> Void)?
    private(set) var dismissCallCount = 0

    init(onPresent: @escaping () -> Void = {}) {
        self.onPresent = onPresent
    }

    func present(in window: NSWindow, completion: (() -> Void)?) {
        self.completion = completion
        onPresent()
    }

    func dismiss() {
        dismissCallCount += 1
        complete()
    }

    /// Finishes the presentation, like the sheet does when it closes. Does nothing when finished.
    func complete() {
        let completion = self.completion
        self.completion = nil
        completion?()
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
