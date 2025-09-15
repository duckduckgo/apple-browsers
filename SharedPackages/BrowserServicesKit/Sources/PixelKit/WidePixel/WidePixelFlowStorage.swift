//
//  WidePixelFlowStorage.swift
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

public protocol WidePixelStoring {
    func save<T: WidePixelData>(_ data: T) throws
    func load<T: WidePixelData>(globalID: String) throws -> T
    func update<T: WidePixelData>(_ data: T) throws
    func delete<T: WidePixelData>(_ data: T)
    func allWidePixels<T: WidePixelData>(for type: T.Type) -> [T]
    func percentile(for contextID: String) -> Float
}

public final class WidePixelUserDefaultsStorage: WidePixelStoring {
    public static let suiteName = "com.duckduckgo.wide-pixel.storage"

    private let defaults: UserDefaults

    public init(userDefaults: UserDefaults = UserDefaults(suiteName: WidePixelUserDefaultsStorage.suiteName) ?? .standard) {
        self.defaults = userDefaults
    }

    public func save<T: WidePixelData>(_ data: T) throws {
        let key = storageKey(T.self, globalID: data.globalData.id)

        do {
            let encoded = try JSONEncoder().encode(data)
            defaults.set(encoded, forKey: key)
        } catch {
            throw WidePixelError.serializationFailed(error)
        }
    }

    public func load<T: WidePixelData>(globalID: String) throws -> T {
        let key = storageKey(T.self, globalID: globalID)

        guard let data = defaults.data(forKey: key) else {
            throw WidePixelError.flowNotFound(pixelName: T.pixelName)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw WidePixelError.serializationFailed(error)
        }
    }

    public func update<T: WidePixelData>(_ data: T) throws {
        guard defaults.data(forKey: storageKey(T.self, globalID: data.globalData.id)) != nil else {
            throw WidePixelError.flowNotFound(pixelName: T.pixelName)
        }

        try save(data)
    }

    public func delete<T: WidePixelData>(_ data: T) {
        let key = storageKey(T.self, globalID: data.globalData.id)
        defaults.removeObject(forKey: key)
    }

    public func allWidePixels<T: WidePixelData>(for type: T.Type) -> [T] {
        let allKeys = Array(defaults.dictionaryRepresentation().keys)
        var results: [T] = []

        for key in allKeys {
            guard key.hasPrefix("\(T.pixelName).") else { continue }
            let globalID = String(key.dropFirst(T.pixelName.count + 1))
            guard !globalID.isEmpty, UUID(uuidString: globalID) != nil else { continue }
            if let decoded: T = (try? load(globalID: globalID)) {
                results.append(decoded)
            }
        }

        return results
    }

    public func percentile(for contextID: String) -> Float {
        let key = "\(contextID).percentile"

        if let stored = defaults.object(forKey: key) as? Float {
            return stored
        }

        let value = Float.random(in: 0...1)
        defaults.set(value, forKey: key)

        return value
    }

    private func storageKey<T: WidePixelData>(_ type: T.Type, globalID: String) -> String {
        return "\(T.pixelName).\(globalID)"
    }

}
