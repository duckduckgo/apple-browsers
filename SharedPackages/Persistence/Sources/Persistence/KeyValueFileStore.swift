//
//  KeyValueFileStore.swift
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

// Basic Key-Value store using file as a persistence.
// Supports Data,
//
// Limitations:
//   - Sharing same file between processes is currently not supported (need to add dispatch source for monitoring such events)
//   - No Codable support but you have Data.
public class KeyValueFileStore: ThrowingKeyValueStoring {

    enum Error: Swift.Error {
        case readFailure(Swift.Error)
        case writeFailure(Swift.Error)
        case invalidFormat
        case fileAlreadyInUse
    }

    private let location: URL
    private let name: String
    private let writeOptions: Data.WritingOptions

    private var internalRepresentation: [String: Any]?
    private let lock = NSLock()

    public init(location: URL, name: String, writeOptions: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) throws {
        self.location = location
        self.name = name
        self.writeOptions = writeOptions

        try Self.openedFiles.claim(fileURL, owner: ObjectIdentifier(self))
    }

    deinit {
        Self.openedFiles.release(fileURL, owner: ObjectIdentifier(self))
    }

    public var fileURL: URL {
        location.appending(name)
    }

    private func persist(dictionary: [String: Any]) throws {
        let location = fileURL

        do {
            let data = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .binary, options: 0)
            try data.write(to: location, options: writeOptions)
        } catch {
            throw Error.writeFailure(error)
        }
    }

    private func load() throws -> [String: Any] {
        let location = fileURL

        do {
            let data = try Data(contentsOf: location)
            guard let dictionary = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                throw Error.invalidFormat
            }

            self.internalRepresentation = dictionary
            return dictionary
        } catch {
            let error = error as NSError
            let ue = error.userInfo[NSUnderlyingErrorKey] as? NSError

            if ue?.domain == NSPOSIXErrorDomain && ue?.code == 2 {
                // File not created yet
                self.internalRepresentation = [:]
                return [:]
            } else {
                throw Error.readFailure(error)
            }
        }
    }

    public func object(forKey key: String) throws -> Any? {
        lock.lock()
        defer {
            lock.unlock()
        }

        let internalRepresentation = try internalRepresentation ?? load()
        return internalRepresentation[key]
    }

    /// A snapshot of every key and value the store holds.
    ///
    /// Reads the whole file, so it is for bulk work such as a one-off migration rather than for
    /// routine access. Use `object(forKey:)` for a single value.
    public func allObjects() throws -> [String: Any] {
        lock.lock()
        defer {
            lock.unlock()
        }

        return try internalRepresentation ?? load()
    }

    public func set(_ value: Any?, forKey key: String) throws {
        lock.lock()
        defer {
            lock.unlock()
        }

        var dictionary = try internalRepresentation ?? load()
        dictionary[key] = value
        try persist(dictionary: dictionary)
        self.internalRepresentation = dictionary
    }

    public func removeObject(forKey key: String) throws {
        lock.lock()
        defer {
            lock.unlock()
        }

        var dictionary = try internalRepresentation ?? load()

        guard dictionary.removeValue(forKey: key) != nil else {
            return
        }
        try persist(dictionary: dictionary)
        self.internalRepresentation = dictionary
    }

    // Each process can open a file once. The lock covers both the lookup and insertion.
    private final class OpenFiles: @unchecked Sendable {
        private let lock = NSLock()
        private var owners: [URL: ObjectIdentifier] = [:]

        func claim(_ url: URL, owner: ObjectIdentifier) throws {
            try lock.withLock {
                guard owners[url] == nil else { throw Error.fileAlreadyInUse }
                owners[url] = owner
            }
        }

        func release(_ url: URL, owner: ObjectIdentifier? = nil) {
            lock.withLock {
                // A failed initializer or an explicitly relinquished store can deinitialize later.
                guard owner == nil || owners[url] == owner else { return }
                owners[url] = nil
            }
        }
    }

    private static let openedFiles = OpenFiles()

    // Call this to relinquish hold on a file used by an instance of a file store.
    // Use this only if you are sure that subsequent instantiation of KeyValueFileStore won't result in concurrent file modifications.
    static public func relinquish(fileURL: URL) {
        openedFiles.release(fileURL)
    }
}

extension KeyValueFileStore.Error: CustomNSError {

    public static var errorDomain: String {
        "Persistence"
    }

    /// The error code within the given domain.
    var errorCode: Int {
        switch self {
        case .readFailure:
            return 0
        case .writeFailure:
            return 1
        case .invalidFormat:
            return 2
        case .fileAlreadyInUse:
            return 3
        }
    }

    /// The user-info dictionary.
    var errorUserInfo: [String: Any] {
        switch self {
        case .readFailure(let error):
            return [NSUnderlyingErrorKey: error]
        case .writeFailure(let error):
            return [NSUnderlyingErrorKey: error]
        case .invalidFormat, .fileAlreadyInUse:
            return [:]
        }
    }
}
