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

/// Localized labels for the enum-valued customization fields, keyed by the stable English id the
/// frontend persists (e.g. `"Casual"`, `"Brainstorm partner"`). Each map resolves an id to its
/// localized display string; an id absent from the map falls back to the raw id (which is English),
/// so a value the frontend adds that native doesn't know about is shown verbatim.
///
/// Maps are field-specific because the same id can appear under two fields with different meanings
/// (e.g. `"Writer"` is both an assistant role and a your-role, `"Professional"` is both a tone and a
/// your-role) and may translate differently per locale.
public struct CustomizeResponsesTranslations: Equatable {

    public let tone: [String: String]
    public let length: [String: String]
    public let assistantRole: [String: String]
    public let userRole: [String: String]

    public static let empty = CustomizeResponsesTranslations()

    public init(tone: [String: String] = [:],
                length: [String: String] = [:],
                assistantRole: [String: String] = [:],
                userRole: [String: String] = [:]) {
        self.tone = tone
        self.length = length
        self.assistantRole = assistantRole
        self.userRole = userRole
    }
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
                            translations: CustomizeResponsesTranslations = .empty,
                            maxSubLabelLength: Int = 15) -> CustomizeResponsesState {
        let summary = CustomizeResponsesSubLabel.summary(from: customizationValue,
                                                         clarifiesLabel: clarifiesLabel,
                                                         translations: translations,
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

    static func summary(from customizationValue: Any?, clarifiesLabel: String, translations: CustomizeResponsesTranslations, maxLength: Int) -> (isCustomized: Bool, subLabel: String?) {
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
        return (!isEmpty(payload), buildSubLabel(payload, clarifiesLabel: clarifiesLabel, translations: translations, maxLength: maxLength))
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

    private static func buildSubLabel(_ data: [String: Any], clarifiesLabel: String, translations: CustomizeResponsesTranslations, maxLength: Int) -> String? {
        var parts: [String] = []
        addLocalizedIfSetAndNotDefault(&parts, data, "tone", translations.tone)
        addLocalizedIfSetAndNotDefault(&parts, data, "length", translations.length)
        addLocalizedIfSetAndNotDefault(&parts, data, "assistantRole", translations.assistantRole)
        addLocalizedIfSetAndNotDefault(&parts, data, "userRole", translations.userRole)
        if isClarifyingActive(data) { parts.append(clarifiesLabel) }
        addIfHasText(&parts, data, "assistantName")
        addIfHasText(&parts, data, "userName")
        return parts.isEmpty ? nil : truncateByWord(parts.joined(separator: ", "), maxLength: maxLength)
    }

    /// Appends the field's value localized via `map`, falling back to the raw (English) id when the
    /// id isn't mapped. Default-valued fields are skipped (a `"Default"` role contributes nothing).
    private static func addLocalizedIfSetAndNotDefault(_ parts: inout [String], _ data: [String: Any], _ key: String, _ map: [String: String]) {
        if isSetAndNotDefault(data, key) {
            let id = string(data, key)!.trimmingCharacters(in: .whitespaces)
            parts.append(map[id] ?? id)
        }
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
