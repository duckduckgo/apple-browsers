//
//  WebExtensionWindowTabProvidingMock.swift
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

import WebKit
@testable import WebExtensions

@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class WebExtensionWindowTabProvidingMock: WebExtensionWindowTabProviding {

    var openWindowsCalled = false
    var openWindowsResult: [any WKWebExtensionWindow] = []
    func openWindows(for context: WKWebExtensionContext) -> [any WKWebExtensionWindow] {
        openWindowsCalled = true
        return openWindowsResult
    }

    var focusedWindowCalled = false
    var focusedWindowResult: (any WKWebExtensionWindow)?
    func focusedWindow(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        focusedWindowCalled = true
        return focusedWindowResult
    }

    var openNewWindowCalled = false
    var openNewWindowResult: (any WKWebExtensionWindow)?
    func openNewWindow(using configuration: WKWebExtension.WindowConfiguration,
                       for context: WKWebExtensionContext) async throws -> (any WKWebExtensionWindow)? {
        openNewWindowCalled = true
        return openNewWindowResult
    }

    var openNewTabCalled = false
    var openNewTabResult: (any WKWebExtensionTab)?
    func openNewTab(using configuration: WKWebExtension.TabConfiguration,
                    for context: WKWebExtensionContext) async throws -> (any WKWebExtensionTab)? {
        openNewTabCalled = true
        return openNewTabResult
    }

    var presentPopupCalled = false
    func presentPopup(_ action: WKWebExtension.Action,
                      for context: WKWebExtensionContext) async throws {
        presentPopupCalled = true
    }
}
