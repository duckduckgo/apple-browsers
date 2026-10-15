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
import FoundationExtensions
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
/// - A self-scheduled, backed-off retry that runs only while the backlog is non-empty, for processes such as app
///   extensions that never receive the app lifecycle notifications
public final class KeychainManager: KeychainManaging {

    // MARK: - Types

    public enum Pixel: Equatable {
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
        static let maxBacklogRetryDelay: TimeInterval = 300
    }

    // MARK: - Properties

    private let keychainOperations: KeychainOperationsProviding
    private let attributes: KeychainAttributes
    private var writingBacklog: [String: Data] = [:]
    private var cancellables = Set<AnyCancellable>()
    private let accessQueue = DispatchQueue(label: Constants.accessQueueLabel)
    private let pixelHandler: SubscriptionPixelHandling
    private let initialBacklogRetryDelay: TimeInterval
    private var backlogRetryDelay: TimeInterval
    private var backlogRetryWorkItem: DispatchWorkItem?

    // MARK: - Initialization

    /// Initializes a new KeychainManager with the specified operations and attributes.
    /// 
    /// - Parameters:
    ///   - keychainOperations: The keychain operations provider (defaults to system keychain)
    ///   - attributes: Base keychain query attributes for all operations
    ///   - initialBacklogRetryDelay: Delay before the first scheduled backlog retry. It doubles after each retry that
    ///     leaves items queued, up to 5 minutes, and resets once the backlog is empty.
    public init(keychainOperations: KeychainOperationsProviding = DefaultKeychainOperations(),
                attributes: KeychainAttributes,
                pixelHandler: SubscriptionPixelHandling,
                initialBacklogRetryDelay: TimeInterval = 5) {
        self.keychainOperations = keychainOperations
        self.attributes = attributes
        self.pixelHandler = pixelHandler
        self.initialBacklogRetryDelay = initialBacklogRetryDelay
        self.backlogRetryDelay = initialBacklogRetryDelay
        self.setupKeychainAvailabilityNotifications()
    }

    // MARK: - Cleanup

    /// Cleans up resources when the KeychainManager is deallocated.
    ///
    /// Cancels notification subscriptions and warns about any unprocessed backlog items.
    deinit {
        backlogRetryWorkItem?.cancel()
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

    /// - Parameter isBacklogRetry: `true` when a backlog drain re-queues an entry that is still unwritable. That is not a new
    ///   failed write, so it is not counted. A new `store` that fails is always counted, even if its key is already queued.
    private func addToWritingBacklog(_ data: Data, forKey key: String, isBacklogRetry: Bool) {
        writingBacklog[key] = data
        if !isBacklogRetry {
            pixelHandler.handle(pixel: .dataAddedToTheBacklog)
        }
        scheduleBacklogRetryIfNeeded()
    }

    private func removeFromWritingBacklog(forKey key: String) {
        writingBacklog[key] = nil
        if writingBacklog.isEmpty {
            cancelBacklogRetry()
        }
    }

    // MARK: - Scheduled Backlog Retry

    /// Schedules a single backlog retry on `accessQueue`, unless one is already pending. Must be called on `accessQueue`.
    ///
    /// Nothing is scheduled while the backlog is empty, so this costs nothing in the common case. A retry that leaves
    /// items queued re-queues them, which schedules the next retry with the doubled delay.
    private func scheduleBacklogRetryIfNeeded() {
        guard !writingBacklog.isEmpty, backlogRetryWorkItem == nil else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.backlogRetryWorkItem = nil
            self.backlogRetryDelay = min(self.backlogRetryDelay * 2, Constants.maxBacklogRetryDelay)
            self.processWritingBacklog()
        }
        backlogRetryWorkItem = workItem
        Logger.keychainManager.log("Scheduling writing backlog retry in \(self.backlogRetryDelay, privacy: .public)s")
        accessQueue.asyncAfter(deadline: .now() + backlogRetryDelay, execute: workItem)
    }

