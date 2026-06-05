//
//  AIChatHistoryListViewController.swift
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
import Combine
import Core
import DesignResourcesKit
import DesignResourcesKitIcons
import SwiftUI
import UIKit
import PrivacyConfig

/// A view controller displaying the list of recent AI chats
final class AIChatHistoryListViewController: UIViewController {

    // MARK: - Constants

    private enum Constants {
        static let cellIdentifier = "AIChatHistoryCell"
        static let iconSize: CGFloat = 16
        static let iconTextSpacing: CGFloat = 12
        static let cellHeight: CGFloat = 44
        static let horizontalInset: CGFloat = 16
        static let topContentInset: CGFloat = -20
        // Use a tighter top padding when a section title sits below the hatch so they feel grouped;
        // use the wider padding when the hatch stands alone.
        static let escapeHatchTopPaddingNoTitle: CGFloat = 16
        static let escapeHatchTopPaddingWithTitle: CGFloat = 6
        static let escapeHatchHeaderHeight: CGFloat = 56
        static let escapeHatchBottomPadding: CGFloat = 16
        static let escapeHatchTopContentInset: CGFloat = 0
        static let escapeHatchMaxWidth: CGFloat = HomeMessageCollectionViewCell.maximumWidth
        static let escapeHatchMaxWidthPad: CGFloat = HomeMessageCollectionViewCell.maximumWidthPad
    }

    struct TitleLayoutConfiguration {
        var topPadding: CGFloat = 8
        var bottomPadding: CGFloat = 8
        var leadingInset: CGFloat = 24
        var trailingInset: CGFloat = -60
        var contentInsetWhenTitle: CGFloat = 0
        var resetContentOffsetOnTitleChange: Bool = false
        var tableLayoutMargins: UIEdgeInsets?

        static let `default` = TitleLayoutConfiguration()

        static let unifiedInput = TitleLayoutConfiguration(
            topPadding: 20,
            bottomPadding: 26,
            leadingInset: 18,
            trailingInset: -60,
            contentInsetWhenTitle: 0,
            resetContentOffsetOnTitleChange: true,
            tableLayoutMargins: UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        )
    }

    // MARK: - Properties

    var titleLayoutConfiguration = TitleLayoutConfiguration.default {
        didSet {
            if let margins = titleLayoutConfiguration.tableLayoutMargins {
                tableView.layoutMargins = margins
            }
        }
    }

