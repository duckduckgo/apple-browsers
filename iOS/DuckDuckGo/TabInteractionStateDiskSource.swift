//
//  TabInteractionStateDiskSource.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import Foundation
import os.log

import Core

protocol TabInteractionStateSource {
    func saveState(_ state: Any?, for tab: Tab)
    func popLastStateForTab(_ tab: Tab) -> Data?
    func removeStateForTab(_ tab: Tab)
    func removeAll(excluding excludedTabs: [Tab])
    func urlsToRemove(excluding excludedTabs: [Tab]) -> [URL]
    func removeStates(at urls: [URL], isCancelled: (() -> Bool)?)
}

protocol TabInteractionStateSourceDebugging {
    func allCacheFiles() throws -> [URL]
}

final class TabInteractionStateDiskSource: TabInteractionStateSource, TabInteractionStateSourceDebugging {
    private let fileManager: FileManager
    private let interactionStateCacheLocation: URL
    private let pixelFiring: PixelFiring.Type

    init?(fileManager: FileManager = .default,
          pixelFiring: PixelFiring.Type = Pixel.self) {
        self.fileManager = fileManager
        self.pixelFiring = pixelFiring

        guard let cachesUrl = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            pixelFiring.fire(.tabInteractionStateSourceMissingRootDirectory, withAdditionalParameters: [:])
            return nil
        }
        let interactionStateLocation = cachesUrl
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? Constant.fallbackBundleIdentifier)
            .appendingPathComponent(Constant.interactionDirectoryName)

        var isDirectory: ObjCBool = false
        var fileExists = fileManager.fileExists(atPath: interactionStateLocation.path, isDirectory: &isDirectory)
        if fileExists, !isDirectory.boolValue {
            // We have file instead of directory, remove the file and create dir.
            if (try? fileManager.removeItem(at: interactionStateLocation)) != nil {
                fileExists = false
            }
        }

        if !fileExists {
            try? fileManager.createDirectory(at: interactionStateLocation, withIntermediateDirectories: true)
        }

        self.interactionStateCacheLocation = interactionStateLocation
    }

    func saveState(_ state: Any?, for tab: Tab) {
        guard let state,
              let stateData = state as? Data
        else { return }

        let tabCacheLocation = cacheLocationForTab(tab)

        Logger.tabInteractionStateSource.debug("Saving interaction state for tab \(tab.uid)...")
        do {
            try stateData.write(to: tabCacheLocation,
                                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            Logger.tabInteractionStateSource.debug("Saved interaction state for tab \(tab.uid)")
        } catch {
            Logger.tabInteractionStateSource.error("Interaction state for tab \(tab.uid) failed. Error: \(error.localizedDescription)")

            // Remove existing file (if present) in case write failed to prevent loading outdated state.
            removeStateForTab(tab)

            pixelFiring.fire(pixel: .tabInteractionStateSourceFailedToWrite,
                             error: error,
                             includedParameters: [.appVersion],
                             withAdditionalParameters: ["dataSizeBytes": TabInteractionStateDataSizeBucket(dataSize: stateData.count).value],
                             onComplete: { _ in })
        }
    }

    func popLastStateForTab(_ tab: Tab) -> Data? {
        let tabCacheLocation = cacheLocationForTab(tab)

        guard let stateData = try? Data(contentsOf: tabCacheLocation) else {
            Logger.tabInteractionStateSource.debug("No interaction state found for tab \(tab.uid)")
            return nil
        }

        Logger.tabInteractionStateSource.debug("Interaction state found for tab \(tab.uid)")

        removeStateForTab(tab)

        return stateData
    }

    func removeStateForTab(_ tab: Tab) {
        let tabCacheLocation = cacheLocationForTab(tab)
        try? fileManager.removeItem(at: tabCacheLocation)
    }

    func removeAll(excluding excludedTabs: [Tab]) {
        let urls = urlsToRemove(excluding: excludedTabs)
        removeStates(at: urls)
    }

    func urlsToRemove(excluding excludedTabs: [Tab]) -> [URL] {
        guard let allCacheFiles = try? allCacheFiles() else {
            return []
        }
        return allCacheFiles.filter { file in
            let isExcluded = excludedTabs.contains { $0.uid == file.lastPathComponent }
            return !isExcluded
        }
    }

    func removeStates(at urls: [URL], isCancelled: (() -> Bool)? = nil) {
        for url in urls {
            if isCancelled?() == true {
                break
            }
            try? fileManager.removeItem(at: url)
        }
    }

    func allCacheFiles() throws -> [URL] {
        try fileManager.contentsOfDirectory(at: interactionStateCacheLocation, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
    }

    private func cacheLocationForTab(_ tab: Tab) -> URL {
        interactionStateCacheLocation.appendingPathComponent(tab.uid)
    }

    private enum Constant {
        static let interactionDirectoryName = "webview-interaction"
        static let fallbackBundleIdentifier = "com.duckduckgo.mobile.ios"
    }
}

private extension Logger {
    static var tabInteractionStateSource: Logger = { Logger(subsystem: "TabInteractionStateSource", category: "") }()
}

private struct TabInteractionStateDataSizeBucket {

    let value: String

    init(dataSize: Int) {

        switch dataSize {
        case 0:
            value = "0"
        case ...256:
            value = "<256"
        case ...16000:
            value = "<16000"
        case ...1000000:
            value = "<1000000"
        case ...100000000:
            value = "<100000000"
        default:
            value = "more"
        }
    }
}
