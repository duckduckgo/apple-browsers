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
    private var pixelHandler: MockNewTabPageNextStepsCardsPixelHandler!
    private var actionHandler: MockNewTabPageNextStepsCardsActionHandler!
    private var appearancePreferences: AppearancePreferences!

    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        featureFlagger = MockFeatureFlagger()
        pixelHandler = MockNewTabPageNextStepsCardsPixelHandler()
        actionHandler = MockNewTabPageNextStepsCardsActionHandler()

        appearancePreferences = AppearancePreferences(
            persistor: MockAppearancePreferencesPersistor(),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            featureFlagger: MockFeatureFlagger()
        )
    }

    override func tearDown() {
        featureFlagger = nil
        pixelHandler = nil
        actionHandler = nil
        appearancePreferences = nil
        super.tearDown()
    }

    // MARK: - Feature Flag OFF (Legacy Provider)

    @MainActor
    func testWhenFeatureFlagIsOff_ThenForwardsToLegacyProvider() throws {
        featureFlagger.enabledFeatureFlags = []
        let facade = createFacade(featureFlagger: featureFlagger)

        let provider = try XCTUnwrap(facade.activeProvider as? NewTabPageNextStepsCardsProvider)

        // Test isViewExpanded
        facade.isViewExpanded = true
        XCTAssertTrue(facade.isViewExpanded)
        facade.isViewExpanded = false
        XCTAssertFalse(provider.isViewExpanded)

        // Test cards
        provider.appearancePreferences.isContinueSetUpCardsViewOutdated = false
        provider.continueSetUpModel.featuresMatrix = [[.defaultBrowser, .emailProtection]]
        XCTAssertEqual(facade.cards, [.defaultApp, .emailProtection])

        // Test handleAction - verify legacy provider's model is called
        facade.handleAction(for: .defaultApp)
        XCTAssertEqual(actionHandler.cardActionsPerformed, [.defaultApp])

        // Test dismiss - verify legacy provider's pixel handler is called
        facade.dismiss(.emailProtection)
        XCTAssertEqual(pixelHandler.fireNextStepsCardDismissedPixelCalledWith, .emailProtection)

        // Test willDisplayCards - verify legacy provider's pixel handler is called
        facade.willDisplayCards([.duckplayer])
        XCTAssertEqual(pixelHandler.fireNextStepsCardShownPixelsCalledWith, [.duckplayer])
    }

    func testWhenFeatureFlagIsOff_ThenCardsPublisher_EmitsChangesFromLegacyProvider() throws {
        featureFlagger.enabledFeatureFlags = []
        let facade = createFacade(featureFlagger: featureFlagger)

        let provider = try XCTUnwrap(facade.activeProvider as? NewTabPageNextStepsCardsProvider)

        var receivedCards: [[NewTabPageDataModel.CardID]] = []
        let cancellable = facade.cardsPublisher.sink { cards in
            receivedCards.append(cards)
        }

        // Trigger change
        provider.continueSetUpModel.featuresMatrix = [[.defaultBrowser]]
        cancellable.cancel()

        XCTAssertEqual(receivedCards, [[.defaultApp]])
    }

    func testWhenFeatureFlagIsOff_ThenIsViewExpandedPublisher_EmitsChangesLegacyProvider() throws {
        featureFlagger.enabledFeatureFlags = []
        let facade = createFacade(featureFlagger: featureFlagger)

        let provider = try XCTUnwrap(facade.activeProvider as? NewTabPageNextStepsCardsProvider)

        var receivedValues: [Bool] = []
        let cancellable = facade.isViewExpandedPublisher.sink { value in
            receivedValues.append(value)
        }

        // Trigger change
        provider.isViewExpanded = true
        cancellable.cancel()

        XCTAssertEqual(receivedValues, [true])
    }

    // MARK: - Feature Flag ON (Single Card Provider)

    @MainActor
    func testWhenFeatureFlagIsOn_ThenForwardsToSingleCardProvider() throws {
        featureFlagger.enabledFeatureFlags = [.nextStepsSingleCardIteration]
        let facade = createFacade(featureFlagger: featureFlagger)

        let provider = try XCTUnwrap(facade.activeProvider as? NewTabPageNextStepsSingleCardProvider)

        // Test isViewExpanded
        provider.isViewExpanded = true
        XCTAssertTrue(facade.isViewExpanded)
        facade.isViewExpanded = false
        XCTAssertFalse(provider.isViewExpanded)

        // Test cards
        XCTAssertEqual(facade.cards, defaultCards(for: provider))

        // Test handleAction - verify single card provider's action handler is called
        facade.handleAction(for: .subscription)
        XCTAssertEqual(actionHandler.cardActionsPerformed, [.subscription])

        // Test dismiss - verify single card provider's pixel handler is called
        facade.dismiss(.bringStuff)
        XCTAssertEqual(pixelHandler.fireNextStepsCardDismissedPixelCalledWith, .bringStuff)

        // Test willDisplayCards - verify single card provider's pixel handler is called
        facade.willDisplayCards([.emailProtection])
        XCTAssertEqual(pixelHandler.fireNextStepsCardShownPixelsCalledWith, [.emailProtection])
    }

    @MainActor
    func testWhenFeatureFlagIsOn_ThenCardsPublisher_EmitsChangesFromSingleCardProvider() throws {
        featureFlagger.enabledFeatureFlags = [.nextStepsSingleCardIteration]
        let facade = createFacade(featureFlagger: featureFlagger)

        let provider = try XCTUnwrap(facade.activeProvider as? NewTabPageNextStepsSingleCardProvider)

        var receivedCards: [[NewTabPageDataModel.CardID]] = []
        let cancellable = facade.cardsPublisher.sink { cards in
            receivedCards.append(cards)
        }

        // Trigger change
        provider.dismiss(.defaultApp)
        cancellable.cancel()

        XCTAssertEqual(receivedCards, [defaultCards(for: provider).filter({ $0 != .defaultApp })])
    }

    func testWhenFeatureFlagIsOn_ThenIsViewExpandedPublisher_EmitsChangesFromSingleCardProvider() throws {
        featureFlagger.enabledFeatureFlags = [.nextStepsSingleCardIteration]
        let facade = createFacade(featureFlagger: featureFlagger)

        let provider = try XCTUnwrap(facade.activeProvider as? NewTabPageNextStepsSingleCardProvider)

        var receivedValues: [Bool] = []
        let cancellable = facade.isViewExpandedPublisher.sink { value in
            receivedValues.append(value)
        }

        // Trigger change
        provider.isViewExpanded = true
        cancellable.cancel()

        XCTAssertEqual(receivedValues, [true])
    }

    // MARK: - Dynamic Flag Switching

    @MainActor
    func testWhenFeatureFlagChanges_ThenSwitchesProvider() throws {
        featureFlagger.enabledFeatureFlags = []
        let facade = createFacade(featureFlagger: featureFlagger)

        var receivedCards: [[NewTabPageDataModel.CardID]] = []
        let cancellable = facade.cardsPublisher.sink { cards in
            receivedCards.append(cards)
        }

        // Initially uses legacy provider
        let legacyProvider = try XCTUnwrap(facade.activeProvider as? NewTabPageNextStepsCardsProvider)
        XCTAssertEqual(facade.cards, legacyProvider.cards)
        legacyProvider.appearancePreferences.isContinueSetUpCardsViewOutdated = false
        legacyProvider.continueSetUpModel.featuresMatrix = [[.defaultBrowser, .emailProtection]]
        XCTAssertEqual(receivedCards.last, legacyProvider.cards)

        // Switch flag on
        featureFlagger.enabledFeatureFlags = [.nextStepsSingleCardIteration]
        featureFlagger.triggerUpdate()

        // Now uses single card provider
        let singleCardProvider = try XCTUnwrap(facade.activeProvider as? NewTabPageNextStepsSingleCardProvider)
        XCTAssertEqual(facade.cards, singleCardProvider.cards)
        facade.dismiss(.subscription)
        XCTAssertEqual(receivedCards.last, singleCardProvider.cards)

        // Switch flag off
        featureFlagger.enabledFeatureFlags = []
        featureFlagger.triggerUpdate()

        // Back to legacy provider
        let legacyProvider2 = try XCTUnwrap(facade.activeProvider as? NewTabPageNextStepsCardsProvider)
        XCTAssertEqual(facade.cards, legacyProvider2.cards)
        legacyProvider2.appearancePreferences.isContinueSetUpCardsViewOutdated = false
        legacyProvider2.continueSetUpModel.featuresMatrix = [[.defaultBrowser]]
        XCTAssertEqual(receivedCards.last, legacyProvider2.cards)

        cancellable.cancel()
    }
}

