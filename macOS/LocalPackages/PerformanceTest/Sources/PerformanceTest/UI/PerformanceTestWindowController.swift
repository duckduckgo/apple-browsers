//
//  PerformanceTestWindowController.swift
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
import SwiftUI
import WebKit

/// Window controller for performance testing - handles everything internally
public class PerformanceTestWindowController: NSWindowController {

    private var viewModel: PerformanceTestViewModel?
    private var hostingController: NSHostingController<PerformanceTestWindowView>?

    public convenience init(
        webView: WKWebView,
        createNewTab: (() async -> WKWebView?)? = nil,
        closeTab: (() async -> Void)? = nil
    ) {
        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: PerformanceTestConstants.windowWidth,
                height: PerformanceTestConstants.windowHeight
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = PerformanceTestConstants.windowTitle
        window.center()

        self.init(window: window)

        // Create view model with the webView and tab lifecycle callbacks
        let viewModel = PerformanceTestViewModel(
            webView: webView,
            createNewTab: createNewTab,
            closeTab: closeTab
        )
        self.viewModel = viewModel

        // Create the SwiftUI view
        let contentView = PerformanceTestWindowView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: contentView)
        self.hostingController = hostingController

        window.contentViewController = hostingController
        window.setFrameAutosaveName(PerformanceTestConstants.windowAutosaveName)
    }
}
