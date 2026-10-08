//
//  BundledAnimationAssetsTests.swift
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

import AppKit
import XCTest
@testable import DuckDuckGo_Privacy_Browser

/// Lottie animations stored as data sets in the browser package's asset catalog are loaded with
/// `LottieAnimation.asset(_:bundle: .module)`, which reads them as `NSDataAsset`s.
final class BundledAnimationAssetsTests: XCTestCase {

    func testLottieDataAssetsAreInThePackageBundle() {
        let assetNames = [
            "fire-pictogram",
            "fire-pictogram-new",
            "dax-waving-dark",
            "dax-waving-light",
            "wing-pointing",
        ]

        for assetName in assetNames {
            XCTAssertNotNil(NSDataAsset(name: assetName, bundle: .module), assetName)
        }
    }

}
