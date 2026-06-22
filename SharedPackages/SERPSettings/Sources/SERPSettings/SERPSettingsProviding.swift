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
import FoundationExtensions

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
    var keyValueStore: ThrowingKeyValueStoring? { get set }

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
    /// 1. Attempts to read data from the key-value store
    /// 2. Reports any errors through the event mapper
    /// 3. Returns the stored data as an encoded dictionary if successful
    ///
    /// - Returns: Encoded settings blob, or an empty JSON object if no data exists, or `nil` if an error occurs
    func getSERPSettings() -> Encodable? {
        do {
            if let stringData = try keyValueStore?.object(forKey: SERPSettingsConstants.serpSettingsStorage) as? String,
                let data = stringData.data(using: .utf8) {
                let dict = try JSONDecoder().decode([String: String].self, from: data)
                return dict
            } else {
                // First-time access: return empty JSON object
                return EmptyPayload()
            }
        } catch {
            eventMapper?.fire(.keyValueStoreReadError, error: error)
        }

        return nil
    }

    /// Stores SERP settings in a thread-safe manner.
    ///
    /// This default implementation:
    /// 1. Converts the settings dictionary to JSON string
    /// 2. Writes the data to the key-value store
    /// 3. Reports any errors through the event mapper
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
        do {
            let data = try JSONSerialization.data(withJSONObject: settings, options: [])
            let stringData = String(data: data, encoding: .utf8)
            do {
                try keyValueStore?.set(stringData, forKey: SERPSettingsConstants.serpSettingsStorage)
            } catch {
                eventMapper?.fire(.keyValueStoreWriteError, error: error)
            }
        } catch {
            eventMapper?.fire(.serializationFailed, error: error)
        }
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

    // MARK: - Per-key native-originated access

    /// Reads a single SERP setting value from the stored blob.
    ///
    /// - Parameter key: The SERP setting key (e.g. `SERPSettingsConstants.searchAssistKey`).
    /// - Returns: The stored value, or `nil` if the key is absent.
    func serpSettingValue(forKey key: String) -> String? {
        return readSERPSettingsDictionary()?[key]
    }

    /// Writes a single SERP setting value into the stored blob, merging with existing keys.
    ///
    /// Passing `nil` removes the key. This is the native-originated write path: it merges into
    /// the existing blob so it never clobbers sibling keys, and is deliberately separate from
    /// `storeSERPSettings(settings:)` (the SERP full-snapshot replace path).
    ///
    /// - Parameters:
    ///   - value: The value to store, or `nil` to remove the key.
    ///   - key: The SERP setting key.
    func setSERPSetting(_ value: String?, forKey key: String) {
        var dictionary = readSERPSettingsDictionary() ?? [:]
        if let value {
            dictionary[key] = value
        } else {
            dictionary.removeValue(forKey: key)
        }
        // Broadcast only on a successful write, so any open SERP reflects the change (any instance).
        if writeSERPSettingsDictionary(dictionary) {
            NotificationCenter.default.post(name: .serpSettingsDidChange, object: nil)
        }
    }

    /// Builds the full snapshot of every native-synced SERP setting at its current effective value.
    ///
    /// Used for the native → SERP push: the SERP reconciles against this full snapshot, so every
    /// key is present (including those left at their default).
    func currentNativeSettingsSnapshot() -> [String: String] {
        return [
            SERPSettingsConstants.searchAssistKey: searchAssistFrequency.rawValue,
            SERPSettingsConstants.hideAIGeneratedImagesKey: HideAIGeneratedImages.rawValue(forHidden: hideAIGeneratedImages)
        ]
    }

    /// Search Assist (`kbe`) frequency, backed by native storage.
    ///
    /// Reads fall back to `SearchAssistFrequency.defaultValue` when the key is absent. Setting the
    /// default removes the key, mirroring the SERP (which omits defaults) so the two stay consistent.
    var searchAssistFrequency: SearchAssistFrequency {
        get {
            guard let rawValue = serpSettingValue(forKey: SERPSettingsConstants.searchAssistKey),
                  let frequency = SearchAssistFrequency(rawValue: rawValue) else {
                return .defaultValue
            }
            return frequency
        }
        set {
            let value = newValue == .defaultValue ? nil : newValue.rawValue
            setSERPSetting(value, forKey: SERPSettingsConstants.searchAssistKey)
        }
    }

    /// Whether AI-generated images are hidden (`kbj`), backed by native storage.
    ///
    /// Reads fall back to `HideAIGeneratedImages.defaultValue` when the key is absent. Setting the
    /// default removes the key.
    var hideAIGeneratedImages: Bool {
        get {
            guard let rawValue = serpSettingValue(forKey: SERPSettingsConstants.hideAIGeneratedImagesKey),
                  let hidden = HideAIGeneratedImages.isHidden(fromRawValue: rawValue) else {
                return HideAIGeneratedImages.defaultValue
            }
            return hidden
        }
        set {
            let value = newValue == HideAIGeneratedImages.defaultValue ? nil : HideAIGeneratedImages.rawValue(forHidden: newValue)
            setSERPSetting(value, forKey: SERPSettingsConstants.hideAIGeneratedImagesKey)
        }
    }

    // MARK: - Blob read/write helpers

    private func readSERPSettingsDictionary() -> [String: String]? {
        do {
            guard let stringData = try keyValueStore?.object(forKey: SERPSettingsConstants.serpSettingsStorage) as? String,
                  let data = stringData.data(using: .utf8) else {
                return nil
            }
            return try JSONDecoder().decode([String: String].self, from: data)
        } catch {
            eventMapper?.fire(.keyValueStoreReadError, error: error)
            return nil
        }
    }

    // Returns true if the blob was written; false if encoding or the store write failed.
    private func writeSERPSettingsDictionary(_ dictionary: [String: String]) -> Bool {
        do {
            let data = try JSONEncoder().encode(dictionary)
            guard let stringData = String(data: data, encoding: .utf8) else { return false }
            do {
                try keyValueStore?.set(stringData, forKey: SERPSettingsConstants.serpSettingsStorage)
                return true
            } catch {
                eventMapper?.fire(.keyValueStoreWriteError, error: error)
                return false
            }
        } catch {
            eventMapper?.fire(.serializationFailed, error: error)
            return false
        }
    }
}

/// Internal for testing purposes
struct EmptyPayload: Codable {
    let noNativeSettings: Bool

    init(noNativeSettings: Bool = true) {
        self.noNativeSettings = noNativeSettings
    }
}
