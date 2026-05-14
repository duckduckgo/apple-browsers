//
//  KeychainManager.swift
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
import os.log
import Common
import Combine

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public extension Logger {
    private static let subscriptionSubsystem = "Subscription"
    static let keychainManager = Logger(subsystem: Self.subscriptionSubsystem, category: "KeychainManager")
}

public protocol KeychainManaging {

    /// Retrieves data from the keychain for the specified key.
    ///
    /// This method first checks the writing backlog for any pending data, then queries the keychain.
    ///
    /// - Parameter key: The unique identifier for the keychain item
    /// - Returns: The stored data, or nil if not found
    /// - Throws: `AccountKeychainAccessError` if retrieval fails
    func retrieveData(forKey key: String) throws -> Data?

    /// Stores data in the keychain for the specified key.
    ///
    /// If the keychain is unavailable, the data is queued in a writing backlog and will be
    /// automatically retried when the keychain becomes available.
    ///
    /// - Parameters:
    ///   - data: The data to store securely
    ///   - key: The unique identifier for the keychain item
    /// - Throws: `AccountKeychainAccessError` if storage fails
    func store(data: Data, forKey key: String) throws

    /// Deletes a keychain item for the specified key.
    ///
    /// Also removes any pending data from the writing backlog.
    ///
    /// - Parameter key: The unique identifier for the keychain item to delete
    /// - Throws: `AccountKeychainAccessError` if deletion fails
    func deleteItem(forKey key: String) throws
}

/// A thread-safe keychain manager that handles secure storage operations with automatic retry capabilities.
/// 
/// This manager provides:
/// - Thread-safe access to keychain operations via dispatch queue
/// - Automatic retry mechanism for operations that fail when keychain is unavailable
/// - Cross-platform notification handling for keychain availability
public final class KeychainManager: KeychainManaging {

    // MARK: - Types

    public enum Pixel {
        case deallocatedWithBacklog
        case dataAddedToTheBacklog
        case dataWroteFromBacklog
        case failedToWriteDataFromBacklog
    }
    public typealias KeychainAttributes = [CFString: Any]

    // MARK: - Constants

    private enum Constants {
        static let accessQueueLabel = "keychain.subscription.access"
        static let keychainAccessibilityLevel = kSecAttrAccessibleAfterFirstUnlock
    }

    // MARK: - Properties

    private let keychainOperations: KeychainOperationsProviding
    private let attributes: KeychainAttributes
    private var writingBacklog: [String: Data] = [:]
    private var cancellables = Set<AnyCancellable>()
    private let accessQueue = DispatchQueue(label: Constants.accessQueueLabel)
    private let pixelHandler: SubscriptionPixelHandling

    // MARK: - Initialization

    /// Initializes a new KeychainManager with the specified operations and attributes.
    /// 
    /// - Parameters:
    ///   - keychainOperations: The keychain operations provider (defaults to system keychain)
    ///   - attributes: Base keychain query attributes for all operations
    public init(keychainOperations: KeychainOperationsProviding = DefaultKeychainOperations(),
                attributes: KeychainAttributes,
                pixelHandler: SubscriptionPixelHandling) {
        self.keychainOperations = keychainOperations
        self.attributes = attributes
        self.pixelHandler = pixelHandler
        self.setupKeychainAvailabilityNotifications()
    }

    // MARK: - Cleanup

    /// Cleans up resources when the KeychainManager is deallocated.
    ///
    /// Cancels notification subscriptions and warns about any unprocessed backlog items.
    deinit {
        cancellables.removeAll()
        if !writingBacklog.isEmpty {
            self.pixelHandler.handle(pixel: .deallocatedWithBacklog)
            Logger.keychainManager.error("Deallocating with \(self.writingBacklog.count, privacy: .public) unprocessed backlog items")
        }
    }

    // MARK: - Public API

    public func retrieveData(forKey key: String) throws -> Data? {
        return try accessQueue.sync {

            if isKeychainAvailable {
                // Trigger backlog processing for that contexts that can't rely on notifications for detecting keychain availability
                self.processWritingBacklog()
            } else if let dataFromBacklog = self.writingBacklog[key] {
                Logger.keychainManager.log("Data for key \(key, privacy: .public) retrieved from writing backlog")
                return dataFromBacklog
            }

            var query = attributes
            query[kSecAttrService] = key
            query[kSecMatchLimit] = kSecMatchLimitOne
            query[kSecReturnData] = true

            var item: CFTypeRef?
            let status = keychainOperations.copyMatching(query as CFDictionary, &item)

            switch status {
            case errSecSuccess:
                if let existingItem = item as? Data {
                    return existingItem
                } else {
                    throw AccountKeychainAccessError.failedToDecodeKeychainData
                }
            case errSecItemNotFound:
                return nil
            default:
                throw AccountKeychainAccessError.keychainLookupFailure(status)
            }
        }
    }

    public func store(data: Data, forKey key: String) throws {
        return try accessQueue.sync {
            try internalStore(data: data, forKey: key)
        }
    }

    public func deleteItem(forKey key: String) throws {
        return try accessQueue.sync {
            removeFromWritingBacklog(forKey: key)

            var query = attributes
            query[kSecAttrService] = key

            let status = keychainOperations.delete(query as CFDictionary)

            switch status {
            case errSecSuccess:
                Logger.keychainManager.log("Successfully deleted keychain item for \(key, privacy: .public)")
            case errSecItemNotFound:
                Logger.keychainManager.log("Keychain item not found for deletion: \(key, privacy: .public)")
            default:
                Logger.keychainManager.error("Failed to delete keychain item: \(status.humanReadableDescription, privacy: .public)")
                throw AccountKeychainAccessError.keychainDeleteFailure(status)
            }
        }
    }

