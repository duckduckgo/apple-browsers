//
//  WKWebExtensionWindow.swift
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

import WebKit

@available(macOS 15.4, *)
@MainActor
extension MainWindowController: WKWebExtensionWindow {

    enum WebExtensionWindowError: Error {
        case notSupported
    }

    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] {
        return mainViewController.tabCollectionViewModel.tabs
    }

    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
        return mainViewController.tabCollectionViewModel.selectedTab
    }

    func windowType(for context: WKWebExtensionContext) -> WKWebExtension.WindowType {
        return .normal
    }

    func windowState(for context: WKWebExtensionContext) -> WKWebExtension.WindowState {
        return .normal
    }

    func setWindowState(_ state: WKWebExtension.WindowState, for context: WKWebExtensionContext) async throws {
        guard let window else {
            return
        }

        func isFullScreen(_ window: NSWindow) -> Bool {
            window.styleMask.contains(.fullScreen)
        }

        switch state {
        case .normal:
            if isFullScreen(window) { window.toggleFullScreen(nil) }
            if window.isMiniaturized { window.deminiaturize(nil) }
            if window.isZoomed { window.zoom(nil) }
            window.makeKeyAndOrderFront(nil)

        case .minimized:
            if !window.isMiniaturized {
                window.miniaturize(nil)
            }

        case .maximized:
            if isFullScreen(window) { window.toggleFullScreen(nil) }
            if window.isMiniaturized { window.deminiaturize(nil) }
            if !window.isZoomed {
                window.zoom(nil)
            } else if let vf = window.screen?.visibleFrame {
                window.setFrame(vf, display: true, animate: false)
            }
            window.makeKeyAndOrderFront(nil)

        case .fullscreen:
            if !isFullScreen(window) {
                window.toggleFullScreen(nil)
            }

        default:
            break
        }
    }

    func isPrivate(for context: WKWebExtensionContext) -> Bool {
        return mainViewController.isBurner
    }

    func screenFrame(for context: WKWebExtensionContext) -> CGRect {
        return window?.screen?.frame ?? CGRect.zero
    }

    func frame(for context: WKWebExtensionContext) -> CGRect {
        return window?.frame ?? CGRect.zero
    }

    func setFrame(_ frame: CGRect, for context: WKWebExtensionContext) async throws {
        window?.setFrame(frame, display: true)
    }

    func focus(for context: WKWebExtensionContext) async throws {
        window?.makeKeyAndOrderFront(nil)
    }

    func close(for context: WKWebExtensionContext) async throws {
        close()
    }
}
