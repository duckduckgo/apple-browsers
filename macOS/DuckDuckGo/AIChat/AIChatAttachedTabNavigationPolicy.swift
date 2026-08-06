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

/// What an attached tab's own navigation does to its attachment card.
///
/// With "Automatically send page content" on, an attached tab that navigates keeps feeding the
/// prompt, so the card follows it to the new page. With the setting off the attachment was an
/// explicit pick of one page, so navigating away drops it rather than silently sending a page the
/// user never chose. A tab that lands somewhere unattachable (Duck.ai, new tab page, non-URL
/// content) is dropped either way.
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
            // A tab attached mid-load is still finishing the navigation the user attached it for:
            // redirects and the committed URL arrive as URL changes. That is the same pick settling,
            // not a page the user chose to leave, so it rebases the attachment either way.
            guard automaticallySendsPageContext || isSettlingLoadFromAttachTime else { return .drop }
            return .refresh(AIChatTabAttachment(id: attachment.id, title: resolvedTitle, url: url, favicon: favicon))
        }

        // Same page: title and favicon both land after the navigation that carried them, so take
        // whichever has arrived. Neither is ever downgraded back to nil / the host fallback.
        let refreshedTitle = title ?? attachment.title
        let refreshedFavicon = favicon ?? attachment.favicon
        guard refreshedTitle != attachment.title || refreshedFavicon !== attachment.favicon else { return .keep }
        return .refresh(AIChatTabAttachment(id: attachment.id,
                                            title: refreshedTitle,
                                            url: url,
                                            favicon: refreshedFavicon))
    }
}