    private let featureFlagger: FeatureFlagger
    private let viewModel: AIChatSuggestionsViewModel
    private let onChatSelected: (AIChatSuggestion) -> Void
    private let onChatDeleted: (AIChatSuggestion) -> Void
    private let isIPadExperience: Bool
    private var cancellables = Set<AnyCancellable>()

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.alwaysBounceVertical = true
        tableView.keyboardDismissMode = .onDrag
        tableView.register(DuckAISuggestionTableViewCell.self, forCellReuseIdentifier: Constants.cellIdentifier)
        tableView.backgroundColor = UIColor(designSystemColor: .background)
        tableView.separatorInset = UIEdgeInsets(top: 0, left: Constants.horizontalInset + Constants.iconSize + Constants.iconTextSpacing, bottom: 0, right: 0)
        tableView.sectionFooterHeight = 0
        tableView.contentInset = UIEdgeInsets(top: Constants.topContentInset, left: 0, bottom: 0, right: 0)
        return tableView
    }()

    private var chats: [AIChatSuggestion] {
        viewModel.filteredSuggestions
    }

    private var currentEscapeHatchModel: EscapeHatchModel?
    private var escapeHatchHostingController: UIHostingController<EscapeHatchView>?

    var additionalTopInset: CGFloat = 0 {
        didSet {
            guard additionalTopInset != oldValue else { return }
            updateTableHeader()
        }
    }

    private(set) var sectionTitle: String? {
        didSet {
            guard sectionTitle != oldValue else { return }
            updateTableHeader()
        }
    }

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.daxTitle3()
        label.textColor = UIColor(designSystemColor: .textPrimary)
        return label
    }()

    // MARK: - Initialization

    init(viewModel: AIChatSuggestionsViewModel,
         isIPadExperience: Bool,
         onChatSelected: @escaping (AIChatSuggestion) -> Void,
         onChatDeleted: @escaping (AIChatSuggestion) -> Void,
         featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger)
    {
        self.viewModel = viewModel
        self.isIPadExperience = isIPadExperience
        self.onChatSelected = onChatSelected
        self.onChatDeleted = onChatDeleted
        self.featureFlagger = featureFlagger
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        subscribeToViewModel()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        /// Dismiss FireConfirmation if present. On iPad this ViewController is dismissed upon rotation
        presentedViewController?.dismiss(animated: true)
    }

    // MARK: - Private Methods

    private func setupView() {
        view.backgroundColor = UIColor(designSystemColor: .background)
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        ])
    }

    private func subscribeToViewModel() {
        viewModel.$filteredSuggestions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.tableView.reloadData()
            }
            .store(in: &cancellables)
    }

    func setScrollableTitle(_ title: String?) {
        sectionTitle = title
    }

    private func updateTableHeader() {
        let hasTitleContent = !(sectionTitle?.isEmpty ?? true)
        let hasEscapeHatch = escapeHatchHostingController != nil

        guard hasTitleContent || hasEscapeHatch else {
            UIView.performWithoutAnimation {
                tableView.tableHeaderView = nil
                tableView.contentInset = UIEdgeInsets(top: Constants.topContentInset, left: 0, bottom: 0, right: 0)
            }
            return
        }

        let container = UIView()
        container.backgroundColor = UIColor(designSystemColor: .background)
        var totalHeight: CGFloat = additionalTopInset

        if hasEscapeHatch, let hosting = escapeHatchHostingController {
            hosting.view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(hosting.view)

            let maxWidth = isIPadExperience ? Constants.escapeHatchMaxWidthPad : Constants.escapeHatchMaxWidth
            let preferredWidth = hosting.view.widthAnchor.constraint(equalToConstant: maxWidth)
            preferredWidth.priority = .defaultHigh

            let minimumLeading = hosting.view.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: Constants.horizontalInset)
            minimumLeading.priority = .required - 1

            let minimumTrailing = hosting.view.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -Constants.horizontalInset)
            minimumTrailing.priority = .required - 1

            let escapeHatchTopPadding = hasTitleContent ? Constants.escapeHatchTopPaddingWithTitle : Constants.escapeHatchTopPaddingNoTitle
            let topOffset = totalHeight + escapeHatchTopPadding
            NSLayoutConstraint.activate([
                hosting.view.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                hosting.view.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth),
                preferredWidth,
                minimumLeading,
                minimumTrailing,
                hosting.view.topAnchor.constraint(equalTo: container.topAnchor, constant: topOffset),
                hosting.view.heightAnchor.constraint(equalToConstant: Constants.escapeHatchHeaderHeight),
            ])

            totalHeight += escapeHatchTopPadding + Constants.escapeHatchHeaderHeight + Constants.escapeHatchBottomPadding
        }

        if hasTitleContent {
            let config = titleLayoutConfiguration
            titleLabel.text = sectionTitle
            container.addSubview(titleLabel)
            NSLayoutConstraint.activate([
                titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: totalHeight + config.topPadding),
                titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: config.leadingInset),
                titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: config.trailingInset),
            ])
            let titleHeight = titleLabel.font.lineHeight
            totalHeight += config.topPadding + ceil(titleHeight) + config.bottomPadding
        }

        let width = tableView.bounds.width > 0 ? tableView.bounds.width : view.bounds.width
        container.frame = CGRect(x: 0, y: 0, width: width, height: totalHeight)
        let config = titleLayoutConfiguration
        let topInset: CGFloat = hasEscapeHatch ? Constants.escapeHatchTopContentInset : config.contentInsetWhenTitle
        UIView.performWithoutAnimation {
            tableView.tableHeaderView = container
            tableView.contentInset = UIEdgeInsets(top: topInset, left: 0, bottom: 0, right: 0)
            if config.resetContentOffsetOnTitleChange {
                tableView.layoutIfNeeded()
                tableView.contentOffset = CGPoint(x: 0, y: -tableView.adjustedContentInset.top)
            }
        }
    }

    /// Shows or hides the escape hatch (return-to-tab card + tab switcher pill) as the table header. Pass nil to hide.
    /// The pill's open-tab count is sourced from the model (it self-subscribes to the target mode's tabs publisher),
    /// so this method only needs to swap when the model changes.
    func setEscapeHatch(_ model: EscapeHatchModel?) {
        let modelChanged = model != currentEscapeHatchModel
        currentEscapeHatchModel = model

        if let model {
            if escapeHatchHostingController != nil, !modelChanged {
                return
            }
            if let existingHosting = escapeHatchHostingController {
                existingHosting.willMove(toParent: nil)
                existingHosting.view.removeFromSuperview()
                existingHosting.removeFromParent()
            }
            escapeHatchHostingController = nil

            let view = EscapeHatchView(model: model)
            let hosting = UIHostingController(rootView: view)
            hosting.view.backgroundColor = .clear
            escapeHatchHostingController = hosting

            addChild(hosting)
            updateTableHeader()
            hosting.didMove(toParent: self)
        } else {
            if let hosting = escapeHatchHostingController {
                hosting.willMove(toParent: nil)
                hosting.view.removeFromSuperview()
                hosting.removeFromParent()
            }
            escapeHatchHostingController = nil
            updateTableHeader()
        }
    }

    private func configureCell(_ cell: UITableViewCell, with chat: AIChatSuggestion) {
        var config = cell.defaultContentConfiguration()

        config.text = chat.title
        config.textProperties.font = UIFont.preferredFont(forTextStyle: .body)
        config.textProperties.color = UIColor(designSystemColor: .textPrimary)
        config.textProperties.lineBreakMode = .byTruncatingTail
        config.textProperties.numberOfLines = 1

        let icon = chat.isPinned ? DesignSystemImages.Glyphs.Size24.pin : DesignSystemImages.Glyphs.Size24.chat
        config.image = icon.withRenderingMode(.alwaysTemplate)
        config.imageProperties.tintColor = UIColor(designSystemColor: .icons)
        config.imageProperties.maximumSize = CGSize(width: Constants.iconSize, height: Constants.iconSize)

        config.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 0,
            leading: Constants.horizontalInset,
            bottom: 0,
            trailing: Constants.horizontalInset
        )
        config.imageToTextPadding = Constants.iconTextSpacing

        cell.contentConfiguration = config
        cell.backgroundColor = UIColor(designSystemColor: .surface)

        configureDeleteActionIfNeeded(cell: cell, chat: chat)
    }
}

