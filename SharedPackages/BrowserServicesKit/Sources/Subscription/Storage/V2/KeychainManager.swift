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
    private static var subscriptionSubsystem = "Subscription"
    static var keychainManager = { Logger(subsystem: Self.subscriptionSubsystem, category: "KeychainManager") }()
}

/// A thread-safe keychain manager that handles secure storage operations with automatic retry capabilities.
/// 
/// This manager provides:
/// - Thread-safe access to keychain operations via dispatch queue
/// - Automatic retry mechanism for operations that fail when keychain is unavailable
/// - Cross-platform notification handling for keychain availability
public final class KeychainManager {

    // MARK: - Types

    public typealias KeychainAttributes = [CFString: Any]

    // MARK: - Constants

    private enum Constants {
        static let accessQueueLabel = "keychain.subscription.access"
        static let keychainAccessibilityLevel = kSecAttrAccessibleAfterFirstUnlock
    }

    // MARK: - Properties

    private let keychainOperations: KeychainOperationsProtocol
    private let attributes: KeychainAttributes
    private var writingBacklog: [String: Data] = [:]
    private var cancellables = Set<AnyCancellable>()
    private let accessQueue = DispatchQueue(label: Constants.accessQueueLabel)

    // MARK: - Initialization

    /// Initializes a new KeychainManager with the specified operations and attributes.
    /// 
    /// - Parameters:
    ///   - keychainOperations: The keychain operations provider (defaults to system keychain)
    ///   - attributes: Base keychain query attributes for all operations
    public init(keychainOperations: KeychainOperationsProtocol = DefaultKeychainOperations(),
                attributes: KeychainAttributes) {
        self.keychainOperations = keychainOperations
        self.attributes = attributes
        self.setupKeychainAvailabilityNotifications()
    }

    // MARK: - Public API

    /// Retrieves data from the keychain for the specified key.
    /// 
    /// This method first checks the writing backlog for any pending data, then queries the keychain.
    /// 
    /// - Parameter key: The unique identifier for the keychain item
    /// - Returns: The stored data, or nil if not found
    /// - Throws: `AccountKeychainAccessError` if retrieval fails
    public func retrieveData(forKey key: String) throws -> Data? {
        return try accessQueue.sync {

            if let dataFromBacklog = self.writingBacklog[key] {
                Logger.keychainManager.debug("Data for key \(key) retrieved from writing backlog")
                return dataFromBacklog
            }

            var query = attributes
            query[kSecAttrService] = key
            query[kSecMatchLimit] = kSecMatchLimitOne
            query[kSecReturnData] = true

            var item: CFTypeRef?
            let status = keychainOperations.copyMatching(query as CFDictionary, &item)

            if status == errSecSuccess {
                if let existingItem = item as? Data {
                    return existingItem
                } else {
                    throw AccountKeychainAccessError.failedToDecodeKeychainData
                }
            } else if status == errSecItemNotFound {
                return nil
            } else {
                throw AccountKeychainAccessError.keychainLookupFailure(status)
            }
        }
    }

    /// Stores data in the keychain for the specified key.
    /// 
    /// If the keychain is unavailable, the data is queued in a writing backlog and will be
    /// automatically retried when the keychain becomes available.
    /// 
    /// - Parameters:
    ///   - data: The data to store securely
    ///   - key: The unique identifier for the keychain item
    /// - Throws: `AccountKeychainAccessError` if storage fails
    public func store(data: Data, forKey key: String) throws {
        try accessQueue.sync {

            var query = attributes
            query[kSecAttrService] = key
            query[kSecAttrAccessible] = Constants.keychainAccessibilityLevel
            query[kSecValueData] = data

            let status = keychainOperations.add(query as CFDictionary, nil)

            switch status {
            case errSecSuccess:
                writingBacklog[key] = nil // Removing the data from the writing backlog if present
                Logger.keychainManager.debug("Successfully added keychain item for \(key)")
                return
            case errSecDuplicateItem:
                Logger.keychainManager.debug("Keychain item exists, updating for \(key)")
                let updateStatus = updateData(data, forKey: key)
                guard updateStatus == errSecSuccess else {
                    throw AccountKeychainAccessError.keychainSaveFailure(updateStatus)
                }
            case errSecNotAvailable:
                Logger.keychainManager.error("Failed to add keychain item: \(status.humanReadableDescription), adding data to writing queue")
                writingBacklog[key] = data
            default:
                Logger.keychainManager.error("Failed to add keychain item: \(status.humanReadableDescription)")
                throw AccountKeychainAccessError.keychainSaveFailure(status)
            }
        }
    }

