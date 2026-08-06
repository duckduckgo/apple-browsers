//
//  AIChatHeaderGlassPill.swift
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

/// Glass capsule chrome for the Duck.ai tab headers; add controls to `contentView`. Split into an
/// outer shadow host and an inner clipped host so the shadow renders outside the capsule while
/// content (and menu-dismiss highlights) stay clipped inside.
final class AIChatHeaderGlassPill: UIView {

    /// Add pill content here (an icon button, or a multi-icon stack).
    let contentView = UIView()

    private let cornerRadius: CGFloat
    private let clipHost = UIView()
    private var glassEffectView: UIVisualEffectView?

    init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        clipHost.translatesAutoresizingMaskIntoConstraints = false
        clipHost.layer.cornerRadius = cornerRadius
        clipHost.clipsToBounds = true
        addSubview(clipHost)

        contentView.translatesAutoresizingMaskIntoConstraints = false

        if #available(iOS 26, *) {
            let effectView = UIVisualEffectView(effect: Self.glassEffect(for: traitCollection))
            effectView.translatesAutoresizingMaskIntoConstraints = false
            effectView.layer.cornerRadius = cornerRadius
            effectView.clipsToBounds = true
            clipHost.addSubview(effectView)
            effectView.contentView.addSubview(contentView)
            NSLayoutConstraint.activate([
                effectView.topAnchor.constraint(equalTo: clipHost.topAnchor),
                effectView.leadingAnchor.constraint(equalTo: clipHost.leadingAnchor),
                effectView.trailingAnchor.constraint(equalTo: clipHost.trailingAnchor),
                effectView.bottomAnchor.constraint(equalTo: clipHost.bottomAnchor),
                contentView.topAnchor.constraint(equalTo: effectView.contentView.topAnchor),
                contentView.leadingAnchor.constraint(equalTo: effectView.contentView.leadingAnchor),
                contentView.trailingAnchor.constraint(equalTo: effectView.contentView.trailingAnchor),
                contentView.bottomAnchor.constraint(equalTo: effectView.contentView.bottomAnchor),
            ])
            glassEffectView = effectView
        } else {
            clipHost.backgroundColor = UIColor(designSystemColor: .controlsRaisedFillPrimary)
            clipHost.addSubview(contentView)
            NSLayoutConstraint.activate([
                contentView.topAnchor.constraint(equalTo: clipHost.topAnchor),
                contentView.leadingAnchor.constraint(equalTo: clipHost.leadingAnchor),
                contentView.trailingAnchor.constraint(equalTo: clipHost.trailingAnchor),
                contentView.bottomAnchor.constraint(equalTo: clipHost.bottomAnchor),
            ])
        }

        NSLayoutConstraint.activate([
            clipHost.topAnchor.constraint(equalTo: topAnchor),
            clipHost.leadingAnchor.constraint(equalTo: leadingAnchor),
            clipHost.trailingAnchor.constraint(equalTo: trailingAnchor),
            clipHost.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        layer.cornerRadius = cornerRadius
        applyShadow(dimmed: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Re-resolve the glass style for the current light/dark appearance. No-op on legacy.
    func refreshGlassForCurrentTraits() {
        guard #available(iOS 26, *), let glassEffectView else { return }
        glassEffectView.effect = Self.glassEffect(for: traitCollection)
    }

    /// Drop shadow for the capsule; `dimmed` softens it during onboarding lock.
    func applyShadow(dimmed: Bool) {
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = dimmed ? 0.04 : 0.16
        layer.shadowOffset = CGSize(width: 0, height: 8)
        layer.shadowRadius = 16
        layer.borderWidth = 0
        layer.borderColor = nil
        clipsToBounds = false
    }

    @available(iOS 26, *)
    private static func glassEffect(for traitCollection: UITraitCollection) -> UIGlassEffect {
        let glassStyle: UIGlassEffect.Style = traitCollection.userInterfaceStyle == .dark ? .clear : .regular
        let effect = UIGlassEffect(style: glassStyle)
        effect.isInteractive = true
        return effect
    }
}
