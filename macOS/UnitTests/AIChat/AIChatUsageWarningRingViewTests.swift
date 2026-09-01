//
//  AIChatUsageWarningRingViewTests.swift
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
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class AIChatUsageWarningRingViewTests: XCTestCase {

    private var sut: AIChatUsageWarningRingView!

    override func setUp() {
        super.setUp()
        sut = AIChatUsageWarningRingView()
        sut.frame = NSRect(x: 0, y: 0,
                           width: AIChatUsageWarningRingView.Constants.size,
                           height: AIChatUsageWarningRingView.Constants.size)
        sut.layoutSubtreeIfNeeded()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    func testProgressFillsTheStroke() {
        sut.setProgress(0.9, severity: .critical, animated: false)

        XCTAssertEqual(progressLayer.strokeEnd, 0.9, accuracy: 0.001)
    }

    /// The percentage arrives capped web-side, but a payload we haven't seen shouldn't draw past the ring.
    func testProgressIsClamped() {
        sut.setProgress(1.4, severity: .critical, animated: false)
        XCTAssertEqual(progressLayer.strokeEnd, 1, accuracy: 0.001)

        sut.setProgress(-0.2, severity: .info, animated: false)
        XCTAssertEqual(progressLayer.strokeEnd, 0, accuracy: 0.001)
    }

    /// Each step is a different colour, and the same step never repaints — that is the whole point of
    /// the ring over a plain glyph.
    func testEachSeverityStepDrawsItsOwnColour() {
        var colours: [DuckAiUsageSeverity: CGColor] = [:]
        for (index, severity) in [DuckAiUsageSeverity.info, .warning, .critical].enumerated() {
            sut.setProgress(Double(index + 1) / 10, severity: severity, animated: false)
            colours[severity] = progressLayer.strokeColor
        }

        XCTAssertEqual(colours.count, 3)
        XCTAssertNotEqual(colours[.info], colours[.warning])
        XCTAssertNotEqual(colours[.warning], colours[.critical])
    }

    /// A reached limit shares the critical colour: both mean "out of room", and the card swaps to the
    /// alert glyph there anyway.
    func testReachedMatchesCritical() {
        sut.setProgress(0.9, severity: .critical, animated: false)
        let critical = progressLayer.strokeColor

        sut.setProgress(1, severity: .reached, animated: false)

        XCTAssertEqual(progressLayer.strokeColor, critical)
    }

    /// Both arcs need a path, or the ring draws nothing at all.
    func testLayoutGivesBothArcsAPath() {
        XCTAssertNotNil(trackLayer.path)
        XCTAssertNotNil(progressLayer.path)
        XCTAssertEqual(trackLayer.path, progressLayer.path)
    }

    /// Starts at twelve o'clock: the track's own bounding box is the tell, since an arc that began
    /// elsewhere would not be centred on the view.
    func testTheRingIsCentredOnTheView() {
        let box = try? XCTUnwrap(trackLayer.path).boundingBox

        XCTAssertEqual(box?.midX ?? 0, sut.bounds.midX, accuracy: 0.01)
        XCTAssertEqual(box?.midY ?? 0, sut.bounds.midY, accuracy: 0.01)
    }

    private var trackLayer: CAShapeLayer {
        shapeLayers[0]
    }

    private var progressLayer: CAShapeLayer {
        shapeLayers[1]
    }

    private var shapeLayers: [CAShapeLayer] {
        (sut.layer?.sublayers ?? []).compactMap { $0 as? CAShapeLayer }
    }
}
