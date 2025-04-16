//
//  HistoryViewOnboardingViewModelTests.swift
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

import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class HistoryViewOnboardingViewModelTests: XCTestCase {

    var viewModel: HistoryViewOnboardingViewModel!
    var pixels: [HistoryViewPixel] = []

    override func setUp() async throws {
        pixels = []
        viewModel = HistoryViewOnboardingViewModel(
            settingsStorage: MockHistoryViewOnboardingViewSettingsPersistor(),
            firePixel: { self.pixels.append($0) },
            ctaCallback: { _ in }
        )
    }

    func testThatMarkAsShownFiresPixel() throws {
        viewModel.markAsShown()
        XCTAssertEqual(pixels.count, 1)
        let pixel = try XCTUnwrap(pixels.first)
        guard case .onboardingDialogShown = pixel else {
            XCTFail("Unexpected pixel fired")
            return
        }
    }

    func testThatNotNowFiresPixel() throws {
        viewModel.notNow()
        XCTAssertEqual(pixels.count, 1)
        let pixel = try XCTUnwrap(pixels.first)
        guard case .onboardingDialogDismissed = pixel else {
            XCTFail("Unexpected pixel fired")
            return
        }
    }

    func testThatShowHistoryFiresPixel() throws {
        viewModel.showHistory()
        XCTAssertEqual(pixels.count, 1)
        let pixel = try XCTUnwrap(pixels.first)
        guard case .onboardingDialogAccepted = pixel else {
            XCTFail("Unexpected pixel fired")
            return
        }
    }
}
