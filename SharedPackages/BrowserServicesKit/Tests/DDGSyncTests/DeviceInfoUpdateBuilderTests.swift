//
//  DeviceInfoUpdateBuilderTests.swift
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

import Foundation
import XCTest

@testable import DDGSync

final class DeviceInfoUpdateBuilderTests: XCTestCase {

    func testWhenMakingUpdateWithoutUnifiedInfoThenInfoIsNilAndLegacyFieldsAreEncrypted() throws {
        let builder = DeviceInfoUpdateBuilder(crypter: CryptingMock(), deviceInfoCodec: DeviceInfoCodec())

        let update = try builder.makeUpdateWithoutUnifiedInfo(deviceID: "device-id",
                                                               deviceName: "Device Name",
                                                               deviceType: "desktop",
                                                               primaryKey: Data())

        XCTAssertEqual(update.id, "device-id")
        XCTAssertEqual(update.name, "encrypted_Device Name")
        XCTAssertEqual(update.type, "encrypted_desktop")
        XCTAssertNil(update.info)
    }
}
