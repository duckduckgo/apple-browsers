//
//  DefaultBrowserAndDockPromptUIHosting.swift
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

import AppKit

/// Protocol for view controllers that can host default browser/dock prompts.
/// Used by the presenter's async show methods when driven by PromoService.
protocol DefaultBrowserAndDockPromptUIHosting: AnyObject {
    /// When true, prompts must not be shown (e.g. popup windows).
    var isInPopUpWindow: Bool { get }

    /// Anchor view for the popover (address bar or bookmarks bar).
    func providePopoverAnchor() -> NSView?

    /// Adds the banner to this view controller's view hierarchy.
    func addSetAsDefaultBanner(_ banner: BannerMessageViewController)

    /// Window to present the inactive user modal sheet over.
    func provideModalAnchor() -> NSWindow?
}
