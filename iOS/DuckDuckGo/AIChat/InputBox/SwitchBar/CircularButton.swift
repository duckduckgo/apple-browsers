//
//  CircularButton.swift
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
import DesignResourcesKit

/// Circular `UIButton` with animated press-state color swap.
/// Call `setColors(foreground:background:pressedForeground:pressedBackground:)` to define the look;
/// the button handles the transition on touch highlight. Optional dual-shadow effect can be hidden via `isShadowHidden`.
final class CircularButton: UIButton {

    enum Constants {
        static let hitSize: CGFloat = 44.0
        static let shadowRadius1: CGFloat = 6
        static let shadowOffset1Y: CGFloat = 2
        static let shadowRadius2: CGFloat = 16
        static let shadowOffset2Y: CGFloat = 16
    }

    private let secondShadowLayer = CALayer()
    private var definedBackgroundColor: UIColor?
    private var definedForegroundColor: UIColor?
    private var definedPressedBackgroundColor: UIColor?
    private var definedPressedForegroundColor: UIColor?

    var isShadowHidden: Bool = false {
        didSet {
            updateShadowVisibility()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupButton()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupButton()
    }

    private func setupButton() {
        layer.masksToBounds = false

        layer.shadowColor = UIColor(designSystemColor: .shadowSecondary).cgColor
        layer.shadowOpacity = 1.0
        layer.shadowOffset = CGSize(width: 0, height: Constants.shadowOffset1Y)
        layer.shadowRadius = Constants.shadowRadius1

        secondShadowLayer.shadowColor = UIColor(designSystemColor: .shadowSecondary).cgColor
        secondShadowLayer.shadowOpacity = 1.0
        secondShadowLayer.shadowOffset = CGSize(width: 0, height: Constants.shadowOffset2Y)
        secondShadowLayer.shadowRadius = Constants.shadowRadius2
        secondShadowLayer.masksToBounds = false
        layer.insertSublayer(secondShadowLayer, at: 0)

        imageView?.contentMode = .scaleAspectFit
        adjustsImageWhenHighlighted = false

        updateShadowVisibility()
    }

    private func updateShadowVisibility() {
        if isShadowHidden {
            layer.shadowOpacity = 0.0
            secondShadowLayer.shadowOpacity = 0.0
        } else {
            layer.shadowOpacity = 1.0
            secondShadowLayer.shadowOpacity = 1.0
        }
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.15) {
                if self.isHighlighted {
                    self.backgroundColor = self.definedPressedBackgroundColor ?? self.definedBackgroundColor?.withAlphaComponent(0.8)
                    self.imageView?.tintColor = self.definedPressedForegroundColor ?? self.definedForegroundColor
                } else {
                    self.backgroundColor = self.definedBackgroundColor
                    self.imageView?.tintColor = self.definedForegroundColor
                }
            }
        }
    }

    func setIcon(_ image: UIImage?) {
        setImage(image, for: .normal)
        imageView?.tintColor = UIColor(designSystemColor: .textPrimary)
    }

    func setColors(foreground: UIColor, background: UIColor, pressedForeground: UIColor? = nil, pressedBackground: UIColor? = nil) {
        definedForegroundColor = foreground
        definedBackgroundColor = background
        definedPressedForegroundColor = pressedForeground
        definedPressedBackgroundColor = pressedBackground

        backgroundColor = background
        imageView?.tintColor = foreground
        setTitleColor(foreground, for: .normal)
    }

    func applySubmitStyle(isActive: Bool, isFireTab: Bool, activeForeground: UIColor) {
        guard isActive else {
            setColors(foreground: UIColor(designSystemColor: .iconsSecondary),
                      background: UIColor(designSystemColor: .controlsFillPrimary))
            return
        }
        let background = isFireTab
            ? UIColor(singleUseColor: .fireModeAccent)
            : UIColor(designSystemColor: .accent)
        let pressedBackground = isFireTab
            ? UIColor(singleUseColor: .fireModeAccentTertiary)
            : UIColor(designSystemColor: .accentTertiary)
        setColors(foreground: activeForeground,
                  background: background,
                  pressedForeground: activeForeground,
                  pressedBackground: pressedBackground)
    }

    func applyAIVoiceChatStyle() {
        setColors(foreground: UIColor(designSystemColor: .textPrimary),
                  background: UIColor(singleUseColor: .unifiedToggleInputStopButtonBackground))
    }

    func applyReturnKeyStyle() {
        setColors(foreground: UIColor(designSystemColor: .textPrimary),
                  background: UIColor(singleUseColor: .unifiedToggleInputStopButtonBackground))
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        layer.cornerRadius = min(bounds.width, bounds.height) / 2
        secondShadowLayer.frame = bounds
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            layer.shadowColor = UIColor(designSystemColor: .shadowSecondary).cgColor
            secondShadowLayer.shadowColor = UIColor(designSystemColor: .shadowSecondary).cgColor
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        assert(Constants.hitSize >= frame.height)
        let offset = (frame.height - Constants.hitSize) / 2
        let rect = CGRect(x: offset, y: offset, width: Constants.hitSize, height: Constants.hitSize)
        guard rect.contains(point) else { return nil }
        return self
    }
}
