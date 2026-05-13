//
//  TabPreviewsSource.swift
//  DuckDuckGo
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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

protocol TabPreviewsSource: AnyObject {

    func prepare()
    func update(preview: UIImage, forTab tab: Tab)
    func removePreview(forTab tab: Tab)
    func removeAllPreviews() -> Result<Void, Error>
    func removePreviewsWithIdNotIn(_ ids: Set<String>) -> Result<Void, Error>
    func totalStoredPreviews() -> Int?
    func preview(for tab: Tab) -> UIImage?
    func fullScreenSnapshot(for tab: Tab) -> UIImage?
    func updateFullScreenSnapshot(_ snapshot: UIImage, forTab tab: Tab)

}

class DefaultTabPreviewsSource: TabPreviewsSource {

    struct Constants {
        static let previewsDirectoryName = "Previews"
        static let fullScreenSubdirectoryName = "FullScreen"
        static let fullScreenJPEGQuality: CGFloat = 0.85
        // buffer so quick back-and-forth swipes don't hit disk on every traversal.
        static let fullScreenCacheCountLimit = 8
    }

    private var cache = [String: UIImage]()
    private let fullScreenCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = Constants.fullScreenCacheCountLimit
        return cache
    }()

    private lazy var tabSettings: TabSwitcherSettings = DefaultTabSwitcherSettings()

    fileprivate var previewStoreDir: URL?
    private var legacyPreviewStoreDir: URL?

    private var fullScreenStoreDir: URL? {
        previewStoreDir?.appendingPathComponent(Constants.fullScreenSubdirectoryName, isDirectory: true)
    }
    
    init(storeDir: URL? = DefaultTabPreviewsSource.previewStoreDir,
         legacyDir: URL? = DefaultTabPreviewsSource.legacyPreviewStoreDir) {
        previewStoreDir = storeDir
        legacyPreviewStoreDir = legacyDir
    }
    
    func prepare() {
        ensurePreviewStoreDirectoryExists()
        ensureFullScreenStoreDirectoryExists()
        migratePreviewStoreDirectoryFromCache()

        // Remove already stored previews for tabs that were not yet closed by the user
        if !tabSettings.isGridViewEnabled {
            _ = removeAllPreviews()
        }
    }
    
    func update(preview: UIImage, forTab tab: Tab) {
        cache[tab.uid] = preview
        store(preview: preview, forTab: tab)
        tab.didUpdatePreview()
    }
    
    func preview(for tab: Tab) -> UIImage? {
        if let preview = cache[tab.uid] {
            return preview
        }
        
        guard let preview = loadPreview(forTab: tab) else {
            return nil
        }
        
        cache[tab.uid] = preview
        return preview
    }
    
    func removePreview(forTab tab: Tab) {
        guard let url = previewLocation(for: tab) else { return }

        cache[tab.uid] = nil

        do {
            if FileManager.default.fileExists(atPath: url.filePath) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            Pixel.fire(pixel: .cachedTabPreviewRemovalError, error: error)
        }

        removeFullScreenSnapshot(forTabUID: tab.uid)
    }
    
    func removeAllPreviews() -> Result<Void, Error> {
        cache.removeAll()
        fullScreenCache.removeAllObjects()
        guard let dirUrl = previewStoreDir else { return .success(()) }

        var encounteredError: Error?

        do {
            let previews = try FileManager.default.contentsOfDirectory(at: dirUrl, includingPropertiesForKeys: nil)
            for previewUrl in previews {
                // `previews` includes the FullScreen subdirectory itself — `removeItem` deletes
                // it recursively, which clears the persisted full-screen snapshots in one pass.
                do {
                    try FileManager.default.removeItem(at: previewUrl)
                } catch {
                    encounteredError = error
                }
            }
        } catch {
            encounteredError = error
        }

        // Recreate the empty FullScreen subdirectory so the next write doesn't fail silently.
        ensureFullScreenStoreDirectoryExists()

        if let error = encounteredError {
            return .failure(error)
        }
        return .success(())
    }
    
    fileprivate func cleanupCache() {
        cache.removeAll()
    }

    func totalStoredPreviews() -> Int? {
        guard let directory = previewStoreDir else { return nil }

        let contents = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        return contents?.filter { $0.hasSuffix(".png") }.count
    }
    
    static fileprivate var previewStoreDir: URL? {
        guard var cachesDirURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        cachesDirURL.appendPathComponent(Constants.previewsDirectoryName, isDirectory: true)
        return cachesDirURL
    }
    
    static private var legacyPreviewStoreDir: URL? {
        guard var cachesDirURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        cachesDirURL.appendPathComponent(Constants.previewsDirectoryName, isDirectory: true)
        return cachesDirURL
    }
    
    private func ensurePreviewStoreDirectoryExists() {
        guard var url = previewStoreDir else { return }
        
        // Create Application Support Dir if needed.
        let parentDirURL = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDirURL.path, isDirectory: nil) {
            try? FileManager.default.createDirectory(at: parentDirURL,
                                                     withIntermediateDirectories: false,
                                                     attributes: nil)
        }
        
        if !FileManager.default.fileExists(atPath: url.path, isDirectory: nil) {
            
            try? FileManager.default.createDirectory(at: url,
                                                     withIntermediateDirectories: false,
                                                     attributes: nil)
            
            // Exclude Previews Dir from backup
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try? url.setResourceValues(resourceValues)
        }
    }
    
    private func migratePreviewStoreDirectoryFromCache() {
        guard let source = legacyPreviewStoreDir,
            let destination = previewStoreDir else { return }
        
        let contents = (try? FileManager.default.contentsOfDirectory(at: source,
                                                                    includingPropertiesForKeys: nil,
                                                                    options: .skipsSubdirectoryDescendants)) ?? []
        let previews = contents.filter { $0.lastPathComponent.hasSuffix(".png") }
        
        for preview in previews {
            let desitnationURL = destination.appendingPathComponent(preview.lastPathComponent)
            try? FileManager.default.moveItem(at: preview, to: desitnationURL)
        }
        
        try? FileManager.default.removeItem(at: source)
    }
    
    private func previewLocation(for tab: Tab) -> URL? {
        return previewStoreDir?.appendingPathComponent("\(tab.uid).png")
    }
    
    private func store(preview: UIImage, forTab tab: Tab) {
        guard let url = previewLocation(for: tab) else { return }
        
        DispatchQueue.global(qos: .utility).async {
            guard let data = preview.pngData() else { return }
            try? data.write(to: url)
        }
    }
    
    private func loadPreview(forTab tab: Tab) -> UIImage? {
        guard let url = previewLocation(for: tab),
            let data = try? Data(contentsOf: url) else { return nil }
        
        return UIImage(data: data)
    }

    func removePreviewsWithIdNotIn(_ ids: Set<String>) -> Result<Void, Error> {
        guard let directory = previewStoreDir else { return .success(()) }
        guard !ids.isEmpty else {
            return removeAllPreviews()
        }
        var encounteredError: Error?
        do {
            let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            // Only iterate thumbnail PNGs — the FullScreen subdirectory is cleaned in its own
            // pass below, and iterating it here would treat it as an orphan and delete every
            // persisted full-screen snapshot.
            contents.filter { $0.hasSuffix(".png") }.forEach {
                let id = $0.dropping(suffix: ".png")
                if !ids.contains(id) {
                    cache[id] = nil
                    let previewUrl = directory.appending($0)
                    do {
                        try FileManager.default.removeItem(at: previewUrl)
                    } catch {
                        encounteredError = error
                    }
                }
            }
        } catch {
            encounteredError = error
        }

        pruneFullScreenSnapshots(retainingTabUIDs: ids)

        if let error = encounteredError {
            return .failure(error)
        }
        return .success(())
    }

    // MARK: - Full-screen snapshots

    func fullScreenSnapshot(for tab: Tab) -> UIImage? {
        let key = tab.uid as NSString
        if let cached = fullScreenCache.object(forKey: key) {
            return cached
        }
        guard let url = fullScreenSnapshotLocation(forTabUID: tab.uid),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            return nil
        }
        fullScreenCache.setObject(image, forKey: key)
        return image
    }

    func updateFullScreenSnapshot(_ snapshot: UIImage, forTab tab: Tab) {
        fullScreenCache.setObject(snapshot, forKey: tab.uid as NSString)
        storeFullScreenSnapshot(snapshot, forTabUID: tab.uid)
    }

    private func ensureFullScreenStoreDirectoryExists() {
        guard let url = fullScreenStoreDir else { return }
        if !FileManager.default.fileExists(atPath: url.path, isDirectory: nil) {
            try? FileManager.default.createDirectory(at: url,
                                                     withIntermediateDirectories: true,
                                                     attributes: nil)
        }
    }

    private func fullScreenSnapshotLocation(forTabUID uid: String) -> URL? {
        fullScreenStoreDir?.appendingPathComponent("\(uid).jpg")
    }

    private func storeFullScreenSnapshot(_ snapshot: UIImage, forTabUID uid: String) {
        guard let url = fullScreenSnapshotLocation(forTabUID: uid) else { return }
        DispatchQueue.global(qos: .utility).async {
            guard let data = snapshot.jpegData(compressionQuality: Constants.fullScreenJPEGQuality) else { return }
            try? data.write(to: url)
        }
    }

    private func removeFullScreenSnapshot(forTabUID uid: String) {
        fullScreenCache.removeObject(forKey: uid as NSString)
        guard let url = fullScreenSnapshotLocation(forTabUID: uid) else { return }
        DispatchQueue.global(qos: .utility).async {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func pruneFullScreenSnapshots(retainingTabUIDs ids: Set<String>) {
        fullScreenCache.removeAllObjects()
        guard let dir = fullScreenStoreDir else { return }
        DispatchQueue.global(qos: .utility).async {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            for file in files {
                let uid = (file as NSString).deletingPathExtension
                if !ids.contains(uid) {
                    try? FileManager.default.removeItem(at: dir.appendingPathComponent(file))
                }
            }
        }
    }
}
