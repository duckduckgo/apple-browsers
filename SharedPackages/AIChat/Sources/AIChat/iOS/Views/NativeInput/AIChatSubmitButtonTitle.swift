//
//  AIChatSubmitButtonTitle.swift
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
import DesignResourcesKit
import UIKit

/// How a Duck.ai send button draws a text label (such as "Ask") in place of its arrow, so every input matches.
public enum AIChatSubmitButtonTitle {

    public static let horizontalPadding: CGFloat = 16
    private static let maximumPointSize: CGFloat = 20

    /// Capped so the label still fits the 40pt button at accessibility text sizes.
    public static var font: UIFont {
        let font = UIFont.daxSubheadSemibold()
        return font.withSize(min(font.pointSize, maximumPointSize))
    }

    /// The width a button needs to show `title`, never narrower than its circular size.
    public static func buttonWidth(for title: String, minimumWidth: CGFloat) -> CGFloat {
        let titleWidth = (title as NSString).size(withAttributes: [.font: font]).width
        return max(minimumWidth, ceil(titleWidth) + 2 * horizontalPadding)
    }
}
#endif
