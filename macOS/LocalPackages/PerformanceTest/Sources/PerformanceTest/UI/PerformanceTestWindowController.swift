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

/// Stub implementation for Performance Test Window Controller
/// Full implementation will be added in PR 2
public final class PerformanceTestWindowController: NSWindowController {

    public convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Performance Test"
        window.center()

        self.init(window: window)

        // Placeholder view
        let placeholderView = NSHostingView(rootView: PlaceholderView())
        window.contentView = placeholderView
    }

    public override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct PlaceholderView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("Performance Test Tool")
                .font(.largeTitle)
                .padding()

            Text("Full UI implementation coming in next PR")
                .font(.headline)
                .foregroundColor(.secondary)

            Spacer()
        }
        .frame(minWidth: 600, minHeight: 400)
        .padding()
    }
}