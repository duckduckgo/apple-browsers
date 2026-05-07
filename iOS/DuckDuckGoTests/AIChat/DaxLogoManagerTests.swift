//
//  DaxLogoManagerTests.swift
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

final class DaxLogoManagerTests: XCTestCase {

    private var sut: DaxLogoManager!

    override func setUp() {
        super.setUp()
        sut = DaxLogoManager()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - shouldShowHomeDax

    func test_shouldShowHomeDax_whenHasContent_returnsFalse() {
        let inputs = HomeDaxInputs(
            hasContent: true,
            shouldDisplayFavoritesOverlay: false,
            hasEscapeHatch: false,
            hasFavorites: false,
            hasRemoteMessages: false
        )
        XCTAssertFalse(sut.shouldShowHomeDax(inputs))
    }

    func test_shouldShowHomeDax_whenHasContent_alwaysReturnsFalse_regardlessOfOtherFlags() {
        let inputs = HomeDaxInputs(
            hasContent: true,
            shouldDisplayFavoritesOverlay: true,
            hasEscapeHatch: true,
            hasFavorites: true,
            hasRemoteMessages: true
        )
        XCTAssertFalse(sut.shouldShowHomeDax(inputs))
    }

    func test_shouldShowHomeDax_whenEmptyAndNoFavoritesOverlay_returnsTrue() {
        let inputs = HomeDaxInputs(
            hasContent: false,
            shouldDisplayFavoritesOverlay: false,
            hasEscapeHatch: false,
            hasFavorites: false,
            hasRemoteMessages: false
        )
        XCTAssertTrue(sut.shouldShowHomeDax(inputs))
    }

    func test_shouldShowHomeDax_whenFavoritesOverlayAndNoEscapeHatch_returnsFalse() {
        let inputs = HomeDaxInputs(
            hasContent: false,
            shouldDisplayFavoritesOverlay: true,
            hasEscapeHatch: false,
            hasFavorites: true,
            hasRemoteMessages: false
        )
        XCTAssertFalse(sut.shouldShowHomeDax(inputs))
    }

    func test_shouldShowHomeDax_whenFavoritesOverlayAndEscapeHatchWithFavorites_returnsFalse() {
        let inputs = HomeDaxInputs(
            hasContent: false,
            shouldDisplayFavoritesOverlay: true,
            hasEscapeHatch: true,
            hasFavorites: true,
            hasRemoteMessages: false
        )
        XCTAssertFalse(sut.shouldShowHomeDax(inputs))
    }

    func test_shouldShowHomeDax_whenFavoritesOverlayAndEscapeHatchWithRemoteMessages_returnsFalse() {
        let inputs = HomeDaxInputs(
            hasContent: false,
            shouldDisplayFavoritesOverlay: true,
            hasEscapeHatch: true,
            hasFavorites: false,
            hasRemoteMessages: true
        )
        XCTAssertFalse(sut.shouldShowHomeDax(inputs))
    }

    // The escape hatch exception: even with favorites overlay active, Dax is still shown
    // when the hatch is the only thing present (no favorites, no remote messages).
    func test_shouldShowHomeDax_whenFavoritesOverlayAndOnlyEscapeHatch_returnsTrue() {
        let inputs = HomeDaxInputs(
            hasContent: false,
            shouldDisplayFavoritesOverlay: true,
            hasEscapeHatch: true,
            hasFavorites: false,
            hasRemoteMessages: false
        )
        XCTAssertTrue(sut.shouldShowHomeDax(inputs))
    }
}
