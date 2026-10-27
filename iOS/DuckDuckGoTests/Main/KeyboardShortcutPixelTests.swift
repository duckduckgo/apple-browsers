//
//  KeyboardShortcutPixelTests.swift
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
@testable import DuckDuckGo
@_spi(Testing) import PixelKit

@Suite("Keyboard Shortcut Pixel Tests")
struct KeyboardShortcutPixelTests {

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func fireUsed_firesDailyAndCountWithoutParameters() {
        let pixelFiring = PixelKitMock()

        KeyboardShortcutPixel.fireUsed(with: pixelFiring)

        #expect(pixelFiring.actualFireCalls == [ExpectedFireCall(pixel: KeyboardShortcutPixel.used, frequency: .dailyAndCount)])
        #expect(pixelFiring.actualFireCalls.first?.pixel.name == "keyboard-shortcut_used")
        #expect(pixelFiring.actualFireCalls.first?.pixel.parameters == nil)
        #expect(pixelFiring.actualFireCalls.first?.pixel.standardParameters == nil)
    }
}
