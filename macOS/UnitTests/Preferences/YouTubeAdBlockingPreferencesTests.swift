//
//  YouTubeAdBlockingPreferencesTests.swift
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

import Persistence
import PixelKit
import PixelKitTestingUtilities
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class YouTubeAdBlockingPreferencesTests: XCTestCase {

    private var defaults: UserDefaults!
    private var sut: YouTubeAdBlockingPreferences!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "\(type(of: self))")!
        defaults.removePersistentDomain(forName: "\(type(of: self))")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "\(type(of: self))")
        defaults = nil
        sut = nil
        super.tearDown()
    }

    private func makeSUT(pixelFiring: PixelFiring? = nil) -> YouTubeAdBlockingPreferences {
        YouTubeAdBlockingPreferences(
            settings: defaults.keyedStoring(),
            pixelFiring: pixelFiring
        )
    }

    // MARK: - Pixel Firing

    func testWhenEnablingAdBlockingThenEnabledPixelIsFired() {
        let pixelMock = PixelKitMock(expecting: [
            ExpectedFireCall(pixel: WebExtensionPixel.adBlockingExtensionEnabled, frequency: .dailyAndCount)
        ])
        sut = makeSUT(pixelFiring: pixelMock)

        sut.youTubeAdBlockingEnabled = true

        pixelMock.verifyExpectations(file: #file, line: #line)
    }

    func testWhenDisablingAdBlockingThenDisabledPixelIsFired() {
        let pixelMock = PixelKitMock(expecting: [
            ExpectedFireCall(pixel: WebExtensionPixel.adBlockingExtensionEnabled, frequency: .dailyAndCount),
            ExpectedFireCall(pixel: WebExtensionPixel.adBlockingExtensionDisabled, frequency: .dailyAndCount)
        ])
        sut = makeSUT(pixelFiring: pixelMock)

        sut.youTubeAdBlockingEnabled = true
        sut.youTubeAdBlockingEnabled = false

        pixelMock.verifyExpectations(file: #file, line: #line)
    }

    func testWhenSettingSameValueThenNoPixelIsFired() {
        let pixelMock = PixelKitMock(expecting: [
            ExpectedFireCall(pixel: WebExtensionPixel.adBlockingExtensionEnabled, frequency: .dailyAndCount)
        ])
        sut = makeSUT(pixelFiring: pixelMock)

        sut.youTubeAdBlockingEnabled = true
        sut.youTubeAdBlockingEnabled = true

        pixelMock.verifyExpectations(file: #file, line: #line)
    }

    func testWhenNoPixelFiringInjectedThenNoPixelIsFired() {
        sut = makeSUT(pixelFiring: nil)

        sut.youTubeAdBlockingEnabled = true
        sut.youTubeAdBlockingEnabled = false
    }
}
