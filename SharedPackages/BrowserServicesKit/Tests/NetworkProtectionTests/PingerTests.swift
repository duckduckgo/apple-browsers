//
//  PingerTests.swift
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

import Foundation
import Network
import XCTest
@testable import NetworkProtection

final class PingerTests: XCTestCase {

    func disabled_testPingValidIpShouldSucceed() async throws {
        let ip = IPv4Address("8.8.8.8")!
        let timeout = 3.0

        let pinger = Pinger(ip: ip, timeout: timeout)
        let r = try await pinger.ping().get()

        XCTAssertEqual(r.ip, ip)
        XCTAssertLessThan(20, r.bytesCount)
        XCTAssertEqual(r.seq, 0)
        XCTAssertLessThanOrEqual(r.time/1000, timeout)
        XCTAssertNotEqual(r.ttl, 0)
    }

    func disabled_testNonExistentIpShouldTimeout() async throws {
        let ip = IPv4Address("111.2.155.2")!
        let timeout = 0.2

        let e = expectation(description: "ready")
        do {
            let pinger = Pinger(ip: ip, timeout: timeout)
            _=try await pinger.ping().get()

            XCTFail("ping should fail")
        } catch Pinger.PingError.timeout(.select) {
            // pass
        } catch {
            XCTFail("error: \(error)")
        }
        e.fulfill()

        await fulfillment(of: [e], timeout: 5)
    }

}
