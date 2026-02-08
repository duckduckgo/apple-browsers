//
//  MainViewController+WKWebExtensionWindow.swift
//  DuckDuckGo
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

import UIKit
import WebKit

@available(iOS 18.4, *)
@MainActor
extension MainViewController: WKWebExtensionWindow {

    enum WebExtensionWindowError: Error {
        case notSupported
    }

    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] {
        return tabManager.model.tabs.compactMap { tab in
            tabManager.controller(for: tab)
        }
    }

    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
        return tabManager.current()
    }

    func windowType(for context: WKWebExtensionContext) -> WKWebExtension.WindowType {
        return .normal
    }

    func windowState(for context: WKWebExtensionContext) -> WKWebExtension.WindowState {
        return .normal
    }

    func setWindowState(_ state: WKWebExtension.WindowState, for context: WKWebExtensionContext) async throws {
        throw WebExtensionWindowError.notSupported
    }

    func isPrivate(for context: WKWebExtensionContext) -> Bool {
        return false
    }

    func screenFrame(for context: WKWebExtensionContext) -> CGRect {
        return view.window?.screen.bounds ?? UIScreen.main.bounds
    }

    func frame(for context: WKWebExtensionContext) -> CGRect {
        return view.window?.frame ?? view.frame
    }

    func setFrame(_ frame: CGRect, for context: WKWebExtensionContext) async throws {
        throw WebExtensionWindowError.notSupported
    }

    func focus(for context: WKWebExtensionContext) async throws {
        view.window?.makeKeyAndVisible()
    }

    func close(for context: WKWebExtensionContext) async throws {
        throw WebExtensionWindowError.notSupported
    }
}
