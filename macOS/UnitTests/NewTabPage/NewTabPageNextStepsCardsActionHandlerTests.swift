//
//  NewTabPageNextStepsCardsActionHandlerTests.swift
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
@testable import DuckDuckGo_Privacy_Browser
import PrivacyConfigTestsUtils
import Subscription
import XCTest
import PrivacyConfig

final class NewTabPageNextStepsCardsActionHandlerTests: XCTestCase {
    private var actionHandler: NewTabPageNextStepsCardsActionHandler!
    private var capturingDefaultBrowserProvider: CapturingDefaultBrowserProvider!
    private var capturingDataImportProvider: CapturingDataImportProvider!
    private var tabOpener: MockTabOpener!
    private var privacyConfigManager: MockPrivacyConfigurationManager!
    private var dockCustomizer: DockCustomization!
    private var pixelHandler: MockNewTabPageNextStepsCardsPixelHandler!
    private var navigator: MockNavigator!
    private var syncLauncher: MockSyncLauncher!
    private var featureFlagger: MockFeatureFlagger!

    @MainActor override func setUp() {
        capturingDefaultBrowserProvider = CapturingDefaultBrowserProvider()
        dockCustomizer = DockCustomizerMock()
        capturingDataImportProvider = CapturingDataImportProvider()
        tabOpener = MockTabOpener()
        privacyConfigManager = MockPrivacyConfigurationManager()
        let config = MockPrivacyConfiguration()
        privacyConfigManager.privacyConfig = config
        pixelHandler = MockNewTabPageNextStepsCardsPixelHandler()
        navigator = MockNavigator()
        syncLauncher = MockSyncLauncher()
        featureFlagger = MockFeatureFlagger()

        actionHandler = NewTabPageNextStepsCardsActionHandler(
            defaultBrowserProvider: capturingDefaultBrowserProvider,
            dockCustomizer: dockCustomizer,
            dataImportProvider: capturingDataImportProvider,
            tabOpener: tabOpener,
            privacyConfigurationManager: privacyConfigManager,
            pixelHandler: pixelHandler,
            newTabPageNavigator: navigator,
            syncLauncher: syncLauncher,
            featureFlagger: featureFlagger
        )
    }

    override func tearDown() {
        actionHandler = nil
        capturingDefaultBrowserProvider = nil
        capturingDataImportProvider = nil
        tabOpener = nil
        dockCustomizer = nil
        privacyConfigManager = nil
        pixelHandler = nil
        navigator = nil
        syncLauncher = nil
        featureFlagger = nil
    }

    @MainActor func testWhenAskedToPerformActionForDefaultBrowserCardThenItPresentsTheDefaultBrowserPrompt() {
        actionHandler.performAction(for: .defaultApp, refreshCardsAction: nil)

        XCTAssertTrue(capturingDefaultBrowserProvider.presentDefaultBrowserPromptCalled)
        XCTAssertFalse(capturingDefaultBrowserProvider.openSystemPreferencesCalled)
    }

    @MainActor func testWhenAskedToPerformActionForDefaultBrowserCardAndDefaultBrowserPromptThrowsThenItOpensSystemPreferences() {
        capturingDefaultBrowserProvider.throwError = true
        actionHandler.performAction(for: .defaultApp, refreshCardsAction: nil)

        XCTAssertTrue(capturingDefaultBrowserProvider.presentDefaultBrowserPromptCalled)
        XCTAssertTrue(capturingDefaultBrowserProvider.openSystemPreferencesCalled)
    }

    @MainActor func testWhenAskedToPerformActionForDockAndFeatureFlagEnabledThenItAddsAppToDockAndCallsRefreshCardsAction() {
        var cardsRefreshed = false
        featureFlagger.enabledFeatureFlags = [.nextStepsSingleCardIteration]
        actionHandler.performAction(for: .addAppToDockMac, refreshCardsAction: { cardsRefreshed = true })

        XCTAssertTrue(dockCustomizer.isAddedToDock)
        XCTAssertTrue(cardsRefreshed)
    }

    @MainActor func testWhenAskedToPerformActionForDockAndFeatureFlagDisabledThenItAddsAppToDockWithoutRefreshCardsAction() {
        var cardsRefreshed = false
        featureFlagger.enabledFeatureFlags = []
        actionHandler.performAction(for: .addAppToDockMac, refreshCardsAction: { cardsRefreshed = true })

        XCTAssertTrue(dockCustomizer.isAddedToDock)
        XCTAssertFalse(cardsRefreshed)
    }

    @MainActor func testWhenAskedToPerformActionForImportPromptThenItOpensImportWindowAndCallsRefreshCardsAction() {
        var cardsRefreshed = false
        actionHandler.performAction(for: .bringStuff, refreshCardsAction: { cardsRefreshed = true })

        XCTAssertTrue(capturingDataImportProvider.showImportWindowCalled)
        XCTAssertTrue(cardsRefreshed)
    }

    @MainActor func testWhenAskedToPerformActionForEmailProtectionThenItOpensEmailProtectionSite() {
        actionHandler.performAction(for: .emailProtection, refreshCardsAction: nil)

        XCTAssertEqual(tabOpener.openedTabs.count, 1)
        XCTAssertEqual(tabOpener.openedTabs.first?.url, EmailUrls().emailProtectionLink)
    }

