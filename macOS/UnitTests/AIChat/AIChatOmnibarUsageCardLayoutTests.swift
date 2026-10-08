//
//  AIChatOmnibarUsageCardLayoutTests.swift
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

import AIChat
import AppKit
import FeatureFlags_macOS
@_spi(Testing) import Persistence
import PrivacyConfig
import PrivacyConfigTestsUtils
import SubscriptionTestingUtilities
import XCTest
@testable import DuckDuckGo_Privacy_Browser
@testable import Subscription

/// The band the host reserves for the card and the card itself must agree from the first open: the
/// Terms of Service disclaimer is required before anything else ever resolves the card.
@MainActor
final class AIChatOmnibarUsageCardLayoutTests: XCTestCase {

    private let bandHeight = AIChatUsageWarningCardView.Constants.contentHeight

    func testWhenTheDisclaimerIsRequiredFromLoadThenTheReservedBandShowsTheCard() {
        let container = loadContainer(requiresTermsOfService: true)

        XCTAssertEqual(container.usageWarningBandHeight, bandHeight)
        XCTAssertEqual(usageWarningCard(in: container.view)?.isHidden, false)
        XCTAssertEqual(exposedBand(in: container), bandHeight, accuracy: 0.5,
                       "The panel still covers the band it reserved for the card")
    }

    func testWhenNothingRequiresTheCardThenNoBandIsReserved() {
        let container = loadContainer(requiresTermsOfService: false)

        XCTAssertEqual(container.usageWarningBandHeight, 0)
        XCTAssertEqual(usageWarningCard(in: container.view)?.isHidden, true)
        XCTAssertEqual(exposedBand(in: container), 0, accuracy: 0.5)
    }

    // MARK: - Assembly

    private func loadContainer(requiresTermsOfService: Bool) -> AIChatOmnibarContainerViewController {
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.featuresStub[FeatureFlag.aiChatNativeTermsOfService.rawValue] = requiresTermsOfService
        let appearancePreferences = AppearancePreferences(
            persistor: AppearancePreferencesPersistorMock(),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            featureFlagger: featureFlagger,
            aiChatMenuConfig: MockAIChatConfig()
        )
        let themeManager = ThemeManager(appearancePreferences: appearancePreferences, featureFlagger: featureFlagger)
        let omnibarController = AIChatOmnibarController(
            aiChatTabOpener: MockAIChatTabOpener(),
            surface: .addressBar,
            draftSource: StaticPromptDraftSource(store: EphemeralPromptDraftStore()),
            origin: nil,
            pixelHandler: AddressBarPromptPixelHandler(),
            featureFlagger: featureFlagger,
            modelsService: StubAIChatModelsService(),
            subscriptionManager: SubscriptionManagerMock(),
            subscriptionUpsellPresenter: StubSubscriptionUpsellPresenter(),
            termsOfServiceStore: DuckAiTermsOfServiceStore(keyValueStore: MockKeyValueStore())
        )
        let container = AIChatOmnibarContainerViewController(themeManager: themeManager,
                                                             omnibarController: omnibarController,
                                                             duckAiNativeStorageHandler: nil,
                                                             burnerMode: .regular)
        container.view.frame = NSRect(x: 0, y: 0, width: 600, height: 200)

        // The panel subscribes on the main queue, so its first resolve lands after `viewDidLoad`.
        let settled = expectation(description: "main queue drained")
        DispatchQueue.main.async { settled.fulfill() }
        wait(for: [settled], timeout: 5)

        container.view.layoutSubtreeIfNeeded()
        return container
    }

    private func usageWarningCard(in view: NSView) -> AIChatUsageWarningCardView? {
        view.subviews.compactMap { $0 as? AIChatUsageWarningCardView }.first
    }

    /// How far the panel's chrome stops short of the bottom, which is where the card shows.
    private func exposedBand(in container: AIChatOmnibarContainerViewController) -> CGFloat {
        guard let panel = container.view.subviews.compactMap({ $0 as? MouseBlockingBackgroundView }).first else {
            XCTFail("No panel background")
            return -1
        }
        return container.view.bounds.height - panel.frame.height
    }
}

// MARK: - Stubs

private struct StubAIChatModelsService: AIChatModelsProviding {
    func fetchModels() async throws -> AIChatModelsResponse {
        AIChatModelsResponse(models: [])
    }
}

@MainActor
private struct StubSubscriptionUpsellPresenter: AIChatOmnibarSubscriptionUpselling {
    func routeGatedSelection(requiredTier: AIChatModelPublicAccessTier,
                             userTier: AIChatUserTier,
                             origin: SubscriptionFunnelOrigin) -> Bool { false }
    func presentSubscriptionActivation() {}
}