    // MARK: - Private Helpers

    private var isKeychainAvailable: Bool {
        var query = attributes
        query[kSecAttrService] = "non existent"
        query[kSecMatchLimit] = kSecMatchLimitOne
        query[kSecReturnData] = true

        var item: CFTypeRef?
        let status = keychainOperations.copyMatching(query as CFDictionary, &item)
        return status == errSecItemNotFound
    }

    private func addToWritingBacklog(_ data: Data, forKey key: String) {
        writingBacklog[key] = data
        pixelHandler.handle(pixel: .dataAddedToTheBacklog)
    }

    private func removeFromWritingBacklog(forKey key: String) {
        writingBacklog[key] = nil
    }

    @discardableResult
    private func internalStore(data: Data, forKey key: String) throws -> OSStatus {
        var query = attributes
        query[kSecAttrService] = key
        query[kSecAttrAccessible] = Constants.keychainAccessibilityLevel
        query[kSecValueData] = data

        let status = keychainOperations.add(query as CFDictionary, nil)

        switch status {
        case errSecSuccess:
            removeFromWritingBacklog(forKey: key)
            Logger.keychainManager.log("Successfully added keychain item for \(key, privacy: .public)")
        case errSecDuplicateItem:
            Logger.keychainManager.log("Keychain item exists, updating for \(key, privacy: .public)")
            try updateData(data, forKey: key)
        case errSecNotAvailable,
        errSecInteractionNotAllowed:
            Logger.keychainManager.error("Failed to add keychain item: \(status.humanReadableDescription, privacy: .public), adding data to writing queue")
            addToWritingBacklog(data, forKey: key)
        default:
            removeFromWritingBacklog(forKey: key)
            Logger.keychainManager.error("Failed to add keychain item: \(status.humanReadableDescription, privacy: .public)")
            throw AccountKeychainAccessError.keychainSaveFailure(status)
        }
        return status
    }

    /// Updates existing keychain data for the specified key.
    /// 
    /// - Parameters:
    ///   - data: The new data to store
    ///   - key: The unique identifier for the keychain item
    /// - Returns: OSStatus indicating success or failure
    private func updateData(_ data: Data, forKey key: String) throws {
        var query = attributes
        query[kSecAttrService] = key

        let newAttributes = [
            kSecValueData: data,
            kSecAttrAccessible: Constants.keychainAccessibilityLevel
        ] as [CFString: Any]

        let status = keychainOperations.update(query as CFDictionary, newAttributes as CFDictionary)

        switch status {
        case errSecSuccess:
            removeFromWritingBacklog(forKey: key)
            Logger.keychainManager.log("Successfully updated keychain item for \(key, privacy: .public)")
        case errSecNotAvailable,
        errSecInteractionNotAllowed:
            Logger.keychainManager.error("Failed to update keychain item: \(status.humanReadableDescription, privacy: .public), adding data to writing queue")
            addToWritingBacklog(data, forKey: key)
        default:
            removeFromWritingBacklog(forKey: key)
            Logger.keychainManager.error("SecItemUpdate failed with status: \(status.humanReadableDescription, privacy: .public) for field: \(key)")
            throw AccountKeychainAccessError.keychainSaveFailure(status)
        }
    }

    // MARK: - Notification Handling

    /// Sets up platform-specific notifications to detect when the keychain becomes available, when the app goes in background or is terminated.
    /// This enables automatic retry of operations that were queued when the keychain was unavailable.
    private func setupKeychainAvailabilityNotifications() {
        Logger.keychainManager.log("Set up keychain availability and recovery notifications")

#if canImport(UIKit)
        Publishers.MergeMany(
            // Foreground notifications
            NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification),
            NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification),
            NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification),
            // Background notification
            NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification),
            // Termination notification
            NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)
        )
        .receive(on: accessQueue)
        .sink { [weak self] _ in
            self?.processWritingBacklog()
        }
        .store(in: &cancellables)
#elseif canImport(AppKit)
        Publishers.MergeMany(
            // Foreground notifications
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification),
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.sessionDidBecomeActiveNotification),
            // Background notification
            NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification),
            // Termination notification
            NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
        )
        .receive(on: accessQueue)
        .sink { [weak self] _ in
            self?.processWritingBacklog()
        }
        .store(in: &cancellables)
#else
        Logger.keychainManager.log("Keychain notifications not supported on this platform")
#endif
    }

    /// Processes all items in the writing backlog by attempting to store them in the keychain.
    /// This method is called when keychain availability notifications or, as best effort, when app foreground and background notifications are received.
    private func processWritingBacklog() {
        guard !writingBacklog.isEmpty else { return }

        Logger.keychainManager.log("Processing writing backlog with \(self.writingBacklog.count, privacy: .public) items")

        let backlogCopy = writingBacklog
        var processedSuccessfully = 0
        var failed = 0

        for (key, data) in backlogCopy {
            do {
                try internalStore(data: data, forKey: key)
                processedSuccessfully += 1
                Logger.keychainManager.log("Successfully processed backlog item for key: \(key, privacy: .public)")
            } catch {
                failed += 1
                Logger.keychainManager.error("Failed to process backlog item for key \(key, privacy: .public): \(error, privacy: .public)")
            }
        }

        if processedSuccessfully > 0 {
            Logger.keychainManager.log("Successfully processed \(processedSuccessfully, privacy: .public) backlog items")
            self.pixelHandler.handle(pixel: .dataWroteFromBacklog)
        }

        if failed > 0 {
            Logger.keychainManager.error("Failed to process \(failed, privacy: .public) backlog items")
            self.pixelHandler.handle(pixel: .failedToWriteDataFromBacklog)
        }
    }
}
