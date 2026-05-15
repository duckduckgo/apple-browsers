//
//  AIChatConsumableDataHandling.swift
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

import Foundation

/// A protocol that defines a standard interface for handling consumable data.
/// Types conforming to this protocol can set, consume, and reset data of a specified type.
public protocol AIChatConsumableDataHandling {
    /// The type of data that the conforming type will handle.
    associatedtype DataType

    /// Sets the data to be handled.
    ///
    /// - Parameter data: The data to be set.
    func setData(_ data: DataType)

    /// Consumes the current data and returns it.
    ///
    /// - Returns: The current data if available, otherwise `nil`.
    func consumeData() -> DataType?

    /// Resets the current data, clearing any stored value.
    func reset()
}

/// Handles prompt data for AI chat interactions.
public final class AIChatPromptHandler: AIChatConsumableDataHandling {
    public typealias DataType = AIChatNativePrompt
    private var data: DataType?

    public static let shared = AIChatPromptHandler()

    private init() {}

    public func setData(_ data: DataType) {
        self.data = data
    }

    public func consumeData() -> DataType? {
        let currentData = data
        reset()
        return currentData
    }

    public func reset() {
        self.data = nil
    }
}

/// Handles payload data for AI chat interactions, typically set by the SERP.
public final class AIChatPayloadHandler: AIChatConsumableDataHandling {
    public typealias DataType = AIChatPayload
    private var data: DataType?

    public init() {}

    public func setData(_ data: DataType) {
        self.data = data
    }

    public func consumeData() -> DataType? {
        let currentData = data
        reset()
        return currentData
    }

    public func reset() {
        self.data = nil
    }
}

/// The payload is configured by the SERP to facilitate data transfer to duck.ai.
/// For instance, when a user searches for "bread recipe" and clicks the chat button, the SERP sets this payload.
/// The payload is then consumed when duck.ai is initialized, allowing for seamless data integration.
public typealias AIChatPayload = [String: Any]

/// Handles serialized restoration data for AI chat
public final class AIChatRestorationDataHandler: AIChatConsumableDataHandling {
    public typealias DataType = AIChatRestorationData
    private var data: DataType?

    public init() {}

    public func setData(_ data: DataType) {
        self.data = data
    }

    public func consumeData() -> DataType? {
        let currentData = data
        reset()
        return currentData
    }

    public func reset() {
        self.data = nil
    }
}

public typealias AIChatRestorationData = String

/// Handles page context data for AI Chat
public final class AIChatPageContextHandler: AIChatConsumableDataHandling {
    public typealias DataType = AIChatPageContextData
    private var data: DataType?

    public init() {}

    public func setData(_ data: DataType) {
        self.data = data
    }

    public func consumeData() -> DataType? {
        let currentData = data
        reset()
        return currentData
    }

    public func reset() {
        self.data = nil
    }
}

public struct AIChatPageContextData: Codable, Equatable {
    public let title: String
    public let favicon: [PageContextFavicon]
    public let url: String
    public let content: String
    public let truncated: Bool
    public let fullContentLength: Int
    public let attachable: Bool?
    /// Discriminator for the duck.ai web app: presence marks a tab-picker context (e.g.
    /// picked via the sidebar `@` picker or the omnibar's "Add Page Content" menu); absence
    /// marks the current sidebar page. The omnibar strips this for the entry that matches
    /// the active tab so the discriminator's semantics hold end-to-end.
    public let tabId: String?

    public init(title: String, favicon: [PageContextFavicon], url: String, content: String, truncated: Bool, fullContentLength: Int, attachable: Bool? = nil, tabId: String? = nil) {
        self.title = title
        self.favicon = favicon
        self.url = url
        self.content = content
        self.truncated = truncated
        self.fullContentLength = fullContentLength
        self.attachable = attachable
        self.tabId = tabId
    }

    /// Returns a copy of this page context with the `tabId` field set to the given value.
    /// Used at extraction time to stamp the originating tab id, and at omnibar submit time
    /// to strip the id for the entry that matches the active tab.
    public func withTabId(_ tabId: String?) -> AIChatPageContextData {
        AIChatPageContextData(
            title: title,
            favicon: favicon,
            url: url,
            content: content,
            truncated: truncated,
            fullContentLength: fullContentLength,
            attachable: attachable,
            tabId: tabId
        )
    }

    public struct PageContextFavicon: Codable, Equatable {
        public let href: String
        public let rel: String

        public init(href: String, rel: String) {
            self.href = href
            self.rel = rel
        }
    }

    /// Returns `true` if this page context contains no usable data for AI Chat.
    ///
    /// A page context is considered empty when it has no title, no favicon, no content,
    /// and the full content length is zero. Note that `url` is intentionally excluded
    /// from this check.
    public func isEmpty() -> Bool {
        return title.isEmpty && favicon.isEmpty && content.isEmpty && fullContentLength == 0
    }
}

// MARK: - Tab Picker Types

/// Metadata for a single open browser tab, returned by `getAIChatOpenTabs`.
public struct AIChatTabMetadata: Codable {
    public let tabId: String
    public let title: String
    public let url: String
    public let favicon: [AIChatPageContextData.PageContextFavicon]
    public let isCurrentTab: Bool

    public init(tabId: String, title: String, url: String, favicon: [AIChatPageContextData.PageContextFavicon], isCurrentTab: Bool = false) {
        self.tabId = tabId
        self.title = title
        self.url = url
        self.favicon = favicon
        self.isCurrentTab = isCurrentTab
    }

    /// Returns `true` if a tab with this URL should be hidden from any tab picker that lists
    /// open tabs as Duck.ai chat attachments (sidebar today, omnibar in the future). Excludes
    /// URLs that carry no useful page context for an AI chat:
    /// - The DDG homepage (SERP URLs with a `q=` parameter remain attachable).
    /// - `about:blank` (transient state, no content).
    /// - Duck.ai itself (avoids meta-attaching one chat to another).
    public static func shouldExcludeFromTabPicker(_ url: URL) -> Bool {
        return url.isDuckDuckGoHomepage
            || url.absoluteString == "about:blank"
            || url.isDuckAIURL
    }
}

/// Response to the `getAIChatOpenTabs` request.
public struct AIChatOpenTabsResponse: Codable {
    public let tabs: [AIChatTabMetadata]

    public init(tabs: [AIChatTabMetadata]) {
        self.tabs = tabs
    }
}

/// Parameters for the `getAIChatTabContent` request.
public struct AIChatTabContentParams: Codable {
    public let tabId: String
}

/// Response to the `getAIChatTabContent` request.
public struct AIChatTabContentResponse: Codable {
    public let pageContext: AIChatPageContextData?

    public init(pageContext: AIChatPageContextData?) {
        self.pageContext = pageContext
    }
}
