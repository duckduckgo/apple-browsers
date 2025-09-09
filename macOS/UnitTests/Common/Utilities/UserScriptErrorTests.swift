//
//  UserScriptErrorTests.swift
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
import enum UserScript.UserScriptError
@testable import DuckDuckGo_Privacy_Browser
import PixelKitTestingUtilities

final class UserScriptErrorTests: XCTestCase {

    func testfireLoadJSFailedPixelIfNeeded_FiresExpectedPixel() async throws {
        let jsFile = "testFile"
        let underlyingError = NSError(domain: "TestDomain", code: 1, userInfo: nil)
        let error = UserScriptError.failedToLoadJS(jsFile: jsFile, error: underlyingError)
        let mockPixelKit = PixelKitMock(expecting: [
            .init(pixel: GeneralPixel.userScriptLoadJSFailed(jsFile: jsFile, error: underlyingError), frequency: .dailyAndCount)
        ])

        error.fireLoadJSFailedPixelIfNeeded(pixelFiring: mockPixelKit)

        mockPixelKit.verifyExpectations()
    }

}
