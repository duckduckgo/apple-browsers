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
    func load<T: WidePixelData>(contextID: UUID) throws -> T
    func update<T: WidePixelData>(_ data: T) throws
    func clearContext(_ contextID: UUID)
    func removeAll()
    func getActiveFlowNames() -> [String]
    func firstContextID<T: WidePixelData>(for type: T.Type) -> UUID?
    func allFlowData<T: WidePixelData>(for type: T.Type) -> [T]
}

public final class WidePixelUserDefaultsStorage: WidePixelStoring {
    private let defaults: UserDefaults

    private struct Envelope: Codable {
        let featureDataJSON: Data
        let featureDataType: String
    }

    public init(userDefaults: UserDefaults) {
        self.defaults = userDefaults
    }

    public func save<T: WidePixelData>(_ data: T) throws {
        let key = storageKey(T.self, contextID: data.contextData.id)

        do {
            let envelope = Envelope(
                featureDataJSON: try JSONEncoder().encode(data),
                featureDataType: String(describing: T.self)
            )
            let encoded = try JSONEncoder().encode(envelope)
            defaults.set(encoded, forKey: key)
        } catch {
            throw WidePixelError.serializationFailed(error)
        }
    }

    public func load<T: WidePixelData>(contextID: UUID) throws -> T {
        let key = storageKey(T.self, contextID: contextID)

        guard let data = defaults.data(forKey: key) else {
            throw WidePixelError.flowNotFound(pixelName: "\(T.pixelName) with context ID \(contextID)")
        }

        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        let expected = String(describing: T.self)

        guard envelope.featureDataType == expected else {
            throw WidePixelError.typeMismatch(expected: expected, actual: envelope.featureDataType)
        }

        return try JSONDecoder().decode(T.self, from: envelope.featureDataJSON)
    }

    public func update<T: WidePixelData>(_ data: T) throws {
        guard defaults.data(forKey: storageKey(T.self, contextID: data.contextData.id)) != nil else {
            throw WidePixelError.flowNotFound(pixelName: "\(T.pixelName) with context ID \(data.contextData.id)")
        }

        try save(data)
    }

    public func clearContext(_ contextID: UUID) {
        let suffix = ".\(contextID.uuidString)"
        let allKeys = Array(defaults.dictionaryRepresentation().keys)
        for key in allKeys where key.hasSuffix(suffix) {
            defaults.removeObject(forKey: key)
        }
    }

    public func removeAll() {
        let allKeys = Array(defaults.dictionaryRepresentation().keys)
        for key in allKeys {
            let parts = key.components(separatedBy: ".")
            if parts.count == 2, UUID(uuidString: parts[1]) != nil {
                defaults.removeObject(forKey: key)
            }
        }
    }

    public func getActiveFlowNames() -> [String] {
        let allKeys = Array(defaults.dictionaryRepresentation().keys)
        var flowNames: Set<String> = []
        for key in allKeys {
            let parts = key.components(separatedBy: ".")
            if parts.count == 2, UUID(uuidString: parts[1]) != nil {
                flowNames.insert(parts[0])
            }
        }
        return Array(flowNames)
    }

    public func firstContextID<T: WidePixelData>(for type: T.Type) -> UUID? {
        let allKeys = Array(defaults.dictionaryRepresentation().keys)

        for key in allKeys {
            let parts = key.components(separatedBy: ".")
            if parts.count == 2 && parts[0] == T.pixelName, let uuid = UUID(uuidString: parts[1]) {
                return uuid
            }
        }

        return nil
    }

    public func allFlowData<T: WidePixelData>(for type: T.Type) -> [T] {
        let allKeys = Array(defaults.dictionaryRepresentation().keys)
        var results: [T] = []

        for key in allKeys {
            let parts = key.components(separatedBy: ".")
            if parts.count == 2 && parts[0] == T.pixelName, let uuid = UUID(uuidString: parts[1]),
               let decoded: T = try? load(contextID: uuid) {
                results.append(decoded)
            }
        }

        return results
    }

    private func storageKey<T: WidePixelData>(_ type: T.Type, contextID: UUID) -> String {
        return "\(T.pixelName).\(contextID.uuidString)"
    }
}
