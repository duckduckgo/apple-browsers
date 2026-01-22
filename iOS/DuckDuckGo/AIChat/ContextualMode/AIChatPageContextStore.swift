//
//  AIChatPageContextStore.swift
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

import AIChat
import Common
import UIKit

/// Protocol for page context storage, enabling dependency injection and testing.
protocol AIChatPageContextStoring: AnyObject {
    /// The latest page context collected from the current tab.
    var latestContext: AIChatPageContextData? { get }

    /// Decoded favicon image from the latest context, cached for chip display.
    var latestFavicon: UIImage? { get }

    /// Returns whether there is context available.
    var hasContext: Bool { get }

    /// Updates the stored page context.
    func update(_ context: AIChatPageContextData?)

    /// Clears the stored page context.
    func clear()
}

/// Single source of truth for page context in a contextual AI chat session.
/// Owned by the coordinator and shared with all components that need access to page context.
final class AIChatPageContextStore: AIChatPageContextStoring {

    private(set) var latestContext: AIChatPageContextData?
    private(set) var latestFavicon: UIImage?

    var hasContext: Bool {
        latestContext != nil
    }

    func update(_ context: AIChatPageContextData?) {
        latestContext = context
        latestFavicon = context.flatMap { decodeFaviconImage(from: $0.favicon) }
    }

    func clear() {
        latestContext = nil
        latestFavicon = nil
    }

    private func decodeFaviconImage(from favicons: [AIChatPageContextData.PageContextFavicon]) -> UIImage? {
        guard let favicon = favicons.first,
              favicon.href.hasPrefix("data:image"),
              let dataRange = favicon.href.range(of: "base64,"),
              let imageData = Data(base64Encoded: String(favicon.href[dataRange.upperBound...])) else {
            return nil
        }
        return UIImage(data: imageData)
    }
}