    /// Cancels any pending backlog retry and resets the back-off. Must be called on `accessQueue`.
    private func cancelBacklogRetry() {
        backlogRetryWorkItem?.cancel()
        backlogRetryWorkItem = nil
        backlogRetryDelay = initialBacklogRetryDelay
    }

    /// Whether a store attempt actually landed in the keychain or merely got (re-)queued because the keychain is still unavailable.
    private enum StoreOutcome {
        case written
        case requeued
    }

    @discardableResult
    private func internalStore(data: Data, forKey key: String, isBacklogRetry: Bool = false) throws -> StoreOutcome {
        var query = attributes
        query[kSecAttrService] = key
        query[kSecAttrAccessible] = Constants.keychainAccessibilityLevel
        query[kSecValueData] = data

        let status = keychainOperations.add(query as CFDictionary, nil)

        switch status {
        case errSecSuccess:
            removeFromWritingBacklog(forKey: key)
            Logger.keychainManager.log("Successfully added keychain item for \(key, privacy: .public)")
            return .written
        case errSecDuplicateItem:
            Logger.keychainManager.log("Keychain item exists, updating for \(key, privacy: .public)")
            return try updateData(data, forKey: key, isBacklogRetry: isBacklogRetry)
        case errSecNotAvailable,
        errSecInteractionNotAllowed:
            Logger.keychainManager.error("Failed to add keychain item: \(status.humanReadableDescription, privacy: .public), adding data to writing queue")
            addToWritingBacklog(data, forKey: key, isBacklogRetry: isBacklogRetry)
            return .requeued
        default:
            removeFromWritingBacklog(forKey: key)
            Logger.keychainManager.error("Failed to add keychain item: \(status.humanReadableDescription, privacy: .public)")
            throw AccountKeychainAccessError.keychainSaveFailure(status)
        }
    }

    /// Updates existing keychain data for the specified key.
    ///
    /// - Parameters:
    ///   - data: The new data to store
    ///   - key: The unique identifier for the keychain item
    ///   - isBacklogRetry: Whether this write is a backlog drain retry rather than a new write
    /// - Returns: Whether the update actually landed or was queued for retry
    @discardableResult
    private func updateData(_ data: Data, forKey key: String, isBacklogRetry: Bool) throws -> StoreOutcome {
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
            return .written
        case errSecNotAvailable,
        errSecInteractionNotAllowed:
            Logger.keychainManager.error("Failed to update keychain item: \(status.humanReadableDescription, privacy: .public), adding data to writing queue")
            addToWritingBacklog(data, forKey: key, isBacklogRetry: isBacklogRetry)
            return .requeued
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
    /// This method is called when keychain availability notifications or, as best effort, when app foreground and background notifications are received,
    /// when a read finds the keychain available, and by the scheduled backlog retry.
    private func processWritingBacklog() {
        guard !writingBacklog.isEmpty else { return }

        Logger.keychainManager.log("Processing writing backlog with \(self.writingBacklog.count, privacy: .public) items")

        let backlogCopy = writingBacklog
        var processedSuccessfully = 0
        var stillPending = 0
        var failed = 0

        for (key, data) in backlogCopy {
            do {
                switch try internalStore(data: data, forKey: key, isBacklogRetry: true) {
                case .written:
                    processedSuccessfully += 1
                    Logger.keychainManager.log("Successfully processed backlog item for key: \(key, privacy: .public)")
                case .requeued:
                    // Still unavailable: internalStore already re-added it to the backlog. Not a
                    // success (nothing was written) and not a failure (no permanent error) - just
                    // still waiting, so it must not count toward either pixel.
                    stillPending += 1
                }
            } catch {
                failed += 1
                Logger.keychainManager.error("Failed to process backlog item for key \(key, privacy: .public): \(error, privacy: .public)")
            }
        }

        if stillPending > 0 {
            Logger.keychainManager.log("\(stillPending, privacy: .public) backlog items still unavailable, left queued")
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
