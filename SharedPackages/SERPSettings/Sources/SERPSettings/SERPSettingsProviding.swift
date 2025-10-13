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

public protocol SERPSettingsProviding {
    func buildMessageOriginRules() -> [HostnameMatchingRule]
    func isSERPSettingsFeatureOn() -> Bool
    func getSERPSettings() -> Encodable?
    func storeSERPSettings(settings: [String: Any])

    var keyValueStore: ThrowingKeyValueStoring { get }
    var settingsQueue: DispatchQueue { get }
    var eventMapper: EventMapping<SERPSettingsError>? { get }

#if os(iOS)
    var aiChatProvider: AIChatSettingsProvider { get }
#endif
#if os(macOS)
    var aiChatPreferencesStorage: AIChatPreferencesStorage { get }
#endif
}

public extension SERPSettingsProviding {

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

private struct JSONBlob: Encodable {
    let data: Data
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(data)
    }
}
