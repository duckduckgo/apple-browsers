//
//  BookmarksBarMenuPopoverPresenting.swift
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
import Foundation

/// Receives lifecycle and navigation callbacks from a bookmarks-bar menu popover.
/// Implemented by both the legacy `NSPopover`-based and the custom `NSPanel`-based
/// implementations, so the bar view controller doesn't need to know which is active.
protocol BookmarksBarMenuPopoverDelegate: AnyObject {
    func bookmarksBarMenuPopoverShouldClose(_ popover: any BookmarksBarMenuPopoverPresenting) -> Bool
    func bookmarksBarMenuPopoverDidClose(_ popover: any BookmarksBarMenuPopoverPresenting)
    func openNextBookmarksMenu(_ sender: any BookmarksBarMenuPopoverPresenting)
    func openPreviousBookmarksMenu(_ sender: any BookmarksBarMenuPopoverPresenting)
}

extension BookmarksBarMenuPopoverDelegate {
    func bookmarksBarMenuPopoverShouldClose(_ popover: any BookmarksBarMenuPopoverPresenting) -> Bool { true }
    func bookmarksBarMenuPopoverDidClose(_ popover: any BookmarksBarMenuPopoverPresenting) {}
}

/// Common API the bookmarks-bar code uses to drive a bookmarks menu popover,
/// abstracting over the two backing implementations:
/// `BookmarksBarMenuPopover` (NSPopover subclass) and
/// `BookmarksBarMenuCustomPopover` (NSResponder backed by `BookmarksBarMenuWindow`).
protocol BookmarksBarMenuPopoverPresenting: AnyObject {

    var isShown: Bool { get }
    var rootFolder: BookmarkFolder? { get }
    var positioningView: NSView? { get }
    var preferredEdge: NSRectEdge? { get }
    var viewController: BookmarksBarMenuViewController { get }

    var bookmarksBarMenuDelegate: BookmarksBarMenuPopoverDelegate? { get set }

    var behavior: NSPopover.Behavior { get set }

    func reloadData(withRootFolder rootFolder: BookmarkFolder)
    func close()

    func show(positionedBelow view: NSView)
    func show(positionedAsSubmenuAgainst positioningView: NSView)

    /// Called by the view controller when its `preferredContentSize`/`preferredContentOffset`
    /// changes. Resizes the custom window if applicable; no-op for the NSPopover-backed
    /// legacy implementation (NSPopover updates its own frame).
    func updatePresentedFrameIfNeeded()
}

extension BookmarksBarMenuPopoverPresenting {
    /// Toggles between auto-closing (transient) and sticky (application-defined) behavior.
    func setShouldPreventClosure(_ shouldPrevent: Bool) {
        behavior = shouldPrevent ? .applicationDefined : .transient
    }
}
