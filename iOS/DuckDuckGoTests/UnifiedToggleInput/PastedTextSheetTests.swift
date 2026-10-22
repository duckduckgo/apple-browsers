//
//  PastedTextSheetTests.swift
//  DuckDuckGo
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
import DesignResourcesKit
import SwiftUI
import UIKit
import XCTest
@testable import DuckDuckGo

@MainActor
final class PastedTextSheetTests: XCTestCase {

    private let original = AIChatPastedText(content: "original text")

    func testSaveIsOffWhenBlankOrOverTheLimitAndOnOtherwise() {
        let rules = PastedTextSheetRules(original: original, mode: .editable(limit: 10))

        XCTAssertFalse(rules.canSave(""))
        XCTAssertFalse(rules.canSave(" \n\t"))
        XCTAssertFalse(rules.canSave("12345678901"))
        XCTAssertTrue(rules.canSave("1234567890"))
    }

    func testSaveIsNeverOfferedInViewOnlyMode() {
        let rules = PastedTextSheetRules(original: original, mode: .viewOnly)

        XCTAssertFalse(rules.canSave("fine"))
        XCTAssertFalse(rules.isOverLimit(String(repeating: "a", count: 100_000)))
    }

    func testSavingIdenticalContentIsUnchangedAndAnEditIsANewValue() {
        let rules = PastedTextSheetRules(original: original, mode: .editable(limit: 100))

        XCTAssertEqual(rules.outcome(savingText: "original text"), .unchanged)
        guard case .saved(let edited) = rules.outcome(savingText: "edited") else { return XCTFail("Expected a saved outcome") }
        XCTAssertEqual(edited.content, "edited")
        XCTAssertNotEqual(edited.id, original.id, "A new id so id-based draft equality sees the edit")
    }

    func testEditableSheetOpensWithTheKeyboardAndViewOnlyDoesNot() {
        let paste = AIChatPastedText(content: "pasted")
        XCTAssertTrue(PastedTextSheetRules(original: paste, mode: .editable(limit: 100)).opensWithKeyboard)
        XCTAssertFalse(PastedTextSheetRules(original: paste, mode: .viewOnly).opensWithKeyboard)
    }

    func testViewOnlySheetShowsTheFullTextInAScrollableReadOnlyViewAndEditableKeepsTheEditor() throws {
        let content = String(repeating: "line\n", count: 2_000)
        let viewOnly = try textView(hosting: .viewOnly, content: content)
        XCTAssertFalse(viewOnly.isEditable)
        XCTAssertTrue(viewOnly.isScrollEnabled, "Reading past the first screen needs scrolling")
        XCTAssertTrue(viewOnly.isSelectable)
        XCTAssertEqual(viewOnly.text, content)

        let editable = try textView(hosting: .editable(limit: 100_000), content: content)
        XCTAssertTrue(editable.isEditable)
        XCTAssertEqual(editable.text, content)
    }

    private func textView(hosting mode: PastedTextSheetMode, content: String) throws -> UITextView {
        let view = PastedTextSheetView(pastedText: AIChatPastedText(content: content), mode: mode, onSave: { _ in }, onCancel: {})
        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        return try XCTUnwrap(firstDescendant(of: UITextView.self, in: controller.view), "The sheet shows its text in a UITextView")
    }

    private func firstDescendant<T: UIView>(of type: T.Type, in view: UIView) -> T? {
        if let match = view as? T { return match }
        return view.subviews.lazy.compactMap { self.firstDescendant(of: type, in: $0) }.first
    }

    func testCountIsUTF16() {
        let rules = PastedTextSheetRules(original: original, mode: .editable(limit: 100))

        XCTAssertEqual(rules.count(of: "😀"), 2)
    }

    func testHostingControllerReportsOneOutcomeHoweverItCloses() {
        var outcomes: [PastedTextSheetOutcome] = []
        let view = PastedTextSheetView(pastedText: original, mode: .editable(limit: 100), onSave: { _ in }, onCancel: {})
        let controller = PastedTextSheetHostingController(rootView: view) { outcomes.append($0) }

        controller.finish(.saved(AIChatPastedText(content: "edited")))
        controller.viewDidDisappear(false)

        XCTAssertEqual(outcomes.count, 1)
        guard case .saved(let saved) = outcomes.first else { return XCTFail("Expected the saved outcome to win") }
        XCTAssertEqual(saved.content, "edited")
    }

    func testHostingControllerReportsUnchangedWhenDismissedWithoutSaving() {
        var outcomes: [PastedTextSheetOutcome] = []
        let view = PastedTextSheetView(pastedText: original, mode: .editable(limit: 100), onSave: { _ in }, onCancel: {})
        let controller = PastedTextSheetHostingController(rootView: view) { outcomes.append($0) }

        controller.viewDidDisappear(false)
        controller.viewDidDisappear(false)

        XCTAssertEqual(outcomes, [.unchanged])
    }

    func testEditableSubtitleIsThePlainCountAgainstTheLimit() throws {
        let rules = PastedTextSheetRules(original: original, mode: .editable(limit: 16_000))

        let subtitle = try XCTUnwrap(rules.subtitle(for: String(repeating: "a", count: 923)))

        XCTAssertEqual(subtitle, PastedTextSheetSubtitle(count: 923, limit: 16_000))
        XCTAssertFalse(subtitle.isOverLimit)
        let line = subtitle.attributed(locale: Self.english)
        XCTAssertEqual(String(line.characters), "923/16,000", "Whole numbers, no compact 16k and no unit")
        XCTAssertEqual(colors(in: line), [
            "923": light(.textPrimary),
            "/16,000": light(.textSecondary)
        ])
    }

