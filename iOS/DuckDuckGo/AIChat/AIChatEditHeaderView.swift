//
//  AIChatEditHeaderView.swift
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

protocol AIChatEditHeaderViewDelegate: AnyObject {
    func aiChatEditHeaderDidTapCancel()
}

/// Header shown while editing a message: a leading ✕ that cancels the edit and a centred
/// "Edit Message" title.
final class AIChatEditHeaderView: UIView {

    private enum Constants {
        static let headerHeight: CGFloat = 60
        static let buttonSize: CGFloat = 44
        static let horizontalPadding: CGFloat = 16
        static let titleEdgeSpacing: CGFloat = 12
    }

    weak var delegate: AIChatEditHeaderViewDelegate?

    private let preferredHeight: CGFloat?

    private var isHostEmbedded: Bool { preferredHeight == nil }

    private lazy var cancelPill = AIChatHeaderGlassPill(cornerRadius: Constants.buttonSize / 2)

    private lazy var cancelButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(DesignSystemImages.Glyphs.Size24.close.withRenderingMode(.alwaysTemplate), for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = UIColor(designSystemColor: .icons)
        button.imageView?.contentMode = .scaleAspectFit
        button.accessibilityLabel = UserText.actionCancel
        button.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        return button
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = UserText.aiChatHeaderEditMessageTitle
        let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .headline)
        label.font = UIFont(descriptor: descriptor, size: descriptor.pointSize)
        label.textColor = UIColor(designSystemColor: .textPrimary)
        label.textAlignment = .center
        label.adjustsFontForContentSizeCategory = true
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
        return label
    }()

    private lazy var bottomSeparator: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor(designSystemColor: .lines)
        return view
    }()

    init(preferredHeight: CGFloat? = Constants.headerHeight) {
        self.preferredHeight = preferredHeight
        super.init(frame: .zero)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            cancelPill.refreshGlassForCurrentTraits()
            cancelPill.applyShadow(dimmed: false)
        }
    }

    private func setupUI() {
        // Embedded in a host header: transparent and separator-free so it inherits the host chrome.
        backgroundColor = isHostEmbedded ? .clear : UIColor(designSystemColor: .surfaceCanvas)
        addSubview(cancelPill)
        addSubview(titleLabel)
        cancelPill.contentView.addSubview(cancelButton)

        if let preferredHeight {
            heightAnchor.constraint(equalToConstant: preferredHeight).isActive = true
        }

        var constraints: [NSLayoutConstraint] = [
            cancelPill.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Constants.horizontalPadding),
            cancelPill.centerYAnchor.constraint(equalTo: centerYAnchor),
            cancelPill.widthAnchor.constraint(equalToConstant: Constants.buttonSize),
            cancelPill.heightAnchor.constraint(equalToConstant: Constants.buttonSize),

            cancelButton.widthAnchor.constraint(equalToConstant: Constants.buttonSize),
            cancelButton.heightAnchor.constraint(equalToConstant: Constants.buttonSize),
            cancelButton.centerXAnchor.constraint(equalTo: cancelPill.centerXAnchor),
            cancelButton.centerYAnchor.constraint(equalTo: cancelPill.centerYAnchor),

            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: cancelPill.trailingAnchor, constant: Constants.titleEdgeSpacing),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Constants.horizontalPadding),
        ]

        if !isHostEmbedded {
            addSubview(bottomSeparator)
            constraints += [
                bottomSeparator.leadingAnchor.constraint(equalTo: leadingAnchor),
                bottomSeparator.trailingAnchor.constraint(equalTo: trailingAnchor),
                bottomSeparator.bottomAnchor.constraint(equalTo: bottomAnchor),
                bottomSeparator.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),
            ]
        }

        NSLayoutConstraint.activate(constraints)
    }

    @objc private func cancelTapped() {
        delegate?.aiChatEditHeaderDidTapCancel()
    }
}
