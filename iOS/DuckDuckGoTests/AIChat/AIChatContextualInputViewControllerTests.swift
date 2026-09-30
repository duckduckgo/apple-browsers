//
//  AIChatContextualInputViewControllerTests.swift
//  DuckDuckGoTests
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
import XCTest
@testable import DuckDuckGo

@MainActor
final class AIChatContextualInputViewControllerTests: XCTestCase {

    private var termsSuiteName: String { String(describing: self) + ".terms" }

    override func setUp() {
        super.setUp()
        UserDefaults(suiteName: termsSuiteName)?.removePersistentDomain(forName: termsSuiteName)
    }

    override func tearDown() {
        UserDefaults(suiteName: termsSuiteName)?.removePersistentDomain(forName: termsSuiteName)
        super.tearDown()
    }

    func testImmediateUTIPrivacyLabelDoesNotOverlapQuickActionsInCompressedHeight() {
        let sut = AIChatContextualInputViewController(
            voiceSearchHelper: MockVoiceSearchHelper(),
            showsBasicNativeInput: false
        )
        sut.loadViewIfNeeded()
        sut.updateStartActions(suggestions: [], quickActions: [.askAboutPage])
        sut.view.frame = CGRect(x: 0, y: 0, width: 390, height: 180)

        sut.view.setNeedsLayout()
        sut.view.layoutIfNeeded()

        let welcomeLabel = findSubview(in: sut.view) { view in
            (view as? UILabel)?.attributedText?.string.contains("private") == true
        } as? UILabel
        let quickActionsScrollView = findSubview(in: sut.view) { view in
            view is UIScrollView
        }

        XCTAssertNotNil(welcomeLabel)
        XCTAssertNotNil(quickActionsScrollView)
        if let welcomeLabel, let quickActionsScrollView {
            XCTAssertLessThanOrEqual(welcomeLabel.frame.maxY, quickActionsScrollView.frame.minY)
        }
    }

    // MARK: - Terms of Service

    func testWhenTermsAreNotAcceptedThenTheDisclaimerShowsBelowTheInput() throws {
        let sut = makeBasicInputSUT()
        let window = show(sut)
        defer { window.isHidden = true }

        let card = try XCTUnwrap(termsOfServiceCard(in: sut))
        let input = try XCTUnwrap(findSubview(in: sut.view) { $0 is AIChatNativeInputView })

        XCTAssertFalse(card.isHidden)
        XCTAssertLessThan(input.convert(input.bounds, to: sut.view).maxY, card.frame.maxY)
    }

    func testWhenTermsAreAcceptedThenNoDisclaimerShows() {
        termsStore.recordWebReport()
        let sut = makeBasicInputSUT()
        let window = show(sut)
        defer { window.isHidden = true }

        XCTAssertEqual(termsOfServiceCard(in: sut)?.isHidden, true)
    }

    /// The immediate UTI carries its own footer, so the chips-only surface never shows one.
    func testWhenTheBasicInputIsNotShownThenNoDisclaimerShows() {
        let sut = AIChatContextualInputViewController(voiceSearchHelper: MockVoiceSearchHelper(),
                                                      showsBasicNativeInput: false,
                                                      termsOfServiceDisclaimer: makeDisclaimer())
        let window = show(sut)
        defer { window.isHidden = true }

        XCTAssertNil(termsOfServiceCard(in: sut))
    }

    func testWhenSentWithTheDisclaimerOnScreenThenTermsAreAcceptedAndItHides() {
        let sut = makeBasicInputSUT()
        let window = show(sut)
        defer { window.isHidden = true }

        sut.acceptTermsIfDisclaimerShown()

        XCTAssertTrue(termsStore.hasAccepted)
        XCTAssertEqual(termsOfServiceCard(in: sut)?.isHidden, true)
    }

    func testWhenSentWhileTheInputIsOffScreenThenNothingIsAccepted() {
        let sut = makeBasicInputSUT()
        sut.loadViewIfNeeded()

        sut.acceptTermsIfDisclaimerShown()

        XCTAssertFalse(termsStore.hasAccepted)
    }

    /// Accepting on the web while the sheet was down retires the disclaimer on the next appearance.
    func testWhenTermsAreAcceptedElsewhereThenTheDisclaimerHidesWhenTheInputReappears() {
        let sut = makeBasicInputSUT()
        let window = show(sut)
        defer { window.isHidden = true }
        termsStore.recordWebReport()

        window.rootViewController = UIViewController()
        window.rootViewController = sut

        XCTAssertEqual(termsOfServiceCard(in: sut)?.isHidden, true)
    }

    // MARK: - Helpers

    private var termsStore: DuckAiTermsOfServiceStore {
        DuckAiTermsOfServiceStore(keyValueStore: UserDefaults(suiteName: termsSuiteName)!)
    }

    private func makeDisclaimer() -> DuckAiTermsOfServiceDisclaimer {
        DuckAiTermsOfServiceDisclaimer(feature: StubNativeTermsOfServiceFeature(isAvailable: true), store: termsStore)
    }

    private func makeBasicInputSUT() -> AIChatContextualInputViewController {
        AIChatContextualInputViewController(voiceSearchHelper: MockVoiceSearchHelper(),
                                            showsBasicNativeInput: true,
                                            termsOfServiceDisclaimer: makeDisclaimer())
    }

    private func show(_ viewController: UIViewController) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 540, height: 620))
        window.rootViewController = viewController
        window.isHidden = false
        viewController.view.layoutIfNeeded()
        return window
    }

    private func termsOfServiceCard(in viewController: UIViewController) -> UTIFooterCardView? {
        findSubview(in: viewController.view) { $0 is UTIFooterCardView } as? UTIFooterCardView
    }

    private func findSubview(in view: UIView, matching predicate: (UIView) -> Bool) -> UIView? {
        if predicate(view) {
            return view
        }
        for subview in view.subviews {
            if let match = findSubview(in: subview, matching: predicate) {
                return match
            }
        }
        return nil
    }
}
