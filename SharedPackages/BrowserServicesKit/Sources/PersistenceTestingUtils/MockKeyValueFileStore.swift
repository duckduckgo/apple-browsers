//
//  MockKeyValueFileStore.swift
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

import Persistence

public class MockKeyValueFileStore: ThrowingKeyValueStoring {

    public var throwOnSet: Error?
    public var throwOnRead: Error?
    public var underlyingDict: [String: Any]

    public init(throwOnInit: Error? = nil,
                underlyingDict: [String: Any] = [:]) throws {
        if let throwOnInit {
            throw throwOnInit
        }

        self.underlyingDict = underlyingDict
    }

    public func object(forKey key: String) throws -> Any? {
        if let throwOnRead {
            throw throwOnRead
        }

        return underlyingDict[key]
    }

    public func set(_ value: Any?, forKey key: String) throws {
        if let throwOnSet {
            throw throwOnSet
        }

        underlyingDict[key] = value
    }

    public func removeObject(forKey key: String) throws {
        underlyingDict[key] = nil
    }
}
