//
//  AIChatFullModeOmniBrandingView.swift
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
import DesignResourcesKitIcons

/// View displaying the Duck.ai branding in the omnibar during AI Chat full mode
final class AIChatFullModeOmniBrandingView: UIView {

    // MARK: - UI Elements

    private let containerView = UIView()
    private let brandingIconView = UIImageView()
    private let textLabel = UILabel()

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
        setupConstraints()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
        setupConstraints()
    }

    // MARK: - Setup

    private func setupViews() {
        backgroundColor = .clear

        containerView.backgroundColor = .clear
        containerView.layer.cornerRadius = 8
        containerView.clipsToBounds = true
        addSubview(containerView)

        brandingIconView.contentMode = .scaleAspectFit
        containerView.addSubview(brandingIconView)

        brandingIconView.image = DesignSystemImages.Color.Size24.aiChatGradient

        textLabel.text = UserText.omnibarFullAIChatModeDisplayTitle
        textLabel.font = UIFont.daxBodyRegular()
        textLabel.textColor = UIColor(designSystemColor: .textPrimary)
        textLabel.setContentHuggingPriority(.required, for: .horizontal)
        containerView.addSubview(textLabel)
    }

    private func setupConstraints() {
        containerView.translatesAutoresizingMaskIntoConstraints = false
        brandingIconView.translatesAutoresizingMaskIntoConstraints = false
        textLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        let iconSize: CGFloat = 24
        let iconTextSpacing: CGFloat = 4

        // Branding icon
        NSLayoutConstraint.activate([
            brandingIconView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
            brandingIconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            brandingIconView.widthAnchor.constraint(equalToConstant: iconSize),
            brandingIconView.heightAnchor.constraint(equalToConstant: iconSize)
        ])

        NSLayoutConstraint.activate([
            textLabel.leadingAnchor.constraint(equalTo: brandingIconView.trailingAnchor, constant: iconTextSpacing),
            textLabel.centerYAnchor.constraint(equalTo: brandingIconView.centerYAnchor),
            textLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8)
        ])

        containerView.heightAnchor.constraint(equalToConstant: 44).isActive = true
    }
}
