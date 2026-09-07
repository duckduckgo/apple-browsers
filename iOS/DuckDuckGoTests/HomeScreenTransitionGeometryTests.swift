//
//  HomeScreenTransitionGeometryTests.swift
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

final class HomeScreenTransitionGeometryTests: XCTestCase {

    func testWhenListViewIsEnabledThenSnapshotFillsTheWidthAndCropsVertically() {
        let sourceSize = CGSize(width: 390, height: 800)
        let container = CGRect(x: 0, y: 0, width: 390, height: 68)

        let frame = HomeScreenTransitionGeometry.snapshotFrame(
            for: sourceSize,
            in: container,
            isGridViewEnabled: false)

        XCTAssertEqual(frame, CGRect(x: 0, y: 0, width: 390, height: 800))
        XCTAssertEqual(frame.width / frame.height, sourceSize.width / sourceSize.height, accuracy: 0.001)
    }

    func testWhenGridCellIsWiderThanThePageThenSnapshotScalesUniformlyAndStaysCentred() {
        let sourceSize = CGSize(width: 390, height: 800)
        let container = CGRect(x: 10, y: 20, width: 180, height: 240)

        let frame = HomeScreenTransitionGeometry.snapshotFrame(
            for: sourceSize,
            in: container,
            isGridViewEnabled: true)

        XCTAssertEqual(frame.width, sourceSize.width * (container.height / sourceSize.height), accuracy: 0.001)
        XCTAssertEqual(frame.height, 240)
        XCTAssertEqual(frame.midX, container.midX, accuracy: 0.001)
        XCTAssertEqual(frame.midY, container.midY, accuracy: 0.001)
        XCTAssertEqual(frame.width / frame.height, sourceSize.width / sourceSize.height, accuracy: 0.001)
    }

    func testWhenSourceSizeIsZeroThenFrameFillsTheContainer() {
        let container = CGRect(x: 4, y: 8, width: 180, height: 68)
        XCTAssertEqual(
            HomeScreenTransitionGeometry.snapshotFrame(
                for: .zero,
                in: container,
                isGridViewEnabled: false),
            container)
    }

    func testWhenSourceSizeIsNonFiniteThenFrameFillsTheContainer() {
        let container = CGRect(x: 0, y: 0, width: 180, height: 68)
        let infinite = CGSize(width: CGFloat.infinity, height: 800)
        XCTAssertEqual(
            HomeScreenTransitionGeometry.snapshotFrame(
                for: infinite,
                in: container,
                isGridViewEnabled: false),
            container)
    }
}