private extension NewTabPageNextStepsCardsProviderFacadeTests {
    func defaultCards(for provider: NewTabPageNextStepsSingleCardProvider) -> [NewTabPageDataModel.CardID] {
        let cards = provider.defaultCards.map { $0.cardID }
#if APPSTORE
        return cards.filter { $0 != .addAppToDockMac }
#else
        return cards
#endif
    }

    func createFacade(featureFlagger: FeatureFlagger) -> NewTabPageNextStepsCardsProviderFacade {
        NewTabPageNextStepsCardsProviderFacade(
            featureFlagger: featureFlagger,
            dataImportProvider: CapturingDataImportProvider(),
            subscriptionCardVisibilityManager: MockHomePageSubscriptionCardVisibilityManaging(),
            legacyPersistor: MockHomePageContinueSetUpModelPersisting(),
            pixelHandler: pixelHandler,
            cardActionsHandler: actionHandler,
            appearancePreferences: appearancePreferences,
            legacySubscriptionCardPersistor: MockHomePageSubscriptionCardPersisting(),
            persistor: MockNewTabPageNextStepsCardsPersistor(),
            duckPlayerPreferences: DuckPlayerPreferencesPersistorMock(),
            syncService: MockDDGSyncing(authState: .inactive, isSyncInProgress: false)
        )
    }
}
