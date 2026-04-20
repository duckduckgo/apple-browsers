//
//  DataBrokerProtectionBlankTests.swift
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

import Foundation
import XCTest

final class DataBrokerProtectionBlankTests: XCTestCase {

    // TODO: Remove — temporary test to verify CI crash reporting
    func testInducedCrashForCIVerification() {
        fatalError("Induced crash to verify CI crash reporting")
    }

    // TODO: Remove — temporary test to verify CI failure reporting
    func testInducedFailureForCIVerification() {
        XCTFail("Induced failure to verify CI test summary")
    }
}
