//
//  AIChatOmnibarBrandLogoLayoutTests.swift
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
import FeatureFlags
import PrivacyConfig
import PrivacyConfigTestsUtils
import SubscriptionTestingUtilities
import XCTest
@testable import DuckDuckGo_Privacy_Browser
@testable import Subscription

@MainActor
final class AIChatOmnibarBrandLogoLayoutTests: XCTestCase {

    // MARK: - Prompt Bar

    func testWhenSurfaceIsPromptBarThenTheBrandLogoLeadsThePrompt() {
        let textViewController = layOutTextContainer(surface: .promptBar)

        guard let logo = brandLogo(in: textViewController.view) else {
            return XCTFail("No brand logo in the Prompt Bar's prompt")
        }

        XCTAssertEqual(logo.bounds.width, 24, accuracy: 0.5)
        XCTAssertEqual(logo.bounds.height, 24, accuracy: 0.5)
        XCTAssertNotNil(logo.image, "The logo view has no image, so nothing renders")
    }

    func testWhenSurfaceIsPromptBarThenThePromptTextClearsTheBrandLogo() {
        let textViewController = layOutTextContainer(surface: .promptBar)
        let host = textViewController.view

        guard let logo = brandLogo(in: host) else {
            return XCTFail("No brand logo in the Prompt Bar's prompt")
        }
        let logoTrailing = host.convert(NSPoint(x: logo.bounds.maxX, y: 0), from: logo).x

        XCTAssertEqual(textLeading(in: host) - logoTrailing, 12, accuracy: 0.5,
                       "The prompt text no longer sits a 12pt gap clear of the logo")
    }

    func testWhenSurfaceIsPromptBarThenThePlaceholderIndentsWithTheText() {
        let addressBar = layOutTextContainer(surface: .addressBar).view
        let promptBar = layOutTextContainer(surface: .promptBar).view

        let placeholderIndent = placeholderLeading(in: promptBar) - placeholderLeading(in: addressBar)
        let textIndent = textLeading(in: promptBar) - textLeading(in: addressBar)

        XCTAssertEqual(placeholderIndent, textIndent, accuracy: 0.5)
    }

    func testWhenTheBrandLogoIsClickedThenTheHitGoesToThePromptEditor() {
        let host = layOutTextContainer(surface: .promptBar).view

        guard let logo = brandLogo(in: host) else {
            return XCTFail("No brand logo in the Prompt Bar's prompt")
        }
        let logoCentre = host.convert(NSPoint(x: logo.bounds.midX, y: logo.bounds.midY), from: logo)

        XCTAssertTrue(host.hitTest(logoCentre) is NSTextView,
                      "Clicking the logo must focus the prompt rather than land on the mark itself")
    }

    // MARK: - Address bar

    func testWhenSurfaceIsAddressBarThenThereIsNoBrandLogo() {
        let textViewController = layOutTextContainer(surface: .addressBar)

        XCTAssertNil(brandLogo(in: textViewController.view))
    }

    func testWhenSurfaceIsAddressBarThenThePromptTextIsNotIndented() {
        let addressBarLeading = textLeading(in: layOutTextContainer(surface: .addressBar).view)
        let promptBarLeading = textLeading(in: layOutTextContainer(surface: .promptBar).view)

        XCTAssertEqual(promptBarLeading - addressBarLeading, 36, accuracy: 0.5,
                       "The address bar's prompt has shifted — only the Prompt Bar indents for the logo")
    }

    // MARK: - Measurement

    private func textLeading(in host: NSView) -> CGFloat {
        guard let textView = firstDescendant(of: host, ofType: NSTextView.self),
              let textContainer = textView.textContainer else {
            XCTFail("No prompt text view in the hierarchy")
            return 0
        }
        let originInTextView = textView.textContainerOrigin.x + textContainer.lineFragmentPadding
        return host.convert(NSPoint(x: originInTextView, y: 0), from: textView).x
    }

    private func placeholderLeading(in host: NSView) -> CGFloat {
        guard let placeholder = firstDescendant(of: host, ofType: NSTextField.self) else {
            XCTFail("No placeholder label in the hierarchy")
            return 0
        }
        return host.convert(NSPoint(x: placeholder.bounds.minX, y: 0), from: placeholder).x
    }

    private func brandLogo(in host: NSView) -> NSImageView? {
        firstDescendant(of: host, ofType: NSImageView.self)
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap { descendants(of: $0) }
    }

    private func firstDescendant<T: NSView>(of view: NSView, ofType type: T.Type) -> T? {
        descendants(of: view).compactMap { $0 as? T }.first
    }

    // MARK: - Assembly

    private func layOutTextContainer(surface: DuckAIPromptSurface) -> AIChatOmnibarTextContainerViewController {
        let textViewController = makeTextContainer(surface: surface)
        let view = textViewController.view
        view.frame = NSRect(x: 0, y: 0, width: PromptBarPlacement.preferredWidth, height: 80)
        view.layoutSubtreeIfNeeded()
        return textViewController
    }

    private func makeTextContainer(surface: DuckAIPromptSurface) -> AIChatOmnibarTextContainerViewController {
        let featureFlagger = MockFeatureFlagger()
        let appearancePreferences = AppearancePreferences(
            persistor: AppearancePreferencesPersistorMock(),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            featureFlagger: featureFlagger,
            aiChatMenuConfig: MockAIChatConfig()
        )
        let themeManager = ThemeManager(appearancePreferences: appearancePreferences, featureFlagger: featureFlagger)

        let omnibarController = AIChatOmnibarController(
            aiChatTabOpener: MockAIChatTabOpener(),
            surface: surface,
            draftSource: StaticPromptDraftSource(store: EphemeralPromptDraftStore()),
            origin: nil,
            pixelHandler: PromptBarPixelHandler(),
            featureFlagger: featureFlagger,
            modelsService: StubAIChatModelsService(),
            subscriptionManager: SubscriptionManagerMock(),
            subscriptionUpsellPresenter: StubSubscriptionUpsellPresenter()
        )

        return AIChatOmnibarTextContainerViewController(
            omnibarController: omnibarController,
            themeManager: themeManager,
            isBurner: false,
            featureFlagger: featureFlagger
        )
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
