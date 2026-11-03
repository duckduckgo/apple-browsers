//
//  SwipeToNewTabAffordanceView.swift
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
import DesignResourcesKitIcons

/// The "+" revealed past the last tab: a ring fills as the pull grows, and the button fills in once releasing opens a new tab.
final class SwipeToNewTabAffordanceView: UIView {

    private typealias Tuning = SwipeToNewTabTuning

    /// Grows with the pull; `button` inside it pops on commit, so the two transforms never fight.
    private let pullScaleView = UIView()
    private let button = UIView()
    /// Fills the button from its center while a `.hold` pull rests at the line, turning the "+" it covers to the committed look.
    private let holdFillView = UIView()
    private let holdFillMask = CAShapeLayer()
    private let iconView = SwipeToNewTabAffordanceView.makeIconView()
    private let filledIconView = SwipeToNewTabAffordanceView.makeIconView()
    private let ringLayer = CAShapeLayer()
    private let titleLabel = UILabel()
    private var isCommitted = false
    private let style: SwipeToNewTabStyle

    init(style: SwipeToNewTabStyle) {
        self.style = style
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        setUpButton()
        setUpTitle()
        applyColors()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Places the affordance in the strip a pull of `distance` reveals at the trailing edge of `bounds`.
    func layout(revealing distance: CGFloat, progress: CGFloat, in bounds: CGRect, centerY: CGFloat) {
        let diameter = Tuning.affordanceDiameter
        let pageEdgeX = bounds.maxX - distance
        let centerX: CGFloat
        switch style {
        case .grow, .hold:
            centerX = bounds.maxX - max(distance / 2, diameter / 2 * Tuning.affordanceMinimumScale)
        case .edge:
            // Starts half behind the page edge and works its way out to the middle of the gap.
            centerX = pageEdgeX + distance / 2 * progress
        }
        self.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        center = CGPoint(x: centerX, y: centerY)
    }

    /// The "+" follows the pull from the first point; only the ring lags, at `ringProgress`.
    func update(progress: CGFloat, ringProgress: CGFloat, holdProgress: CGFloat) {
        let scale = style == .edge ? 1 : Tuning.affordanceMinimumScale + (1 - Tuning.affordanceMinimumScale) * progress
        pullScaleView.transform = CGAffineTransform(scaleX: scale, y: scale)
        alpha = min(progress / Tuning.fadeInProgress, 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ringLayer.strokeEnd = ringProgress
        let radius = Tuning.affordanceDiameter / 2 * holdProgress
        let center = CGPoint(x: holdFillView.bounds.midX, y: holdFillView.bounds.midY)
        holdFillMask.path = UIBezierPath(arcCenter: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: true).cgPath
        CATransaction.commit()
    }

    func setCommitted(_ committed: Bool) {
        guard committed != isCommitted else { return }
        isCommitted = committed
        let animator = UIViewPropertyAnimator(duration: 0.35, dampingRatio: 0.55) {
            self.applyColors()
            let rotation = committed ? CGAffineTransform(rotationAngle: .pi / 2) : .identity
            self.iconView.transform = rotation
            self.filledIconView.transform = rotation
            self.button.transform = committed ? CGAffineTransform(scaleX: Tuning.committedScale, y: Tuning.committedScale) : .identity
        }
        animator.startAnimation()
    }

    private func setUpButton() {
        let diameter = Tuning.affordanceDiameter
        pullScaleView.frame = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        addSubview(pullScaleView)
        button.frame = pullScaleView.bounds
        button.layer.cornerRadius = diameter / 2
        pullScaleView.addSubview(button)

        let iconFrame = CGRect(x: (diameter - 24) / 2, y: (diameter - 24) / 2, width: 24, height: 24)
        iconView.frame = iconFrame
        button.addSubview(iconView)

        holdFillView.frame = button.bounds
        holdFillMask.path = UIBezierPath(ovalIn: .zero).cgPath
        holdFillView.layer.mask = holdFillMask
        filledIconView.frame = iconFrame
        holdFillView.addSubview(filledIconView)
        button.addSubview(holdFillView)

        let inset: CGFloat = 1.5
        ringLayer.path = UIBezierPath(ovalIn: CGRect(x: inset, y: inset, width: diameter - inset * 2, height: diameter - inset * 2)).cgPath
        ringLayer.fillColor = UIColor.clear.cgColor
        ringLayer.lineWidth = 3
        ringLayer.lineCap = .round
        ringLayer.strokeEnd = 0
        ringLayer.transform = CATransform3DMakeRotation(-.pi / 2, 0, 0, 1)
        ringLayer.frame = button.bounds
        button.layer.addSublayer(ringLayer)
    }

    private static func makeIconView() -> UIImageView {
        UIImageView(image: DesignSystemImages.Glyphs.Size24.add.withRenderingMode(.alwaysTemplate))
    }

    private func setUpTitle() {
        titleLabel.text = UserText.actionNewTab
        titleLabel.font = UIFont.daxSubheadRegular()
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textAlignment = .center
        addSubview(titleLabel)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let titleSize = titleLabel.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
        titleLabel.frame = CGRect(x: (bounds.width - titleSize.width) / 2, y: bounds.maxY + Self.titleSpacing,
                                  width: titleSize.width, height: titleSize.height)
    }

    private static let titleSpacing: CGFloat = 8

    private func applyColors() {
        titleLabel.textColor = UIColor(designSystemColor: .textSecondary)
        button.backgroundColor = UIColor(designSystemColor: isCommitted ? .accentPrimary : .controlsFillPrimary)
        holdFillView.backgroundColor = UIColor(designSystemColor: .accentPrimary)
        iconView.tintColor = UIColor(designSystemColor: isCommitted ? .accentContentPrimary : .icons)
        filledIconView.tintColor = UIColor(designSystemColor: .accentContentPrimary)
        ringLayer.strokeColor = UIColor(designSystemColor: .accentPrimary).resolvedColor(with: traitCollection).cgColor
        ringLayer.opacity = isCommitted ? 0 : 1
    }
}
