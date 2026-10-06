//
//  PixelKitMock+Verify.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
@_spi(Testing) import PixelKit
import XCTest

@_spi(Testing)
public extension PixelKitMock {

    /// Asserts the mock saw exactly the fire calls it was told to expect.
    ///
    /// Lives here rather than on `PixelKitMock` itself so that PixelKit's testing support does not link
    /// XCTest. A target that links XCTest cannot be built as a dynamic framework, so Xcode links it
    /// statically and absorbs `PixelKit` into every test bundle — giving the app and the tests separate
    /// `PixelKit.shared` values, at which point pixels fired by app code vanish silently.
    func verifyExpectations(file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(expectedFireCalls, actualFireCalls, file: file, line: line)
    }
}
