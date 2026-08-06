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

/// Everything an attached tab publishes about the page it is on.
struct AIChatAttachedTabPage {
    let content: Tab.TabContent
    let title: String?
    let favicon: NSImage?
    var isLoading: Bool = false

    init(content: Tab.TabContent, title: String?, favicon: NSImage?, isLoading: Bool = false) {
        self.content = content
        self.title = title
        self.favicon = favicon
        self.isLoading = isLoading
    }

    init(tab: Tab) {
        self.init(content: tab.content, title: tab.title, favicon: tab.favicon, isLoading: tab.isLoading)
    }
}

/// What an attached tab's navigation does to its card: follow it, or drop the explicit pick.
enum AIChatAttachedTabNavigationPolicy {

    enum Action: Equatable {
        case keep
        case refresh(AIChatTabAttachment)
        case drop
    }

    static func action(for attachment: AIChatTabAttachment,
                       page: AIChatAttachedTabPage,
                       isSettlingLoadFromAttachTime: Bool,
                       automaticallySendsPageContext: Bool) -> Action {
        guard case .url(let url, _, let source) = page.content, !AIChatTabMetadata.shouldExcludeFromTabPicker(url) else {
            return .drop
        }
        guard url != attachment.url else {
            return updatedMetadata(for: attachment, page: page)
        }
        return afterPageChange(for: attachment,
                               to: url,
                               isSettling: isSettlingLoadFromAttachTime && source == .webViewUpdated,
                               automaticallySendsPageContext: automaticallySendsPageContext)
    }

    /// Only the web view settling the load that was in flight at attach time (redirect, committed
    /// URL) counts as the same pick; anything the user drove is a page change.
    private static func afterPageChange(for attachment: AIChatTabAttachment,
                                        to url: URL,
                                        isSettling: Bool,
                                        automaticallySendsPageContext: Bool) -> Action {
        guard automaticallySendsPageContext || isSettling else { return .drop }
        // The old title and favicon still describe the previous page until the new ones land.
        return .refresh(AIChatTabAttachment(id: attachment.id,
                                            title: url.host ?? url.absoluteString,
                                            url: url,
                                            favicon: nil))
    }

    /// Same page: title and favicon land after it does, and neither is ever downgraded back to nil.
    private static func updatedMetadata(for attachment: AIChatTabAttachment, page: AIChatAttachedTabPage) -> Action {
        let title = page.title ?? attachment.title
        let favicon = page.favicon ?? attachment.favicon
        guard title != attachment.title || favicon !== attachment.favicon else { return .keep }
        return .refresh(AIChatTabAttachment(id: attachment.id, title: title, url: attachment.url, favicon: favicon))
    }
}
