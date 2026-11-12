//
//  AssistedOptOutSteps.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

public struct AssistedOptOutSteps: Equatable, Sendable {
    public let titles: [String]

    public init(titles: [String]) {
        self.titles = titles
    }

    public init(actions: [Action]) {
        var titles: [String] = []
        let labels = actions.flatMap(\.nestedActionObjects).compactMap { $0["step"] as? String }
        for label in labels where !titles.contains(label) {
            titles.append(label)
        }
        self.titles = titles
    }

    public func index(of action: Action) -> Int? {
        action.step.flatMap { titles.firstIndex(of: $0) }
    }
}

extension Action {
    /// This action's JSON object followed by every action nested under `actions`, depth first.
    var nestedActionObjects: [[String: Any]] {
        guard let json, let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return [] }
        return flattenedActionObjects(object)
    }
}

private func flattenedActionObjects(_ object: [String: Any]) -> [[String: Any]] {
    [object] + ((object["actions"] as? [[String: Any]])?.flatMap(flattenedActionObjects) ?? [])
}
