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

    var hasUnread: Bool = false {
        didSet {
            unreadDotImageView.isHidden = !hasUnread
            iconImageView.image = hasUnread ? DesignSystemImages.Glyphs.Size24.tabMobileAlertRecolorable : DesignSystemImages.Glyphs.Size24.tabMobile
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
    }

    private func setUpConstraints() {
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        unreadDotImageView.translatesAutoresizingMaskIntoConstraints = false

        let verticalLabelOffsetConstraint = label.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -Metrics.labelOffset)
        self.verticalLabelOffsetConstraint = verticalLabelOffsetConstraint

        NSLayoutConstraint.activate([
            iconImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: Metrics.iconSize),
            iconImageView.heightAnchor.constraint(equalToConstant: Metrics.iconSize),

            label.centerXAnchor.constraint(equalTo: centerXAnchor, constant: Metrics.labelOffset),
            verticalLabelOffsetConstraint,

            unreadDotImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            unreadDotImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            unreadDotImageView.widthAnchor.constraint(equalToConstant: Metrics.iconSize),
            unreadDotImageView.heightAnchor.constraint(equalToConstant: Metrics.iconSize),
        ])
    }

    private func updateLayout(_ isShowingSymbol: Bool) {
        verticalLabelOffsetConstraint?.constant = -(isShowingSymbol ? Metrics.labelYOffsetInfinity : Metrics.labelOffset)
    }

    private func setUpProperties() {
        unreadDotImageView.isUserInteractionEnabled = false
        unreadDotImageView.tintColor = UIColor(designSystemColor: .accent)

        unreadDotImageView.isHidden = true

        label.textAlignment = .center
        label.isUserInteractionEnabled = false
        iconImageView.isUserInteractionEnabled = false
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

        static let labelOffset: CGFloat = 2
        static let labelYOffsetInfinity: CGFloat = 3

        static let fontSize = 9.0
        static let fontWeight = UIFont.Weight.bold

        static let symbolFontSize = 12.0
        static let symbolFontWeight = UIFont.Weight.semibold
    }
}
