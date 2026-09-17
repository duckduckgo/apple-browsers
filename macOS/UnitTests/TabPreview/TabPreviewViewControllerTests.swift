//
//  TabPreviewViewControllerTests.swift
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

import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class TabPreviewViewControllerTests: XCTestCase {

    /// Regression test for #4615: a snapshot with a zero width or height must yield a finite height
    /// (0), never NaN. `getHeight` feeds `snapshotImageViewHeightConstraint.constant`, and assigning
    /// NaN there crashes AppKit layout. Reverting the `width > 0, height > 0` guard makes 0×0 produce
    /// `0/0 = NaN`, failing the `.isFinite` assertions below.
    func testGetHeightReturnsZeroForZeroDimensionSnapshot() {
        let sut = TabPreviewViewController()

        let zeroSize = sut.getHeight(for: NSImage(size: .zero))
        XCTAssertTrue(zeroSize.isFinite)
        XCTAssertEqual(zeroSize, 0)

        let zeroHeight = sut.getHeight(for: NSImage(size: NSSize(width: 100, height: 0)))
        XCTAssertTrue(zeroHeight.isFinite)
        XCTAssertEqual(zeroHeight, 0)

        let zeroWidth = sut.getHeight(for: NSImage(size: NSSize(width: 0, height: 100)))
        XCTAssertTrue(zeroWidth.isFinite)
        XCTAssertEqual(zeroWidth, 0)

        XCTAssertEqual(sut.getHeight(for: nil), 0)
    }

    func testGetHeightComputesFiniteHeightForValidSnapshot() {
        let sut = TabPreviewViewController()

        let height = sut.getHeight(for: NSImage(size: NSSize(width: 200, height: 100)))

        XCTAssertTrue(height.isFinite)
        XCTAssertGreaterThan(height, 0)
    }
}
