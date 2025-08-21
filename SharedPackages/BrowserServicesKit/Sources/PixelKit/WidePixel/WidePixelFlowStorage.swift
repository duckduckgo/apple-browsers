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
    func load<T: WidePixelData>(contextID: String) throws -> T
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
        let key = storageKey(T.self, contextID: data.contextData.id)

        do {
            let encoded = try JSONEncoder().encode(data)
            defaults.set(encoded, forKey: key)
        } catch {
            throw WidePixelError.serializationFailed(error)
        }
    }

    public func load<T: WidePixelData>(contextID: String) throws -> T {
        let key = storageKey(T.self, contextID: contextID)
        guard let data = defaults.data(forKey: key) else {
            throw WidePixelError.flowNotFound(pixelName: "\(T.pixelName) with context ID \(contextID)")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw WidePixelError.serializationFailed(error)
        }
    }

    public func update<T: WidePixelData>(_ data: T) throws {
        guard defaults.data(forKey: storageKey(T.self, contextID: data.contextData.id)) != nil else {
            throw WidePixelError.flowNotFound(pixelName: "\(T.pixelName) with context ID \(data.contextData.id)")
        }

        try save(data)
    }

    public func delete<T: WidePixelData>(_ data: T) {
        let key = storageKey(T.self, contextID: data.contextData.id)
        defaults.removeObject(forKey: key)
    }

    public func allWidePixels<T: WidePixelData>(for type: T.Type) -> [T] {
        let allKeys = Array(defaults.dictionaryRepresentation().keys)
        var results: [T] = []

        for key in allKeys {
            guard key.hasPrefix("\(T.pixelName).") else { continue }
            let contextID = String(key.dropFirst(T.pixelName.count + 1))
            guard !contextID.isEmpty, UUID(uuidString: contextID) != nil else { continue }
            if let decoded: T = (try? load(contextID: contextID)) {
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

    private func storageKey<T: WidePixelData>(_ type: T.Type, contextID: String) -> String {
        return "\(T.pixelName).\(contextID)"
    }

}
