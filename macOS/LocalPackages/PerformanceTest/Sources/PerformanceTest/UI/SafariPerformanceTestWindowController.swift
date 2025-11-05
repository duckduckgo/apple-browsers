//
//  SafariPerformanceTestWindowController.swift
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

/// Window controller for Safari performance testing
public class SafariPerformanceTestWindowController: NSWindowController {

    private var viewModel: SafariPerformanceTestViewModel?
    private var hostingController: NSHostingController<SafariPerformanceTestWindowView>?

    public convenience init(url: URL) {
        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: 600,
                height: 400
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Safari Performance Test"
        window.center()

        self.init(window: window)

        // Create view model with the URL
        let viewModel = SafariPerformanceTestViewModel()
        viewModel.currentURL = url
        self.viewModel = viewModel

        // Create the SwiftUI view
        let contentView = SafariPerformanceTestWindowView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: contentView)
        self.hostingController = hostingController

        window.contentViewController = hostingController
        window.setFrameAutosaveName("SafariPerformanceTestWindow")
    }

    deinit {
        if let viewModel = viewModel {
            Task { @MainActor in
                viewModel.cleanup()
            }
        }
    }
}
