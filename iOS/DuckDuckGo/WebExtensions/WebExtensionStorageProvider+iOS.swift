//
//  WebExtensionStorageProvider+iOS.swift
//  DuckDuckGo
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

import Foundation
import WebExtensions

@available(iOS 18.4, *)
public final class WebExtensionStorageProvider: WebExtensionStorageProviding {

    public enum StorageError: Error {
        case applicationSupportDirectoryNotFound
        case failedToCreateDirectory(Error)
        case failedToCopyExtension(Error)
        case failedToRemoveExtension(Error)
    }

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public var extensionsDirectory: URL {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Application Support directory not found")
        }
        return appSupport.appendingPathComponent("WebExtensions", isDirectory: true)
    }

    public func resolveInstalledExtension(identifier: String) -> URL? {
        let path = extensionsDirectory.appendingPathComponent(identifier)
        guard fileManager.fileExists(atPath: path.path) else {
            return nil
        }
        return path
    }

    public func installExtension(from sourceURL: URL) throws -> (path: URL, identifier: String) {
        let identifier = sourceURL.lastPathComponent
        let destinationURL = extensionsDirectory.appendingPathComponent(identifier)

        do {
            try fileManager.createDirectory(at: extensionsDirectory,
                                            withIntermediateDirectories: true)
        } catch {
            throw StorageError.failedToCreateDirectory(error)
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            try? fileManager.removeItem(at: destinationURL)
        }

        let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            throw StorageError.failedToCopyExtension(error)
        }

        return (destinationURL, identifier)
    }

    public func removeExtension(identifier: String) throws {
        let path = extensionsDirectory.appendingPathComponent(identifier)
        guard fileManager.fileExists(atPath: path.path) else {
            return
        }

        do {
            try fileManager.removeItem(at: path)
        } catch {
            throw StorageError.failedToRemoveExtension(error)
        }
    }
}
