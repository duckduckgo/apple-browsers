//
//  ReplayWindowTests.swift
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
@testable import DuckWireGuard

final class ReplayWindowTests: XCTestCase {
    func testReplayWindowAcceptsReorderingAndRejectsItsLowerBoundary() {
        let window = WireGuardPeer.ReplayWindow()
        XCTAssertTrue(window.accept(9000))
        XCTAssertTrue(window.accept(8999))
        XCTAssertTrue(window.accept(872), "Distance 8128 is inclusive")
        XCTAssertFalse(window.accept(871))
        XCTAssertFalse(window.accept(872))
        XCTAssertFalse(window.accept(8999))
        XCTAssertTrue(window.accept(9001))
    }

    func testReplayBoundaryMatchesGoAtEveryWordAlignment() {
        let window = WireGuardPeer.ReplayWindow()
        for offset in UInt64(0)..<64 {
            // Each jump clears the full ring, while the low six bits cover every word alignment.
            let highest = 16_384 + offset * 16_385
            XCTAssertTrue(window.accept(highest))
            XCTAssertTrue(window.accept(highest - 8128), "alignment \(offset)")
            XCTAssertFalse(window.accept(highest - 8129))
            XCTAssertFalse(window.accept(highest - 8128))
        }
    }

    func testReplayBitmapReusesWordsAcrossFullRingWraps() {
        let window = WireGuardPeer.ReplayWindow()
        for highest in [UInt64(8192), 16_384, 24_576] {
            XCTAssertTrue(window.accept(highest))
            XCTAssertTrue(window.accept(highest - 8128))
            XCTAssertFalse(window.accept(highest - 8129))
            XCTAssertFalse(window.accept(highest))
            XCTAssertFalse(window.accept(highest - 8128))
        }
    }

    func testReplayWindowMatchesReferenceAcrossWrapsReorderingAndLargeJumps() {
        let window = WireGuardPeer.ReplayWindow()
        var counters: [UInt64] = [
            0, 63, 64, 65, 0, 63, 127, 128, 8127, 0, 8128, 0, 8129, 1, 0,
            8191, 63, 8192, 64, 63, 8193, 65, 8256, 128, 8191, 16_383, 8255, 16_384, 8256
        ]
        var head: UInt64 = 16_384
        var seed: UInt64 = 0x82a2b175229d6a5b
        let jumps: [UInt64] = [8127, 8128, 8129, 8191, 8192, 8193, 16_384]
        for _ in 0..<4096 {
            seed = seed &* 6364136223846793005 &+ 1
            if seed & 3 < 2 {
                head += seed & 0x100 == 0 ? (seed >> 16) % 97 + 1 : jumps[Int((seed >> 16) % UInt64(jumps.count))]
                counters.append(head)
            } else {
                let distance = (seed >> 16) % 16_385
                counters.append(head >= distance ? head - distance : 0)
            }
        }
        let lastAccepted = UInt64.max - 8193
        counters += [lastAccepted, lastAccepted - 8128, lastAccepted - 8129, lastAccepted, lastAccepted - 1]
        var highest: UInt64 = 0
        // Independent set model of Go's inclusive distance limit; no ring/word operations.
        var seen = Set<UInt64>()
        for counter in counters {
            let expected = !seen.contains(counter) && (counter > highest || highest - counter <= 8128)
            if expected {
                highest = max(highest, counter)
                seen = seen.filter { highest - $0 <= 8128 }
                seen.insert(counter)
            }
            XCTAssertEqual(window.accept(counter), expected, "counter \(counter)")
        }
    }
}
