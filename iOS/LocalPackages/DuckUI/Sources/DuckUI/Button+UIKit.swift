//
//  Button+UIKit.swift
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

import SwiftUI
import UIKit

/// UIKit counterparts of `PrimaryButtonStyle`. These apply the **rebranded** design only.
///
public extension UIButton {

    func applyPrimaryStyle(compact: Bool = false) {
        applyFilledStyle(colors: .rebrandedPrimary, compact: compact)
    }

    func applyBrandStyle(compact: Bool = false) {
        applyFilledStyle(colors: .rebrandedBrand, compact: compact)
    }

    func applyDestructiveStyle(compact: Bool = false) {
        applyFilledStyle(colors: .rebrandedDestructive, compact: compact)
    }
}

private extension UIButton {

    func applyFilledStyle(colors: PrimaryButtonColors, compact: Bool) {
        var buttonConfiguration = UIButton.Configuration.filled()
        buttonConfiguration.contentInsets = compact ? ButtonAppearanceConstants.compactContentInsets : ButtonAppearanceConstants.contentInsets
        buttonConfiguration.cornerStyle = .capsule

        configuration = buttonConfiguration
        configurationUpdateHandler = { button in
            guard var configuration = button.configuration else { return }

            let background: UIColor
            let foreground: UIColor
            if !button.isEnabled {
                background = UIColor(colors.disabled).withDisabledOpacity
                foreground = UIColor(colors.textDisabled)
            } else if button.isHighlighted {
                background = UIColor(colors.pressed)
                foreground = UIColor(colors.text)
            } else {
                background = UIColor(colors.standard)
                foreground = UIColor(colors.text)
            }

            let titleFont = ButtonAppearanceConstants.titleFont(compact: compact, traits: button.traitCollection)

            // Set resolved color rather than baseBackgroundColor, so UIKit doesn't apply extra dimming
            configuration.background.backgroundColor = background
            configuration.baseForegroundColor = foreground
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var transformed = incoming
                transformed.font = titleFont
                transformed.foregroundColor = foreground
                return transformed
            }

            button.configuration = configuration
        }
    }
}

private extension UIColor {
    var withDisabledOpacity: UIColor {
        UIColor { [self] traits in
            resolvedColor(with: traits).withAlphaComponent(Consts.disabledOpacity)
        }
    }
}

private enum ButtonAppearanceConstants {
    static let compactContentInsets: NSDirectionalEdgeInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
    static let contentInsets: NSDirectionalEdgeInsets = NSDirectionalEdgeInsets(top: 16, leading: 24, bottom: 16, trailing: 24)

    /// The UIKit equivalent of the SwiftUI styles' `ddgButtonDynamicTypeCap()`, capping the font size at `DynamicTypeSize.accessibility3`
    static let maximumContentSizeCategory: UIContentSizeCategory = .accessibilityExtraLarge

    static func titleFont(compact: Bool, traits: UITraitCollection) -> UIFont {
        let textStyle: UIFont.TextStyle = compact ? .subheadline : .body
        let maximumTraits = UITraitCollection(preferredContentSizeCategory: maximumContentSizeCategory)
        let pointSize = min(UIFont.preferredFont(forTextStyle: textStyle, compatibleWith: traits).pointSize,
                            UIFont.preferredFont(forTextStyle: textStyle, compatibleWith: maximumTraits).pointSize)
        return .systemFont(ofSize: pointSize, weight: .medium)
    }
}
