//
//  DesignSystemImagesTests.swift
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
@testable import DesignResourcesKitIcons

/// Verifies that generated asset symbols (by Xcode, or by AssetCatalogPlugin
/// under `swift test`) resolve to images compiled into `Bundle.module`.
final class DesignSystemImagesTests: XCTestCase {

    func testGlyphLoadsFromGeneratedSymbol() {
        XCTAssertEqual(DesignSystemImages.Glyphs.Size12.add.size, CGSize(width: 12, height: 12))
    }

    func testColorIconLoadsFromGeneratedSymbol() {
        XCTAssertEqual(DesignSystemImages.Color.Size16.accessibility.size, CGSize(width: 16, height: 16))
    }

    func testRecolorableSymbolLoadsFromGeneratedSymbol() {
        XCTAssertGreaterThan(DesignSystemImages.Recolorable.Size24.check.size.width, 0)
    }
}
