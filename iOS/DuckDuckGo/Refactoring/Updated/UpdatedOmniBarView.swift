//
//  UpdatedOmniBarView.swift
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
import SwiftUI

final class UpdatedOmniBarView: UIView, OmniBarView {
    var onTextEntered: (() -> Void)?
    var onVoiceSearchButtonPressed: (() -> Void)?
    var onAbortButtonPressed: (() -> Void)?
    var onClearButtonPressed: (() -> Void)?
    var onPrivacyIconPressed: (() -> Void)?
    var onMenuButtonPressed: (() -> Void)?
    var onTrackersViewPressed: (() -> Void)?
    var onSettingsButtonPressed: (() -> Void)?
    var onCancelPressed: (() -> Void)?
    var onRefreshPressed: (() -> Void)?
    var onBackPressed: (() -> Void)?
    var onForwardPressed: (() -> Void)?
    var onBookmarksPressed: (() -> Void)?
    var onAccessoryPressed: (() -> Void)?
    var onDismissPressed: (() -> Void)?
    var onSettingsLongPress: (() -> Void)?
    var onAccessoryLongPress: (() -> Void)?

    var text: String? {
        get { textField.text }
        set { textField.text = newValue }
    }

    var searchContainerView: UIView = UIView()
    var bookmarksButtonView: UIButton = UIButton()
    var accessoryButtonView: UIButton = UIButton()
    var menuButtonView: UIButton = UIButton()
    var privacyIconView: UIView?

    var backButtonMenu: UIMenu?

    var forwardButtonMenu: UIMenu?

    var searchContainerWidth: CGFloat { searchContainerView.frame.width }
    var progressView: ProgressView? { searchAreaView.progressView }
    var menuButtonContent: MenuButton = MenuButton()

    private let leadingButtonsContainer = UIStackView()
    private let trailingButtonsContainer = UIStackView()
    private let searchAlignmentContainer = UIView()

    private let searchAreaView = UpdatedOmniBarSearchView()
    private let searchAreaContainerView = UIView()
    private let shadowBackdropView = UIView()

    var textField: UITextField { searchAreaView.textField }

    private let leftImage = UIImageView()
    private let rightImage = UIImageView()

    private let stackView = UIStackView()

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
        addSubview(stackView)

        searchAreaContainerView.addSubview(shadowBackdropView)
        searchAreaContainerView.addSubview(searchAreaView)

        stackView.addArrangedSubview(leadingButtonsContainer)
        stackView.addArrangedSubview(searchAreaContainerView)
        stackView.addArrangedSubview(trailingButtonsContainer)
    }

    private func setUpConstraints() {

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),

            searchAreaView.heightAnchor.constraint(equalToConstant: 44),
            searchAreaView.leadingAnchor.constraint(equalTo: searchAreaContainerView.leadingAnchor, constant: 14),
            searchAreaView.trailingAnchor.constraint(equalTo: searchAreaContainerView.trailingAnchor, constant: -14),
            searchAreaView.topAnchor.constraint(equalTo: searchAreaContainerView.topAnchor, constant: 6),
            searchAreaView.bottomAnchor.constraint(equalTo: searchAreaContainerView.bottomAnchor, constant: -10),

            shadowBackdropView.leadingAnchor.constraint(equalTo: searchAreaView.leadingAnchor),
            shadowBackdropView.trailingAnchor.constraint(equalTo: searchAreaView.trailingAnchor),
            shadowBackdropView.topAnchor.constraint(equalTo: searchAreaView.topAnchor),
            shadowBackdropView.bottomAnchor.constraint(equalTo: searchAreaView.bottomAnchor)

        ])
    }

    private func setUpProperties() {
        leadingButtonsContainer.isHidden = true
        trailingButtonsContainer.isHidden = true

        setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .horizontal)

        backgroundColor = UIColor(designSystemColor: .background)

        searchAreaView.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        searchAreaView.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        searchAreaView.translatesAutoresizingMaskIntoConstraints = false

        shadowBackdropView.translatesAutoresizingMaskIntoConstraints = false
        shadowBackdropView.layer.shadowColor = UIColor(Color.shade(0.24)).cgColor
        shadowBackdropView.layer.shadowOffset = CGSize(width: 0, height: 2)
        shadowBackdropView.layer.shadowRadius = 4
        shadowBackdropView.layer.shadowOpacity = 1
        shadowBackdropView.layer.cornerRadius = searchAreaView.layer.cornerRadius
        shadowBackdropView.backgroundColor = .red

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.distribution = .fill
        stackView.backgroundColor = .clear

        rightImage.tintColor = UIColor(designSystemColor: .icons)
        leftImage.tintColor = UIColor(designSystemColor: .icons)

        leftImage.image = UIImage(resource: .searchLoupe)
        leftImage.setContentCompressionResistancePriority(.required, for: .horizontal)
        leftImage.setContentCompressionResistancePriority(.required, for: .vertical)

        rightImage.image = UIImage(resource: .aiChat24)
        rightImage.setContentCompressionResistancePriority(.required, for: .horizontal)
        rightImage.setContentCompressionResistancePriority(.required, for: .vertical)

        leftImage.contentMode = .scaleAspectFit
        rightImage.contentMode = .scaleAspectFit
    }

    private struct Metrics {
        static let buttonSize: CGFloat = 24
        static let height: CGFloat = 60
        static let textAreaHeight: CGFloat = 44
    }
}
