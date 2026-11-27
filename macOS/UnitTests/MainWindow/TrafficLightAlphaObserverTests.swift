//
//  TrafficLightAlphaObserverTests.swift
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

import AppKit
import XCTest

@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class TrafficLightAlphaObserverTests: XCTestCase {

    private var window: NSWindow!

    override func setUp() async throws {
        try await super.setUp()

        window = makeWindow(styleMask: [.titled, .closable, .miniaturizable, .resizable])
    }

    override func tearDown() async throws {
        window = nil

        try await super.tearDown()
    }

    // MARK: - Before macOS 27

    func testWhenAlphaValueIsLowered_ThenItIsRestored() throws {
        try skipUnlessAlphaValueIsObserved()

        let observer = TrafficLightAlphaObserver(window: window)

        for button in trafficLights {
            button.alphaValue = 0

            XCTAssertEqual(button.alphaValue, 1, button.className)
        }

        withExtendedLifetime(observer) {}
    }

    // MARK: - macOS 27

    /// The observer relies on AppKit's private `buttonRevealAmount`, so this fails when a macOS release drops it.
    func testFrameViewRespondsToButtonRevealAmount() throws {
        try skipUnlessButtonRevealAmountIsObserved()

        let frameView = try XCTUnwrap(window.contentView?.superview)

        XCTAssertTrue(frameView.responds(to: TrafficLightAlphaObserver.buttonRevealAmountSelector), frameView.className)
    }

    func testWhenButtonRevealAmountIsLowered_ThenTrafficLightsAreRestored() throws {
        try skipUnlessButtonRevealAmountIsObserved()

        let frameView = try XCTUnwrap(window.contentView?.superview)
        let observer = TrafficLightAlphaObserver(window: window)

        XCTAssertEqual(trafficLights.count, 3)
        for buttonRevealAmount in [0, 0.5, 0] {
            frameView.setValue(buttonRevealAmount, forKey: TrafficLightAlphaObserver.buttonRevealAmountKey)

            XCTAssertEqual(self.buttonRevealAmount(of: frameView), 1)
            for button in trafficLights {
                XCTAssertEqual(button.alphaValue, 1, button.className)
            }
        }

        withExtendedLifetime(observer) {}
    }

    func testWhenObserverIsReleased_ThenButtonRevealAmountIsLeftAlone() throws {
        try skipUnlessButtonRevealAmountIsObserved()

        let frameView = try XCTUnwrap(window.contentView?.superview)
        var observer: TrafficLightAlphaObserver? = TrafficLightAlphaObserver(window: window)
        XCTAssertNotNil(observer)
        observer = nil

        frameView.setValue(0.5, forKey: TrafficLightAlphaObserver.buttonRevealAmountKey)

        XCTAssertEqual(buttonRevealAmount(of: frameView), 0.5)
    }

    /// A borderless window's frame view has no `buttonRevealAmount` to observe or to stop observing.
    func testWhenFrameViewHasNoButtonRevealAmount_ThenItIsLeftAlone() throws {
        try skipUnlessButtonRevealAmountIsObserved()

        let borderlessWindow = makeWindow(styleMask: [.borderless])
        let frameView = try XCTUnwrap(borderlessWindow.contentView?.superview)
        XCTAssertFalse(frameView.responds(to: TrafficLightAlphaObserver.buttonRevealAmountSelector), frameView.className)

        var observer: TrafficLightAlphaObserver? = TrafficLightAlphaObserver(window: borderlessWindow)
        XCTAssertNotNil(observer)
        observer = nil
    }
}

private extension TrafficLightAlphaObserverTests {

    var trafficLights: [NSButton] {
        let buttonTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        return buttonTypes.compactMap { window.standardWindowButton($0) }
    }

    func makeWindow(styleMask: NSWindow.StyleMask) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: styleMask, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        return window
    }

    func buttonRevealAmount(of frameView: NSView) -> Double? {
        frameView.value(forKey: TrafficLightAlphaObserver.buttonRevealAmountKey) as? Double
    }

    func skipUnlessButtonRevealAmountIsObserved() throws {
        guard #available(macOS 27, *) else {
            throw XCTSkip("Before macOS 27 the traffic lights are faded through alphaValue")
        }
    }

    func skipUnlessAlphaValueIsObserved() throws {
        if #available(macOS 27, *) {
            throw XCTSkip("macOS 27 fades the traffic lights through buttonRevealAmount")
        }
    }
}
