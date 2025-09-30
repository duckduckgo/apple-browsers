//
//  CheckForUpdatesAppStorePixelsTests.swift
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
import PixelKit
@testable import DuckDuckGo_Privacy_Browser

final class CheckForUpdatesAppStorePixelsTests: XCTestCase {

    // MARK: - Pixel Name Tests

    func testCheckForUpdatePixel_HasCorrectName() {
        // Given
        let pixel = CheckForUpdatesAppStorePixels.checkForUpdate(source: .mainMenu)

        // When
        let name = pixel.name

        // Then
        XCTAssertEqual(name, "m_mac_app_store_check_for_update")
    }

    // MARK: - Pixel Parameters Tests

    func testCheckForUpdatePixel_MainMenuSource_HasCorrectParameters() {
        // Given
        let pixel = CheckForUpdatesAppStorePixels.checkForUpdate(source: .mainMenu)

        // When
        let parameters = pixel.parameters

        // Then
        XCTAssertEqual(parameters?["source"], "main_menu")
    }

    func testCheckForUpdatePixel_MoreOptionsMenuSource_HasCorrectParameters() {
        // Given
        let pixel = CheckForUpdatesAppStorePixels.checkForUpdate(source: .moreOptionsMenu)

        // When
        let parameters = pixel.parameters

        // Then
        XCTAssertEqual(parameters?["source"], "more_options")
    }

    func testCheckForUpdatePixel_AboutMenuSource_HasCorrectParameters() {
        // Given
        let pixel = CheckForUpdatesAppStorePixels.checkForUpdate(source: .aboutMenu)

        // When
        let parameters = pixel.parameters

        // Then
        XCTAssertEqual(parameters?["source"], "about")
    }

    // MARK: - Error Property Tests

    func testCheckForUpdatePixel_HasNoError() {
        // Given
        let pixel = CheckForUpdatesAppStorePixels.checkForUpdate(source: .mainMenu)

        // When
        let error = pixel.error

        // Then
        XCTAssertNil(error)
    }

    // MARK: - Source Enum Tests

    func testSourceEnum_MainMenuRawValue() {
        XCTAssertEqual(CheckForUpdatesAppStorePixels.Source.mainMenu.rawValue, "main_menu")
    }

    func testSourceEnum_MoreOptionsMenuRawValue() {
        XCTAssertEqual(CheckForUpdatesAppStorePixels.Source.moreOptionsMenu.rawValue, "more_options")
    }

    func testSourceEnum_AboutMenuRawValue() {
        XCTAssertEqual(CheckForUpdatesAppStorePixels.Source.aboutMenu.rawValue, "about")
    }
}
