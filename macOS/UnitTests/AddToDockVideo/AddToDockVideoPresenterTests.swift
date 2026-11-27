//
//  AddToDockVideoPresenterTests.swift
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
@_spi(Testing) import PixelKit
import Testing

@testable import DuckDuckGo_Privacy_Browser

@MainActor
@Suite("Add to Dock Video Presenter Tests")
final class AddToDockVideoPresenterTests {

    private let pixelFiring = PixelKitMock()
    private let window = SheetRecordingWindow()

    private func makeSUT(window: NSWindow?, newWindow: NSWindow? = nil) -> AddToDockVideoPresenter {
        AddToDockVideoPresenter(windowProvider: { window }, newWindowProvider: { newWindow }, pixelFiring: pixelFiring)
    }

    @available(macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func presentingWithNoWindowShowsSheetInNewWindow() {
        let sut = makeSUT(window: nil, newWindow: window)

        let didPresent = sut.present(from: .mainMenu, primaryAction: .done) { _ in }

        #expect(didPresent)
        #expect(window.presentedSheets.count == 1)
    }

    @available(macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func presentingWhenNoWindowCanBeOpenedDoesNothing() {
        let sut = makeSUT(window: nil)
        var receivedActions: [AddToDockVideoAction] = []

        let didPresent = sut.present(from: .mainMenu, primaryAction: .done) { receivedActions.append($0) }
        sut.handle(.done)

        #expect(!didPresent)
        #expect(receivedActions.isEmpty)
        #expect(pixelFiring.actualFireCalls.isEmpty)
    }

    @available(macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [AddToDockVideoAction.done, .next, .cancel])
    func reportsChosenActionAndEndsSheet(action: AddToDockVideoAction) {
        let sut = makeSUT(window: window)
        var receivedActions: [AddToDockVideoAction] = []

        let entryPoint: AddToDockVideoEntryPoint = action == .done ? .mainMenu : .popover
        sut.present(from: entryPoint, primaryAction: action == .done ? .done : .next) { receivedActions.append($0) }
        sut.handle(action)

        #expect(receivedActions == [action])
        #expect(window.presentedSheets.count == 1)
        #expect(window.endedSheets == window.presentedSheets)
        #expect(pixelFiring.actualFireCalls == [
            ExpectedFireCall(pixel: AddToDockVideoPixel.buttonClicked(action: action, entryPoint: entryPoint), frequency: .standard)
        ])
    }

    @available(macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func secondPresentWhileShowingIsIgnored() {
        let sut = makeSUT(window: window)
        var firstActions: [AddToDockVideoAction] = []
        var secondActions: [AddToDockVideoAction] = []

        let firstDidPresent = sut.present(from: .mainMenu, primaryAction: .done) { firstActions.append($0) }
        let secondDidPresent = sut.present(from: .popover, primaryAction: .next) { secondActions.append($0) }

        #expect(firstDidPresent)
        #expect(!secondDidPresent)
        #expect(window.presentedSheets.count == 1)

        sut.handle(.done)

        #expect(firstActions == [.done])
        #expect(secondActions.isEmpty)
        #expect(pixelFiring.actualFireCalls == [
            ExpectedFireCall(pixel: AddToDockVideoPixel.buttonClicked(action: .done, entryPoint: .mainMenu), frequency: .standard)
        ])
    }
}

private final class SheetRecordingWindow: NSWindow {
    private(set) var presentedSheets: [NSWindow] = []
    private(set) var endedSheets: [NSWindow] = []

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 50, height: 50), styleMask: .titled, backing: .buffered, defer: true)
        isReleasedWhenClosed = false
    }

    override func beginSheet(_ sheetWindow: NSWindow, completionHandler handler: ((NSApplication.ModalResponse) -> Void)? = nil) {
        presentedSheets.append(sheetWindow)
    }

    override func endSheet(_ sheetWindow: NSWindow) {
        endedSheets.append(sheetWindow)
    }
}
