//
//  BrowsingMenuEntryViewCell.swift
//  DuckDuckGo
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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
import Core

class BrowsingMenuEntryViewCell: UITableViewCell {
    
    let entryImage = UIImageView()
    let entryLabel = UILabel()
    let notificationDot = UIView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
        setupConstraints()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configure(image: UIImage, label: String, accessibilityLabel: String?, showNotificationDot: Bool = false, customDotColor: UIColor? = nil) {
        entryImage.image = image
        entryLabel.setAttributedTextString(label)
        entryLabel.accessibilityLabel = accessibilityLabel

        let theme = ThemeManager.shared.currentTheme

        decorate(with: theme)
        entryImage.tintColor = theme.browsingMenuIconsColor
        entryLabel.textColor = theme.browsingMenuTextColor
        backgroundColor = theme.browsingMenuBackgroundColor
        setHighlightedStateBackgroundColor(theme.browsingMenuHighlightColor)
        
        notificationDot.isHidden = !showNotificationDot
        notificationDot.layer.cornerRadius = 4
        if let customDotColor {
            notificationDot.backgroundColor = customDotColor
        }
    }
    
    static func preferredWidth(for text: String) -> CGFloat {
        
        let size = (text as NSString).boundingRect(with: CGSize(width: 1000, height: 22),
                                                   options: [.usesFontLeading, .usesLineFragmentOrigin],
                                                   attributes: [.font: UIFont.appFont(ofSize: 17)],
                                                   context: nil)
        
        return size.width + 90 // Left Margin + Icon width + Spacing + Right Margin
    }

    private func setupViews() {
        selectionStyle = .default
        accessibilityTraits.insert(.button)

        entryImage.translatesAutoresizingMaskIntoConstraints = false
        entryImage.contentMode = .center
        contentView.addSubview(entryImage)

        entryLabel.translatesAutoresizingMaskIntoConstraints = false
        entryLabel.numberOfLines = 0
        entryLabel.lineBreakMode = .byTruncatingTail
        entryLabel.attributedText = Self.makeLabelTemplate()
        contentView.addSubview(entryLabel)

        notificationDot.translatesAutoresizingMaskIntoConstraints = false
        notificationDot.backgroundColor = UIColor(designSystemColor: .accentPrimary)
        contentView.addSubview(notificationDot)
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            entryImage.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            entryImage.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 13),
            entryImage.widthAnchor.constraint(equalToConstant: 16),
            entryImage.heightAnchor.constraint(equalToConstant: 16),

            entryLabel.leadingAnchor.constraint(equalTo: entryImage.trailingAnchor, constant: 17),
            entryLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            entryLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            entryLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 10),
            entryLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 22),

            contentView.trailingAnchor.constraint(greaterThanOrEqualTo: entryLabel.trailingAnchor, constant: 12),

            notificationDot.leadingAnchor.constraint(equalTo: entryLabel.trailingAnchor, constant: 6),
            notificationDot.centerYAnchor.constraint(equalTo: entryImage.centerYAnchor),
            notificationDot.widthAnchor.constraint(equalToConstant: 8),
            notificationDot.heightAnchor.constraint(equalToConstant: 8),
            contentView.trailingAnchor.constraint(greaterThanOrEqualTo: notificationDot.trailingAnchor, constant: 12)
        ])
    }

    private static func makeLabelTemplate() -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = 22

        return NSAttributedString(string: " ",
                                  attributes: [.font: UIFont.appFont(ofSize: 17),
                                               .paragraphStyle: paragraphStyle])
    }
}
