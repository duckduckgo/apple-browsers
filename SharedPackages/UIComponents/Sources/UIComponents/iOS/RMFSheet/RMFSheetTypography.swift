//
//  RMFSheetTypography.swift
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

#if os(iOS)

import SwiftUI

/// The DesignResourcesKit `dax*` type tokens used by the RMF sheet, expressed as the SwiftUI text styles
/// they are built from (same style, same weight).
///
/// `Font(UIFont.daxTitle1())` and friends are fixed at the app's content size category when they are
/// created, so they ignore the SwiftUI environment's `dynamicTypeSize`. The text-style forms follow it,
/// which keeps the sheet correct under `.dynamicTypeSize(_:)` overrides, previews and snapshot tests.
enum RMFSheetTypography {
    /// `daxTitle1`: Title 1, bold. Sheet title.
    static let title1 = Font.title.weight(.bold)
    /// `daxBodyRegular`: Body. Sheet body and option labels.
    static let bodyRegular = Font.body
    /// `daxBodyRegular` at medium weight: Figma `Button L`.
    static let button = Font.body.weight(.medium)
    /// `daxHeadline`: Headline. Card row titles.
    static let headline = Font.headline
    /// `daxSubheadRegular`: Subheadline. Option descriptions, card row text and the footnote.
    static let subheadRegular = Font.subheadline
    /// `daxFootnoteSemibold`: Footnote, semibold. Eyebrow.
    static let footnoteSemibold = Font.footnote.weight(.semibold)
}

#endif
