//
//  FileStorageManaging.swift
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

public protocol FileStorageManaging {
    func migrateDatabaseToSharedStorageIfNeeded(from databaseURL: URL, to sharedDatabaseURL: URL) throws -> URL
}

final public class AppGroupFileStorageManager: FileStorageManaging {

    private let fileManager: FileManager

    public init(fileManager: FileManager = FileManager.default) {
        self.fileManager = fileManager
    }

    private func fileExists(at url: URL) -> Bool {
        return fileManager.fileExists(atPath: url.path)
    }

    private func createDirectoryIfNeeded(at url: URL) throws {
        let directoryPath = url.path
        if !fileManager.fileExists(atPath: directoryPath) {
            do {
                try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
                Logger.secureStorage.info("Created directory at \(directoryPath)")
            } catch {
                Logger.secureStorage.error("Failed to create directory: \(error.localizedDescription)")
                throw error
            }
        }
    }

    private func copyFile(from sourceURL: URL, to destinationURL: URL) throws {
        do {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            Logger.secureStorage.error("Error moving file: \(error.localizedDescription)")
            throw error
        }
    }

    private func removeFile(at url: URL) throws {
        do {
            try fileManager.removeItem(at: url)
            Logger.secureStorage.info("Removed file at \(url.path)")
        } catch {
            Logger.secureStorage.error("Error removing file: \(error.localizedDescription)")
            throw error
        }
    }

    public func migrateDatabaseToSharedStorageIfNeeded(from databaseURL: URL, to sharedDatabaseURL: URL) throws -> URL {
        if fileExists(at: sharedDatabaseURL) {
            return sharedDatabaseURL
        }

        do {
            // Ensure the shared group directory exists
            try createDirectoryIfNeeded(at: sharedDatabaseURL.deletingLastPathComponent())

            if fileExists(at: databaseURL) {
                try copyFile(from: databaseURL, to: sharedDatabaseURL)

                // If the copy was successful, delete the original file
                try removeFile(at: databaseURL)

                return sharedDatabaseURL
            }
        } catch {
            Logger.secureStorage.error("Failed to migrate Vault.db: \(error.localizedDescription)")
            throw error
        }

        return sharedDatabaseURL
    }
}
