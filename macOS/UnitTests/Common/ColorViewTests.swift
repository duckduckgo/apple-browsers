//
//  ColorViewTests.swift
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
final class ColorViewTests: XCTestCase {

    private var windows: [NSWindow] = []

    override func tearDown() {
        windows.forEach { $0.close() }
        windows = []
        super.tearDown()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        windows.append(window)
        return window
    }

    func testWhenMovedToAnotherWindowAndRedisplayedThenLayerBackgroundColorIsRestored() {
        let sourceWindow = makeWindow()
        let destinationWindow = makeWindow()
        let sut = ColorView(frame: NSRect(x: 0, y: 0, width: 50, height: 20), backgroundColor: .red)
        sourceWindow.contentView!.addSubview(sut)

        // Simulate AppKit reparenting the view into another window (as with the full screen
        // toolbar window) and the view's layer losing its background color along the way.
        sut.removeFromSuperview()
        destinationWindow.contentView!.addSubview(sut)
        sut.layer?.backgroundColor = nil

        sut.needsDisplay = true
        sut.displayIfNeeded()

        XCTAssertEqual(sut.layer?.backgroundColor, NSColor.red.cgColor)
    }

    func testWhenEffectiveAppearanceChangesThenDynamicBackgroundColorIsResolvedAgain() {
        let window = makeWindow()
        let dynamicColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .black : .white
        }
        let sut = ColorView(frame: NSRect(x: 0, y: 0, width: 50, height: 20))
        sut.resolvesStyleWithEffectiveAppearance = true
        sut.appearance = NSAppearance(named: .aqua)
        window.contentView!.addSubview(sut)
        sut.backgroundColor = dynamicColor
        XCTAssertEqual(sut.layer?.backgroundColor, NSColor.white.cgColor)

        sut.appearance = NSAppearance(named: .darkAqua)
        sut.displayIfNeeded()

        XCTAssertEqual(sut.layer?.backgroundColor, NSColor.black.cgColor)
    }
}