// MARK: - Chat Deletion

private extension AIChatHistoryListViewController {

    func configureDeleteActionIfNeeded(cell: UITableViewCell, chat: AIChatSuggestion) {
        guard let cell = cell as? DuckAISuggestionTableViewCell else {
            return
        }

        cell.accessoryButtonImage = DesignSystemImages.Glyphs.Size16.fire
        cell.displaysAccessoryButton = featureFlagger.isFeatureOn(.removeChatHistory)
        cell.onAccessoryButtonPressed = { [weak self] source in
            self?.presentChatDeletionConfirmation(chat: chat, source: source)
        }
    }

    func presentChatDeletionConfirmation(chat: AIChatSuggestion, source: UIView) {
        DailyPixel.fireDailyAndCount(pixel: .aiChatRecentChatDeleteButtonTapped)

        FireConfirmationPresenter.presentFireConfirmation(suggestion: chat, presenter: self, source: source) {
            DailyPixel.fireDailyAndCount(pixel: .aiChatRecentChatDeleteCancelled)

        } onConfirm: { [weak self] in
            self?.onChatDeleted(chat)
            DailyPixel.fireDailyAndCount(pixel: .aiChatRecentChatDeleteConfirmed)
        }
    }
}

// MARK: - UITableViewDataSource

extension AIChatHistoryListViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        return chats.isEmpty ? 0 : 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return chats.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Constants.cellIdentifier, for: indexPath)

        guard indexPath.row < chats.count else { return cell }

        let chat = chats[indexPath.row]
        configureCell(cell, with: chat)

        return cell
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return nil
    }
}

// MARK: - UITableViewDelegate

extension AIChatHistoryListViewController: UITableViewDelegate {

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        view.window?.endEditing(true)
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        guard indexPath.row < chats.count else { return }

        let chat = chats[indexPath.row]
        let pixel: Pixel.Event = chat.isPinned ? .aiChatRecentChatSelectedPinned : .aiChatRecentChatSelected
        DailyPixel.fireDailyAndCount(pixel: pixel)

        if isIPadExperience {
            let iPadPixel: Pixel.Event = chat.isPinned ? .aiChatIPadToggleRecentChatSelectedPinned : .aiChatIPadToggleRecentChatSelected
            DailyPixel.fireDailyAndCount(pixel: iPadPixel)
        }

        onChatSelected(chat)
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return Constants.cellHeight
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 0
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return 0
    }
}
