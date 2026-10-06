//
//  DataBrokerExecutionConfigTests.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import Foundation
@testable import DataBrokerProtectionCore
import DataBrokerProtectionCoreTestsUtils

final class DataBrokerExecutionConfigTests: XCTestCase {

    private let sut = BrokerJobExecutionConfig()
    #if os(macOS) && DEBUG
    private let expectedManualScanConcurrency = 1
    private let expectedScheduledConcurrency = 1
    #else
    private let expectedManualScanConcurrency = 6
    private let expectedScheduledConcurrency = 2
    #endif

    func testWhenOperationIsManualScans_thenUsesManualScanConcurrencyLimit() {
        let value = sut.concurrentJobsFor(.manualScan)
        XCTAssertEqual(value, expectedManualScanConcurrency)
    }

    func testWhenOperationIsScheduledScans_thenUsesScheduledConcurrencyLimit() {
        let value = sut.concurrentJobsFor(.scheduledScan)
        XCTAssertEqual(value, expectedScheduledConcurrency)
    }

    func testWhenOperationIsAll_thenUsesScheduledConcurrencyLimit() {
        let value = sut.concurrentJobsFor(.all)
        XCTAssertEqual(value, expectedScheduledConcurrency)
    }

    func testWhenOperationIsOptOut_thenUsesScheduledConcurrencyLimit() {
        let value = sut.concurrentJobsFor(.optOut)
        XCTAssertEqual(value, expectedScheduledConcurrency)
    }
}
