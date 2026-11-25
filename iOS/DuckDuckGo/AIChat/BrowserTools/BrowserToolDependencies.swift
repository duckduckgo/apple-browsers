//
//  BrowserToolDependencies.swift
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
import Core
import Foundation

extension ListOpenTabsBrowserTool {
    convenience init(scopeProvider: @escaping BrowserToolScopeProvider) {
        self.init { context in
            guard let scope = scopeProvider(context), scope.accepts(context) else { return nil }
            let tabs: [TabEntry] = scope.source.tabsProvider().compactMap { tab in
                guard tab.mode == .normal, let link = tab.link, !link.url.isDuckAIURL, !link.url.isFileURL else { return nil }
                return TabEntry(id: tab.uid, title: link.displayTitle, url: link.url)
            }
            return (tabs, scope.selectedTabID())
        }
    }
}
extension ReadTabContentBrowserTool {
    convenience init(scopeProvider: @escaping BrowserToolScopeProvider, reader: BrowserToolPageContentReading) {
        self.init(readPage: pageLoader(scopeProvider: scopeProvider, reader: reader))
    }
}
private func pageLoader(scopeProvider: @escaping BrowserToolScopeProvider, reader: BrowserToolPageContentReading) -> BrowserToolPageLoader {
    { tabIDArgument, context in
        guard let scope = scopeProvider(context), scope.accepts(context) else { return .failure(.unavailable) }
        let tab: Tab
        switch BrowserToolTargetTab.resolve(tabIDArgument: tabIDArgument, context: context, scope: scope) {
        case .failure(let failure):
            return .failure(failure)
        case .resolved(let target): tab = target
        }
        guard !Task.isCancelled, scope.canRead(tab) else { return .failure(.unavailable) }
        let tabID = tab.uid

        guard let pageContext = await reader.pageContext(for: tab, in: scope) else {
            return .failure(.unavailable)
        }
        guard !Task.isCancelled, scope.accepts(context), scope.canRead(tab) else {
            return .failure(.unavailable)
        }
        return .success(pageContext.withTabId(tabID))
    }
}
