//
//  BrowserToolsDebugPanel.swift
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

#if DEBUG || REVIEW

import AppKit

/// The browser tools debug panel as a standalone window. Its owner tab is whichever tab is
/// selected in the key window; the sidebar mode pins it to the host tab instead.
@MainActor
final class BrowserToolsDebugPanel: NSWindowController {

    init(windowControllersManager: WindowControllersManagerProtocol) {
        let controller = BrowserToolsDebugViewController(windowControllersManager: windowControllersManager) {
            windowControllersManager.lastKeyMainWindowController?.mainViewController.tabCollectionViewModel.selectedTab
        }
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .resizable]
        window.title = "Duck.ai Browser Tools"
        window.setContentSize(NSSize(width: 780, height: 560))
        super.init(window: window)
        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

#endif
