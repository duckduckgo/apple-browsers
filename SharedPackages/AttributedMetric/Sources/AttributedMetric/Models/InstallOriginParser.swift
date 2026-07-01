//
//  InstallOriginParser.swift
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

/// Parsed install-origin xattr fields.
///
/// Format: `funnel_entry_source_campaign_content` (up to five underscore-delimited fields).
/// Trailing fields omitted from the string are `nil`; explicit empty segments are `""`.
struct InstallOriginComponents: Equatable {
    let funnel: String
    let entry: String
    let source: String?
    let campaign: String?
    let content: String?
}

enum InstallOriginParser {

    private static let minimumSegmentCount = 2
    private static let maximumSegmentCount = 5

    static func parse(_ origin: String) -> InstallOriginComponents? {
        let trimmed = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let segments = trimmed
            .split(separator: "_", omittingEmptySubsequences: false)
            .map(String.init)
        guard segments.count >= minimumSegmentCount, segments.count <= maximumSegmentCount else { return nil }

        return InstallOriginComponents(
            funnel: segments[0],
            entry: segments[1],
            source: segments.count > 2 ? segments[2] : nil,
            campaign: segments.count > 3 ? segments[3] : nil,
            content: segments.count > 4 ? segments[4] : nil
        )
    }
}
