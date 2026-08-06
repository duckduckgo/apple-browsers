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
        guard case .url(let url, _, _) = content, !AIChatTabMetadata.shouldExcludeFromTabPicker(url) else {
            return .drop
        }

        let resolvedTitle = title ?? url.host ?? ""

        guard url == attachment.url else {
            // A load in flight at attach time is settling (redirect, committed URL), not a page change.
            guard automaticallySendsPageContext || isSettlingLoadFromAttachTime else { return .drop }
            return .refresh(AIChatTabAttachment(id: attachment.id, title: resolvedTitle, url: url, favicon: favicon))
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
