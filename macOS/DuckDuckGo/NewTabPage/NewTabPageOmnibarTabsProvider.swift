//
//  NewTabPageOmnibarTabsProvider.swift
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
import AppKit
import NewTabPage
import WebKit

/// Backs the NTP omnibar's attach-tabs picker. Sources tabs across windows (excluding Fire Windows)
/// via the shared `AIChatTabPickerSource` and extracts page content via
/// `AIChatUserScriptHandler.extractPageContext`, matching the Duck.ai sidebar and address-bar pickers.
final class NewTabPageOmnibarTabsProvider: NewTabPageOmnibarTabsProviding {

    private let windowControllersManager: WindowControllersManagerProtocol

    init(windowControllersManager: WindowControllersManagerProtocol) {
        self.windowControllersManager = windowControllersManager
    }

    @MainActor
    func openTabs(requestingWebView: WKWebView?) async -> [NewTabPageDataModel.OmnibarTabMetadata] {
        guard let origin = AIChatTabPickerSource.originTabCollectionViewModel(for: requestingWebView, in: windowControllersManager) else {
            return []
        }
        let currentTabId = origin.selectedTabViewModel?.tab.uuid

        let faviconManager = NSApp.delegateTyped.faviconManager
        return AIChatTabPickerSource.attachableTabs(forOrigin: origin, in: windowControllersManager).compactMap { tab in
            guard case .url(let url, _, _) = tab.content else { return nil }
            guard tab.uuid != currentTabId else { return nil }

            let favicon: NewTabPageDataModel.OmnibarTabFavicon?
            if let image = faviconManager.getCachedFavicon(for: url, sizeCategory: .small)?.image,
               let base64 = image.base64PNGDataURL {
                favicon = NewTabPageDataModel.OmnibarTabFavicon(src: base64, maxAvailableSize: Int(Favicon.SizeCategory.small.rawValue))
            } else {
                favicon = nil
            }

            return NewTabPageDataModel.OmnibarTabMetadata(
                tabId: tab.uuid,
                title: tab.title ?? url.host ?? "",
                url: url.absoluteString,
                favicon: favicon
            )
        }
    }

    @MainActor
    func tabContent(tabId: String, requestingWebView: WKWebView?) async -> NewTabPageDataModel.OmnibarPageContext? {
        // Wakes the tab if it's suspended so its content can be extracted instead of being dropped.
        guard let origin = AIChatTabPickerSource.originTabCollectionViewModel(for: requestingWebView, in: windowControllersManager),
              let pageContext = await AIChatUserScriptHandler.extractPageContext(forTabId: tabId, origin: origin, in: windowControllersManager) else {
            return nil
        }

        return NewTabPageDataModel.OmnibarPageContext(
            tabId: tabId,
            title: pageContext.title,
            url: pageContext.url,
            favicon: pageContext.favicon.first.map { NewTabPageDataModel.OmnibarTabFavicon(src: $0.href) },
            content: pageContext.content,
            truncated: pageContext.truncated,
            fullContentLength: pageContext.fullContentLength
        )
    }
}
