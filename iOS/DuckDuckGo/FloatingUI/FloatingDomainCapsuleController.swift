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

    static let handoffStart: CGFloat = 0.60

    static let handoffBandHalfWidth: CGFloat = 0.02

    /// Gap between the pill and the adjacent edge of its expanded chrome at its resting position.
    /// The collapsed bottom capsule sits `restBottomInsetReduction` closer to the device bottom so
    /// the chrome morphs down into the pill rather than gaining space above it.
    static let restEdgePadding: CGFloat = 8

    /// Extra downward shift of the collapsed bottom capsule, in points, relative to `restEdgePadding`
    /// above the home indicator. Clamped so the pill cannot leave the screen on devices with no
    /// home-indicator inset.
    static let restBottomInsetReduction: CGFloat = 12

    /// Extra clearance kept between a page-fixed footer and the top of the resting capsule so the two
    /// don't visually touch.
    static let fixedElementClearance: CGFloat = 4

    /// Distance from the physical bottom of the view to the bottom of the collapsed capsule.
    static func restPaddingFromPhysicalBottom(safeAreaBottom: CGFloat) -> CGFloat {
        max(0, safeAreaBottom + restEdgePadding - restBottomInsetReduction)
    }

    static func expandedFieldFrame(restingBarFrame: CGRect, fieldFrameInBar: CGRect) -> CGRect {
        guard !fieldFrameInBar.isEmpty else { return restingBarFrame }
        return fieldFrameInBar.offsetBy(dx: restingBarFrame.minX, dy: restingBarFrame.minY)
    }

    static func restCenterY(addressBarPosition: AddressBarPosition,
                            expandedFrame: CGRect,
                            boundsMaxY: CGFloat,
                            safeAreaInsets: UIEdgeInsets,
                            capsuleHeight: CGFloat) -> CGFloat {
        let halfHeight = capsuleHeight / 2
        switch addressBarPosition {
        case .top:
            guard !expandedFrame.isEmpty else {
                return safeAreaInsets.top + restEdgePadding + halfHeight
            }
            return expandedFrame.maxY - restEdgePadding - halfHeight
        case .bottom:
            return boundsMaxY - restPaddingFromPhysicalBottom(safeAreaBottom: safeAreaInsets.bottom) - halfHeight
        }
    }

    /// The pill's resting height, hugging the domain label. Independent of the label text (driven by
    /// the font line height), so it is stable enough to size the web view's obscured bottom inset.
    var capsuleHeight: CGFloat {
        domainLabel.intrinsicContentSize.height + 12
    }

    /// Height obscured by the resting capsule, measured from the matching screen edge, so a
    /// page-fixed footer pins above the pill once the bars have hidden.
    func restObscuredHeightFromScreenEdge(for addressBarPosition: AddressBarPosition,
                                          safeAreaInsets: UIEdgeInsets,
                                          expandedFrame: CGRect = .zero) -> CGFloat {
        switch addressBarPosition {
        case .top:
            guard !expandedFrame.isEmpty else {
                return safeAreaInsets.top + Self.restEdgePadding + capsuleHeight
            }
            return expandedFrame.maxY - Self.restEdgePadding
        case .bottom:
            return Self.restPaddingFromPhysicalBottom(safeAreaBottom: safeAreaInsets.bottom) + capsuleHeight
        }
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
    private var hasAppliedGlassStyleAtValidSize = false
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
        button.accessibilityIdentifier = "Browser.FloatingDomainCapsule"
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
        let shouldShow = FloatingUILayoutPolicy.shouldShowFloatingDomainCapsule(
            isFloatingUIEnabled: isFloatingUIEnabled,
            isUnifiedToggleInputActive: isUnifiedToggleInputActive,
            isAITab: isAITab,
            isMinimalChromeLayout: isMinimalChromeLayout
        )
        guard shouldShow,
              let domain,
              !domain.isEmpty else {
            button.alpha = 0
            button.isHidden = true
            return
        }

        if domainLabel.text != domain {
            domainLabel.text = domain
        }
        if button.accessibilityLabel != domain {
            button.accessibilityLabel = domain
        }

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
        if view.subviews.last !== button {
            view.bringSubviewToFront(button)
        }
    }

    private func pillAlpha(for p: CGFloat, reduceMotion: Bool) -> CGFloat {
        if reduceMotion {
            return max(0, min(1, 1 - p))
        }
        let bandStart = Self.handoffStart - Self.handoffBandHalfWidth
        let bandEnd = Self.handoffStart + Self.handoffBandHalfWidth
        guard bandEnd > bandStart else { return p < Self.handoffStart ? 1 : 0 }
        return 1 - ((p - bandStart) / (bandEnd - bandStart)).clamped(to: 0...1)
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
        let restCenterY = Self.restCenterY(
            addressBarPosition: addressBarPosition,
            expandedFrame: expandedFrame,
            boundsMaxY: view.bounds.maxY,
            safeAreaInsets: view.safeAreaInsets,
            capsuleHeight: capsuleHeight)

        let morphP = (reduceMotion || expandedFrame.isEmpty) ? 0 : min(1, p / Self.handoffStart)
        let width = capsuleWidth + (expandedFrame.width - capsuleWidth) * morphP
        let height = capsuleHeight + (expandedFrame.height - capsuleHeight) * morphP
        let centerY = restCenterY + (expandedFrame.midY - restCenterY) * morphP

        widthConstraint?.constant = width
        heightConstraint?.constant = height
        centerYConstraint?.constant = centerY

        button.layer.cornerRadius = height / 2
        backgroundView.layer.cornerRadius = height / 2

        if !hasAppliedGlassStyleAtValidSize, width > 0, height > 0 {
            hasAppliedGlassStyleAtValidSize = true
            applyGlassStyle()
        }
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
