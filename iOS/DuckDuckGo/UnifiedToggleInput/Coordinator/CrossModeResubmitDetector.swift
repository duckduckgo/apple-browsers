//
//  CrossModeResubmitDetector.swift
//  DuckDuckGo
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

import AIChat
import Foundation

/// Spots the same text sent to Search and Duck.ai within a minute, a proxy for submits made in the wrong mode.
/// The text is compared on the device and kept in memory only; pixels get nothing but the delay bucket.
@MainActor
final class CrossModeResubmitDetector {

    enum DelayBucket: String {
        case upTo15s = "0-15"
        case upTo30s = "16-30"
        case upTo45s = "31-45"
        case upTo60s = "46-60"

        init?(elapsed: TimeInterval) {
            switch elapsed {
            case ...15: self = .upTo15s
            case ...30: self = .upTo30s
            case ...45: self = .upTo45s
            case ...60: self = .upTo60s
            default: return nil
            }
        }
    }

    private struct Submission {
        let normalizedText: [Character]
        let mode: TextEntryMode
        let uptime: TimeInterval
    }

    private var origin: Submission?
    private let uptime: () -> TimeInterval

    /// Uses a monotonic clock so clock changes can't produce negative or inflated delays.
    init(uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.uptime = uptime
    }

    /// Returns the delay when `text` repeats the last origin in the other mode. A match consumes the origin;
    /// otherwise the submission becomes the new origin when `canStartComparison` allows it.
    func registerSubmission(_ text: String, mode: TextEntryMode, canStartComparison: Bool) -> DelayBucket? {
        let normalizedText = ResubmitTextMatcher.normalized(text)
        if let delay = resubmitDelay(of: normalizedText, mode: mode) {
            clear()
            return delay
        }
        if canStartComparison, !normalizedText.isEmpty {
            origin = Submission(normalizedText: normalizedText, mode: mode, uptime: uptime())
        }
        return nil
    }

    func clear() {
        origin = nil
    }

    private func resubmitDelay(of normalizedText: [Character], mode: TextEntryMode) -> DelayBucket? {
        guard let origin, origin.mode != mode,
              let delay = DelayBucket(elapsed: uptime() - origin.uptime),
              ResubmitTextMatcher.matches(origin.normalizedText, normalizedText) else { return nil }
        return delay
    }
}

/// Matches texts that differ only in case, punctuation, spacing or a typo or two. Short texts must match exactly,
/// so that "hi" and "ii" don't count as the same; long texts are usually pasted, so they must match exactly too.
enum ResubmitTextMatcher {

    static let maxTypoTolerantLength = 1_000

    static func matches(_ lhs: String, _ rhs: String) -> Bool {
        matches(normalized(lhs), normalized(rhs))
    }

    static func matches(_ lhs: [Character], _ rhs: [Character]) -> Bool {
        guard !lhs.isEmpty, !rhs.isEmpty else { return false }
        guard lhs != rhs else { return true }
        guard max(lhs.count, rhs.count) <= maxTypoTolerantLength else { return false }
        let allowedTypos = allowedTypoCount(forLength: min(lhs.count, rhs.count))
        return editDistance(lhs, rhs, atMost: allowedTypos) <= allowedTypos
    }

    static func normalized(_ text: String) -> [Character] {
        Array(text.lowercased()
            .components(separatedBy: .punctuationCharacters).joined()
            .split(whereSeparator: \.isWhitespace).joined(separator: " "))
    }

    private static func allowedTypoCount(forLength length: Int) -> Int {
        switch length {
        case ...3: return 0
        case ...7: return 1
        default: return 2
        }
    }

    /// Levenshtein distance limited to a band of `limit` around the diagonal; returns `limit + 1` once it is exceeded.
    private static func editDistance(_ lhs: [Character], _ rhs: [Character], atMost limit: Int) -> Int {
        let exceeded = limit + 1
        guard abs(lhs.count - rhs.count) <= limit else { return exceeded }
        var previous = (0...rhs.count).map { min($0, exceeded) }
        var current = Array(repeating: exceeded, count: rhs.count + 1)
        for i in 1...lhs.count {
            let band = max(1, i - limit)...min(rhs.count, i + limit)
            current[0] = min(i, exceeded)
            if band.lowerBound > 1 { current[band.lowerBound - 1] = exceeded }
            var rowMinimum = current[0]
            for j in band {
                let substitution = previous[j - 1] + (lhs[i - 1] == rhs[j - 1] ? 0 : 1)
                current[j] = min(substitution, previous[j] + 1, current[j - 1] + 1, exceeded)
                rowMinimum = min(rowMinimum, current[j])
            }
            if band.upperBound < rhs.count { current[band.upperBound + 1] = exceeded }
            guard rowMinimum <= limit else { return exceeded }
            swap(&previous, &current)
        }
        return previous[rhs.count]
    }
}
