//
//  BrowserToolsWireTypes.swift
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

// MARK: - Tab change hint

/// Params of the `aiChatTabChanged` push: metadata only, never page content.
public struct AIChatTabChangedData: Encodable, Equatable, Sendable {
    public let tabId: String
    public let change: String
    public let url: String?
    public let title: String?
    public let isAttachable: Bool?

    public init(tabId: String, url: String?, isAttachable: Bool?) {
        self.tabId = tabId
        self.change = "navigated"
        self.url = url
        self.title = nil
        self.isAttachable = isAttachable
    }
}

// MARK: - Failures

/// Failures reported by native tool execution.
public enum BrowserToolFailure: String, Equatable, Sendable, CaseIterable {

    /// Arguments did not satisfy the tool's input schema.
    case invalidArguments = "invalid_arguments"

    /// The referenced target existed as an identifier but could not be resolved — e.g. a tab id
    /// that names no open tab, or one in another window.
    case notFound = "not_found"

    /// Feature or sub-feature off, tool unknown, or a Fire window — deliberately indistinguishable.
    case unavailable

    /// The user refused, now or by a stored decision.
    case denied

    /// The permission prompt was dismissed, timed out, or could not be delivered.
    case cancelled
}
