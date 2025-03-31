//
//  UserScriptMessage.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

public protocol UserScriptMessage {
    var messageName: String { get }
    var messageBody: Any { get }
    var messageHost: String { get }
    var isMainFrame: Bool { get }
    var messageWebView: WKWebView? { get }
}

extension WKScriptMessage: UserScriptMessage {
    public var messageName: String {
        return name
    }

    public var messageBody: Any {
        return body
    }

    public var messageHost: String {
        return "\(frameInfo.securityOrigin.host)\(messagePort)"
    }

    public var messagePort: String {
        return frameInfo.securityOrigin.port == 0 ? "" : ":\(frameInfo.securityOrigin.port)"
    }

    public var isMainFrame: Bool {
        return frameInfo.isMainFrame
    }

    public var messageWebView: WKWebView? {
        return webView
    }
}
