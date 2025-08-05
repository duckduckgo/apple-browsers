//
//  KeychainManager.swift
//  BrowserServicesKit
//
//  Created by Federico Cappelli on 05/08/2025.
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

public final class KeychainManager {

    public typealias KeychainAttributes = [CFString: Any]
    private let keychainOperations: KeychainOperationsProtocol
    private let attributes: KeychainAttributes
    private var writingBacklog: [String: Data] = [:]
    private var cancellables = Set<AnyCancellable>()

    public init(keychainOperations: KeychainOperationsProtocol = DefaultKeychainOperations(), attributes: KeychainAttributes) {
        self.keychainOperations = keychainOperations
        self.attributes = attributes
        self.setupKeychainAvailabilityNotifications()
    }

    func retrieveData(forKey key: String) throws -> Data? {
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

    func store(data: Data, forKey key: String) throws {

        writingBacklog[key] = nil // Removing the data from the writing backlog if present

        var query = attributes
        query[kSecAttrService] = key
        query[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        query[kSecValueData] = data

        let status = keychainOperations.add(query as CFDictionary, nil)

        switch status {
        case errSecSuccess:
            Logger.subscriptionKeychain.debug("Successfully added keychain item for \(key)")
            return
        case errSecDuplicateItem:
            Logger.subscriptionKeychain.debug("Keychain item exists, updating for \(key)")
            let updateStatus = updateData(data, forKey: key)
            guard updateStatus == errSecSuccess else {
                Logger.subscriptionKeychain.error("Failed to update keychain item: \(updateStatus)")
                throw AccountKeychainAccessError.keychainSaveFailure(updateStatus)
            }
            Logger.subscriptionKeychain.debug("Successfully updated keychain item for \(key)")
        case errSecNotAvailable:
            Logger.subscriptionKeychain.error("Failed to add keychain item: \(status.humanReadableDescription), adding data to writing queue")
            writingBacklog[key] = data
        default:
            Logger.subscriptionKeychain.error("Failed to add keychain item: \(status.humanReadableDescription)")
            throw AccountKeychainAccessError.keychainSaveFailure(status)
        }
    }

    private func updateData(_ data: Data, forKey key: String) -> OSStatus {

        writingBacklog[key] = nil // Removing the data from the writing backlog if present

        var query = attributes
        query[kSecAttrService] = key

        let newAttributes = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock
        ] as [CFString: Any]

        let status = keychainOperations.update(query as CFDictionary, newAttributes as CFDictionary)

        if status != errSecSuccess {
            Logger.subscriptionKeychain.error("SecItemUpdate failed with status: \(status.humanReadableDescription) for field: \(key)")
        }

        return status
    }

    func deleteItem(forKey key: String) throws {

        writingBacklog[key] = nil // Removing the data from the writing backlog if present

        var query = attributes
        query[kSecAttrService] = key

        let status = keychainOperations.delete(query as CFDictionary)

        if status == errSecSuccess {
            Logger.subscriptionKeychain.debug("Successfully deleted keychain item for \(key)")
        } else if status == errSecItemNotFound {
            Logger.subscriptionKeychain.debug("Keychain item not found for deletion: \(key)")
        } else {
            Logger.subscriptionKeychain.error("Failed to delete keychain item: \(status.humanReadableDescription)")
            throw AccountKeychainAccessError.keychainDeleteFailure(status)
        }
    }
    
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
        
        Logger.subscriptionKeychain.debug("KeychainManager: Set up iOS keychain availability notifications")
        
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
        
        Logger.subscriptionKeychain.debug("KeychainManager: Set up macOS keychain availability notifications")
        
        #else
        Logger.subscriptionKeychain.info("KeychainManager: Keychain notifications not supported on this platform")
        #endif
    }
    
    private func processWritingBacklog() {
        guard !writingBacklog.isEmpty else { return }
        
        Logger.subscriptionKeychain.debug("KeychainManager: Processing writing backlog with \(self.writingBacklog.count) items")
        
        let backlogCopy = writingBacklog
        var processedSuccessfully = 0
        var failed = 0
        
        for (key, data) in backlogCopy {
            do {
                try store(data: data, forKey: key)
                processedSuccessfully += 1
                Logger.subscriptionKeychain.debug("KeychainManager: Successfully processed backlog item for key: \(key)")
            } catch {
                failed += 1
                // Don't log individual failures at error level to avoid spam
                Logger.subscriptionKeychain.debug("KeychainManager: Failed to process backlog item for key \(key): \(error)")
            }
        }
        
        if processedSuccessfully > 0 {
            Logger.subscriptionKeychain.info("KeychainManager: Successfully processed \(processedSuccessfully) backlog items")
        }
        
        if failed > 0 {
            Logger.subscriptionKeychain.error("KeychainManager: Failed to process \(failed) backlog items")
        }
    }
    
    deinit {
        cancellables.removeAll()
        Logger.subscriptionKeychain.debug("KeychainManager: Cancelled keychain availability notification subscriptions")
        
        if !writingBacklog.isEmpty {
            Logger.subscriptionKeychain.warning("KeychainManager: Deallocating with \(writingBacklog.count) unprocessed backlog items")
        }
    }
}
