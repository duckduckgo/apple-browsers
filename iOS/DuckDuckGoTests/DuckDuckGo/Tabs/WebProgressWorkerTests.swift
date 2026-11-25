//
//  WebProgressWorkerTests.swift
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
@testable import DuckDuckGo

final class WebProgressWorkerTests: XCTestCase {

    private final class SpyProgressView: ProgressView {
        var shows = 0
        var progresses: [CGFloat] = []

        override func show(initialProgress: CGFloat = 0) {
            shows += 1
        }

        override func increaseProgress(to progress: CGFloat, animated: Bool = false) {
            progresses.append(progress)
        }
    }

    private let bar = SpyProgressView()
    private let worker = WebProgressWorker()

    override func setUp() {
        super.setUp()
        worker.progressBar = bar
    }

    func testPageLoadTakesTheBarOverFromATranslation() {
        worker.didStartLoading(.translation)
        worker.progressDidChange(0.6)

        worker.didStartLoading()
        worker.progressDidChange(0.3)

        XCTAssertFalse(bar.fillsLinearly)
        XCTAssertEqual(bar.shows, 2)
        XCTAssertEqual(bar.progresses.last, 0.3)
    }

    func testTranslationWaitsForAPageLoad() {
        worker.didStartLoading()
        worker.didStartLoading(.translation)

        XCTAssertFalse(bar.fillsLinearly)
        XCTAssertEqual(bar.shows, 1)
    }

    func testTranslationFillsLinearly() {
        worker.didStartLoading(.translation)

        XCTAssertTrue(bar.fillsLinearly)
    }
}
