//
//  AutoconsentCompactRuleFilter.swift
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

/// Port of autoconsent's `filterCompactRules`: keeps only the compact rules that can run in a frame, and replaces
/// the strings those rules do not use with empty strings. Rules refer to strings by index, so strings are blanked, not removed.
public final class AutoconsentCompactRuleFilter {

    private static let supportedFormatVersion = 1
    private static let ruleLength = 10
    private static let urlPatternSlot = 3
    private static let runContextSlot = 4
    private static let prehideSlot = 5
    private static let stepSlots = [6, 7, 8, 9]
    private static let stringKeys = ["e", "v", "c", "k", "w", "wv", "h", "cc"]
    private static let nestedStepKeys = ["then", "else", "any"]

    @MainActor private static var cachedSource: AnyObject?
    @MainActor private static var cachedFilter: AutoconsentCompactRuleFilter?

    private let strings: [Any]
    private let mainFrameCandidates: [Rule]
    private let subframeCandidates: [Rule]
    private lazy var mainFrameWithoutSiteRules = write(Self.select(mainFrameCandidates, isMainFrame: true, url: nil))
    private lazy var subframeWithoutSiteRules = write(Self.select(subframeCandidates, isMainFrame: false, url: nil))

    /// Returns the compact rule list to send to a frame.
    ///
    /// The filter for the latest rule list is kept, so a new filter is only built when the rule list changes.
    /// - Returns: The filtered rule list, or `ruleList` unchanged when it has a format or shape the filter does not know.
    @MainActor
    public static func ruleList(_ ruleList: Any?, frameURL: String, isMainFrame: Bool) -> Any? {
        guard let ruleList else { return nil }

        let source = ruleList as AnyObject
        if cachedSource !== source {
            cachedSource = source
            cachedFilter = AutoconsentCompactRuleFilter(ruleList: ruleList)
        }
        return cachedFilter?.filter(url: frameURL, isMainFrame: isMainFrame) ?? ruleList
    }

    /// Prepares a compact rule list for filtering.
    ///
    /// Fails when the rule list has a format or shape this filter does not know.
    public init?(ruleList: Any) {
        guard let ruleList = ruleList as? [String: Any],
              Self.int(ruleList["v"]) == Self.supportedFormatVersion,
              let strings = ruleList["s"] as? [Any],
              let ruleArray = ruleList["r"] as? [Any] else {
            return nil
        }

        var rules = [Rule]()
        for rule in ruleArray {
            guard let parsed = Rule(rule, stringCount: strings.count) else { return nil }
            rules.append(parsed)
        }

        self.strings = strings
        if let index = ruleList["index"] as? [String: Any],
           let generic = Self.range(index["genericRuleRange"], ruleCount: rules.count),
           let frame = Self.range(index["frameRuleRange"], ruleCount: rules.count),
           let specific = Self.range(index["specificRuleRange"], ruleCount: rules.count) {
            mainFrameCandidates = Array(rules[generic] + rules[specific])
            subframeCandidates = Array(rules[frame])
        } else {
            mainFrameCandidates = rules
            subframeCandidates = rules
        }
    }

    /// Builds the compact rule list for a frame.
    /// - Parameters:
    ///   - url: The URL of the frame the rules are for.
    ///   - isMainFrame: Whether the frame is the top-level frame.
    public func filter(url: String, isMainFrame: Bool) -> [String: Any] {
        let selected = Self.select(isMainFrame ? mainFrameCandidates : subframeCandidates, isMainFrame: isMainFrame, url: url)
        guard selected.contains(where: \.hasURLPattern) else {
            return isMainFrame ? mainFrameWithoutSiteRules : subframeWithoutSiteRules
        }
        return write(selected)
    }

    private static func select(_ candidates: [Rule], isMainFrame: Bool, url: String?) -> [Rule] {
        candidates.filter { rule in
            guard rule.canRun(isMainFrame: isMainFrame) else { return false }
            guard rule.hasURLPattern else { return true }
            guard let url else { return false }
            return rule.matches(url: url)
        }
    }

