//
//  XCUIElementSnapshotExtension.swift
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

import XCTest

extension XCUIElementSnapshot {

    var title: String {
        ((self as? NSObject)?.value(forKey: "title") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var trimmedLabel: String {
        label.trimmingWhitespace()
    }

    var trimmedStringValue: String {
        (value as? String)?.trimmingWhitespace() ?? ""
    }

    func toDictionary(keys: [String] = ["elementType",
                                        "identifier",
                                        "label",
                                        "title",
                                        "value",
                                        "isEnabled",
                                        "frame"]) -> [String: Any] {
        var dict: [String: Any] = [:]

        // Add requested properties
        for key in keys {
            if key == "elementType" {
                dict[key] = elementType.description
            } else if let value = (self as! NSObject).value(forKey: key) {
                dict[key] = "\(value)"
            }
        }

        // Recurse on children
        dict["children"] = children.map { $0.toDictionary(keys: keys) }

        return dict
    }
}
