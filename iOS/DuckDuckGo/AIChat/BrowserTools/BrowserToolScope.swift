//
//  BrowserToolScope.swift
//  DuckDuckGo
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
import Foundation

typealias BrowserToolScopeProvider = @MainActor (BrowserToolCallContext) -> BrowserToolScope?

@MainActor
final class BrowserToolScope {
    enum Resolution {
        case resolved(Tab)
        case failure(BrowserToolFailure)
    }

    let ownerTabID: String
    let isBurner: Bool
    let token = UUID().uuidString
    let source: MultiTabAttachmentSource
    let selectedTabID: () -> String?
    let controller: (Tab) -> TabViewController?
    let selectTab: (Tab) -> Bool
    private weak var owner: Tab?
    private var isRevoked = false

    init(owner: Tab, source: MultiTabAttachmentSource,
         selectedTabID: @escaping () -> String?,
         controller: @escaping (Tab) -> TabViewController?,
         selectTab: @escaping (Tab) -> Bool) {
        self.owner = owner
        self.ownerTabID = owner.uid
        self.isBurner = owner.mode == .fire
        self.source = source
        self.selectedTabID = selectedTabID
        self.controller = controller
        self.selectTab = selectTab
    }

    var isValid: Bool {
        guard !isRevoked, !isBurner, source.mode == .normal, let owner, owner.mode == .normal else { return false }
        return source.tabsProvider().contains { $0 === owner }
    }

    func revoke() {
        isRevoked = true
    }

    var tabs: [Tab] {
        guard isValid else { return [] }
        return source.tabsProvider().filter { $0.mode == .normal }
    }

    func isChatURL(_ url: URL) -> Bool {
        url.isDuckAIURL || AIChatDebugSettings().matchesCustomURL(url)
    }

    func isAttachableURL(_ url: URL) -> Bool {
        !isChatURL(url) && !AIChatTabMetadata.shouldExcludeFromTabPicker(url)
    }

    func accepts(_ context: BrowserToolCallContext) -> Bool {
        isValid && !context.isBurner && context.ownerTabID == ownerTabID && context.ownerWindowToken == token
    }

    func contains(_ tab: Tab) -> Bool {
        isValid && tab.mode == .normal && source.tabsProvider().contains { $0 === tab }
    }

    func resolve(tabIDArgument: JSONValue?, context: BrowserToolCallContext) -> Resolution {
        guard accepts(context) else { return .failure(.unavailable) }
        let tabID: String
        switch tabIDArgument {
        case .none, .some(.null): tabID = ownerTabID
        case .some(.string(let value)):
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            tabID = trimmed.isEmpty ? ownerTabID : trimmed
        default: return .failure(.invalidArguments)
        }
        guard let tab = tabs.first(where: { $0.uid == tabID }) else { return .failure(.notFound) }
        return .resolved(tab)
    }
}
