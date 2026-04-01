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
        static let escapeHatchTopPadding: CGFloat = 16
        static let escapeHatchHeaderHeight: CGFloat = 72
        static let escapeHatchBottomPadding: CGFloat = 16
        static let escapeHatchTopContentInset: CGFloat = 8
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

    private let viewModel: AIChatSuggestionsViewModel
    private let onChatSelected: (AIChatSuggestion) -> Void
    private let isIPadExperience: Bool
    private var cancellables = Set<AnyCancellable>()

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.alwaysBounceVertical = true
        tableView.keyboardDismissMode = .onDrag
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Constants.cellIdentifier)
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
    private var escapeHatchHostingController: UIHostingController<ReturnToTabCard>?

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
         onChatSelected: @escaping (AIChatSuggestion) -> Void) {
        self.viewModel = viewModel
        self.isIPadExperience = isIPadExperience
        self.onChatSelected = onChatSelected
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
                guard let self else { return }
                self.tableView.reloadData()
                self.updateScrollEnabled()
            }
            .store(in: &cancellables)
    }

    private func updateScrollEnabled() {
        tableView.isScrollEnabled = !chats.isEmpty
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
        var totalHeight: CGFloat = 0

        if hasTitleContent {
            let config = titleLayoutConfiguration
            titleLabel.text = sectionTitle
            container.addSubview(titleLabel)
            NSLayoutConstraint.activate([
                titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: config.topPadding),
                titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: config.leadingInset),
                titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: config.trailingInset),
            ])
            let titleHeight = titleLabel.font.lineHeight
            totalHeight += config.topPadding + ceil(titleHeight) + config.bottomPadding
        }

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

            let topOffset = totalHeight + Constants.escapeHatchTopPadding
            NSLayoutConstraint.activate([
                hosting.view.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                hosting.view.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth),
                preferredWidth,
                minimumLeading,
                minimumTrailing,
                hosting.view.topAnchor.constraint(equalTo: container.topAnchor, constant: topOffset),
                hosting.view.heightAnchor.constraint(equalToConstant: Constants.escapeHatchHeaderHeight),
            ])

            totalHeight += Constants.escapeHatchTopPadding + Constants.escapeHatchHeaderHeight + Constants.escapeHatchBottomPadding
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

    /// Shows or hides the escape hatch (Return to tab card) as the table header. Pass nil to hide.
    func setEscapeHatch(_ model: EscapeHatchModel?, onTapped: (() -> Void)?) {
        if model == currentEscapeHatchModel {
            return
        }
        currentEscapeHatchModel = model

        if let model, let onTapped {
            if let existingHosting = escapeHatchHostingController {
                existingHosting.willMove(toParent: nil)
                existingHosting.view.removeFromSuperview()
                existingHosting.removeFromParent()
            }
            escapeHatchHostingController = nil

            let card = ReturnToTabCard(model: model, onTap: onTapped)
            let hosting = UIHostingController(rootView: card)
            hosting.view.backgroundColor = .clear
            escapeHatchHostingController = hosting

            addChild(hosting)
            updateTableHeader()
            hosting.didMove(toParent: self)
            updateScrollEnabled()
        } else {
            if let hosting = escapeHatchHostingController {
                hosting.willMove(toParent: nil)
                hosting.view.removeFromSuperview()
                hosting.removeFromParent()
            }
            escapeHatchHostingController = nil
            updateTableHeader()
            updateScrollEnabled()
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
