//
//  MappingValidator.swift
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

enum MappingError: LocalizedError, Equatable {
    case nilValue(AnyKeyPath)
    case emptyValue(AnyKeyPath)
    case duplicateValue(AnyKeyPath)
    case invalidValue(AnyKeyPath)

    var errorDescription: String? {
        switch self {
        case let .nilValue(keyPath):
            return "Found nil value for \(keyPath)"
        case let .emptyValue(keyPath):
            return "Found empty value for \(keyPath)"
        case let .duplicateValue(keyPath):
            return "Found duplicate value for \(keyPath)"
        case let .invalidValue(keyPath):
            return "Found invalid value for \(keyPath)"
        }
    }
}

struct MappingValidator<Root> {
    private let root: Root

    init(root: Root) {
        self.root = root
    }

    func notEmpty<T: Collection>(_ keyPath: KeyPath<Root, T>) throws(MappingError) -> T {
        let value = root[keyPath: keyPath]
        guard !value.isEmpty else { throw .emptyValue(keyPath) }
        return value
    }

    func notEmpty<T: Collection>(_ value: T, keyPath: AnyKeyPath) throws(MappingError) -> T {
        guard !value.isEmpty else { throw .emptyValue(keyPath) }
        return value
    }

    func notNil<T>(_ keyPath: KeyPath<Root, T?>) throws(MappingError) -> T {
        guard let value = root[keyPath: keyPath] else { throw .nilValue(keyPath) }
        return value
    }

    func notNilOrEmpty<T: Collection>(_ keyPath: KeyPath<Root, T?>) throws(MappingError) -> T {
        let wrappedValue = try notNil(keyPath)
        return try notEmpty(wrappedValue, keyPath: keyPath)
    }

    func mapEnum<T, E: RawRepresentable>(_ keyPath: KeyPath<Root, T>, to enumType: E.Type) throws(MappingError) -> E where E.RawValue == T {
        let value = root[keyPath: keyPath]
        guard let result = E(rawValue: value) else { throw .invalidValue(keyPath) }
        return result
    }

    func compactMap<T, U>(_ keyPath: KeyPath<Root, T?>, _ transform: (T) throws(MappingError) -> U?) throws(MappingError) -> U {
        let wrappedValue = try notNil(keyPath)
        guard let mappedValue = try transform(wrappedValue) else { throw .invalidValue(keyPath) }
        return mappedValue
    }
}
