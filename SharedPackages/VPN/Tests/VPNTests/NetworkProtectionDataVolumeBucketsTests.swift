//
//  NetworkProtectionDataVolumeBucketsTests.swift
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
@testable import VPN

final class NetworkProtectionDataVolumeBucketsTests: XCTestCase {

    func testBucketsZeroAndNegativeValues() {
        let dataVolume = NetworkProtectionDataVolumeBuckets(bytesSent: 0, bytesReceived: -1)

        XCTAssertEqual(dataVolume.bytesSentBucket, "0")
        XCTAssertEqual(dataVolume.bytesReceivedBucket, "0")
    }

    func testBucketsSmallValuesUnderTenMiB() {
        let dataVolume = NetworkProtectionDataVolumeBuckets(bytesSent: 1, bytesReceived: 10_485_759)

        XCTAssertEqual(dataVolume.bytesSentBucket, "<10 MiB")
        XCTAssertEqual(dataVolume.bytesReceivedBucket, "<10 MiB")
    }

    func testBucketsMediumValuesFromTenToOneHundredMiB() {
        let dataVolume = NetworkProtectionDataVolumeBuckets(bytesSent: 10_485_760, bytesReceived: 104_857_599)

        XCTAssertEqual(dataVolume.bytesSentBucket, "10-100 MiB")
        XCTAssertEqual(dataVolume.bytesReceivedBucket, "10-100 MiB")
    }

    func testBucketsValuesAtLeastOneHundredMiB() {
        let dataVolume = NetworkProtectionDataVolumeBuckets(bytesSent: 104_857_600, bytesReceived: 1_073_741_823)

        XCTAssertEqual(dataVolume.bytesSentBucket, "100 MiB+")
        XCTAssertEqual(dataVolume.bytesReceivedBucket, "100 MiB+")
    }
}
