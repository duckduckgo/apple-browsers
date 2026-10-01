//
//  AppSwitcherSnapshotCleaner.swift
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

import Common
import Foundation
import PixelKit

actor AppSwitcherSnapshotCleaner {

    private let fileManager: FileManager
    private let libraryDirectoryOverride: URL?
    private let pixelFiring: PixelFiring?

    init(fileManager: FileManager = .default,
         libraryDirectoryOverride: URL? = nil,
         pixelFiring: PixelFiring? = PixelKit.shared) {
        self.fileManager = fileManager
        self.libraryDirectoryOverride = libraryDirectoryOverride
        self.pixelFiring = pixelFiring
    }

    func clearSnapshots() async {
        guard let libraryDirectory = libraryDirectoryOverride ?? fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return
        }

        let snapshotsDirectory = libraryDirectory
            .appendingPathComponent("SplashBoard", isDirectory: true)
            .appendingPathComponent("Snapshots", isDirectory: true)

        let snapshotItems: [URL]
        do {
            snapshotItems = try fileManager.contentsOfDirectory(at: snapshotsDirectory,
                                                                includingPropertiesForKeys: nil,
                                                                options: [])
        } catch CocoaError.fileReadNoSuchFile {
            // This system-owned directory may be absent. In that case, there are no snapshots at
            // this path to clear.
            return
        } catch {
            let errorDescription = error.localizedDescription
            Logger.general.error("Failed to enumerate app switcher snapshots: \(errorDescription, privacy: .public)")
            pixelFiring?.fire(AppSwitcherSnapshotClearingPixel.failed(error), frequency: .dailyAndCount)
            return
        }

        var firstRemovalError: Error?
        for snapshotItem in snapshotItems {
            do {
                try fileManager.removeItem(at: snapshotItem)
            } catch CocoaError.fileNoSuchFile {
                // The desired state is already reached if the item disappears after enumeration.
                continue
            } catch {
                firstRemovalError = firstRemovalError ?? error
                let itemName = snapshotItem.lastPathComponent
                let errorDescription = error.localizedDescription
                Logger.general.error("Failed to remove snapshot \(itemName, privacy: .public): \(errorDescription, privacy: .public)")
            }
        }

        if let firstRemovalError {
            pixelFiring?.fire(AppSwitcherSnapshotClearingPixel.failed(firstRemovalError), frequency: .dailyAndCount)
        }
    }
}

private enum AppSwitcherSnapshotClearingPixel: PixelKit.Event {
    case failed(Error)

    var name: String { "app-switcher_snapshot_clearing_failed" }

    var parameters: [String: String]? { nil }

    var error: NSError? {
        switch self {
        case .failed(let error):
            return error as NSError
        }
    }

    var standardParameters: [PixelKitStandardParameter]? { [.pixelSource] }
}
