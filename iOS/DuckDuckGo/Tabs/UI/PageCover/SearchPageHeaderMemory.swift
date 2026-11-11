//
//  SearchPageHeaderMemory.swift
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

import UIKit

/// Remembers how the results page header last rendered, per appearance, so the cover can show it as is.
///
/// The header holds the tabs and filters, never the query. Kept in memory for the session only.
@MainActor
final class SearchPageHeaderMemory {

    private var headers: [UIUserInterfaceStyle: UIImage] = [:]

    /// Nil unless a header was captured in this appearance at this width; other widths lay out differently.
    func header(for style: UIUserInterfaceStyle, width: CGFloat) -> UIImage? {
        guard let image = headers[style], Self.matches(image, width: width) else { return nil }
        return image
    }

    func record(_ header: UIImage, for style: UIUserInterfaceStyle) {
        guard header.size.width > 0, header.size.height > 0 else { return }
        headers[style] = header
    }

    nonisolated static func matches(_ header: UIImage, width: CGFloat) -> Bool {
        abs(header.size.width - width) < 0.5
    }
}
