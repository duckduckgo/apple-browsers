//
//  WebViewTransitionGeometryTests.swift
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

import XCTest
import UIKit
@testable import DuckDuckGo

final class WebViewTransitionGeometryTests: XCTestCase {

    // MARK: - aspectRatio

    func testAspectRatioReturnsHeightOverWidthForNormalSize() {
        let ratio = WebViewTransitionGeometry.aspectRatio(of: CGSize(width: 100, height: 200))
        XCTAssertEqual(ratio, 2.0)
    }

    func testAspectRatioIsNilForZeroWidth() {
        XCTAssertNil(WebViewTransitionGeometry.aspectRatio(of: CGSize(width: 0, height: 200)))
    }

    func testAspectRatioIsNilForZeroHeight() {
        XCTAssertNil(WebViewTransitionGeometry.aspectRatio(of: CGSize(width: 100, height: 0)))
    }

    func testAspectRatioIsNilForZeroSize() {
        XCTAssertNil(WebViewTransitionGeometry.aspectRatio(of: .zero))
    }

    func testAspectRatioIsNilForInfiniteDimension() {
        XCTAssertNil(WebViewTransitionGeometry.aspectRatio(of: CGSize(width: CGFloat.infinity, height: 200)))
    }

    func testAspectRatioIsNilForNaNDimension() {
        XCTAssertNil(WebViewTransitionGeometry.aspectRatio(of: CGSize(width: 100, height: CGFloat.nan)))
    }

    // MARK: - previewFrame (crash regression guard)

    func testPreviewFrameIsFiniteForZeroSizedPreview() {
        let frame = WebViewTransitionGeometry.previewFrame(for: CGSize(width: 180, height: 240),
                                                           previewSize: .zero,
                                                           isGridViewEnabled: true)
        assertFinite(frame)
    }

    func testPreviewFrameReturnsExactFrameForNormalPreview() {
        let frame = WebViewTransitionGeometry.previewFrame(for: CGSize(width: 180, height: 240),
                                                           previewSize: CGSize(width: 300, height: 600),
                                                           isGridViewEnabled: true)
        XCTAssertEqual(frame, CGRect(x: 4, y: 44, width: 172, height: 344))
    }

    func testPreviewFrameFillsCellBoundsWhenGridDisabled() {
        let cellBounds = CGSize(width: 180, height: 240)
        let frame = WebViewTransitionGeometry.previewFrame(for: cellBounds,
                                                           previewSize: CGSize(width: 300, height: 600),
                                                           isGridViewEnabled: false)
        XCTAssertEqual(frame, CGRect(origin: .zero, size: cellBounds))
    }

    // MARK: - destinationImageFrame (crash regression guard)

    func testDestinationImageFrameIsFiniteForZeroSizedPreview() {
        let frame = WebViewTransitionGeometry.destinationImageFrame(for: CGSize(width: 390, height: 800),
                                                                    previewSize: .zero)
        assertFinite(frame)
    }

    func testDestinationImageFrameIsFiniteForNilPreview() {
        let frame = WebViewTransitionGeometry.destinationImageFrame(for: CGSize(width: 390, height: 800),
                                                                    previewSize: nil)
        assertFinite(frame)
    }

    func testDestinationImageFrameFillsContainerWidthForNormalPreview() {
        let frame = WebViewTransitionGeometry.destinationImageFrame(for: CGSize(width: 390, height: 800),
                                                                    previewSize: CGSize(width: 100, height: 200))
        assertFinite(frame)
        XCTAssertEqual(frame.width, 390)
        XCTAssertEqual(frame.height, 780) // 390 * (200/100)
    }

    // MARK: - Helpers

    private func assertFinite(_ rect: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(rect.origin.x.isFinite, "origin.x not finite", file: file, line: line)
        XCTAssertTrue(rect.origin.y.isFinite, "origin.y not finite", file: file, line: line)
        XCTAssertTrue(rect.size.width.isFinite, "width not finite", file: file, line: line)
        XCTAssertTrue(rect.size.height.isFinite, "height not finite", file: file, line: line)
    }
}
