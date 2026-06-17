//
//  AIChatRecentChatsPopupViewController.swift
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

import AIChat
import DesignResourcesKit
import DesignResourcesKitIcons
import MetricBuilder
import UIKit

// MARK: - AIChatRecentChatsPopupViewController

final class AIChatRecentChatsPopupViewController: UIViewController {

    // MARK: - Constants

    private enum Constants {
        static let shadowOffsetY: CGFloat = 8
        static let shadowRadius: CGFloat = 20
        static let shadowOpacity: Float = 1.0
        static let horizontalPadding: CGFloat = 16
        static let verticalPadding: CGFloat = 10
        static let sectionHeaderTopPadding: CGFloat = 4
        static let sectionHeaderBottomPadding: CGFloat = 10
        static let sectionHeaderLeading: CGFloat = 8
        static let cellIconSize: CGFloat = 20
        /// The `chats` glyph has a 24pt artboard (vs the 20pt single-`chat` glyph), so it needs a
        /// larger frame to render at the same optical size as the other rows' icons.
        static let viewAllChatsIconSize: CGFloat = 24
        static let cellIconGap: CGFloat = 8
        static let cellVerticalPadding: CGFloat = 10
        static let cellLeadingPadding: CGFloat = 6
        static let separatorHorizontalInset: CGFloat = 8
        static let separatorContainerHeight: CGFloat = 21
        static let popupWidth: CGFloat = 270
        static let popupLeadingOffset: CGFloat = 16
    }

    // MARK: - Properties

    private let viewModel: AIChatRecentChatsPopupViewModel

    // MARK: - UI Components

    /// Shadow container — not clipped so shadow is visible
    private lazy var shadowContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.shadowColor = UIColor(designSystemColor: .shadowTertiary).cgColor
        view.layer.shadowOffset = CGSize(width: 0, height: Constants.shadowOffsetY)
        view.layer.shadowRadius = Constants.shadowRadius
        view.layer.shadowOpacity = Constants.shadowOpacity
        return view
    }()

    /// Clipping container for corner radius and background
    private lazy var contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = ContainerMetrics.cornerRadius
        view.layer.masksToBounds = true
        return view
    }()

    private lazy var blurView: UIVisualEffectView = {
        let blur = UIBlurEffect(style: .systemUltraThinMaterial)
        let effectView = UIVisualEffectView(effect: blur)
        effectView.translatesAutoresizingMaskIntoConstraints = false
        return effectView
    }()

    private lazy var stackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    // MARK: - Initialization

    init(viewModel: AIChatRecentChatsPopupViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        shadowContainer.layer.shadowPath = UIBezierPath(
            roundedRect: shadowContainer.bounds,
            cornerRadius: ContainerMetrics.cornerRadius
        ).cgPath
    }

    // MARK: - Public

    /// Anchors the popup card overlapping the header pill using screen coordinates.
    func anchorContentView(pillFrame: CGRect) {
        let cardTop = pillFrame.minY - ContainerMetrics.cornerRadius
        let cardLeading = pillFrame.minX + Constants.popupLeadingOffset

        let desiredTop = shadowContainer.topAnchor.constraint(equalTo: view.topAnchor, constant: cardTop)
        desiredTop.priority = .defaultHigh

        NSLayoutConstraint.activate([
            desiredTop,
            shadowContainer.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor),
            shadowContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: cardLeading),
            shadowContainer.widthAnchor.constraint(equalToConstant: Constants.popupWidth),
        ])
    }
}

// MARK: - Private

private extension AIChatRecentChatsPopupViewController {

