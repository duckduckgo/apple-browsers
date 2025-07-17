//
//  MockWindow.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import Foundation

@testable import DuckDuckGo_Privacy_Browser

class MockWindow: NSWindow {

    init(contentRect: NSRect = NSRect(x: 300, y: 300, width: 50, height: 50), styleMask: NSWindow.StyleMask = .titled, isVisible: Bool = true) {
        super.init(contentRect: contentRect, styleMask: styleMask, backing: .buffered, defer: false)
        self.isReleasedWhenClosed = false
        self._isVisible = isVisible
    }

    private var _isVisible: Bool = true
    private var _isKeyWindow: Bool = true
    private var _isMainWindow: Bool = true
    private var _occlusionState: NSWindow.OcclusionState = .visible
    private var _styleMask: NSWindow.StyleMask = .titled

    override var isVisible: Bool {
        get { _isVisible }
        set { _isVisible = newValue }
    }
    override var isKeyWindow: Bool {
        get { _isKeyWindow }
        set { _isKeyWindow = newValue }
    }
    override var isMainWindow: Bool {
        get { _isMainWindow }
        set { _isMainWindow = newValue }
    }
    override var occlusionState: NSWindow.OcclusionState {
        get { _occlusionState }
        set { _occlusionState = newValue }
    }
    override var styleMask: NSWindow.StyleMask {
        get { _styleMask }
        set { _styleMask = newValue }
    }

    var makeKeyAndOrderFrontCalled = false
    var beginSheetCalled = false

    override func orderFront(_ sender: Any?) {
    }

    override func orderFrontRegardless() {
    }

    override func makeKeyAndOrderFront(_ sender: Any?) {
    }

    override func beginSheet(_ sheetWindow: NSWindow, completionHandler handler: ((NSApplication.ModalResponse) -> Void)? = nil) {
        beginSheetCalled = true
        handler?(.continue)
    }

    override func toggleFullScreen(_ sender: Any?) {
        if styleMask.contains(.fullScreen) {
            styleMask.remove(.fullScreen)
        } else {
            styleMask.insert(.fullScreen)
        }
    }

    // window?.standardWindowButton(.closeButton)?.superview
    private var _standardWindowButton: NSButton?
    private var _toolbarView: NSView?

    private var toolbarView: NSView {
        if _toolbarView == nil {
            _toolbarView = NSView()
        }
        return _toolbarView!
    }

    override func standardWindowButton(_ b: NSWindow.ButtonType) -> NSButton? {
        if _standardWindowButton == nil {
            _standardWindowButton = NSButton()
            toolbarView.addSubview(_standardWindowButton!)
        }
        return _standardWindowButton!
    }

}
