//
//  KeyValueStoring.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

/// Key-value store compatible with base UserDefaults API
/// - Important: Use this for non-critical data that is easily recoverable if lost due to access issues.
public protocol KeyValueStoring {

    func object(forKey defaultName: String) -> Any?
    func set(_ value: Any?, forKey defaultName: String)
    func removeObject(forKey defaultName: String)

}

/// Key-value store that throws an error in case of an issue.
/// Use this for scenarios that reliability is a must.
public protocol ThrowingKeyValueStoring {

    func object(forKey defaultName: String) throws -> Any?
    func set(_ value: Any?, forKey defaultName: String) throws
    func removeObject(forKey defaultName: String) throws

}

extension UserDefaults: KeyValueStoring { }
