//
//  ConfigurationFileReadErrorTests.swift
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
@testable import Configuration

final class ConfigurationFileReadErrorTests: XCTestCase {

    func testWhenFileDoesNotExistThenErrorIsExpected() {
        // The configuration simply hasn't been downloaded yet.
        let error = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)
        XCTAssertTrue(Configuration.isExpectedFileReadError(error))
    }

    func testWhenFileIsUnreadableDueToDataProtectionThenErrorIsExpected() {
        // A background reader (e.g. the VPN extension) hit the file while iOS Data
        // Protection had it locked - device locked or before first unlock. Transient.
        let error = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)
        XCTAssertTrue(Configuration.isExpectedFileReadError(error))
    }

    func testWhenFileIsCorruptThenErrorIsNotExpected() {
        // A genuine load failure the reporting exists to catch.
        let error = NSError(domain: NSCocoaErrorDomain, code: NSFileReadCorruptFileError)
        XCTAssertFalse(Configuration.isExpectedFileReadError(error))
    }

    func testWhenErrorIsNotACocoaErrorThenItIsNotExpected() {
        let error = NSError(domain: NSPOSIXErrorDomain, code: 1)
        XCTAssertFalse(Configuration.isExpectedFileReadError(error))
    }
}
