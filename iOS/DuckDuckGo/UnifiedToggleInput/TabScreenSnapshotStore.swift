//
//  TabScreenSnapshotStore.swift
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

import UIKit
import Core

/// Per-tab cache of full-screen snapshots used as the slide-in/slide-out content of
/// `TabSwipeOverlayView`. Captures a `UIImage` of `MainViewController.view` via
/// `drawHierarchy(in:afterScreenUpdates:)`, which goes through UIKit's real rendering
/// pipeline — so the snapshot includes UIVisualEffectView blur, drop shadows, and SwiftUI
/// hosting views correctly. `CALayer.render(in:)` would miss all three.
///
/// Snapshots are refreshed each time a tab becomes active again, so they stay reasonably
/// current relative to scroll position, URL changes, subscription state, etc. Tabs that
/// haven't been visited in the current session have no cached entry — the overlay shows a
/// blank page for those, which is preferable to reusing a stale entry from a different tab.
final class TabScreenSnapshotStore {

    private var snapshots: [String: UIImage] = [:]

    /// Captures `view` into a `UIImage` and stores it under `tabUID`. Skips when `view` isn't
    /// in a window — `drawHierarchy` needs window context for visual-effect composition to be
    /// valid, otherwise the result has no blur/shadows.
    func capture(view: UIView, tabUID: String) {
        guard view.window != nil,
              view.bounds.width > 0,
              view.bounds.height > 0 else { return }
        let renderer = UIGraphicsImageRenderer(size: view.bounds.size)
        let image = renderer.image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: false)
        }
        snapshots[tabUID] = image
    }

    func snapshot(for tabUID: String) -> UIImage? {
        snapshots[tabUID]
    }

    /// Direct image setter — used when the caller has already produced a `UIImage` (e.g. from
    /// the live source capture at swipe start) and wants to cache it without re-rendering.
    func set(image: UIImage, for tabUID: String) {
        snapshots[tabUID] = image
    }

    /// Drops cached snapshots for tabs that no longer exist so the cache can't grow
    /// unbounded across long sessions. Called by the host when the tabs model changes.
    func prune(retainingTabUIDs validUIDs: Set<String>) {
        snapshots = snapshots.filter { validUIDs.contains($0.key) }
    }

    /// Forget a single tab — call when a tab is closed or fire-cleared.
    func remove(tabUID: String) {
        snapshots.removeValue(forKey: tabUID)
    }

    /// Forget everything (e.g. on global theme change where every cached visual is stale).
    func clear() {
        snapshots.removeAll()
    }
}
