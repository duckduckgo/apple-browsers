//
//  AIChatContextChipViewTests.swift
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

#if os(iOS)
import XCTest
@testable import AIChat

final class AIChatContextChipViewTests: XCTestCase {

    func testConfigureSetsTitle() {
        // Given
        let sut = AIChatContextChipView()
        let expectedTitle = "Test Page Title"

        // When
        sut.configure(title: expectedTitle, favicon: nil)

        // Then
        XCTAssertEqual(sut.accessibilityLabel, expectedTitle)
    }

    func testOnRemoveCallbackIsSettable() {
        // Given
        let sut = AIChatContextChipView()

        // When
        sut.onRemove = {}

        // Then
        XCTAssertNotNil(sut.onRemove)
    }

    func testUpdateSetsNewTitle() {
        // Given
        let sut = AIChatContextChipView()
        sut.configure(title: "Original Title", favicon: nil)

        // When
        sut.update(title: "Updated Title", favicon: nil)

        // Then
        XCTAssertEqual(sut.accessibilityLabel, "Updated Title")
    }

    func testUpdateSetsNewFaviconWhenProvided() {
        // Given
        let sut = AIChatContextChipView()
        let originalFavicon = UIImage()
        let newFavicon = UIImage()
        sut.configure(title: "Title", favicon: originalFavicon)

        // When
        sut.update(title: "Title", favicon: newFavicon)

        // Then
        XCTAssertNotNil(sut.subviews.first)
    }

    func testUpdatePreservesFaviconWhenNil() {
        // Given
        let sut = AIChatContextChipView()
        let originalFavicon = UIImage()
        sut.configure(title: "Original", favicon: originalFavicon)

        // When
        sut.update(title: "Updated", favicon: nil)

        // Then
        XCTAssertEqual(sut.accessibilityLabel, "Updated")
    }

    // MARK: - Suggested state

    func testSuggestedStateWrapsThePageTitleInTheAttachOffer() {
        // Given
        let sut = AIChatContextChipView()
        let pageTitle = "Magnetic confinement fusion"

        // When
        sut.configure(state: .suggested(title: pageTitle, favicon: nil))

        // Then
        let label = sut.accessibilityLabel
        XCTAssertEqual(label, UserText.askAboutPage(title: pageTitle))
        XCTAssertEqual(label?.contains(pageTitle), true)
        XCTAssertNotEqual(label, pageTitle)
    }

    func testUpdateIsIgnoredInTheSuggestedState() {
        // Given
        let sut = AIChatContextChipView()
        sut.configure(state: .suggested(title: "Original", favicon: nil))
        let offerBefore = sut.accessibilityLabel

        // When
        sut.update(title: "Updated", favicon: nil)

        // Then
        XCTAssertEqual(sut.accessibilityLabel, offerBefore)
    }

    func testChipTapIsNotReceivedOverTheRemoveButton() {
        // Given
        let sut = AIChatContextChipView()
        sut.configure(state: .suggested(title: "Magnetic confinement fusion", favicon: nil))
        sut.frame = CGRect(x: 0, y: 0, width: 240, height: 44)
        sut.layoutIfNeeded()

        // Then — the 32pt button sits 10pt from the trailing edge, so its centre is (240-10-16, 22).
        XCTAssertFalse(sut.shouldReceiveChipTap(at: CGPoint(x: 214, y: 22)))
        XCTAssertTrue(sut.shouldReceiveChipTap(at: CGPoint(x: 100, y: 22)))
    }

    func testSuggestedChipAcceptsTheOfferOnVoiceOverActivate() {
        // Given
        let sut = AIChatContextChipView()
        sut.configure(state: .suggested(title: "Tokamak", favicon: nil))
        var accepted = false
        sut.onTap = { accepted = true }

        // Then — the chip itself is the button, and activating it accepts
        XCTAssertTrue(sut.isAccessibilityElement)
        XCTAssertTrue(sut.accessibilityTraits.contains(.button))
        XCTAssertTrue(sut.accessibilityActivate())
        XCTAssertTrue(accepted)
    }

}
#endif
