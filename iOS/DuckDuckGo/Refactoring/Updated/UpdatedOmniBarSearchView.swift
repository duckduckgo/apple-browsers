//
//  UpdatedOmniBarSearchView.swift
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

final class UpdatedOmniBarSearchView: UIView {

    private let leftIconView = UIImageView()

    private let leadingItemsContainer = UIStackView()

    let textField = UITextField()
    let progressView = ProgressView()

    private let trailingItemsContainer = UIStackView()
    private let contextActionButton = UIButton()
    private let auxiliaryActionButton = UIButton()

    private let mainStackView = UIStackView()

    init() {
        super.init(frame: .zero)

        setUpSubviews()
        setUpConstraints()
        setUpProperties()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setUpSubviews() {
        addSubview(mainStackView)

        mainStackView.addArrangedSubview(leadingItemsContainer)
        mainStackView.addArrangedSubview(textField)
        mainStackView.addArrangedSubview(trailingItemsContainer)

        trailingItemsContainer.addArrangedSubview(contextActionButton)
        trailingItemsContainer.addArrangedSubview(URLSeparatorView())
        trailingItemsContainer.addArrangedSubview(auxiliaryActionButton)

        leadingItemsContainer.addArrangedSubview(OmniBarItemView(leftIconView))

        addSubview(progressView)
    }

    private func setUpConstraints() {
        NSLayoutConstraint.activate([
            mainStackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            mainStackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            mainStackView.topAnchor.constraint(equalTo: topAnchor),
            mainStackView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contextActionButton.widthAnchor.constraint(equalTo: contextActionButton.heightAnchor),
            auxiliaryActionButton.widthAnchor.constraint(equalTo: auxiliaryActionButton.heightAnchor),

            progressView.bottomAnchor.constraint(equalTo: bottomAnchor),
            progressView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            progressView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            progressView.heightAnchor.constraint(equalToConstant: 2),
        ])
    }

    private func setUpProperties() {
        backgroundColor = UIColor(designSystemColor: .surface)
        layer.cornerRadius = Metrics.cornerRadius
        layer.cornerCurve = .circular
        clipsToBounds = true
        tintColor = UIColor(designSystemColor: .icons)

        textField.textAlignment = .left
        textField.contentVerticalAlignment = .center
        textField.font = UIFont.systemFont(ofSize: 16)
        textField.returnKeyType = .go
        textField.textColor = UIColor(designSystemColor: .textPrimary)

        mainStackView.translatesAutoresizingMaskIntoConstraints = false

        auxiliaryActionButton.setImage(UIImage(resource: .aiChat24), for: .normal)
        contextActionButton.setImage(UIImage(resource: .reload24), for: .normal)

        progressView.translatesAutoresizingMaskIntoConstraints = false

        leftIconView.image = UIImage(resource: .globe24)
        leftIconView.tintColor = tintColor
        leftIconView.contentMode = .scaleAspectFit
    }

    private struct Metrics {
        static let cornerRadius = 12.0

        static let buttonSize: CGFloat = 44
        static let height: CGFloat = 60
        static let textAreaHeight: CGFloat = 44
    }

}
