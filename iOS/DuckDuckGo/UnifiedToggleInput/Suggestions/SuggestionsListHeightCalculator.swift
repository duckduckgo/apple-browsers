//
//  SuggestionsListHeightCalculator.swift
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

import CoreGraphics

/// Computes the iPad popover's content height from the section model. A lazily-rendered `List`
/// can't report its full content height (only mounted rows exist), so — like the legacy
/// `AutocompleteViewController.updateHeight()` — we derive it arithmetically from the rows.
/// Constants mirror `SuggestionsListView`/`SuggestionRowView` metrics; tuned against the rendered list.
enum SuggestionsListHeightCalculator {

    private enum Metrics {
        /// `listTopInset` (6) per `SuggestionsListView`, top-bar only.
        static let topContentInset: CGFloat = 6
        /// `rowVerticalPaddingSingleLine` (15) ×2 + 24pt icon row.
        static let singleLineRowHeight: CGFloat = 54
        /// `rowVerticalPaddingWithSubtitle` (14) ×2 + title line + 21pt subtitle.
        static let subtitleRowHeight: CGFloat = 69
        /// `.listSectionSpacing(.compact)` gap between adjacent sections.
        static let interSectionSpacing: CGFloat = 10
        /// Slack below the last row so the rounded popover doesn't clip it.
        static let bottomPadding: CGFloat = 12
    }

    static func height(for sections: [SuggestionSection], isAddressBarAtBottom: Bool) -> CGFloat {
        guard !sections.isEmpty else { return 0 }

        let rowsHeight = sections.reduce(CGFloat.zero) { runningTotal, section in
            runningTotal + section.rows.reduce(CGFloat.zero) { $0 + rowHeight(for: $1) }
        }
        let spacing = CGFloat(max(0, sections.count - 1)) * Metrics.interSectionSpacing
        let topInset = isAddressBarAtBottom ? 0 : Metrics.topContentInset

        return rowsHeight + spacing + topInset + Metrics.bottomPadding
    }

    private static func rowHeight(for row: SuggestionRow) -> CGFloat {
        row.subtitle == nil ? Metrics.singleLineRowHeight : Metrics.subtitleRowHeight
    }
}
