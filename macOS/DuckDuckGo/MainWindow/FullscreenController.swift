//
//  FullscreenController.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import WebKit

final class FullscreenController {

    // List of hosts where ESC doesn't exit fullscreen
    static var hosts = [
        "docs.google.com"
    ]

    private(set) var shouldPreventFullscreenExit: Bool = false

    func resetFullscreenExitFlag() {
        shouldPreventFullscreenExit = false
    }

    func handleEscapePress(host: String?) {
        if let host, Self.hosts.contains(host) {
            // Website is handling ESC. Stay in fullscreen.
            shouldPreventFullscreenExit = true
        }
    }

    func manuallyExitFullscreen(window: NSWindow?) {
        guard let window = window, window.styleMask.contains(.fullScreen) else {
            return
        }

        // Exit full screen
        window.toggleFullScreen(nil)
    }
}
