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

    private let stackView = UIStackView()
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

        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 4
        addSubview(stackView)

        brandingIconView.contentMode = .scaleAspectFit
        brandingIconView.image = DesignSystemImages.Color.Size24.aiChatGradient
        stackView.addArrangedSubview(brandingIconView)

        textLabel.text = UserText.omnibarFullAIChatModeDisplayTitle
        textLabel.font = UIFont.daxBodyRegular()
        textLabel.textColor = UIColor(designSystemColor: .textPrimary)
        stackView.addArrangedSubview(textLabel)
    }

    private func setupConstraints() {
        stackView.translatesAutoresizingMaskIntoConstraints = false
        brandingIconView.translatesAutoresizingMaskIntoConstraints = false

        let iconSize: CGFloat = 24

        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),

            brandingIconView.widthAnchor.constraint(equalToConstant: iconSize),
            brandingIconView.heightAnchor.constraint(equalToConstant: iconSize),

            heightAnchor.constraint(equalToConstant: 44)
        ])
    }
}
