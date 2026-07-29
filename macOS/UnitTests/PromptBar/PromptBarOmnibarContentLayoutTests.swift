//
//  PromptBarOmnibarContentLayoutTests.swift
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

/// Lays the real prompt stack out and measures the resulting frames, rather than restating the
/// height formula: the vertical anchors live in `AIChatOmnibarContainerViewController`.
@MainActor
final class PromptBarOmnibarContentLayoutTests: XCTestCase {

    private var content: PromptBarOmnibarContentViewController!
    private var omnibarController: AIChatOmnibarController!
    private var containerViewController: AIChatOmnibarContainerViewController!

    override func setUp() {
        super.setUp()
        content = makeContent()
    }

    override func tearDown() {
        content = nil
        omnibarController = nil
        containerViewController = nil
        super.tearDown()
    }

    // MARK: - Tests

    func testWhenThePromptIsOneLineThenTheControlsRowSitsClearOfIt() {
        let gap = layOutAndMeasureGap(prompt: "what is a duck")

        XCTAssertGreaterThanOrEqual(gap, 8, "The controls row must not touch the prompt text")
    }

    func testWhenThePromptGrowsToMoreLinesThenTheGapBelowItDoesNotChange() {
        let oneLine = layOutAndMeasureGap(prompt: "what is a duck")
        let twoLines = layOutAndMeasureGap(prompt: String(repeating: "what is a duck ", count: 8))
        let fourLines = layOutAndMeasureGap(prompt: String(repeating: "what is a duck ", count: 20))

        XCTAssertEqual(twoLines, oneLine, accuracy: 1)
        XCTAssertEqual(fourLines, oneLine, accuracy: 1)
    }

    func testWhenThePromptGrowsThenThePanelGrowsWithIt() {
        let oneLineHeight = layOutAndMeasureHeight(prompt: "what is a duck")
        let fourLineHeight = layOutAndMeasureHeight(prompt: String(repeating: "what is a duck ", count: 20))

        XCTAssertGreaterThan(fourLineHeight, oneLineHeight)
    }

    /// A first read that doesn't match the settled height means the panel resizes a line at a time as
    /// layout catches up — the bar visibly jumping while you type.
    func testWhenTheHeightIsReadBeforeLayoutHasSettledThenItAlreadyMatchesTheSettledHeight() {
        let view = content.view
        guard let textView = firstDescendant(of: view, ofType: NSTextView.self) else {
            return XCTFail("No prompt text view in the hierarchy")
        }
        textView.string = String(repeating: "what is a duck ", count: 20)

        let firstRead = content.preferredWindowContentSize.height

        for _ in 0..<3 {
            view.frame = NSRect(origin: .zero, size: content.preferredWindowContentSize)
            view.layoutSubtreeIfNeeded()
        }
        let settled = content.preferredWindowContentSize.height

        XCTAssertEqual(firstRead, settled, accuracy: 1)
    }

    func testWhenTheControlsRowIsLaidOutThenItMatchesTheHeightThePanelBudgetsForIt() {
        let view = content.view
        _ = layOutAndMeasureGap(prompt: "what is a duck")

        XCTAssertEqual(containerViewController.suggestionsHeight, 0,
                       "This measurement only isolates the controls row while nothing sits below it")
        XCTAssertEqual(containerViewController.additionalContentHeight, 0,
                       "This measurement only isolates the controls row while nothing sits below it")

        let buttons = controlsRowButtons(in: view)
        XCTAssertFalse(buttons.isEmpty, "No controls row in the hierarchy")

        for button in buttons {
            XCTAssertEqual(button.bounds.height, 28, accuracy: 1,
                           "Controls are no longer 28pt tall — `controlsRowHeight` must be re-derived")

            let bottom = distanceFromTop(of: view, toPointIn: button, point: NSPoint(x: 0, y: button.bounds.minY))
            XCTAssertLessThanOrEqual(bottom, view.frame.height,
                                     "\(type(of: button)) hangs past the panel bottom — `controlsRowHeight` is too small")
        }
    }

    // MARK: - Measurement

    /// Distance between the bottom of the laid-out text and the top of the controls row.
    private func layOutAndMeasureGap(prompt: String) -> CGFloat {
        layOutAndMeasure(prompt: prompt).gap
    }

    private func layOutAndMeasureHeight(prompt: String) -> CGFloat {
        layOutAndMeasure(prompt: prompt).height
    }

