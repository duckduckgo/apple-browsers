//
//  DetectorData.swift
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

public struct DetectorData {
    public let rawData: [String: Any]

    public init(from dict: [String: Any]) {
        self.rawData = dict
    }

    public func flattenedMetrics(includedProperties: Set<String> = ["detected", "results"]) -> [String: String] {
        var result: [String: String] = [:]

        for (detectorKey, detectorValue) in rawData {
            guard let detectorDict = detectorValue as? [String: Any] else {
                continue
            }

            for (propertyKey, propertyValue) in detectorDict {
                guard includedProperties.contains(propertyKey) else {
                    continue
                }

                let flattenedKey = "\(detectorKey).\(propertyKey)"
                let stringValue = stringValue(from: propertyValue)
                result[flattenedKey] = stringValue
            }
        }

        return result
    }

    private func stringValue(from value: Any) -> String {
        if let boolValue = value as? Bool {
            return boolValue.description
        } else if let stringValue = value as? String {
            return stringValue
        } else if let numberValue = value as? NSNumber {
            return numberValue.stringValue
        } else if let arrayValue = value as? [Any] {
            if arrayValue.isEmpty {
                return ""
            }
            return arrayValue.map { stringValue(from: $0) }.joined(separator: ",")
        } else if let dictValue = value as? [String: Any] {
            if let jsonData = try? JSONSerialization.data(withJSONObject: dictValue),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
            return String(describing: value)
        } else {
            return String(describing: value)
        }
    }
}