    func setupUI() {
        view.backgroundColor = UIColor.black.withAlphaComponent(0.1)

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped))
        tapGesture.delegate = self
        view.addGestureRecognizer(tapGesture)

        view.addSubview(shadowContainer)
        shadowContainer.addSubview(contentView)
        contentView.addSubview(blurView)
        contentView.addSubview(stackView)

        buildContent()

        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: shadowContainer.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: shadowContainer.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: shadowContainer.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: shadowContainer.bottomAnchor),

            blurView.topAnchor.constraint(equalTo: contentView.topAnchor),
            blurView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Constants.verticalPadding),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.horizontalPadding),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.horizontalPadding),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Constants.verticalPadding),
        ])
    }

    func buildContent() {
        if viewModel.showNewChat {
            let newChatRow = makeNewChatRow()
            stackView.addArrangedSubview(newChatRow)

            if !viewModel.suggestions.isEmpty {
                let separator = makeSeparator()
                stackView.addArrangedSubview(separator)
            }
        }

        if !viewModel.suggestions.isEmpty {
            let headerLabel = makeSectionHeader(UserText.aiChatRecentChatsSectionTitle)
            stackView.addArrangedSubview(headerLabel)

            for (index, suggestion) in viewModel.suggestions.enumerated() {
                let row = makeChatRow(for: suggestion, index: index)
                stackView.addArrangedSubview(row)
            }

            let separatorContainer = makeSeparator()
            stackView.addArrangedSubview(separatorContainer)
        }

        let footer = makeViewAllChatsRow()
        stackView.addArrangedSubview(footer)
    }

    // MARK: - Row Builders

    func makeSectionHeader(_ title: String) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = title
        label.font = .daxFootnoteSemibold()
        label.textColor = UIColor(designSystemColor: .textTertiary)
        label.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: Constants.sectionHeaderTopPadding),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Constants.sectionHeaderLeading),
            label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Constants.sectionHeaderBottomPadding),
        ])

        return container
    }

    func makeChatRow(for suggestion: AIChatSuggestion, index: Int) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.tag = index

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(chatRowTapped(_:)))
        container.addGestureRecognizer(tapGesture)

        let iconView = UIImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = UIColor(designSystemColor: .icons)
        iconView.image = (suggestion.isPinned
            ? DesignSystemImages.Glyphs.Size24.pin
            : DesignSystemImages.Glyphs.Size24.chat).withRenderingMode(.alwaysTemplate)

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = suggestion.title
        titleLabel.font = .daxBodyRegular()
        titleLabel.textColor = UIColor(designSystemColor: .textPrimary)
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping

        container.addSubview(iconView)
        container.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Constants.cellLeadingPadding),
            iconView.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: Constants.cellIconSize),
            iconView.heightAnchor.constraint(equalToConstant: Constants.cellIconSize),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: Constants.cellIconGap),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: Constants.cellVerticalPadding),
            titleLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Constants.cellVerticalPadding),

            container.heightAnchor.constraint(greaterThanOrEqualToConstant: Constants.cellIconSize + Constants.cellVerticalPadding * 2),
        ])

        return container
    }

    func makeSeparator() -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = .separator

        container.addSubview(separator)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: Constants.separatorContainerHeight),
            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Constants.separatorHorizontalInset),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Constants.separatorHorizontalInset),
            separator.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
        ])

        return container
    }

    func makeViewAllChatsRow() -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(viewAllChatsTapped))
        container.addGestureRecognizer(tapGesture)

        let iconView = UIImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = UIColor(designSystemColor: .icons)
        iconView.image = DesignSystemImages.Glyphs.Size24.chats.withRenderingMode(.alwaysTemplate)

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = UserText.aiChatViewAllChats
        titleLabel.font = .daxBodyRegular()
        titleLabel.textColor = UIColor(designSystemColor: .textPrimary)

        container.addSubview(iconView)
        container.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Constants.cellLeadingPadding),
            iconView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: Constants.viewAllChatsIconSize),
            iconView.heightAnchor.constraint(equalToConstant: Constants.viewAllChatsIconSize),

            // Keep the title aligned with the other rows despite the wider icon frame.
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor,
                                                constant: Constants.cellLeadingPadding + Constants.cellIconSize + Constants.cellIconGap),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            container.heightAnchor.constraint(equalToConstant: Constants.cellIconSize + Constants.cellVerticalPadding * 2),
        ])

        return container
    }

    func makeNewChatRow() -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(newChatTapped))
        container.addGestureRecognizer(tapGesture)

        let iconView = UIImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = UIColor(designSystemColor: .icons)
        iconView.image = DesignSystemImages.Glyphs.Size24.compose.withRenderingMode(.alwaysTemplate)

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = UserText.actionNewAIChat
        titleLabel.font = .daxBodyRegular()
        titleLabel.textColor = UIColor(designSystemColor: .textPrimary)

        container.addSubview(iconView)
        container.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Constants.cellLeadingPadding),
            iconView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: Constants.cellIconSize),
            iconView.heightAnchor.constraint(equalToConstant: Constants.cellIconSize),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: Constants.cellIconGap),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            container.heightAnchor.constraint(equalToConstant: Constants.cellIconSize + Constants.cellVerticalPadding * 2),
        ])

        return container
    }

    // MARK: - Actions

    @objc func backgroundTapped() {
        viewModel.didDismiss()
    }

    @objc func newChatTapped() {
        viewModel.didSelectNewChat()
    }

    @objc func chatRowTapped(_ gesture: UITapGestureRecognizer) {
        guard let view = gesture.view else { return }
        viewModel.didSelectChat(at: view.tag)
    }

    @objc func viewAllChatsTapped() {
        viewModel.didSelectViewAll()
    }
}

// MARK: - UIGestureRecognizerDelegate

extension AIChatRecentChatsPopupViewController: UIGestureRecognizerDelegate {

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Only dismiss when tapping outside the content view
        let location = touch.location(in: contentView)
        return !contentView.bounds.contains(location)
    }
}
