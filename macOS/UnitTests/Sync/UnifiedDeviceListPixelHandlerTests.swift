//
//  UnifiedDeviceListPixelHandlerTests.swift
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
import DDGSync
@_spi(Testing) import PixelKit
@testable import DuckDuckGo_Privacy_Browser

final class UnifiedDeviceListPixelHandlerTests: XCTestCase {

    func testUnifiedDeviceListPixelHandlerMapsStandardAndDailyEvents() throws {
        let pixelFiring = PixelKitMock()
        let handler = UnifiedDeviceListPixelHandler(pixelFiring: pixelFiring)

        handler.fire(.accountInfoKeyCreateSuccess)
        handler.fire(.ownRowResolvedLegacy(.blobAbsent))

        let firstCall = try XCTUnwrap(pixelFiring.actualFireCalls.first)
        XCTAssertEqual(pixelFiring.actualFireCalls.map(\.pixel.name), [
            "sync_unified_devices_account_info_key_create_success",
            "sync_unified_devices_own_row_resolved_legacy"
        ])
        XCTAssertEqual(pixelFiring.actualFireCalls.map(\.frequency), [.standard, .daily])
        XCTAssertEqual(pixelFiring.actualFireCalls.last?.pixel.parameters, ["reason": "blob_absent"])
        XCTAssertEqual(firstCall.pixel.standardParameters, [.pixelSource])
        XCTAssertEqual(firstCall.pixel.namePrefix, PixelKitNamePrefix.none)
    }
}
