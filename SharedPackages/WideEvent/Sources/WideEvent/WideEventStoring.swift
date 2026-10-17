//
//  WideEventStoring.swift
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

public protocol WideEventStoring {
    func save<T: WideEventData>(_ data: T) throws
    func load<T: WideEventData>(globalID: String) throws -> T
    func update<T: WideEventData>(_ data: T) throws
    func delete<T: WideEventData>(_ data: T)
    func allWideEvents<T: WideEventData>(for type: T.Type) -> [T]

    func lastSentTimestamp(for eventType: String) -> Date?
    func recordSentTimestamp(for eventType: String, date: Date)
}

public final class WideEventUserDefaultsStorage: WideEventStoring {
    public static let suiteName = "com.duckduckgo.wide-pixel.storage"

    private let defaults: UserDefaults

    public init(userDefaults: UserDefaults = UserDefaults(suiteName: WideEventUserDefaultsStorage.suiteName) ?? .standard) {
        self.defaults = userDefaults
    }

    public func save<T: WideEventData>(_ data: T) throws {
        let key = storageKey(T.self, globalID: data.globalData.id)

        do {
            let encoded = try JSONEncoder().encode(data)
            defaults.set(encoded, forKey: key)
        } catch {
            throw WideEventError.serializationFailed(error)
        }
    }

    public func load<T: WideEventData>(globalID: String) throws -> T {
        let key = storageKey(T.self, globalID: globalID)

        guard let data = defaults.data(forKey: key) else {
            throw WideEventError.flowNotFound(pixelName: T.metadata.pixelName)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw WideEventError.serializationFailed(error)
        }
    }

    public func update<T: WideEventData>(_ data: T) throws {
        guard defaults.data(forKey: storageKey(T.self, globalID: data.globalData.id)) != nil else {
            throw WideEventError.flowNotFound(pixelName: T.metadata.pixelName)
        }

        try save(data)
    }

    public func delete<T: WideEventData>(_ data: T) {
        let key = storageKey(T.self, globalID: data.globalData.id)
        defaults.removeObject(forKey: key)
    }

    public func allWideEvents<T: WideEventData>(for type: T.Type) -> [T] {
        let allKeys = Array(defaults.dictionaryRepresentation().keys)
        var results: [T] = []

        for key in allKeys {
            guard key.hasPrefix("\(T.metadata.pixelName).") else { continue }
            let globalID = String(key.dropFirst(T.metadata.pixelName.count + 1))
            guard !globalID.isEmpty, UUID(uuidString: globalID) != nil else { continue }
            if let decoded: T = (try? load(globalID: globalID)) {
                results.append(decoded)
            }
        }

        return results
    }

    private func storageKey<T: WideEventData>(_ type: T.Type, globalID: String) -> String {
        return "\(T.metadata.pixelName).\(globalID)"
    }

    // MARK: - Daily Occurrence Tracking

    public func lastSentTimestamp(for eventType: String) -> Date? {
        let key = lastSentKey(for: eventType)
        return defaults.object(forKey: key) as? Date
    }

    public func recordSentTimestamp(for eventType: String, date: Date) {
        let key = lastSentKey(for: eventType)
        defaults.set(date, forKey: key)
    }

    private func lastSentKey(for eventType: String) -> String {
        return "last_sent.\(eventType)"
    }

}
