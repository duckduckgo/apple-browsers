//
//  MainWindow.swift
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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

import Cocoa

final class MainWindow: NSWindow {

    static let minWindowWidth: CGFloat = 600
    static let firstResponderDidChangeNotification = Notification.Name("firstResponderDidChange")

    override var canBecomeKey: Bool {
        return true
    }

    override var canBecomeMain: Bool {
        return true
    }

    override var frameAutosaveName: NSWindow.FrameAutosaveName {
        return "MainWindow"
    }

    override func setFrameAutosaveName(_ name: NSWindow.FrameAutosaveName) -> Bool {
        return super.setFrameAutosaveName(self.frameAutosaveName)
    }

    init(frame: NSRect) {
        super.init(contentRect: frame,
                   styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                   backing: .buffered,
                   defer: true)

        setupWindow()
    }

    // To avoid beep sounds, this keyDown method catches events that go through the
    // responder chain when no other responders process it
    override func keyDown(with event: NSEvent) {
        if event.keyEquivalent == [.command, "f"] {
            // beep on Cmd+F when Find In Page is unavailable
            super.keyDown(with: event)
            return
        }
        super.performKeyEquivalent(with: event)
    }

    private func setupWindow() {
        allowsToolTipsWhenApplicationIsInactive = false
        autorecalculatesKeyViewLoop = false
        isReleasedWhenClosed = false
        animationBehavior = .documentWindow
        hasShadow = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        collectionBehavior = .fullScreenPrimary

        // Setting minimum width to fit the wide NTP search bar
        minSize = .init(width: Self.minWindowWidth, height: 0)
    }

    // MARK: - First Responder Notification

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        // The only reliable way to detect NSTextField is the first responder
        defer {
            // Send it after the first responder has been set on the super class so that window.firstResponder matches correctly
            NotificationCenter.default.post(name: MainWindow.firstResponderDidChangeNotification, object: self)
        }
        return super.makeFirstResponder(responder)
    }

    override func endEditing(for object: Any?) {
        if case .leftMouseUp = NSApp.currentEvent?.type,
           object is AddressBarTextEditor {
            // prevent deactivation of Address Bar on Toolbar click
            return
        }

        super.endEditing(for: object)
    }

    // used to observe childWindows property
    override func addChildWindow(_ childWin: NSWindow, ordered place: NSWindow.OrderingMode) {
        willChangeValue(forKey: "childWindows")
        super.addChildWindow(childWin, ordered: place)
        didChangeValue(forKey: "childWindows")
    }

    override func removeChildWindow(_ childWin: NSWindow) {
        willChangeValue(forKey: "childWindows")
        super.removeChildWindow(childWin)
        didChangeValue(forKey: "childWindows")
    }

}