    /// Deletes a keychain item for the specified key.
    ///
    /// Also removes any pending data from the writing backlog.
    ///
    /// - Parameter key: The unique identifier for the keychain item to delete
    /// - Throws: `AccountKeychainAccessError` if deletion fails
    public func deleteItem(forKey key: String) throws {
        return try accessQueue.sync {
            writingBacklog[key] = nil // Removing the data from the writing backlog if present

            var query = attributes
            query[kSecAttrService] = key

            let status = keychainOperations.delete(query as CFDictionary)

            switch status {
            case errSecSuccess:
                Logger.keychainManager.debug("Successfully deleted keychain item for \(key)")
            case errSecItemNotFound:
                Logger.keychainManager.debug("Keychain item not found for deletion: \(key)")
            default:
                Logger.keychainManager.error("Failed to delete keychain item: \(status.humanReadableDescription)")
                throw AccountKeychainAccessError.keychainDeleteFailure(status)
            }
        }
    }

    // MARK: - Private Helpers

    /// Updates existing keychain data for the specified key.
    /// 
    /// - Parameters:
    ///   - data: The new data to store
    ///   - key: The unique identifier for the keychain item
    /// - Returns: OSStatus indicating success or failure
    private func updateData(_ data: Data, forKey key: String) -> OSStatus {
        var query = attributes
        query[kSecAttrService] = key

        let newAttributes = [
            kSecValueData: data,
            kSecAttrAccessible: Constants.keychainAccessibilityLevel
        ] as [CFString: Any]

        let status = keychainOperations.update(query as CFDictionary, newAttributes as CFDictionary)

        switch status {
        case errSecSuccess:
            writingBacklog[key] = nil // Removing the data from the writing backlog if present
            Logger.keychainManager.debug("Successfully updated keychain item for \(key)")
        default:
            Logger.keychainManager.error("SecItemUpdate failed with status: \(status.humanReadableDescription) for field: \(key)")
        }
        return status
    }

    // MARK: - Notification Handling

    /// Sets up platform-specific notifications to detect when the keychain becomes available.
    /// 
    /// This enables automatic retry of operations that were queued when the keychain was unavailable.
    private func setupKeychainAvailabilityNotifications() {
        #if canImport(UIKit)
        // On iOS, listen for app becoming active and protected data becoming available
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.processWritingBacklog()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)
            .sink { [weak self] _ in
                self?.processWritingBacklog()
            }
            .store(in: &cancellables)

        Logger.keychainManager.debug("KeychainManager: Set up iOS keychain availability notifications")

        #elseif canImport(AppKit)
        // On macOS, listen for app becoming active and workspace session becoming active
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.processWritingBacklog()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSWorkspace.sessionDidBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.processWritingBacklog()
            }
            .store(in: &cancellables)

        Logger.keychainManager.debug("KeychainManager: Set up macOS keychain availability notifications")

        #else
        Logger.keychainManager.info("KeychainManager: Keychain notifications not supported on this platform")
        #endif
    }

    /// Processes all items in the writing backlog by attempting to store them in the keychain.
    /// 
    /// This method is called when keychain availability notifications are received.
    /// It provides detailed logging of success and failure counts.
    private func processWritingBacklog() {
        guard !writingBacklog.isEmpty else { return }

        Logger.keychainManager.debug("KeychainManager: Processing writing backlog with \(self.writingBacklog.count) items")

        let backlogCopy = writingBacklog
        var processedSuccessfully = 0
        var failed = 0

        for (key, data) in backlogCopy {
            do {
                try store(data: data, forKey: key)
                processedSuccessfully += 1
                Logger.keychainManager.debug("KeychainManager: Successfully processed backlog item for key: \(key)")
            } catch {
                failed += 1
                // Don't log individual failures at error level to avoid spam
                Logger.keychainManager.debug("KeychainManager: Failed to process backlog item for key \(key): \(error)")
            }
        }

        if processedSuccessfully > 0 {
            Logger.keychainManager.info("KeychainManager: Successfully processed \(processedSuccessfully) backlog items")
        }

        if failed > 0 {
            Logger.keychainManager.error("KeychainManager: Failed to process \(failed) backlog items")
        }
    }

    // MARK: - Cleanup

    /// Cleans up resources when the KeychainManager is deallocated.
    /// 
    /// Cancels notification subscriptions and warns about any unprocessed backlog items.
    deinit {
        cancellables.removeAll()
        Logger.keychainManager.debug("KeychainManager: Cancelled keychain availability notification subscriptions")

        if !writingBacklog.isEmpty {
            Logger.keychainManager.warning("KeychainManager: Deallocating with \(self.writingBacklog.count) unprocessed backlog items")
        }
    }
}
