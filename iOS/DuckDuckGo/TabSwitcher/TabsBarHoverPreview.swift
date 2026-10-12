//
//  TabsBarHoverPreview.swift
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

final class TabsBarHoverPreview: UIView {

    init(title: String, domain: String?, image: UIImage?, theme: Theme) {
        super.init(frame: .zero)

        accessibilityIdentifier = "TabsBar.HoverPreview"
        isUserInteractionEnabled = false
        backgroundColor = theme.tableCellBackgroundColor
        layer.cornerRadius = 12
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.18
        layer.shadowRadius = 10
        layer.shadowOffset = CGSize(width: 0, height: 4)

        let content = UIStackView()
        content.axis = .vertical
        content.translatesAutoresizingMaskIntoConstraints = false
        content.clipsToBounds = true
        content.layer.cornerRadius = layer.cornerRadius
        addSubview(content)

        if let image {
            let thumbnail = UIImageView(image: image)
            thumbnail.contentMode = .scaleAspectFill
            thumbnail.clipsToBounds = true
            thumbnail.heightAnchor.constraint(equalToConstant: 170).isActive = true
            content.addArrangedSubview(thumbnail)
        }

        let text = UIStackView()
        text.axis = .vertical
        text.spacing = 4
        text.isLayoutMarginsRelativeArrangement = true
        text.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        content.addArrangedSubview(text)

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: .systemFont(ofSize: 15, weight: .semibold))
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 3
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.textColor = theme.tableCellTextColor
        text.addArrangedSubview(titleLabel)

        if let domain, !domain.isEmpty {
            let domainLabel = UILabel()
            domainLabel.text = domain
            domainLabel.font = .preferredFont(forTextStyle: .caption1)
            domainLabel.adjustsFontForContentSizeCategory = true
            domainLabel.lineBreakMode = .byTruncatingMiddle
            domainLabel.textColor = theme.tableCellSecondaryTextColor
            text.addArrangedSubview(domainLabel)
        }

        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: layer.cornerRadius).cgPath
    }
}
