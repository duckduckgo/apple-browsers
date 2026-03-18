//
//  TabSwitcherStaticView.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

final class TabSwitcherStaticView: UIView {
    private let iconImageView = UIImageView(image: DesignSystemImages.Glyphs.Size24.tabMobile)
    private let unreadDotImageView = UIImageView(image: DesignSystemImages.Glyphs.Size24.tabMobileAlertDot)
    private let fireOverlayImageView = UIImageView(image: DesignSystemImages.Glyphs.Size24.fireTabMobile)

    let label = UILabel()

    private var verticalLabelOffsetConstraint: NSLayoutConstraint?

    override init(frame: CGRect = .zero) {
        super.init(frame: frame)

        setUpSubviews()
        setUpConstraints()
        setUpProperties()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isFireMode: Bool = false {
        didSet {
            updateIconState()
        }
    }

    var hasUnread: Bool = false {
        didSet {
            updateIconState()
        }
    }

    func updateCount(_ count: String?, isSymbol: Bool) {
        updateLayout(isSymbol)
        updateFont(isSymbol)
        label.text = count
    }

    func incrementAnimated(_ increment: @escaping () -> Void) {
        increment()
    }

    private func setUpSubviews() {
        addSubview(iconImageView)
        addSubview(label)
        addSubview(unreadDotImageView)
        addSubview(fireOverlayImageView)
    }

    private func setUpConstraints() {
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        unreadDotImageView.translatesAutoresizingMaskIntoConstraints = false
        fireOverlayImageView.translatesAutoresizingMaskIntoConstraints = false

        let verticalLabelOffsetConstraint = label.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -Metrics.labelYOffset)
        self.verticalLabelOffsetConstraint = verticalLabelOffsetConstraint

        NSLayoutConstraint.activate([
            iconImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: Metrics.iconSize),
            iconImageView.heightAnchor.constraint(equalToConstant: Metrics.iconSize),

            label.centerXAnchor.constraint(equalTo: centerXAnchor, constant: Metrics.labelXOffset),
            verticalLabelOffsetConstraint,

            unreadDotImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            unreadDotImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            unreadDotImageView.widthAnchor.constraint(equalToConstant: Metrics.iconSize),
            unreadDotImageView.heightAnchor.constraint(equalToConstant: Metrics.iconSize),

            fireOverlayImageView.leadingAnchor.constraint(equalTo: iconImageView.leadingAnchor, constant: Metrics.fireOverlayLeading),
            fireOverlayImageView.bottomAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: Metrics.fireOverlayBottom),
            fireOverlayImageView.widthAnchor.constraint(equalToConstant: Metrics.fireOverlayWidth),
            fireOverlayImageView.heightAnchor.constraint(equalToConstant: Metrics.fireOverlayHeight),
        ])
    }

    private func updateLayout(_ isShowingSymbol: Bool) {
        verticalLabelOffsetConstraint?.constant = -(isShowingSymbol ? Metrics.symbolYOffset : Metrics.labelYOffset)
    }

    private func setUpProperties() {
        clipsToBounds = false

        unreadDotImageView.isUserInteractionEnabled = false
        unreadDotImageView.tintColor = UIColor(designSystemColor: .accent)
        unreadDotImageView.isHidden = true

        fireOverlayImageView.isUserInteractionEnabled = false
        fireOverlayImageView.tintColor = UIColor(singleUseColor: .fireModeAccent)
        fireOverlayImageView.isHidden = true

        label.textAlignment = .center
        label.isUserInteractionEnabled = false
        iconImageView.isUserInteractionEnabled = false
    }

    private func updateIconState() {
        switch (isFireMode, hasUnread) {
        case (false, false):
            iconImageView.image = DesignSystemImages.Glyphs.Size24.tabMobile
            fireOverlayImageView.isHidden = true
            unreadDotImageView.isHidden = true
        case (false, true):
            iconImageView.image = DesignSystemImages.Glyphs.Size24.tabMobileAlert
            fireOverlayImageView.isHidden = true
            unreadDotImageView.isHidden = false
            unreadDotImageView.tintColor = UIColor(designSystemColor: .accent)
        case (true, false):
            iconImageView.image = DesignSystemImages.Glyphs.Size24.fireTabMobileFrame
            fireOverlayImageView.isHidden = false
            unreadDotImageView.isHidden = true
        case (true, true):
            iconImageView.image = DesignSystemImages.Glyphs.Size24.tabMobileAlert
            fireOverlayImageView.isHidden = true
            unreadDotImageView.isHidden = false
            unreadDotImageView.tintColor = UIColor(singleUseColor: .fireModeAccent)
        }
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()

        iconImageView.tintColor = tintColor
        label.textColor = tintColor
    }

    private func updateFont(_ isShowingSymbol: Bool) {
        let size = isShowingSymbol ? Metrics.symbolFontSize : Metrics.fontSize
        let weight = isShowingSymbol ? Metrics.symbolFontWeight : Metrics.fontWeight

        if #available(iOS 16.0, *) {
            label.font = UIFont.systemFont(ofSize: size,
                                           weight: weight,
                                           width: .condensed)
        } else {
            label.font = UIFont.systemFont(ofSize: size,
                                           weight: weight)
        }
    }

    private struct Metrics {
        static let iconSize: CGFloat = 24

        static let labelXOffset: CGFloat = 0
        static let labelYOffset: CGFloat = 0
        static let symbolYOffset: CGFloat = 1

        static let fontSize = 12.0
        static let fontWeight = UIFont.Weight.bold

        static let symbolFontSize = 14.0
        static let symbolFontWeight = UIFont.Weight.semibold

        static let fireOverlayLeading: CGFloat = 16.5
        static let fireOverlayBottom: CGFloat = -16
        static let fireOverlayWidth: CGFloat = 9
        static let fireOverlayHeight: CGFloat = 12
    }
}
