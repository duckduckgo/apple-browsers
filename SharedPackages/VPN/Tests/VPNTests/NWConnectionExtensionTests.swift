//
//  NWConnectionExtensionTests.swift
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

import Common
import Network
@testable import VPN
import XCTest

final class NWConnectionExtensionTests: XCTestCase {
    let endpoint = NWEndpoint.hostPort(host: .name("www.duckduckgo.com", nil), port: .https)

    func testWhenConnectionIsNotStartedStateUpdateStreamFinishes() async throws {
        let stateUpdateStream = NWConnection(to: endpoint, using: .tcp).stateUpdateStream

        let e = expectation(description: "stateUpdateStream finished")
        try await withTimeout(0.1) {
            for try await _ in stateUpdateStream {
                XCTFail("Unexpected state update")
            }
            e.fulfill()
        }

        await fulfillment(of: [e])
    }

    func testWhenConnectionIsStartedAndCancelledStateUpdateStreamReceivesStatesAndFinishes() async throws {
        let connection = NWConnection(to: endpoint, using: .tcp)
        let stateUpdateStream = connection.stateUpdateStream
        connection.start(queue: .main)

        let ePreparing = expectation(description: "connection is preparing")
        let eFinished = expectation(description: "stateUpdateStream finished")
        async let states = withTimeout(5) {
            var states = [NWConnection.State]()
            for try await state in stateUpdateStream {
                states.append(state)
                if case .preparing = state {
                    ePreparing.fulfill()
                }
            }
            eFinished.fulfill()

            return states
        }

        await fulfillment(of: [ePreparing])
        connection.cancel()

        await fulfillment(of: [eFinished])
        let result = try await states

        XCTAssertEqual(result.first, .preparing)
        XCTAssertEqual(result.last, .cancelled)
        XCTAssertFalse(Task.isCancelled)
    }

}
