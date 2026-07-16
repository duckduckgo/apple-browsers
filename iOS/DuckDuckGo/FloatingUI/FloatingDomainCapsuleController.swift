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

    /// Below this `barsVisibilityPercent` the morph pill is fully opaque and physically resizes
    /// between the capsule and the bar. Above it, the pill fades out over the short remaining band
    /// while the real chrome fades in, giving a seamless swap without an obvious mid-transition
    /// cross-fade. Shared with `MainViewController` for the complementary chrome-alpha ramp.
    static let handoffStart: CGFloat = 0.85

    /// Gap between the pill and the edge of the safe area at its resting position.
    static let restEdgePadding: CGFloat = 8

    /// Extra clearance kept between a page-fixed footer and the top of the resting capsule so the two
    /// don't visually touch.
    static let fixedElementClearance: CGFloat = 4

    /// The pill's resting height, hugging the domain label. Independent of the label text (driven by
    /// the font line height), so it is stable enough to size the web view's obscured bottom inset.
    var capsuleHeight: CGFloat {
        domainLabel.intrinsicContentSize.height + 12
    }

    /// Height of the region obscured by the resting capsule, measured from the safe area edge (the
    /// `restEdgePadding` gap plus the pill height). Used by the floating web view inset so a page-fixed
    /// footer pins above the capsule once the bars have hidden.
    var restObscuredHeightAboveSafeArea: CGFloat {
        Self.restEdgePadding + capsuleHeight
    }

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

    lazy var button: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true
        button.alpha = 0
        button.backgroundColor = .clear
        button.layer.cornerCurve = .continuous
        button.layer.cornerRadius = 14
        button.layer.masksToBounds = true
        button.addTarget(self, action: #selector(onCapsuleTapped), for: .touchUpInside)
        return button
    }()

    init(onTap: @escaping () -> Void) {
        self.onTap = onTap
    }

    func install(in view: UIView, addressBarPosition: AddressBarPosition) {
        guard button.superview == nil else { return }

        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.isUserInteractionEnabled = false
        backgroundView.layer.cornerCurve = .continuous
        backgroundView.layer.cornerRadius = 14
        backgroundView.clipsToBounds = true
        button.insertSubview(backgroundView, at: 0)

        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: button.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: button.bottomAnchor)
        ])
        backgroundView.contentView.addSubview(domainLabel)
        // Center the label with padding as soft limits so the explicit pill size never conflicts
        // with the label's intrinsic width; the label truncates when the pill is smaller.
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
        let centerYConstraint = button.centerYAnchor.constraint(equalTo: view.topAnchor, constant: 0)
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
                isFloatingUIEnabled: Bool,
                isUnifiedToggleInputActive: Bool,
                isAITab: Bool,
                isMinimalChromeLayout: Bool,
                domain: String?,
                barsVisibilityPercent: CGFloat,
                expandedFrame: CGRect,
                reduceMotion: Bool,
                in view: UIView) {
        guard FloatingUILayoutPolicy.shouldShowFloatingDomainCapsule(
            isFloatingUIEnabled: isFloatingUIEnabled,
            isUnifiedToggleInputActive: isUnifiedToggleInputActive,
            isAITab: isAITab,
            isMinimalChromeLayout: isMinimalChromeLayout
        ),
              let domain,
              !domain.isEmpty else {
            button.alpha = 0
            button.isHidden = true
            return
        }

        if domainLabel.text != domain {
            domainLabel.text = domain
        }
        button.accessibilityLabel = domain

        let p = max(0, min(1, barsVisibilityPercent))

        // Keep the pill geometry current even when it's about to be hidden, so it is never left
        // frozen at a stale size/position the next time it becomes visible.
        applyMorphGeometry(for: p, addressBarPosition: addressBarPosition, expandedFrame: expandedFrame, reduceMotion: reduceMotion, in: view)

        let pillAlpha = pillAlpha(for: p, reduceMotion: reduceMotion)
        guard pillAlpha > 0.01 else {
            button.alpha = 0
            button.isHidden = true
            return
        }

        domainLabel.alpha = reduceMotion ? 1 : max(0, min(1, 1 - p))
        button.isHidden = false
        button.alpha = pillAlpha
        view.bringSubviewToFront(button)
    }

    /// Opacity of the morph pill. Fully opaque through the resize band (`p <= handoffStart`), then
    /// ramps to 0 over `[handoffStart, 1]` so the real chrome takes over. Reduce Motion falls back
    /// to a plain inverse cross-fade.
    private func pillAlpha(for p: CGFloat, reduceMotion: Bool) -> CGFloat {
        if reduceMotion {
            return max(0, min(1, 1 - p))
        }
        if p >= 1 {
            return 0
        }
        if p <= Self.handoffStart {
            return 1
        }
        return 1 - (p - Self.handoffStart) / (1 - Self.handoffStart)
    }

    /// Interpolates the pill's real width/height/vertical-centre (and capsule corner radius) between
    /// its natural capsule size and the bar's `expandedFrame`, so it physically morphs rather than
    /// scaling a transparent copy. Reduce Motion (or a missing bar frame) pins it to the capsule size.
    private func applyMorphGeometry(for p: CGFloat,
                                    addressBarPosition: AddressBarPosition,
                                    expandedFrame: CGRect,
                                    reduceMotion: Bool,
                                    in view: UIView) {
        let labelSize = domainLabel.intrinsicContentSize
        let capsuleHeight = self.capsuleHeight
        let capsuleWidth = min(labelSize.width + 24, max(0, view.bounds.width - 32))
        let restCenterY = addressBarPosition == .top
            ? view.safeAreaInsets.top + Self.restEdgePadding + capsuleHeight / 2
            : view.bounds.maxY - view.safeAreaInsets.bottom - Self.restEdgePadding - capsuleHeight / 2

        let morphP = (reduceMotion || expandedFrame.isEmpty) ? 0 : p
        let width = capsuleWidth + (expandedFrame.width - capsuleWidth) * morphP
        let height = capsuleHeight + (expandedFrame.height - capsuleHeight) * morphP
        let centerY = restCenterY + (expandedFrame.midY - restCenterY) * morphP

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
            backgroundView.effect = UIBlurEffect(style: .systemThinMaterial)
            backgroundView.contentView.backgroundColor = UIColor(designSystemColor: .surface).withAlphaComponent(0.2)
        }
    }

    @objc
    private func onCapsuleTapped() {
        onTap()
    }
}
