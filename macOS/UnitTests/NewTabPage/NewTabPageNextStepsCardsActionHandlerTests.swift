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

final class NewTabPageNextStepsCardsActionHandlerTests: XCTestCase {
    private var actionHandler: NewTabPageNextStepsCardsActionHandler!
    private var tabCollectionVM: TabCollectionViewModel!
    private var capturingDefaultBrowserProvider: CapturingDefaultBrowserProvider!
    private var capturingDataImportProvider: CapturingDataImportProvider!
    private var privacyConfigManager: MockPrivacyConfigurationManager!
    private var dockCustomizer: DockCustomization!
    private var pixelHandler: MockNewTabPageNextStepsCardsPixelHandler!

    @MainActor override func setUp() {
        capturingDefaultBrowserProvider = CapturingDefaultBrowserProvider()
        dockCustomizer = DockCustomizerMock()
        capturingDataImportProvider = CapturingDataImportProvider()
        tabCollectionVM = TabCollectionViewModel(isPopup: false)
        privacyConfigManager = MockPrivacyConfigurationManager()
        let config = MockPrivacyConfiguration()
        privacyConfigManager.privacyConfig = config
        pixelHandler = MockNewTabPageNextStepsCardsPixelHandler()

        actionHandler = NewTabPageNextStepsCardsActionHandler(
            defaultBrowserProvider: capturingDefaultBrowserProvider,
            dockCustomizer: dockCustomizer,
            dataImportProvider: capturingDataImportProvider,
            tabOpener: MockTabOpener(tabCollectionViewModel: tabCollectionVM),
            privacyConfigurationManager: privacyConfigManager,
            pixelHandler: pixelHandler
        )
    }

    override func tearDown() {
        actionHandler = nil
        capturingDefaultBrowserProvider = nil
        capturingDataImportProvider = nil
        tabCollectionVM = nil
        dockCustomizer = nil
        privacyConfigManager = nil
        pixelHandler = nil
    }

    @MainActor func testWhenAskedToPerformActionForDefaultBrowserCardThenItPresentsTheDefaultBrowserPrompt() {
        actionHandler.performAction(for: .defaultApp, completion: nil)

        XCTAssertTrue(capturingDefaultBrowserProvider.presentDefaultBrowserPromptCalled)
        XCTAssertFalse(capturingDefaultBrowserProvider.openSystemPreferencesCalled)
    }

    @MainActor func testWhenAskedToPerformActionForDefaultBrowserCardAndDefaultBrowserPromptThrowsThenItOpensSystemPreferences() {
        capturingDefaultBrowserProvider.throwError = true
        actionHandler.performAction(for: .defaultApp, completion: nil)

        XCTAssertTrue(capturingDefaultBrowserProvider.presentDefaultBrowserPromptCalled)
        XCTAssertTrue(capturingDefaultBrowserProvider.openSystemPreferencesCalled)
    }

    @MainActor func testWhenAskedToPerformActionForDockThenItAddsAppToDock() {
        actionHandler.performAction(for: .addAppToDockMac, completion: nil)

        XCTAssertTrue(dockCustomizer.isAddedToDock)
    }

    @MainActor func testWhenAskedToPerformActionForImportPromptThrowsThenItOpensImportWindow() {
        actionHandler.performAction(for: .bringStuff, completion: nil)

        XCTAssertTrue(capturingDataImportProvider.showImportWindowCalled)
    }

    @MainActor func testWhenAskedToPerformActionForEmailProtectionThenItOpensEmailProtectionSite() {
        actionHandler.performAction(for: .emailProtection, completion: nil)

        XCTAssertEqual(tabCollectionVM.tabs[1].url, EmailUrls().emailProtectionLink)
    }

    @MainActor func testWhenAskedToPerformActionForDuckPlayerThenItOpensYoutubeVideo() {
        actionHandler.performAction(for: .duckplayer, completion: nil)

        XCTAssertEqual(tabCollectionVM.tabs[1].url, URL(string: actionHandler.duckPlayerURL))
    }

    @MainActor func testWhenAskedToPerformActionForSubscriptionThenItOpensSubscriptionSite() {
        actionHandler.performAction(for: .subscription, completion: nil)

        let expectedURL = SubscriptionURL.purchaseURLComponentsWithOrigin(SubscriptionFunnelOrigin.newTabPageNextStepsCard.rawValue)?.url

        XCTAssertEqual(tabCollectionVM.tabs[1].url, expectedURL)
    }

    // MARK: - Pixel Tests

    @MainActor func testWhenAskedToPerformActionForDefaultBrowserThenItFiresPixels() {
        actionHandler.performAction(for: .defaultApp, completion: nil)

        XCTAssertTrue(pixelHandler.fireDefaultBrowserRequestedPixelCalled)
        XCTAssertEqual(pixelHandler.fireNextStepsCardClickedPixelCalledWith, .defaultApp)
    }

    @MainActor func testWhenAskedToPerformActionForDockThenItFiresPixels() {
        actionHandler.performAction(for: .addAppToDockMac, completion: nil)

        XCTAssertTrue(pixelHandler.fireAddedToDockPixelCalled)
        XCTAssertEqual(pixelHandler.fireNextStepsCardClickedPixelCalledWith, .addAppToDockMac)
    }

    @MainActor func testWhenAskedToPerformActionForDuckplayerThenItFiresPixel() {
        actionHandler.performAction(for: .duckplayer, completion: nil)

        XCTAssertEqual(pixelHandler.fireNextStepsCardClickedPixelCalledWith, .duckplayer)
    }

    @MainActor func testWhenAskedToPerformActionForEmailProtectionThenItFiresPixel() {
        actionHandler.performAction(for: .emailProtection, completion: nil)

        XCTAssertEqual(pixelHandler.fireNextStepsCardClickedPixelCalledWith, .emailProtection)
    }

    @MainActor func testWhenAskedToPerformActionForImportPromptThenItFiresPixel() {
        actionHandler.performAction(for: .bringStuff, completion: nil)

        XCTAssertEqual(pixelHandler.fireNextStepsCardClickedPixelCalledWith, .bringStuff)
    }

    @MainActor func testWhenAskedToPerformActionForSubscriptionThenItFiresPixels() {
        actionHandler.performAction(for: .subscription, completion: nil)

        XCTAssertTrue(pixelHandler.fireSubscriptionCardClickedPixelCalled)
        XCTAssertEqual(pixelHandler.fireNextStepsCardClickedPixelCalledWith, .subscription)
    }

}

private struct MockTabOpener: NewTabPageNextStepsCardsTabOpening {
    let tabCollectionViewModel: TabCollectionViewModel

    @MainActor
    func openTab(_ tab: Tab) {
        tabCollectionViewModel.insertOrAppend(tab: tab, selected: true)
    }
}
