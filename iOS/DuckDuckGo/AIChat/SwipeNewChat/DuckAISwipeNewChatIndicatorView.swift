//
//  DuckAISwipeNewChatIndicatorView.swift
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

import DesignResourcesKit
import DesignResourcesKitIcons
import UIKit

/// A ring that fills as the pull nears the trigger, then becomes a button styled like the input's send button.
final class DuckAISwipeNewChatIndicatorView: UIView {

    private enum Metrics {
        static let diameter: CGFloat = 48
        static let lineWidth: CGFloat = 2.5
        static let labelSpacing: CGFloat = 6
        static let fadeInProgress: CGFloat = 0.3
        static let collapsed = CGAffineTransform(scaleX: 0.01, y: 0.01)
    }

    static var circleDiameter: CGFloat { Metrics.diameter }

    private let circle = UIView()
    private let ring = CAShapeLayer()
    private let button = CircularButton()
    private let label = UILabel()
    private var isArmed = false

    init(isFireTab: Bool) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isUserInteractionEnabled = false
        alpha = 0

        circle.translatesAutoresizingMaskIntoConstraints = false
        ring.fillColor = UIColor.clear.cgColor
        ring.lineWidth = Metrics.lineWidth
        ring.lineCap = .round
        ring.strokeEnd = 0
        circle.layer.addSublayer(ring)

        button.translatesAutoresizingMaskIntoConstraints = false
        button.isShadowHidden = true
        button.setIcon(DesignSystemImages.Glyphs.Size24.compose)
        button.applySubmitStyle(isActive: true, isFireTab: isFireTab,
                                activeForeground: isFireTab ? .white : UIColor(designSystemColor: .accentContentPrimary))
        circle.addSubview(button)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .daxCaption()
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UIColor(designSystemColor: .textSecondary)
        label.text = UserText.actionNewAIChat

        addSubview(circle)
        addSubview(label)
        NSLayoutConstraint.activate([
            circle.topAnchor.constraint(equalTo: topAnchor),
            circle.centerXAnchor.constraint(equalTo: centerXAnchor),
            circle.widthAnchor.constraint(equalToConstant: Metrics.diameter),
            circle.heightAnchor.constraint(equalToConstant: Metrics.diameter),
            button.topAnchor.constraint(equalTo: circle.topAnchor),
            button.bottomAnchor.constraint(equalTo: circle.bottomAnchor),
            button.leadingAnchor.constraint(equalTo: circle.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: circle.trailingAnchor),
            label.topAnchor.constraint(equalTo: circle.bottomAnchor, constant: Metrics.labelSpacing),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        reset()
        applyRingColor()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let radius = (Metrics.diameter - Metrics.lineWidth) / 2
        let center = CGPoint(x: Metrics.diameter / 2, y: Metrics.diameter / 2)
        ring.path = UIBezierPath(arcCenter: center, radius: radius, startAngle: -.pi / 2, endAngle: 1.5 * .pi, clockwise: true).cgPath
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            applyRingColor()
        }
    }

    private func applyRingColor() {
        ring.strokeColor = button.backgroundColor?.resolvedColor(with: traitCollection).cgColor
    }

    func reset() {
        isArmed = false
        showButton(false)
        ring.strokeEnd = 0
    }

    func update(progress: CGFloat, isArmed: Bool) {
        layer.removeAllAnimations()
        alpha = min(progress / Metrics.fadeInProgress, 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.strokeEnd = progress
        CATransaction.commit()

        guard isArmed != self.isArmed else { return }
        self.isArmed = isArmed
        if UIAccessibility.isReduceMotionEnabled {
            UIView.animate(withDuration: 0.15) { self.showButton(isArmed) }
        } else {
            UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0,
                           options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.showButton(isArmed)
            }
        }
    }

    private func showButton(_ isShown: Bool) {
        if UIAccessibility.isReduceMotionEnabled {
            button.transform = .identity
            button.alpha = isShown ? 1 : 0
        } else {
            button.alpha = 1
            button.transform = isShown ? .identity : Metrics.collapsed
        }
    }
}
