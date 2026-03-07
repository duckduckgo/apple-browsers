//
//  UnifiedInputTopHeaderView.swift
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

final class UnifiedInputTopHeaderView: UIView {

    enum TitleLayoutPosition {
        case topBarSection
        case bottomBarHeader
    }

    var onDismissTapped: (() -> Void)?

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.daxTitle3()
        label.textAlignment = .left
        label.textColor = UIColor(designSystemColor: .textPrimary)
        return label
    }()
    private var titleTopConstraint: NSLayoutConstraint!
    private var titleTrailingToDismissConstraint: NSLayoutConstraint!
    private var titleTrailingToContainerConstraint: NSLayoutConstraint!

    private lazy var dismissButton: UIButton = {
        #if compiler(>=6.2)
        if #available(iOS 26, *) {
            var config = UIButton.Configuration.glass()
            config.image = UIImage(systemName: "xmark")
            config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            let button = UIButton(configuration: config)
            button.translatesAutoresizingMaskIntoConstraints = false
            return button
        }
        #endif
        return makePreiOS26DismissButton()
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(designSystemColor: .panel)
        setupLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String?) {
        titleLabel.text = title
        titleLabel.isHidden = title?.isEmpty != false
    }

    func setDismissButtonHidden(_ hidden: Bool) {
        dismissButton.isHidden = hidden
    }

    func setTitleLayoutPosition(_ position: TitleLayoutPosition) {
        switch position {
        case .topBarSection:
            titleTopConstraint.constant = 24
            titleTrailingToDismissConstraint.isActive = false
            titleTrailingToContainerConstraint.isActive = true
        case .bottomBarHeader:
            titleTopConstraint.constant = 16
            titleTrailingToContainerConstraint.isActive = false
            titleTrailingToDismissConstraint.isActive = true
        }
    }

    private func setupLayout() {
        addSubview(titleLabel)
        addSubview(dismissButton)

        dismissButton.addTarget(self, action: #selector(handleDismissTap), for: .primaryActionTriggered)

        titleTopConstraint = titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 16)
        titleTrailingToDismissConstraint = titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: dismissButton.leadingAnchor, constant: -8)
        titleTrailingToContainerConstraint = titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24)

        NSLayoutConstraint.activate([
            titleTopConstraint,
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            titleTrailingToDismissConstraint,
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -8),

            dismissButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            dismissButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            dismissButton.widthAnchor.constraint(equalToConstant: 44),
            dismissButton.heightAnchor.constraint(equalToConstant: 44),
        ])

        titleTrailingToContainerConstraint.isActive = false
    }

    @objc private func handleDismissTap() {
        onDismissTapped?()
    }

    private func makePreiOS26DismissButton() -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        let image = UIImage(systemName: "xmark")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 12, weight: .medium))
        button.setImage(image, for: .normal)
        button.tintColor = UIColor(designSystemColor: .textPrimary)
        button.backgroundColor = UIColor(designSystemColor: .surface)
        button.layer.cornerRadius = 22
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.1
        button.layer.shadowRadius = 4
        button.layer.shadowOffset = CGSize(width: 0, height: 2)
        return button
    }
}
