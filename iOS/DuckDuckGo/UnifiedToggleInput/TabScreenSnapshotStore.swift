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
/// current relative to scroll position, URL changes, subscription state, etc. The in-memory
/// cache is also backed by a JPEG disk cache so snapshots survive cold boots — otherwise the
/// first swipe to a not-yet-visited tab would fall back to the legacy webview-only preview,
/// which is significantly shorter than the full screen and gets scaled up by the overlay's
/// `.scaleAspectFill` content mode, producing a visible zoom-in artifact on the destination.
final class TabScreenSnapshotStore {

    private enum Constants {
        static let directoryName = "TabScreenSnapshots"
        static let fileExtension = "jpg"
        static let jpegQuality: CGFloat = 0.85
    }

    private var snapshots: [String: UIImage] = [:]
    private let storeDir: URL?

    init(storeDir: URL? = TabScreenSnapshotStore.defaultStoreDir) {
        self.storeDir = storeDir
        ensureStoreDirectoryExists()
    }

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
        set(image: image, for: tabUID)
    }

    func snapshot(for tabUID: String) -> UIImage? {
        if let cached = snapshots[tabUID] {
            return cached
        }
        guard let image = loadFromDisk(tabUID: tabUID) else { return nil }
        snapshots[tabUID] = image
        return image
    }

    /// Direct image setter — used when the caller has already produced a `UIImage` (e.g. from
    /// the live source capture at swipe start) and wants to cache it without re-rendering.
    func set(image: UIImage, for tabUID: String) {
        snapshots[tabUID] = image
        writeToDisk(image: image, tabUID: tabUID)
    }

    /// Drops cached snapshots for tabs that no longer exist so the cache can't grow
    /// unbounded across long sessions. Called by the host when the tabs model changes.
    func prune(retainingTabUIDs validUIDs: Set<String>) {
        snapshots = snapshots.filter { validUIDs.contains($0.key) }
        guard let dir = storeDir else { return }
        DispatchQueue.global(qos: .utility).async {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            for file in files {
                let uid = (file as NSString).deletingPathExtension
                if !validUIDs.contains(uid) {
                    try? FileManager.default.removeItem(at: dir.appendingPathComponent(file))
                }
            }
        }
    }

    /// Forget a single tab — call when a tab is closed or fire-cleared.
    func remove(tabUID: String) {
        snapshots.removeValue(forKey: tabUID)
        guard let url = diskURL(for: tabUID) else { return }
        DispatchQueue.global(qos: .utility).async {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Forget everything (e.g. on global theme change where every cached visual is stale).
    func clear() {
        snapshots.removeAll()
        guard let dir = storeDir else { return }
        DispatchQueue.global(qos: .utility).async {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            for file in files {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(file))
            }
        }
    }

    // MARK: - Disk

    static fileprivate var defaultStoreDir: URL? {
        guard var dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        dir.appendPathComponent(Constants.directoryName, isDirectory: true)
        return dir
    }

    private func ensureStoreDirectoryExists() {
        guard var url = storeDir else { return }
        let parent = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parent.path, isDirectory: nil) {
            try? FileManager.default.createDirectory(at: parent,
                                                     withIntermediateDirectories: false,
                                                     attributes: nil)
        }
        if !FileManager.default.fileExists(atPath: url.path, isDirectory: nil) {
            try? FileManager.default.createDirectory(at: url,
                                                     withIntermediateDirectories: false,
                                                     attributes: nil)
            // Snapshots are derived data; don't push them through iCloud.
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try? url.setResourceValues(resourceValues)
        }
    }

    private func diskURL(for tabUID: String) -> URL? {
        storeDir?.appendingPathComponent("\(tabUID).\(Constants.fileExtension)")
    }

    private func writeToDisk(image: UIImage, tabUID: String) {
        guard let url = diskURL(for: tabUID) else { return }
        DispatchQueue.global(qos: .utility).async {
            guard let data = image.jpegData(compressionQuality: Constants.jpegQuality) else { return }
            try? data.write(to: url)
        }
    }

    private func loadFromDisk(tabUID: String) -> UIImage? {
        guard let url = diskURL(for: tabUID),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return UIImage(data: data)
    }
}
