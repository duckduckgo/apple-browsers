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

actor AppSwitcherSnapshotCleaner {

    private let fileManager: FileManager
    private let libraryDirectoryOverride: URL?

    init(fileManager: FileManager = .default,
         libraryDirectoryOverride: URL? = nil) {
        self.fileManager = fileManager
        self.libraryDirectoryOverride = libraryDirectoryOverride
    }

    func clearSnapshots() async {
        guard let libraryDirectory = libraryDirectoryOverride ?? fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return
        }

        let snapshotsDirectory = libraryDirectory
            .appendingPathComponent("SplashBoard", isDirectory: true)
            .appendingPathComponent("Snapshots", isDirectory: true)

        let snapshotItems = (try? fileManager.contentsOfDirectory(at: snapshotsDirectory,
                                                                  includingPropertiesForKeys: nil,
                                                                  options: [])) ?? []

        for snapshotItem in snapshotItems {
            do {
                try fileManager.removeItem(at: snapshotItem)
            } catch {
                let itemName = snapshotItem.lastPathComponent
                let errorDescription = error.localizedDescription
                Logger.general.error("Failed to remove snapshot \(itemName, privacy: .public): \(errorDescription, privacy: .public)")
            }
        }
    }
}
