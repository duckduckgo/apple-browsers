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

import MetricBuilder
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
        buttonConfiguration.background.cornerRadius = ContainerMetrics.cornerRadius

        configuration = buttonConfiguration
        configurationUpdateHandler = { button in
            guard var configuration = button.configuration else { return }

            let background: UIColor
            let foreground: UIColor
            if !button.isEnabled {
                background = UIColor(colors.disabled)
                foreground = UIColor(colors.textDisabled)
            } else if button.isHighlighted {
                background = UIColor(colors.pressed)
                foreground = UIColor(colors.text)
            } else {
                background = UIColor(colors.standard)
                foreground = UIColor(colors.text)
            }

            // Set resolved color rather than baseBackgroundColor, so UIKit doesn't apply extra dimming
            configuration.background.backgroundColor = background
            configuration.baseForegroundColor = foreground
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var transformed = incoming
                transformed.font = compact ? ButtonAppearanceConstants.compactTitleFont : ButtonAppearanceConstants.titleFont
                transformed.foregroundColor = foreground
                return transformed
            }

            button.configuration = configuration
        }
    }
}

private enum ButtonAppearanceConstants {
    static let compactContentInsets: NSDirectionalEdgeInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
    static let contentInsets: NSDirectionalEdgeInsets = NSDirectionalEdgeInsets(top: 16, leading: 24, bottom: 16, trailing: 24)
    static let compactTitleFont: UIFont = .systemFont(ofSize: UIFont.preferredFont(forTextStyle: .subheadline) .pointSize, weight: .medium)
    static let titleFont: UIFont = .systemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .medium)
}
