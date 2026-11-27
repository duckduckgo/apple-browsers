//
//  UnifiedToggleInputPlacementTests.swift
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
import UIKit
@testable import DuckDuckGo

@MainActor
@Suite("Unified toggle input placement")
struct UnifiedToggleInputPlacementTests {

    private static let allRestingSurfaces: [UTIRestingSurface] = [.chrome, .newTabPage, .returningToNewTabPage]

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: allRestingSurfaces)
    func parksInTheHostedSlotWithoutASession(restingSurface: UTIRestingSurface) {
        let slot = NewTabPageInputSlotViewController()

        let placement = UnifiedToggleInputPlacement.resolve(slot: slot, isSessionActive: false, restingSurface: restingSurface)

        #expect(placement == .newTabPage(slot))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: allRestingSurfaces)
    func staysInTheChromeWithoutAHostedSlot(restingSurface: UTIRestingSurface) {
        let placement = UnifiedToggleInputPlacement.resolve(slot: nil, isSessionActive: false, restingSurface: restingSurface)

        #expect(placement == .chrome)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [true, false])
    func keepsTheCardWhileASessionReturnsToTheNewTabPage(hasSlot: Bool) {
        let slot = hasSlot ? NewTabPageInputSlotViewController() : nil

        let placement = UnifiedToggleInputPlacement.resolve(slot: slot, isSessionActive: true, restingSurface: .returningToNewTabPage)

        #expect(placement == .keepCurrent)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [UTIRestingSurface.chrome, .newTabPage])
    func activeSessionUsesTheChrome(restingSurface: UTIRestingSurface) {
        let placement = UnifiedToggleInputPlacement.resolve(slot: NewTabPageInputSlotViewController(),
                                                            isSessionActive: true,
                                                            restingSurface: restingSurface)

        #expect(placement == .chrome)
    }
}