    private func write(_ selected: [Rule]) -> [String: Any] {
        var used = [Bool](repeating: false, count: strings.count)
        var last = -1
        for stringIndex in selected.flatMap(\.stringIndices) {
            used[stringIndex] = true
            last = max(last, stringIndex)
        }

        let filteredStrings: [Any] = (0..<(last + 1)).map { used[$0] ? strings[$0] : "" }
        return ["v": Self.supportedFormatVersion, "s": filteredStrings, "r": selected.map(\.json)]
    }

    private static func int(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let double = value as? Double { return Int(exactly: double) }
        return nil
    }

    private static func range(_ value: Any?, ruleCount: Int) -> Range<Int>? {
        guard let bounds = value as? [Any], bounds.count == 2,
              let start = int(bounds[0]), let end = int(bounds[1]),
              start >= 0, start <= end, end <= ruleCount else {
            return nil
        }
        return start..<end
    }

    private final class Rule {

        let json: Any
        let stringIndices: [Int]
        private let urlPattern: String
        private let runContext: Int
        private lazy var urlRegex = try? NSRegularExpression(pattern: urlPattern)

        var hasURLPattern: Bool { !urlPattern.isEmpty }

        init?(_ json: Any, stringCount: Int) {
            guard let rule = json as? [Any], rule.count >= AutoconsentCompactRuleFilter.ruleLength,
                  let urlPattern = rule[AutoconsentCompactRuleFilter.urlPatternSlot] as? String,
                  let runContext = AutoconsentCompactRuleFilter.int(rule[AutoconsentCompactRuleFilter.runContextSlot]),
                  let prehide = rule[AutoconsentCompactRuleFilter.prehideSlot] as? [Any] else {
                return nil
            }

            var stringIndices = Set<Int>()
            for selector in prehide {
                guard let stringIndex = AutoconsentCompactRuleFilter.int(selector) else { return nil }
                stringIndices.insert(stringIndex)
            }
            for slot in AutoconsentCompactRuleFilter.stepSlots {
                guard Self.collectStringIndices(rule[slot], into: &stringIndices) else { return nil }
            }
            guard stringIndices.allSatisfy({ (0..<stringCount).contains($0) }) else { return nil }

            self.json = json
            self.stringIndices = Array(stringIndices)
            self.urlPattern = urlPattern
            self.runContext = runContext
        }

        // runContext holds two digits (main, frame): 1 = true, 0 = false, 2 = unset; autoconsent defaults main to true and frame to false
        func canRun(isMainFrame: Bool) -> Bool {
            isMainFrame ? runContext / 10 % 10 != 0 : runContext % 10 == 1
        }

        // Fails open: a pattern that does not compile keeps the rule, and autoconsent checks the URL itself
        func matches(url: String) -> Bool {
            guard let urlRegex else { return true }
            return urlRegex.firstMatch(in: url, options: [], range: NSRange(url.startIndex..., in: url)) != nil
        }

        private static func collectStringIndices(_ steps: Any, into stringIndices: inout Set<Int>) -> Bool {
            guard let steps = steps as? [Any] else { return false }
            return steps.allSatisfy { collectStepStringIndices($0, into: &stringIndices) }
        }

        private static func collectStepStringIndices(_ step: Any, into stringIndices: inout Set<Int>) -> Bool {
            guard let step = step as? [String: Any] else { return false }

            for key in AutoconsentCompactRuleFilter.stringKeys {
                guard let value = step[key] else { continue }
                guard let stringIndex = AutoconsentCompactRuleFilter.int(value) else { return false }
                stringIndices.insert(stringIndex)
            }
            if let condition = step["if"], !collectStepStringIndices(condition, into: &stringIndices) {
                return false
            }
            return AutoconsentCompactRuleFilter.nestedStepKeys.allSatisfy { key in
                step[key].map { collectStringIndices($0, into: &stringIndices) } ?? true
            }
        }
    }
}