    private func layOutAndMeasure(prompt: String) -> (gap: CGFloat, height: CGFloat) {
        let view = content.view
        view.frame = NSRect(origin: .zero, size: content.preferredWindowContentSize)
        view.layoutSubtreeIfNeeded()

        guard let textView = firstDescendant(of: view, ofType: NSTextView.self) else {
            XCTFail("No prompt text view in the hierarchy")
            return (0, 0)
        }
        // Directly, not via the controller: if its publisher plumbing is idle here, every measurement
        // comes out identical and the assertions pass for the wrong reason.
        textView.string = prompt
        omnibarController.updateText(prompt)

        // The first pass resolves the width the prompt wraps against.
        for _ in 0..<2 {
            let size = content.preferredWindowContentSize
            view.frame = NSRect(origin: .zero, size: size)
            view.layoutSubtreeIfNeeded()
        }

        XCTAssertGreaterThan(textView.frame.width, 0, "A zero-width text view can't wrap, making every measurement equal")

        guard let controlsTop = topOfControlsRow(in: view) else {
            XCTFail("No controls row in the hierarchy")
            return (0, 0)
        }

        let textBottom = bottomOfText(in: textView, convertedTo: view)
        return (controlsTop - textBottom, view.frame.height)
    }

    private func bottomOfText(in textView: NSTextView, convertedTo host: NSView) -> CGFloat {
        guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else {
            return 0
        }
        layoutManager.ensureLayout(for: textContainer)
        let used = layoutManager.usedRect(for: textContainer)
        let inTextView = NSRect(x: used.minX,
                                y: used.maxY + textView.textContainerInset.height,
                                width: used.width,
                                height: 0)
        return distanceFromTop(of: host, toPointIn: textView, point: inTextView.origin)
    }

    /// From the real button frames rather than a constant.
    private func topOfControlsRow(in host: NSView) -> CGFloat? {
        let tops = controlsRowButtons(in: host).map { button in
            distanceFromTop(of: host, toPointIn: button, point: NSPoint(x: 0, y: button.bounds.maxY))
        }
        return tops.min()
    }

    private func controlsRowButtons(in host: NSView) -> [NSView] {
        descendants(of: host)
            .filter { $0 is AIChatOmnibarToolButton || $0 is AIChatModelPickerButton }
            .filter { !$0.isHiddenOrHasHiddenAncestor }
    }

    /// Normalised to a top-left origin, so measurements compare regardless of which views are flipped.
    private func distanceFromTop(of host: NSView, toPointIn view: NSView, point: NSPoint) -> CGFloat {
        let converted = host.convert(point, from: view)
        return host.isFlipped ? converted.y : host.bounds.maxY - converted.y
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap { descendants(of: $0) }
    }

    private func firstDescendant<T: NSView>(of view: NSView, ofType type: T.Type) -> T? {
        descendants(of: view).compactMap { $0 as? T }.first
    }

    // MARK: - Assembly

    private func makeContent() -> PromptBarOmnibarContentViewController {
        let featureFlagger = MockFeatureFlagger()
        let appearancePreferences = AppearancePreferences(
            persistor: AppearancePreferencesPersistorMock(),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            featureFlagger: featureFlagger,
            aiChatMenuConfig: MockAIChatConfig()
        )
        let themeManager = ThemeManager(appearancePreferences: appearancePreferences, featureFlagger: featureFlagger)
        let draftStore = EphemeralPromptDraftStore()

        let omnibarController = AIChatOmnibarController(
            aiChatTabOpener: MockAIChatTabOpener(),
            surface: .promptBar,
            draftSource: StaticPromptDraftSource(store: draftStore),
            origin: nil,
            pixelHandler: PromptBarPixelHandler(),
            featureFlagger: featureFlagger,
            modelsService: StubAIChatModelsService(),
            subscriptionManager: SubscriptionManagerMock(),
            subscriptionUpsellPresenter: StubSubscriptionUpsellPresenter()
        )
        self.omnibarController = omnibarController

        let containerViewController = AIChatOmnibarContainerViewController(
            themeManager: themeManager,
            omnibarController: omnibarController,
            duckAiNativeStorageHandler: nil,
            burnerMode: .regular
        )
        self.containerViewController = containerViewController
        let textViewController = AIChatOmnibarTextContainerViewController(
            omnibarController: omnibarController,
            themeManager: themeManager,
            isBurner: false,
            featureFlagger: featureFlagger
        )

        return PromptBarOmnibarContentViewController(
            omnibarController: omnibarController,
            containerViewController: containerViewController,
            textViewController: textViewController,
            draftStore: draftStore,
            promptSubmitter: StubPromptBarPromptSubmitter()
        )
    }
}

// MARK: - Stubs

@MainActor
private final class StubPromptBarPromptSubmitter: PromptBarPromptSubmitting {
    func submit(query: String, payload: AIChatNativePrompt?, preferringWindowOn screen: NSScreen?) {}
    func openVoiceSession(preferringWindowOn screen: NSScreen?) {}
    func open(url: URL, preferringWindowOn screen: NSScreen?) {}
}

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
