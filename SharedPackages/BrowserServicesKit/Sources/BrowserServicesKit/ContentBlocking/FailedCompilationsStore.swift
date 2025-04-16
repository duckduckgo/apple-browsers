//
//  FailedCompilationsStore.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import Persistence

public struct FailedCompilationsStore: KeyValueStoring {

    private var userDefaults: UserDefaults? { UserDefaults(suiteName: "com.duckduckgo.app.failedCompilations") }

    public init() {}

    public func object(forKey defaultName: String) -> Any? { userDefaults?.object(forKey: defaultName) }
    public func set(_ value: Any?, forKey defaultName: String) { userDefaults?.set(value, forKey: defaultName) }
    public func removeObject(forKey defaultName: String) { userDefaults?.removeObject(forKey: defaultName) }

    private func counter(for component: ContentBlockerDebugEvents.Component) -> Int { object(forKey: component.rawValue) as? Int ?? 0 }

    func compilationFailed(for component: ContentBlockerDebugEvents.Component) {
        set(counter(for: component) + 1, forKey: component.rawValue)
    }

    public func cleanup() {
        for component in ContentBlockerDebugEvents.Component.allCases {
            removeObject(forKey: component.rawValue)
        }
    }

    public var hasAnyFailures: Bool { ContentBlockerDebugEvents.Component.allCases.contains { counter(for: $0) != 0 } }

    public var summary: [String: String] {
        Dictionary(uniqueKeysWithValues: ContentBlockerDebugEvents.Component.allCases.map { ($0.rawValue, String(counter(for: $0))) })
    }

}
