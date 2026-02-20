//
//  MockUserScriptMessage.swift
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

import UserScript
import WebKit

/// A mock implementation of `UserScriptMessage` for testing.
/// Use this instead of instantiating `WKScriptMessage` directly, which can cause crashes.
public struct MockUserScriptMessage: UserScriptMessage {
    public var messageName: String
    public var messageBody: Any
    public var messageHost: String
    public var messageWebView: WKWebView?
    public var isMainFrame: Bool

    public init(
        name: String = "",
        body: Any = [:],
        host: String = "",
        webView: WKWebView? = nil,
        isMainFrame: Bool = true
    ) {
        self.messageName = name
        self.messageBody = body
        self.messageHost = host
        self.messageWebView = webView
        self.isMainFrame = isMainFrame
    }
}
