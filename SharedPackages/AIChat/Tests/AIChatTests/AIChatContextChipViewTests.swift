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

    func testSubtitleSetsCorrectly() {
        // Given
        let sut = AIChatContextChipView()
        let expectedSubtitle = "Page Content"

        // When
        sut.subtitle = expectedSubtitle

        // Then
        XCTAssertEqual(sut.subtitle, expectedSubtitle)
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
}
#endif
