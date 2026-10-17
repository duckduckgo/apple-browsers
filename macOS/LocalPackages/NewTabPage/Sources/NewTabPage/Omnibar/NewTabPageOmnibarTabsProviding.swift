//
//  NewTabPageOmnibarTabsProviding.swift
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

import WebKit

/// Supplies the data backing the NTP omnibar's attach-tabs picker. The concrete implementation
/// lives in the app, where it can enumerate open tabs and extract page content.
///
/// `requestingWebView` is the web view that hosts the requesting NTP, used to resolve which window
/// the picker was opened in so tabs can be sourced across windows (excluding Fire Windows) relative
/// to that origin.
public protocol NewTabPageOmnibarTabsProviding: AnyObject {

    /// Metadata for the user's open tabs, excluding the requesting NTP tab, in recency order.
    @MainActor
    func openTabs(requestingWebView: WKWebView?) async -> [NewTabPageDataModel.OmnibarTabMetadata]

    /// Extracted page content for the given tab, or `nil` if the tab can't be found or content
    /// can't be extracted (closed, restricted page, extraction failure, etc).
    @MainActor
    func tabContent(tabId: String, requestingWebView: WKWebView?) async -> NewTabPageDataModel.OmnibarPageContext?
}
