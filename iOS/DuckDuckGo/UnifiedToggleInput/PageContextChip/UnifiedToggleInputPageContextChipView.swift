//
//  UnifiedToggleInputPageContextChipView.swift
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

import Combine
import DesignResourcesKit
import DesignResourcesKitIcons
import UIKit

final class UnifiedToggleInputPageContextChipView: UIControl {

    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private var cancellables = Set<AnyCancellable>()
    private var viewModel: UnifiedToggleInputPageContextChipViewModel?

    /// Called by the parent layout when the chip's visibility changes, so the
    /// surrounding stack can collapse/expand its height in sync.
    var onVisibilityChange: ((Bool) -> Void)?

    init() {
        super.init(frame: .zero)
        setupUI()
        addTarget(self, action: #selector(handleTap), for: .touchUpInside)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Binds the chip's tap target and visibility forwarding to the view-model.
    /// The chip retains the view-model so the parent doesn't need to.
    func bind(to viewModel: UnifiedToggleInputPageContextChipViewModel) {
        self.viewModel = viewModel
        viewModel.$isVisible
            .sink { [weak self] in self?.onVisibilityChange?($0) }
            .store(in: &cancellables)
    }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = UIColor(designSystemColor: .surface)
        layer.cornerRadius = 14
        layer.borderColor = UIColor(designSystemColor: .lines).cgColor
        layer.borderWidth = 1

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = DesignSystemImages.Glyphs.Size16.pageContentAttach
        iconView.tintColor = UIColor(designSystemColor: .icons)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = UserText.aiChatAttachPageContent
        titleLabel.font = .preferredFont(forTextStyle: .footnote)
        titleLabel.textColor = UIColor(designSystemColor: .textPrimary)

        addSubview(iconView)
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @objc private func handleTap() {
        viewModel?.tapped()
    }
}
