//
//  CustomizeResponsesState.swift
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

public enum CustomizeResponsesStorageKey {
    public static let customization = "duckaiCustomization"
    public static let active = "duckaiCustomizationActive"
}

public struct CustomizeResponsesState: Equatable {

    public let hasCustomization: Bool
    public let subLabel: String?
    public let isActive: Bool

    public static let none = CustomizeResponsesState(hasCustomization: false, subLabel: nil, isActive: false)

    public init(hasCustomization: Bool, subLabel: String?, isActive: Bool) {
        self.hasCustomization = hasCustomization
        self.subLabel = subLabel
        self.isActive = isActive
    }

    public static func make(customizationValue: Any?,
                            activeValue: Any?,
                            clarifiesLabel: String,
                            maxSubLabelLength: Int = 15) -> CustomizeResponsesState {
        let summary = CustomizeResponsesSubLabel.summary(from: customizationValue,
                                                         clarifiesLabel: clarifiesLabel,
                                                         maxLength: maxSubLabelLength)
        return CustomizeResponsesState(hasCustomization: summary.isCustomized,
                                       subLabel: summary.subLabel,
                                       isActive: interpretActive(activeValue))
    }

    private static func interpretActive(_ value: Any?) -> Bool {
        switch value {
        case let flag as Bool: return flag
        case let text as String: return text.lowercased() == "true"
        default: return false
        }
    }
}

enum CustomizeResponsesSubLabel {

    private static let defaultValue = "Default"

    static func summary(from customizationValue: Any?, clarifiesLabel: String, maxLength: Int) -> (isCustomized: Bool, subLabel: String?) {
        let root: [String: Any]?
        switch customizationValue {
        case let json as String:
            guard !json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let data = json.data(using: .utf8) else { return (false, nil) }
            root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        case let object as [String: Any]:
            root = object
        default:
            return (false, nil)
        }
        guard let payload = root?["data"] as? [String: Any] else { return (false, nil) }
        return (!isEmpty(payload), buildSubLabel(payload, clarifiesLabel: clarifiesLabel, maxLength: maxLength))
    }

    private static func isEmpty(_ data: [String: Any]) -> Bool {
        !hasText(data, "assistantName")
            && !hasText(data, "userName")
            && !hasText(data, "additionalInstructions")
            && !hasText(data, "assistantRole")
            && !hasText(data, "userRole")
            && !isSetAndNotDefault(data, "tone")
            && !isSetAndNotDefault(data, "length")
            && !isClarifyingActive(data)
    }

    private static func buildSubLabel(_ data: [String: Any], clarifiesLabel: String, maxLength: Int) -> String? {
        var parts: [String] = []
        addIfSetAndNotDefault(&parts, data, "tone")
        addIfSetAndNotDefault(&parts, data, "length")
        addIfSetAndNotDefault(&parts, data, "assistantRole")
        addIfSetAndNotDefault(&parts, data, "userRole")
        if isClarifyingActive(data) { parts.append(clarifiesLabel) }
        addIfHasText(&parts, data, "assistantName")
        addIfHasText(&parts, data, "userName")
        return parts.isEmpty ? nil : truncateByWord(parts.joined(separator: ", "), maxLength: maxLength)
    }

    private static func addIfSetAndNotDefault(_ parts: inout [String], _ data: [String: Any], _ key: String) {
        if isSetAndNotDefault(data, key) { parts.append(string(data, key)!.trimmingCharacters(in: .whitespaces)) }
    }

    private static func addIfHasText(_ parts: inout [String], _ data: [String: Any], _ key: String) {
        if hasText(data, key) { parts.append(string(data, key)!.trimmingCharacters(in: .whitespaces)) }
    }

    private static func isSetAndNotDefault(_ data: [String: Any], _ key: String) -> Bool {
        hasText(data, key) && string(data, key)!.trimmingCharacters(in: .whitespaces) != defaultValue
    }

    private static func hasText(_ data: [String: Any], _ key: String) -> Bool {
        !(string(data, key)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    private static func string(_ data: [String: Any], _ key: String) -> String? {
        data[key] as? String
    }

    private static func isClarifyingActive(_ data: [String: Any]) -> Bool {
        (data["shouldSeekClarity"] as? Bool) == true
    }

    private static func truncateByWord(_ text: String, maxLength: Int) -> String {
        guard maxLength > 0 else { return "" }
        if text.count <= maxLength { return text }
        var result = ""
        for word in text.split(separator: " ", omittingEmptySubsequences: false) {
            let candidate = result.isEmpty ? String(word) : result + " " + word
            if candidate.count > maxLength { break }
            result = candidate
        }
        if result.isEmpty { result = String(text.prefix(maxLength)) }
        if result.hasSuffix(",") { result = String(result.dropLast()) }
        return result.hasSuffix(".") ? result : result + "…"
    }
}
