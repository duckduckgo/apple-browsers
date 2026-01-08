//
//  NewTabPageNextStepsCardsProviderFacadeTests.swift
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
import Combine
import NewTabPage
import PrivacyConfig
import PrivacyConfigTestsUtils
import SubscriptionTestingUtilities
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class NewTabPageNextStepsCardsProviderFacadeTests: XCTestCase {
    private var featureFlagger: MockFeatureFlagger!
    private var legacyCardsProvider: NewTabPageNextStepsCardsProvider!
    private var singleCardProvider: NewTabPageNextStepsSingleCardProvider!
    private var facade: NewTabPageNextStepsCardsProviderFacade!
    private var legacyCardsProviderPixelHandler: MockNewTabPageNextStepsCardsPixelHandler!
    private var singleCardProviderPixelHandler: MockNewTabPageNextStepsCardsPixelHandler!
    private var legacyCardsProviderActionHandler: MockNewTabPageNextStepsCardsActionHandler!
    private var singleCardProviderActionHandler: MockNewTabPageNextStepsCardsActionHandler!
    private var appearancePreferences: AppearancePreferences!

    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        featureFlagger = MockFeatureFlagger()
        legacyCardsProviderPixelHandler = MockNewTabPageNextStepsCardsPixelHandler()
        singleCardProviderPixelHandler = MockNewTabPageNextStepsCardsPixelHandler()
        legacyCardsProviderActionHandler = MockNewTabPageNextStepsCardsActionHandler()
        singleCardProviderActionHandler = MockNewTabPageNextStepsCardsActionHandler()

        appearancePreferences = AppearancePreferences(
            persistor: MockAppearancePreferencesPersistor(),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            featureFlagger: MockFeatureFlagger()
        )

        let continueSetUpModel = HomePage.Models.ContinueSetUpModel(
            defaultBrowserProvider: CapturingDefaultBrowserProvider(),
            dockCustomizer: DockCustomizerMock(),
            dataImportProvider: CapturingDataImportProvider(),
            emailManager: EmailManager(storage: MockEmailStorage()),
            duckPlayerPreferences: DuckPlayerPreferencesPersistorMock(),
            subscriptionCardVisibilityManager: MockHomePageSubscriptionCardVisibilityManaging(),
            persistor: MockHomePageContinueSetUpModelPersisting(),
            pixelHandler: legacyCardsProviderPixelHandler,
            cardActionsHandler: legacyCardsProviderActionHandler
        )
        legacyCardsProvider = NewTabPageNextStepsCardsProvider(
            continueSetUpModel: continueSetUpModel,
            appearancePreferences: appearancePreferences,
            pixelHandler: legacyCardsProviderPixelHandler
        )

        singleCardProvider = NewTabPageNextStepsSingleCardProvider(
            cardActionHandler: singleCardProviderActionHandler,
            pixelHandler: singleCardProviderPixelHandler,
            persistor: MockNewTabPageNextStepsCardsPersistor(),
            legacyPersistor: MockHomePageContinueSetUpModelPersisting(),
            legacySubscriptionCardPersistor: MockHomePageSubscriptionCardPersisting(),
            appearancePreferences: appearancePreferences,
            defaultBrowserProvider: CapturingDefaultBrowserProvider(),
            dockCustomizer: DockCustomizerMock(),
            dataImportProvider: CapturingDataImportProvider(),
            duckPlayerPreferences: DuckPlayerPreferencesPersistorMock(),
            subscriptionCardVisibilityManager: MockHomePageSubscriptionCardVisibilityManaging()
        )
    }

    override func tearDown() {
        facade = nil
        singleCardProvider = nil
        legacyCardsProvider = nil
        featureFlagger = nil
        legacyCardsProviderPixelHandler = nil
        singleCardProviderPixelHandler = nil
        legacyCardsProviderActionHandler = nil
        singleCardProviderActionHandler = nil
        appearancePreferences = nil
        super.tearDown()
    }

    // MARK: - Feature Flag OFF (Legacy Provider)

    @MainActor
    func testWhenFeatureFlagIsOff_ThenForwardsToLegacyProvider() {
        featureFlagger.enabledFeatureFlags = []
        facade = NewTabPageNextStepsCardsProviderFacade(
            featureFlagger: featureFlagger,
            singleCardProvider: singleCardProvider,
            legacyProvider: legacyCardsProvider
        )

        // Test isViewExpanded
        legacyCardsProvider.isViewExpanded = true
        XCTAssertTrue(facade.isViewExpanded)
        facade.isViewExpanded = false
        XCTAssertFalse(legacyCardsProvider.isViewExpanded)

        // Test cards
        legacyCardsProvider.appearancePreferences.isContinueSetUpCardsViewOutdated = false
        legacyCardsProvider.continueSetUpModel.featuresMatrix = [[.defaultBrowser, .emailProtection]]
        XCTAssertEqual(facade.cards, [.defaultApp, .emailProtection])

        // Test handleAction - verify legacy provider's model is called
        facade.handleAction(for: .defaultApp)
        XCTAssertEqual(legacyCardsProviderActionHandler.cardActionsPerformed, [.defaultApp])
        XCTAssertTrue(singleCardProviderActionHandler.cardActionsPerformed.isEmpty)

        // Test dismiss - verify legacy provider's pixel handler is called
        facade.dismiss(.emailProtection)
        XCTAssertEqual(legacyCardsProviderPixelHandler.fireNextStepsCardDismissedPixelCalledWith, .emailProtection)
        XCTAssertNil(singleCardProviderPixelHandler.fireNextStepsCardDismissedPixelCalledWith)

        // Test willDisplayCards - verify legacy provider's pixel handler is called
        facade.willDisplayCards([.duckplayer])
        XCTAssertEqual(legacyCardsProviderPixelHandler.fireNextStepsCardShownPixelsCalledWith, [.duckplayer])
        XCTAssertNil(singleCardProviderPixelHandler.fireNextStepsCardShownPixelsCalledWith)
    }

    func testWhenFeatureFlagIsOff_ThenCardsPublisher_EmitsChangesFromLegacyProvider() {
        featureFlagger.enabledFeatureFlags = []
        facade = NewTabPageNextStepsCardsProviderFacade(
            featureFlagger: featureFlagger,
            singleCardProvider: singleCardProvider,
            legacyProvider: legacyCardsProvider
        )

        var receivedCards: [[NewTabPageDataModel.CardID]] = []
        let cancellable = facade.cardsPublisher.sink { cards in
            receivedCards.append(cards)
        }

        // Trigger change
        legacyCardsProvider.continueSetUpModel.featuresMatrix = [[.defaultBrowser]]
        cancellable.cancel()

        XCTAssertEqual(receivedCards, [[.defaultApp]])
    }

    func testWhenFeatureFlagIsOff_ThenIsViewExpandedPublisher_EmitsChangesLegacyProvider() {
        featureFlagger.enabledFeatureFlags = []
        facade = NewTabPageNextStepsCardsProviderFacade(
            featureFlagger: featureFlagger,
            singleCardProvider: singleCardProvider,
            legacyProvider: legacyCardsProvider
        )

        var receivedValues: [Bool] = []
        let cancellable = facade.isViewExpandedPublisher.sink { value in
            receivedValues.append(value)
        }

        // Trigger change
        legacyCardsProvider.isViewExpanded = true
        cancellable.cancel()

        XCTAssertEqual(receivedValues, [true])
    }

    // MARK: - Feature Flag ON (Single Card Provider)

    @MainActor
    func testWhenFeatureFlagIsOn_ThenForwardsToSingleCardProvider() {
        featureFlagger.enabledFeatureFlags = [.nextStepsSingleCardIteration]
        facade = NewTabPageNextStepsCardsProviderFacade(
            featureFlagger: featureFlagger,
            singleCardProvider: singleCardProvider,
            legacyProvider: legacyCardsProvider
        )

        // Test isViewExpanded
        singleCardProvider.isViewExpanded = true
        XCTAssertTrue(facade.isViewExpanded)
        facade.isViewExpanded = false
        XCTAssertFalse(singleCardProvider.isViewExpanded)

        // Test cards
        let cards = facade.cards
        XCTAssertEqual(cards, NewTabPageDataModel.CardID.allCases)

        // Test handleAction - verify single card provider's action handler is called
        facade.handleAction(for: .subscription)
        XCTAssertEqual(singleCardProviderActionHandler.cardActionsPerformed, [.subscription])
        XCTAssertTrue(legacyCardsProviderActionHandler.cardActionsPerformed.isEmpty)

        // Test dismiss - verify single card provider's pixel handler is called
        facade.dismiss(.bringStuff)
        XCTAssertEqual(singleCardProviderPixelHandler.fireNextStepsCardDismissedPixelCalledWith, .bringStuff)
        XCTAssertNil(legacyCardsProviderPixelHandler.fireNextStepsCardDismissedPixelCalledWith)

        // Test willDisplayCards - verify single card provider's pixel handler is called
        facade.willDisplayCards([.addAppToDockMac])
        XCTAssertEqual(singleCardProviderPixelHandler.fireNextStepsCardShownPixelsCalledWith, [.addAppToDockMac])
        XCTAssertNil(legacyCardsProviderPixelHandler.fireNextStepsCardShownPixelsCalledWith)
    }

    // MARK: - Dynamic Flag Switching

    @MainActor
    func testWhenFeatureFlagChanges_ThenSwitchesProvider() {
        featureFlagger.enabledFeatureFlags = []
        facade = NewTabPageNextStepsCardsProviderFacade(
            featureFlagger: featureFlagger,
            singleCardProvider: singleCardProvider,
            legacyProvider: legacyCardsProvider
        )

        // Initially uses legacy provider
        facade.handleAction(for: .defaultApp)
        XCTAssertEqual(legacyCardsProviderActionHandler.cardActionsPerformed, [.defaultApp])
        XCTAssertEqual(singleCardProviderActionHandler.cardActionsPerformed, [])

        // Switch flag on
        featureFlagger.enabledFeatureFlags = [.nextStepsSingleCardIteration]

        // Now uses single card provider
        facade.handleAction(for: .subscription)
        XCTAssertEqual(legacyCardsProviderActionHandler.cardActionsPerformed, [.defaultApp])
        XCTAssertEqual(singleCardProviderActionHandler.cardActionsPerformed, [.subscription])

        // Switch flag off
        featureFlagger.enabledFeatureFlags = []

        // Back to legacy provider
        facade.handleAction(for: .emailProtection)
        XCTAssertEqual(legacyCardsProviderActionHandler.cardActionsPerformed, [.defaultApp, .emailProtection])
        XCTAssertEqual(singleCardProviderActionHandler.cardActionsPerformed, [.subscription])
    }
}

