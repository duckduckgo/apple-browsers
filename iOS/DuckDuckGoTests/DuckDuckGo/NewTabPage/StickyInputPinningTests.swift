//
//  StickyInputPinningTests.swift
//  DuckDuckGo
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

import Testing
import CoreGraphics
@testable import DuckDuckGo

@available(iOS 16, macOS 13, *)
struct StickyInputPinningTests {

    private let pinning = StickyInputPinning(restingMinY: 100, height: 60, containerHeight: 1000)

    @Test("Input stays at rest while its resting position is below the pinned edge", .timeLimit(.minutes(1)))
    func restsWhileBelowPinnedEdge() {
        #expect(pinning.translation(pinnedMinY: 0) == 0)
        #expect(pinning.translation(pinnedMinY: 100) == 0)
    }

    @Test("Input follows the pinned edge once scrolling would carry it offscreen", .timeLimit(.minutes(1)))
    func followsPinnedEdge() {
        #expect(pinning.translation(pinnedMinY: 250) == 150)
    }

    @Test("Input stops at the bottom of its container", .timeLimit(.minutes(1)))
    func stopsAtContainerBottom() {
        #expect(pinning.translation(pinnedMinY: 5000) == 840)
    }

    @Test("Input does not move when the container is shorter than the input's resting bottom edge", .timeLimit(.minutes(1)))
    func shortContainerDoesNotMoveInput() {
        let shortContainer = StickyInputPinning(restingMinY: 100, height: 60, containerHeight: 120)
        #expect(shortContainer.translation(pinnedMinY: 500) == 0)
    }
}
