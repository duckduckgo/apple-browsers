//
//  FloatingDomainCapsuleController.swift
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
import UIKit

final class FloatingDomainCapsuleController {

    static let handoffStart: CGFloat = 0.85
    private static let restEdgePadding: CGFloat = 8

    private let onTap: () -> Void
    private let backgroundView = UIVisualEffectView(effect: nil)
    private let domainLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.daxCaption1()
        label.textColor = UIColor(designSystemColor: .textPrimary)
        label.textAlignment = .center
        label.lineBreakMode = .byTruncatingMiddle
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.isAccessibilityElement = false
        return label
    }()
    private var centerYConstraint: NSLayoutConstraint?
    private var widthConstraint: NSLayoutConstraint?
    private var heightConstraint: NSLayoutConstraint?

    private lazy var button: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true
        button.alpha = 0
        button.backgroundColor = .clear
        button.layer.cornerCurve = .continuous
        button.layer.masksToBounds = true
        button.addTarget(self, action: #selector(onCapsuleTapped), for: .touchUpInside)
        return button
    }()

    init(onTap: @escaping () -> Void) {
        self.onTap = onTap
    }

    func install(in view: UIView) {
        guard button.superview == nil else { return }

        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.isUserInteractionEnabled = false
        backgroundView.layer.cornerCurve = .continuous
        backgroundView.clipsToBounds = true
        button.insertSubview(backgroundView, at: 0)

        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: button.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: button.bottomAnchor)
        ])

        backgroundView.contentView.addSubview(domainLabel)
        NSLayoutConstraint.activate([
            domainLabel.centerXAnchor.constraint(equalTo: backgroundView.contentView.centerXAnchor),
            domainLabel.centerYAnchor.constraint(equalTo: backgroundView.contentView.centerYAnchor),
            domainLabel.leadingAnchor.constraint(greaterThanOrEqualTo: backgroundView.contentView.leadingAnchor, constant: 12),
            domainLabel.trailingAnchor.constraint(lessThanOrEqualTo: backgroundView.contentView.trailingAnchor, constant: -12)
        ])

        applyGlassStyle()
        view.addSubview(button)

        let widthConstraint = button.widthAnchor.constraint(equalToConstant: 0)
        let heightConstraint = button.heightAnchor.constraint(equalToConstant: 0)
        let centerYConstraint = button.centerYAnchor.constraint(equalTo: view.topAnchor)
        self.widthConstraint = widthConstraint
        self.heightConstraint = heightConstraint
        self.centerYConstraint = centerYConstraint

        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            widthConstraint,
            heightConstraint,
            centerYConstraint
        ])
    }

    func update(addressBarPosition: AddressBarPosition,
                isEnabled: Bool,
                isUnifiedToggleInputActive: Bool,
                isAITab: Bool,
                isMinimalChromeLayout: Bool,
                domain: String?,
                barsVisibilityPercent: CGFloat,
                expandedFrame: CGRect,
                reduceMotion: Bool,
                in view: UIView) {
        guard isEnabled,
              !isUnifiedToggleInputActive,
              !isAITab,
              !isMinimalChromeLayout,
              let domain,
              !domain.isEmpty else {
            button.alpha = 0
            button.isHidden = true
            return
        }

        domainLabel.text = domain
        button.accessibilityLabel = domain

        let progress = max(0, min(1, barsVisibilityPercent))
        applyMorphGeometry(for: progress,
                           addressBarPosition: addressBarPosition,
                           expandedFrame: expandedFrame,
                           reduceMotion: reduceMotion,
                           in: view)

        let alpha = capsuleAlpha(for: progress, reduceMotion: reduceMotion)
        button.alpha = alpha
        domainLabel.alpha = reduceMotion ? 1 : max(0, min(1, 1 - progress))
        guard alpha > 0.01 else {
            button.isAccessibilityElement = false
            button.isUserInteractionEnabled = false
            hideButtonAfterInheritedAnimation()
            return
        }

        button.isHidden = false
        button.isAccessibilityElement = true
        button.isUserInteractionEnabled = true
        view.bringSubviewToFront(button)
    }

    private func hideButtonAfterInheritedAnimation() {
        let animationDuration = UIView.inheritedAnimationDuration
        guard animationDuration > 0 else {
            button.isHidden = true
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) { [weak self] in
            guard let self, button.alpha <= 0.01 else { return }
            button.isHidden = true
        }
    }

    private func capsuleAlpha(for progress: CGFloat, reduceMotion: Bool) -> CGFloat {
        if reduceMotion {
            return 1 - progress
        }
        if progress >= 1 {
            return 0
        }
        if progress <= Self.handoffStart {
            return 1
        }
        return 1 - (progress - Self.handoffStart) / (1 - Self.handoffStart)
    }

    private func applyMorphGeometry(for progress: CGFloat,
                                    addressBarPosition: AddressBarPosition,
                                    expandedFrame: CGRect,
                                    reduceMotion: Bool,
                                    in view: UIView) {
        let labelSize = domainLabel.intrinsicContentSize
        let capsuleHeight = labelSize.height + 12
        let capsuleWidth = min(labelSize.width + 24, max(0, view.bounds.width - 32))
        let restCenterY = addressBarPosition == .top
            ? view.safeAreaInsets.top + Self.restEdgePadding + capsuleHeight / 2
            : view.bounds.maxY - view.safeAreaInsets.bottom - Self.restEdgePadding - capsuleHeight / 2

        let morphProgress = reduceMotion || expandedFrame.isEmpty ? 0 : progress
        let width = capsuleWidth + (expandedFrame.width - capsuleWidth) * morphProgress
        let height = capsuleHeight + (expandedFrame.height - capsuleHeight) * morphProgress
        let centerY = restCenterY + (expandedFrame.midY - restCenterY) * morphProgress

        widthConstraint?.constant = width
        heightConstraint?.constant = height
        centerYConstraint?.constant = centerY
        button.layer.cornerRadius = height / 2
        backgroundView.layer.cornerRadius = height / 2
    }

    private func applyGlassStyle() {
        if #available(iOS 26.0, *) {
            backgroundView.effect = UIGlassEffect(style: .regular)
        } else {
            backgroundView.effect = UIBlurEffect(style: BrowserChromeMaterial.blurStyle)
            backgroundView.contentView.backgroundColor = UIColor(designSystemColor: .surface).withAlphaComponent(0.2)
        }
    }

    @objc
    private func onCapsuleTapped() {
        onTap()
    }
}