    @MainActor func testWhenAskedToPerformActionForDuckPlayerThenItOpensYoutubeVideo() {
        actionHandler.performAction(for: .duckplayer, refreshCardsAction: nil)

        XCTAssertEqual(tabOpener.openedTabs.count, 1)
        XCTAssertEqual(tabOpener.openedTabs.first?.url, URL(string: actionHandler.duckPlayerURL))
    }

    @MainActor func testWhenAskedToPerformActionForSubscriptionThenItOpensSubscriptionSite() {
        actionHandler.performAction(for: .subscription, refreshCardsAction: nil)

        let expectedURL = SubscriptionURL.purchaseURLComponentsWithOrigin(SubscriptionFunnelOrigin.newTabPageNextStepsCard.rawValue)?.url

        XCTAssertEqual(tabOpener.openedTabs.count, 1)
        XCTAssertEqual(tabOpener.openedTabs.first?.url, expectedURL)
    }

    @MainActor func testWhenAskedToPerformActionForPersonalizeBrowserThenItOpensCustomization() {
        actionHandler.performAction(for: .personalizeBrowser, refreshCardsAction: nil)

        XCTAssertTrue(navigator.customizationSettingsOpened)
    }

    @MainActor func testWhenAskedToPerformActionForSyncThenItStartsSyncFlow() {
        actionHandler.performAction(for: .sync, refreshCardsAction: { })

        XCTAssertTrue(syncLauncher.startDeviceSyncFlowCalled)
        XCTAssertEqual(syncLauncher.syncSource, .nextStepsCard)
        XCTAssertNotNil(syncLauncher.capturedCompletion)
    }

    // MARK: - Pixel Tests

    @MainActor func testWhenAskedToPerformActionForDefaultBrowserThenItFiresPixels() {
        actionHandler.performAction(for: .defaultApp, refreshCardsAction: nil)

        XCTAssertTrue(pixelHandler.fireDefaultBrowserRequestedPixelCalled)
        XCTAssertEqual(pixelHandler.fireNextStepsCardClickedPixelCalledWith, .defaultApp)
    }

    @MainActor func testWhenAskedToPerformActionForDockThenItFiresPixels() {
        actionHandler.performAction(for: .addAppToDockMac, refreshCardsAction: nil)

        XCTAssertTrue(pixelHandler.fireAddedToDockPixelCalled)
        XCTAssertEqual(pixelHandler.fireNextStepsCardClickedPixelCalledWith, .addAppToDockMac)
    }

    @MainActor func testWhenAskedToPerformActionForDuckplayerThenItFiresPixel() {
        actionHandler.performAction(for: .duckplayer, refreshCardsAction: nil)

        XCTAssertEqual(pixelHandler.fireNextStepsCardClickedPixelCalledWith, .duckplayer)
    }

    @MainActor func testWhenAskedToPerformActionForEmailProtectionThenItFiresPixel() {
        actionHandler.performAction(for: .emailProtection, refreshCardsAction: nil)

        XCTAssertEqual(pixelHandler.fireNextStepsCardClickedPixelCalledWith, .emailProtection)
    }

    @MainActor func testWhenAskedToPerformActionForImportPromptThenItFiresPixel() {
        actionHandler.performAction(for: .bringStuff, refreshCardsAction: nil)

        XCTAssertEqual(pixelHandler.fireNextStepsCardClickedPixelCalledWith, .bringStuff)
    }

    @MainActor func testWhenAskedToPerformActionForSubscriptionThenItFiresPixels() {
        actionHandler.performAction(for: .subscription, refreshCardsAction: nil)

        XCTAssertTrue(pixelHandler.fireSubscriptionCardClickedPixelCalled)
        XCTAssertEqual(pixelHandler.fireNextStepsCardClickedPixelCalledWith, .subscription)
    }

    @MainActor func testWhenAskedToPerformActionForPersonalizeBrowserThenItFiresPixel() {
        actionHandler.performAction(for: .personalizeBrowser, refreshCardsAction: nil)

        XCTAssertEqual(pixelHandler.fireNextStepsCardClickedPixelCalledWith, .personalizeBrowser)
    }

    @MainActor func testWhenAskedToPerformActionForSyncThenItFiresPixel() {
        actionHandler.performAction(for: .sync, refreshCardsAction: nil)

        XCTAssertEqual(pixelHandler.fireNextStepsCardClickedPixelCalledWith, .sync)
    }

}

private final class MockTabOpener: NewTabPageNextStepsCardsTabOpening {
    var openedTabs: [Tab] = []

    @MainActor
    func openTab(_ tab: Tab) {
        openedTabs.append(tab)
    }
}

private class MockNavigator: NewTabPageNavigator {
    private(set) var customizationSettingsOpened = false

    func openNewTabPageBackgroundCustomizationSettings() {
        customizationSettingsOpened = true
    }
}

private class MockSyncLauncher: SyncDeviceFlowLaunching {
    private(set) var startDeviceSyncFlowCalled = false
    private(set) var syncSource: SyncDeviceButtonTouchpoint?
    private(set) var capturedCompletion: (() -> Void)?

    func startDeviceSyncFlow(source: SyncDeviceButtonTouchpoint, completion: (() -> Void)?) {
        startDeviceSyncFlowCalled = true
        syncSource = source
        capturedCompletion = completion
    }
}
