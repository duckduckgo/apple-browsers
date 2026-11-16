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
    let ownerTabID: String
    let isBurner: Bool
    let token = UUID().uuidString
    let source: MultiTabAttachmentSource
    let selectedTabID: () -> String?
    let selectTab: (Tab) -> Bool
    private weak var owner: Tab?
    private var isRevoked = false

    init(owner: Tab, source: MultiTabAttachmentSource, selectedTabID: @escaping () -> String?,
         selectTab: @escaping (Tab) -> Bool = { _ in false }) {
        self.owner = owner
        self.ownerTabID = owner.uid
        self.isBurner = owner.mode == .fire
        self.source = source
        self.selectedTabID = selectedTabID
        self.selectTab = selectTab
    }

    var isValid: Bool {
        guard !isRevoked, !isBurner, source.mode == .normal, let owner, owner.mode == .normal else { return false }
        return source.tabsProvider().contains { $0 === owner }
    }

    func accepts(_ context: BrowserToolCallContext) -> Bool {
        isValid && !context.isBurner && context.ownerTabID == ownerTabID && context.ownerWindowToken == token
    }

    func contains(_ tab: Tab) -> Bool {
        isValid && tab.mode == .normal && source.tabsProvider().contains { $0 === tab }
    }

    func revoke() {
        isRevoked = true
    }
}
