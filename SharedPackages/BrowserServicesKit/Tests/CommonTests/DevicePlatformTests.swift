//
//  DevicePlatformTests.swift
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
@testable import Common

#if canImport(UIKit)
import UIKit
#endif

final class DevicePlatformTests: XCTestCase {

    func testWhenDeviceIsMac_ThenIsMacIsTrue() {
        #if os(macOS)
        XCTAssertTrue(DevicePlatform.isMac)
        #endif
    }

    func testWhenDeviceIsPhone_ThenIsIphoneIsTrue() {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            XCTAssertTrue(DevicePlatform.isIphone)
        }
        #endif
    }

    func testWhenDeviceIsTablet_ThenIsIpadIsTrue() {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCTAssertTrue(DevicePlatform.isIpad)
        }
        #endif
    }

    func testWhenGettingCurrentPlatform_thenPlatformMatchesCurrentDevice() {
        #if os(macOS)
        XCTAssertEqual(DevicePlatform.currentPlatform, .macOS)
        #elseif os(iOS)
        XCTAssertEqual(DevicePlatform.currentPlatform, .iOS)
        #endif
    }

}
