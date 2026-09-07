//
//  PixelRetryQueueFileStore.swift
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

import Foundation

/// JSON-file backed `PixelRetryQueueStoring`. A faithful port of iOS `DefaultPersistentPixelStorage`:
/// a serial file-access queue guards all reads/writes, decoded items are cached in memory, and the
/// queue is capped at `itemCountLimit` (oldest dropped first).
final class PixelRetryQueueFileStore: PixelRetryQueueStoring {

    public enum Constants {
        public static let fileName = "pixelkit-retry-queue.json"
        public static let itemCountLimit = 100
    }

    private let fileManager: FileManager
    private let fileName: String
    private let storageDirectory: URL
    private let itemCountLimit: Int

    private let fileAccessQueue = DispatchQueue(label: "PixelKit Retry Queue File Access Queue", qos: .utility)
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var cachedItems: [PixelRetryQueueItem]?

    private var fileURL: URL {
        storageDirectory.appendingPathComponent(fileName)
    }

    public init(fileManager: FileManager = .default,
                fileName: String = Constants.fileName,
                storageDirectory: URL? = nil,
                itemCountLimit: Int = Constants.itemCountLimit) {
        self.fileManager = fileManager
        self.fileName = fileName
        self.itemCountLimit = itemCountLimit

        if let storageDirectory {
            self.storageDirectory = storageDirectory
        } else if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            self.storageDirectory = appSupport
        } else {
            fatalError("Unable to locate application support directory")
        }
    }

    func append(_ newItems: [PixelRetryQueueItem]) throws {
        try fileAccessQueue.sync {
            var items = try readFromFileSystem()
            items.append(contentsOf: newItems)
            if items.count > itemCountLimit {
                items = Array(items.suffix(itemCountLimit))
            }
            try writeToFileSystem(items: items)
        }
    }

    func remove(itemsWithIDs ids: Set<UUID>) throws {
        try fileAccessQueue.sync {
            var items = try readFromFileSystem()
            items.removeAll { ids.contains($0.id) }
            try writeToFileSystem(items: items)
        }
    }

    func storedItems() throws -> [PixelRetryQueueItem] {
        try fileAccessQueue.sync {
            try readFromFileSystem()
        }
    }

    private func readFromFileSystem() throws -> [PixelRetryQueueItem] {
        dispatchPrecondition(condition: .onQueue(fileAccessQueue))

        if let cachedItems {
            return cachedItems
        }
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw PixelRetryQueueStorageError.readError(error)
        }

        do {
            let decoded = try decoder.decode([PixelRetryQueueItem].self, from: data)
            cachedItems = decoded
            return decoded
        } catch {
            throw PixelRetryQueueStorageError.decodingError(error)
        }
    }

    private func writeToFileSystem(items: [PixelRetryQueueItem]) throws {
        dispatchPrecondition(condition: .onQueue(fileAccessQueue))

        let data: Data
        do {
            data = try encoder.encode(items)
        } catch {
            throw PixelRetryQueueStorageError.encodingError(error)
        }

        do {
            try data.write(to: fileURL)
            cachedItems = items
        } catch {
            throw PixelRetryQueueStorageError.writeError(error)
        }
    }
}
