//
//  SyncPromoViewModelTests.swift
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
@_spi(Testing) @testable import PixelKit

final class SyncPromoViewModelTests: XCTestCase {

    func testWhenPromoDisplayedThenDisplayedPixelFiresWithTouchpointAsSource() {
        let touchpoints: [SyncPromoManager.Touchpoint] = [.bookmarks, .passwords, .autofill, .creditCards, .identities]

        for touchpoint in touchpoints {
            let pixelFiring = PixelKitMock()
            let viewModel = SyncPromoViewModel(touchpointType: touchpoint, pixelFiring: pixelFiring)

            viewModel.promoDisplayed()

            XCTAssertEqual(pixelFiring.actualFireCalls.map(\.pixel.name), [SyncPromoPixelKitEvent.syncPromoDisplayed.name])
            XCTAssertEqual(pixelFiring.actualFireCalls.first?.additionalParameters, ["source": touchpoint.rawValue])
        }
    }
}
