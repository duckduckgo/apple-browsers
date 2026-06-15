//
//  OrphanProxyBucketTests.swift
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

import Foundation
@testable import NetworkProtectionProxy
import XCTest

final class OrphanProxyBucketTests: XCTestCase {

    private let now = Date()

    private func heartbeatBucket(ageSeconds: TimeInterval?) -> TransparentProxyProvider.HeartbeatAgeBucket {
        let date = ageSeconds.map { now.addingTimeInterval(-$0) }
        return TransparentProxyProvider.HeartbeatAgeBucket.bucket(for: date, now: now)
    }

    func testHeartbeatBuckets() {
        XCTAssertEqual(heartbeatBucket(ageSeconds: nil), .missing)
        XCTAssertEqual(heartbeatBucket(ageSeconds: 299), .under5m)
        XCTAssertEqual(heartbeatBucket(ageSeconds: 300), .under30m)
        XCTAssertEqual(heartbeatBucket(ageSeconds: 1799), .under30m)
        XCTAssertEqual(heartbeatBucket(ageSeconds: 1800), .over30m)
    }

    func testProxyBuckets() {
        XCTAssertEqual(TransparentProxyProvider.ProxyAgeBucket.bucket(for: 299), .under5m)
        XCTAssertEqual(TransparentProxyProvider.ProxyAgeBucket.bucket(for: 300), .under30m)
        XCTAssertEqual(TransparentProxyProvider.ProxyAgeBucket.bucket(for: 1799), .under30m)
        XCTAssertEqual(TransparentProxyProvider.ProxyAgeBucket.bucket(for: 1800), .under2h)
        XCTAssertEqual(TransparentProxyProvider.ProxyAgeBucket.bucket(for: 7199), .under2h)
        XCTAssertEqual(TransparentProxyProvider.ProxyAgeBucket.bucket(for: 7200), .over2h)
    }
}
