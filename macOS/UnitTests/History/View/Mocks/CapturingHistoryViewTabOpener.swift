//
//  CapturingHistoryViewTabOpener.swift
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

import AppKit
import Foundation

@testable import DuckDuckGo_Privacy_Browser

final class CapturingHistoryViewTabOpener: HistoryViewTabOpening {
    var dialogPresenter: HistoryViewDialogPresenting?

    func open(_ url: URL, window: NSWindow?) async {
        openCalls.append(url)
    }

    func openInNewTab(_ urls: [URL], sourceWindow: NSWindow?) async {
        openInNewTabCalls.append(urls)
    }

    func openInNewWindow(_ urls: [URL], sourceWindow: NSWindow?) async {
        openInNewWindowCalls.append(urls)
    }

    func openInNewFireWindow(_ urls: [URL], sourceWindow: NSWindow?) async {
        openInNewFireWindowCalls.append(urls)
    }

    var openCalls: [URL] = []
    var openInNewTabCalls: [[URL]] = []
    var openInNewWindowCalls: [[URL]] = []
    var openInNewFireWindowCalls: [[URL]] = []
}