    func testOverTheLimitOnlyTheCountTurnsRed() throws {
        let rules = PastedTextSheetRules(original: original, mode: .editable(limit: 16_000))

        let subtitle = try XCTUnwrap(rules.subtitle(for: String(repeating: "a", count: 16_001)))

        XCTAssertTrue(subtitle.isOverLimit)
        let line = subtitle.attributed(locale: Self.english)
        XCTAssertEqual(String(line.characters), "16,001/16,000")
        XCTAssertEqual(colors(in: line), [
            "16,001": light(.destructivePrimary),
            "/16,000": light(.textSecondary)
        ])
    }

    func testTheCountKeepsItsColourWhenItIsAPrefixOfTheLimit() {
        let subtitle = PastedTextSheetSubtitle(count: 16, limit: 16_000)

        XCTAssertEqual(colors(in: subtitle.attributed(format: "%1$d/%2$d", locale: Self.plainDigits)), [
            "16": light(.textPrimary),
            "/16000": light(.textSecondary)
        ])
    }

    func testTheCountKeepsItsColourWhenATranslationPutsTheLimitFirst() {
        let subtitle = PastedTextSheetSubtitle(count: 16, limit: 16_000)

        let line = subtitle.attributed(format: "%2$d / %1$d", locale: Self.plainDigits)

        XCTAssertEqual(String(line.characters), "16000 / 16")
        XCTAssertEqual(colors(in: line), [
            "16000 / ": light(.textSecondary),
            "16": light(.textPrimary)
        ])
    }

    func testTheCountUsesLocaleDigitsAndStillTurnsRed() {
        let subtitle = PastedTextSheetSubtitle(count: 16_001, limit: 16_000)

        let line = subtitle.attributed(locale: Locale(identifier: "ar_EG"))

        XCTAssertEqual(String(line.characters), "١٦٬٠٠١/١٦٬٠٠٠")
        XCTAssertEqual(colors(in: line), [
            "١٦٬٠٠١": light(.destructivePrimary),
            "/١٦٬٠٠٠": light(.textSecondary)
        ])
    }

    func testVoiceOverReadsTheCountAsCharactersOfTheLimitNotASlash() {
        let subtitle = PastedTextSheetSubtitle(count: 923, limit: 16_000)

        XCTAssertEqual(subtitle.accessibilityLabel(locale: Self.english), "923 of 16,000 characters")
    }

    func testCountAtExactlyTheLimitIsNotRed() throws {
        let rules = PastedTextSheetRules(original: original, mode: .editable(limit: 16_000))

        let subtitle = try XCTUnwrap(rules.subtitle(for: String(repeating: "a", count: 16_000)))

        XCTAssertEqual(colors(in: subtitle.attributed(locale: Self.english))["16,000"], light(.textPrimary))
    }

    func testViewOnlySheetIsTitledPastedTextWithNoSubtitleAndEditableIsEditText() {
        let viewOnly = PastedTextSheetRules(original: original, mode: .viewOnly)
        let editable = PastedTextSheetRules(original: original, mode: .editable(limit: 100))

        XCTAssertEqual(viewOnly.title, "Pasted Text")
        XCTAssertNil(viewOnly.subtitle(for: "anything"))
        XCTAssertEqual(editable.title, "Edit Text")
    }

    private func colors(in line: AttributedString) -> [String: UIColor] {
        var result: [String: UIColor] = [:]
        for run in line.runs {
            result[String(line[run.range].characters)] = run.foregroundColor.map { UIColor($0).resolvedColor(with: Self.light) }
        }
        return result
    }

    private static let light = UITraitCollection(userInterfaceStyle: .light)
    private static let english = Locale(identifier: "en_US")
    /// POSIX formats numbers without grouping, which keeps the prefix cases readable.
    private static let plainDigits = Locale(identifier: "en_US_POSIX")

    private func light(_ color: DesignSystemColor) -> UIColor {
        UIColor(designSystemColor: color).resolvedColor(with: Self.light)
    }

    func testOnlyChangedTextInAnEditableSheetIsAnUnsavedEdit() {
        let editable = PastedTextSheetRules(original: original, mode: .editable(limit: 100))
        let viewOnly = PastedTextSheetRules(original: original, mode: .viewOnly)

        XCTAssertFalse(editable.hasUnsavedEdits("original text"))
        XCTAssertTrue(editable.hasUnsavedEdits("original text!"))
        XCTAssertFalse(viewOnly.hasUnsavedEdits("original text!"))
    }

    func testSheetRefusesInteractiveDismissalOnlyWhileItHasUnsavedEdits() throws {
        let host = UIViewController()
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        PastedTextSheetPresenter.present(original, mode: .editable(limit: 100), from: host) { _ in }
        let sheet = try XCTUnwrap(host.presentedViewController as? PastedTextSheetHostingController)
        XCTAssertFalse(sheet.isModalInPresentation)

        sheet.rootView.onUnsavedEditsChanged(true)
        XCTAssertTrue(sheet.isModalInPresentation)

        sheet.rootView.onUnsavedEditsChanged(false)
        XCTAssertFalse(sheet.isModalInPresentation)
    }

    func testPresenterPresentsFromTheTopmostControllerAboveTheHost() {
        let host = UIViewController()
        let presented = UIViewController()
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.present(presented, animated: false)

        XCTAssertTrue(PastedTextSheetPresenter.topmost(from: host) === presented)
    }
}
