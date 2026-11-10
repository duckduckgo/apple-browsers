//
//  DataBrokerProtectionDebugWebViews.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import Foundation
import WebKit

/// The PIR web views that are alive, so the debug server can inspect them while jobs run.
@MainActor
public final class DataBrokerProtectionDebugWebViews {

    public static let shared = DataBrokerProtectionDebugWebViews()

    public struct Entry {
        public let id: Int
        public let brokerURL: String?
        public let createdAt: Date
        public weak var webView: WKWebView?
    }

    private var entries: [Entry] = []
    private var nextID = 1

    public var live: [Entry] {
        entries.removeAll { $0.webView == nil }
        return entries
    }

    public func entry(id: Int) -> Entry? {
        live.first { $0.id == id }
    }

    func register(_ webView: WKWebView, brokerURL: String?) {
        entries.append(Entry(id: nextID, brokerURL: brokerURL, createdAt: Date(), webView: webView))
        nextID += 1
    }
}
