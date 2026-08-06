//
//  AIChatAttachedTabNavigationPolicy.swift
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

import AIChat
import AppKit
import Foundation

/// What an attached tab's navigation does to its card: follow it, or drop the explicit pick.
enum AIChatAttachedTabNavigationPolicy {

    enum Action: Equatable {
        case keep
        case refresh(AIChatTabAttachment)
        case drop
    }

    static func action(for attachment: AIChatTabAttachment,
                       content: Tab.TabContent,
                       title: String?,
                       favicon: NSImage?,
                       isSettlingLoadFromAttachTime: Bool,
                       automaticallySendsPageContext: Bool) -> Action {
        guard case .url(let url, _, let source) = content, !AIChatTabMetadata.shouldExcludeFromTabPicker(url) else {
            return .drop
        }

        guard url == attachment.url else {
            // Only the web view settling the load that was in flight at attach time (redirect,
            // committed URL) counts as the same pick; anything the user drove is a page change.
            let isSettling = isSettlingLoadFromAttachTime && source == .webViewUpdated
            guard automaticallySendsPageContext || isSettling else { return .drop }
            // The old title and favicon still describe the previous page until the new ones land.
            return .refresh(AIChatTabAttachment(id: attachment.id,
                                                title: url.host ?? url.absoluteString,
                                                url: url,
                                                favicon: nil))
        }

        // Title and favicon land after the page; never downgrade to nil / the host fallback.
        let refreshedTitle = title ?? attachment.title
        let refreshedFavicon = favicon ?? attachment.favicon
        guard refreshedTitle != attachment.title || refreshedFavicon !== attachment.favicon else { return .keep }
        return .refresh(AIChatTabAttachment(id: attachment.id,
                                            title: refreshedTitle,
                                            url: url,
                                            favicon: refreshedFavicon))
    }
}
