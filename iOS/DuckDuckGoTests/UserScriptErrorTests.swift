//
//  UserScriptErrorTests.swift
//  DuckDuckGo
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
@testable import Core
@testable import BrowserServicesKit

final class UserScriptErrorTests: XCTestCase {

    func testfireLoadJSFailedPixelIfNeeded_FiresExpectedPixel() async throws {
        let jsFile = "testFile"
        let path = "/path/to/file"
        let underlyingError = NSError(domain: "TestDomain", code: 1, userInfo: nil)
        let error = UserScriptError.failedToLoadJS(jsFile: jsFile, path: path, error: underlyingError)

        let expectedPixel = PixelInfo(pixelName: Pixel.Event.userScriptLoadJSFailed.name,
                                      error: underlyingError,
                                      params: [PixelParameters.jsFile: jsFile, PixelParameters.path: path],
                                      includedParams: [.appVersion])

        error.fireLoadJSFailedPixelIfNeeded(pixelFiring: PixelFiringMock.self)

        XCTAssertEqual(PixelFiringMock.lastPixelName, expectedPixel.pixelName)
        XCTAssertEqual(PixelFiringMock.lastParams, expectedPixel.params)
        XCTAssertEqual(PixelFiringMock.lastIncludedParams, expectedPixel.includedParams)
        XCTAssertEqual(PixelFiringMock.lastPixelInfo?.error as? NSError, underlyingError)
    }

}
