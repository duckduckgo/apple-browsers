//
//  SERPSettingsProviding.swift
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
import UserScript
import AIChat
import Persistence
import Common

/// Protocol defining the interface for SERP settings management.
///
/// This protocol establishes a contract between the SERP (Search Engine Results Page)
/// and native application settings storage. It enables bidirectional communication
/// where the SERP can persist user preferences natively, preventing settings loss
/// due to cookie clearing or storage limitations.
///
/// ## Architecture
///
/// The protocol supports:
/// - **Settings Persistence**: Store and retrieve SERP settings as JSON blobs
/// - **AI Chat Integration**: Query the state of AI features from native settings
/// - **Thread Safety**: All storage operations are serialized through a dedicated queue
/// - **Error Reporting**: Failures are reported through EventMapping for analytics
/// - **Feature Flagging**: Settings sync can be controlled via feature flags
///
/// ## Implementation Notes
///
/// Conforming types must provide:
/// - A key-value store for persistent storage
/// - A serial dispatch queue for thread-safe access
/// - Platform-specific AI chat preference providers
/// - Message origin rules for security validation
/// - Optional event mapper for error analytics
public protocol SERPSettingsProviding {

    /// Builds message origin rules for validating SERP communication.
    ///
    /// These rules define which hostnames are permitted to send settings messages
    /// to the native application, providing a security boundary.
    ///
    /// - Returns: An array of hostname matching rules, typically including duckduckgo.com
    func buildMessageOriginRules() -> [HostnameMatchingRule]

    /// Determines if SERP settings synchronization is enabled.
    ///
    /// This allows runtime control over the feature, typically through a feature flag
    /// or privacy configuration setting.
    ///
    /// - Returns: `true` if settings should be synchronized, `false` otherwise
    func isSERPSettingsFeatureOn() -> Bool

    /// Retrieves stored SERP settings.
    ///
    /// Settings are returned as an opaque encodable blob that can be sent back to the SERP.
    /// The internal format is JSON data wrapped in a JSONBlob encoder.
    ///
    /// - Returns: Encoded settings if available, or `nil` if no settings exist or an error occurs
    func getSERPSettings() -> Encodable?

    /// Stores SERP settings received from the web page.
    ///
    /// The SERP sends a complete snapshot of all non-default settings. This method
    /// replaces the entire stored settings blob with the new data.
    ///
    /// ## Storage Strategy
    ///
    /// Settings are stored as a JSON blob containing only non-default values from the SERP.
    /// This approach allows defaults to be updated on the SERP side without requiring
    /// native storage migration. When a setting is not present in the stored blob,
    /// the SERP uses its current default value.
    ///
    /// - Parameter settings: Dictionary of setting keys to values from the SERP
    func storeSERPSettings(settings: [String: Any])

    /// Key-value store for persistent settings storage.
    ///
    /// The store must support throwing operations and should provide persistent storage
    /// that survives app restarts. Typical implementations use UserDefaults or Keychain.
    var keyValueStore: ThrowingKeyValueStoring { get }

    /// Serial dispatch queue for thread-safe storage access.
    ///
    /// All read and write operations to the settings storage are serialized through
    /// this queue to prevent race conditions and ensure data consistency.
    var settingsQueue: DispatchQueue { get }

    /// Optional event mapper for reporting storage errors.
    ///
    /// When provided, storage errors are reported through this mapper for analytics
    /// and debugging. Platform-specific implementations translate errors to pixels.
    var eventMapper: EventMapping<SERPSettingsError>? { get }

#if os(iOS)
    /// iOS-specific AI chat settings provider.
    ///
    /// Provides the current state of AI chat features for iOS applications.
    var aiChatProvider: AIChatSettingsProvider { get }
#endif
#if os(macOS)
    /// macOS-specific AI chat preferences storage.
    ///
    /// Provides the current state of AI features for macOS applications.
    var aiChatPreferencesStorage: AIChatPreferencesStorage { get }
#endif
}

public extension SERPSettingsProviding {

    /// Retrieves stored SERP settings in a thread-safe manner.
    ///
    /// This default implementation:
    /// 1. Serializes access through the settings queue
    /// 2. Attempts to read data from the key-value store
    /// 3. Reports any errors through the event mapper
    /// 4. Returns data wrapped in a JSONBlob if successful
    ///
    /// - Returns: Encoded settings blob, or `nil` if no data exists or an error occurs
    func getSERPSettings() -> Encodable? {
        settingsQueue.sync {
            do {
                if let data = try keyValueStore.object(forKey: SERPSettingsConstants.serpSettingsStorage) as? Data {
                    return JSONBlob(data: data)
                }
            } catch {
                eventMapper?.fire(.keyValueStoreReadError, error: error)
            }

            return nil
        }
    }

    /// Stores SERP settings in a thread-safe manner.
    ///
    /// This default implementation:
    /// 1. Serializes access through the settings queue
    /// 2. Converts the settings dictionary to JSON data
    /// 3. Writes the data to the key-value store
    /// 4. Reports any errors through the event mapper
    ///
    /// ## Error Handling
    ///
    /// Two types of errors can occur:
    /// - **Serialization failures**: Reported as `.serializationFailed`
    /// - **Storage failures**: Reported as `.keyValueStoreWriteError`
    ///
    /// Errors are reported but do not throw, allowing the operation to fail gracefully.
    ///
    /// - Parameter settings: Complete dictionary of SERP settings to store
    func storeSERPSettings(settings: [String: Any]) {
        settingsQueue.sync {
            do {
                let data = try JSONSerialization.data(withJSONObject: settings, options: [])
                do {
                    try keyValueStore.set(data, forKey: SERPSettingsConstants.serpSettingsStorage)
                } catch {
                    eventMapper?.fire(.keyValueStoreWriteError, error: error)
                }
            } catch {
                eventMapper?.fire(.serializationFailed, error: error)
            }
        }
    }

    /// Helper method to convert a dictionary to encodable JSON.
    ///
    /// - Parameter dict: Dictionary to convert
    /// - Returns: JSONBlob if conversion succeeds, `nil` otherwise
    private func asEncodableJSON(_ dict: [String: Any]?) -> Encodable? {
        guard
            let dict,
            JSONSerialization.isValidJSONObject(dict),
            let data = try? JSONSerialization.data(withJSONObject: dict, options: [])
        else { return nil }
        return JSONBlob(data: data)
    }

#if os(iOS)
    var isAIChatEnabled: Bool {
        return aiChatProvider.isAIChatEnabled
    }
#elseif os(macOS)
    var isAIChatEnabled: Bool {
        return aiChatPreferencesStorage.isAIFeaturesEnabled
    }
#endif
}

/// Internal JSON blob encoder for settings data.
///
/// This struct wraps raw JSON data and implements Encodable to allow
/// the data to be returned through the UserScript messaging system.
struct JSONBlob: Encodable {
    let data: Data

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(data)
    }
}
