//
//  HandshakeAttemptBudgetTests.swift
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
import XCTest
@testable import DuckWireGuard

final class HandshakeAttemptBudgetTests: XCTestCase {
    func testInitialBurstAllowsEightAttemptsWithoutRefillingAtTheSameTime() throws {
        var budget = HandshakeAttemptBudget()
        try consumeBurst(&budget, at: 0)
        assertLimited(&budget, at: 0)
        assertLimited(&budget, at: 0)
    }

    func testOneAttemptRefillsAtTheTwentyMillisecondBoundary() throws {
        var budget = HandshakeAttemptBudget()
        try consumeBurst(&budget, at: 0)
        assertLimited(&budget, at: 0.019999)
        try budget.consume(at: 0.02)
        assertLimited(&budget, at: 0.02)
    }

    func testFractionalCreditAccumulatesAcrossRejectedAttemptsAndSuccessfulConsumption() throws {
        var budget = HandshakeAttemptBudget()
        try consumeBurst(&budget, at: 0)
        // Binary-exact times keep these assertions independent of timestamp rounding.
        assertLimited(&budget, at: 1.0 / 128)
        assertLimited(&budget, at: 1.0 / 64)
        try budget.consume(at: 1.0 / 32)
        assertLimited(&budget, at: 5.0 / 128)
        try budget.consume(at: 3.0 / 64)
        assertLimited(&budget, at: 3.0 / 64)
    }

    func testLongPauseRefillsAnExhaustedBudgetWithOnlyOneBurst() throws {
        var budget = HandshakeAttemptBudget()
        try consumeBurst(&budget, at: 0)
        try consumeBurst(&budget, at: 1_000_000)
        assertLimited(&budget, at: 1_000_000)
    }

    func testIdleCreditCannotAccumulateBeyondCapacityWhenTokensRemain() throws {
        var budget = HandshakeAttemptBudget()
        try budget.consume(at: 0)
        try consumeBurst(&budget, at: 1_000_000)
        assertLimited(&budget, at: 1_000_000)
    }

    func testBackwardTimeCannotGrantCreditOrMoveTheRefillWatermarkBack() throws {
        var budget = HandshakeAttemptBudget()
        try consumeBurst(&budget, at: 1)
        assertLimited(&budget, at: 0.5)
        assertLimited(&budget, at: 1 + 1.0 / 64)
        try budget.consume(at: 1 + 1.0 / 32)
        assertLimited(&budget, at: 1 + 1.0 / 32)
        try budget.consume(at: 1 + 3.0 / 64)
    }

    private func consumeBurst(_ budget: inout HandshakeAttemptBudget, at time: TimeInterval) throws {
        for _ in 0..<8 { try budget.consume(at: time) }
    }

    private func assertLimited(_ budget: inout HandshakeAttemptBudget, at time: TimeInterval,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try budget.consume(at: time), file: file, line: line) { error in
            XCTAssertEqual(error as? WireGuardPeer.Error, .handshakeRateLimited, file: file, line: line)
        }
    }
}
