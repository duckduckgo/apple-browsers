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

    func testWhenOperationIsManualScans_thenConcurrentJobsBetweenBrokersIsSix() {
        let value = sut.concurrentJobsFor(.manualScan)
        let expectedValue = 6
        XCTAssertEqual(value, expectedValue)
    }

    func testWhenOperationIsScheduledScans_thenConcurrentJobsBetweenBrokersIsTwo() {
        let value = sut.concurrentJobsFor(.scheduledScan)
        let expectedValue = 2
        XCTAssertEqual(value, expectedValue)
    }

    func testWhenOperationIsAll_thenConcurrentJobsBetweenBrokersIsTwo() {
        let value = sut.concurrentJobsFor(.all)
        let expectedValue = 2
        XCTAssertEqual(value, expectedValue)
    }

    func testWhenOperationIsOptOut_thenConcurrentJobsBetweenBrokersIsTwo() {
        let value = sut.concurrentJobsFor(.optOut)
        let expectedValue = 2
        XCTAssertEqual(value, expectedValue)
    }
}
